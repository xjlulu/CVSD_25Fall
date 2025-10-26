`timescale 1ns/100ps

module ctrl (
    input  wire         i_clk,
    input  wire         i_rst_n,

    // from decoder
    input  wire [6:0]   i_opcode,
    input  wire [2:0]   i_funct3,
    input  wire [6:0]   i_funct7,
    input  wire         i_is_branch,
    input  wire         i_is_jalr,
    input  wire         i_is_load,
    input  wire         i_is_store,
    input  wire         i_is_imm,
    input  wire         i_is_alu,
    input  wire         i_is_fp,

    // from ALU
    input  wire         i_zero,
    input  wire         i_overflow,
    input  wire         i_fp_invalid,

    // raw instruction (for EOF)
    input  wire [31:0]  i_instr,

    // control outputs
    output reg          o_pc_we,
    output reg          o_reg_we,
    output reg          o_fp_reg_we,
    output reg          o_mem_we,
    output reg  [2:0]   o_status,
    output reg          o_status_valid,

    // debug (optional)
    output [2:0]        o_state
);

    // ---------------------------------------------------------
    // FSM state encoding
    // ---------------------------------------------------------
    localparam S_RESET  = 3'd0;
    localparam S_FETCH  = 3'd1;
    localparam S_DECODE = 3'd2;
    localparam S_EXEC   = 3'd3;
    localparam S_MEM    = 3'd4;
    localparam S_WB     = 3'd5;
    localparam S_PC     = 3'd6;
    localparam S_END    = 3'd7;

    reg [2:0] state, next_state;

    // ---------------------------------------------------------
    // State transition logic
    // ---------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            S_RESET:  next_state = S_FETCH;
            S_FETCH:  next_state = S_DECODE;

            S_DECODE: begin
                if (i_is_store || i_is_load)
                    next_state = S_MEM;
                else
                    next_state = S_EXEC;
            end

            S_EXEC: begin
                if (i_overflow || i_fp_invalid)
                    next_state = S_END;
                else if (i_is_branch)
                    next_state = S_PC;
                else if (i_is_imm || i_is_alu)
                    next_state = S_WB;
                else
                    next_state = S_PC;
            end

            S_MEM: begin
                if (i_is_load)
                    next_state = S_WB;
                else
                    next_state = S_PC;  // store done
            end

            S_WB: next_state = S_PC;

            S_PC: next_state = S_RESET;

            S_END: next_state = S_END;
        endcase
    end

    // ---------------------------------------------------------
    // Control signal outputs (Moore machine)
    // ---------------------------------------------------------
    always @(*) begin
        // default outputs
        o_pc_we        = 1'b0;
        o_reg_we       = 1'b0;
        o_mem_we       = 1'b0;
        o_status       = 3'd0;
        o_status_valid = 1'b0;
        o_fp_reg_we    = 1'b0;

        case (state)
            S_FETCH: begin
                // no write enables, just fetch instruction
            end

            S_DECODE: begin
                // decode stage (no outputs)
            end

            S_EXEC: begin
                if (i_overflow) begin
                    o_status       = 3'd5;  // INVALID
                    o_status_valid = 1'b1;
                end
            end

            S_MEM: begin
                o_mem_we = i_is_store; // write for store
            end

            S_WB: begin
                // Integer instructions (ADD, ADDI, LW)
                // o_reg_we is asserted if the instruction is an I-Type immediate, R-Type ALU, or a Load (LW).
                o_reg_we = (i_is_imm || i_is_alu || i_is_load) && !i_is_fp;

                // Floating-point instructions: determine write target based on funct7
                if (i_opcode == 7'b1010011) begin // R4-type (FP operations)
                    // Floating-point ALU instructions
                    case (i_funct7)
                        7'b0000100,  // FSUB.S
                        7'b0001000:  // FMUL.S
                            o_fp_reg_we = 1'b1;  // Write to FP register file (FPRs)

                        7'b1100000,  // FCVT.W.S (Converts Float to Integer)
                        7'b1110000:  // FCLASS.S (Classifies Float, result in Integer reg)
                            o_reg_we = 1'b1;     // Write to Integer register file (GPRs)

                        default: ;
                    endcase
                end
                else if (i_opcode == 7'b0000111) begin
                    // FLW (Floating-point Load Word)
                    o_fp_reg_we = 1'b1; // Write to FP register file
                end
                else if (i_opcode == 7'b0100111) begin
                    // FSW (Floating-point Store Word)
                    o_fp_reg_we = 1'b0; // Store operation, no writeback to any register file
                end
            end

            S_PC: begin
                o_pc_we = 1'b1; // update PC

                if (i_opcode == 7'b0110011)            // R-type integer
                    o_status = `R_TYPE;
                else if (i_opcode == 7'b0010011)       // I-type integer (ADDI)
                    o_status = `I_TYPE;
                else if (i_opcode == 7'b0000011)       // LW
                    o_status = `I_TYPE;
                else if (i_opcode == 7'b0100011)       // SW
                    o_status = `S_TYPE;
                else if (i_opcode == 7'b1100011)       // BEQ, BLT
                    o_status = `B_TYPE;
                else if (i_opcode == 7'b0010111)       // AUIPC
                    o_status = `U_TYPE;
                else if (i_opcode == 7'b1010011)       // FP ALU ops: FSUB, FMUL, FCVT, FCLASS
                    o_status = `R_TYPE;
                else if (i_opcode == 7'b0000111)       // FLW
                    o_status = `I_TYPE;
                else if (i_opcode == 7'b0100111)       // FSW
                    o_status = `S_TYPE;
                else if (i_opcode == 7'b1110011)       // EOF
                    o_status = `EOF_TYPE;
                else
                    o_status = `INVALID_TYPE;
                        
                o_status_valid = 1'b1;
            end

            S_END: begin
                o_status       = (i_opcode == 7'b1110011) ? 3'd6 : 3'd5; // EOF or INVALID
                o_status_valid = 1'b1;
            end

            default: ;
        endcase
    end

    // ---------------------------------------------------------
    // Sequential block (state register)
    // ---------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= S_RESET;
        else
            state <= next_state;
    end

    // debug
    assign o_state = state;

endmodule
