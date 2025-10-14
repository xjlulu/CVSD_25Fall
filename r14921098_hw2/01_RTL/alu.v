`timescale 1ns/100ps

module alu (
    input  wire [6:0]  i_opcode,      // opcode from instruction
    input  wire [2:0]  i_funct3,      // funct3 field
    input  wire [6:0]  i_funct7,      // funct7 field
    input  wire [31:0] i_src1,        // operand 1
    input  wire [31:0] i_src2,        // operand 2 (or immediate)
    output reg  [31:0] o_result,      // computation result
    output reg         o_zero,        // result == 0 flag
    output reg         o_overflow     // signed overflow flag
);

    // internal signals
    wire [31:0] add_sum;
    wire add_overflow, sub_overflow;
    wire [31:0] sub_diff;
    wire [31:0] srl_res;

    assign add_sum     = i_src1 + i_src2;
    assign sub_diff    = i_src1 - i_src2;
    assign srl_res     = i_src1 >> i_src2[4:0];  // logical right shift

    assign add_overflow = (i_src1[31] == i_src2[31]) && (add_sum[31] != i_src1[31]);
    assign sub_overflow = (i_src1[31] != i_src2[31]) && (sub_diff[31] != i_src1[31]);

    always @(*) begin
        o_result   = 32'd0;
        o_overflow = 1'b0;

        case (i_opcode)

            // ----------------------------------------------------------------
            // R-type operations
            // ----------------------------------------------------------------
            7'b0110011: begin
                case (i_funct3)
                    3'b000: begin
                        if (i_funct7 == 7'b0100000) begin
                            // SUB
                            o_result   = sub_diff;
                            o_overflow = sub_overflow;
                        end else begin
                            // ADD
                            o_result   = add_sum;
                            o_overflow = add_overflow;
                        end
                    end
                    3'b010: begin
                        // SLT (signed)
                        o_result   = ($signed(i_src1) < $signed(i_src2)) ? 32'd1 : 32'd0;
                        o_overflow = 1'b0;
                    end
                    3'b101: begin
                        // SRL
                        o_result   = srl_res;
                        o_overflow = 1'b0;
                    end
                    default: begin
                        o_result   = 32'd0;
                        o_overflow = 1'b0;
                    end
                endcase
            end

            // ----------------------------------------------------------------
            // I-type (ADDI, JALR)
            // ----------------------------------------------------------------
            7'b0010011: begin
                // ADDI
                o_result   = add_sum;
                o_overflow = add_overflow;
            end
            7'b1100111: begin
                // JALR (jump target address)
                o_result   = (i_src1 + i_src2) & ~32'd1; // LSB must be 0
                o_overflow = 1'b0;
            end

            // ----------------------------------------------------------------
            // U-type (AUIPC)
            // ----------------------------------------------------------------
            7'b0010111: begin
                // AUIPC: PC-relative addition
                o_result   = i_src1 + i_src2; // PC + imm
                o_overflow = 1'b0;
            end

            // ----------------------------------------------------------------
            // S-type
            // ----------------------------------------------------------------
            // LW / SW
            7'b0000011, 7'b0100011,
            // FLW / FSW
            7'b0000111, 7'b0100111: begin
                // LW / SW
                o_result   = i_src1 + i_src2; // effective address
                o_overflow = 1'b0;
            end

            // ----------------------------------------------------------------
            // Comparison for branch (BEQ, BLT)
            // ----------------------------------------------------------------
            7'b1100011: begin
                case (i_funct3)
                    3'b000: o_result = (i_src1 == i_src2) ? 32'd1 : 32'd0; // BEQ
                    3'b100: o_result = ($signed(i_src1) < $signed(i_src2)) ? 32'd1 : 32'd0; // BLT
                    default: o_result = 32'd0;
                endcase
                o_overflow = 1'b0;
            end

            // ----------------------------------------------------------------
            default: begin
                o_result   = 32'd0;
                o_overflow = 1'b0;
            end

        endcase

        // Zero flag (used by branch decision)
        o_zero = (o_result == 32'd0);
    end

endmodule
