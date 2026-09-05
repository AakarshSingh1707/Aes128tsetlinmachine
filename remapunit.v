`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/11/2024 04:50:04 PM
// Design Name: 
// Module Name: remapunit
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

module remapunit(clk,i_rst_n, rst, patch_size,stride,pixel_in, residues,cycle_counts,cycle_detect,xcor1,
                processor_in1,processor_in2,processor_in3,processor_in4,processor_in5,processor_in6,processor_in7,processor_in8
                ,p_en,p1y1,p1x1,p2y1,p3y1,p4y1,p5y1,p6y1,p7y1,p8y1,clause_act,done);

parameter  IMG_WIDTH = 28;
parameter  IMG_HEIGHT = 28;

input clk, rst, i_rst_n, cycle_detect;
input [2:0] patch_size,stride;
input [7:0] pixel_in;
input [5:0] residues,cycle_counts;
input [$clog2(IMG_WIDTH + 2) :0]xcor1;
output reg [6:0] processor_in1,processor_in2,processor_in3,processor_in4,processor_in5,processor_in6,processor_in7,processor_in8;
output wire [7:0] p_en;
output reg [IMG_WIDTH - 1:0] p1x1;
output wire [IMG_HEIGHT - 1:0] p1y1,p2y1,p3y1,p4y1,p5y1,p6y1,p7y1,p8y1;
output wire clause_act;
output wire done;
reg [2:0] k1, k2, k3, k4, k5, k6, k7, k8;
reg done_seen,xdone;
integer i,l;
wire [7:0] clause_active;
wire [7:0] done_ad;
wire [7:0] p_en_rmu;
wire [IMG_WIDTH - 1:0] po1x1[0:7];
wire en;

reg [IMG_WIDTH-1:0] p1x1_nxt;
reg xdone_nxt;
reg done_seen_nxt;
reg [6:0] pin1_nxt, pin2_nxt, pin3_nxt, pin4_nxt;
reg [6:0] pin5_nxt, pin6_nxt, pin7_nxt, pin8_nxt;

assign en = (|p_en);
assign clause_act = (!done_seen) && (clause_active[0]||clause_active[1]||clause_active[2]||clause_active[3]||clause_active[4]||clause_active[5]||clause_active[6]||clause_active[7]);
assign done = xdone && (done_ad[0]||done_ad[1]||done_ad[2]||done_ad[3]||done_ad[4]||done_ad[5]||done_ad[6]||done_ad[7]);  


always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        p1x1  <= {IMG_WIDTH{1'b0}};
        xdone <= 1'b0;
    end
    else begin
        p1x1  <= p1x1_nxt;
        xdone <= xdone_nxt;
    end
end


always @(*) begin
    // default hold
    p1x1_nxt  = p1x1;
    xdone_nxt = xdone;

    if (rst) begin
        p1x1_nxt  = {IMG_WIDTH{1'b0}};
        xdone_nxt = 1'b0;
    end
    else begin
        xdone_nxt = p1x1[IMG_WIDTH-1];

        if (xcor1 != 0 && en) begin
            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                if (i < xcor1 - 1)
                    p1x1_nxt[i] = 1'b1;
                else
                    p1x1_nxt[i] = 1'b0;
            end
        end
        else begin
            p1x1_nxt = {IMG_WIDTH{1'b0}};
        end
    end
end


always @(*) begin
    case (stride)
        3'd1: begin k1 = 3'd0; k2 = 3'd1; k3 = 3'd2; k4 = 3'd3; k5 = 3'd4; k6 = 3'd5; k7 = 3'd6; k8 = 3'd7; end
        3'd2: begin k1 = 3'd0; k2 = 3'd0; k3 = 3'd3; k4 = 3'd0; k5 = 3'd1; k6 = 3'd2; k7 = 3'd0; k8 = 3'd0; end
        3'd3: begin k1 = 3'd6; k2 = 3'd7; k3 = 3'd0; k4 = 3'd1; k5 = 3'd2; k6 = 3'd3; k7 = 3'd4; k8 = 3'd5; end
        3'd4: begin k1 = 3'd0; k2 = 3'd0; k3 = 3'd0; k4 = 3'd0; k5 = 3'd0; k6 = 3'd0; k7 = 3'd0; k8 = 3'd1; end
        3'd5: begin k1 = 3'd6; k2 = 3'd7; k3 = 3'd0; k4 = 3'd1; k5 = 3'd2; k6 = 3'd3; k7 = 3'd4; k8 = 3'd5; end
        3'd6: begin k1 = 3'd0; k2 = 3'd0; k3 = 3'd3; k4 = 3'd0; k5 = 3'd1; k6 = 3'd2; k7 = 3'd0; k8 = 3'd0; end
        3'd7: begin k1 = 3'd6; k2 = 3'd7; k3 = 3'd0; k4 = 3'd1; k5 = 3'd2; k6 = 3'd3; k7 = 3'd4; k8 = 3'd5; end
        default: begin k1 = 3'd0; k2 = 3'd0; k3 = 3'd0; k4 = 3'd0; k5 = 3'd0; k6 = 3'd0; k7 = 3'd0; k8 = 3'd0; end
    endcase
end

processor_en proc_en(clk, rst, i_rst_n, patch_size, stride, cycle_detect, p_en, done, p_en_rmu);

addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst1(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[0]),.k(k1),.en(p_en_rmu[0]),.y1(p1y1),.clause_active(clause_active[0]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst2(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[1]),.k(k2),.en(p_en_rmu[1]),.y1(p2y1),.clause_active(clause_active[1]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst3(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[2]),.k(k3),.en(p_en_rmu[2]),.y1(p3y1),.clause_active(clause_active[2]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst4(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[3]),.k(k4),.en(p_en_rmu[3]),.y1(p4y1),.clause_active(clause_active[3]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst5(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[4]),.k(k5),.en(p_en_rmu[4]),.y1(p5y1),.clause_active(clause_active[4]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst6(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[5]),.k(k6),.en(p_en_rmu[5]),.y1(p6y1),.clause_active(clause_active[5]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst7(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[6]),.k(k7),.en(p_en_rmu[6]),.y1(p7y1),.clause_active(clause_active[6]));
addr_gen #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) addr_inst8(
        .clk(clk),.i_rst_n(i_rst_n),.cycle_counts(cycle_counts),.stride(stride),.patch_size(patch_size),.rst(rst),
        .done(done_ad[7]),.k(k8),.en(p_en_rmu[7]),.y1(p8y1),.clause_active(clause_active[7]));


/* Sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n)
        done_seen <= 1'b0;
    else
        done_seen <= done_seen_nxt;
end

/* Combinational next-state logic */
always @(*) begin
    // default hold
    done_seen_nxt = done_seen;

    if (rst)
        done_seen_nxt = 1'b0;
    else if (done)
        done_seen_nxt = 1'b1;
end

// ------------------------------------------------------------
// processor_in1..8 : combinational next-state
// FIX: split complex stride/patch logic into always@(*) + sequential
// ------------------------------------------------------------


always @(*) begin
// default 0  matches original rst branch and unhandled stride/patch combos
    pin1_nxt = 7'd0; pin2_nxt = 7'd0; pin3_nxt = 7'd0; pin4_nxt = 7'd0;
    pin5_nxt = 7'd0; pin6_nxt = 7'd0; pin7_nxt = 7'd0; pin8_nxt = 7'd0;
    
    if (rst) begin
	pin1_nxt = 7'd0; pin2_nxt = 7'd0; pin3_nxt = 7'd0; pin4_nxt = 7'd0;
    	pin5_nxt = 7'd0; pin6_nxt = 7'd0; pin7_nxt = 7'd0; pin8_nxt = 7'd0;
    end 
    else begin
    if (stride == 1) begin
        pin1_nxt = (patch_size == 3) ? {pixel_in[0],pixel_in[1],pixel_in[2],1'b0,1'b0,1'b0,1'b0} :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(6,stride,patch_size,residues,pixel_in) : 7'd0);
        pin2_nxt = (patch_size == 3) ? tex(1,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(7,stride,patch_size,residues,pixel_in) : 7'd0);
        pin3_nxt = (patch_size == 3) ? tex(2,stride,patch_size,residues,pixel_in) :
                   ((patch_size == 5) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],1'b0,1'b0} :
                   ((patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0));
        pin4_nxt = (patch_size == 3) ? tex(3,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0);
        pin5_nxt = (patch_size == 3) ? tex(4,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0);
        pin6_nxt = (patch_size == 3) ? tex(5,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0);
        pin7_nxt = (patch_size == 3) ? tex(6,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(4,stride,patch_size,residues,pixel_in) : 7'd0);
        pin8_nxt = (patch_size == 3) ? tex(7,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(5,stride,patch_size,residues,pixel_in) : 7'd0);
    end
    else if (stride == 2) begin
        pin1_nxt = 7'd0;
        pin2_nxt = 7'd0;
        pin3_nxt = (patch_size == 3) ? tex(3,stride,patch_size,residues,pixel_in) :
                   ((patch_size == 5) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],1'b0,1'b0} :
                   ((patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0));
        pin4_nxt = (patch_size == 3) ? {pixel_in[0],pixel_in[1],pixel_in[2],1'b0,1'b0,1'b0,1'b0} :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0);
        pin5_nxt = (patch_size == 3) ? tex(1,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0);
        pin6_nxt = (patch_size == 3) ? tex(2,stride,patch_size,residues,pixel_in) :
                   (((patch_size == 5)||(patch_size == 7)) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0);
        pin7_nxt = 7'd0;
        pin8_nxt = 7'd0;
    end
    else if (stride == 3) begin
        pin1_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(6,stride,patch_size,residues,pixel_in) : 7'd0;
        pin2_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(7,stride,patch_size,residues,pixel_in) : 7'd0;
        pin3_nxt = (patch_size == 3) ? {pixel_in[0],pixel_in[1],pixel_in[2],1'b0,1'b0,1'b0,1'b0} :
                   ((patch_size == 5) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],1'b0,1'b0} :
                   ((patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0));
        pin4_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0;
        pin5_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0;
        pin6_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0;
        pin7_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(4,stride,patch_size,residues,pixel_in) : 7'd0;
        pin8_nxt = ((patch_size == 5)||(patch_size == 7)||(patch_size == 3)) ? tex(5,stride,patch_size,residues,pixel_in) : 7'd0;
    end
    else if (stride == 4) begin
        pin1_nxt = 7'd0; pin2_nxt = 7'd0; pin3_nxt = 7'd0;
        pin4_nxt = 7'd0; pin5_nxt = 7'd0; pin6_nxt = 7'd0;
        pin7_nxt = (patch_size == 5) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],1'b0,1'b0} :
                   ((patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0);
        pin8_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0;
    end
    else if (stride == 5) begin
        pin1_nxt = (patch_size == 5) ? tex(6,stride,patch_size,residues,pixel_in) :
                   ((patch_size == 7) ? tex(7,stride,patch_size,residues,pixel_in) : 7'd0);
        pin2_nxt = (patch_size == 5) ? tex(7,stride,patch_size,residues,pixel_in) :
                   ((patch_size == 7) ? tex(6,stride,patch_size,residues,pixel_in) : 7'd0);
        pin3_nxt = (patch_size == 5) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],1'b0,1'b0} :
                   ((patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0);
        pin4_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0;
        pin5_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0;
        pin6_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0;
        pin7_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(4,stride,patch_size,residues,pixel_in) : 7'd0;
        pin8_nxt = ((patch_size == 5)||(patch_size == 7)) ? tex(5,stride,patch_size,residues,pixel_in) : 7'd0;
    end
    else if (stride == 6) begin
        pin1_nxt = 7'd0; pin2_nxt = 7'd0;
        pin3_nxt = (patch_size == 7) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0;
        pin4_nxt = (patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0;
        pin5_nxt = (patch_size == 7) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0;
        pin6_nxt = (patch_size == 7) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0;
        pin7_nxt = 7'd0; pin8_nxt = 7'd0;
    end
    else if (stride == 7) begin
        pin1_nxt = (patch_size == 7) ? tex(6,stride,patch_size,residues,pixel_in) : 7'd0;
        pin2_nxt = (patch_size == 7) ? tex(7,stride,patch_size,residues,pixel_in) : 7'd0;
        pin3_nxt = (patch_size == 7) ? {pixel_in[0],pixel_in[1],pixel_in[2],pixel_in[3],pixel_in[4],pixel_in[5],pixel_in[6]} : 7'd0;
        pin4_nxt = (patch_size == 7) ? tex(1,stride,patch_size,residues,pixel_in) : 7'd0;
        pin5_nxt = (patch_size == 7) ? tex(2,stride,patch_size,residues,pixel_in) : 7'd0;
        pin6_nxt = (patch_size == 7) ? tex(3,stride,patch_size,residues,pixel_in) : 7'd0;
        pin7_nxt = (patch_size == 7) ? tex(4,stride,patch_size,residues,pixel_in) : 7'd0;
        pin8_nxt = (patch_size == 7) ? tex(5,stride,patch_size,residues,pixel_in) : 7'd0;
    end
    end
    // else: all stay 0  matches original else branch
end

// FIX: async reset with i_rst_n, register update only
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        processor_in1 <= 7'd0; processor_in2 <= 7'd0;
        processor_in3 <= 7'd0; processor_in4 <= 7'd0;
        processor_in5 <= 7'd0; processor_in6 <= 7'd0;
        processor_in7 <= 7'd0; processor_in8 <= 7'd0;
    end
    else begin
        processor_in1 <= pin1_nxt; processor_in2 <= pin2_nxt;
        processor_in3 <= pin3_nxt; processor_in4 <= pin4_nxt;
        processor_in5 <= pin5_nxt; processor_in6 <= pin6_nxt;
        processor_in7 <= pin7_nxt; processor_in8 <= pin8_nxt;
    end
end

// ------------------------------------------------------------
// tex function  unchanged from original
// ------------------------------------------------------------
function automatic [6:0] tex;
input  [2:0] k;
input  [2:0] s;
input  [2:0] patch_size;
input  [5:0] residues;
input  [7:0] pixel_in;

reg [6:0] j;
reg [5:0] t;
reg [3:0] T;
reg [2:0] idx0, idx1, idx2, idx3, idx4, idx5, idx6;

begin
    t = 1 + k*s;
    T = (t > 6'd8) ? {3'b000, t[2:0]} : t;
    idx0 = (T - 1) & 3'b111;
    idx1 = (T    ) & 3'b111;
    idx2 = (T + 1) & 3'b111;
    idx3 = (T + 2) & 3'b111;
    idx4 = (T + 3) & 3'b111;
    idx5 = (T + 4) & 3'b111;
    idx6 = (T + 5) & 3'b111;

    if (patch_size == 3) begin
        j[0] = (T == 7)  ? residues[1] : (T == 8)  ? residues[0] : pixel_in[idx0];
        j[1] = ((T+1) == 8) ? residues[0] : pixel_in[idx1];
        j[2] = pixel_in[idx2];
        j[3] = 1'b0; j[4] = 1'b0; j[5] = 1'b0; j[6] = 1'b0;
    end
    else if (patch_size == 5) begin
        j[0] = (T==5)?residues[3]:(T==6)?residues[2]:(T==7)?residues[1]:(T==8)?residues[0]:pixel_in[idx0];
        j[1] = ((T+1)==6)?residues[2]:((T+1)==7)?residues[1]:((T+1)==8)?residues[0]:pixel_in[idx1];
        j[2] = ((T+2)==7)?residues[1]:((T+2)==8)?residues[0]:pixel_in[idx2];
        j[3] = ((T+3)==8)?residues[0]:pixel_in[idx3];
        j[4] = pixel_in[idx4];
        j[5] = 1'b0; j[6] = 1'b0;
    end
    else if (patch_size == 7) begin
        j[0] = (T==3)?residues[5]:(T==4)?residues[4]:(T==5)?residues[3]:(T==6)?residues[2]:(T==7)?residues[1]:(T==8)?residues[0]:pixel_in[idx0];
        j[1] = ((T+1)==4)?residues[4]:((T+1)==5)?residues[3]:((T+1)==6)?residues[2]:((T+1)==7)?residues[1]:((T+1)==8)?residues[0]:pixel_in[idx1];
        j[2] = ((T+2)==5)?residues[3]:((T+2)==6)?residues[2]:((T+2)==7)?residues[1]:((T+2)==8)?residues[0]:pixel_in[idx2];
        j[3] = ((T+3)==6)?residues[2]:((T+3)==7)?residues[1]:((T+3)==8)?residues[0]:pixel_in[idx3];
        j[4] = ((T+4)==7)?residues[1]:((T+4)==8)?residues[0]:pixel_in[idx4];
        j[5] = ((T+5)==8)?residues[0]:pixel_in[idx5];
        j[6] = pixel_in[idx6];
    end
    else begin
        j = 7'b0;
    end
    tex = j;
end
endfunction

endmodule
