// ============================================================
// BCH hard-decision core (skeleton version)
//  - 只管流程與 handshake，不管演算法內容
// ============================================================
module bch_hard_core
#(
    parameter integer N_MAX = 1023,
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                 clk,
    input  wire                 rstn,      // synchronous, active-low

    input  wire                 start,     // 在 IDLE 打 1 拍，開始 decode
    input  wire [9:0]           n,
    input  wire [3:0]           t,
    input  wire [3:0]           m,

    input  wire [N_MAX-1:0]     hard_bits,

    output reg                  done,      // decode 完成，一拍 pulse
    output reg                  success,   // skeleton: 先一律拉 1，之後再改成真正判斷
    output reg [N_MAX-1:0]      err_vec
);

    // ------------------------------
    // State encoding
    // ------------------------------
    localparam [2:0]
        S_IDLE  = 3'd0,
        S_SYN   = 3'd1,
        S_BER   = 3'd2,
        S_CHIEN = 3'd3,
        S_DONE  = 3'd4;

    reg [2:0] state, state_next;

    // ------------------------------
    // Latched inputs
    // ------------------------------
    reg [9:0]           n_reg;
    reg [3:0]           t_reg;
    reg [3:0]           m_reg;
    reg [N_MAX-1:0]     hard_bits_reg;

    // ------------------------------
    // Submodule handshake signals
    // ------------------------------
    reg                 syn_start;
    wire                syn_done;
    wire [2*T_MAX*M_MAX-1:0]  syndromes;

    reg                 ber_start;
    wire                ber_done;
    wire                ber_failure;
    wire [3:0]          ber_degree;
    wire [(T_MAX+1)*M_MAX-1:0] sigma;

    reg                 chien_start;
    wire                chien_done;
    wire [N_MAX-1:0]    chien_err_vec;

    // ------------------------------
    // Output next-state
    // ------------------------------
    reg                 done_next;
    reg                 success_next;
    reg [N_MAX-1:0]     err_vec_next;

    // ============================================================
    //  Submodule instances (目前是 "假的" 版本，只用來 debug handshake)
    //  之後你可以把這三個 module 換成真正的 syn_calc/berlekamp/chien
    // ============================================================

    // 假的 syndrome 計算：看到 start 後延遲幾拍，拉 done
    syn_calc #(
        .N_MAX (N_MAX),
        .T_MAX (T_MAX),
        .M_MAX (M_MAX)
    ) u_syn_calc (
        .clk       (clk),
        .rstn      (rstn),
        .start     (syn_start),
        .n         (n_reg),
        .t         (t_reg),
        .m         (m_reg),
        .hard_bits (hard_bits_reg),
        .done      (syn_done),
        .syndromes (syndromes)
    );

    // 假的 Berlekamp：看到 start 後延遲幾拍，拉 done
    berlekamp #(
        .T_MAX (T_MAX),
        .M_MAX (M_MAX)
    ) u_berlekamp (
        .clk       (clk),
        .rstn      (rstn),
        .start     (ber_start),
        .t         (t_reg),
        .m         (m_reg),
        .syndromes (syndromes),
        .done      (ber_done),
        .failure   (ber_failure),
        .degree    (ber_degree),
        .sigma     (sigma)
    );

    // 假的 Chien search：看到 start 後延遲幾拍，拉 done
    chien #(
        .N_MAX (N_MAX),
        .T_MAX (T_MAX),
        .M_MAX (M_MAX)
    ) u_chien (
        .clk    (clk),
        .rstn   (rstn),
        .start  (chien_start),
        .n      (n_reg),
        .m      (m_reg),
        .degree (ber_degree),
        .sigma  (sigma),
        .done   (chien_done),
        .err_vec(chien_err_vec)
    );

    // ============================================================
    //  Sequential: 狀態與暫存器
    // ============================================================
    always @(posedge clk) begin
        if (!rstn) begin
            state          <= S_IDLE;
            n_reg          <= 10'd0;
            t_reg          <= 4'd0;
            m_reg          <= 4'd0;
            hard_bits_reg  <= {N_MAX{1'b0}};

            done           <= 1'b0;
            success        <= 1'b0;
            err_vec        <= {N_MAX{1'b0}};
        end else begin
            state   <= state_next;
            done    <= done_next;
            success <= success_next;
            err_vec <= err_vec_next;

            // 在 IDLE 並且 start=1 的那一拍，latch inputs
            if (state == S_IDLE && start) begin
                n_reg         <= n;
                t_reg         <= t;
                m_reg         <= m;
                hard_bits_reg <= hard_bits;
            end
        end
    end

    // ============================================================
    //  Combinational: 下一狀態與 handshake 脈波
    // ============================================================
    always @* begin
        // 預設保持原狀
        state_next   = state;

        // 預設 output 下一拍
        done_next    = 1'b0;        // 預設 done 為 0，只有在 S_CHIEN → S_DONE transition 才打一拍
        success_next = success;     // 預設維持上一輪結果
        err_vec_next = err_vec;

        // submodule start pulse 預設為 0
        syn_start    = 1'b0;
        ber_start    = 1'b0;
        chien_start  = 1'b0;

        case (state)
            // --------------------------
            // IDLE: 等待 start
            // --------------------------
            S_IDLE: begin
                // 新的一輪開始時，可以考慮順便把 success 清為 0
                if (start) begin
                    state_next   = S_SYN;
                    syn_start    = 1'b1;   // 啟動 syn_calc，一拍 pulse
                    success_next = 1'b0;   // 新一輪 decode，先假設還沒成功
                end
            end

            // --------------------------
            // S_SYN: 等 syn_calc.done
            // --------------------------
            S_SYN: begin
                if (syn_done) begin
                    state_next = S_BER;
                    ber_start  = 1'b1;     // 啟動 berlekamp，一拍 pulse
                end
            end

            // --------------------------
            // S_BER: 等 berlekamp.done
            // --------------------------
            S_BER: begin
                if (ber_done) begin
                    state_next  = S_CHIEN;
                    chien_start = 1'b1;    // 啟動 chien，一拍 pulse
                end
            end

            // --------------------------
            // S_CHIEN: 等 chien.done
            // --------------------------
            S_CHIEN: begin
                if (chien_done) begin
                    state_next   = S_DONE;
                    done_next    = 1'b1;          // 對外宣告 decode 完成（打一拍）
                    success_next = 1'b1;          // skeleton 先一律當作成功
                    err_vec_next = chien_err_vec; // skeleton 先直接接 chien 的輸出
                end
            end

            // --------------------------
            // S_DONE: 結束，回到 IDLE
            // --------------------------
            S_DONE: begin
                state_next = S_IDLE;
                // done_next 在這裡已經回到 0（上面預設），所以 done 只會有一拍
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

endmodule
