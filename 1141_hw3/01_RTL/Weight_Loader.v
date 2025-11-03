`timescale 1ns/1ps
module Weight_Loader (
    input         i_clk,
    input         i_rst_n,

    // 進入 CONV 階段就拉高
    input         i_start,

    // 從頂層共用的 in_* 通道收權重
    input         i_w_valid,
    input  [31:0] i_w_data,
    output reg    o_w_ready,

    // 輸出：收好 9 個權重（8-bit signed）打包成 72-bit
    output reg          o_done,      // 收滿一包（3×32-bit -> 9 bytes）
    output reg [71:0]   o_weights    // {w0,w1,...,w8}，每個 8-bit
);
    // FSM
    localparam S_IDLE = 2'd0;
    localparam S_LOAD = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state, nstate;
    reg [1:0] pack_cnt; // 需要 3 筆 32-bit

    // 將原本的 w[0:8] 展開成單一 72-bit 匯流排
    // byte 位置對應：
    // w0 -> [71:64], w1 -> [63:56], w2 -> [55:48], w3 -> [47:40],
    // w4 -> [39:32], w5 -> [31:24], w6 -> [23:16], w7 -> [15:8], w8 -> [7:0]
    reg [71:0] w_bus;

    // next state
    always @(*) begin
        nstate = state;
        case (state)
            S_IDLE: if (i_start)                        nstate = S_LOAD;
            S_LOAD: if (pack_cnt == 2/* && i_w_valid*/) nstate = S_DONE;
            S_DONE:                                     nstate = S_DONE;
            default:                                    nstate = S_IDLE;
        endcase
    end

    // FFs
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state     <= S_IDLE;
            pack_cnt  <= 2'd0;
            o_w_ready <= 1'b0;
            o_done    <= 1'b0;
            w_bus     <= 72'd0;
            o_weights <= 72'd0;
        end else begin
            state     <= nstate;

            // 預設值（每拍都重置，再由各狀態覆寫）
            o_done    <= 1'b0;
            o_w_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    pack_cnt <= 2'd0;
                    w_bus    <= 72'd0;
                    if (i_start) o_w_ready <= 1'b1;
                    // 第 1 筆 32-bit -> w0..w3
                    w_bus[71:64] <= i_w_data[31:24]; // w0
                    w_bus[63:56] <= i_w_data[23:16]; // w1
                    w_bus[55:48] <= i_w_data[15: 8]; // w2
                    w_bus[47:40] <= i_w_data[ 7: 0]; // w3
                end

                S_LOAD: begin
                    o_w_ready <= 1'b1;
                    if (i_w_valid) begin
                        case (pack_cnt)
                            2'd0: begin
                                // 第 2 筆 32-bit -> w4..w7
                                w_bus[39:32] <= i_w_data[31:24]; // w4
                                w_bus[31:24] <= i_w_data[23:16]; // w5
                                w_bus[23:16] <= i_w_data[15: 8]; // w6
                                w_bus[15: 8] <= i_w_data[ 7: 0]; // w7
                            end
                            2'd1: begin
                                // 第 3 筆 32-bit -> 只取最高位元組作為 w8
                                w_bus[7:0]   <= i_w_data[31:24]; // w8
                            end
                            2'd2: begin
                                w_bus        <=  w_bus; // 已在 IDLE 狀態寫入
                            end
                        endcase
                        pack_cnt <= pack_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    // 打成 72-bit 給 Engine 用（一拍脈衝）
                    o_weights <= w_bus;
                    o_done    <= 1'b1;
                    // o_w_ready 預設為 0（不再收資料）
                end
            endcase
        end
    end
endmodule
