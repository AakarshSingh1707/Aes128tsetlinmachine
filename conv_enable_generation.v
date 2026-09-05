`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/24/2024 07:43:07 PM
// Design Name: 
// Module Name: conv_enable_generation
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module conv_enable_generation(clk, rst, i_rst_n, stride, patch_size, conv_enable);
input clk, rst;
input i_rst_n;                          // FIX: added i_rst_n port
input [2:0] stride, patch_size;
output reg conv_enable;
reg [2:0] init_counter, on_counter, off_counter;

reg conv_enable_nxt;
reg [2:0] init_counter_nxt;
reg [2:0] on_counter_nxt;
reg [2:0] off_counter_nxt;

always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        conv_enable  <= 1'b0;
        init_counter <= 3'b0;
        on_counter   <= 3'b0;
        off_counter  <= 3'b0;
    end
    else begin
        conv_enable  <= conv_enable_nxt;
        init_counter <= init_counter_nxt;
        on_counter   <= on_counter_nxt;
        off_counter  <= off_counter_nxt;
    end
end

always @(*) begin
    conv_enable_nxt  = conv_enable;
    init_counter_nxt = init_counter;
    on_counter_nxt   = on_counter;
    off_counter_nxt  = off_counter;

    if (rst) begin
        conv_enable_nxt  = 1'b0;
        init_counter_nxt = 3'b0;
        on_counter_nxt   = 3'b0;
        off_counter_nxt  = 3'b0;
    end
    else begin
        if (init_counter >= patch_size - 1) begin
            conv_enable_nxt = 1'b1;

            if (on_counter == 1) begin
                if (off_counter == stride - 1) begin
                    conv_enable_nxt = 1'b1;
                    off_counter_nxt = 0;
                end
                else begin
                    off_counter_nxt = off_counter + 1;
                    conv_enable_nxt = 1'b0;
                end
            end
            else begin
                on_counter_nxt = on_counter + 1;
            end
        end
        else begin
            init_counter_nxt = init_counter + 1;
            conv_enable_nxt  = 1'b0;
        end
    end
end
endmodule
