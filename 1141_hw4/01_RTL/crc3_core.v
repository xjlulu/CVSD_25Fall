`timescale 1ns/10ps
module crc3_core (
    input             clk,
    input             rst,
    input             start,         // IOTDF 丟 start=1，資料已經穩在 data_in
    input  [127:0]    data_in,
    output reg        done,      // 算完拉 1 一個 cycle
    output reg [2:0]  crc_out    // 3-bit CRC
);

// ============================================================
//  狀態暫存（時序）
// ============================================================
reg        running;             // 1: 正在跑 CRC
reg [6:0]  bit_idx;             // 0~127
reg [2:0]  crc_reg;             // 目前 LFSR 狀態

// 下一拍值（組合）
reg        next_running;
reg [6:0]  next_bit_idx;
reg [2:0]  next_crc_reg;

reg        next_done;
reg [2:0]  next_crc_out;

// 目前要吃哪一個資料 bit（MSB-first）
wire din = data_in[bit_idx];

// feedback
wire fb = din ^ crc_reg[2];

// 依 G(x)=x^3+x^2+1 對應的 LFSR 更新結果（純組合）
// 注意：這裡完全只用「舊的」 crc_reg & din，沒有用到 crc_next 自己
wire [2:0] crc_calc = { crc_reg[1] ^ fb, crc_reg[0], fb };

// ============================================================
//  組合邏輯：決定 next_*
// ============================================================
always @(*) begin
    // 預設：維持原狀
    next_running  = running;
    next_bit_idx  = bit_idx;
    next_crc_reg  = crc_reg;

    // done / crc_out 預設：跟原本一樣，但 done 下一拍預設 0
    next_done     = 1'b0;
    next_crc_out  = crc_out;

    if (start && !running) begin
        // 接收到新的 start，開始一輪 CRC 計算
        next_running = 1'b1;
        next_bit_idx = 7'd127;     // 從 MSB 開始
        next_crc_reg = 3'd0;       // 初始 CRC 清 0
    end
    else if (running) begin
        // 正在跑：這一拍吃 data_in[bit_idx]，算一次 LFSR
        next_crc_reg = crc_calc;

        if (bit_idx == 7'd0) begin
            // 最後一個 bit 也算完了
            next_running = 1'b0;
            next_bit_idx = 7'd0;   // 隨便，已經結束了
            next_done    = 1'b1;   // 下個 clock 拉 done=1
            next_crc_out = crc_calc; // 把最後結果輸出
        end
        else begin
            // 還沒吃完全部 128 bits
            next_bit_idx = bit_idx - 7'd1;
        end
    end
    // 如果沒有 start 又沒在 running，就全部維持原狀
end

// ============================================================
//  時序邏輯：在 clock 邊緣更新狀態與輸出
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        running  <= 1'b0;
        bit_idx  <= 7'd0;
        crc_reg  <= 3'd0;

        done     <= 1'b0;
        crc_out  <= 3'd0;
    end
    else begin
        running  <= next_running;
        bit_idx  <= next_bit_idx;
        crc_reg  <= next_crc_reg;

        done     <= next_done;
        crc_out  <= next_crc_out;
    end
end

endmodule
