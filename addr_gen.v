`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.06.2025 20:46:55
// Design Name: 
// Module Name: addr_gen
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

module addr_gen#(
parameter  WIDTH = 28,
parameter  HEIGHT = 28			
)(
    input clk,
    input i_rst_n,   // FIX: added i_rst_n port for async reset
    input rst,
    input [5:0] cycle_counts,
    input [2:0] stride,
    input [2:0] patch_size,
    input [2:0] k,
    input en,
    output reg clause_active,
    output reg [HEIGHT - 1:0] y1,
    output reg done
);

integer i;
reg [15:0]ycor1;
reg [5:0] cycle_count;
reg [8:0] cc_m1;
reg [9:0] cc_x8, cc_m1_x8;
reg [8:0] k_x3, k_x5, k_x6, k_x7;
reg [8:0] tmp;

// next-state regs for split blocks
reg [8:0] cc_m1_nxt;
reg [9:0] cc_x8_nxt, cc_m1_x8_nxt;
reg [8:0] k_x3_nxt, k_x5_nxt, k_x6_nxt, k_x7_nxt;
reg [8:0] tmp_nxt;
reg [15:0] ycalc_nxt;
reg clause_act_nxt;
reg [HEIGHT-1:0] y1_nxt;

// Stage 1 register
reg [15:0] ycalc;    // y co-ordinate address calculation

reg [15:0] ycor1_nxt;
reg clause_active_nxt;
reg done_nxt;
reg [5:0] cycle_count_nxt;


always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cc_m1    <= 8'b0;
        cc_x8    <= 8'b0;
        cc_m1_x8 <= 8'b0;
        k_x3     <= 8'b0;
        k_x5     <= 8'b0;
        k_x6     <= 8'b0;
        k_x7     <= 8'b0;
        tmp      <= 8'b0;
        ycalc    <= 9'b0;
    end
    else begin
        cc_m1    <= cc_m1_nxt;
        cc_x8    <= cc_x8_nxt;
        cc_m1_x8 <= cc_m1_x8_nxt;
        k_x3     <= k_x3_nxt;
        k_x5     <= k_x5_nxt;
        k_x6     <= k_x6_nxt;
        k_x7     <= k_x7_nxt;
        tmp      <= tmp_nxt;
        ycalc    <= ycalc_nxt;
    end
end

always @(*) begin

    // defaults  hold values
    cc_m1_nxt    = cc_m1;
    cc_x8_nxt    = cc_x8;
    cc_m1_x8_nxt = cc_m1_x8;
    k_x3_nxt     = k_x3;
    k_x5_nxt     = k_x5;
    k_x6_nxt     = k_x6;
    k_x7_nxt     = k_x7;
    tmp_nxt      = tmp;
    ycalc_nxt    = 9'b0;
    if(rst) begin
	    cc_m1_nxt    = cc_m1;
	    cc_x8_nxt    = cc_x8;
	    cc_m1_x8_nxt = cc_m1_x8;
	    k_x3_nxt     = k_x3;
	    k_x5_nxt     = k_x5;
	    k_x6_nxt     = k_x6;
	    k_x7_nxt     = k_x7;
	    tmp_nxt      = tmp;
	    ycalc_nxt    = 9'b0;
    end 
    
    else begin
    if (en) begin
        cc_m1_nxt    = cycle_count - 1;
        clause_act_nxt = 1'b1;
        cc_x8_nxt    = {1'b0,1'b0,1'b0,1'b0,cycle_count << 3};
        cc_m1_x8_nxt = (cycle_count - 1) << 3;
        k_x3_nxt     = {2'b0,(k * 3'd3)};
        k_x5_nxt     = {3'b0,(3'd5 * k)};
        k_x6_nxt     = {3'b0,(3'd6 * k)};
        k_x7_nxt     = {4'b0,(3'd7 * k)};

        if (patch_size == 3 && (stride == 1 || stride == 2)) begin
            if (cycle_count == 0)
                ycalc_nxt = {1'b0,1'b0, 1'b0,1'b0,1'b0, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, ( stride * k )};
            else if ((k > 5 && stride == 1) || (k == 3 && stride == 2))
                ycalc_nxt = {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_m1_x8 + stride * k};
            else
                ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_x8 + stride * k};
        end

        else if (patch_size == 3 && stride == 3) begin
            tmp_nxt   = cycle_count / 3;
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x3 + (tmp << 4) + (tmp << 3)};   // use registered tmp
        end

        else if (patch_size == 5 && (stride == 1 || stride == 2 || stride == 4)) begin
            if (cycle_count == 0)
                ycalc_nxt = {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, (stride *k)};
            else if ((k > 3 && stride == 1) || (k > 1 && stride == 2) || (k == 1 && stride == 4))
                ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_m1_x8 + stride * k};
            else
                ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_x8 + stride * k};
        end

        else if (patch_size == 5 && stride == 3) begin
            tmp_nxt   = ((cc_m1 * (cycle_count > 1)) / 3)
                      + ((k==0 || k==1) && cycle_count>0);
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x3 + (tmp << 4) + (tmp << 3)};   // use registered tmp
        end

        else if (patch_size == 5 && stride == 5) begin
            tmp_nxt   = cycle_count / 5;
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x5 + (tmp << 5) + (tmp << 3)};   // use registered tmp
        end

        else if (patch_size == 7 && (stride == 1 || stride == 2 || stride == 4)) begin
            if (cycle_count == 0)
                ycalc_nxt = {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, stride * k};
            else if ((k > 1 && stride == 1) || (k > 0 && stride == 2) || (k == 1 && stride == 4))
                ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_m1_x8 + stride * k};
            else
                ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,cc_x8 + stride * k};
        end

        else if (patch_size == 7 && stride == 3) begin
            tmp_nxt   = ((cc_m1 * (cycle_count > 1)) / 3)
                      + ((k==0) && cycle_count>0);
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x3 + (tmp << 4) + (tmp << 3)};   // use registered tmp
        end

        else if (patch_size == 7 && stride == 5) begin
            tmp_nxt   = ((cc_m1 * (cycle_count > 1)) / 5)
                      + ((k==0) && cycle_count>0);
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x5 + (tmp << 5) + (tmp << 3)};   // use registered tmp
        end

        else if (stride == 6) begin
            tmp_nxt   = ((cc_m1 * (cycle_count > 1)) / 3)
                      + ((k==0) && cycle_count>0);
            ycalc_nxt =  {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,k_x6 + (tmp << 4) + (tmp << 3)};   // use registered tmp
        end

        else if (stride == 7) begin
            tmp_nxt   = cycle_count / 7;
            ycalc_nxt = k_x7 + (tmp << 6) - (tmp << 3);   // use registered tmp
        end
    end
    end
    // en=0 : ycalc_nxt stays 0 (matches original else ycalc <= 0)
end


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n)
        ycor1 <= 9'b0;
    else
        ycor1 <= ycor1_nxt;
end


/* combinational next-state logic */
always @(*) begin
    // default hold
    ycor1_nxt = ycor1;

    if (rst)
        ycor1_nxt = 9'b0;
    else
        ycor1_nxt = ycalc;
end


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n)
        y1 <= {HEIGHT{1'b0}};
    else
        y1 <= y1_nxt;
end


/* combinational next-state logic */
always @(*) begin
    // default hold
    y1_nxt = y1;

    if (rst) begin
        y1_nxt = {HEIGHT{1'b0}};
    end
    else begin
        for (i = 0; i < HEIGHT; i = i + 1)
            y1_nxt[i] = (i < ycor1);
    end
end

// ------------------------------------------------------------
// clause_active, cycle_count, done
// FIX: async reset with i_rst_n
// ------------------------------------------------------------
/* next-state registers */


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        clause_active <= 1'b0;
        done          <= 1'b0;
        cycle_count   <= 6'b0;
    end
    else begin
        clause_active <= clause_active_nxt;
        done          <= done_nxt;
        cycle_count   <= cycle_count_nxt;
    end
end


/* combinational next-state logic */
always @(*) begin
    // default hold
    clause_active_nxt = clause_active;
    done_nxt          = done;
    cycle_count_nxt   = cycle_count;

    if (rst) begin
        clause_active_nxt = 1'b0;
        done_nxt          = 1'b0;
        cycle_count_nxt   = 6'b0;
    end
    else begin
        if (en)
            clause_active_nxt = 1'b1;
        else
            clause_active_nxt = 1'b0;

        cycle_count_nxt = cycle_counts - 1;

        if (y1[HEIGHT - patch_size - 1])
            done_nxt = 1'b1;
        else
            done_nxt = 1'b0;
    end
end
endmodule
