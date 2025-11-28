module syn_calc
#(
    parameter integer N_MAX = 1023,
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                     clk,
    input  wire                     rstn,

    input  wire                     start,       // 開始計算 syndrome
    input  wire [9:0]               n,
    input  wire [3:0]               t,
    input  wire [3:0]               m,

    input  wire [N_MAX-1:0]         hard_bits,   // 收到的 codeword

    output reg                      done,

    // packed syndromes: S1, S2, ..., S_{2T_MAX}
    // 每個 syndrome 是 M_MAX bits，實際只用 m bits
    output reg [2*T_MAX*M_MAX-1:0]  syndromes
);

endmodule
