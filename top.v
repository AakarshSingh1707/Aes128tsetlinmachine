`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: top
// Description: Top module connecting buffer, remapunit, convolution units, etc.
//
// FIX (MAP-2 preset FFs)  two changes in async reset branch only:
//
//   1. clause_no: async reset 1 ? 0
//      clause_no is only used after img_load_done, by which time the
//      synchronous reset (reset branch) has already set it to 1.
//      Functional impact: NONE.
//
//   2. max_sum: async reset -1000 ? 18'sh0
//      -1000 in 18-bit signed = 18'b11_1111_0000_0001_1000  many bits are 1,
//      requiring preset FFs. The synchronous reset branch still sets it to
//      -1000 (implemented as data mux logic, not preset pin). Functional
//      impact: NONE  max_sum is only read during done_conv_long which only
//      asserts after the synchronous reset has completed.
//
//   All synchronous reset branches (if (reset) ...) are UNCHANGED.
//////////////////////////////////////////////////////////////////////////////////

module top#(
    parameter WIDTH = 28, 
            HEIGHT = 28, 				
            CLAUSEN = 10,
            CLASSN = 10,
            CLAUSE_WIDTH = (35 + HEIGHT + WIDTH)*2
)
(
    input clk,
    input img_rst, i_rst_n,
    input [2:0] patch_size,
    input [2:0] stride,
    input [7:0] clauses,
    input [255:0] clause_write,
    input [7:0] pe_en,
    input [7:0] bram_addr_a2,
    input [255:0] weight_write,
    input done_rmu,
    input [6:0] processor_in1,processor_in2,processor_in3,processor_in4,processor_in5,processor_in6,processor_in7,processor_in8,
    input [HEIGHT - 1:0] p1y1,p2y1,p3y1,p4y1,p5y1,p6y1,p7y1,p8y1,
    input [WIDTH - 1:0] p1x1,
    input wea, wea2,
    input [7:0] bram_addr_a,
    input clause_act,
    output reg [$clog2(CLASSN)-1:0] class_op,
    output reg done,
    output wire pre_reset
);       
    wire [CLAUSEN - 1:0] clause_op;     
    reg signed [17:0] temp_sum[CLASSN-1:0];
    wire reset, done_conv;
    wire [2:0] patch_size_op [CLAUSEN : 0];
    wire [2:0] stride_op [CLAUSEN : 0];
    
    wire [0:CLAUSEN-1] done_conv_arch;
    wire [6:0] processor_out [1: CLAUSEN][0:7];
    wire [WIDTH-1:0] po_x1 [1:CLAUSEN];
    wire [7:0] pe_en_out [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y1 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y2 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y3 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y4 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y5 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y6 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y7 [1:CLAUSEN];
    wire [HEIGHT-1:0] po_y8 [1:CLAUSEN];
    wire clause_done [1:CLAUSEN];
    wire signed [8:0] weight[CLASSN - 1:0];
    reg [$clog2(CLAUSEN)-1:0] clause_no;
    reg ip_done_reg;
    reg signed [17:0] max_sum;      
    reg [$clog2(CLASSN):0] cnt;
    reg should_add;
    reg signed [8:0] weight_snapshot [CLASSN-1:0];
    reg done_conv_long;
    reg [$clog2(CLAUSEN):0] clause_idx;
    reg done_bit_r;
    reg op_bit_r;
    reg should_add_r;
    reg should_add_d;
    reg [4:0] cnt_nxt;          // keep same width as original cnt

    reg signed [18:0] add_result [0:CLASSN-1];
    integer m, jdx, kdx, ldx;

    assign patch_size_op[0] = patch_size;
    assign stride_op[0]     = stride;
    assign reset     = wea || wea2 || img_rst;
    assign done_conv = done_conv_arch[clauses-1];
    assign pre_reset = (cnt_nxt ==1); 

    // ------------------------------------------------------------
    // cnt, done_conv_long
    // ------------------------------------------------------------
reg done_conv_long_nxt;

/* Sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cnt            <= 0;
        done_conv_long <= 0;
    end
    else begin
        cnt            <= cnt_nxt;
        done_conv_long <= done_conv_long_nxt;
    end
end


/* Combinational next-state logic */
always @(*) begin
    // default hold
    cnt_nxt            = cnt;
    done_conv_long_nxt = done_conv_long;

    if (reset) begin
        cnt_nxt            = 0;
        done_conv_long_nxt = 0;
    end
    else begin
        if (done_conv) begin
            cnt_nxt            = CLASSN;
            done_conv_long_nxt = 1;
        end
        else if (cnt != 0) begin
            cnt_nxt            = cnt - 1;
            done_conv_long_nxt = 1;
        end
        else begin
            done_conv_long_nxt = 0;
        end
    end
end

    wire [CLAUSEN-1:0] clause_output;
    assign clause_output = clause_op;

    // ------------------------------------------------------------
    // clause_no, clause_idx, should_add, should_add_r, ip_done_reg,
    // should_add_d, done_bit_r, op_bit_r, weight_snapshot
    //
    // FIX (MAP-2): clause_no async reset changed from 1 to 0.
    // Sync reset (reset branch) still sets clause_no=1  UNCHANGED.
    // ------------------------------------------------------------
    /* next-state registers */
reg [$clog2(CLAUSEN):0] clause_no_nxt;
reg [$clog2(CLAUSEN):0] clause_idx_nxt;

reg should_add_nxt;
reg should_add_r_nxt;
reg should_add_d_nxt;
reg should_add_d2;

reg ip_done_reg_nxt;
reg done_bit_r_nxt;
reg op_bit_r_nxt;

reg signed [8:0] weight_snapshot_nxt [0:CLASSN-1];   // keep same width as original
reg signed [18:0] add_result_nxt [0:CLASSN-1];   // keep same width as original
reg [17:0] temp_sum_nxt [0:CLASSN-1];   // keep same width as original
reg signed [17:0] max_sum_nxt;
reg [31:0] kdx_nxt;
reg [$clog2(CLASSN)-1:0] class_op_nxt;
reg done_nxt;
integer fd;
integer i,b;


always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        clause_no    <= 0;
        clause_idx   <= 0;
        should_add   <= 0;
        should_add_r <= 0;
        ip_done_reg  <= 0;
        should_add_d <= 0;
        done_bit_r   <= 0;
        op_bit_r     <= 0;

        for (jdx = 0; jdx < CLASSN; jdx = jdx + 1)
            weight_snapshot[jdx] <= 0;
    end
    else begin
        clause_no    <= clause_no_nxt;
        clause_idx   <= clause_idx_nxt;
        should_add   <= should_add_nxt;
        should_add_r <= should_add_r_nxt;
        ip_done_reg  <= ip_done_reg_nxt;
        should_add_d <= should_add_d_nxt;
        done_bit_r   <= done_bit_r_nxt;
        op_bit_r     <= op_bit_r_nxt;

        for (jdx = 0; jdx < CLASSN; jdx = jdx + 1)
            weight_snapshot[jdx] <= weight_snapshot_nxt[jdx];
    end
end



/* combinational next-state logic */
always @(*) begin

    /* default hold */
    clause_no_nxt    = clause_no;
    clause_idx_nxt   = clause_idx;
    should_add_nxt   = should_add;
    should_add_r_nxt = should_add_r;
    should_add_d_nxt = should_add_d;
    ip_done_reg_nxt  = ip_done_reg;
    done_bit_r_nxt   = done_bit_r;
    op_bit_r_nxt     = op_bit_r;

    for (jdx = 0; jdx < CLASSN; jdx = jdx + 1)
        weight_snapshot_nxt[jdx] = weight_snapshot[jdx];


    if (reset) begin
        clause_no_nxt    = 1;   // preserved from original sync reset
        clause_idx_nxt   = 0;
        should_add_nxt   = 0;
        should_add_r_nxt = 0;
        ip_done_reg_nxt  = 0;
        should_add_d_nxt = 0;
        done_bit_r_nxt   = 0;
        op_bit_r_nxt     = 0;

        for (jdx = 0; jdx < CLASSN; jdx = jdx + 1)
            weight_snapshot_nxt[jdx] = 0;
    end
    else begin

        if (done_rmu)
            ip_done_reg_nxt = 1;

        clause_idx_nxt = clause_no;

        done_bit_r_nxt = done_conv_arch[clause_idx + 1];
        op_bit_r_nxt   = clause_op[clause_idx + 1];

        should_add_r_nxt = done_bit_r_nxt & op_bit_r_nxt;


        if (ip_done_reg) begin
            should_add_nxt   = should_add_r;
            should_add_d_nxt = should_add;

            for (jdx = 0; jdx < CLASSN; jdx = jdx + 1)
                weight_snapshot_nxt[jdx] = weight[jdx];

            clause_no_nxt = clause_no + 1;
        end
        else begin
            should_add_nxt = 0;
        end
    end
end
    // ------------------------------------------------------------
    // add_result
    // ------------------------------------------------------------
    /* next-state array */



/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            add_result[ldx] <= 0;
    end
    else begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            add_result[ldx] <= add_result_nxt[ldx];
    end
end
always @(posedge clk or negedge i_rst_n)begin
    if(!i_rst_n) should_add_d2 <= 1'b0;
    else should_add_d2 <= should_add_d;
end


/* combinational next-state logic */
always @(*) begin

    /* default hold */
    for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
        add_result_nxt[ldx] = add_result[ldx];

    if (reset) begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            add_result_nxt[ldx] = 0;
    end
    else begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1) begin
            if (should_add_d2)
                add_result_nxt[ldx] = temp_sum[ldx] + weight_snapshot[ldx];
        end
    end
end

    // ------------------------------------------------------------
    // temp_sum
    // ------------------------------------------------------------
   /* next-state array */


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            temp_sum[ldx] <= 0;
    end
    else begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            temp_sum[ldx] <= temp_sum_nxt[ldx];
    end
end

/* combinational next-state logic */
always @(*) begin

    /* default hold */
    for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
        temp_sum_nxt[ldx] = temp_sum[ldx];

    if (reset) begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            temp_sum_nxt[ldx] = 0;
    end
    else begin
        for (ldx = 0; ldx < CLASSN; ldx = ldx + 1)
            temp_sum_nxt[ldx] = add_result[ldx][17:0];
    end
end


   /* next-state registers */


/* sequential register update */
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        max_sum  <= 18'sh0;
        kdx      <= 0;
        class_op <= 0;
        done     <= 0;
    end
    else begin
        max_sum  <= max_sum_nxt;
        kdx      <= kdx_nxt;
        class_op <= class_op_nxt;
        done     <= done_nxt;
    end
end


/* combinational next-state logic */
always @(*) begin
    /* default hold */
    max_sum_nxt  = max_sum;
    kdx_nxt      = kdx;
    class_op_nxt = class_op;
    done_nxt     = done;

    if (reset) begin
        max_sum_nxt  = -18'sd1000;
        kdx_nxt      = 0;
        class_op_nxt = 0;
        done_nxt     = 0;
    end
    else if (done_conv_long) begin

        if (temp_sum[kdx] > max_sum) begin
            max_sum_nxt  = temp_sum[kdx];
            class_op_nxt = kdx;
        end

        if (kdx == CLASSN) begin
            done_nxt = 1'b1;
            kdx_nxt  = 0;
        end
        else begin
            kdx_nxt  = kdx + 1'b1;
            done_nxt = 1'b0;
        end
    end
end

    wire [2:0] baddr;  
    wire [5:0] baddrv;  
    wire [CLAUSEN - 1 : 0]valid;
    assign baddr = (bram_addr_a2 )% 5; // removed extra - 2
    assign baddrv = (bram_addr_a2)/ 5; // removed extra  - 2

    genvar id, idx;
    generate
    for (idx = 0; idx < CLASSN; idx = idx + 1) begin : wt_chain_pos
        weight_adder #(.CLAUSEN(CLAUSEN)) W (
            .clk(clk),
            .i_rst_n(i_rst_n),
            .valid(baddrv == idx),
            .offset(baddr),
            .clauses(clauses),
            .weight_write(weight_write),
            .clause_no(clause_no),
            .weight(weight[idx])
        );
    end
    endgenerate

    generate
    for (id = 0; id < CLAUSEN; id = id + 1) begin : conv_chain_pos
    assign valid[id] = id < clauses;
        if (id == 0 || id == 1) begin : conv_chain_exception
            conv_arch #(
                .IMG_WIDTH(WIDTH),
                .IMG_HEIGHT(HEIGHT),
                .CLAUSEN(CLAUSEN),
                .CLASSN(CLASSN),
                .CLAUSE_WIDTH(CLAUSE_WIDTH)
            ) C (
                .clk(clk),
                .i_rst_n(i_rst_n),
                .valid_sig(valid[id]),
                .img_rst(img_rst),
                .patch_size_out(patch_size_op[id + 1]),
                .ipdone(done_rmu),
                .opdone_reg(done_conv_arch[id]),
                .stride(stride),
                .stride_out(stride_op[id+1]),
                .pe_en(pe_en),
                .pe_en_out(pe_en_out[id+1]),
                .patch_size(patch_size),
                .valid(bram_addr_a == id ), // removed axtra + 2
                .clause_op(clause_op[id]),
                .clause_act(clause_act),
                .clause_write(clause_write),
                .prev_clause_op(clause_output[id]),
                .clause_done(clause_done[id+1]),
                .processor_in1(processor_in1),
                .processor_in2(processor_in2),
                .processor_in3(processor_in3),
                .processor_in4(processor_in4),
                .processor_in5(processor_in5),
                .processor_in6(processor_in6),
                .processor_in7(processor_in7),
                .processor_in8(processor_in8),
                .p1y1(p1y1),
                .p1x1(p1x1),
                .p2y1(p2y1),
                .p3y1(p3y1),
                .p4y1(p4y1),
                .p5y1(p5y1),
                .p6y1(p6y1),
                .p7y1(p7y1),
                .p8y1(p8y1),
                .processor_out1(processor_out[id+1][0]),
                .processor_out2(processor_out[id+1][1]),
                .processor_out3(processor_out[id+1][2]),
                .processor_out4(processor_out[id+1][3]),
                .processor_out5(processor_out[id+1][4]),
                .processor_out6(processor_out[id+1][5]),
                .processor_out7(processor_out[id+1][6]),
                .processor_out8(processor_out[id+1][7]),
                .po1x(po_x1[id+1]),
                .po1y(po_y1[id+1]),
                .po2y(po_y2[id+1]),
                .po3y(po_y3[id+1]),
                .po4y(po_y4[id+1]),
                .po5y(po_y5[id+1]),
                .po6y(po_y6[id+1]),
                .po7y(po_y7[id+1]),
                .po8y(po_y8[id+1])
            );
        end
        else begin : conv_chain_general
            conv_arch #(
                .IMG_WIDTH(WIDTH),
                .IMG_HEIGHT(HEIGHT),
                .CLAUSEN(CLAUSEN),
                .CLASSN(CLASSN),
                .CLAUSE_WIDTH(CLAUSE_WIDTH)
            ) C (
                .clk(clk),
                .i_rst_n(i_rst_n),
                .valid_sig(valid[id]),
                .img_rst(img_rst),
                .stride(stride_op[id]),
                .pe_en(pe_en_out[id]),
                .patch_size_out(patch_size_op[id + 1]),
                .pe_en_out(pe_en_out[id+1]),
                .stride_out(stride_op[id+1]),
                .ipdone(done_conv_arch[id-1]),
                .opdone_reg(done_conv_arch[id]),
                .patch_size(patch_size_op[id]),
                .valid(bram_addr_a == id), // removed extra +2
                .clause_write(clause_write),
                .clause_op(clause_op[id]),
                .clause_act(clause_done[id]),
                .clause_done(clause_done[id+1]),
                .prev_clause_op(clause_output[id]),
                .processor_in1(processor_out[id][0]),
                .processor_in2(processor_out[id][1]),
                .processor_in3(processor_out[id][2]),
                .processor_in4(processor_out[id][3]),
                .processor_in5(processor_out[id][4]),
                .processor_in6(processor_out[id][5]),
                .processor_in7(processor_out[id][6]),
                .processor_in8(processor_out[id][7]),
                .p1y1(po_y1[id]),
                .p1x1(po_x1[id]),
                .p2y1(po_y2[id]),
                .p3y1(po_y3[id]),
                .p4y1(po_y4[id]),
                .p5y1(po_y5[id]),
                .p6y1(po_y6[id]),
                .p7y1(po_y7[id]),
                .p8y1(po_y8[id]),
                .processor_out1(processor_out[id+1][0]),
                .processor_out2(processor_out[id+1][1]),
                .processor_out3(processor_out[id+1][2]),
                .processor_out4(processor_out[id+1][3]),
                .processor_out5(processor_out[id+1][4]),
                .processor_out6(processor_out[id+1][5]),
                .processor_out7(processor_out[id+1][6]),
                .processor_out8(processor_out[id+1][7]),
                .po1x(po_x1[id+1]),
                .po1y(po_y1[id+1]),
                .po2y(po_y2[id+1]),
                .po3y(po_y3[id+1]),
                .po4y(po_y4[id+1]),
                .po5y(po_y5[id+1]),
                .po6y(po_y6[id+1]),
                .po7y(po_y7[id+1]),
                .po8y(po_y8[id+1])
            );
        end
    end
    endgenerate

endmodule
