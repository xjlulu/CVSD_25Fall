`timescale 1ns/100ps

module decoder (
    input  wire [31:0] i_instr,     // 32-bit instruction

    // Basic fields
    output wire [6:0]  o_opcode,
    output wire [2:0]  o_funct3,
    output wire [6:0]  o_funct7,
    output wire [4:0]  o_rs1,
    output wire [4:0]  o_rs2,
    output wire [4:0]  o_rd,

    // Control signals for later use
    output reg         o_is_branch,
    output reg         o_is_jalr,
    output reg         o_is_load,
    output reg         o_is_store,
    output reg         o_is_imm,
    output reg         o_is_alu,
    output reg         o_is_fp,       // NEW: Floating-point operation
    output reg         o_is_end,
    output reg  [2:0]  o_instr_type   // NEW: For ctrl/status type
);

    // ------------------------------------------------------------------------
    // Extract instruction fields
    // ------------------------------------------------------------------------
    assign o_opcode = i_instr[6:0];
    assign o_rd     = i_instr[11:7];
    assign o_funct3 = i_instr[14:12];
    assign o_rs1    = i_instr[19:15];
    assign o_rs2    = i_instr[24:20];
    assign o_funct7 = i_instr[31:25];

    // ------------------------------------------------------------------------
    // Decode instruction category by opcode
    // ------------------------------------------------------------------------
    always @(*) begin
        // default
        o_is_branch = 1'b0;
        o_is_jalr   = 1'b0;
        o_is_load   = 1'b0;
        o_is_store  = 1'b0;
        o_is_imm    = 1'b0;
        o_is_alu    = 1'b0;
        o_is_fp     = 1'b0;
        o_is_end    = 1'b0;
        o_instr_type = `INVALID_TYPE; // default

        case (o_opcode)

            7'b0110011: begin
                o_is_alu      = 1'b1;
                o_instr_type  = `R_TYPE;
            end
            7'b0010011: begin
                o_is_imm      = 1'b1;
                o_instr_type  = `I_TYPE;
            end
            7'b0000011: begin
                o_is_load     = 1'b1;
                o_instr_type  = `I_TYPE;
            end
            7'b0100011: begin
                o_is_store    = 1'b1;
                o_instr_type  = `S_TYPE;
            end
            7'b1100011: begin
                o_is_branch   = 1'b1;
                o_instr_type  = `B_TYPE;
            end
            7'b1100111: begin
                o_is_jalr     = 1'b1;
                o_instr_type  = `I_TYPE;
            end
            7'b0010111: begin
                o_is_imm      = 1'b1;
                o_instr_type  = `U_TYPE; // AUIPC
            end
            7'b1010011: begin            // FP operations: FSUB, FMUL, FCVT, FCLASS
                o_is_alu      = 1'b1;
                o_is_fp       = 1'b1;
                o_instr_type  = `R_TYPE;
            end
            7'b0000111: begin            // FLW
                o_is_load     = 1'b1;
                o_is_fp       = 1'b1;
                o_instr_type  = `I_TYPE;
            end
            7'b0100111: begin            // FSW
                o_is_store    = 1'b1;
                o_is_fp       = 1'b1;
                o_instr_type  = `S_TYPE;
            end
            7'b1110011: begin
                o_is_end      = 1'b1;
                o_instr_type  = `EOF_TYPE;
            end
            default: begin
                o_instr_type  = `INVALID_TYPE;
            end
        endcase
    end

endmodule
