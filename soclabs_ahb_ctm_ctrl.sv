//-----------------------------------------------------------------------------
// SoC Labs AHB Control Wrapper for Convolutional Tsetlin Machine (CTM)
// + AES-128 accelerator, as 4 memory-mapped regions: image / clause /
// weight / aes, following the professor's spec of "4 memories".
// Wraps class_top (image classifier accelerator) and aes_core (Secworks
// AES-128/256) as AHB-Lite memory-mapped peripherals, following the
// soclabs_ahb_aes128_ctrl.v pattern and reusing the generic wrapper_*.sv
// packet constructor library for the wide programming buses.
//
// Modelled on:
//   - soclabs_ahb_aes128_ctrl.v   (SoC Labs, D. Flynn)
//   - wrapper_packet_construct.sv (SoC Labs, D. Mapstone)
//   - aes.v                       (Secworks, J. Strombergson) - register
//                                  map style (KEY/BLOCK/RESULT/CTRL/STATUS)
//                                  reused here, re-expressed for AHB rather
//                                  than aes.v's own 8-bit cs/we/address bus.
//
// NOTE ON class_top's internal handshake:
//   class_top does NOT expose a request/ready handshake for clause_write /
//   weight_write. Internally it free-runs bram_addr_a / bram_addr_a2 counters
//   and samples clause_write / weight_write directly whenever
//   wea = (bram_addr_a < clauses) / wea2 = (bram_addr_a2 < weight_limit) is
//   true (see top.v). This means:
//     - clause_write / weight_write must be held STABLE for the whole cycle
//       in which class_top consumes them, and class_top consumes a new word
//       every clock while loading (it does not wait for software).
//     - packet_data_ready is therefore tied high; there is no backpressure
//       into the constructor. Software MUST pace writes by polling
//       bram_addr_a / bram_addr_a2 (exposed read-only below) rather than
//       relying on any wready stall, to avoid overrunning class_top's
//       expected load sequence.
//   This is a real constraint of the wrapped core, not a wrapper limitation;
//   flagged explicitly rather than silently working around it.
//
// NOTE ON AES-128 region (region 4) - functional relationship to the TM:
//   As currently wired, AES is a STANDALONE 4th memory region: software
//   writes KEY/BLOCK, pulses INIT/NEXT, reads RESULT - entirely independent
//   of the image/clause/weight regions. No ciphertext/plaintext flows
//   automatically between AES and class_top. If the intent is for AES to
//   encrypt/decrypt data before it reaches the TM (e.g. protecting clause
//   or weight data at rest), that requires an explicit data-path connection
//   between the AES result/block registers and the clause_write/weight_write
//   packet path, which is NOT implemented here - flagged for the same reason
//   as the class_top notes above: this is a real design decision, not
//   something to silently assume.
//-----------------------------------------------------------------------------

module soclabs_ahb_ctm_ctrl #(
  parameter HEIGHT       = 28,
  parameter WIDTH        = 28,
  parameter CLAUSEN      = 140,
  parameter CLASSN       = 10
) (
  // -------------------------------------------------------
  // MCU interface (AHB-Lite slave)
  // -------------------------------------------------------
  input  wire        ahb_hclk,
  input  wire        ahb_hresetn,
  input  wire        ahb_hsel,
  input  wire [15:0] ahb_haddr16,
  input  wire  [1:0] ahb_htrans,
  input  wire  [2:0] ahb_hsize,
  input  wire  [3:0] ahb_hprot,
  input  wire        ahb_hwrite,
  input  wire        ahb_hready,
  input  wire [31:0] ahb_hwdata,
  output wire        ahb_hreadyout,
  output wire [31:0] ahb_hrdata,
  output wire        ahb_hresp,

  // stream data requests (mirrors soclabs_ahb_aes128_ctrl style; unused
  // DMA channels tied off for CTM since load is core-paced, not DMA-paced)
  output wire        drq_clausebuf,
  output wire        drq_weightbuf,
  output wire        drq_imgbuf,
  output wire        drq_aesbuf,

  // interrupts
  output wire        irq_done,       // classification complete (tready pulse)
  output wire        irq_error,      // reserved (tied 0 - class_top has no error flag)
  output wire        irq_aes_done,   // aes_core result_valid pulse
  output wire        irq_merged
);

  //----------------------------------------------------------------
  // Address map - 4 memory regions: image / clause / weight / aes
  //----------------------------------------------------------------
  //  0x0000  CORE_NAME0        R    "ctm "
  //  0x0004  CORE_NAME1        R    "top "
  //  0x0008  CORE_VERSION      R    "0.01"
  //  0x0010  CTRL              R/W  [1:0] resetessen, [0]=start not used (class_top has no start pulse; kept reserved)
  //  0x0014  MODEL_PARAMS      R/W  [17:0] model_params (patch_size/stride/clause/classes)
  //  0x0018  X_W               R/W  [6:0]  x_w (chunk-load index)
  //  0x001C  STATUS            R    [0]=tready, [7:4]=output_params (class result)
  //  0x0020  LOAD_STATUS       R    [7:0]=bram_addr_a, [15:8]=bram_addr_a2 (SW polls these to pace loading)
  //
  //  Region 1 - IMAGE:
  //  0x1000  TDATA             W    32-bit image chunk (single address, re-sampled by core each cycle)
  //
  //  Region 2 - CLAUSE:
  //  0x2000  CLAUSE_WRITE      W    256-bit packet, 8x sequential 32-bit writes to this region (0x2000-0x201F)
  //
  //  Region 3 - WEIGHT:
  //  0x3000  WEIGHT_WRITE      W    256-bit packet, 8x sequential 32-bit writes to this region (0x3000-0x301F)
  //
  //  Region 4 - AES-128:
  //  0x4000-0x401F  AES_KEY    W    256-bit packet, 8x sequential 32-bit writes.
  //                              IMPORTANT (confirmed by simulation): the packet
  //                              constructor places the LAST word WRITTEN into
  //                              the packet's MSBs, and the FIRST word written
  //                              into the LSBs - opposite of a naive top-down
  //                              reading of the address range. To load
  //                              key[255:0] = K255...K0, write K[31:0] to
  //                              0x4000 FIRST and K[255:224] to 0x401C LAST.
  //                              For AES-128 (keylen=0), aes_core uses
  //                              key[255:128] as the active 128-bit key, so
  //                              the actual key bytes must land in the last
  //                              4 words written (0x4010-0x401C), with the
  //                              first 4 words (0x4000-0x400C) don't-care.
  //  0x4020-0x402F  AES_BLOCK  W    128-bit packet, 4x sequential 32-bit writes,
  //                              same last-write-is-MSB ordering as AES_KEY:
  //                              write plaintext[31:0] to 0x4020 FIRST and
  //                              plaintext[127:96] to 0x402C LAST.
  //  0x4030         AES_CTRL   R/W  [0]=init (pulse, key expansion), [1]=next (pulse, block op), [2]=encdec (1=encrypt,0=decrypt), [3]=keylen (0=128,1=256)
  //  0x4034         AES_STATUS R    [0]=ready, [1]=result_valid
  //  0x4040-0x404F  AES_RESULT R    128-bit result, 4x sequential 32-bit reads
  //----------------------------------------------------------------

  localparam ADDR_CORE_NAME0   = 16'h0000;
  localparam ADDR_CORE_NAME1   = 16'h0004;
  localparam ADDR_CORE_VERSION = 16'h0008;
  localparam ADDR_CTRL         = 16'h0010;
  localparam ADDR_MODEL_PARAMS = 16'h0014;
  localparam ADDR_X_W          = 16'h0018;
  localparam ADDR_STATUS       = 16'h001c;
  localparam ADDR_LOAD_STATUS  = 16'h0020;

  localparam ADDR_TDATA_BASE   = 16'h1000;

  localparam ADDR_CLAUSE_BASE  = 16'h2000;
  localparam CLAUSE_ADDRWIDTH  = 5;  // 32 bytes = 8 words = 256 bits

  localparam ADDR_WEIGHT_BASE  = 16'h3000;
  localparam WEIGHT_ADDRWIDTH  = 5;

  localparam ADDR_AES_KEY_BASE   = 16'h4000;
  localparam AES_KEY_ADDRWIDTH   = 5;   // 32 bytes = 8 words = 256 bits
  localparam ADDR_AES_BLOCK_BASE = 16'h4020;
  localparam AES_BLOCK_ADDRWIDTH = 4;   // 16 bytes = 4 words = 128 bits
  localparam ADDR_AES_CTRL       = 16'h4030;
  localparam ADDR_AES_STATUS     = 16'h4034;
  localparam ADDR_AES_RESULT_BASE = 16'h4040;

  localparam CORE_NAME0   = 32'h63746d20; // "ctm "
  localparam CORE_NAME1   = 32'h746f7020; // "top "
  localparam CORE_VERSION = 32'h302e3031; // "0.01"

  //----------------------------------------------------------------
  // De-pipelined AHB access signals (reused pattern from
  // soclabs_ahb_aes128_ctrl.v byte-buffer front-end)
  //----------------------------------------------------------------
  reg  [15:0] addr16_r;
  reg         sel_r;
  reg         wcyc_r;
  reg         rcyc_r;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn) begin
      addr16_r <= 16'h0000;
      sel_r    <= 1'b0;
      wcyc_r   <= 1'b0;
      rcyc_r   <= 1'b0;
    end else if (ahb_hready) begin
      addr16_r <= (ahb_hsel & ahb_htrans[1]) ? ahb_haddr16 : addr16_r;
      sel_r    <= (ahb_hsel & ahb_htrans[1]);
      wcyc_r   <= (ahb_hsel & ahb_htrans[1]  &  ahb_hwrite);
      rcyc_r   <= (ahb_hsel & ahb_htrans[1]  & !ahb_hwrite);
    end

  wire sel_mode   = sel_r & (addr16_r[15:12] == 4'h0);
  wire sel_tdata  = sel_r & (addr16_r[15:12] == 4'h1);
  wire sel_clause = sel_r & (addr16_r[15:12] == 4'h2);
  wire sel_weight = sel_r & (addr16_r[15:12] == 4'h3);
  wire sel_aes    = sel_r & (addr16_r[15:12] == 4'h4);
  wire sel_aes_key   = sel_aes & (addr16_r[11:5] == 7'h0);              // 0x4000-0x401F
  wire sel_aes_block = sel_aes & (addr16_r[11:4] == ADDR_AES_BLOCK_BASE[11:4]); // 0x4020-0x402F
  wire sel_aes_ctrl   = sel_aes & (addr16_r == ADDR_AES_CTRL);
  wire sel_aes_status = sel_aes & (addr16_r == ADDR_AES_STATUS);
  wire sel_aes_result = sel_aes & (addr16_r[11:4] == ADDR_AES_RESULT_BASE[11:4]); // 0x4040-0x404F

  // ------------------------------------------------------------------
  // LIVE (combinational, address-phase-timed) region selects.
  //
  // BUG NOTE: wrapper_ahb_packet_constructor internally instantiates
  // wrapper_ahb_reg_interface, which does its OWN address-phase capture
  // (addr_reg <= haddrs on trans_req = hreadys & hsels & htranss[1]).
  // It expects hsels/haddrs/htranss to be the LIVE, un-registered AHB
  // signals (as driven directly by the bus master), not signals already
  // delayed by a cycle. Feeding it the registered addr16_r/sel_* (as the
  // first draft of this wrapper did for clause/weight) double-registers
  // the address phase and desyncs write_en from the data the constructor
  // actually latches - confirmed by simulation: an AES-128 KAT through
  // this path silently produced ciphertext of an all-zero key/block
  // instead of the real programmed key/plaintext. Packet constructors
  // MUST be fed the live signals below, not sel_r/addr16_r.
  // ------------------------------------------------------------------
  wire sel_clause_live = ahb_hsel & (ahb_haddr16[15:12] == 4'h2);
  wire sel_weight_live = ahb_hsel & (ahb_haddr16[15:12] == 4'h3);
  wire sel_aes_live      = ahb_hsel & (ahb_haddr16[15:12] == 4'h4);
  wire sel_aes_key_live   = sel_aes_live & (ahb_haddr16[11:5] == 7'h0);
  wire sel_aes_block_live = sel_aes_live & (ahb_haddr16[11:4] == ADDR_AES_BLOCK_BASE[11:4]);

  // zero-wait-state slave
  assign ahb_hreadyout = 1'b1;
  assign ahb_hresp     = 1'b0;

  //----------------------------------------------------------------
  // Simple mode registers: CTRL, MODEL_PARAMS, X_W
  //----------------------------------------------------------------
  reg [1:0]  resetessen_reg;
  reg [17:0] model_params_reg;
  reg [6:0]  x_w_reg;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn) begin
      resetessen_reg   <= 2'b00;
      model_params_reg <= 18'h0;
      x_w_reg           <= 7'h0;
    end else if (sel_mode & wcyc_r) begin
      case (addr16_r)
        ADDR_CTRL:         resetessen_reg   <= ahb_hwdata[1:0];
        ADDR_MODEL_PARAMS: model_params_reg <= ahb_hwdata[17:0];
        ADDR_X_W:          x_w_reg          <= ahb_hwdata[6:0];
        default: ;
      endcase
    end

  //----------------------------------------------------------------
  // TDATA: single-address 32-bit write-through register.
  // class_top samples tdata combinationally into total_memory each cycle
  // it is not stalled (!(img_rst || img_load_done || wea || wea2)), so this
  // is a plain register, not a packetizer - one AHB word in, one core word.
  //----------------------------------------------------------------
  reg [31:0] tdata_reg;
  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn)
      tdata_reg <= 32'h0;
    else if (sel_tdata & wcyc_r)
      tdata_reg <= ahb_hwdata;

  //----------------------------------------------------------------
  // CLAUSE_WRITE / WEIGHT_WRITE: 256-bit packet constructors
  // packet_data_ready tied high - class_top has no backpressure path, see
  // header note. Software paces itself via LOAD_STATUS (bram_addr_a/a2).
  //----------------------------------------------------------------
  wire [255:0] clause_packet_data;
  wire         clause_packet_last;
  wire         clause_packet_valid;
  wire         clause_constructor_ready;
  wire [31:0]  clause_rdata_unused;
  wire         clause_wready, clause_rready;

  wrapper_ahb_packet_constructor #(
    .ADDRWIDTH  (16),
    .PACKETWIDTH(256)
  ) u_clause_constructor (
    .hclk              (ahb_hclk),
    .hresetn            (ahb_hresetn),
    .hsels              (sel_clause_live),
    .haddrs             (ahb_haddr16),
    .htranss            (ahb_htrans),
    .hsizes             (ahb_hsize),
    .hwrites            (ahb_hwrite),
    .hreadys            (ahb_hready),
    .hwdatas            (ahb_hwdata),
    .hreadyouts         (),           // OR'd into top-level readyout below
    .hresps             (),
    .hrdatas            (clause_rdata_unused),
    .packet_data        (clause_packet_data),
    .packet_data_last   (clause_packet_last),
    .packet_data_valid  (clause_packet_valid),
    .packet_data_ready  (1'b1),
    .data_req           (drq_clausebuf)
  );

  wire [255:0] weight_packet_data;
  wire         weight_packet_last;
  wire         weight_packet_valid;
  wire [31:0]  weight_rdata_unused;

  wrapper_ahb_packet_constructor #(
    .ADDRWIDTH  (16),
    .PACKETWIDTH(256)
  ) u_weight_constructor (
    .hclk              (ahb_hclk),
    .hresetn            (ahb_hresetn),
    .hsels              (sel_weight_live),
    .haddrs             (ahb_haddr16),
    .htranss            (ahb_htrans),
    .hsizes             (ahb_hsize),
    .hwrites            (ahb_hwrite),
    .hreadys            (ahb_hready),
    .hwdatas            (ahb_hwdata),
    .hreadyouts         (),
    .hresps             (),
    .hrdatas            (weight_rdata_unused),
    .packet_data        (weight_packet_data),
    .packet_data_last   (weight_packet_last),
    .packet_data_valid  (weight_packet_valid),
    .packet_data_ready  (1'b1),
    .data_req           (drq_weightbuf)
  );

  // Hold last-assembled packet stable on the class_top inputs. class_top
  // re-samples every cycle it is actively loading (see header note), so a
  // simple hold register (not a FIFO) matches its expected behaviour.
  reg [255:0] clause_write_hold;
  reg [255:0] weight_write_hold;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn)
      clause_write_hold <= 256'h0;
    else if (clause_packet_valid)
      clause_write_hold <= clause_packet_data;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn)
      weight_write_hold <= 256'h0;
    else if (weight_packet_valid)
      weight_write_hold <= weight_packet_data;

  //----------------------------------------------------------------
  // AES-128 region (region 4): KEY (256b) and BLOCK (128b) packet
  // constructors, same pattern as clause/weight above. Unlike
  // clause_write/weight_write, aes_core DOES have a proper init/next/ready
  // handshake, so KEY and BLOCK are latched into simple hold registers on
  // packet completion and only pushed into aes_core when software pulses
  // AES_CTRL.init / AES_CTRL.next - no re-sampling-every-cycle concern here.
  //----------------------------------------------------------------
  wire [255:0] aes_key_packet_data;
  wire         aes_key_packet_last;
  wire         aes_key_packet_valid;
  wire [31:0]  aes_key_rdata_unused;

  wrapper_ahb_packet_constructor #(
    .ADDRWIDTH  (16),
    .PACKETWIDTH(256)
  ) u_aes_key_constructor (
    .hclk              (ahb_hclk),
    .hresetn            (ahb_hresetn),
    .hsels              (sel_aes_key_live),
    .haddrs             (ahb_haddr16),
    .htranss            (ahb_htrans),
    .hsizes             (ahb_hsize),
    .hwrites            (ahb_hwrite),
    .hreadys            (ahb_hready),
    .hwdatas            (ahb_hwdata),
    .hreadyouts         (),
    .hresps             (),
    .hrdatas            (aes_key_rdata_unused),
    .packet_data        (aes_key_packet_data),
    .packet_data_last   (aes_key_packet_last),
    .packet_data_valid  (aes_key_packet_valid),
    .packet_data_ready  (1'b1),
    .data_req           (drq_aesbuf)
  );

  // BLOCK is 128 bits, but wrapper_ahb_packet_constructor's internal counter
  // width is derived from PACKETWIDTH; instantiate with PACKETWIDTH=128
  // directly, matching aes_core's block port width one-for-one.
  wire [127:0] aes_block_packet_data;
  wire         aes_block_packet_last;
  wire         aes_block_packet_valid;
  wire [31:0]  aes_block_rdata_unused;

  wrapper_ahb_packet_constructor #(
    .ADDRWIDTH  (16),
    .PACKETWIDTH(128)
  ) u_aes_block_constructor (
    .hclk              (ahb_hclk),
    .hresetn            (ahb_hresetn),
    .hsels              (sel_aes_block_live),
    .haddrs             (ahb_haddr16),
    .htranss            (ahb_htrans),
    .hsizes             (ahb_hsize),
    .hwrites            (ahb_hwrite),
    .hreadys            (ahb_hready),
    .hwdatas            (ahb_hwdata),
    .hreadyouts         (),
    .hresps             (),
    .hrdatas            (aes_block_rdata_unused),
    .packet_data        (aes_block_packet_data),
    .packet_data_last   (aes_block_packet_last),
    .packet_data_valid  (aes_block_packet_valid),
    .packet_data_ready  (1'b1),
    .data_req           ()
  );

  reg [255:0] aes_key_hold;
  reg [127:0] aes_block_hold;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn)
      aes_key_hold <= 256'h0;
    else if (aes_key_packet_valid)
      aes_key_hold <= aes_key_packet_data;

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn)
      aes_block_hold <= 128'h0;
    else if (aes_block_packet_valid)
      aes_block_hold <= aes_block_packet_data;

  // AES_CTRL register: bit0=init (pulse), bit1=next (pulse), bit2=encdec,
  // bit3=keylen. init/next are self-clearing one-cycle pulses generated on
  // the write itself, matching aes_core's expected pulsed (not level)
  // init/next inputs - a level-held write would repeatedly re-trigger
  // key expansion / block processing every cycle HWDATA bit stayed high,
  // which is not what aes_core expects.
  reg aes_encdec_reg;
  reg aes_keylen_reg;
  wire aes_ctrl_write = sel_aes_ctrl & wcyc_r;
  wire aes_init_pulse  = aes_ctrl_write & ahb_hwdata[0];
  wire aes_next_pulse  = aes_ctrl_write & ahb_hwdata[1];

  always @(posedge ahb_hclk or negedge ahb_hresetn)
    if (!ahb_hresetn) begin
      aes_encdec_reg <= 1'b1; // default encrypt
      aes_keylen_reg <= 1'b0; // default AES-128
    end else if (aes_ctrl_write) begin
      aes_encdec_reg <= ahb_hwdata[2];
      aes_keylen_reg <= ahb_hwdata[3];
    end

  wire        aes_ready;
  wire [127:0] aes_result;
  wire        aes_result_valid;

  aes_core u_aes_core (
    .clk          (ahb_hclk),
    .reset_n      (ahb_hresetn),
    .encdec       (aes_encdec_reg),
    .init         (aes_init_pulse),
    .next         (aes_next_pulse),
    .ready        (aes_ready),
    .key          (aes_key_hold),
    .keylen       (aes_keylen_reg),
    .block        (aes_block_hold),
    .result       (aes_result),
    .result_valid (aes_result_valid)
  );

  assign irq_aes_done = aes_result_valid;

  //----------------------------------------------------------------
  // class_top instantiation
  //----------------------------------------------------------------
  wire [7:0] bram_addr_a;
  wire [7:0] bram_addr_a2;
  wire [3:0] output_params;
  wire       tready;

  class_top #(
    .CLAUSEN(CLAUSEN),
    .CLASSN (CLASSN),
    .HEIGHT (HEIGHT),
    .WIDTH  (WIDTH)
  ) u_class_top (
    .clk           (ahb_hclk),
    .i_rst_n       (ahb_hresetn),
    .init_done     (1'b1),              // tie high: no external init sequencing exposed by class_top
    .tdata         (tdata_reg),
    .model_params  (model_params_reg),
    .x_w           (x_w_reg),
    .clause_write  (clause_write_hold),
    .weight_write  (weight_write_hold),
    .resetessen    (resetessen_reg),
    .bram_addr_a   (bram_addr_a),
    .bram_addr_a2  (bram_addr_a2),
    .output_params (output_params),
    .tready        (tready)
  );

  //----------------------------------------------------------------
  // Interrupts: tready pulse -> irq_done. No error flag exposed by
  // class_top, so irq_error is tied off (reserved for future use).
  //----------------------------------------------------------------
  assign irq_done    = tready;
  assign irq_error   = 1'b0;
  assign irq_merged  = irq_done | irq_error | irq_aes_done;

  // Image-chunk load has no separate DMA request signal in class_top (it is
  // paced by software writing x_w), so drq_imgbuf is tied off. Included in
  // the port list for symmetry with the AES subsystem's DRQ pattern and to
  // leave room for a future streaming/DMA-paced version of class_top.
  assign drq_imgbuf = 1'b0;

  //----------------------------------------------------------------
  // Read decode
  //----------------------------------------------------------------
  reg [31:0] rdata32;
  always @* begin
    rdata32 = 32'h0;
    if (sel_r & rcyc_r) begin
      if (sel_aes_result) begin
        // 128-bit aes_result read back as 4x 32-bit words, MSW first at
        // ADDR_AES_RESULT_BASE. NOTE: this is independent of, and NOT the
        // same convention as, the write-side KEY/BLOCK packet assembly
        // below - confirmed via simulation that wrapper_packet_construct
        // assembles words such that the LAST word WRITTEN lands in the
        // packet's MSBs (opposite of a naive "first write = MSW" reading).
        // Software loading KEY/BLOCK must write the intended MSW LAST.
        // This read-side mux is hand-written independently and reads out
        // MSW-first at the lowest address, which is the more conventional
        // choice for a read-only result register - no reordering needed
        // here since this logic (unlike the packet constructor) was
        // written directly against aes_result, not assembled word-by-word.
        case (addr16_r[3:2])
          2'd0: rdata32 = aes_result[127:96];
          2'd1: rdata32 = aes_result[95:64];
          2'd2: rdata32 = aes_result[63:32];
          2'd3: rdata32 = aes_result[31:0];
        endcase
      end else begin
        case (addr16_r)
          ADDR_CORE_NAME0:   rdata32 = CORE_NAME0;
          ADDR_CORE_NAME1:   rdata32 = CORE_NAME1;
          ADDR_CORE_VERSION: rdata32 = CORE_VERSION;
          ADDR_CTRL:         rdata32 = {30'h0, resetessen_reg};
          ADDR_MODEL_PARAMS: rdata32 = {14'h0, model_params_reg};
          ADDR_X_W:          rdata32 = {25'h0, x_w_reg};
          ADDR_STATUS:       rdata32 = {24'h0, output_params, 3'h0, tready};
          ADDR_LOAD_STATUS:  rdata32 = {16'h0, bram_addr_a2, bram_addr_a};
          ADDR_AES_CTRL:     rdata32 = {28'h0, aes_keylen_reg, aes_encdec_reg, 2'b00};
          ADDR_AES_STATUS:   rdata32 = {30'h0, aes_result_valid, aes_ready};
          default: ;
        endcase
      end
    end
  end

  assign ahb_hrdata = rdata32;

endmodule
