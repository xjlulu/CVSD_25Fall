`timescale 1ns/100ps

module regfile_int (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_we,               // write enable
    input  wire [4:0]  i_rs1,              // read source 1 index
    input  wire [4:0]  i_rs2,              // read source 2 index
    input  wire [4:0]  i_rd,               // destination index
    input  wire [31:0] i_wdata,            // data to write
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data
);

    reg [31:0] regs [0:31];
    integer i;
    wire [31:0] regs0 = regs[0];
    wire [31:0] regs1 = regs[1];
    wire [31:0] regs2 = regs[2];
    wire [31:0] regs3 = regs[3];
    wire [31:0] regs4 = regs[4];
    wire [31:0] regs5 = regs[5];
    wire [31:0] regs6 = regs[6];
    wire [31:0] regs7 = regs[7];
    wire [31:0] regs8 = regs[8];
    wire [31:0] regs10 = regs[10];
    wire [31:0] regs11 = regs[11];
    wire [31:0] regs12 = regs[12];
    wire [31:0] regs15 = regs[15];
    wire [31:0] regs16 = regs[16];
    wire [31:0] regs21 = regs[21];
    wire [31:0] regs29 = regs[29];
    wire [31:0] regs30 = regs[30];
    wire [31:0] regs31 = regs[31];

    // write + reset
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end 
        else if (i_we) begin //  && (i_rd != 5'd0) allowed write to $0
            regs[i_rd] <= i_wdata; // x0 is read-only 0
        end
    end

    // read (combinational)
    assign o_rs1_data = regs[i_rs1];
    assign o_rs2_data = regs[i_rs2];

endmodule
