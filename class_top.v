`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.07.2025 18:30:22
// Design Name: 
// Module Name: class_top
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

module class_top#(
    parameter CLAUSEN = 140,
    CLASSN = 10,
    HEIGHT = 28,
    WIDTH  = 28,
    CLAUSE_WIDTH = (35 + HEIGHT + WIDTH)*2
)(  
    input clk,
    input i_rst_n,
    input init_done,
    input [31:0] tdata,
    input [17:0] model_params,
    input [6:0] x_w,
    input [255:0]clause_write,
    input [255:0]weight_write,
    input [1:0] resetessen,
    output reg [7:0] bram_addr_a,
    output reg [7:0] bram_addr_a2,
    output reg  [3:0] output_params,
    output reg tready
);
    wire img_rst;
    reg [6:0] x; // find x_w
    wire img_done_wire;
    wire [31:0] total_img;
    wire [2:0] stride;
    reg [3:0] class_op;
    wire [3:0] class_op_wire;
    wire wea, wea2;
    wire [7:0] bram_addr_a_wire;
    wire [7:0] bram_addr_a2_wire;
    reg [((HEIGHT + 8)*WIDTH)-1:0] total_memory;
    wire [7:0] clause;
    reg [7:0] img_bram;
    wire [7:0] clause2;
    reg img_load_done;
    integer i, j, k, l;
    wire done_rmu;
    genvar idx;
    wire clause_act;
    reg [5:0] cycle_count;
    reg shift_enable;
    wire [7:0] pixel_out;
    wire img_done;
    wire [3:0] classes;
    reg [7:0] pixel_in;
    wire [7:2] residues_buf;
    wire [7:2] residues_rmu;
    wire [$clog2(WIDTH + 2):0] img_width_count;
    wire [7:0] pe_en;
    wire [7:0] weight_limit;
    wire reset;
    wire [2:0] patch_size;
    wire [6:0] processor_in1,processor_in2,processor_in3,processor_in4,processor_in5,processor_in6,processor_in7,processor_in8;
    wire [WIDTH - 1:0] p1x1;
    wire [HEIGHT - 1:0] p1y1,p2y1,p3y1,p4y1,p5y1,p6y1,p7y1,p8y1;
    genvar b;
    wire cycle_change;
    wire [4:0] img_wide;
    
    assign img_wide    = WIDTH;
    assign bram_img_addr_w = img_bram;
    assign clause      = model_params[13:6];
    assign rstb = i_rst_n;
    assign clause2 = clause ;
    assign classes     = model_params[17:14];
    assign img_rst     =  img_done_wire ; // i have changed it; after OR;
    assign total_img   = tdata;
    assign patch_size  = model_params[2:0];
    assign stride      = model_params[5:3];
    //assign reset       = wea || !img_load_done || wea2; // one more time i ave to see
    assign reset       =  resetessen[1] || resetessen[0];
    assign img_done    = img_done_wire ;
  //  assign img_done    = img_done_wire 
    reg [9:0] addr0,addr1,addr2,addr3,addr4,addr5,addr6,addr7;
    reg valid_addr;
    assign bram_addr_a_wire  = bram_addr_a;
    assign bram_addr_a2_wire = bram_addr_a2;
    assign weight_limit = classes * 5 ;
    reg p0,p1,p2,p3,p4,p5,p6,p7;
    reg [14:0] bram_addr_a_nxt;
    reg [14:0] bram_addr_a2_nxt;
    reg [5:0] img_count;
    reg [7:0] img_bram_nxt;
    reg [5:0] img_count_nxt; 

    // finding img_load_done
    
    reg [9:0] addr0_nxt, addr1_nxt, addr2_nxt, addr3_nxt;
    reg [9:0] addr4_nxt, addr5_nxt, addr6_nxt, addr7_nxt;
    reg valid_addr_nxt;
    
    reg p0_nxt,p1_nxt,p2_nxt,p3_nxt;
    reg p4_nxt,p5_nxt,p6_nxt,p7_nxt;

    reg [7:0] pixel_in_nxt;
    reg shift_enable_nxt;
    
    always @(posedge clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            bram_addr_a  <= 0;
            x <= 0;
            img_bram <= 0;
            bram_addr_a2 <= 0;
            img_count <= 0;
        end
        else begin
               img_bram <= img_bram_nxt;
               img_count <= img_count_nxt;
               bram_addr_a  <= bram_addr_a_nxt;
               bram_addr_a2 <= bram_addr_a2_nxt;
               x <= x_w;
             end
    end

    assign wea         = init_done ? (bram_addr_a  < {{6{1'b0}}, clause2}) : 1'b0;
    assign wea2        = init_done ? (bram_addr_a2 < weight_limit) : 1'b0;
    always @(*) begin
                    bram_addr_a2_nxt = wea2 ? bram_addr_a2 + 1 : bram_addr_a2;
                    bram_addr_a_nxt  = wea  ? bram_addr_a  + 1 : bram_addr_a;          
                    img_bram_nxt = (img_count << 5) + x;
                    img_count_nxt = img_count + img_done; 
    end
    
    // Buffer instantiation
    my_buffer #(.BUF_WIDTH(WIDTH+2)) Buf(
        .clk(clk),
        .rst(reset),
         .i_rst_n(i_rst_n),
        .pixel_in(pixel_in),
        .shift_enable(shift_enable),
        .done(1'b0),
        .img_width(img_wide),
        .pixel_out(pixel_out),
        .residues(residues_buf),
        .cycle_change(cycle_change),
        .img_width_count(img_width_count)
    );

    // Reversing residues
    generate
        for (b = 2; b < 8; b = b + 1) begin: reverse_loop
            assign residues_rmu[b] = residues_buf[9 - b];
        end
    endgenerate

    // Remap unit instantiation
    remapunit #(
        .IMG_WIDTH(WIDTH),
        .IMG_HEIGHT(HEIGHT)
    ) R (
        .clk(clk),
        .i_rst_n(i_rst_n),
        .rst(reset),
        .patch_size(patch_size),
        .stride(stride),
        .done(done_rmu),
        .xcor1(img_width_count),
        .pixel_in(pixel_out),
        .residues(residues_rmu),
        .cycle_counts(cycle_count),
        .cycle_detect(cycle_change),
        .processor_in1(processor_in1), .processor_in2(processor_in2),
        .processor_in3(processor_in3), .processor_in4(processor_in4),
        .processor_in5(processor_in5), .processor_in6(processor_in6),
        .processor_in7(processor_in7), .processor_in8(processor_in8),
        .p_en(pe_en),
        .p1y1(p1y1), .p1x1(p1x1), .p2y1(p2y1), .p3y1(p3y1), .p4y1(p4y1),
        .p5y1(p5y1), .p6y1(p6y1), .p7y1(p7y1), .p8y1(p8y1),
        .clause_act(clause_act)
    );
    
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        addr0 <= 0; addr1 <= 0; addr2 <= 0; addr3 <= 0;
        addr4 <= 0; addr5 <= 0; addr6 <= 0; addr7 <= 0;
        valid_addr <= 0;
    end
    else begin
        addr0 <= addr0_nxt; addr1 <= addr1_nxt;
        addr2 <= addr2_nxt; addr3 <= addr3_nxt;
        addr4 <= addr4_nxt; addr5 <= addr5_nxt;
        addr6 <= addr6_nxt; addr7 <= addr7_nxt;
        valid_addr <= valid_addr_nxt;
    end
end

always @(*) begin
    addr0_nxt = addr0; addr1_nxt = addr1;
    addr2_nxt = addr2; addr3_nxt = addr3;
    addr4_nxt = addr4; addr5_nxt = addr5;
    addr6_nxt = addr6; addr7_nxt = addr7;
    valid_addr_nxt = valid_addr;

    if (reset) begin
        addr0_nxt = 0; addr1_nxt = 0; addr2_nxt = 0; addr3_nxt = 0;
        addr4_nxt = 0; addr5_nxt = 0; addr6_nxt = 0; addr7_nxt = 0;
        valid_addr_nxt = 0;
    end
    else begin
        addr0_nxt = (j+0)*WIDTH + k;
        addr1_nxt = (j+1)*WIDTH + k;
        addr2_nxt = (j+2)*WIDTH + k;
        addr3_nxt = (j+3)*WIDTH + k;
        addr4_nxt = (j+4)*WIDTH + k;
        addr5_nxt = (j+5)*WIDTH + k;
        addr6_nxt = (j+6)*WIDTH + k;
        addr7_nxt = (j+7)*WIDTH + k;
        valid_addr_nxt = ((j*WIDTH)+k < WIDTH*HEIGHT);
    end
end


always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        p0<=0; p1<=0; p2<=0; p3<=0;
        p4<=0; p5<=0; p6<=0; p7<=0;
    end
    else begin
        p0<=p0_nxt; p1<=p1_nxt; p2<=p2_nxt; p3<=p3_nxt;
        p4<=p4_nxt; p5<=p5_nxt; p6<=p6_nxt; p7<=p7_nxt;
    end
 end

always @(*) begin
    p0_nxt=p0; p1_nxt=p1; p2_nxt=p2; p3_nxt=p3;
    p4_nxt=p4; p5_nxt=p5; p6_nxt=p6; p7_nxt=p7;

    if (reset) begin
        p0_nxt=0; p1_nxt=0; p2_nxt=0; p3_nxt=0;
        p4_nxt=0; p5_nxt=0; p6_nxt=0; p7_nxt=0;
    end
    else begin
        if (valid_addr) begin
            p0_nxt = total_memory[addr0];
            p1_nxt = total_memory[addr1];
            p2_nxt = total_memory[addr2];
            p3_nxt = total_memory[addr3];
            p4_nxt = total_memory[addr4];
            p5_nxt = total_memory[addr5];
            p6_nxt = total_memory[addr6];
            p7_nxt = total_memory[addr7];
        end
        else begin
            p0_nxt=1'b0; p1_nxt=1'b0; p2_nxt=1'b0; p3_nxt=1'b0;
            p4_nxt=1'b0; p5_nxt=1'b0; p6_nxt=1'b0; p7_nxt=1'b0;
        end
    end
 end

    
always @(posedge clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        pixel_in     <= 0;
        shift_enable <= 0;
    end
    else begin
        pixel_in     <= pixel_in_nxt;
        shift_enable <= shift_enable_nxt;
    end
end

always @(*) begin
    pixel_in_nxt     = pixel_in;
    shift_enable_nxt = shift_enable;

    if (reset) begin
        pixel_in_nxt     = 0;
        shift_enable_nxt = 0;
    end
    else if (!cycle_change) begin
        shift_enable_nxt = 1;

        if (valid_addr)
            pixel_in_nxt = {p7,p6,p5,p4,p3,p2,p1,p0};
        else
            pixel_in_nxt = 0;
    end
    else begin
        shift_enable_nxt = 1;
    end
end



    always @(posedge clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tready        <= 0;
            output_params <= 0;
            img_load_done <= 0;
            cycle_count   <= 6'b1;    // FIX 2: was 1 (preset FF on bit[0]), now 0
            k             <= 0;
            j             <= 0;
            class_op      <= 0;
            total_memory  <= 0;
        end
        else begin
        /*    if (rst) begin
                tready        <= 0;
                output_params <= 0;
                x             <= 6'sd0;   // FIX 1: was -2, now 0
                img_load_done <= 0;
                cycle_count   <= 1;       // sync reset keeps cycle_count=1 (UNCHANGED)
                k             <= 0;
                j             <= 0;
                class_op      <= 0;
                total_memory  <= 0;
            end
            else begin */
             tready <= img_done_wire;
                if (img_rst) begin
                 //   tready        <= 0; right now commented
                    img_load_done <= 0;
                end
                else begin
                    //tready   <= !img_load_done && !wea && !wea2;
                    //tready <= !img_load_done;
                    // tready <= img_done_wire; moving tready up
                    class_op <= class_op_wire;

                    
                    if (!(img_rst || img_load_done || wea || wea2)) begin
                        for (i = 0; i < 32; i = i + 1) begin
                            total_memory[((x) << 5) + i] <= total_img[i];
                        end
                    end
                    if (x == 7'd32) begin
                        img_load_done <= 1;
                      //  tready        <= 0; moving up
                    end
                     if (resetessen[0]) begin
                        img_load_done <= 0;
                      //  tready        <= 0; moving up
                    end

                    if (!reset && !cycle_change) begin
                        k <= k + 1;
                    end
                    else if (cycle_change && !reset) begin
                        j           <= j + 8;
                        k           <= 0;
                        cycle_count <= cycle_count + 1;
                    end
                    else begin
                        j           <= 0;
                        k           <= 0;
                        cycle_count <= 1;
                    end
                end

                if (img_done_wire) output_params <= class_op;
                else               output_params <= output_params;
            end
    end

    // Convolution Engine instantiation
    top #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .CLAUSEN(CLAUSEN),
        .CLASSN(CLASSN),
        .CLAUSE_WIDTH(CLAUSE_WIDTH)
    ) T (
        .clk(clk),
        .i_rst_n(i_rst_n),
        .img_rst(img_rst),
        .patch_size(patch_size),
        .stride(stride),
        .wea(wea),
        .bram_addr_a(bram_addr_a_wire),
        .clause_write(clause_write),
        .pe_en(pe_en),
        .clauses(clause),
        .weight_write(weight_write),
        .wea2(wea2),
        .bram_addr_a2(bram_addr_a2_wire),
        .clause_act(clause_act),
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
        .done(img_done_wire),
        .class_op(class_op_wire),
        .done_rmu(done_rmu)
    );

endmodule

