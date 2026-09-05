`timescale 1ns / 1ps

module Convolution (
    input clk,
    input i_rst_n,
    input rst,
    input conv_enable,
    input pe_enable,
    input [6:0] pixels,
    input [2:0] patch_size,
    input [48:0] rule,
    input [48:0] neg_rule,
    input Xmatch,
    input Ymatch,
    output reg clause_op
);
reg [9:0] shift_reg,shift_reg2;   // to match delays
reg [6:0] conv_unit[0:6];
reg [6:0] conv_unit_nxt[0:6];
integer i,j;
wire x_match_d2,x_match_d4,x_match_d6,y_match_d2,y_match_d4,y_match_d6;  // delaying positioned matched outputs
wire row3_r,row5_r,row7_r;
wire negrow3_r,negrow5_r,negrow7_r;
reg [6:0] out3_r,out5_r,out7_r;
reg [6:0] neg3_r,neg5_r,neg7_r;

reg out_r     [0:48];
reg neg_out_r [0:48];
reg [9:0] shift_reg_nxt;
reg [9:0] shift_reg2_nxt;
reg clause_op_nxt;


always @(posedge clk or negedge i_rst_n) begin:cu_l1
	integer iii,jjj;
	if (!i_rst_n)
	begin
        for (iii=0;iii<7;iii=iii+1)
            for (jjj=0;jjj<7;jjj=jjj+1)
	conv_unit[iii][jjj] <= 7'b0; 
   	end
      else 
      begin	      
        for (iii=0;iii<7;iii=iii+1)
            for (jjj=0;jjj<7;jjj=jjj+1)
	conv_unit[iii][jjj] <= conv_unit_nxt[iii][jjj];
	end
end

always @(*) begin 
 if (rst) begin
        for (i=0;i<7;i=i+1)
            for (j=0;j<7;j=j+1)
                conv_unit_nxt[i][j] = 0;
    end
    else begin  
   if (pe_enable) begin:pe_l2
        for (i=0;i<7;i=i+1) begin
            conv_unit_nxt[i][0] = (i < patch_size) ? pixels[i] : 1'b0;
            for (j=1;j<7;j=j+1)
                conv_unit_nxt[i][j] = (j < patch_size) ? conv_unit[i][j-1] : 1'b0;
        end
    end
    else  begin:def_l3
        for (i=0;i<7;i=i+1)
            for (j=0;j<7;j=j+1)
	conv_unit_nxt[i][j] = conv_unit[i][j];
    end
    end
end

always @(*) begin
    if (rst) begin
        for(i=0;i<49;i=i+1) begin
            out_r[i]     = 0;
            neg_out_r[i] = 0;
        end
    end
    else begin
        for (i=0;i<49;i=i+1) begin
            out_r[i]     = conv_unit[i/7][6-(i%7)] | (~rule[i]);
            neg_out_r[i] = (~conv_unit[i/7][6-(i%7)]) | (~neg_rule[i]);
        end
    end
end

always @(*) begin
    if (rst) begin
        out3_r=0; out5_r=0; out7_r=0;
        neg3_r=0; neg5_r=0; neg7_r=0;
    end
    else begin
        for(i=0;i<7;i=i+1) begin
            out3_r[i] = (patch_size>=3) ?
                (out_r[i*7+0] & out_r[i*7+1] & out_r[i*7+2]) : 0;

            out5_r[i] = (patch_size>=5) ?
                (out3_r[i] & out_r[i*7+3] & out_r[i*7+4]) : 0;

            out7_r[i] = (patch_size==7) ?
                (out5_r[i] & out_r[i*7+5] & out_r[i*7+6]) : 0;

            neg3_r[i] = (patch_size>=3) ?
                (neg_out_r[i*7+0] & neg_out_r[i*7+1] & neg_out_r[i*7+2]) : 0;

            neg5_r[i] = (patch_size>=5) ?
                (neg3_r[i] & neg_out_r[i*7+3] & neg_out_r[i*7+4]) : 0;

            neg7_r[i] = (patch_size==7) ?
                (neg5_r[i] & neg_out_r[i*7+5] & neg_out_r[i*7+6]) : 0;
        end
    end
end




assign row3_r = &out3_r[1:0];
assign row5_r = &out5_r[3:0];
assign row7_r = &out7_r[5:0];

assign negrow3_r = &neg3_r[1:0];
assign negrow5_r = &neg5_r[3:0];
assign negrow7_r = &neg7_r[5:0];

   

always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg  <= 10'b0;
        shift_reg2 <= 10'b0;
    end
    else begin
        shift_reg  <= shift_reg_nxt;
        shift_reg2 <= shift_reg2_nxt;
    end
end

always @(*) begin
    shift_reg_nxt  = shift_reg;
    shift_reg2_nxt = shift_reg2;

    shift_reg_nxt  = {shift_reg[8:0],  Xmatch};
    shift_reg2_nxt = {shift_reg2[8:0], Ymatch};
end


    assign x_match_d2 = shift_reg[1];
    assign x_match_d4 = shift_reg[3];
    assign x_match_d6 = shift_reg[5];
    assign y_match_d2 = shift_reg2[1];
    assign y_match_d4 = shift_reg2[3];
    assign y_match_d6 = shift_reg2[5];


always @(posedge clk or negedge i_rst_n) begin
if (!i_rst_n) clause_op <= 1'b0;
        else 
    clause_op <= clause_op_nxt;
end

always @(*) begin
    clause_op_nxt = clause_op;

    if (rst)
        clause_op_nxt = 0;
    else begin
        if (pe_enable && conv_enable) begin
            case (patch_size)
                3: clause_op_nxt = x_match_d2 & y_match_d2 & row3_r & negrow3_r;
                5: clause_op_nxt = x_match_d4 & y_match_d4 & row5_r & negrow5_r;
                7: clause_op_nxt = x_match_d6 & y_match_d6 & row7_r & negrow7_r;
                default: clause_op_nxt = 0;
            endcase
        end
        else
            clause_op_nxt = 0;
    end
end
endmodule
