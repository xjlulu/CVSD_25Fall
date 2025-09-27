module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,

    input                      i_in_valid,
    output reg                 o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,

    output reg                 o_out_valid,
    output reg    [DATA_W-1:0] o_data
);
/******************************************* Parameters ********************************************/
parameter ADD    = 4'b0000; // o_data = i_data_a + i_data_b
parameter SUB    = 4'b0001; // o_data = i_data_a - i_data_b
parameter MAC    = 4'b0010; // o_data = i_data_a * i_data_b + data_acc_old
parameter SIN    = 4'b0011; // o_data = Σ(n=0)^2 (-1)^n * (i_data_a)^(2n+1) / (2n+1)!
parameter GRAY   = 4'b0100; // Encode the gray code result
parameter LRCW   = 4'b0101; // Encode the CPOP result
parameter ROT    = 4'b0110; // Rotate i_data_a right by i_data_b bits
parameter CLZ    = 4'b0111; // Count leading 0's in i_data_a
parameter RM4    = 4'b1000; // Custom bit-level operation
parameter TRANS  = 4'b1001; // Transpose an 8*8 matrix

parameter MAX_VAL = {1'b0, {(DATA_W-1){1'b1}}};
parameter MIN_VAL = {1'b1, {(DATA_W-1){1'b0}}};
parameter FINAL_TRANS_COUNT  = 8;
parameter CNT_W  = 4;

/******************************************* Internal Signals ****************************************/
reg                 in_valid_reg;
reg [INST_W-1:0]    inst_reg_1, inst_reg_2;
reg [DATA_W-1:0]    a_reg, b_reg, ab_reg, data_acc;
reg [CNT_W-1:0]     rot_count;
reg [CNT_W-1:0]     clz_count;
reg [CNT_W-1:0]     trans_count;
reg [DATA_W-1:0]    rot_out;

wire is_final_rot_count     = ((rot_count == b_reg[CNT_W-1:0]) || (b_reg[CNT_W-1:0] == 4'd0)) && (inst_reg_1 == ROT);
wire is_final_clz_count     = ((a_reg[15-clz_count] == 1'b1) || (clz_count == 4'd15) || (a_reg[DATA_W-1:0] == 16'd0)) && (inst_reg_1 == CLZ);
wire is_finalm1_trans_count = trans_count == FINAL_TRANS_COUNT - 1;
wire is_final_trans_count   = trans_count == FINAL_TRANS_COUNT;
wire trans_ready            = i_inst == TRANS && i_in_valid && is_finalm1_trans_count && !o_busy;
wire o_data_update_add      = (inst_reg_1 == ADD  || inst_reg_1 == SUB) && in_valid_reg;
wire o_data_update_mac      = (inst_reg_1 == MAC  ) && in_valid_reg;
wire o_data_update_gray     = (inst_reg_1 == GRAY ) && in_valid_reg;
wire o_data_update_rm4      = (inst_reg_1 == RM4  ) && in_valid_reg;
wire o_data_update_rot      = (inst_reg_1 == ROT  ) && (is_final_rot_count && o_busy);
wire o_data_update_clz      = (inst_reg_1 == CLZ  ) && (is_final_clz_count && o_busy);
wire o_data_update_trans    = (inst_reg_2 == TRANS) && !is_final_trans_count && o_busy;
wire o_data_update          = o_data_update_add || o_data_update_mac || o_data_update_gray || o_data_update_rm4 || o_data_update_rot || o_data_update_clz || o_data_update_trans;
wire rot_start              = !o_busy && i_in_valid && (i_inst == ROT  );
wire clz_start              = !o_busy && i_in_valid && (i_inst == CLZ  );
wire trans_start            = !o_busy && i_in_valid && (i_inst == TRANS);
wire matrix_out_update      =  o_busy && (inst_reg_2 == TRANS);
wire rot_done               = is_final_rot_count;
wire clz_done               = is_final_clz_count;
wire trans_done             = is_final_trans_count && o_busy;
wire data_acc_update        = o_data_update_mac;

/******************************************* ALU core ***********************************************/

/******************************************* ALU core ***********************************************/
wire [DATA_W-1:0]   add_in_a = a_reg;
wire [DATA_W-1:0]   macadd_in_a = data_acc;
wire [DATA_W-1:0]   add_in_b = (inst_reg_1 == SUB) ? twos_complement(b_reg) : b_reg;
wire [DATA_W-1:0]   macadd_in_b = ab_reg;

wire                a_sign   = add_in_a[DATA_W-1];
wire                b_sign   = add_in_b[DATA_W-1];
wire                sign_eq  = (a_sign == b_sign);
wire [DATA_W:0]     sum      = add_in_a + add_in_b;
wire                overflow = (sum[DATA_W] ^ sum[DATA_W - 1]) && sign_eq;
wire [DATA_W-1:0]   add_out  = (!overflow) ? sum[DATA_W-1:0]
                                           : (a_sign ? MIN_VAL : MAX_VAL);

/******************************************* ALU:MAC ******************************************/
wire [DATA_W-1:0] comp_i_data_a  = twos_complement(i_data_a);
wire [DATA_W-1:0] comp_i_data_b  = twos_complement(i_data_b);
wire [DATA_W-1:0] mult_in_a      = (i_data_a[DATA_W-1]) ? comp_i_data_a : i_data_a;
wire [DATA_W-1:0] mult_in_b      = (i_data_b[DATA_W-1]) ? comp_i_data_b : i_data_b;
wire [2*DATA_W-1:0] mult_full    = (mult_in_a * mult_in_b);
wire [DATA_W:0]   mult_shift     = mult_full [DATA_W + FRAC_W - 1 : FRAC_W - 1];
wire [DATA_W-1:0] mult_out_round = mult_shift[DATA_W:1] + {{(DATA_W-1){1'b0}}, mult_shift[0]};
wire [DATA_W-1:0] ab_reg_in      = (i_data_a[DATA_W-1] ^ i_data_b[DATA_W-1]) ? twos_complement(mult_out_round) : mult_out_round;

wire [DATA_W-1:0] data_acc_in    = add_out;
//   b:1111110100100011
//  ib:0000001011011101
// abf:0000010010000110
//  ab:00000100100001100011001010
// iab:11111011011110011100110101
// 1111101101111010
// I1:  0000011001010010 1111110100100011
// g1:  1111101101111010
// g0:  
//ig0:  
// g1-g0:

// I2:  1000000100100000 1111110000101001
// g2:  0111010101000101
// g1:  1111101101111010
//ig1:  0000010010000110
// g2-g1:0111 1001 1100 1011 = result - 1

// I3:  00001110001110001101000101001111
// g3:  1100111101001100
// g2:  0111010101000101
//ig2:  1000101010111011
// g3-g2:1 0101 1010 0000 0111

// I4:  01011011110101000000001000001000
// g4:  1111110111101110
// g3:  1100111101001100
//ig3:  0011000010110100
// g4-g3:1 0010 1110 1010 0010

// I5:  11001011100101110000011000100110
// g5:  1010110101011110
// g4:  1111110111101110
//ig4:  0000001000010010
// g5-g4:    1010 1111 0111 0000 = result -1
//i(g5-g4):  0101 0000 1001 0000

// GRAY
// wire [DATA_W-1:0] axorb = a_reg ^ b_reg;

/******************************************* ALU:ROT ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_busy <= 1'b0;
    end
    else if (rot_start || clz_start || trans_ready) begin
        o_busy <= 1'b1;
    end
    else if (rot_done || clz_done || trans_done) begin
        o_busy <= 1'b0;
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        rot_out   <= {DATA_W{1'b0}};
    end
    else if (rot_start) begin
        rot_out <= i_data_a;
    end
    else if (o_busy) begin
        rot_out <= {rot_out[0], rot_out[DATA_W-1:1]};
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        rot_count <= {CNT_W{1'b0}};
    end
    else if (is_final_rot_count) begin
        rot_count <= {CNT_W{1'b0}};
    end
    else if (rot_start) begin
        rot_count <= {CNT_W{1'b0}};
    end
    else if (o_busy) begin
        rot_count <= rot_count + 1'b1;
    end
end

/******************************************* ALU:CLZ ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        clz_count <= {CNT_W{1'b0}};
    end
    else if (is_final_clz_count) begin
        clz_count <= {CNT_W{1'b0}};
    end
    else if (clz_start) begin
        clz_count <= {CNT_W{1'b0}};
    end
    else if (o_busy) begin
        clz_count <= clz_count + 1'b1;
    end
end


wire [DATA_W-1:0] clz_out = (a_reg == 16'b0) ? 16'd16 : {{(DATA_W-CNT_W){1'b0}}, clz_count};

/******************************************* ALU:GRAY ******************************************/
reg [DATA_W-1:0] gray_out;
always @(*) begin
    for (integer i = 0; i < DATA_W-1; i = i + 1) begin
        gray_out[i] = a_reg[i+1] ^ a_reg[i];
    end
    gray_out[DATA_W-1] = a_reg[DATA_W-1];
end

/******************************************* ALU:RM4 ******************************************/
// I8
reg [DATA_W-1:0] rm4_out;
always @(*) begin
    for (integer i = 0; i < 13; i = i + 1) begin
        rm4_out[i] = (a_reg[i+:4] == b_reg[15-i-:4]);
    end
    rm4_out[15:13] = 3'b0;
end

/******************************************* ALU:LRCW ******************************************/
wire [DATA_W-1:0] lrcw_out = grp16(a_reg, b_reg);

/******************************************* ALU:TRANS ******************************************/
// 將原 matrix 改為單一 reg
reg [127:0] matrix_flat; // 64*2 = 128 bits

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        matrix_flat <= 128'b0;
    end
    else if (trans_start) begin
        // shift up 每行 16 bits
        matrix_flat[0 +: 112] <= matrix_flat[16 +: 112]; // 上移 1 行
        // load new row 到最後一行
        for (integer j = 0; j < 8; j = j + 1) begin
            matrix_flat[112 + j*2 +: 2] <= i_data_a[j*2 +: 2];
        end
    end
    else if (matrix_out_update) begin
        // shift left 每列 2 bits
        for (integer i = 0; i < 8; i = i + 1) begin
            matrix_flat[i*16 + 2 +: 14] <= matrix_flat[i*16 +: 14]; // 左移 1 列
            matrix_flat[i*16 +: 2] <= 2'b0; // 清最後一列
        end
    end
end

// trans_count 保持不變
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        trans_count <= 4'b0;
    end
    else if (inst_reg_2 == TRANS && is_final_trans_count && o_busy) begin
        trans_count <= 4'b0;
    end
    else if (trans_ready) begin
        trans_count <= 4'd0;
    end
    else if (trans_start) begin
        trans_count <= trans_count + 1'b1;
    end
    else if (o_busy && !is_final_trans_count && inst_reg_2 == TRANS) begin
        trans_count <= trans_count + 1'b1;
    end
end

// 組合輸出
reg [DATA_W-1:0] trans_out;
always @(*) begin
    for (integer i = 0; i < 8; i = i + 1) begin
        trans_out[i*2 +: 2] = matrix_flat[(127-i*16) -: 2]; // 取每行第一列
    end
end
// reg [1:0] matrix [7:0][7:0];
// wire trans_start = !o_busy && i_in_valid && i_inst == TRANS;

// always @(posedge i_clk or negedge i_rst_n) begin
//     if (!i_rst_n) begin
//         for (integer i = 0; i < 8; i = i + 1) begin
//             for (integer j = 0; j < 8; j = j + 1) begin
//                 matrix[i][j] <= 2'b0;
//             end
//         end
//     end
//     else if (trans_start) begin
//         for (integer i = 0; i < 7; i = i + 1) begin
//             for (integer j = 0; j < 8; j = j + 1) begin
//                 matrix[i][j] <= matrix[i+1][j];
//             end
//         end
//         for (integer j = 0; j < 8; j = j + 1) begin
//             matrix[7][j] <= i_data_a[j*2 +: 2]; 
//         end
//     end
//     else if (o_busy) begin
//         for (integer j = 0; j < 7; j = j + 1) begin
//             for (integer i = 0; i < 8; i = i + 1) begin
//                 matrix[i][j] <= matrix[i][j+1];
//             end
//         end
//         for (integer j = 0; j < 8; j = j + 1) begin
//             matrix[7][j] <= 2'b0;
//         end
//     end
// end

// always @(posedge i_clk or negedge i_rst_n) begin
//     if (!i_rst_n) begin
//         trans_count <= {4{1'b0}};
//     end
//     else if (is_final_trans_count) begin
//         trans_count <= {4{1'b0}};
//     end
//     else if (trans_start) begin
//         trans_count <= trans_count + 1'b1;
//     end
//     else if (o_busy) begin
//         trans_count <= trans_count + 1'b1;
//     end
// end
// // wire [DATA_W-1:0] trans_out = {matrix[0][0], matrix[1][0], matrix[2][0], matrix[3][0], matrix[4][0], matrix[5][0], matrix[6][0], matrix[7][0]};
// reg [DATA_W-1:0] trans_out;
// always @(*) begin
//     for (integer i = 0; i < 8; i = i + 1) begin
//         trans_out[i*2+:2] = matrix[i][0];
//     end
// end

// input 1
// 10 01 11 01 01 00 01 00
// 10 01 11 10 11 01 10 10
// 10 10 01 01 00 10 01 11
// 01 11 00 00 01 00 10 11
// 10 10 11 11 10 00 00 00
// 11 11 01 00 01 01 00 10
// 11 11 11 00 10 00 10 00
// 00 00 11 00 10 00 00 01

// gold 1
// 10 10 10 01 10 11 11 00
// 01 01 10 11 10 11 11 00
// 11 11 01 00 11 01 11 11
// 01 10 01 00 11 00 00 00
// 01 11 00 01 10 01 10 10
// 00 01 10 00 00 01 00 00
// 01 10 01 10 00 00 10 00
// 00 10 11 11 00 10 00 01

// input 2
// 11 01 00 01 11 10 11 11
// 00 00 01 01 00 11 10 01
// 10 10 11 01 00 11 00 11
// 01 00 11 11 11 11 00 10
// 10 10 00 00 10 11 11 00
// 10 01 00 10 10 11 01 01
// 11 11 00 10 11 10 11 00
// 10 00 10 11 10 01 01 11

// gold 2
// 11 00 10 01 10 10 11 10
// 01 00 10 00 10 01 11 00
// 00 01 11 11 00 00 00 10
// 01 01 01 11 00 10 10 11
// 11 00 00 11 10 10 11 10
// 10 11 11 11 11 11 10 01
// 11 10 00 00 11 01 11 01
// 11 01 11 10 00 01 00 11

/******************************************* Control Logic ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_out_valid    <= 0;
    end
    else if (o_data_update) begin
        o_out_valid    <= 1'b1;
    end
    else begin
        o_out_valid    <= 1'b0;
    end
end 
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        a_reg          <= 0;
        b_reg          <= 0;
        inst_reg_1     <= 0;
        in_valid_reg   <= 0;
    end
    else begin
        if (!o_busy) begin
            in_valid_reg     <= i_in_valid;
        end
        else if (o_data_update) begin
            in_valid_reg     <= i_in_valid;
        end

        if (o_busy) begin
            inst_reg_1   <= inst_reg_1;
            a_reg        <= a_reg;
            b_reg        <= b_reg;
        end
        else if (!o_busy && i_in_valid) begin
            inst_reg_1   <= i_inst;
            a_reg        <= i_data_a;
            b_reg        <= i_data_b;
        end
        if (o_busy) begin
            inst_reg_2   <= inst_reg_2;
        end
        else if (trans_ready) begin
            inst_reg_2   <= i_inst;
        end
        else if (!o_busy && in_valid_reg) begin
            inst_reg_2   <= inst_reg_1;
        end
        else begin
            inst_reg_2 <= {INST_W{1'b0}};
        end
    end
end



always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_acc     <= 16'b0;
    end
    else if(data_acc_update) begin
        data_acc     <= data_acc_in;
    end
    else begin
        data_acc     <= data_acc;
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        ab_reg       <= 16'b0;
    end
    else if(i_in_valid) begin
        ab_reg       <= ab_reg_in;
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_data     <= 0;
    end
    else if (o_data_update) begin
        if(inst_reg_1 == ADD || inst_reg_1 == SUB) begin
            o_data     <= add_out;
        end
        else if(inst_reg_1 == MAC) begin
            o_data     <= data_acc_in;
        end
        else if(inst_reg_1 == SIN) begin
            o_data     <= add_out;
        end
        else if(inst_reg_1 == GRAY) begin
            o_data     <= gray_out;
        end
        else if(inst_reg_1 == LRCW) begin
            o_data     <= lrcw_out;
        end
        else if(inst_reg_1 == ROT) begin
            o_data     <= rot_out;
        end
        else if(inst_reg_1 == CLZ) begin
            o_data     <= clz_out;
        end
        else if(inst_reg_1 == RM4) begin
            o_data     <= rm4_out;
        end
        else if(inst_reg_1 == TRANS) begin
            o_data     <= trans_out;
        end
        else begin
            o_data     <= 0;
        end
    end
end

/******************************************* Output Signal ******************************************/

/******************************************* ALU Function ******************************************/
// compute the two's complement of a signed number
function signed [DATA_W-1:0] twos_complement (
    input signed [DATA_W-1:0] in_data
);
    twos_complement = ~in_data + 1;
endfunction

function [15:0] grp16;
    input [15:0] grp_a_reg;  // data word
    input [15:0] grp_b_reg;  // control word
    integer left_pos, right_pos;
    reg [15:0] temp;
begin
    left_pos  = 0;      //(LSB -> MSB)
    right_pos = 15;     //(MSB -> LSB)
    temp      = 16'b0;

    for (integer i=0; i<16; i=i+1) begin
        if (grp_b_reg[i] == 1'b0) begin
            // L-group
            temp[left_pos] = grp_a_reg[i];
            left_pos = left_pos + 1;
        end else begin
            // R-group
            temp[right_pos] = grp_a_reg[i];
            right_pos = right_pos - 1;
        end
    end

    grp16 = temp;
end
endfunction


endmodule
