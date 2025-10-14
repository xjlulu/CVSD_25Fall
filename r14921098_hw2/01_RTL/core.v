`timescale 1ns/100ps

module core #( // DO NOT MODIFY INTERFACE!!!
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output [2:0] o_status,
    output       o_status_valid,

    // Memory IOs
    output [ADDR_WIDTH-1:0] o_addr,
    output [DATA_WIDTH-1:0] o_wdata,
    output                  o_we,
    input  [DATA_WIDTH-1:0] i_rdata
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

// ---------------------------------------------------------------------------
// Internal wires and regs
// ---------------------------------------------------------------------------
// core
wire [ADDR_WIDTH-1:0] o_addr_reg;
reg [DATA_WIDTH-1:0] o_wdata_reg;
reg                  o_we_reg;

// PC
wire [31:0] pc_now;
reg  [31:0] pc_next;
wire [31:0] instr_addr;
wire [31:0] data_addr;

// Instruction register (latches fetched instruction)
reg  [31:0] instr_reg;

// Decoder outputs
wire [6:0]  dec_opcode;
wire [2:0]  dec_funct3;
wire [6:0]  dec_funct7;
wire [4:0]  dec_rs1;
wire [4:0]  dec_rs2;
wire [4:0]  dec_rd;
wire        dec_is_branch;
wire        dec_is_jalr;
wire        dec_is_load;
wire        dec_is_store;
wire        dec_is_imm;
wire        dec_is_alu;
wire        dec_is_fp;
wire        dec_is_end;
wire [2:0]  dec_instr_type;

// Immediate
wire [31:0] imm;

// Register file
wire [31:0] rs1_data;
wire [31:0] rs2_data;
reg  [31:0] wb_data;
wire        reg_we;    // write enable to integer regfile
reg  [4:0]  rd_idx;   // destination index

// ALU
wire [31:0] alu_result;
wire        alu_zero;
wire        alu_overflow;

// Floating point register file
wire [31:0] fp_rs1_data;
wire [31:0] fp_rs2_data;
reg [31:0]  fp_wb_data;
wire        fp_reg_we;

// Floating point ALU
wire [31:0] fp_alu_result;
wire        fp_invalid;

// Controller (FSM)
wire [2:0] ctrl_status;
wire       ctrl_status_valid;
wire       ctrl_pc_we;
wire       ctrl_reg_we;
wire       ctrl_mem_we;
wire [2:0] ctrl_state; // optional debug

// Memory data latch (for loads)
reg  [31:0] mem_rdata_reg;

// A few helper signals
wire [6:0] opcode_for_ctrl;
wire [2:0] funct3_for_ctrl;
wire [6:0] funct7_for_ctrl;

// ---------------------------------------------------------------------------
// Instantiate submodules
// ---------------------------------------------------------------------------

// Program counter
pc u_pc (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_pc_write_en(ctrl_pc_we),
    .i_pc_next(pc_next),
    .o_pc(pc_now)
);

// Instruction decoder (reads instr_reg)
decoder u_decoder (
    .i_instr(instr_reg),
    .o_opcode(dec_opcode),
    .o_funct3(dec_funct3),
    .o_funct7(dec_funct7),
    .o_rs1(dec_rs1),
    .o_rs2(dec_rs2),
    .o_rd(dec_rd),
    .o_is_branch(dec_is_branch),
    .o_is_jalr(dec_is_jalr),
    .o_is_load(dec_is_load),
    .o_is_store(dec_is_store),
    .o_is_imm(dec_is_imm),
    .o_is_alu(dec_is_alu),
    .o_is_fp(dec_is_fp),
    .o_is_end(dec_is_end),
    .o_instr_type(dec_instr_type)
);

// Immediate generator (reads instr_reg)
imm_gen u_imm_gen (
    .i_instr(instr_reg),
    .o_imm(imm)
);

// Integer register file
regfile_int u_regfile_int (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_we(ctrl_reg_we),   // controlled by ctrl (write in WB)
    .i_rs1(dec_rs1),
    .i_rs2(dec_rs2),
    .i_rd(dec_rd),
    .i_wdata(wb_data),
    .o_rs1_data(rs1_data),
    .o_rs2_data(rs2_data)
);

// ALU: use rs1_data and either rs2_data or imm depending on instruction class
alu u_alu (
    .i_opcode(dec_opcode),
    .i_funct3(dec_funct3),
    .i_funct7(dec_funct7),
    .i_src1((dec_opcode == 7'b0010111) ? pc_now : rs1_data), // puipc
    .i_src2((dec_is_imm || dec_is_store || dec_is_load) ? imm : rs2_data),
    .o_result(alu_result),
    .o_zero(alu_zero),
    .o_overflow(alu_overflow)
);

// Controller / FSM
ctrl u_ctrl (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_opcode(dec_opcode),
    .i_funct3(dec_funct3),
    .i_funct7(dec_funct7),
    .i_is_branch(dec_is_branch),
    .i_is_jalr(dec_is_jalr),
    .i_is_load(dec_is_load),
    .i_is_store(dec_is_store),
    .i_is_imm(dec_is_imm),
    .i_is_alu(dec_is_alu),
    .i_is_fp(dec_is_fp),
    .i_zero(alu_zero),
    .i_overflow(alu_overflow),
    .i_fp_invalid(fp_invalid),
    .i_instr(instr_reg),
    .o_pc_we(ctrl_pc_we),
    .o_reg_we(ctrl_reg_we),
    .o_fp_reg_we(fp_reg_we),
    .o_mem_we(ctrl_mem_we),
    .o_status(ctrl_status),
    .o_status_valid(ctrl_status_valid),
    .o_state(ctrl_state)
);

// Floating-point register file
regfile_fp u_regfile_fp (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_we(fp_reg_we),         // from control unit for FP ops
    .i_rs1(dec_rs1),
    .i_rs2(dec_rs2),
    .i_rd(dec_rd),
    .i_wdata(fp_wb_data),     // from FP ALU result or memory
    .o_rs1_data(fp_rs1_data),
    .o_rs2_data(fp_rs2_data)
);

// Floating-point ALU
fp_alu u_fp_alu (
    .i_opcode(dec_opcode),
    .i_funct7(dec_funct7),
    .i_funct3(dec_funct3),
    .i_src1(fp_rs1_data),
    .i_src2(fp_rs2_data),
    .o_result(fp_alu_result),
    .o_invalid(fp_invalid)
);

// ---------------------------------------------------------------------------
// o_addr
// ---------------------------------------------------------------------------
assign o_addr     = o_addr_reg;
assign o_wdata    = o_wdata_reg;
assign o_we       = o_we_reg;
assign instr_addr = pc_now;
assign data_addr  = alu_result;
assign o_addr_reg = (ctrl_state == S_MEM) ? data_addr : instr_addr;

// ---------------------------------------------------------------------------
// Expose status outputs (top-level)
// ---------------------------------------------------------------------------
assign o_status = ctrl_status;
assign o_status_valid = ctrl_status_valid;

// ---------------------------------------------------------------------------
// FSM-driven datapath sequencing (combinational)
// ---------------------------------------------------------------------------
// We will generate memory outputs and next-pc logic based on controller signals
// and current decoded instruction. Sequencing between stages is handled by the
// controller's state machine (fetch/decode/exec/mem/wb/pc).
// ---------------------------------------------------------------------------

// Corrected combinational logic for pc_next with priority
always @(*) begin
    pc_next = pc_now + 32'd4; // Default: PC+4

    // Priority Check 1: Unconditional Jump (JALR) - Highest priority change
    if (dec_is_jalr) begin 
        // JALR target = (rs1 + Imm) & ~1 (LSB cleared for instruction alignment)
        pc_next = (rs1_data + imm) & 32'hFFFFFFFE; 
    end
    
    // Priority Check 2: Conditional Branch
    else if (dec_is_branch && alu_zero) begin
        // Branch taken: target = PC_now + Imm (offset)
        pc_next = pc_now + imm;
    end
    
    // Priority Check 3: JAL (Assuming you need to implement it)
    // else if (dec_is_jal) begin 
        // pc_next = pc_now + imm; // J-Type Imm
    // end
    
    // Priority Check 4: END Instruction (Assuming it's a specific opcode/funct3 combo)
    // You need to define a dedicated signal for the END instruction (e.g., dec_is_end)
    else if (dec_is_end) begin 
        pc_next = pc_now; // PC should stop advancing
    end
    
    // else: pc_next remains pc_now + 4 (Default)
end

// Default assignment (safe defaults, updated in sequential block)
always @(*) begin
    // default register writeback fields (rd index already from dec)
    rd_idx = dec_rd;

    // By default wb_data is ALU result (overridden for load)
    // We'll not change wb_data in combinational block; it is assigned in sequential blocks

    // o_addr_reg     <= {ADDR_WIDTH{1'b0}};
    // if (ctrl_mem_we) begin
    //     o_addr_reg <= alu_result;      // byte address
    // end else if (dec_is_load && ctrl_mem_we == 1'b0 && ctrl_reg_we == 1'b0 && ctrl_pc_we == 1'b0) begin
    //     o_addr_reg <= alu_result;
    // end else begin
    //     o_addr_reg <= pc_now;
    // end

    // --- Writeback data selection ---
    // If a load completed, write mem_rdata_reg into register file on reg write.
    // Otherwise write ALU result.
    // Write-back for integer register file
    if (ctrl_reg_we) begin
        if (dec_is_load) begin
            // Integer load (LW)
            wb_data = mem_rdata_reg;
        end
        else if (dec_is_fp && (dec_opcode == 7'b1010011)) begin
            // Floating-point ALU that writes to integer reg (FCVT.W.S / FCLASS.S)
            wb_data = fp_alu_result;
        end
        else begin
            // Normal integer ALU result (ADD / ADDI / AUIPC / etc.)
            wb_data = alu_result;
        end
    end

    // Write-back for floating-point register file
    if (fp_reg_we) begin
        if (dec_opcode == 7'b0000111) begin
            // FLW
            fp_wb_data = i_rdata;
        end
        else if (dec_opcode == 7'b1010011) begin
            // FSUB.S / FMUL.S
            fp_wb_data = fp_alu_result;
        end
    end

    if (ctrl_mem_we) begin
        if (dec_is_fp && dec_is_store) begin
            o_wdata_reg = fp_rs2_data;
        end else begin
            o_wdata_reg = rs2_data;
        end
    end
    // Default: clear memory write enable; controller will assert when needed.
    // o_we_reg <= 1'b0;
    // --- Instruction fetch: present PC to memory bus ---
    // Note: controller controls ctrl_pc_we to latch pc_next into PC.
    // We must present PC on o_addr_reg during fetch stage so memory returns i_rdata next cycle.
    // To keep logic simple, always drive o_addr_reg = current PC during fetch state.
    // But because we don't expose ctrl state here, we adopt behavior:
    //  - If controller requests a memory access (ctrl_mem_we for store), we will drive store addr/data;
    //  - Otherwise, treat the memory access as instruction fetch (o_addr_reg = pc_now).
    // The controller's FSM timing guarantees correct sequencing.
    if (ctrl_mem_we) begin
        // Memory write (store): address = ALU result, data = rs2_data
        o_we_reg    = 1'b1;
    end else if (dec_is_load && ctrl_mem_we == 1'b0 && fp_reg_we == 1'b0 && ctrl_reg_we == 1'b0 && ctrl_pc_we == 1'b0) begin
        // This case is defensive: when controller intends a memory read (load), it will assert ctrl_mem_we in MEM state
        // However the simple handshake used here relies on ctrl_mem_we to indicate store; if load, we still present address below.
        o_we_reg   = 1'b0;
    end else begin
        // Default memory access = instruction fetch (byte address)
        o_we_reg   = 1'b0;
    end
end

// ---------------------------------------------------------------------------
// Sequential logic: instruction fetch latch, memory-read latch, writeback data
// ---------------------------------------------------------------------------

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // reset all stateful elements
        instr_reg      = 32'd0;
        mem_rdata_reg  = 32'd0;

    end else begin
        // --- Latch incoming i_rdata ---
        // i_rdata is used for both instruction fetch and data-load responses.
        // We need to decide whether the arriving i_rdata is an instruction or a load data.
        // The timing of the FSM ensures:
        //  - After we present PC (fetch), the next cycle i_rdata is the instruction and should be latched into instr_reg.
        //  - After we present data address for load (in MEM state), the next cycle i_rdata is the loaded data and should be latched into mem_rdata_reg.
        //
        // We use the controller outputs and decode signals to disambiguate:
        // If the instruction currently in instr_reg indicates a load and the controller is in MEM or WB stage,
        // the arriving i_rdata corresponds to data memory and should be latched into mem_rdata_reg.
        //
        // Simpler approach: always latch i_rdata into instr_reg if the last address we presented was PC (i.e., we were fetching).
        // To implement that cleanly, we treat "instr_reg" update on every cycle with the i_rdata that arrived for the previous o_addr_reg.
        // In a multi-cycle FSM the sequence will be:
        //   cycle N: present pc_now on o_addr_reg
        //   cycle N+1: i_rdata contains instruction -> instr_reg <= i_rdata (DECODE)
        //
        // For load:
        //   cycle M: present data address on o_addr_reg
        //   cycle M+1: i_rdata contains load data -> mem_rdata_reg <= i_rdata (WB)
        //
        // We distinguish by looking at ctrl_state (controller exposes o_state). When controller indicates fetch->decode,
        // we treat the arriving i_rdata as fetched instruction. When controller indicates MEM->WB for loads, we treat arriving as load data.
        case (ctrl_state)
            S_FETCH: begin
                // S_FETCH just presented PC_last_cycle; the i_rdata that arrives now is the fetched instruction
                instr_reg = i_rdata;
            end
            S_MEM: begin
                // S_MEM -> when load read returns, latch into mem_rdata_reg.
                // Depending on controller implementation, the state numbers may differ.
                // To be robust, also latch mem data whenever ctrl_mem_we is low but dec_is_load was true for previous instruction.
                // We'll latch mem_rdata_reg whenever the instruction currently decoded is a load and controller is in MEM/WB stage.
                if (dec_is_load) begin
                    mem_rdata_reg = i_rdata;
                end
            end
            S_WB: begin
                // In WB state, a load's data should be available in mem_rdata_reg (already latched).
                // No special action here.
            end
            default: begin
                // Fallback: if the controller indicates decode stage next, treat i_rdata as instruction.
                // We'll be conservative: if instr_reg currently zero (reset case) allow writing.
                if (instr_reg == 32'd0) instr_reg = i_rdata;
            end
        endcase

        // rd_idx handled by combinational decoder (dec_rd). No need to update here.

    end
end

// ---------------------------------------------------------------------------
// Notes on the implementation above:
//
// - The controller FSM (u_ctrl) is expected to set ctrl_pc_we, ctrl_reg_we,
//   ctrl_mem_we in the correct cycles so that the sequencing described in the HW
//   spec is observed (fetch -> decode -> exec -> mem -> wb -> pc).
//
// - The simplistic case selection in the always block relies on ctrl_state to
//   separate when the arriving i_rdata represents an instruction vs. load data.
//   If you prefer stricter timing, you can expand the controller to assert
//   dedicated handshakes (e.g., o_ifetch_valid, o_mem_read_valid) and use them
//   here to unambiguously latch i_rdata into instr_reg or mem_rdata_reg.
//
// - Ensure your `ctrl` state encodings match the numbers used above (we
//   previously defined S_FETCH=3'd1 and S_MEM=3'd4, S_WB=3'd5). If your ctrl.v
//   encodings differ, adapt the `case (ctrl_state)` branch accordingly.
//
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

endmodule