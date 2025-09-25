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
    output reg     [DATA_W-1:0] o_data
);
/******************************************* Parameters ********************************************/
parameter ADD    = 4'b0000; // o_data = i_data_a + i_data_b
parameter SUB    = 4'b0001; // o_data = i_data_a - i_data_b
parameter MUL    = 4'b0010; // o_data = i_data_a * i_data_b + data_acc_old
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
reg          in_valid_reg;
reg  [3:0]   inst_reg;
reg  [15:0]  data_a_reg, data_b_reg;
reg signed [35:0] data_acc, data_acc_in;
assign data_acc_in = data_a_reg * data_b_reg + data_acc;

/******************************************* ALU core ***********************************************/
// wire [DATA_W-1:0] o_addsub = addsub_comb(data_a_reg, data_b_reg, inst_reg==SUB);


/******************************************* Control Logic ******************************************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        inst_reg     <= 0;
        data_a_reg   <= 0;
        data_b_reg   <= 0;
        in_valid_reg <= 0;
    end
    else begin
        in_valid_reg <= i_in_valid;
        if (i_in_valid) begin
            inst_reg   <= i_inst;
            data_a_reg <= i_data_a;
            data_b_reg <= i_data_b;
        end
    end
end
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_acc     <= 0;
    end
    else if(inst_reg == MUL) begin
        data_acc <= data_acc_in;
    end
end




/******************************************* Output Signal ******************************************/
assign o_busy = 1'b0;
assign o_out_valid = in_valid_reg;

always @(*) begin
    case (inst_reg)
    ADD: begin
        // Signed addition Q6.10
        o_data = o_addsub;
    end
    SUB: begin
        // TODO: subtraction
        o_data = o_addsub;
    end
    MUL: begin
        // TODO: MAC
        o_data = o_addsub;
    end
    SIN: begin
        // TODO: sin(x) Taylor
        o_data = o_addsub;
    end
    GRAY: begin
        // TODO: binary -> gray
        o_data = o_addsub;
    end
    LRCW: begin
        // TODO: LRCW
        o_data = o_addsub;
    end
    ROT: begin
        // TODO: right rotation
        o_data = o_addsub;
    end
    CLZ: begin
        // TODO: CLZ
        o_data = o_addsub;
    end
    RM4: begin
        // TODO: reverse match4
        o_data = o_addsub;
    end
    TRANS: begin
        // TODO: 8x8 matrix transpose
        o_data = o_addsub;
    end
    default o_data = {DATA_W{1'b0}}; 
endcase
end

/******************************************* ALU Function ******************************************/

// addition
// overflow detection
// data_add = a + b
// a,b = (+, +); data_add[17] = 0; data_add[16] = 1
// a,b = (-, -); data_add[17] = 1; data_add[16] = 0
// function[DATA_W-1:0] addsub_comb;
//     input [DATA_W-1:0] a;
//     input [DATA_W-1:0] i_b;
//     input              addorsub;
//     reg                sign_a;
//     reg   [DATA_W:0]   b;
//     reg   [DATA_W:0]   sum;
//     reg                overflow;
//     begin
//         if(addorsub) begin
//             b = ~i_b + 1;
//         end
//         else begin
//             b = {1'b0, i_b};
//         end
//         sign_a = a[DATA_W-1];
//         sum = {1'b0, a} + b;
//         overflow = sum[DATA_W] ^ sum[DATA_W - 1];
//         addsub_comb =  overflow ? (sign_a ? MIN_VAL : MAX_VAL) : sum[DATA_W-1:0];
//     end
// endfunction

wire [DATA_W-1:0] a = data_a_reg;
wire [DATA_W-1:0] i_b = data_b_reg;
wire              addorsub = (inst_reg==SUB);
wire                sign_a;
wire   [DATA_W:0]   b;
wire   [DATA_W:0]   sum;
wire               overflow;
wire [DATA_W-1:0] addsub_comb;

assign b = addorsub ? ({1'b0, ~i_b} + 17'd1) : {1'b0, i_b};
assign sign_a = a[DATA_W-1];
assign sum = {1'b0, a} + b;
assign overflow = sum[DATA_W] ^ sum[DATA_W - 1];
assign addsub_comb =  overflow ? (sign_a ? MIN_VAL : MAX_VAL) : sum[DATA_W-1:0];
wire [DATA_W-1:0] o_addsub = addsub_comb;

endmodule
