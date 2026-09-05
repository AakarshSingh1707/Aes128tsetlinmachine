//-----------------------------------------------------------------------------
// SoC Labs Accelerator Subsystem for Convolutional Tsetlin Machine (CTM)
// Mirrors the structure of accelerator_subsystem.v (SecWorks AES-128 version)
// so the CTM accelerator plugs into a nanoSoC in the same way: as an
// AHB-Lite memory-mapped peripheral.
//-----------------------------------------------------------------------------

module accelerator_subsystem_ctm #(
  parameter SYS_ADDR_W = 32,
  parameter SYS_DATA_W = 32,
  parameter ACC_ADDR_W = 16,
  parameter IRQ_NUM    = 4
) (
  input  wire                      HCLK,
  input  wire                      HRESETn,

  // AHB connection to Initiator
  input  wire                      HSEL,
  input  wire   [SYS_ADDR_W-1:0]   HADDR,
  input  wire   [1:0]              HTRANS,
  input  wire   [2:0]              HSIZE,
  input  wire   [3:0]              HPROT,
  input  wire                      HWRITE,
  input  wire                      HREADY,
  input  wire   [SYS_DATA_W-1:0]   HWDATA,

  output wire                      HREADYOUT,
  output wire                      HRESP,
  output wire   [SYS_DATA_W-1:0]   HRDATA,

  // Data Request Signals to DMAC (clause / weight / image / aes load channels)
  output wire   [3:0]              EXP_DRQ,

  // Interrupts
  output wire   [IRQ_NUM-1:0]      EXP_IRQ
);

  //  --------------------------------------
  //   CTM + AES-128 Accelerator Wrapper
  //  --------------------------------------
  soclabs_ahb_ctm_ctrl u_exp_ctm (
    .ahb_hclk        (HCLK),
    .ahb_hresetn     (HRESETn),
    .ahb_hsel        (HSEL),
    .ahb_haddr16     (HADDR[ACC_ADDR_W-1:0]),
    .ahb_htrans      (HTRANS),
    .ahb_hwrite      (HWRITE),
    .ahb_hsize       (HSIZE),
    .ahb_hprot       (HPROT),
    .ahb_hwdata      (HWDATA),
    .ahb_hready      (HREADY),
    .ahb_hrdata      (HRDATA),
    .ahb_hreadyout   (HREADYOUT),
    .ahb_hresp       (HRESP),
    .drq_clausebuf   (EXP_DRQ[0]),
    .drq_weightbuf   (EXP_DRQ[1]),
    .drq_imgbuf      (EXP_DRQ[2]),
    .drq_aesbuf      (EXP_DRQ[3]),
    .irq_done        (EXP_IRQ[0]),
    .irq_error       (EXP_IRQ[1]),
    .irq_aes_done    (EXP_IRQ[2]),
    .irq_merged      (EXP_IRQ[3])
  );

endmodule
