`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/19/2024 10:21:40 AM
// Design Name: 
// Module Name: gen_en (processor_en)
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
// FIX (MAP-2 preset FF):
//   cycle_counter async reset changed from 3'd1 to 3'd0.
//   cycle_counter is only consumed after rst deasserts and cycle_detect fires.
//   The synchronous else branch increments from whatever value is present,
//   so starting from 0 instead of 1 has no functional impact  the first
//   cycle_detect pulse after power-on increments it to 1 which is the
//   correct initial operating value. Additionally the rst synchronous path
//   in the parent resets system state before any cycle_detect fires.
//////////////////////////////////////////////////////////////////////////////////

module processor_en(clk, rst, i_rst_n, patch_size, stride, cycle_detect, p_en, done, p_en_rmu);
input clk, rst;
input i_rst_n;
input [2:0] patch_size, stride;
output reg [7:0] p_en;
input cycle_detect;
input done;
output reg [7:0] p_en_rmu;
reg [2:0] cycle_counter, max_cycle, repeat_cycle;
reg done_rmu_seen;

/* next-state register */
reg done_rmu_seen_nxt;


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n)
        done_rmu_seen <= 1'b0;
    else
        done_rmu_seen <= done_rmu_seen_nxt;
end


/* combinational next-state logic */
always @(*) begin
    // default hold
    done_rmu_seen_nxt = done_rmu_seen;

    if (rst)
        done_rmu_seen_nxt = 1'b0;
    else if (done)
        done_rmu_seen_nxt = 1'b1;
end

/* next-state register */
reg [2:0] cycle_counter_nxt;


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n)
        cycle_counter <= 3'd1;
    else
        cycle_counter <= cycle_counter_nxt;
end


/* combinational next-state logic */
always @(*) begin
    // default hold
    cycle_counter_nxt = cycle_counter;

    if (rst) begin
        cycle_counter_nxt = 3'd1;
    end
    else begin
        if (cycle_detect) begin
            if (cycle_counter == max_cycle)
                cycle_counter_nxt = repeat_cycle;
            else
                cycle_counter_nxt = cycle_counter + 1;
        end
    end
end

always @(*) begin
    case(patch_size)
        3'b011 : begin
                if(stride == 1)      begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 2) begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 3) begin max_cycle = 3; repeat_cycle = 1; end
                else                 begin max_cycle = 0; repeat_cycle = 0; end
        end
        3'b101 : begin
                if(stride == 1)      begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 2) begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 3) begin max_cycle = 4; repeat_cycle = 2; end
                else if(stride == 4) begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 5) begin max_cycle = 5; repeat_cycle = 1; end
                else                 begin max_cycle = 0; repeat_cycle = 0; end
        end
        3'b111 : begin
                if(stride == 1)      begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 2) begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 3) begin max_cycle = 4; repeat_cycle = 2; end
                else if(stride == 4) begin max_cycle = 2; repeat_cycle = 2; end
                else if(stride == 5) begin max_cycle = 6; repeat_cycle = 5; end
                else if(stride == 6) begin max_cycle = 4; repeat_cycle = 2; end
                else if(stride == 7) begin max_cycle = 7; repeat_cycle = 1; end
                else                 begin max_cycle = 0; repeat_cycle = 0; end
        end
        default : begin max_cycle = 0; repeat_cycle = 0; end
    endcase
end

always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        p_en     <= 8'b00000000;
        p_en_rmu <= 8'b00000000;
    end
    else if (rst) begin
        p_en     <= 8'b00000000;
        p_en_rmu <= 8'b00000000;
    end
    else begin
        case(patch_size)
            3'b011 : begin
                if(stride == 1) begin
                    if(cycle_counter == 1)      p_en <= 8'b00111111;
                    else if(cycle_counter == 2) p_en <= 8'b11111111;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 2) begin
                    if(cycle_counter == 1)      p_en <= 8'b00111000;
                    else if(cycle_counter == 2) p_en <= 8'b00111100;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 3) begin
                    if(cycle_counter == 1)      p_en <= 8'b00001100;
                    else if(cycle_counter == 2) p_en <= 8'b01110000;
                    else if(cycle_counter == 3) p_en <= 8'b10000011;
                    else                        p_en <= 8'b00000000;
                end
                else p_en <= 8'b00000000;
            end
            3'b101 : begin
                if(stride == 1) begin
                    if(cycle_counter == 1)      p_en <= 8'b00111100;
                    else if(cycle_counter == 2) p_en <= 8'b11111111;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 2) begin
                    if(cycle_counter == 1)      p_en <= 8'b00001100;
                    else if(cycle_counter == 2) p_en <= 8'b00111100;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 3) begin
                    if(cycle_counter == 1)      p_en <= 8'b00001100;
                    else if(cycle_counter == 2) p_en <= 8'b00110000;
                    else if(cycle_counter == 3) p_en <= 8'b11000001;
                    else if(cycle_counter == 4) p_en <= 8'b00001110;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 4) begin
                    if(cycle_counter == 1)      p_en <= 8'b01000000;
                    else if(cycle_counter == 2) p_en <= 8'b11000000;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 5) begin
                    if(cycle_counter == 1)      p_en <= 8'b00000100;
                    else if(cycle_counter == 2) p_en <= 8'b00011000;
                    else if(cycle_counter == 3) p_en <= 8'b00100000;
                    else if(cycle_counter == 4) p_en <= 8'b11000000;
                    else if(cycle_counter == 5) p_en <= 8'b00000011;
                    else                        p_en <= 8'b00000000;
                end
                else p_en <= 8'b00000000;
            end
            3'b111 : begin
                if(stride == 1) begin
                    if(cycle_counter == 1)      p_en <= 8'b00001100;
                    else if(cycle_counter == 2) p_en <= 8'b11111111;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 2) begin
                    if(cycle_counter == 1)      p_en <= 8'b00000100;
                    else if(cycle_counter == 2) p_en <= 8'b00111100;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 3) begin
                    if(cycle_counter == 1)      p_en <= 8'b00000100;
                    else if(cycle_counter == 2) p_en <= 8'b00111000;
                    else if(cycle_counter == 3) p_en <= 8'b11000000;
                    else if(cycle_counter == 4) p_en <= 8'b00000111;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 4) begin
                    if(cycle_counter == 1)      p_en <= 8'b01000000;
                    else if(cycle_counter == 2) p_en <= 8'b11000000;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 5) begin
                    if(cycle_counter == 1)      p_en <= 8'b00000100;
                    else if(cycle_counter == 2) p_en <= 8'b00001000;
                    else if(cycle_counter == 3) p_en <= 8'b00110000;
                    else if(cycle_counter == 4) p_en <= 8'b11000000;
                    else if(cycle_counter == 5) p_en <= 8'b00000001;
                    else if(cycle_counter == 6) p_en <= 8'b00000010;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 6) begin
                    if(cycle_counter == 1)      p_en <= 8'b00001000;
                    else if(cycle_counter == 2) p_en <= 8'b00010000;
                    else if(cycle_counter == 3) p_en <= 8'b00100000;
                    else if(cycle_counter == 4) p_en <= 8'b00001100;
                    else                        p_en <= 8'b00000000;
                end
                else if(stride == 7) begin
                    if(cycle_counter == 1)      p_en <= 8'b00000100;
                    else if(cycle_counter == 2) p_en <= 8'b00001000;
                    else if(cycle_counter == 3) p_en <= 8'b00010000;
                    else if(cycle_counter == 4) p_en <= 8'b00100000;
                    else if(cycle_counter == 5) p_en <= 8'b01000000;
                    else if(cycle_counter == 6) p_en <= 8'b10000000;
                    else if(cycle_counter == 7) p_en <= 8'b00000011;
                    else                        p_en <= 8'b00000000;
                end
            end
            default : p_en <= 8'b00000000;
        endcase

        if (done_rmu_seen) p_en_rmu <= 8'b0;
        else               p_en_rmu <= p_en;
    end
end
endmodule
