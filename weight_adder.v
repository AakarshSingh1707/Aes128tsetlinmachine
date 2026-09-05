`timescale 1ns / 1ps
module weight_adder #(
    parameter CLAUSEN = 140
)(
    input clk,
    input i_rst_n,                          // FIX: added i_rst_n port
    input valid,
    input [255:0] weight_write,
    input [2:0] offset,
    input [$clog2(CLAUSEN)-1:0] clauses,
    input [$clog2(CLAUSEN)-1:0] clause_no,
    output reg signed [8:0] weight
);
    reg [1279:0] dout;
    reg [$clog2(CLAUSEN*9)-1:0] idx;
    reg signed [8:0] wt;

    // ------------------------------------------------------------
    // Write logic
    // FIX: async reset with i_rst_n
    // ------------------------------------------------------------
    always @(posedge clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            dout <= 0;
        end
        else if (valid) begin
            case (offset)
                3'd0: dout[255:0]     <= weight_write;
                3'd1: dout[511:256]   <= weight_write;
                3'd2: dout[767:512]   <= weight_write;
                3'd3: dout[1023:768]  <= weight_write;
                3'd4: dout[1279:1024] <= weight_write;
                default: dout <= 0;
            endcase
        end
        else dout <= dout;
    end

    // ------------------------------------------------------------
    // Address pipeline
    // FIX: async reset with i_rst_n
    // ------------------------------------------------------------
    always @(posedge clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            idx <= 0;
        else
            idx <= (clauses - clause_no - 1) * 9;
    end

    // ------------------------------------------------------------
    // Read pipeline
    // FIX: async reset with i_rst_n
    // ------------------------------------------------------------
    always @(posedge clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wt     <= 0;
            weight <= 0;
        end
        else begin
            wt     <= dout[idx +: 9];
            weight <= wt;
        end
    end

endmodule
