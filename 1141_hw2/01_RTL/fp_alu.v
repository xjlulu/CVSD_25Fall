`timescale 1ns/100ps

module fp_alu (
    input  [6:0]      i_opcode,
    input  [6:0]      i_funct7,
    input  [2:0]      i_funct3,
    input  [31:0]     i_src1,
    input  [31:0]     i_src2,
    output reg [31:0] o_result,
    output reg        o_invalid
);
    // n1 = 3F000050 -> 0 01111110 0000000 00000000 01010000
    // n2 = 410005AC -> 0 10000010 0000000 00000101 10101100
    // exp1 = 126 - 127 = -1
    // exp2 = 130 - 127 = 3
    // real1 =                  0.10000000 00000000 01010000
    // real2 =               1000.0000  00000101 10101100
    //                       0111.11111111 10100101 0100
    // real1 =               0000.10000000 00000000 01010000
    // sum   =               1000.0111111110 1001011001
    //                        111.1000000001 01101001110
    // c0f00b4e =           1 10000001  11100000000101101001110
    //                        129-127=2 
    // 080005                0000 10000000000000000101
    // 080005                1111 01111111111111111011
    // 8005ac                1000 00000000010110101100
    // sum:                 10111100000000101101001110
    //                      10111100000000101101001110 00000000000000000000000
    // norm_mant:           001111000000001011010011
    // o_result:c23c02d3  1 10000100 01111000000001011010011
    // DUT: c0e0169c      1 10000001 11000000001011010011100
    // expec:c0f00b4e     1 10000001 11100000000101101001110  exp=129
    // new offset:        1 10000000 111000000001011010011100
    // mant aft rtn:                 011110000000010110100111
    // e0169c:                       111000000001011010011100
    // ----------------------------------------------------------------
    // Local parameters
    // ----------------------------------------------------------------
    localparam EXP_BIAS = 8'd127;
    localparam [6:0] OP_FP = 7'b1010011; // opcode for floating point

    // Classification bits
    localparam [31:0] NEG_INF       = 32'd1 << 0;
    localparam [31:0] NEG_NORMAL    = 32'd1 << 1;
    localparam [31:0] NEG_SUBNORMAL = 32'd1 << 2;
    localparam [31:0] NEG_ZERO      = 32'd1 << 3;
    localparam [31:0] POS_ZERO      = 32'd1 << 4;
    localparam [31:0] POS_SUBNORMAL = 32'd1 << 5;
    localparam [31:0] POS_NORMAL    = 32'd1 << 6;
    localparam [31:0] POS_INF       = 32'd1 << 7;
    localparam [31:0] SIG_NAN       = 32'd1 << 8;
    localparam [31:0] QUIET_NAN     = 32'd1 << 9;

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    reg sign1, sign2, sign_res;
    reg [7:0] exp1, exp2, exp_res;
    reg [23:0] frac1, frac2, frac1_shifted, frac2_shifted;
    reg [47:0] prod_mant;      // mantissa product
    reg [48:0] diff_mant;      // for subtraction (extended for borrow)
    reg [23:0] norm_mant;
    reg [7:0]  norm_exp;
    reg guard, round_bit, sticky;
    reg [26:0] mant_ext;       // for rounding stage
    reg [24:0] temp_round;
    reg [31:0] temp_result;

    // For invalid detection
    reg src1_is_nan, src2_is_nan;
    reg src1_is_inf, src2_is_inf;
    reg src1_is_zero, src2_is_zero;
    reg src1_is_subnormal;
    reg src1_is_signaling_nan, src1_is_quiet_nan;
    reg [7:0] exp_diff;
    reg [4:0] shift_amount;

    reg sign_a;
    reg sign_b;  // sign of -b

    reg [23:0] larger_mant, smaller_mant, larger_aligned, smaller_aligned;
    reg [7:0]  max_exp;
    reg larger_is_a;  // 1 if src1 larger
    reg same_effective_sign;
    reg sign_larger;
    reg sign_smaller;
    reg [23:0] new_mant;
    reg [7:0] new_exp;
    reg [4:0] offset;
    reg [23:0] rtn_norm_mant;
    
    // function to normalize mantissa (find first 1 using case, return offset, compute new_mant/new_exp)
    function automatic [4:0] normalize_offset;
        input reg [23:0] mant;
        normalize_offset = 5'd0; // Default: no shift
        casez (mant)
            24'b1???????????????????????: normalize_offset = 5'd0;
            24'b01??????????????????????: normalize_offset = 5'd1;
            24'b001?????????????????????: normalize_offset = 5'd2;
            24'b0001????????????????????: normalize_offset = 5'd3;
            24'b00001???????????????????: normalize_offset = 5'd4;
            24'b000001??????????????????: normalize_offset = 5'd5;
            24'b0000001?????????????????: normalize_offset = 5'd6;
            24'b00000001????????????????: normalize_offset = 5'd7;
            24'b000000001???????????????: normalize_offset = 5'd8;
            24'b0000000001??????????????: normalize_offset = 5'd9;
            24'b00000000001?????????????: normalize_offset = 5'd10;
            24'b000000000001????????????: normalize_offset = 5'd11;
            24'b0000000000001???????????: normalize_offset = 5'd12;
            24'b00000000000001??????????: normalize_offset = 5'd13;
            24'b000000000000001?????????: normalize_offset = 5'd14;
            24'b0000000000000001????????: normalize_offset = 5'd15;
            24'b00000000000000001???????: normalize_offset = 5'd16;
            24'b000000000000000001??????: normalize_offset = 5'd17;
            24'b0000000000000000001?????: normalize_offset = 5'd18;
            24'b00000000000000000001????: normalize_offset = 5'd19;
            24'b000000000000000000001???: normalize_offset = 5'd20;
            24'b0000000000000000000001??: normalize_offset = 5'd21;
            24'b00000000000000000000001?: normalize_offset = 5'd22;
            24'b000000000000000000000001: normalize_offset = 5'd23;
            default: normalize_offset = 5'd0; // Zero mantissa
        endcase
    endfunction


    // ----------------------------------------------------------------
    // Helper: round-to-nearest-even (RNE)
    // ----------------------------------------------------------------
    function [24:0] round_nearest_even;
        input [26:0] mant_ext; // mantissa with 3 extra bits [guard,round,sticky]
        begin
            if (mant_ext[2]) begin // guard bit set
                if (mant_ext[1] | mant_ext[0] | mant_ext[3]) // round or sticky
                    round_nearest_even = mant_ext[26:2] + 1'b1;
                else
                    round_nearest_even = mant_ext[26:2];
            end else begin
                round_nearest_even = mant_ext[26:2];
            end
        end
    endfunction

    // ----------------------------------------------------------------
    // Main combinational logic
    // ----------------------------------------------------------------
    always @(*) begin
        // Default outputs
        o_result  = 32'd0;
        o_invalid = 1'b0;

        // Default fields
        sign1 = i_src1[31];
        sign2 = i_src2[31];
        exp1  = i_src1[30:23];
        exp2  = i_src2[30:23];
        frac1 = {1'b1, i_src1[22:0]};
        frac2 = {1'b1, i_src2[22:0]};
        sign_a = sign1;
        sign_b = ~sign2;  // sign of -b

        // Special number detection
        src1_is_nan  = (exp1 == 8'hFF) && (i_src1[22:0] != 0);
        src2_is_nan  = (exp2 == 8'hFF) && (i_src2[22:0] != 0);
        src1_is_inf  = (exp1 == 8'hFF) && (i_src1[22:0] == 0);
        src2_is_inf  = (exp2 == 8'hFF) && (i_src2[22:0] == 0);
        src1_is_zero = (exp1 == 8'h00) && (i_src1[22:0] == 0);
        src2_is_zero = (exp2 == 8'h00) && (i_src2[22:0] == 0);
        src1_is_subnormal = (exp1 == 8'h00) && (i_src1[22:0] != 0);
        src1_is_signaling_nan = src1_is_nan && (i_src1[22] == 0);
        src1_is_quiet_nan = src1_is_nan && (i_src1[22] == 1);

        if (i_opcode == OP_FP) begin
            case (i_funct7)
                // ----------------------------------------------------
                // FSUB.S : f1 - f2 = f1 + (-f2)
                // ----------------------------------------------------
                7'b0000100: begin
                    // Invalid cases (IEEE-754 required)
                    if (src1_is_nan || src2_is_nan ||
                        (src1_is_inf && src2_is_inf && sign1 == sign2)) begin  // Inf - Inf (same sign) -> invalid
                        o_invalid = 1'b1;
                        o_result  = {1'b0, 8'hFF, 23'h400000}; // canonical quiet NaN
                    end else if (src1_is_inf) begin
                        o_result = {sign1, 8'hFF, 23'b0};       // Inf - finite = Inf
                    end else if (src2_is_inf) begin
                        o_result = {~sign2, 8'hFF, 23'b0};      // finite - Inf = -Inf
                    end else if (src1_is_zero && src2_is_zero) begin
                        o_result = {1'b0, 31'b0};               // 0 - 0 = +0 (IEEE prefer)
                    end else begin
                        // Handle subnormals: no implicit 1
                        frac1 = (exp1 == 0) ? {1'b0, i_src1[22:0]} : {1'b1, i_src1[22:0]};
                        frac2 = (exp2 == 0) ? {1'b0, i_src2[22:0]} : {1'b1, i_src2[22:0]};

                        // Effective signs: a - b = a + (-b)

                        // Step 1: Align & Find LARGER magnitude


                        if (exp1 > exp2) begin
                            exp_diff = exp1 - exp2;
                            smaller_aligned = frac2 >> exp_diff;
                            larger_aligned = frac1;
                            larger_mant = frac1;
                            smaller_mant = smaller_aligned;
                            max_exp = exp1;
                            larger_is_a = 1'b1;
                        end else if (exp1 < exp2) begin
                            exp_diff = exp2 - exp1;
                            smaller_aligned = frac1 >> exp_diff;
                            larger_aligned = frac2;
                            larger_mant = frac2;
                            smaller_mant = smaller_aligned;
                            max_exp = exp2;
                            larger_is_a = 1'b0;
                        end else begin  // exp1 == exp2
                            max_exp = exp1;
                            if (frac1 >= frac2) begin
                                larger_mant = frac1;
                                smaller_mant = frac2;
                                larger_is_a = 1'b1;
                            end else begin
                                larger_mant = frac2;
                                smaller_mant = frac1;
                                larger_is_a = 1'b0;
                            end
                            larger_aligned = larger_mant;
                            smaller_aligned = smaller_mant;
                        end

                        // Step 2: Determine signs of larger/smaller
                        sign_larger  = larger_is_a ? sign_a : sign_b;
                        sign_smaller = larger_is_a ? sign_b : sign_a;
                        same_effective_sign = (sign_larger == sign_smaller);

                        // Step 3: Add or Subtract magnitudes
                        diff_mant = {1'b0, larger_mant, 24'b0};
                        if (same_effective_sign) begin
                            // Same sign: ADD magnitudes
                            diff_mant = diff_mant + {1'b0, smaller_mant, 24'b0};
                        end else begin
                            // Diff sign: SUBTRACT magnitudes
                            diff_mant = diff_mant + to_twos_complement({1'b0, smaller_mant, 24'b0});
                        end
                        sign_res = sign_larger;

                        // Step 4: Normalize
                        norm_mant = diff_mant[47:24];
                        norm_exp = max_exp;
                        if (diff_mant[48] && same_effective_sign) begin  // Carry from ADD
                            norm_mant = diff_mant[48:25];
                            norm_exp = max_exp + 1;
                        end
                        // Normalize leading zeros (for cancellation in SUB)
                        offset = normalize_offset(norm_mant);
                        new_mant = (norm_mant == 0) ? 24'b0 : (norm_mant << offset);
                        new_exp = (norm_mant == 0 || norm_exp <= offset) ? 8'b0 : (norm_exp - offset);
                        
                        
                        // Step 5: Guard, Round, Sticky (approx; ignore shift loss for simple cases)
                        // TODO: For full IEEE, compute align_sticky = |shifted_out bits|
                        guard = diff_mant[23];
                        round_bit = diff_mant[22];
                        sticky = |diff_mant[21:0];

                        // Step 6: Round-to-nearest-even
                        mant_ext = {norm_mant, guard, round_bit, sticky};
                        temp_round = round_nearest_even(mant_ext);
                        rtn_norm_mant = temp_round[23:0];  // 24-bit

                        if (temp_round[24] && same_effective_sign) begin  // Round carry
                            rtn_norm_mant = {1'b0, rtn_norm_mant[23:1]};
                            norm_exp = norm_exp + 1;
                        end

                        // Step 7: Clamp exp
                        if (norm_exp > 254) begin  // Overflow
                            o_result = {sign_res, 8'hFF, 23'b0};
                        end else if (norm_exp == 0 && rtn_norm_mant == 0) begin  // Zero
                            o_result = {1'b0, 31'b0};  // +0
                        end else if (norm_exp <= 0) begin  // Underflow -> subnormal
                            shift_amount = -norm_exp[4:0];  // Clamp to 5-bit
                            rtn_norm_mant = rtn_norm_mant >> shift_amount;
                            o_result = {sign_res, 8'b0, rtn_norm_mant[22:0]};
                        end else begin  // Normal
                            o_result = {sign_res, new_exp, new_mant[22:0]};
                            // exp_res = norm_exp;
                            // o_result = {sign_res, exp_res, rtn_norm_mant[22:0]};
                        end
                    end
                end

                // ----------------------------------------------------
                // FMUL.S : f1 * f2
                // ----------------------------------------------------
                7'b0001000: begin
                    // Invalid: NaN, 0 * Inf
                    if (src1_is_nan || src2_is_nan ||
                        (src1_is_zero && src2_is_inf) ||
                        (src1_is_inf && src2_is_zero)) begin
                        o_invalid = 1'b1;
                        o_result  = {1'b0, 8'hFF, 23'h400000};
                    end else if (src1_is_inf || src2_is_inf) begin
                        // Result is infinity
                        o_result = {sign1 ^ sign2, 8'hFF, 23'b0};
                    end else if (src1_is_zero || src2_is_zero) begin
                        // Result is zero
                        o_result = {sign1 ^ sign2, 31'b0};
                    end else begin
                        // Normal multiplication
                        prod_mant = frac1 * frac2;
                        exp_res   = exp1 + exp2 - EXP_BIAS;
                        sign_res  = sign1 ^ sign2;

                        // Normalize
                        if (prod_mant[47]) begin
                            prod_mant = prod_mant >> 1;
                            exp_res = exp_res + 1;
                        end else begin
                            while (prod_mant[46] == 0 && exp_res > 0) begin
                                prod_mant = prod_mant << 1;
                                exp_res = exp_res - 1;
                            end
                        end

                        // Extract guard, round, sticky bits
                        guard      = prod_mant[22];
                        round_bit  = prod_mant[21];
                        sticky     = |prod_mant[20:0];

                        // Round-to-nearest-even
                        mant_ext = {prod_mant[46:23], guard, round_bit, sticky};
                        temp_round = round_nearest_even(mant_ext);
                        norm_mant = temp_round[23:0]; // Adjust to 24 bits

                        // Overflow after rounding
                        if (temp_round[24]) begin
                            norm_mant = norm_mant >> 1;
                            exp_res = exp_res + 1;
                        end

                        // Clamp
                        if (exp_res >= 255) begin
                            o_result = {sign_res, 8'hFF, 23'b0};
                        end else if (exp_res <= 0) begin
                            o_result = {sign_res, 31'b0};
                        end else begin
                            o_result = {sign_res, exp_res[7:0], norm_mant[22:0]};
                        end
                    end
                end

                // ----------------------------------------------------
                // FCVT.W.S : float -> int
                // ----------------------------------------------------
                7'b1100000: begin
                    if (src1_is_nan || src1_is_inf) begin
                        o_invalid = 1'b1;
                        o_result = 32'b0;
                    end else begin
                        if (exp1 < 8'd127) begin
                            o_result = 32'b0; // |x| < 1 -> 0
                        end else if (exp1 > 8'd158) begin
                            o_invalid = 1'b1; // overflow
                            o_result  = 32'b0;
                        end else begin
                            // shift mantissa
                            norm_exp = exp1 - 8'd127;
                            if (norm_exp >= 23)
                                o_result = {{8{sign1}}, {1'b1, i_src1[22:0]}} << (norm_exp - 23);
                            else
                                o_result = {{8{sign1}}, {1'b1, i_src1[22:0]}} >> (23 - norm_exp);
                        end
                    end
                end

                // ----------------------------------------------------
                // FCLASS.S : classification
                // ----------------------------------------------------
                7'b1110000: begin
                    if (src1_is_nan) begin
                        if (src1_is_signaling_nan)
                            o_result = SIG_NAN;
                        else
                            o_result = QUIET_NAN;
                    end else if (src1_is_inf) begin
                        if (sign1)
                            o_result = NEG_INF;
                        else
                            o_result = POS_INF;
                    end else if (src1_is_zero) begin
                        if (sign1)
                            o_result = NEG_ZERO;
                        else
                            o_result = POS_ZERO;
                    end else if (src1_is_subnormal) begin
                        if (sign1)
                            o_result = NEG_SUBNORMAL;
                        else
                            o_result = POS_SUBNORMAL;
                    end else begin  // normal
                        if (sign1)
                            o_result = NEG_NORMAL;
                        else
                            o_result = POS_NORMAL;
                    end
                end

                // ----------------------------------------------------
                default: begin
                    o_invalid = 1'b1;
                    o_result  = 32'd0;
                end
            endcase
        end
    end
    // Function to convert 24-bit unsigned mantissa to 25-bit 2's complement based on sign
    function automatic [47:0] to_twos_complement;
        input [47:0] mantissa; // 24-bit unsigned mantissa
        begin
            to_twos_complement = ~{1'b0, mantissa} + 1; // Negate: ~mant + 1
        end
    endfunction
endmodule