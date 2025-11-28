module chien
#(
    parameter integer N_MAX = 1023,
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                       clk,
    input  wire                       rstn,

    input  wire                       start,
    input  wire [9:0]                 n,
    input  wire [3:0]                 m,

    input  wire [3:0]                 degree,
    input  wire [(T_MAX+1)*M_MAX-1:0] sigma,

    output reg                        done,
    output reg [N_MAX-1:0]            err_vec
);
endmodule
