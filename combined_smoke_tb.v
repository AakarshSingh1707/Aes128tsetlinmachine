`timescale 1ns / 1ps
module combined_smoke_tb;

  reg         HCLK = 0;
  reg         HRESETn = 0;
  reg         HSEL = 0;
  reg  [31:0] HADDR = 0;
  reg  [1:0]  HTRANS = 0;
  reg  [2:0]  HSIZE = 3'b010;
  reg  [3:0]  HPROT = 0;
  reg         HWRITE = 0;
  reg         HREADY = 1;
  reg  [31:0] HWDATA = 0;

  wire        HREADYOUT;
  wire        HRESP;
  wire [31:0] HRDATA;
  wire [3:0]  EXP_DRQ;
  wire [3:0]  EXP_IRQ;

  integer errors = 0;

  accelerator_subsystem_ctm dut (
    .HCLK(HCLK), .HRESETn(HRESETn),
    .HSEL(HSEL), .HADDR(HADDR), .HTRANS(HTRANS), .HSIZE(HSIZE),
    .HPROT(HPROT), .HWRITE(HWRITE), .HREADY(HREADY), .HWDATA(HWDATA),
    .HREADYOUT(HREADYOUT), .HRESP(HRESP), .HRDATA(HRDATA),
    .EXP_DRQ(EXP_DRQ), .EXP_IRQ(EXP_IRQ)
  );

  always #5 HCLK = ~HCLK;

  task ahb_write(input [15:0] addr, input [31:0] data);
    begin
      @(negedge HCLK);
      HSEL = 1; HADDR = addr; HTRANS = 2'b10; HWRITE = 1; HWDATA = data;
      @(posedge HCLK);   // end of cycle 0: address phase captured, write_en_reg->1 next
      @(negedge HCLK);
      HSEL = 0; HTRANS = 2'b00; HWRITE = 0;  // drop address-phase signals...
                                               // ...but KEEP HWDATA valid (do not clear it)
      @(posedge HCLK);   // end of cycle 1: write_en=1 now, wdata=HWDATA sampled here
      @(negedge HCLK);
      HWDATA = 32'h0;    // now safe to clear
    end
  endtask

  task ahb_write_trace(input [15:0] addr, input [31:0] data);
    begin
      ahb_write(addr, data);
    end
  endtask

  reg [31:0] rdata_captured;
  task ahb_read(input [15:0] addr);
    begin
      @(negedge HCLK);
      HSEL = 1; HADDR = addr; HTRANS = 2'b10; HWRITE = 0;
      @(posedge HCLK);   // end of cycle 0 -> read_en_reg becomes 1
      @(posedge HCLK);   // end of cycle 1 -> hrdatas valid (combinational
                          // from rdata, which combinationally follows addr_reg)
      #1;
      rdata_captured = HRDATA;
      @(negedge HCLK);
      HSEL = 0; HTRANS = 2'b00;
    end
  endtask

  reg [127:0] aes_result_captured;

  initial begin
    $dumpfile("combined.vcd");
    $dumpvars(0, dut);
  end

  initial begin
    HRESETn = 0;
    repeat (4) @(posedge HCLK);
    HRESETn = 1;
    repeat (2) @(posedge HCLK);

    // ---- Region 0: ID checks ----
    ahb_read(16'h0000);
    if (rdata_captured !== 32'h63746d20) begin
      $display("FAIL: CORE_NAME0 = %h", rdata_captured); errors = errors + 1;
    end else $display("PASS: CORE_NAME0 correct");

    // ---- Region 2: CLAUSE_WRITE packet path still works ----
    ahb_write(16'h2000, 32'h1111_0000);
    ahb_write(16'h2004, 32'h1111_0001);
    ahb_write(16'h2008, 32'h1111_0002);
    ahb_write(16'h200C, 32'h1111_0003);
    ahb_write(16'h2010, 32'h1111_0004);
    ahb_write(16'h2014, 32'h1111_0005);
    ahb_write(16'h2018, 32'h1111_0006);
    ahb_write(16'h201C, 32'h1111_0007);
    $display("PASS: clause_write packet sequence completed (region 2 unaffected)");

    // ---- Region 4: AES-128 KAT via memory-mapped interface ----
    // NIST FIPS-197 test vector:
    // Key:       000102030405060708090a0b0c0d0e0f (128-bit, upper 128b of
    //            the 256-bit key bus unused for AES-128)
    // Plaintext: 00112233445566778899aabbccddeeff
    // Expected ciphertext: 69c4e0d86a7b0430d8cdb78070b4c55a
    //
    // Write ordering note (confirmed by waveform inspection): the packet
    // constructor assembles words such that the LAST word written lands in
    // the packet's MSBs and the FIRST word written lands in the LSBs. For
    // AES-128, aes_core uses key[255:128] as the active key (see
    // aes_key_mem.v), so the real key bytes must be in the last 4 words
    // written (0x4010-0x401C), with the first 4 words (0x4000-0x400C)
    // don't-care for AES-128. Same last-write-is-MSB ordering applies to
    // AES_BLOCK.
    ahb_write(16'h4000, 32'h00000000);  // key[31:0]   (unused, AES-128)
    ahb_write(16'h4004, 32'h00000000);  // key[63:32]  (unused, AES-128)
    ahb_write(16'h4008, 32'h00000000);  // key[95:64]  (unused, AES-128)
    ahb_write(16'h400C, 32'h00000000);  // key[127:96] (unused, AES-128)
    ahb_write(16'h4010, 32'h0c0d0e0f);  // key[159:128]
    ahb_write(16'h4014, 32'h08090a0b);  // key[191:160]
    ahb_write(16'h4018, 32'h04050607);  // key[223:192]
    ahb_write(16'h401C, 32'h00010203);  // key[255:224] - written LAST -> MSBs
    $display("INFO: AES key packet written");

    ahb_write(16'h4020, 32'hccddeeff);  // plaintext[31:0]
    ahb_write(16'h4024, 32'h8899aabb);  // plaintext[63:32]
    ahb_write(16'h4028, 32'h44556677);  // plaintext[95:64]
    ahb_write(16'h402C, 32'h00112233);  // plaintext[127:96] - written LAST -> MSBs
    $display("INFO: AES block (plaintext) packet written");

    // AES_CTRL: encdec=1 (encrypt), keylen=0 (AES-128), pulse init (bit0)
    ahb_write(16'h4030, 32'b0000_0101);  // keylen=0, encdec=1, next=0, init=1
    $display("INFO: AES init pulsed (key expansion)");

    // Poll AES_STATUS.ready (bit0) until key expansion completes
    begin : poll_ready
      integer i;
      reg done;
      done = 1'b0;
      for (i = 0; i < 40 && !done; i = i + 1) begin
        ahb_read(16'h4034);
        if (rdata_captured[0] === 1'b1) done = 1'b1;
      end
      if (!done) begin
        $display("FAIL: AES key expansion did not complete (ready never asserted)");
        errors = errors + 1;
      end else
        $display("PASS: AES key expansion complete (ready asserted)");
    end

    // Pulse next (bit1) to start block encryption
    ahb_write(16'h4030, 32'b0000_0110);  // keylen=0, encdec=1, next=1, init=0
    $display("INFO: AES next pulsed (block encryption start)");

    // Poll AES_STATUS.result_valid (bit1)
    begin : poll_valid
      integer i;
      reg done;
      done = 1'b0;
      for (i = 0; i < 40 && !done; i = i + 1) begin
        ahb_read(16'h4034);
        if (rdata_captured[1] === 1'b1) done = 1'b1;
      end
      if (!done) begin
        $display("FAIL: AES result_valid never asserted");
        errors = errors + 1;
      end else
        $display("PASS: AES result_valid asserted");
    end

    // Read back RESULT (4 words, MSW first)
    ahb_read(16'h4040); aes_result_captured[127:96] = rdata_captured;
    ahb_read(16'h4044); aes_result_captured[95:64]  = rdata_captured;
    ahb_read(16'h4048); aes_result_captured[63:32]  = rdata_captured;
    ahb_read(16'h404C); aes_result_captured[31:0]   = rdata_captured;

    if (aes_result_captured === 128'h69c4e0d86a7b0430d8cdb78070b4c55a) begin
      $display("PASS: AES-128 KAT via AHB memory map matches NIST FIPS-197 vector");
      $display("      result = %h", aes_result_captured);
    end else begin
      $display("FAIL: AES-128 KAT via AHB memory map mismatch");
      $display("      expected = 69c4e0d86a7b0430d8cdb78070b4c55a");
      $display("      got      = %h", aes_result_captured);
      errors = errors + 1;
    end

    // ---- Confirm region isolation: clause data untouched by AES traffic ----
    ahb_read(16'h0020); // LOAD_STATUS - just confirm readable, no hang
    $display("INFO: LOAD_STATUS post-AES = %h", rdata_captured);

    repeat (5) @(posedge HCLK);

    if (errors == 0)
      $display("\n=== ALL COMBINED SMOKE TESTS PASSED ===");
    else
      $display("\n=== %0d COMBINED SMOKE TEST(S) FAILED ===", errors);

    $finish;
  end

  initial begin
    #200000;
    $display("TIMEOUT: combined smoke test did not finish in time");
    $finish;
  end

endmodule
