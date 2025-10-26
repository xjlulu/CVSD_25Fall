`timescale 1ns/100ps

module regfile_fp (
    input              i_clk,
    input              i_rst_n,
    input              i_we,             // write enable
    input       [4:0]  i_rs1,            // source register 1 index
    input       [4:0]  i_rs2,            // source register 2 index
    input       [4:0]  i_rd,             // destination register index
    input       [31:0] i_wdata,          // data to write
    output reg  [31:0] o_rs1_data,       // data from source 1
    output reg  [31:0] o_rs2_data        // data from source 2
);

    // 32 single-precision floating-point registers
    reg [31:0] fp_regs [0:31];
    integer i;
    wire [31:0] fp_regs0  = fp_regs[0];
    wire [31:0] fp_regs1  = fp_regs[1];
    wire [31:0] fp_regs2  = fp_regs[2];
    wire [31:0] fp_regs3  = fp_regs[3];
    wire [31:0] fp_regs4  = fp_regs[4];
    wire [31:0] fp_regs5  = fp_regs[5];
    wire [31:0] fp_regs6  = fp_regs[6];
    wire [31:0] fp_regs7  = fp_regs[7];
    wire [31:0] fp_regs8  = fp_regs[8];
    wire [31:0] fp_regs10 = fp_regs[10];
    wire [31:0] fp_regs11 = fp_regs[11];
    wire [31:0] fp_regs12 = fp_regs[12];
    wire [31:0] fp_regs15 = fp_regs[15];
    wire [31:0] fp_regs16 = fp_regs[16];
    wire [31:0] fp_regs21 = fp_regs[21];
    wire [31:0] fp_regs29 = fp_regs[29];
    wire [31:0] fp_regs30 = fp_regs[30];
    wire [31:0] fp_regs31 = fp_regs[31];

    // asynchronous reset
    always @(negedge i_rst_n or posedge i_clk) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                fp_regs[i] <= 32'b0;
        end else if (i_we) begin
            fp_regs[i_rd] <= i_wdata;
        end
    end

    // combinational read ports
    always @(*) begin
        o_rs1_data = fp_regs[i_rs1];
        o_rs2_data = fp_regs[i_rs2];
    end

endmodule