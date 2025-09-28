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
parameter MAX_VAL26 = {1'b0, {25{1'b1}}};
// parameter MIN_VAL26 = {1'b1, {25{1'b0}}};
parameter MAX_VAL36 = {1'b0, {35{1'b1}}};
parameter MIN_VAL36 = {1'b1, {35{1'b0}}};
parameter FINAL_TRANS_COUNT  = 8;
parameter CNT_W  = 4;
// Q6.10 format constants for fractional values
parameter [DATA_W+9:0] CONST_FRAC_2 = 26'b000000_10000000000000000000; // 1/2 = 0.5 (Q6.10)
parameter [DATA_W+9:0] CONST_FRAC_3 = 26'b000000_01010101010000000000; // 1/3 ≈ 0.3333 (Q6.10)
parameter [DATA_W+9:0] CONST_FRAC_4 = 26'b000000_01000000000000000000; // 1/4 = 0.25 (Q6.10)
parameter [DATA_W+9:0] CONST_FRAC_5 = 26'b000000_00110011000000000000; // 1/5 ≈ 0.2 (Q6.10)

/******************************************* Internal Signals ****************************************/
reg                 in_valid_reg;
reg  [INST_W-1:0]   inst_reg_1, inst_reg_2;
reg  [DATA_W-1:0]   a_reg, b_reg;
reg  [2*DATA_W-1:0] ab_reg;
reg  [35:0]         data_acc;
reg  [CNT_W-1:0]    lrcw_count;
reg  [CNT_W-1:0]    rot_count;
reg  [CNT_W-1:0]    clz_count;
reg  [CNT_W-1:0]    trans_count;
wire [DATA_W-1:0]   lrcw_out;
reg  [DATA_W-1:0]   rot_out;

wire is_final_sin_count     = (sin_count == 3'd5) && (inst_reg_1 == SIN);
wire is_final_lrcw_count    = ((lrcw_count == 4'd15) || (a_reg == 16'd0) || (a_reg == {16{1'b1}})) && (inst_reg_1 == LRCW);
wire is_final_rot_count     = ((rot_count == b_reg[CNT_W-1:0]) || (b_reg[CNT_W-1:0] == 4'd0)) && (inst_reg_1 == ROT);
wire is_final_clz_count     = ((a_reg[15-clz_count] == 1'b1) || (clz_count == 4'd14) || (a_reg[DATA_W-1:0] == 16'd0)) && (inst_reg_1 == CLZ);
wire is_finalm1_trans_count = trans_count == FINAL_TRANS_COUNT - 1;
wire is_final_trans_count   = trans_count == FINAL_TRANS_COUNT;
wire trans_ready            = i_inst == TRANS && i_in_valid && is_finalm1_trans_count && !o_busy;
wire o_data_update_add      = (inst_reg_1 == ADD  || inst_reg_1 == SUB) && in_valid_reg;
wire o_data_update_mac      = (inst_reg_1 == MAC  ) && in_valid_reg;
wire o_data_update_sin      = (inst_reg_1 == SIN  ) && (is_final_sin_count && o_busy);
wire o_data_update_gray     = (inst_reg_1 == GRAY ) && in_valid_reg;
wire o_data_update_rm4      = (inst_reg_1 == RM4  ) && in_valid_reg;
wire o_data_update_lrcw     = (inst_reg_1 == LRCW ) && (is_final_lrcw_count && o_busy);
wire o_data_update_rot      = (inst_reg_1 == ROT  ) && (is_final_rot_count  && o_busy);
wire o_data_update_clz      = (inst_reg_1 == CLZ  ) && (is_final_clz_count  && o_busy);
wire o_data_update_trans    = (inst_reg_2 == TRANS) && !is_final_trans_count && o_busy;
wire o_data_update          = o_data_update_add || o_data_update_mac || o_data_update_sin || o_data_update_gray || o_data_update_rm4 || o_data_update_lrcw || o_data_update_rot || o_data_update_clz || o_data_update_trans;
wire sin_start              = !o_busy && i_in_valid && (i_inst == SIN  );
wire lrcw_start             = !o_busy && i_in_valid && (i_inst == LRCW );
wire rot_start              = !o_busy && i_in_valid && (i_inst == ROT  );
wire clz_start              = !o_busy && i_in_valid && (i_inst == CLZ  );
wire trans_start            = !o_busy && i_in_valid && (i_inst == TRANS);
wire busy_start             = sin_start || lrcw_start || rot_start || clz_start || trans_ready;
wire matrix_out_update      =  o_busy && (inst_reg_2 == TRANS);
wire sin_done               = is_final_sin_count;
wire lrcw_done              = is_final_lrcw_count;
wire rot_done               = is_final_rot_count;
wire clz_done               = is_final_clz_count;
wire trans_done             = is_final_trans_count && o_busy;
wire busy_done              = sin_done || lrcw_done || rot_done || clz_done || trans_done;
wire data_acc_update        = o_data_update_mac;

/******************************************* ALU core ***********************************************/

/******************************************* ALU core ***********************************************/
wire [DATA_W-1:0]   add_in_a       = a_reg;
wire [DATA_W-1:0]   add_in_b       = (inst_reg_1 == SUB) ? twos_complement(b_reg) : b_reg;

wire                sign_eq  = (add_in_a[DATA_W-1] == add_in_b[DATA_W-1]);
wire [DATA_W:0]     sum      = add_in_a + add_in_b;
wire                overflow = (sum[DATA_W] ^ sum[DATA_W - 1]) && sign_eq;
wire [DATA_W-1:0]   add_out  = (!overflow) ? sum[DATA_W-1:0]
                                           : (add_in_a[DATA_W-1] ? MIN_VAL : MAX_VAL);

/******************************************* ALU:MAC ******************************************/
wire [DATA_W-1:0]   comp_i_data_a  = twos_complement(i_data_a);
wire [DATA_W-1:0]   comp_i_data_b  = twos_complement(i_data_b);
wire [DATA_W-1:0]   mult_in_a      = (i_data_a[DATA_W-1]) ? comp_i_data_a : i_data_a;
wire [DATA_W-1:0]   mult_in_b      = (i_data_b[DATA_W-1]) ? comp_i_data_b : i_data_b;
wire [2*DATA_W-1:0] mult_full      = (mult_in_a * mult_in_b);
// wire [DATA_W:0]     mult_shift     = mult_full [DATA_W + FRAC_W - 1 : FRAC_W - 1];
// wire [DATA_W-1:0]   mult_out_round = mult_shift[DATA_W:1] + {{(DATA_W-1){1'b0}}, mult_shift[0]};
wire [2*DATA_W-1:0] ab_reg_in      = (i_data_a[DATA_W-1] ^ i_data_b[DATA_W-1]) ? twos_complement32(mult_full) : mult_full;

wire        mac_mult_sign  = (a_reg[DATA_W-1] ^ b_reg[DATA_W-1]);
wire [35:0] mac_add_in_a   = data_acc;
wire [35:0] mac_add_in_b   = {{4{mac_mult_sign}}, ab_reg};
wire        mac_sign_eq    = mac_add_in_a[35] == mac_add_in_b[35];
wire [36:0] mac_sum        = mac_add_in_a + mac_add_in_b;
wire        mac_overflow   = (mac_sum[36] ^ mac_sum[36 - 1]) && mac_sign_eq;
wire [35:0] mac_add_out    = (!mac_overflow) ? mac_sum[35:0]
                                             : (mac_add_in_a[35] ? MIN_VAL36 : MAX_VAL36);
wire [35:0] data_acc_in    = mac_add_out;



// data_acc_in overflow
wire [35:0] comp_mac_add_out = twos_complement36(mac_add_out);
wire        sign_mac_add_out = mac_add_out[35];
wire [35:0] posvalue = sign_mac_add_out ? comp_mac_add_out : mac_add_out;
wire [25:0] posvalue_rounded = posvalue[35:10] + {25'b0, posvalue[9]};
wire [25:0] comp_posvalue_rounded = twos_complement26(posvalue_rounded);

wire mac_add_out_overflow = (posvalue_rounded > MAX_VAL26);
wire [DATA_W-1:0] mac_out = (!mac_add_out_overflow) ? (sign_mac_add_out ? comp_posvalue_rounded[15:0] : posvalue_rounded[15:0]) :
                                                      (sign_mac_add_out ? MIN_VAL : MAX_VAL);

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

/******************************************* ALU:SIN ******************************************/
// I1: 1111111110001000
// G1: 1111111110001000
// I2: 1111111011111100
// G2: 1111111011111111


//  I28                 : 111111 1000011111
// iI28                 : 000000 0111100001
// iI28^2               : 000000000000 00111000011111000001
// iI28^2/2             :     000000000000 000111000011111000001
// iI28^3/2             :                                   000 0000110101000100001000110100001
// 1/3                  :                           0 0101010101
// iI28^3/2/3           :                             00000100011010101111000010111101101110101
// iI28^4/2/3           :                 0 000000100001001100111011100101010001111011011010101
// iI28^4/2/3/4         :                 0 00000000100001001100111011100101010001111011011010101
// iI28                 :  000000 0111100001
// 1/5                  :  000000_0011001100
// iI28^5/2/3/4         :                 0 000000000011111001100010001011110011001011101111100011000110101
// iI28^5/2/3/4/5       :       0 0000000000001100011011011000111101100111001001011011100011111001000111100
//  G28   : 111111 1111000101
// iG28   : 000000 0000111011

// iI28^3/2/3           :  000000 0000010001 1010101111000010111101101110101
// iI28                 :  000000 0111100001
//  I28^3/2/3           :  111111 1111101110 0101010000111101000010010001011
//                        1000000 0111001111 0101010000111101000010010001011
// iI28^5/2/3/4/5       :  000000 0000000000 001100011011011000111101100111001001011011100011111001000111100
//                      :  000000 0111001111 100001011
//                      :  000000 0111010000
//                  inv :  111111 1000110000

//                        1000000 0111001111 0101010000111101000010010001011
// iI28^5/2/3/4/5       :  000000 0000000000 001100011011011000111101100111001001011011100011111001000111100
//                  test:  000000 0111001111
//                 itest:  111111 1000110001
// 1111111000110001
// [ERROR  ]   [28] Your Result:1111111000110000 Golden:1111111000110001
reg signed [2*DATA_W-1:0] sin_out_reg;
reg signed [2*DATA_W-1:0] a_power_reg;
reg [2:0] sin_count;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sin_count   <= 3'b0;
    end
    else if (is_final_sin_count) begin
        sin_count   <= 3'b0;
    end
    else if (sin_start) begin
        sin_count   <= 3'b0;
    end
    else if (o_busy) begin
        sin_count   <= sin_count + 1'b1;
    end
end


// function [31:0] round_a_power_reg;
//     input [31:0] in_data;
// begin
//     round_a_power_reg = {in_data[31:10], 10'b0} + {21'b0, in_data[9], 10'b0};
// end
// endfunction

wire [2*DATA_W-1:0] sin_a_init = i_data_a[15] ? {6'b0, twos_complement(i_data_a), 10'b0} : {6'b0, i_data_a, 10'b0};
wire [2*DATA_W-1:0] sin_a_reg  = a_reg[15]    ? {6'b0, twos_complement(a_reg   ), 10'b0} : {6'b0, a_reg   , 10'b0};
wire [4*DATA_W-1:0] a_power_reg_mult_full    = a_power_reg * sin_a_reg;
wire [2*DATA_W-1:0] a_power_reg_mult_shifted = a_power_reg_mult_full[51:20];
wire [4*DATA_W-1:0] a_power_reg_in_frac2     = a_power_reg_mult_shifted * CONST_FRAC_2;
wire [4*DATA_W-1:0] a_power_reg_in_frac3     = a_power_reg_mult_shifted * CONST_FRAC_3;
wire [4*DATA_W-1:0] a_power_reg_in_frac4     = a_power_reg_mult_shifted * CONST_FRAC_4;
wire [4*DATA_W-1:0] a_power_reg_in_frac5     = a_power_reg_mult_shifted * CONST_FRAC_5;
// wire [2*DATA_W-1:0] a_power_reg_in_2         = round_a_power_reg(a_power_reg_in_frac2[51:20]);
// wire [2*DATA_W-1:0] a_power_reg_in_3         = round_a_power_reg(a_power_reg_in_frac3[51:20]);
// wire [2*DATA_W-1:0] a_power_reg_in_4         = round_a_power_reg(a_power_reg_in_frac4[51:20]);
// wire [2*DATA_W-1:0] a_power_reg_in_5         = round_a_power_reg(a_power_reg_in_frac5[51:20]);


wire [2*DATA_W-1:0] a_power_reg_in_2         = a_power_reg_in_frac2[51:20];
wire [2*DATA_W-1:0] a_power_reg_in_3         = a_power_reg_in_frac3[51:20];
wire [2*DATA_W-1:0] a_power_reg_in_4         = a_power_reg_in_frac4[51:20];
wire [2*DATA_W-1:0] a_power_reg_in_5         = a_power_reg_in_frac5[51:20];


// wire [2*DATA_W-1:0] a_power_reg_in_2     = div_by_2(a_power_reg_mult_shifted);
// wire [2*DATA_W-1:0] a_power_reg_in_3     = div_by_3(a_power_reg_mult_shifted);
// wire [2*DATA_W-1:0] a_power_reg_in_4     = div_by_4(a_power_reg_mult_shifted);
// wire [2*DATA_W-1:0] a_power_reg_in_5     = div_by_5(a_power_reg_mult_shifted);

// // Function to approximate division by 2 for 32-bit input
// function [31:0] div_by_2;
//     input [31:0] in_data;
// begin
//     div_by_2 = in_data >> 1;
// end
// endfunction

// // Function to approximate division by 3 for 32-bit input
// function [31:0] div_by_3;
//     input [31:0] in_data;
//     reg [31:0] Q1;
//     reg [31:0] Q2;
//     reg [31:0] Q3;
//     reg [31:0] Q4;
// begin
//     Q1 = ((in_data >> 2) + in_data) >> 2; // Q = A*0.0101
//     Q2 = (Q1 + in_data) >> 1;              // Q = A*0.10101
//     Q3 = ((Q2 >> 6) + Q2);                  // Q = A*0.10101010101
//     Q4 = ((Q3 >> 12) + Q3) >> 1;            // Q = A*0.01010101010101010...
//     div_by_3 = Q4;
// end
// endfunction

// // Function to approximate division by 4 for 32-bit input
// function [31:0] div_by_4;
//     input [31:0] in_data;
// begin
//     div_by_4 = in_data >> 2;
// end
// endfunction

// // Function to approximate division by 5 for 32-bit input
// function [31:0] div_by_5;
//     input [31:0] in_data;
//     reg [31:0] Q1;
//     reg [31:0] Q2;
//     reg [31:0] Q3;
// begin
//     Q1 = (in_data >> 1) + in_data;      // Q = A*0.11
//     Q2 =  (Q1 >> 4) + Q1;                  // Q = A*0.110011
//     Q3 = ((Q2 >> 8) + Q2) >> 2;           // Q = A*0.0011001100110011
//     div_by_5 = Q3;
// end
// endfunction


// wire [2*DATA_W-1:0] a_power_reg_in = (a_power_reg * sin_a_reg >> 2*FRAC_W);
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        a_power_reg   <= {2*DATA_W{1'b0}};
    end
    else if (sin_start) begin
        a_power_reg <= sin_a_init;
    end
    else if (o_busy && sin_count == 3'd0) begin
        a_power_reg <= a_power_reg_in_2;
    end
    else if (o_busy && sin_count == 3'd1) begin
        a_power_reg <= a_power_reg_in_3;
    end
    else if (o_busy && sin_count == 3'd2) begin
        a_power_reg <= a_power_reg_in_4;
    end
    else if (o_busy && sin_count == 3'd3) begin
        a_power_reg <= a_power_reg_in_5;
    end
end

// wire [31:0] a_power_reg_round = {a_power_reg[31:10], 10'b0} + {21'b0, a_power_reg[9] ,10'b0};
// wire [31:0] a_power_reg32 = twos_complement32(a_power_reg_round);

wire [31:0] a_power5 = {a_power_reg[31:10], 10'b0} + {21'b0, a_power_reg[9] ,10'b0};
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sin_out_reg   <= {(2*DATA_W){1'b0}};
    end
    else if (sin_start) begin
        sin_out_reg <= sin_a_init;
    end
    else if (sin_count == 3'd2) begin
        sin_out_reg <= sin_out_reg + twos_complement32(a_power_reg);
        // sin_out_reg <= sin_out_reg + {a_power_reg32[31:1], {1{1'b1}}};
    end
    else if (sin_count == 3'd4) begin
        sin_out_reg <= sin_out_reg + a_power_reg;
        // sin_out_reg <= sin_out_reg + {a_power_reg[31:1], 1'b0};
        // sin_out_reg <= sin_out_reg + a_power_reg_round;
    end
end

wire [2*DATA_W-11:0] sin_out_reg_round = sin_out_reg[31:10] + {21'b0, sin_out_reg[9]};
wire sin_overflow = |sin_out_reg[31:26];
wire [DATA_W-1:0] sin_out = (!sin_overflow) ? (a_reg[15] ? twos_complement(sin_out_reg_round[DATA_W-1:0]) : sin_out_reg_round[DATA_W-1:0]) :
                                              (a_reg[15] ? MIN_VAL : MAX_VAL);



/******************************************* ALU:LRCW ******************************************/
//    a: 0101100000101000
//    b: 1110011000101110
// h(a): 5
//    b: 11100 11000101110
//       00011 11000101110
// L(b): 1100010111000011
reg [DATA_W-1:0] lrcw_b_reg;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        lrcw_b_reg   <= {DATA_W{1'b0}};
    end
    else if (lrcw_start) begin
        lrcw_b_reg <= i_data_b;
    end
    else if (o_busy && a_reg[lrcw_count]) begin
        lrcw_b_reg <= {lrcw_b_reg[DATA_W-2:0], ~lrcw_b_reg[DATA_W-1]};
    end
end
assign lrcw_out = (a_reg == {16{1'b0}}) ?  b_reg :
                  (a_reg == {16{1'b1}}) ? ~b_reg :
                  (a_reg[lrcw_count])   ? {lrcw_b_reg[DATA_W-2:0], ~lrcw_b_reg[DATA_W-1]} :
                                           lrcw_b_reg;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        lrcw_count <= {CNT_W{1'b0}};
    end
    else if (is_final_lrcw_count) begin
        lrcw_count <= {CNT_W{1'b0}};
    end
    else if (lrcw_start) begin
        lrcw_count <= {CNT_W{1'b0}};
    end
    else if (o_busy && inst_reg_1 == LRCW) begin
        lrcw_count <= lrcw_count + 1'b1;
    end
end


/******************************************* ALU:ROT ******************************************/
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
    else if (o_busy && inst_reg_1 == ROT) begin
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
    else if (o_busy && inst_reg_1 == CLZ) begin
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
        data_acc     <= 36'b0;
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
        ab_reg       <= 32'b0;
    end
    else if(i_in_valid) begin
        ab_reg       <= ab_reg_in;
    end
end

/******************************************* Output Signal ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_data     <= 0;
    end
    else if (o_data_update) begin
        if(inst_reg_1 == ADD || inst_reg_1 == SUB) begin
            o_data     <= add_out;
        end
        else if(inst_reg_1 == MAC) begin
            o_data     <= mac_out;
        end
        else if(inst_reg_1 == SIN) begin
            o_data     <= sin_out;
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
        o_busy <= 1'b0;
    end
    else if (busy_start) begin
        o_busy <= 1'b1;
    end
    else if (busy_done) begin
        o_busy <= 1'b0;
    end
end

/******************************************* ALU Function ******************************************/
// compute the two's complement of a signed number
function signed [DATA_W-1:0] twos_complement (
    input signed [DATA_W-1:0] in_data
);
    twos_complement = ~in_data + 1;
endfunction

function signed [25:0] twos_complement26 (
    input signed [25:0] in_data26
);
    twos_complement26 = ~in_data26 + 1;
endfunction

function signed [2*DATA_W-1:0] twos_complement32 (
    input signed [2*DATA_W-1:0] in_data32
);
    twos_complement32 = ~in_data32 + 1;
endfunction

function signed [35:0] twos_complement36 (
    input signed [35:0] in_data36
);
    twos_complement36 = ~in_data36 + 1;
endfunction


endmodule
