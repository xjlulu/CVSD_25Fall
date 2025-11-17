`timescale 1ns/10ps
module IOTDF( clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
input          clk;
input          rst;
input          in_en;
input  [7:0]   iot_in;
input  [2:0]   fn_sel;
output         busy;
output         valid;
output [127:0] iot_out;

// ======== internal reg 版本的輸出，再 assign 出去 ========
reg          busy_r,   next_busy;
reg          valid_r,  next_valid;
reg [127:0]  iot_out_r, next_iot_out;

assign busy   = busy_r || (in_en && !busy_r && (byte_cnt == 4'd15));
assign valid  = valid_r;
assign iot_out= iot_out_r;

// ======== FSM 狀態 ========
localparam S_IDLE   = 3'd0;
localparam S_INPUT  = 3'd1;
localparam S_PREP   = 3'd2;
localparam S_F_DES  = 3'd3;
localparam S_F_CRC  = 3'd4;
localparam S_F_SORT = 3'd5;
localparam S_OUTPUT = 3'd6;

reg [2:0] state, next_state;

// 收資料用的 counter & buffer
reg  [3:0]   byte_cnt,  next_byte_cnt;
reg  [127:0] data_in,   next_data_in;

// ======== submodule 介面 ========

// DES (F1/F2 共用)
wire        des_done;
wire [63:0] des_text_out;

// CRC (F3)
wire        crc_done;
wire [2:0]  crc_out;

// Sort (F4)
wire        sort_done;
wire [127:0] sort_out;

// key / text 切割
wire [63:0] key_in  = data_in[127:64];
wire [63:0] text_in = data_in[63:0];

// F1 / F2 判斷
wire is_des_enc = (fn_sel == 3'b001);
wire is_des_dec = (fn_sel == 3'b010);

// start pulse：在 S_PREP 那一拍依 fn_sel 產生
wire des_start  = (state == S_PREP) && (fn_sel == 3'b001 || fn_sel == 3'b010);
wire crc_start  = (state == S_PREP) && (fn_sel == 3'b011);
wire sort_start = (state == S_PREP) && (fn_sel == 3'b100);

// ======== submodules ========
des_core u_des_core(
    .clk       (clk),
    .rst       (rst),
    .start     (des_start),
    .is_decrypt(is_des_dec),
    .key_in    (key_in),
    .text_in   (text_in),
    .done      (des_done),
    .text_out  (des_text_out)
);

crc3_core u_crc3_core(
    .clk    (clk),
    .rst    (rst),
    .start  (crc_start),
    .data_in(data_in),
    .done   (crc_done),
    .crc_out(crc_out)
);

sort16_desc u_sort16_desc(
    .clk     (clk),
    .rst     (rst),
    .start   (sort_start),
    .data_in (data_in),
    .done    (sort_done),
    .data_out(sort_out)
);

// ============================================================
//  組合邏輯：next_state / next_*
// ============================================================
always @(*) begin
    // default（避免 latch）
    next_state    = state;
    next_byte_cnt = byte_cnt;
    next_data_in  = data_in;

    next_busy     = busy_r;
    next_valid    = 1'b0;         // 除了 S_OUTPUT 之外，valid 下一拍預設 0
    next_iot_out  = iot_out_r;

    case (state)
        // ----------------------------------------------------
        // S_IDLE：等待第一個 byte
        // ----------------------------------------------------
        S_IDLE: begin
            next_busy     = 1'b0;
            next_byte_cnt = 4'd0;

            if (in_en && !busy_r) begin
                // 第 0 個 byte：新在左，舊往右推
                next_data_in  = { iot_in, data_in[127:8] };
                next_byte_cnt = 4'd1;
                next_state    = S_INPUT;
            end
        end

        // ----------------------------------------------------
        // S_INPUT：收剩下的 15 個 byte
        // ----------------------------------------------------
        S_INPUT: begin
            next_busy = 1'b0;

            if (in_en && !busy_r) begin
                next_data_in = { iot_in, data_in[127:8] };

                if (byte_cnt == 4'd15) begin
                    next_busy     = 1'b1;
                    next_byte_cnt = 4'd0;
                    next_state    = S_PREP;
                end else begin
                    next_byte_cnt = byte_cnt + 4'd1;
                end
            end
        end

        // ----------------------------------------------------
        // S_PREP：依 fn_sel 啟動對應 core（start 由 assign 產生）
        // ----------------------------------------------------
        S_PREP: begin
            next_busy = 1'b1;

            case (fn_sel)
                3'b001, 3'b010: next_state = S_F_DES;   // F1/F2 → DES
                3'b011:         next_state = S_F_CRC;   // F3 → CRC
                3'b100:         next_state = S_F_SORT;  // F4 → SORT
                default: begin
                    next_iot_out = 128'd0;
                    next_state   = S_OUTPUT;
                end
            endcase
        end

        // ----------------------------------------------------
        // S_F_DES：DES Encrypt / Decrypt
        // ----------------------------------------------------
        S_F_DES: begin
            next_busy = 1'b1;

            if (des_done) begin
                next_iot_out = { key_in, des_text_out };
                next_state   = S_OUTPUT;
            end
        end

        // ----------------------------------------------------
        // S_F_CRC：CRC3
        // ----------------------------------------------------
        S_F_CRC: begin
            next_busy = 1'b1;

            if (crc_done) begin
                next_iot_out = { 125'd0, crc_out };
                next_state   = S_OUTPUT;
            end
        end

        // ----------------------------------------------------
        // S_F_SORT：Sorting 16 bytes
        // ----------------------------------------------------
        S_F_SORT: begin
            next_busy = 1'b1;

            if (sort_done) begin
                next_iot_out = sort_out;
                next_state   = S_OUTPUT;
            end
        end

        // ----------------------------------------------------
        // S_OUTPUT：valid=1 一個 cycle，然後回 S_IDLE
        // ----------------------------------------------------
        S_OUTPUT: begin
            next_busy  = 1'b0;
            next_valid = 1'b1;
            next_state = S_IDLE;
        end

        default: begin
            next_state = S_IDLE;
        end
    endcase
end


// ============================================================
//  時序 1：state
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
    end else begin
        state <= next_state;
    end
end

// ============================================================
//  時序 2：data_in / byte_cnt
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        data_in  <= 128'd0;
        byte_cnt <= 4'd0;
    end else begin
        data_in  <= next_data_in;
        byte_cnt <= next_byte_cnt;
    end
end

// ============================================================
//  時序 3：busy_r / valid_r / iot_out_r
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        busy_r    <= 1'b0;
        valid_r   <= 1'b0;
        iot_out_r <= 128'd0;
    end else begin
        busy_r    <= next_busy;
        valid_r   <= next_valid;
        iot_out_r <= next_iot_out;
    end
end

endmodule
