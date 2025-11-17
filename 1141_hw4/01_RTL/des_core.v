`timescale 1ns/10ps
module des_core(
    input         clk,
    input         rst,
    input         start,
    input         is_decrypt,   // 0: encrypt (F1), 1: decrypt (F2)
    input  [63:0] key_in,
    input  [63:0] text_in,
    output reg    done,
    output reg [63:0] text_out
);

// ============================================================
//  state encoding
// ============================================================
localparam S_IDLE  = 2'd0;
localparam S_KEY   = 2'd1;
localparam S_ROUND = 2'd2;
localparam S_DONE  = 2'd3;

reg [1:0] state, next_state;

// ============================================================
//  key schedule reg
// ============================================================
reg [27:0] C, D;
reg [27:0] next_C, next_D;
reg [3:0]  round_idx, next_round_idx;

// 16 組 subkey
reg  [47:0] subkey [0:15];
reg         subkey_we;
reg  [3:0]  subkey_widx;
reg  [47:0] subkey_wdata;

// ============================================================
//  data path reg
// ============================================================
reg [31:0] L_reg, R_reg;
reg [31:0] next_L_reg, next_R_reg;

reg [63:0] next_text_out;
reg        next_done;

// ============================================================
//  helper function 的輸出 (由你自己的 function 來實作)
// ============================================================
wire [55:0] pc1_out;
wire [63:0] ip_out;
wire [1:0]  shift_val;
wire [27:0] C_rot, D_rot;
wire [55:0] CD_rot;
wire [47:0] cur_subkey;
wire [31:0] f_out;
wire [31:0] L_round_next, R_round_next;

// -------- 呼叫你的 helper functions --------
assign pc1_out = pc1_perm(key_in);      // 由你自己實作 pc1_perm
assign ip_out  = ip_perm(text_in);      // 由你自己實作 ip_perm

// 左循環 shift schedule（round 1,2,9,16 shift=1，其餘 shift=2）
assign shift_val =
    (round_idx == 4'd0  ||
     round_idx == 4'd1  ||
     round_idx == 4'd8  ||
     round_idx == 4'd15) ? 2'd1 : 2'd2;

// 28-bit 左循環
assign C_rot = rotl28(C, shift_val);    // 由你自己實作 rotl28
assign D_rot = rotl28(D, shift_val);

assign CD_rot = {C_rot, D_rot};

// subkey 選擇（解密時反向）
assign cur_subkey = (is_decrypt) ? subkey[15 - round_idx] : subkey[round_idx];

// f 函數：F(R, K)
assign f_out = f_function(R_reg, cur_subkey);  // 由你自己實作 f_function

// 一輪 DES round 的 L/R 更新
assign L_round_next = R_reg;
assign R_round_next = L_reg ^ f_out;

// ============================================================
//  組合邏輯：next_state, next_*
// ============================================================
integer i;
always @(*) begin
    // default：保持不變
    next_state      = state;

    next_C          = C;
    next_D          = D;
    next_round_idx  = round_idx;

    next_L_reg      = L_reg;
    next_R_reg      = R_reg;

    next_text_out   = text_out;
    next_done       = 1'b0;

    subkey_we       = 1'b0;
    subkey_widx     = 4'd0;
    subkey_wdata    = 48'd0;

    case (state)
        // ----------------------------------------------------
        // S_IDLE：等 start，先做 PC1，把 key 切成 C0,D0
        // ----------------------------------------------------
        S_IDLE: begin
            if (start) begin
                next_C         = pc1_out[55:28];
                next_D         = pc1_out[27:0];
                next_round_idx = 4'd0;
                next_state     = S_KEY;
            end
        end

        // ----------------------------------------------------
        // S_KEY：16 個 cycle 產生 subkey[0..15]
        //        每一 cycle 旋轉一次、產生一組 subkey
        // ----------------------------------------------------
        S_KEY: begin
            // 先把 C,D 更新為旋轉後
            next_C = C_rot;
            next_D = D_rot;

            // 以旋轉後的 C_rot,D_rot 產生本輪 subkey
            subkey_we    = 1'b1;
            subkey_widx  = round_idx;
            subkey_wdata = pc2_perm(CD_rot);  // 由你自己實作 pc2_perm

            if (round_idx == 4'd15) begin
                // 16 組 subkey 都準備好了，切 text 做 IP
                next_L_reg      = ip_out[63:32];
                next_R_reg      = ip_out[31:0];
                next_round_idx  = 4'd0;
                next_state      = S_ROUND;
            end
            else begin
                next_round_idx  = round_idx + 4'd1;
            end
        end

        // ----------------------------------------------------
        // S_ROUND：16 個 DES round
        // ----------------------------------------------------
        S_ROUND: begin
            // 每一拍做一輪： (L,R) -> (R, L ^ F(R,K))
            next_L_reg = L_round_next;
            next_R_reg = R_round_next;

            if (round_idx == 4'd15) begin
                // 第 16 輪結束，做 Final Permutation
                // 注意順序是 (R16,L16)
                next_text_out = fp_perm({R_round_next, L_round_next}); // 由你實作 fp_perm
                next_state    = S_DONE;
            end
            else begin
                next_round_idx = round_idx + 4'd1;
            end
        end

        // ----------------------------------------------------
        // S_DONE：done 拉 1 個 cycle
        // ----------------------------------------------------
        S_DONE: begin
            next_done  = 1'b1;
            next_state = S_IDLE;
        end

        default: begin
            next_state = S_IDLE;
        end
    endcase
end

// ============================================================
//  時序：state
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
    end
    else begin
        state <= next_state;
    end
end

// ============================================================
//  時序：key schedule reg (C, D, round_idx, subkey)
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        C          <= 28'd0;
        D          <= 28'd0;
        round_idx  <= 4'd0;
        for (i = 0; i < 16; i = i + 1) begin
            subkey[i] <= 48'd0;
        end
    end
    else begin
        C         <= next_C;
        D         <= next_D;
        round_idx <= next_round_idx;

        if (subkey_we) begin
            subkey[subkey_widx] <= subkey_wdata;
        end
    end
end

// ============================================================
//  時序：data path (L,R) + output (text_out, done)
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        L_reg    <= 32'd0;
        R_reg    <= 32'd0;
        text_out <= 64'd0;
        done     <= 1'b0;
    end
    else begin
        L_reg    <= next_L_reg;
        R_reg    <= next_R_reg;
        text_out <= next_text_out;
        done     <= next_done;
    end
end

// =============================
// 以下是你要填的 function / S-box
// =============================

// 28-bit 左循環 shift
function [27:0] rotl28;
    input [27:0] in_data;
    input [1:0]  sh;
    begin
        case (sh)
            2'd1: rotl28 = {in_data[26:0], in_data[27]};
            2'd2: rotl28 = {in_data[25:0], in_data[27:26]};
            default: rotl28 = in_data;
        endcase
    end
endfunction



// =======================
// S-boxes + f function
// =======================

// f(R, K) = P( S-box( E(R) XOR K ) )
function [31:0] f_function;
    input [31:0] R;
    input [47:0] K;
    reg   [47:0] ex;
    reg   [47:0] x;
    reg   [5:0]  b0,b1,b2,b3,b4,b5,b6,b7;
    reg   [3:0]  s0,s1,s2,s3,s4,s5,s6,s7;
    reg   [31:0] s_out;
    begin
        ex = expand_e(R);
        x  = ex ^ K;

        b0 = x[47:42];
        b1 = x[41:36];
        b2 = x[35:30];
        b3 = x[29:24];
        b4 = x[23:18];
        b5 = x[17:12];
        b6 = x[11:6];
        b7 = x[5:0];

        s0 = sbox1(b0);
        s1 = sbox2(b1);
        s2 = sbox3(b2);
        s3 = sbox4(b3);
        s4 = sbox5(b4);
        s5 = sbox6(b5);
        s6 = sbox7(b6);
        s7 = sbox8(b7);

        s_out = {s0,s1,s2,s3,s4,s5,s6,s7};
        f_function = perm_p(s_out);
    end
endfunction


// ------ PC1: 64-bit -> 56-bit ------
function [55:0] pc1_perm;
    input [63:0] in_data;
    begin
        pc1_perm = { 56{1'b0} };
        pc1_perm[55] = in_data[7];
        pc1_perm[54] = in_data[15];
        pc1_perm[53] = in_data[23];
        pc1_perm[52] = in_data[31];
        pc1_perm[51] = in_data[39];
        pc1_perm[50] = in_data[47];
        pc1_perm[49] = in_data[55];
        pc1_perm[48] = in_data[63];
        pc1_perm[47] = in_data[6];
        pc1_perm[46] = in_data[14];
        pc1_perm[45] = in_data[22];
        pc1_perm[44] = in_data[30];
        pc1_perm[43] = in_data[38];
        pc1_perm[42] = in_data[46];
        pc1_perm[41] = in_data[54];
        pc1_perm[40] = in_data[62];
        pc1_perm[39] = in_data[5];
        pc1_perm[38] = in_data[13];
        pc1_perm[37] = in_data[21];
        pc1_perm[36] = in_data[29];
        pc1_perm[35] = in_data[37];
        pc1_perm[34] = in_data[45];
        pc1_perm[33] = in_data[53];
        pc1_perm[32] = in_data[61];
        pc1_perm[31] = in_data[ 4];
        pc1_perm[30] = in_data[12];
        pc1_perm[29] = in_data[20];
        pc1_perm[28] = in_data[28];
        pc1_perm[27] = in_data[ 1];
        pc1_perm[26] = in_data[ 9];
        pc1_perm[25] = in_data[17];
        pc1_perm[24] = in_data[25];
        pc1_perm[23] = in_data[33];
        pc1_perm[22] = in_data[41];
        pc1_perm[21] = in_data[49];
        pc1_perm[20] = in_data[57];
        pc1_perm[19] = in_data[ 2];
        pc1_perm[18] = in_data[10];
        pc1_perm[17] = in_data[18];
        pc1_perm[16] = in_data[26];
        pc1_perm[15] = in_data[34];
        pc1_perm[14] = in_data[42];
        pc1_perm[13] = in_data[50];
        pc1_perm[12] = in_data[58];
        pc1_perm[11] = in_data[ 3];
        pc1_perm[10] = in_data[11];
        pc1_perm[9]  = in_data[19];
        pc1_perm[8]  = in_data[27];
        pc1_perm[7]  = in_data[35];
        pc1_perm[6]  = in_data[43];
        pc1_perm[5]  = in_data[51];
        pc1_perm[4]  = in_data[59];
        pc1_perm[3]  = in_data[36];
        pc1_perm[2]  = in_data[44];
        pc1_perm[1]  = in_data[52];
        pc1_perm[0]  = in_data[60];
    end
endfunction

// ------ PC2: 56-bit -> 48-bit ------
function [47:0] pc2_perm;
    input [55:0] in_data;
    begin
        pc2_perm = { 48{1'b0} };
        pc2_perm[47] = in_data[42];
        pc2_perm[46] = in_data[39];
        pc2_perm[45] = in_data[45];
        pc2_perm[44] = in_data[32];
        pc2_perm[43] = in_data[55];
        pc2_perm[42] = in_data[51];
        pc2_perm[41] = in_data[53];
        pc2_perm[40] = in_data[28];
        pc2_perm[39] = in_data[41];
        pc2_perm[38] = in_data[50];
        pc2_perm[37] = in_data[35];
        pc2_perm[36] = in_data[46];
        pc2_perm[35] = in_data[33];
        pc2_perm[34] = in_data[37];
        pc2_perm[33] = in_data[44];
        pc2_perm[32] = in_data[52];
        pc2_perm[31] = in_data[30];
        pc2_perm[30] = in_data[48];
        pc2_perm[29] = in_data[40];
        pc2_perm[28] = in_data[49];
        pc2_perm[27] = in_data[29];
        pc2_perm[26] = in_data[36];
        pc2_perm[25] = in_data[43];
        pc2_perm[24] = in_data[54];
        pc2_perm[23] = in_data[15];
        pc2_perm[22] = in_data[4];
        pc2_perm[21] = in_data[25];
        pc2_perm[20] = in_data[19];
        pc2_perm[19] = in_data[9];
        pc2_perm[18] = in_data[1];
        pc2_perm[17] = in_data[26];
        pc2_perm[16] = in_data[16];
        pc2_perm[15] = in_data[5];
        pc2_perm[14] = in_data[11];
        pc2_perm[13] = in_data[23];
        pc2_perm[12] = in_data[8];
        pc2_perm[11] = in_data[12];
        pc2_perm[10] = in_data[7];
        pc2_perm[9]  = in_data[17];
        pc2_perm[8]  = in_data[0];
        pc2_perm[7]  = in_data[22];
        pc2_perm[6]  = in_data[3];
        pc2_perm[5]  = in_data[10];
        pc2_perm[4]  = in_data[14];
        pc2_perm[3]  = in_data[6];
        pc2_perm[2]  = in_data[20];
        pc2_perm[1]  = in_data[27];
        pc2_perm[0]  = in_data[24];
    end
endfunction

// ------ Initial Permutation IP: 64 -> 64 ------
function [63:0] ip_perm;
    input [63:0] in_data;
    begin
        ip_perm = { 64{1'b0} };
        ip_perm[63] = in_data[6];
        ip_perm[62] = in_data[14];
        ip_perm[61] = in_data[22];
        ip_perm[60] = in_data[30];
        ip_perm[59] = in_data[38];
        ip_perm[58] = in_data[46];
        ip_perm[57] = in_data[54];
        ip_perm[56] = in_data[62];
        ip_perm[55] = in_data[4];
        ip_perm[54] = in_data[12];
        ip_perm[53] = in_data[20];
        ip_perm[52] = in_data[28];
        ip_perm[51] = in_data[36];
        ip_perm[50] = in_data[44];
        ip_perm[49] = in_data[52];
        ip_perm[48] = in_data[60];
        ip_perm[47] = in_data[2];
        ip_perm[46] = in_data[10];
        ip_perm[45] = in_data[18];
        ip_perm[44] = in_data[26];
        ip_perm[43] = in_data[34];
        ip_perm[42] = in_data[42];
        ip_perm[41] = in_data[50];
        ip_perm[40] = in_data[58];
        ip_perm[39] = in_data[0];
        ip_perm[38] = in_data[8];
        ip_perm[37] = in_data[16];
        ip_perm[36] = in_data[24];
        ip_perm[35] = in_data[32];
        ip_perm[34] = in_data[40];
        ip_perm[33] = in_data[48];
        ip_perm[32] = in_data[56];
        ip_perm[31] = in_data[7];
        ip_perm[30] = in_data[15];
        ip_perm[29] = in_data[23];
        ip_perm[28] = in_data[31];
        ip_perm[27] = in_data[39];
        ip_perm[26] = in_data[47];
        ip_perm[25] = in_data[55];
        ip_perm[24] = in_data[63];
        ip_perm[23] = in_data[5];
        ip_perm[22] = in_data[13];
        ip_perm[21] = in_data[21];
        ip_perm[20] = in_data[29];
        ip_perm[19] = in_data[37];
        ip_perm[18] = in_data[45];
        ip_perm[17] = in_data[53];
        ip_perm[16] = in_data[61];
        ip_perm[15] = in_data[3];
        ip_perm[14] = in_data[11];
        ip_perm[13] = in_data[19];
        ip_perm[12] = in_data[27];
        ip_perm[11] = in_data[35];
        ip_perm[10] = in_data[43];
        ip_perm[9]  = in_data[51];
        ip_perm[8]  = in_data[59];
        ip_perm[7]  = in_data[1];
        ip_perm[6]  = in_data[9];
        ip_perm[5]  = in_data[17];
        ip_perm[4]  = in_data[25];
        ip_perm[3]  = in_data[33];
        ip_perm[2]  = in_data[41];
        ip_perm[1]  = in_data[49];
        ip_perm[0]  = in_data[57];
    end
endfunction

// ------ Final Permutation FP: 64 -> 64 ------
function [63:0] fp_perm;
    input [63:0] in_data;
    begin
        fp_perm = { 64{1'b0} };
        fp_perm[63] = in_data[24];
        fp_perm[62] = in_data[56];
        fp_perm[61] = in_data[16];
        fp_perm[60] = in_data[48];
        fp_perm[59] = in_data[8];
        fp_perm[58] = in_data[40];
        fp_perm[57] = in_data[0];
        fp_perm[56] = in_data[32];
        fp_perm[55] = in_data[25];
        fp_perm[54] = in_data[57];
        fp_perm[53] = in_data[17];
        fp_perm[52] = in_data[49];
        fp_perm[51] = in_data[9];
        fp_perm[50] = in_data[41];
        fp_perm[49] = in_data[1];
        fp_perm[48] = in_data[33];
        fp_perm[47] = in_data[26];
        fp_perm[46] = in_data[58];
        fp_perm[45] = in_data[18];
        fp_perm[44] = in_data[50];
        fp_perm[43] = in_data[10];
        fp_perm[42] = in_data[42];
        fp_perm[41] = in_data[2];
        fp_perm[40] = in_data[34];
        fp_perm[39] = in_data[27];
        fp_perm[38] = in_data[59];
        fp_perm[37] = in_data[19];
        fp_perm[36] = in_data[51];
        fp_perm[35] = in_data[11];
        fp_perm[34] = in_data[43];
        fp_perm[33] = in_data[3];
        fp_perm[32] = in_data[35];
        fp_perm[31] = in_data[28];
        fp_perm[30] = in_data[60];
        fp_perm[29] = in_data[20];
        fp_perm[28] = in_data[52];
        fp_perm[27] = in_data[12];
        fp_perm[26] = in_data[44];
        fp_perm[25] = in_data[4];
        fp_perm[24] = in_data[36];
        fp_perm[23] = in_data[29];
        fp_perm[22] = in_data[61];
        fp_perm[21] = in_data[21];
        fp_perm[20] = in_data[53];
        fp_perm[19] = in_data[13];
        fp_perm[18] = in_data[45];
        fp_perm[17] = in_data[5];
        fp_perm[16] = in_data[37];
        fp_perm[15] = in_data[30];
        fp_perm[14] = in_data[62];
        fp_perm[13] = in_data[22];
        fp_perm[12] = in_data[54];
        fp_perm[11] = in_data[14];
        fp_perm[10] = in_data[46];
        fp_perm[9]  = in_data[6];
        fp_perm[8]  = in_data[38];
        fp_perm[7]  = in_data[31];
        fp_perm[6]  = in_data[63];
        fp_perm[5]  = in_data[23];
        fp_perm[4]  = in_data[55];
        fp_perm[3]  = in_data[15];
        fp_perm[2]  = in_data[47];
        fp_perm[1]  = in_data[7];
        fp_perm[0]  = in_data[39];
    end
endfunction

// ------ Expansion E: 32 -> 48 ------
function [47:0] expand_e;
    input [31:0] in_data;
    begin
        expand_e = { 48{1'b0} };
        expand_e[47] = in_data[0];
        expand_e[46] = in_data[31];
        expand_e[45] = in_data[30];
        expand_e[44] = in_data[29];
        expand_e[43] = in_data[28];
        expand_e[42] = in_data[27];
        expand_e[41] = in_data[28];
        expand_e[40] = in_data[27];
        expand_e[39] = in_data[26];
        expand_e[38] = in_data[25];
        expand_e[37] = in_data[24];
        expand_e[36] = in_data[23];
        expand_e[35] = in_data[24];
        expand_e[34] = in_data[23];
        expand_e[33] = in_data[22];
        expand_e[32] = in_data[21];
        expand_e[31] = in_data[20];
        expand_e[30] = in_data[19];
        expand_e[29] = in_data[20];
        expand_e[28] = in_data[19];
        expand_e[27] = in_data[18];
        expand_e[26] = in_data[17];
        expand_e[25] = in_data[16];
        expand_e[24] = in_data[15];
        expand_e[23] = in_data[16];
        expand_e[22] = in_data[15];
        expand_e[21] = in_data[14];
        expand_e[20] = in_data[13];
        expand_e[19] = in_data[12];
        expand_e[18] = in_data[11];
        expand_e[17] = in_data[12];
        expand_e[16] = in_data[11];
        expand_e[15] = in_data[10];
        expand_e[14] = in_data[9];
        expand_e[13] = in_data[8];
        expand_e[12] = in_data[7];
        expand_e[11] = in_data[8];
        expand_e[10] = in_data[7];
        expand_e[9]  = in_data[6];
        expand_e[8]  = in_data[5];
        expand_e[7]  = in_data[4];
        expand_e[6]  = in_data[3];
        expand_e[5]  = in_data[4];
        expand_e[4]  = in_data[3];
        expand_e[3]  = in_data[2];
        expand_e[2]  = in_data[1];
        expand_e[1]  = in_data[0];
        expand_e[0]  = in_data[31];
    end
endfunction

// ------ P permutation: 32 -> 32 ------
function [31:0] perm_p;
    input [31:0] in_data;
    begin
        perm_p = { 32{1'b0} };
        perm_p[31] = in_data[16];
        perm_p[30] = in_data[25];
        perm_p[29] = in_data[12];
        perm_p[28] = in_data[11];
        perm_p[27] = in_data[3];
        perm_p[26] = in_data[20];
        perm_p[25] = in_data[4];
        perm_p[24] = in_data[15];
        perm_p[23] = in_data[31];
        perm_p[22] = in_data[17];
        perm_p[21] = in_data[9];
        perm_p[20] = in_data[6];
        perm_p[19] = in_data[27];
        perm_p[18] = in_data[14];
        perm_p[17] = in_data[1];
        perm_p[16] = in_data[22];
        perm_p[15] = in_data[30];
        perm_p[14] = in_data[24];
        perm_p[13] = in_data[8];
        perm_p[12] = in_data[18];
        perm_p[11] = in_data[0];
        perm_p[10] = in_data[5];
        perm_p[9]  = in_data[29];
        perm_p[8]  = in_data[23];
        perm_p[7]  = in_data[13];
        perm_p[6]  = in_data[19];
        perm_p[5]  = in_data[2];
        perm_p[4]  = in_data[26];
        perm_p[3]  = in_data[10];
        perm_p[2]  = in_data[21];
        perm_p[1]  = in_data[28];
        perm_p[0]  = in_data[7];
    end
endfunction

// =======================
// S-boxes
// =======================

function [3:0] sbox1;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox1 = 4'd14;
            6'b000001: sbox1 = 4'd4;
            6'b000010: sbox1 = 4'd13;
            6'b000011: sbox1 = 4'd1;
            6'b000100: sbox1 = 4'd2;
            6'b000101: sbox1 = 4'd15;
            6'b000110: sbox1 = 4'd11;
            6'b000111: sbox1 = 4'd8;
            6'b001000: sbox1 = 4'd3;
            6'b001001: sbox1 = 4'd10;
            6'b001010: sbox1 = 4'd6;
            6'b001011: sbox1 = 4'd12;
            6'b001100: sbox1 = 4'd5;
            6'b001101: sbox1 = 4'd9;
            6'b001110: sbox1 = 4'd0;
            6'b001111: sbox1 = 4'd7;
            6'b010000: sbox1 = 4'd0;
            6'b010001: sbox1 = 4'd15;
            6'b010010: sbox1 = 4'd7;
            6'b010011: sbox1 = 4'd4;
            6'b010100: sbox1 = 4'd14;
            6'b010101: sbox1 = 4'd2;
            6'b010110: sbox1 = 4'd13;
            6'b010111: sbox1 = 4'd1;
            6'b011000: sbox1 = 4'd10;
            6'b011001: sbox1 = 4'd6;
            6'b011010: sbox1 = 4'd12;
            6'b011011: sbox1 = 4'd11;
            6'b011100: sbox1 = 4'd9;
            6'b011101: sbox1 = 4'd5;
            6'b011110: sbox1 = 4'd3;
            6'b011111: sbox1 = 4'd8;
            6'b100000: sbox1 = 4'd4;
            6'b100001: sbox1 = 4'd1;
            6'b100010: sbox1 = 4'd14;
            6'b100011: sbox1 = 4'd8;
            6'b100100: sbox1 = 4'd13;
            6'b100101: sbox1 = 4'd6;
            6'b100110: sbox1 = 4'd2;
            6'b100111: sbox1 = 4'd11;
            6'b101000: sbox1 = 4'd15;
            6'b101001: sbox1 = 4'd12;
            6'b101010: sbox1 = 4'd9;
            6'b101011: sbox1 = 4'd7;
            6'b101100: sbox1 = 4'd3;
            6'b101101: sbox1 = 4'd10;
            6'b101110: sbox1 = 4'd5;
            6'b101111: sbox1 = 4'd0;
            6'b110000: sbox1 = 4'd15;
            6'b110001: sbox1 = 4'd12;
            6'b110010: sbox1 = 4'd8;
            6'b110011: sbox1 = 4'd2;
            6'b110100: sbox1 = 4'd4;
            6'b110101: sbox1 = 4'd9;
            6'b110110: sbox1 = 4'd1;
            6'b110111: sbox1 = 4'd7;
            6'b111000: sbox1 = 4'd5;
            6'b111001: sbox1 = 4'd11;
            6'b111010: sbox1 = 4'd3;
            6'b111011: sbox1 = 4'd14;
            6'b111100: sbox1 = 4'd10;
            6'b111101: sbox1 = 4'd0;
            6'b111110: sbox1 = 4'd6;
            6'b111111: sbox1 = 4'd13;
            default:   sbox1 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox2;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox2 = 4'd15;
            6'b000001: sbox2 = 4'd1;
            6'b000010: sbox2 = 4'd8;
            6'b000011: sbox2 = 4'd14;
            6'b000100: sbox2 = 4'd6;
            6'b000101: sbox2 = 4'd11;
            6'b000110: sbox2 = 4'd3;
            6'b000111: sbox2 = 4'd4;
            6'b001000: sbox2 = 4'd9;
            6'b001001: sbox2 = 4'd7;
            6'b001010: sbox2 = 4'd2;
            6'b001011: sbox2 = 4'd13;
            6'b001100: sbox2 = 4'd12;
            6'b001101: sbox2 = 4'd0;
            6'b001110: sbox2 = 4'd5;
            6'b001111: sbox2 = 4'd10;
            6'b010000: sbox2 = 4'd3;
            6'b010001: sbox2 = 4'd13;
            6'b010010: sbox2 = 4'd4;
            6'b010011: sbox2 = 4'd7;
            6'b010100: sbox2 = 4'd15;
            6'b010101: sbox2 = 4'd2;
            6'b010110: sbox2 = 4'd8;
            6'b010111: sbox2 = 4'd14;
            6'b011000: sbox2 = 4'd12;
            6'b011001: sbox2 = 4'd0;
            6'b011010: sbox2 = 4'd1;
            6'b011011: sbox2 = 4'd10;
            6'b011100: sbox2 = 4'd6;
            6'b011101: sbox2 = 4'd9;
            6'b011110: sbox2 = 4'd11;
            6'b011111: sbox2 = 4'd5;
            6'b100000: sbox2 = 4'd0;
            6'b100001: sbox2 = 4'd14;
            6'b100010: sbox2 = 4'd7;
            6'b100011: sbox2 = 4'd11;
            6'b100100: sbox2 = 4'd10;
            6'b100101: sbox2 = 4'd4;
            6'b100110: sbox2 = 4'd13;
            6'b100111: sbox2 = 4'd1;
            6'b101000: sbox2 = 4'd5;
            6'b101001: sbox2 = 4'd8;
            6'b101010: sbox2 = 4'd12;
            6'b101011: sbox2 = 4'd6;
            6'b101100: sbox2 = 4'd9;
            6'b101101: sbox2 = 4'd3;
            6'b101110: sbox2 = 4'd2;
            6'b101111: sbox2 = 4'd15;
            6'b110000: sbox2 = 4'd13;
            6'b110001: sbox2 = 4'd8;
            6'b110010: sbox2 = 4'd10;
            6'b110011: sbox2 = 4'd1;
            6'b110100: sbox2 = 4'd3;
            6'b110101: sbox2 = 4'd15;
            6'b110110: sbox2 = 4'd4;
            6'b110111: sbox2 = 4'd2;
            6'b111000: sbox2 = 4'd11;
            6'b111001: sbox2 = 4'd6;
            6'b111010: sbox2 = 4'd7;
            6'b111011: sbox2 = 4'd12;
            6'b111100: sbox2 = 4'd0;
            6'b111101: sbox2 = 4'd5;
            6'b111110: sbox2 = 4'd14;
            6'b111111: sbox2 = 4'd9;
            default:   sbox2 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox3;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox3 = 4'd10;
            6'b000001: sbox3 = 4'd0;
            6'b000010: sbox3 = 4'd9;
            6'b000011: sbox3 = 4'd14;
            6'b000100: sbox3 = 4'd6;
            6'b000101: sbox3 = 4'd3;
            6'b000110: sbox3 = 4'd15;
            6'b000111: sbox3 = 4'd5;
            6'b001000: sbox3 = 4'd1;
            6'b001001: sbox3 = 4'd13;
            6'b001010: sbox3 = 4'd12;
            6'b001011: sbox3 = 4'd7;
            6'b001100: sbox3 = 4'd11;
            6'b001101: sbox3 = 4'd4;
            6'b001110: sbox3 = 4'd2;
            6'b001111: sbox3 = 4'd8;
            6'b010000: sbox3 = 4'd13;
            6'b010001: sbox3 = 4'd7;
            6'b010010: sbox3 = 4'd0;
            6'b010011: sbox3 = 4'd9;
            6'b010100: sbox3 = 4'd3;
            6'b010101: sbox3 = 4'd4;
            6'b010110: sbox3 = 4'd6;
            6'b010111: sbox3 = 4'd10;
            6'b011000: sbox3 = 4'd2;
            6'b011001: sbox3 = 4'd8;
            6'b011010: sbox3 = 4'd5;
            6'b011011: sbox3 = 4'd14;
            6'b011100: sbox3 = 4'd12;
            6'b011101: sbox3 = 4'd11;
            6'b011110: sbox3 = 4'd15;
            6'b011111: sbox3 = 4'd1;
            6'b100000: sbox3 = 4'd13;
            6'b100001: sbox3 = 4'd6;
            6'b100010: sbox3 = 4'd4;
            6'b100011: sbox3 = 4'd9;
            6'b100100: sbox3 = 4'd8;
            6'b100101: sbox3 = 4'd15;
            6'b100110: sbox3 = 4'd3;
            6'b100111: sbox3 = 4'd0;
            6'b101000: sbox3 = 4'd11;
            6'b101001: sbox3 = 4'd1;
            6'b101010: sbox3 = 4'd2;
            6'b101011: sbox3 = 4'd12;
            6'b101100: sbox3 = 4'd5;
            6'b101101: sbox3 = 4'd10;
            6'b101110: sbox3 = 4'd14;
            6'b101111: sbox3 = 4'd7;
            6'b110000: sbox3 = 4'd1;
            6'b110001: sbox3 = 4'd10;
            6'b110010: sbox3 = 4'd13;
            6'b110011: sbox3 = 4'd0;
            6'b110100: sbox3 = 4'd6;
            6'b110101: sbox3 = 4'd9;
            6'b110110: sbox3 = 4'd8;
            6'b110111: sbox3 = 4'd7;
            6'b111000: sbox3 = 4'd4;
            6'b111001: sbox3 = 4'd15;
            6'b111010: sbox3 = 4'd14;
            6'b111011: sbox3 = 4'd3;
            6'b111100: sbox3 = 4'd11;
            6'b111101: sbox3 = 4'd5;
            6'b111110: sbox3 = 4'd2;
            6'b111111: sbox3 = 4'd12;
            default:   sbox3 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox4;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox4 = 4'd7;
            6'b000001: sbox4 = 4'd13;
            6'b000010: sbox4 = 4'd14;
            6'b000011: sbox4 = 4'd3;
            6'b000100: sbox4 = 4'd0;
            6'b000101: sbox4 = 4'd6;
            6'b000110: sbox4 = 4'd9;
            6'b000111: sbox4 = 4'd10;
            6'b001000: sbox4 = 4'd1;
            6'b001001: sbox4 = 4'd2;
            6'b001010: sbox4 = 4'd8;
            6'b001011: sbox4 = 4'd5;
            6'b001100: sbox4 = 4'd11;
            6'b001101: sbox4 = 4'd12;
            6'b001110: sbox4 = 4'd4;
            6'b001111: sbox4 = 4'd15;
            6'b010000: sbox4 = 4'd13;
            6'b010001: sbox4 = 4'd8;
            6'b010010: sbox4 = 4'd11;
            6'b010011: sbox4 = 4'd5;
            6'b010100: sbox4 = 4'd6;
            6'b010101: sbox4 = 4'd15;
            6'b010110: sbox4 = 4'd0;
            6'b010111: sbox4 = 4'd3;
            6'b011000: sbox4 = 4'd4;
            6'b011001: sbox4 = 4'd7;
            6'b011010: sbox4 = 4'd2;
            6'b011011: sbox4 = 4'd12;
            6'b011100: sbox4 = 4'd1;
            6'b011101: sbox4 = 4'd10;
            6'b011110: sbox4 = 4'd14;
            6'b011111: sbox4 = 4'd9;
            6'b100000: sbox4 = 4'd10;
            6'b100001: sbox4 = 4'd6;
            6'b100010: sbox4 = 4'd9;
            6'b100011: sbox4 = 4'd0;
            6'b100100: sbox4 = 4'd12;
            6'b100101: sbox4 = 4'd11;
            6'b100110: sbox4 = 4'd7;
            6'b100111: sbox4 = 4'd13;
            6'b101000: sbox4 = 4'd15;
            6'b101001: sbox4 = 4'd1;
            6'b101010: sbox4 = 4'd3;
            6'b101011: sbox4 = 4'd14;
            6'b101100: sbox4 = 4'd5;
            6'b101101: sbox4 = 4'd2;
            6'b101110: sbox4 = 4'd8;
            6'b101111: sbox4 = 4'd4;
            6'b110000: sbox4 = 4'd3;
            6'b110001: sbox4 = 4'd15;
            6'b110010: sbox4 = 4'd0;
            6'b110011: sbox4 = 4'd6;
            6'b110100: sbox4 = 4'd10;
            6'b110101: sbox4 = 4'd1;
            6'b110110: sbox4 = 4'd13;
            6'b110111: sbox4 = 4'd8;
            6'b111000: sbox4 = 4'd9;
            6'b111001: sbox4 = 4'd4;
            6'b111010: sbox4 = 4'd5;
            6'b111011: sbox4 = 4'd11;
            6'b111100: sbox4 = 4'd12;
            6'b111101: sbox4 = 4'd7;
            6'b111110: sbox4 = 4'd2;
            6'b111111: sbox4 = 4'd14;
            default:   sbox4 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox5;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox5 = 4'd2;
            6'b000001: sbox5 = 4'd12;
            6'b000010: sbox5 = 4'd4;
            6'b000011: sbox5 = 4'd1;
            6'b000100: sbox5 = 4'd7;
            6'b000101: sbox5 = 4'd10;
            6'b000110: sbox5 = 4'd11;
            6'b000111: sbox5 = 4'd6;
            6'b001000: sbox5 = 4'd8;
            6'b001001: sbox5 = 4'd5;
            6'b001010: sbox5 = 4'd3;
            6'b001011: sbox5 = 4'd15;
            6'b001100: sbox5 = 4'd13;
            6'b001101: sbox5 = 4'd0;
            6'b001110: sbox5 = 4'd14;
            6'b001111: sbox5 = 4'd9;
            6'b010000: sbox5 = 4'd14;
            6'b010001: sbox5 = 4'd11;
            6'b010010: sbox5 = 4'd2;
            6'b010011: sbox5 = 4'd12;
            6'b010100: sbox5 = 4'd4;
            6'b010101: sbox5 = 4'd7;
            6'b010110: sbox5 = 4'd13;
            6'b010111: sbox5 = 4'd1;
            6'b011000: sbox5 = 4'd5;
            6'b011001: sbox5 = 4'd0;
            6'b011010: sbox5 = 4'd15;
            6'b011011: sbox5 = 4'd10;
            6'b011100: sbox5 = 4'd3;
            6'b011101: sbox5 = 4'd9;
            6'b011110: sbox5 = 4'd8;
            6'b011111: sbox5 = 4'd6;
            6'b100000: sbox5 = 4'd4;
            6'b100001: sbox5 = 4'd2;
            6'b100010: sbox5 = 4'd1;
            6'b100011: sbox5 = 4'd11;
            6'b100100: sbox5 = 4'd10;
            6'b100101: sbox5 = 4'd13;
            6'b100110: sbox5 = 4'd7;
            6'b100111: sbox5 = 4'd8;
            6'b101000: sbox5 = 4'd15;
            6'b101001: sbox5 = 4'd9;
            6'b101010: sbox5 = 4'd12;
            6'b101011: sbox5 = 4'd5;
            6'b101100: sbox5 = 4'd6;
            6'b101101: sbox5 = 4'd3;
            6'b101110: sbox5 = 4'd0;
            6'b101111: sbox5 = 4'd14;
            6'b110000: sbox5 = 4'd11;
            6'b110001: sbox5 = 4'd8;
            6'b110010: sbox5 = 4'd12;
            6'b110011: sbox5 = 4'd7;
            6'b110100: sbox5 = 4'd1;
            6'b110101: sbox5 = 4'd14;
            6'b110110: sbox5 = 4'd2;
            6'b110111: sbox5 = 4'd13;
            6'b111000: sbox5 = 4'd6;
            6'b111001: sbox5 = 4'd15;
            6'b111010: sbox5 = 4'd0;
            6'b111011: sbox5 = 4'd9;
            6'b111100: sbox5 = 4'd10;
            6'b111101: sbox5 = 4'd4;
            6'b111110: sbox5 = 4'd5;
            6'b111111: sbox5 = 4'd3;
            default:   sbox5 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox6;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox6 = 4'd12;
            6'b000001: sbox6 = 4'd1;
            6'b000010: sbox6 = 4'd10;
            6'b000011: sbox6 = 4'd15;
            6'b000100: sbox6 = 4'd9;
            6'b000101: sbox6 = 4'd2;
            6'b000110: sbox6 = 4'd6;
            6'b000111: sbox6 = 4'd8;
            6'b001000: sbox6 = 4'd0;
            6'b001001: sbox6 = 4'd13;
            6'b001010: sbox6 = 4'd3;
            6'b001011: sbox6 = 4'd4;
            6'b001100: sbox6 = 4'd14;
            6'b001101: sbox6 = 4'd7;
            6'b001110: sbox6 = 4'd5;
            6'b001111: sbox6 = 4'd11;
            6'b010000: sbox6 = 4'd10;
            6'b010001: sbox6 = 4'd15;
            6'b010010: sbox6 = 4'd4;
            6'b010011: sbox6 = 4'd2;
            6'b010100: sbox6 = 4'd7;
            6'b010101: sbox6 = 4'd12;
            6'b010110: sbox6 = 4'd9;
            6'b010111: sbox6 = 4'd5;
            6'b011000: sbox6 = 4'd6;
            6'b011001: sbox6 = 4'd1;
            6'b011010: sbox6 = 4'd13;
            6'b011011: sbox6 = 4'd14;
            6'b011100: sbox6 = 4'd0;
            6'b011101: sbox6 = 4'd11;
            6'b011110: sbox6 = 4'd3;
            6'b011111: sbox6 = 4'd8;
            6'b100000: sbox6 = 4'd9;
            6'b100001: sbox6 = 4'd14;
            6'b100010: sbox6 = 4'd15;
            6'b100011: sbox6 = 4'd5;
            6'b100100: sbox6 = 4'd2;
            6'b100101: sbox6 = 4'd8;
            6'b100110: sbox6 = 4'd12;
            6'b100111: sbox6 = 4'd3;
            6'b101000: sbox6 = 4'd7;
            6'b101001: sbox6 = 4'd0;
            6'b101010: sbox6 = 4'd4;
            6'b101011: sbox6 = 4'd10;
            6'b101100: sbox6 = 4'd1;
            6'b101101: sbox6 = 4'd13;
            6'b101110: sbox6 = 4'd11;
            6'b101111: sbox6 = 4'd6;
            6'b110000: sbox6 = 4'd4;
            6'b110001: sbox6 = 4'd3;
            6'b110010: sbox6 = 4'd2;
            6'b110011: sbox6 = 4'd12;
            6'b110100: sbox6 = 4'd9;
            6'b110101: sbox6 = 4'd5;
            6'b110110: sbox6 = 4'd15;
            6'b110111: sbox6 = 4'd10;
            6'b111000: sbox6 = 4'd11;
            6'b111001: sbox6 = 4'd14;
            6'b111010: sbox6 = 4'd1;
            6'b111011: sbox6 = 4'd7;
            6'b111100: sbox6 = 4'd6;
            6'b111101: sbox6 = 4'd0;
            6'b111110: sbox6 = 4'd8;
            6'b111111: sbox6 = 4'd13;
            default:   sbox6 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox7;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox7 = 4'd4;
            6'b000001: sbox7 = 4'd11;
            6'b000010: sbox7 = 4'd2;
            6'b000011: sbox7 = 4'd14;
            6'b000100: sbox7 = 4'd15;
            6'b000101: sbox7 = 4'd0;
            6'b000110: sbox7 = 4'd8;
            6'b000111: sbox7 = 4'd13;
            6'b001000: sbox7 = 4'd3;
            6'b001001: sbox7 = 4'd12;
            6'b001010: sbox7 = 4'd9;
            6'b001011: sbox7 = 4'd7;
            6'b001100: sbox7 = 4'd5;
            6'b001101: sbox7 = 4'd10;
            6'b001110: sbox7 = 4'd6;
            6'b001111: sbox7 = 4'd1;
            6'b010000: sbox7 = 4'd13;
            6'b010001: sbox7 = 4'd0;
            6'b010010: sbox7 = 4'd11;
            6'b010011: sbox7 = 4'd7;
            6'b010100: sbox7 = 4'd4;
            6'b010101: sbox7 = 4'd9;
            6'b010110: sbox7 = 4'd1;
            6'b010111: sbox7 = 4'd10;
            6'b011000: sbox7 = 4'd14;
            6'b011001: sbox7 = 4'd3;
            6'b011010: sbox7 = 4'd5;
            6'b011011: sbox7 = 4'd12;
            6'b011100: sbox7 = 4'd2;
            6'b011101: sbox7 = 4'd15;
            6'b011110: sbox7 = 4'd8;
            6'b011111: sbox7 = 4'd6;
            6'b100000: sbox7 = 4'd1;
            6'b100001: sbox7 = 4'd4;
            6'b100010: sbox7 = 4'd11;
            6'b100011: sbox7 = 4'd13;
            6'b100100: sbox7 = 4'd12;
            6'b100101: sbox7 = 4'd3;
            6'b100110: sbox7 = 4'd7;
            6'b100111: sbox7 = 4'd14;
            6'b101000: sbox7 = 4'd10;
            6'b101001: sbox7 = 4'd15;
            6'b101010: sbox7 = 4'd6;
            6'b101011: sbox7 = 4'd8;
            6'b101100: sbox7 = 4'd0;
            6'b101101: sbox7 = 4'd5;
            6'b101110: sbox7 = 4'd9;
            6'b101111: sbox7 = 4'd2;
            6'b110000: sbox7 = 4'd6;
            6'b110001: sbox7 = 4'd11;
            6'b110010: sbox7 = 4'd13;
            6'b110011: sbox7 = 4'd8;
            6'b110100: sbox7 = 4'd1;
            6'b110101: sbox7 = 4'd4;
            6'b110110: sbox7 = 4'd10;
            6'b110111: sbox7 = 4'd7;
            6'b111000: sbox7 = 4'd9;
            6'b111001: sbox7 = 4'd5;
            6'b111010: sbox7 = 4'd0;
            6'b111011: sbox7 = 4'd15;
            6'b111100: sbox7 = 4'd14;
            6'b111101: sbox7 = 4'd2;
            6'b111110: sbox7 = 4'd3;
            6'b111111: sbox7 = 4'd12;
            default:   sbox7 = 4'd0;
        endcase
    end
endfunction

function [3:0] sbox8;
    input [5:0] in;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {in[5], in[0]};
        col = in[4:1];
        case ({row, col})
            6'b000000: sbox8 = 4'd13;
            6'b000001: sbox8 = 4'd2;
            6'b000010: sbox8 = 4'd8;
            6'b000011: sbox8 = 4'd4;
            6'b000100: sbox8 = 4'd6;
            6'b000101: sbox8 = 4'd15;
            6'b000110: sbox8 = 4'd11;
            6'b000111: sbox8 = 4'd1;
            6'b001000: sbox8 = 4'd10;
            6'b001001: sbox8 = 4'd9;
            6'b001010: sbox8 = 4'd3;
            6'b001011: sbox8 = 4'd14;
            6'b001100: sbox8 = 4'd5;
            6'b001101: sbox8 = 4'd0;
            6'b001110: sbox8 = 4'd12;
            6'b001111: sbox8 = 4'd7;
            6'b010000: sbox8 = 4'd1;
            6'b010001: sbox8 = 4'd15;
            6'b010010: sbox8 = 4'd13;
            6'b010011: sbox8 = 4'd8;
            6'b010100: sbox8 = 4'd10;
            6'b010101: sbox8 = 4'd3;
            6'b010110: sbox8 = 4'd7;
            6'b010111: sbox8 = 4'd4;
            6'b011000: sbox8 = 4'd12;
            6'b011001: sbox8 = 4'd5;
            6'b011010: sbox8 = 4'd6;
            6'b011011: sbox8 = 4'd11;
            6'b011100: sbox8 = 4'd0;
            6'b011101: sbox8 = 4'd14;
            6'b011110: sbox8 = 4'd9;
            6'b011111: sbox8 = 4'd2;
            6'b100000: sbox8 = 4'd7;
            6'b100001: sbox8 = 4'd11;
            6'b100010: sbox8 = 4'd4;
            6'b100011: sbox8 = 4'd1;
            6'b100100: sbox8 = 4'd9;
            6'b100101: sbox8 = 4'd12;
            6'b100110: sbox8 = 4'd14;
            6'b100111: sbox8 = 4'd2;
            6'b101000: sbox8 = 4'd0;
            6'b101001: sbox8 = 4'd6;
            6'b101010: sbox8 = 4'd10;
            6'b101011: sbox8 = 4'd13;
            6'b101100: sbox8 = 4'd15;
            6'b101101: sbox8 = 4'd3;
            6'b101110: sbox8 = 4'd5;
            6'b101111: sbox8 = 4'd8;
            6'b110000: sbox8 = 4'd2;
            6'b110001: sbox8 = 4'd1;
            6'b110010: sbox8 = 4'd14;
            6'b110011: sbox8 = 4'd7;
            6'b110100: sbox8 = 4'd4;
            6'b110101: sbox8 = 4'd10;
            6'b110110: sbox8 = 4'd8;
            6'b110111: sbox8 = 4'd13;
            6'b111000: sbox8 = 4'd15;
            6'b111001: sbox8 = 4'd12;
            6'b111010: sbox8 = 4'd9;
            6'b111011: sbox8 = 4'd0;
            6'b111100: sbox8 = 4'd3;
            6'b111101: sbox8 = 4'd5;
            6'b111110: sbox8 = 4'd6;
            6'b111111: sbox8 = 4'd11;
            default:   sbox8 = 4'd0;
        endcase
    end
endfunction


endmodule
