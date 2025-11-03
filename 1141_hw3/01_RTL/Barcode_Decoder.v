`timescale 1ns/1ps
module Barcode_Decoder (
    input             i_clk,
    input             i_rst_n,
    input             i_start,        // 由 image_done 觸發
    output reg        o_done,         // 完成解碼
    output reg        o_valid,        // 條碼有效

    // SRAM interface (read-only)
    output reg  [11:0] sram_addr,     // = row*64 + col
    output reg         sram_cen,      // active low
    output reg         sram_wen,      // active low (always read)
    input       [7:0]  sram_q,

    // Decoded results
    output reg [7:0] o_kernel_size,   // 3
    output reg [7:0] o_stride_size,   // 1 or 2
    output reg [7:0] o_dilation_size  // 1 or 2
);

    // -------- Code128-C patterns --------
    localparam [10:0] START_C_PAT = 11'b11010011100;      // 11 bits
    localparam [10:0] CODE_03_PAT = 11'b10010011000;      // 11 bits (K=03)
    localparam [10:0] CODE_01_PAT = 11'b11001101100;      // 11 bits
    localparam [10:0] CODE_02_PAT = 11'b11001100110;      // 11 bits
    localparam [12:0] STOP_PAT    = 13'b1100011101011;    // 13 bits (!!)

    // 影像大小與掃描限制
    localparam integer COL_MAX      = 63;
    localparam integer ROW_MAX      = 63;
    localparam integer START_MAXCOL = 7;     // Start 起點只能 0..7
    localparam integer SCAN_CUTOFF  = 17;    // SCAN 階段在 prev_col>17 就不再比對 Start（等價限制起點<=7）

    // -------- FSM --------
    localparam S_IDLE        = 3'd0;
    localparam S_SCAN        = 3'd1;   // 找 StartC
    localparam S_DECODE_K    = 3'd2;   // 11 bits
    localparam S_DECODE_S    = 3'd3;   // 11 bits
    localparam S_DECODE_D    = 3'd4;   // 11 bits
    localparam S_DECODE_STOP = 3'd5;   // 13 bits
    localparam S_VALIDATE    = 3'd6;
    localparam S_DONE        = 3'd7;

    reg [2:0] state, nstate;

    // -------- 掃描座標（發位址用） --------
    reg [5:0] row, col;       // 下一拍要讀的座標（本拍送出位址給 SRAM）
    reg [5:0] n_row, n_col;

    // -------- 1-cycle read latency 管線對齊資訊 --------
    reg       q_valid;        // 上拍資料是否已經有效
    reg [5:0] prev_col;       // 與當前 sram_q 對齊的欄位（上一拍發出的 col）
    reg [5:0] prev_row;       // 與當前 sram_q 對齊的列（上一拍發出的 row）

    // -------- 視窗與計數 --------
    reg [10:0] sh11;          // 11-bit shift 視窗 (Start/K/S/D)
    reg [12:0] sh13;          // 13-bit shift 視窗 (Stop)
    reg  [3:0] cnt11;         // 0..11
    reg  [3:0] cnt13;         // 0..13

    // -------- 暫存解碼 --------
    reg [7:0] k_val, s_val, d_val;
    reg       found_start;

    // 命中偵測（在 q_valid 的同拍、且只在合法欄位範圍）
    wire start_hit = (q_valid && state==S_SCAN && cnt11>=4'd11 &&
                      (prev_col <= SCAN_CUTOFF) && (sh11 == START_C_PAT));

    // =======================
    // Next-state
    // =======================
    always @(*) begin
        nstate = state;
        case (state)
            S_IDLE:        if (i_start) nstate = S_SCAN;
            S_SCAN:        if (found_start) nstate = S_DECODE_K;
                           else if (prev_row==ROW_MAX && prev_col>SCAN_CUTOFF && q_valid) nstate = S_VALIDATE;
            S_DECODE_K:    if (q_valid && cnt11==4'd11) nstate = S_DECODE_S;
            S_DECODE_S:    if (q_valid && cnt11==4'd11) nstate = S_DECODE_D;
            S_DECODE_D:    if (q_valid && cnt11==4'd11) nstate = S_DECODE_STOP;
            S_DECODE_STOP: if (q_valid && cnt13==4'd13) nstate = S_VALIDATE;
            S_VALIDATE:    nstate = S_DONE;
            S_DONE:        nstate = S_DONE;
            default:       nstate = S_IDLE;
        endcase
    end

    // =======================
    // 下一個要發的掃描座標（含命中時凍結）
    // =======================
    always @(*) begin
        n_row = row;
        n_col = col;

        if (state==S_SCAN || state==S_DECODE_K || state==S_DECODE_S ||
            state==S_DECODE_D || state==S_DECODE_STOP) begin

            // ★ 命中 Start 的當拍 → 凍結座標，不再做 col+1
            if (state==S_SCAN && start_hit) begin
                n_row = row;
                n_col = col;   // freeze one cycle
            end
            // ★ SCAN 階段若 >17 還沒命中，直接換列（加速）
            else if (state==S_SCAN && !found_start && col>SCAN_CUTOFF) begin
                n_col = 6'd0;
                n_row = (row==ROW_MAX) ? ROW_MAX : (row + 6'd1);
            end
            // ★ 一般推進
            else begin
                if (col==COL_MAX) begin
                    n_col = 6'd0;
                    n_row = (row==ROW_MAX) ? ROW_MAX : (row + 6'd1);
                end else begin
                    n_col = col + 6'd1;
                end
            end
        end
    end

    // =======================
    // 主時序：先處理上拍資料，再發下拍位址
    //   ※ 依你的要求：sh11/sh13 的 shift 改成使用 sram_q[0] 直接餵入
    // =======================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state         <= S_IDLE;

            row           <= 6'd0;
            col           <= 6'd0;
            prev_row      <= 6'd0;
            prev_col      <= 6'd0;

            sram_addr     <= 12'd0;
            sram_cen      <= 1'b1;
            sram_wen      <= 1'b1;

            q_valid       <= 1'b0;

            sh11          <= 11'd0;
            sh13          <= 13'd0;
            cnt11         <= 4'd0;
            cnt13         <= 4'd0;

            found_start   <= 1'b0;
            k_val         <= 8'd0;
            s_val         <= 8'd0;
            d_val         <= 8'd0;

            o_done        <= 1'b0;
            o_valid       <= 1'b0;
            o_kernel_size <= 8'd0;
            o_stride_size <= 8'd0;
            o_dilation_size <= 8'd0;
        end else begin
            state <= nstate;

            // 1) 先處理「上拍」資料（與 sram_q 對齊的 prev_row/prev_col）
            if (q_valid) begin
                case (state)
                    // ---------- SCAN：only prev_col <= 17 才允許比對 ----------
                    S_SCAN: begin
                        // ※ 依你的要求：直接用 sram_q[0] 進 shift
                        sh11 <= {sh11[9:0], sram_q[0]};
                        if (cnt11 != 4'd11) cnt11 <= cnt11 + 4'd1;

                        if (!found_start && cnt11>=4'd11 && (prev_col <= SCAN_CUTOFF)) begin
                            if (sh11 == START_C_PAT) begin
                                found_start <= 1'b1;
                                cnt11       <= 4'd0;
                            end
                        end
                    end

                    // ---------- 11-bit 的三段：K、S、D ----------
                    S_DECODE_K, S_DECODE_S, S_DECODE_D: begin
                        sh11 <= {sh11[9:0], sram_q[0]};
                        if (cnt11 != 4'd11) cnt11 <= cnt11 + 4'd1;

                        if (cnt11==4'd11) begin
                            if (state==S_DECODE_K) begin
                                k_val <= (sh11==CODE_03_PAT) ? 8'd3 : 8'd0;
                            end else if (state==S_DECODE_S) begin
                                s_val <= (sh11==CODE_01_PAT) ? 8'd1 :
                                         (sh11==CODE_02_PAT) ? 8'd2 : 8'd0;
                            end else begin
                                d_val <= (sh11==CODE_01_PAT) ? 8'd1 :
                                         (sh11==CODE_02_PAT) ? 8'd2 : 8'd0;
                            end
                            sh11  <= 11'd0;
                            cnt11 <= 4'd0;
                        end
                    end

                    // ---------- STOP：13-bit ----------
                    S_DECODE_STOP: begin
                        sh13 <= {sh13[11:0], sram_q[0]};
                        if (cnt13 != 4'd13) cnt13 <= cnt13 + 4'd1;
                    end

                    default: ; // no-op
                endcase
            end

            // 2) 狀態轉移時的雜項控制
            case (state)
                S_IDLE: begin
                    // 啟動讀
                    sram_cen  <= 1'b0;
                    sram_wen  <= 1'b1; // read
                    // 清除旗標
                    found_start <= 1'b0;
                    k_val <= 8'd0; s_val <= 8'd0; d_val <= 8'd0;
                    sh11 <= 11'd0; cnt11 <= 4'd0;
                    sh13 <= 13'd0; cnt13 <= 4'd0;
                    o_done  <= 1'b0;
                    o_valid <= 1'b0;
                end

                S_VALIDATE: begin
                    sram_cen <= 1'b1; // 可關閉讀
                    if (k_val==8'd3 &&
                        (s_val==8'd1 || s_val==8'd2) &&
                        (d_val==8'd1 || d_val==8'd2) &&
                        (sh13==STOP_PAT)) begin
                        o_kernel_size   <= 8'd3;
                        o_stride_size   <= s_val;
                        o_dilation_size <= d_val;
                        o_valid         <= 1'b1;
                    end else begin
                        o_kernel_size   <= 8'd0;
                        o_stride_size   <= 8'd0;
                        o_dilation_size <= 8'd0;
                        o_valid         <= 1'b0;
                    end
                end

                S_DONE: begin
                    o_done <= 1'b1;
                end
                default: ;
            endcase

            // 3) 發出「下一拍要讀」的位址，並管線對齊 prev_row/prev_col/q_valid
            prev_row  <= row;
            prev_col  <= col;
            q_valid   <= (state!=S_IDLE);  // 進入讀取狀態下一拍後資料才有效

            // 下一拍要讀哪一格（位址 = row*64 + col）
            row       <= n_row;
            col       <= n_col;
            sram_addr <= {n_row, 6'd0} + n_col;  // n_row*64 + n_col
        end
    end

endmodule
