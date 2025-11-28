// ============================================================
// BCH hard-decision core (skeleton version) -- updated with
//   success conditions and syndrome-all-zero detection
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
    output reg                  success,   // decode 是否成功
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
    //  Submodule instances（保持原樣）
    // ============================================================

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
    //   ★★★ 新增：syndrome 是否全 0 判斷 ★★★
    // ============================================================
    wire syn_all_zero;  /*** ADD ***/
    assign syn_all_zero = (syndromes == {2*T_MAX*M_MAX{1'b0}});

    // ============================================================
    //  Sequential
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

            if (state == S_IDLE && start) begin
                n_reg         <= n;
                t_reg         <= t;
                m_reg         <= m;
                hard_bits_reg <= hard_bits;
            end
        end
    end

    // ============================================================
    //  Combinational
    // ============================================================
    always @* begin
        // 預設保持
        state_next   = state;

        done_next    = 1'b0;
        success_next = success;
        err_vec_next = err_vec;

        syn_start    = 1'b0;
        ber_start    = 1'b0;
        chien_start  = 1'b0;

        case (state)

            S_IDLE: begin
                if (start) begin
                    state_next   = S_SYN;
                    syn_start    = 1'b1;
                    success_next = 1'b0;
                end
            end

            S_SYN: begin
                if (syn_done) begin
                    state_next = S_BER;
                    ber_start  = 1'b1;
                end
            end

            S_BER: begin
                if (ber_done) begin
                    state_next  = S_CHIEN;
                    chien_start = 1'b1;
                end
            end

            // ====================================================
            // ★★★ 修改：加入正確的成功條件 ★★★
            // ====================================================
            S_CHIEN: begin
                if (chien_done) begin
                    state_next = S_DONE;
                    done_next  = 1'b1;

                    // ---- 成功條件 ----

                    if (syn_all_zero) begin
                        // syndrome = 0 → 原本就沒錯誤
                        success_next = 1'b1;
                        err_vec_next = {N_MAX{1'b0}};

                    end else if (ber_failure || (ber_degree > t_reg)) begin
                        // Berlekamp fail，或 sigma degree > t
                        success_next = 1'b0;
                        err_vec_next = {N_MAX{1'b0}};

                    end else begin
                        // 合理的 sigma → 相信 Chien 的 err_vec
                        success_next = 1'b1;
                        err_vec_next = chien_err_vec;
                    end
                end
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            default: state_next = S_IDLE;

        endcase
    end

endmodule
