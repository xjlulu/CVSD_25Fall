module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,

    input                      i_in_valid,
    output                     o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,

    output                     o_out_valid,
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

/******************************************* Internal Signals ****************************************/
reg                       in_valid_reg_1, in_valid_reg_2;
reg  [INST_W-1:0]         inst_reg_1, inst_reg_2;
reg  [DATA_W-1:0]         a_reg, b_reg, ab_reg, data_acc;

wire data_acc_update = (inst_reg_1 == MAC) && in_valid_reg_1;

wire [DATA_W:0]   a_comp_temp = {1'b0, ~a_reg} + {{DATA_W{1'b0}}, 1'b1};
wire [DATA_W:0]   b_comp_temp = {1'b0, ~b_reg} + {{DATA_W{1'b0}}, 1'b1};
wire [DATA_W-1:0] a_comp      = a_comp_temp[DATA_W-1:0];
wire [DATA_W-1:0] b_comp      = b_comp_temp[DATA_W-1:0];

/******************************************* ALU core ***********************************************/

/******************************************* ALU core ***********************************************/
wire [DATA_W-1:0]   add_in_a = (inst_reg_1 == MAC) ? data_acc : a_reg;
wire [DATA_W-1:0]   add_in_b = (inst_reg_1 == SUB) ? b_comp :
                               (inst_reg_1 == MAC) ? ab_reg :
                                                     b_reg  ;

wire                a_sign   = add_in_a[DATA_W-1];
wire                b_sign   = add_in_b[DATA_W-1];
wire                sign_eq  = (a_sign == b_sign);
wire [DATA_W:0]     sum      = add_in_a + add_in_b;
wire                overflow = (sum[DATA_W] ^ sum[DATA_W - 1]) && sign_eq;
wire [DATA_W-1:0]   add_out  = (!overflow) ? sum[DATA_W-1:0]
                                           : (a_sign ? MIN_VAL : MAX_VAL);

// MAC
wire [DATA_W-1:0] comp_i_data_a = twos_complement(i_data_a);
wire [DATA_W-1:0] comp_i_data_b = twos_complement(i_data_b);
wire [DATA_W-1:0] mult_in_a = (i_data_a[DATA_W-1]) ? comp_i_data_a : i_data_a;
wire [DATA_W-1:0] mult_in_b = (i_data_b[DATA_W-1]) ? comp_i_data_b : i_data_b;
wire [2*DATA_W-1:0] mult_out = {16'b0, mult_in_a} * {16'b0, mult_in_b};
// wire [DATA_W-1:0] nearest = (mult_out[DATA_W-1:0] == 16'b0) ? 16'd0 : 16'd1;
// wire [DATA_W-1:0] mult_out_round = mult_out[FRAC_W+:DATA_W] + nearest;
// wire [DATA_W-1:0] mult_out_round = mult_out[FRAC_W+:DATA_W] + {15'b0, mult_out[FRAC_W-1]};
wire [DATA_W-1:0] mult_out_round = mult_out[FRAC_W+:DATA_W];
wire [DATA_W-1:0] ab_reg_in = (i_data_a[DATA_W-1] ^ i_data_b[DATA_W-1]) ? twos_complement(mult_out_round) : mult_out_round;

wire [DATA_W-1:0]   data_acc_in = add_out;

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

// ROT
wire [DATA_W-1:0] rot_out;
reg [3:0] count;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        count <= 4'b0;
    end
    begin 
end

/******************************************* Control Logic ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        a_reg          <= 0;
        b_reg          <= 0;
        inst_reg_1     <= 0;
        in_valid_reg_1 <= 0;
        in_valid_reg_2 <= 0;
    end
    else begin
        in_valid_reg_1 <= i_in_valid;
        in_valid_reg_2 <= in_valid_reg_1;
        if (i_in_valid && !o_busy) begin
            inst_reg_1   <= i_inst;
            a_reg        <= i_data_a;
            b_reg        <= i_data_b;
        end
        if (in_valid_reg_1) begin
            inst_reg_2   <= inst_reg_1;
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
    else if(inst_reg_1 == ADD || inst_reg_1 == SUB) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == MAC) begin
        o_data     <= data_acc_in;
    end
    else if(inst_reg_1 == SIN) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == GRAY) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == LRCW) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == ROT) begin
        o_data     <= rot_out;
    end
    else if(inst_reg_1 == CLZ) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == RM4) begin
        o_data     <= add_out;
    end
    else if(inst_reg_1 == TRANS) begin
        o_data     <= add_out;
    end
    else begin
        o_data     <= 0;
    end
end

/******************************************* Output Signal ******************************************/
assign o_busy = 1'b0;
assign o_out_valid = in_valid_reg_2;

/******************************************* ALU Function ******************************************/
// compute the two's complement of a signed number
function signed [DATA_W-1:0] twos_complement (
    input signed [DATA_W-1:0] in_data
);
    twos_complement = ~in_data + 1;
endfunction

endmodule
