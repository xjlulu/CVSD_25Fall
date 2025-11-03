`timescale 1ns/1ps
module Conv_Engine (
    input         i_clk,
    input         i_rst_n,

    // 啟動：等權重準備好再拉高（level 訊號即可）
    input         i_start,

    // 參數
    input  [7:0]  i_stride_size,     // 1 或 2
    input  [7:0]  i_dilation_size,   // 1 或 2

    // 權重（9 個 8-bit signed），展平成 72-bit（Q0.7）
    input  [71:0] i_weights,         // {w0,w1,...,w8}

    // SRAM 介面（read-only）
    output reg [11:0] sram_addr,
    output reg        sram_cen,      // active-low；RUN 狀態常為 0
    output reg        sram_wen,      // 讀態固定 1
    input      [7:0]  sram_q,

    // 輸出（只用通道1）
    output reg [7:0]  o_out_data1,   // 無號 8-bit，0~255 飽和
    output reg [11:0] o_out_addr1,
    output reg        o_out_valid1,

    output reg        o_done
);
    // ----------------- 常數與設定 -----------------
    localparam IMG_W      = 64;
    localparam IMG_H      = 64;
    localparam K          = 3;
    localparam integer FRAC_BITS = 7;  // 權重 Q0.7

    // 權重切片（signed 8-bit）
    wire signed [7:0] w0 = i_weights[71:64];
    wire signed [7:0] w1 = i_weights[63:56];
    wire signed [7:0] w2 = i_weights[55:48];
    wire signed [7:0] w3 = i_weights[47:40];
    wire signed [7:0] w4 = i_weights[39:32];
    wire signed [7:0] w5 = i_weights[31:24];
    wire signed [7:0] w6 = i_weights[23:16];
    wire signed [7:0] w7 = i_weights[15: 8];
    wire signed [7:0] w8 = i_weights[ 7: 0];

    // ----------------- FSM（兩級管線） -----------------
    localparam S_IDLE  = 3'd0;
    localparam S_PREP  = 3'd1;
    localparam S_RUN   = 3'd2;  // ★ 一拍發位址 + 同步上一拍 MAC
    localparam S_WRITE = 3'd3;
    localparam S_DONE  = 3'd4;

    localparam signed [23:0] HALF_LSB = 24'sd1 <<< (FRAC_BITS-1);

    reg [2:0] state, nstate;

    // 參數展開
    reg [1:0] stride, dil;
    reg [2:0] pad;            // pad = dil（K=3）

    // 輸出尺寸（SAME padding：S=1→64, S=2→32）
    reg [6:0] out_W, out_H;

    // 掃描座標
    reg [6:0] out_x, out_y;

    // tap 走訪（0..8）
    reg  [3:0] tap_idx;       // 當拍要「發位址」的 tap
    reg  [3:0] tap_idx_d;     // 對齊 sram_q 的上一拍 tap（做 MAC 用）
    reg        in_range_d;    // 對齊 sram_q 的上一拍 in_range
    reg        in_range_dd;   // 對齊 sram_q 的上上一拍 in_range

    // 已完成的 MAC 次數（0..9）
    reg  [3:0] mac_cnt;

    // kx/ky：不用除法/取餘，直接 LUT
    reg [1:0] kx, ky;
    always @(*) begin
        case (tap_idx)
            4'd0:  begin kx=2'd0; ky=2'd0; end
            4'd1:  begin kx=2'd1; ky=2'd0; end
            4'd2:  begin kx=2'd2; ky=2'd0; end
            4'd3:  begin kx=2'd0; ky=2'd1; end
            4'd4:  begin kx=2'd1; ky=2'd1; end
            4'd5:  begin kx=2'd2; ky=2'd1; end
            4'd6:  begin kx=2'd0; ky=2'd2; end
            4'd7:  begin kx=2'd1; ky=2'd2; end
            4'd8:  begin kx=2'd2; ky=2'd2; end
            default:begin kx=2'd0; ky=2'd0; end
        endcase
    end
    

    // 當拍要發位址的輸入座標（含 stride/dilation/padding）
    wire signed [9:0] base_x = $signed({1'b0,out_x}) * $signed({1'b0,stride}) - $signed({1'b0,pad});
    wire signed [9:0] base_y = $signed({1'b0,out_y}) * $signed({1'b0,stride}) - $signed({1'b0,pad});
    wire signed [9:0] in_x   = base_x + $signed({1'b0,kx}) * $signed({1'b0,dil});
    wire signed [9:0] in_y   = base_y + $signed({1'b0,ky}) * $signed({1'b0,dil});

    wire in_range = (in_x >= 0) && (in_x < IMG_W) && (in_y >= 0) && (in_y < IMG_H);
    wire [11:0] in_addr = (in_y[5:0] << 6) + in_x[5:0];  // y*64 + x

    // 累加器（留寬裕）
    reg  signed [23:0] acc;

    // 輸出地址（線性 raster-scan）
    wire [11:0] out_addr_flat = (out_y * out_W) + out_x;

    // 還原/飽和暫存（無號 0~255）
    reg  signed [23:0] acc_round, acc_shift;
    reg  [8:0]         clip_u;

    reg [7:0]  w_t;
    reg [7:0]  next_w_t;
    always @(*) begin
        case (tap_idx_d)
            4'd0:  begin  next_w_t=w0; end
            4'd1:  begin  next_w_t=w1; end
            4'd2:  begin  next_w_t=w2; end
            4'd3:  begin  next_w_t=w3; end
            4'd4:  begin  next_w_t=w4; end
            4'd5:  begin  next_w_t=w5; end
            4'd6:  begin  next_w_t=w6; end
            4'd7:  begin  next_w_t=w7; end
            4'd8:  begin  next_w_t=w8; end
            default:begin next_w_t=w8; end
        endcase
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            w_t <= 8'd0;
        end
        else begin
            w_t <= next_w_t;
        end
    end

    // next-state
    always @(*) begin
        nstate = state;
        case (state)
            S_IDLE : if (i_start)            nstate = S_PREP;
            S_PREP :                         nstate = S_RUN;
            S_RUN  : if (mac_cnt == 4'd9)    nstate = S_WRITE; // 9 次 MAC 完成
            S_WRITE: begin
                        if ((out_y==(out_H-1)) && (out_x==(out_W-1)))
                            nstate = S_DONE;
                        else
                            nstate = S_RUN;
                     end
            S_DONE : nstate = S_DONE;
            default: nstate = S_IDLE;
        endcase
    end

    always @(*) begin
            // Q0.7 → 四捨五入後右移 7，無號 0~255 飽和
        // acc_round <= acc + $signed(24'sd1 <<< (FRAC_BITS-1));
        acc_round = acc + HALF_LSB;
        acc_shift = acc_round >>> FRAC_BITS;

        if (acc_shift < 0)        clip_u = 9'd0;
        else if (acc_shift > 255) clip_u = 9'd255;
        else                      clip_u = acc_shift[8:0];
    end

    // FFs
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state        <= S_IDLE;

            sram_addr    <= 12'd0;
            sram_cen     <= 1'b1;   // 非 RUN 狀態預設關閉
            sram_wen     <= 1'b1;   // 永遠讀態

            stride       <= 2'd1;
            dil          <= 2'd1;
            pad          <= 3'd1;
            out_W        <= 7'd64;
            out_H        <= 7'd64;

            out_x        <= 7'd0;
            out_y        <= 7'd0;

            tap_idx      <= 4'd0;
            tap_idx_d    <= 4'd0;
            in_range_d   <= 1'b0;
            in_range_dd  <= 1'b0;

            mac_cnt      <= 4'd0;
            acc          <= 24'sd0;

            o_out_data1  <= 8'd0;
            o_out_addr1  <= 12'd0;
            o_out_valid1 <= 1'b0;
            o_done       <= 1'b0;

            acc_round    <= 24'sd0;
            acc_shift    <= 24'sd0;
            clip_u       <= 9'sd0;
        end else begin
            state        <= nstate;

            // 預設
            sram_wen     <= 1'b1;        // read-only
            o_out_valid1 <= 1'b0;

            case (state)
                S_IDLE: begin
                    o_done <= 1'b0;
                    out_x  <= 7'd0;
                    out_y  <= 7'd0;
                end

                S_PREP: begin
                    // 參數解碼（K=3，SAME padding）
                    stride  <= (i_stride_size   == 8'd1) ? 2'd1 : 2'd2;
                    dil     <= (i_dilation_size == 8'd1) ? 2'd1 : 2'd2;
                    pad     <= (K==3) ? {1'b0, ((i_dilation_size == 8'd1) ? 2'd1 : 2'd2)} : 3'd0; // pad=dil
                    out_W   <= (i_stride_size   == 8'd1) ? 7'd64 : 7'd32;
                    out_H   <= (i_stride_size   == 8'd1) ? 7'd64 : 7'd32;

                    tap_idx <= 4'd0;
                    mac_cnt <= 4'd0;
                    acc     <= 24'sd0;

                    // RUN 狀態會常開 CEN；這裡先關
                    sram_cen <= 1'b1;
                end

                S_RUN: begin
                    // ★ 第一級：發位址（tap_idx < 9 時才需要發）
                    sram_cen <= 1'b0; // RUN 期間常為 0，提升效率
                    if (tap_idx < 4'd9) begin
                        sram_addr <= in_addr;   // 即使越界也無妨，第二級用 in_range_d 遮罩
                    end

                    // ★ pipeline 對齊：鎖上一拍 tap/in_range/q
                    tap_idx_d   <= tap_idx;
                    in_range_d  <= in_range;
                    in_range_dd <= in_range_d;

                    // ★ 第二級：乘加（使用上一拍的資料）
                    // 第一拍 tap_idx=0 時，上一拍沒有有效資料 → 我們只在 (tap_idx>0) 時才累加與計數
                    if (tap_idx > 4'd0 && mac_cnt <= 4'd9) begin
                        if (in_range_dd && tap_idx_d > 4'd0) begin
                            acc <= acc + $signed(w_t) * $signed({8'd0, sram_q});
                        end
                        mac_cnt <= mac_cnt + 4'd1;  // 計滿 9 次 MAC
                    end

                    // 發位址索引遞增（最多到 9）
                    if (tap_idx < 4'd9)
                        tap_idx <= tap_idx + 4'd1;
                end

                S_WRITE: begin
                    o_out_data1  <= clip_u[7:0];       // 無號 8-bit
                    o_out_addr1  <= out_addr_flat;
                    o_out_valid1 <= 1'b1;

                    // 下一個輸出像素（raster-scan）
                    if (out_x == (out_W-1)) begin
                        out_x <= 7'd0;
                        out_y <= out_y + 1'b1;
                    end else begin
                        out_x <= out_x + 1'b1;
                    end

                    // 重置 MAC 組
                    tap_idx <= 4'd0;
                    mac_cnt <= 4'd0;
                    acc     <= 24'sd0;

                    // 寫完先關 CEN；回到 RUN 再打開
                    sram_cen <= 1'b1;
                end

                S_DONE: begin
                    o_done <= 1'b1; // 結束後保持為 1
                    sram_cen <= 1'b1;
                end
            endcase
        end
    end
endmodule
