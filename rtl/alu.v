// ============================================================================
// alu.v — Execute Stage / Arithmetic Logic Unit (Stage 3 of 5)
// ============================================================================
//
// PURPOSE:
//   Performs the arithmetic/logic operation specified by the Decode stage.
//   Also handles branch and jump decisions, computing the target PC.
//
// INPUTS FROM:
//   - Decode stage: ALU operation, operands (rs1, rs2, imm), opcode, PC
//   - Forwarding unit: corrected rs1/rs2 values
//
// OUTPUTS TO:
//   - Memory Access stage: ALU result (y), opcode, rd value, funct3
//   - Fetch stage: branch/jump target PC and change_pc signal
//   - Forwarding unit: rd_addr, rd value (for hazard resolution)
//
// KEY CONCEPTS:
//   - Operand A: normally rs1, but PC for JAL/AUIPC
//   - Operand B: normally imm for I-type, rs2 for R-type/BRANCH
//   - ALU result (y) is used as:
//       * Data result for R-type/I-type → written to rd
//       * Memory address for LOAD/STORE → passed to Memory stage
//       * Branch condition for BRANCH → determines if branch is taken
//   - Branches and jumps cause a pipeline flush (o_flush) + PC redirect
//   - Stall logic handles load-use hazards via force_stall from forwarding
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module alu (
    input  wire        i_clk,          // System clock
    input  wire        i_rst_n,        // Active-low reset

    // ── ALU Operation Select (from Decode stage) ──
    input  wire [`ALU_WIDTH-1:0] i_alu, // One-hot ALU operation select

    // ── Source Registers (from forwarding unit) ──
    input  wire [4:0]  i_rs1_addr,     // rs1 address (for forwarding tracking)
    output reg  [4:0]  o_rs1_addr,     // rs1 address (passed to Memory stage)
    input  wire [31:0] i_rs1,          // rs1 value (forwarded if needed)
    output reg  [31:0] o_rs1,          // rs1 value (passed to CSR unit)
    input  wire [31:0] i_rs2,          // rs2 value (forwarded if needed)
    output reg  [31:0] o_rs2,          // rs2 value (passed to Memory stage for STORE)

    // ── Immediate and Function Type ──
    input  wire [31:0] i_imm,          // Immediate value from Decode
    output reg  [11:0] o_imm,          // Lower 12 bits of immediate (CSR index)
    input  wire [2:0]  i_funct3,       // funct3 from Decode
    output reg  [2:0]  o_funct3,       // funct3 (passed to Memory stage)

    // ── Opcode and Exception ──
    input  wire [`OPCODE_WIDTH-1:0]    i_opcode,    // Opcode from Decode
    output reg  [`OPCODE_WIDTH-1:0]    o_opcode,    // Opcode (passed to Memory stage)
    input  wire [`EXCEPTION_WIDTH-1:0] i_exception, // Exception flags from Decode
    output reg  [`EXCEPTION_WIDTH-1:0] o_exception, // Exception flags (passed forward)

    // ── ALU Result ──
    output reg  [31:0] o_y,            // ALU output result

    // ── PC Control (branch/jump handling) ──
    input  wire [31:0] i_pc,           // Current PC from Decode
    output reg  [31:0] o_pc,           // PC (passed to Memory stage)
    output reg  [31:0] o_next_pc,      // New PC if branch/jump taken
    output reg         o_change_pc,    // 1 = redirect PC (branch taken or jump)

    // ── Register Writeback Control ──
    output reg         o_wr_rd,        // 1 = write rd to register file
    input  wire [4:0]  i_rd_addr,      // Destination register address from Decode
    output reg  [4:0]  o_rd_addr,      // Destination register address (passed forward)
    output reg  [31:0] o_rd,           // Value to write to rd
    output reg         o_rd_valid,     // 1 = rd is valid NOW (not LOAD/CSR)

    // ── Pipeline Control ──
    output reg         o_stall_from_alu, // Stall Memory stage for LOAD/STORE
    input  wire        i_ce,             // Clock enable from Decode
    output reg         o_ce,             // Clock enable to Memory stage
    input  wire        i_stall,          // Stall from downstream
    input  wire        i_force_stall,    // Force stall from forwarding unit
    output reg         o_stall,          // Stall to upstream
    input  wire        i_flush,          // Flush from downstream
    output reg         o_flush           // Flush to upstream (Decode, Fetch)
);

    // ── ALU operation wires (for readability) ──
    wire alu_add  = i_alu[`ADD];
    wire alu_sub  = i_alu[`SUB];
    wire alu_slt  = i_alu[`SLT];
    wire alu_sltu = i_alu[`SLTU];
    wire alu_xor  = i_alu[`XOR];
    wire alu_or   = i_alu[`OR];
    wire alu_and  = i_alu[`AND];
    wire alu_sll  = i_alu[`SLL];
    wire alu_srl  = i_alu[`SRL];
    wire alu_sra  = i_alu[`SRA];
    wire alu_eq   = i_alu[`EQ];
    wire alu_neq  = i_alu[`NEQ];
    wire alu_ge   = i_alu[`GE];
    wire alu_geu  = i_alu[`GEU];

    // ── Opcode convenience wires ──
    wire opcode_rtype  = i_opcode[`RTYPE];
    wire opcode_itype  = i_opcode[`ITYPE];
    wire opcode_load   = i_opcode[`LOAD];
    wire opcode_store  = i_opcode[`STORE];
    wire opcode_branch = i_opcode[`BRANCH];
    wire opcode_jal    = i_opcode[`JAL];
    wire opcode_jalr   = i_opcode[`JALR];
    wire opcode_lui    = i_opcode[`LUI];
    wire opcode_auipc  = i_opcode[`AUIPC];
    wire opcode_system = i_opcode[`SYSTEM];
    wire opcode_fence  = i_opcode[`FENCE];

    // ── Internal signals ──
    reg [31:0] a;           // Operand A (rs1 or PC)
    reg [31:0] b;           // Operand B (rs2 or immediate)
    reg [31:0] y_d;         // ALU result (combinational)
    reg [31:0] rd_d;        // Value for rd (combinational)
    reg        wr_rd_d;     // Write enable for rd
    reg        rd_valid_d;  // rd is valid at this stage?
    reg [31:0] a_pc;        // Operand for PC computation
    wire [31:0] sum;        // Shared adder output
    wire stall_bit = o_stall || i_stall;

    // ──────────────────────────────────────────────
    //  Pipeline Register Update
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_exception      <= 0;
            o_ce             <= 0;
            o_stall_from_alu <= 0;
        end
        else begin
            if (i_ce && !stall_bit) begin
                o_opcode         <= i_opcode;
                o_exception      <= i_exception;
                o_y              <= y_d;
                o_rs1_addr       <= i_rs1_addr;
                o_rs1            <= i_rs1;
                o_rs2            <= i_rs2;
                o_rd_addr        <= i_rd_addr;
                o_imm            <= i_imm[11:0];
                o_funct3         <= i_funct3;
                o_rd             <= rd_d;
                o_rd_valid       <= rd_valid_d;
                o_wr_rd          <= wr_rd_d;
                // Stall Memory stage when current instruction is LOAD or STORE
                // (memory access takes more than 1 cycle)
                o_stall_from_alu <= i_opcode[`STORE] || i_opcode[`LOAD];
                o_pc             <= i_pc;
            end

            // Pipeline flush/stall/bubble control
            if (i_flush && !stall_bit)
                o_ce <= 0;
            else if (!stall_bit)
                o_ce <= i_ce;
            else if (stall_bit && !i_stall)
                o_ce <= 0;  // Bubble
        end
    end

    // ──────────────────────────────────────────────
    //  ALU Computation (combinational)
    //  Selects operands and performs the operation.
    // ──────────────────────────────────────────────
    always @* begin
        y_d = 0;

        // Operand A: PC for JAL/AUIPC, otherwise rs1
        a = (opcode_jal || opcode_auipc) ? i_pc : i_rs1;

        // Operand B: rs2 for R-type/BRANCH, otherwise immediate
        b = (opcode_rtype || opcode_branch) ? i_rs2 : i_imm;

        // Execute the selected ALU operation
        if (alu_add)                y_d = a + b;
        if (alu_sub)                y_d = a - b;
        if (alu_slt || alu_sltu) begin
            y_d = {31'b0, (a < b)};
            if (alu_slt) y_d = (a[31] ^ b[31]) ? {31'b0, a[31]} : y_d;
        end
        if (alu_xor)                y_d = a ^ b;
        if (alu_or)                 y_d = a | b;
        if (alu_and)                y_d = a & b;
        if (alu_sll)                y_d = a << b[4:0];
        if (alu_srl)                y_d = a >> b[4:0];
        if (alu_sra)                y_d = $signed(a) >>> b[4:0];
        if (alu_eq || alu_neq) begin
            y_d = {31'b0, (a == b)};
            if (alu_neq) y_d = {31'b0, !y_d[0]};
        end
        if (alu_ge || alu_geu) begin
            y_d = {31'b0, (a >= b)};
            if (alu_ge) y_d = (a[31] ^ b[31]) ? {31'b0, b[31]} : y_d;
        end
    end

    // ──────────────────────────────────────────────
    //  Branch/Jump + rd Value Logic (combinational)
    // ──────────────────────────────────────────────
    always @* begin
        o_flush     = i_flush;
        rd_d        = 0;
        rd_valid_d  = 0;
        o_change_pc = 0;
        o_next_pc   = 0;
        wr_rd_d     = 0;
        a_pc        = i_pc;

        if (!i_flush) begin
            // R-type / I-type: result goes to rd
            if (opcode_rtype || opcode_itype)
                rd_d = y_d;

            // BRANCH: take branch if ALU result is 1 (condition true)
            if (opcode_branch && y_d[0]) begin
                o_next_pc   = sum;
                o_change_pc = i_ce;
                o_flush     = i_ce;  // Flush pipeline on taken branch
            end

            // JAL / JALR: unconditional jump
            if (opcode_jal || opcode_jalr) begin
                if (opcode_jalr) a_pc = i_rs1;  // JALR uses rs1 as base
                o_next_pc   = sum;
                o_change_pc = i_ce;
                o_flush     = i_ce;  // Flush pipeline on jump
                rd_d        = i_pc + 4;  // Save return address in rd
            end
        end

        // LUI: load upper immediate directly to rd
        if (opcode_lui)   rd_d = i_imm;
        // AUIPC: add upper immediate to PC
        if (opcode_auipc) rd_d = sum;

        // Write enable: write rd for all instructions EXCEPT BRANCH, STORE, non-CSR SYSTEM, FENCE
        if (opcode_branch || opcode_store || (opcode_system && i_funct3 == 0) || opcode_fence)
            wr_rd_d = 0;
        else
            wr_rd_d = 1;

        // rd validity: not valid for LOAD (value comes from memory) or CSR (value comes from CSR unit)
        if (opcode_load || (opcode_system && i_funct3 != 0))
            rd_valid_d = 0;
        else
            rd_valid_d = 1;

        // Stall logic
        o_stall = (i_stall || i_force_stall) && !i_flush;
    end

    // Shared adder: used for branch target, jump target, AUIPC
    assign sum = a_pc + i_imm;

endmodule
