`timescale 1ns / 1ps
module aes_core_kat_tb;

  reg          clk = 0;
  reg          reset_n = 0;
  reg          encdec;
  reg          init;
  reg          next;
  wire         ready;
  reg  [255:0] key;
  reg          keylen;
  reg  [127:0] block;
  wire [127:0] result;
  wire         result_valid;

  aes_core dut (
    .clk(clk), .reset_n(reset_n),
    .encdec(encdec), .init(init), .next(next), .ready(ready),
    .key(key), .keylen(keylen),
    .block(block), .result(result), .result_valid(result_valid)
  );

  always #5 clk = ~clk;

  // NIST FIPS-197 Appendix B / C.1 AES-128 test vector:
  // Key:       000102030405060708090a0b0c0d0e0f
  // Plaintext: 00112233445566778899aabbccddeeff
  // Expected ciphertext: 69c4e0d86a7b0430d8cdb78070b4c55a

  initial begin
    reset_n = 0;
    encdec  = 1'b1;   // encrypt
    init    = 0;
    next    = 0;
    keylen  = 1'b0;   // AES-128
    key     = {128'h000102030405060708090a0b0c0d0e0f, 128'h0};
    block   = 128'h00112233445566778899aabbccddeeff;

    repeat (4) @(posedge clk);
    reset_n = 1;
    repeat (2) @(posedge clk);

    // Initialize (key expansion)
    @(posedge clk);
    init = 1;
    @(posedge clk);
    init = 0;
    $display("DEBUG after init pulse: ready=%b t=%0t", ready, $time);

    // Wait for ready after key expansion
    begin : wait_ready_loop
      integer i;
      for (i = 0; i < 30; i = i + 1) begin
        @(posedge clk);
        $display("DEBUG waiting: ready=%b result_valid=%b t=%0t", ready, result_valid, $time);
        if (ready) i = 30;
      end
    end

    // Start block encryption
    next = 1;
    @(posedge clk);
    next = 0;

    wait (result_valid == 1'b1);
    @(posedge clk);

    if (result === 128'h69c4e0d86a7b0430d8cdb78070b4c55a) begin
      $display("PASS: AES-128 KAT matches NIST FIPS-197 test vector");
      $display("      result = %h", result);
    end else begin
      $display("FAIL: AES-128 KAT mismatch");
      $display("      expected = 69c4e0d86a7b0430d8cdb78070b4c55a");
      $display("      got      = %h", result);
    end

    repeat (5) @(posedge clk);
    $finish;
  end

  initial begin
    #50000;
    $display("TIMEOUT: aes_core KAT did not complete");
    $finish;
  end

endmodule
