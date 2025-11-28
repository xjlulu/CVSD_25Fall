module bch_hard_core
#(
    parameter integer N_MAX = 1023,    // 最大 n
    parameter integer T_MAX = 4,       // 最大 t
    parameter integer M_MAX = 10       // 最大 m
)
(
    input  wire                 clk,
    input  wire                 rstn,

    input  wire                 start,      // 1 個 pulse，開始 decode
    input  wire [9:0]           n,          // 實際 code 長度
    input  wire [3:0]           t,          // 實際 error capability
    input  wire [3:0]           m,          // 實際 GF(2^m)

    input  wire [N_MAX-1:0]     hard_bits,  // 只用 [n-1:0]

    output reg                  done,       // decode 完成 (1 個 cycle pulse 或 sticky 皆可)
    output reg                  success,    // 1: 成功找到 <= t 個錯誤; 0: 解碼失敗
    output reg [N_MAX-1:0]      err_vec     // 1 的位置代表那個 bit 是錯誤
);

endmodule
