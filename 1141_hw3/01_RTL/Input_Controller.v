`timescale 1ns/1ps
module Input_Controller(
    input              i_clk,
    input              i_rst_n,
    input              i_in_valid,
    input      [31:0]  i_in_data,
    output reg         o_in_ready,
    output reg         image_done,

    // SRAM interface
    output reg  [11:0] sram_addr,
    output reg  [7:0]  sram_din,
    output reg         sram_cen,   // active low
    output reg         sram_wen   // active low
);

    // ------------------------------------------------------------
    // Internal states
    // ------------------------------------------------------------
    localparam S_IDLE  = 2'd0;
    localparam S_WRITE = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0] state, next_state;

    reg [31:0] data_buf;
    reg [1:0]  byte_cnt, byte_cnt_n;     // 0~3, which byte of the 32-bit data
    reg [11:0] addr_cnt;     // 0~4095

    // ------------------------------------------------------------
    // FSM state transition
    // ------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (i_in_valid)
                    next_state = S_WRITE;
            end

            S_WRITE: begin
                // 寫完 4096 bytes 之後就結束
                if (addr_cnt == 12'd4095 && byte_cnt == 2'd3)
                    next_state = S_DONE;
                // 寫完這 4 bytes 後可回去等新輸入
                else if (byte_cnt == 2'd3)
                    next_state = S_IDLE;
            end

            S_DONE: begin
                next_state = S_DONE;
            end
        endcase
    end

    always @(*) begin
        byte_cnt_n = byte_cnt;
        case (state)
            S_IDLE: begin
            // 只在「真的接到一筆新資料」時把 counter 啟動/歸 0
            if (i_in_valid && o_in_ready)
                byte_cnt_n = 2'd0;
            end
            S_WRITE: begin
            // 連續 4 個 byte：0,1,2,3 -> 回 0
            byte_cnt_n = (byte_cnt == 2'd3) ? 2'd0 : (byte_cnt + 2'd1);
            end
            default: ;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            byte_cnt <= 2'd0;
        else
            byte_cnt <= byte_cnt_n;
    end
    
    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_in_ready  <= 1'b0;
            image_done  <= 1'b0;
            sram_cen    <= 1'b1;
            sram_wen    <= 1'b1;
            sram_addr   <= 12'd0;
            sram_din    <= 8'd0;
            addr_cnt    <= 12'd0;
            data_buf    <= 32'd0;
        end
        else begin
            case (state)
                // ===================================================
                // IDLE: 等待上層給資料
                // ===================================================
                S_IDLE: begin
                    sram_cen   <= 1'b0;
                    sram_wen   <= 1'b0;
                    image_done <= 1'b0;

                    // 準備好接收下一個 32-bit 輸入
                    o_in_ready <= 1'b1;

                    if (i_in_valid && o_in_ready) begin
                        data_buf   <= i_in_data;
                        o_in_ready <= 1'b0; // 接收後關閉 ready
                    end
                end

                // ===================================================
                // WRITE: 將 data_buf 內容拆成 4 byte 寫入 SRAM
                // ===================================================
                S_WRITE: begin
                    case (byte_cnt)
                        2'd0: sram_din <= data_buf[31:24];
                        2'd1: sram_din <= data_buf[23:16];
                        2'd2: sram_din <= data_buf[15:8];
                        2'd3: sram_din <= data_buf[7:0];
                    endcase

                    sram_addr <= addr_cnt;

                    // 寫完後更新計數器
                    if (addr_cnt < 12'd4095)
                        addr_cnt <= addr_cnt + 1'b1;

                    // 若這 4 bytes 寫完，讓 FSM 回到 IDLE，ready 再開
                    if (byte_cnt == 2'd3 && addr_cnt != 12'd4095) begin
                        o_in_ready <= 1'b1;
                        sram_cen   <= 1'b1;
                        sram_wen   <= 1'b1;
                    end
                    else begin
                        o_in_ready <= 1'b0;
                        sram_cen   <= 1'b0;  // enable
                        sram_wen   <= 1'b0;  // write enable
                    end
                end

                // ===================================================
                // DONE: 全部影像寫完，觸發 image_done
                // ===================================================
                S_DONE: begin
                    o_in_ready  <= 1'b0;
                    sram_cen    <= 1'b1;
                    sram_wen    <= 1'b1;
                    image_done  <= 1'b1;  // 單一 cycle pulse
                end
            endcase
        end
    end

endmodule
