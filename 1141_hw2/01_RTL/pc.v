`timescale 1ns/100ps

module pc (
    input  wire        i_clk,
    input  wire        i_rst_n,       // active low async reset
    input  wire        i_pc_write_en, // enable to update PC
    input  wire [31:0] i_pc_next,
    output reg  [31:0] o_pc
);
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_pc <= 32'd0;
        else if (i_pc_write_en)
            o_pc <= i_pc_next;
        else
            o_pc <= o_pc; // hold
    end
endmodule