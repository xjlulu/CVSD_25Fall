module berlekamp
#(
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                     clk,
    input  wire                     rstn,

    input  wire                     start,
    input  wire [3:0]               t,
    input  wire [3:0]               m,

    input  wire [2*T_MAX*M_MAX-1:0] syndromes,

    output reg                      done,
    output reg                      failure,    // 1 代表無法求出合理的 sigma
    output reg [3:0]                degree,     // deg sigma(x)

    // packed sigma(x) = sigma_0 + sigma_1 x + ... + sigma_T x^T
    // sigma_0, sigma_1, ... 每個 M_MAX bits
    output reg [(T_MAX+1)*M_MAX-1:0] sigma
);
endmodule
