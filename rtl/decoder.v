// ============================================================================
// decoder.v — Instruction Decode Stage (Stage 2 of 5)
// ============================================================================
//
// PURPOSE:
//   Decodes the 32-bit RISC-V instruction fetched by Stage 1. Extracts:
//     - Opcode type (R-type, I-type, LOAD, STORE, BRANCH, etc.)
//     - ALU operation (ADD, SUB, SLT, XOR, etc.)
//     - Source register addresses (rs1, rs2) for register file read
//     - Destination register address (rd)
//     - Immediate value (sign-extended to 32 bits)
//     - Function type (funct3)
//     - Exceptions (illegal instruction, ECALL, EBREAK, MRET)
//
// INPUTS FROM:
//   - Fetch stage: i_inst (32-bit instruction), i_pc (program counter)
//
// OUTPUTS TO:
//   - Register file (basereg): o_rs1_addr, o_rs2_addr (combinational)
//   - ALU stage: all decoded fields (registered, 1 cycle delay)
//
// KEY CONCEPTS:
//   - RV32I has 6 instruction formats: R, I, S, B, U, J
//   - Each format places the immediate bits in different positions
//   - The decoder sign-extends all immediates to 32 bits
//   - funct3 and bit 30 of instruction distinguish ADD/SUB, SRL/SRA
//   - Opcode and ALU select signals are one-hot encoded for speed
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module decoder (
    input  wire        i_clk,          // System clock
    input  wire        i_rst_n,        // Active-low reset

    // ── Instruction Input (from Fetch stage) ──
    input  wire [31:0] i_inst,         // 32-bit instruction to decode
    input  wire [31:0] i_pc,           // PC value from Fetch stage

    // ── Decoded Outputs (to ALU stage, registered) ──
    output reg  [31:0] o_pc,           // PC value (registered)
    output wire [4:0]  o_rs1_addr,     // rs1 address (combinational, to basereg)
    output reg  [4:0]  o_rs1_addr_q,   // rs1 address (registered, to forwarding)
    output wire [4:0]  o_rs2_addr,     // rs2 address (combinational, to basereg)
    output reg  [4:0]  o_rs2_addr_q,   // rs2 address (registered, to forwarding)
    output reg  [4:0]  o_rd_addr,      // Destination register address
    output reg  [31:0] o_imm,          // Sign-extended immediate value
    output reg  [2:0]  o_funct3,       // Function type (sub-operation select)
    output reg  [`ALU_WIDTH-1:0]       o_alu,       // ALU operation (one-hot)
    output reg  [`OPCODE_WIDTH-1:0]    o_opcode,    // Opcode type (one-hot)
    output reg  [`EXCEPTION_WIDTH-1:0] o_exception, // Detected exceptions

    // ── Pipeline Control ──
    input  wire        i_ce,           // Clock enable from previous stage
    output reg         o_ce,           // Clock enable to next stage (ALU)
    input  wire        i_stall,        // Stall from downstream
    output reg         o_stall,        // Stall to upstream
    input  wire        i_flush,        // Flush this stage
    output reg         o_flush         // Flush upstream stages
);

    // ── Combinational register address extraction ──
    // These are NOT registered because basereg does its own registering
    assign o_rs1_addr = i_inst[19:15];
    assign o_rs2_addr = i_inst[24:20];

    // ── Instruction field extraction ──
    wire [2:0] funct3_d = i_inst[14:12];
    wire [6:0] opcode   = i_inst[6:0];

    // ── Combinational decode signals ──
    reg [31:0] imm_d;          // Decoded immediate value

    // ALU operation bits (one-hot)
    reg alu_add_d,  alu_sub_d;
    reg alu_slt_d,  alu_sltu_d;
    reg alu_xor_d,  alu_or_d,  alu_and_d;
    reg alu_sll_d,  alu_srl_d, alu_sra_d;
    reg alu_eq_d,   alu_neq_d;
    reg alu_ge_d,   alu_geu_d;

    // Opcode type bits (one-hot)
    reg opcode_rtype_d,  opcode_itype_d;
    reg opcode_load_d,   opcode_store_d;
    reg opcode_branch_d, opcode_jal_d, opcode_jalr_d;
    reg opcode_lui_d,    opcode_auipc_d;
    reg opcode_system_d, opcode_fence_d;

    // Exception detection
    reg system_noncsr;    // System instruction but NOT a CSR operation
    reg valid_opcode;     // 1 if opcode matches any known instruction
    reg illegal_shift;    // 1 if I-type shift has invalid bit 25

    wire stall_bit = o_stall || i_stall;

    // ──────────────────────────────────────────────
    //  Pipeline Register Update
    //  All decoded fields are registered for timing.
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_ce <= 0;
        end
        else begin
            if (i_ce && !stall_bit) begin
                // Register all decoded fields
                o_pc         <= i_pc;
                o_rs1_addr_q <= o_rs1_addr;
                o_rs2_addr_q <= o_rs2_addr;
                o_rd_addr    <= i_inst[11:7];
                o_funct3     <= funct3_d;
                o_imm        <= imm_d;

                // ALU operation select (one-hot)
                o_alu[`ADD]  <= alu_add_d;
                o_alu[`SUB]  <= alu_sub_d;
                o_alu[`SLT]  <= alu_slt_d;
                o_alu[`SLTU] <= alu_sltu_d;
                o_alu[`XOR]  <= alu_xor_d;
                o_alu[`OR]   <= alu_or_d;
                o_alu[`AND]  <= alu_and_d;
                o_alu[`SLL]  <= alu_sll_d;
                o_alu[`SRL]  <= alu_srl_d;
                o_alu[`SRA]  <= alu_sra_d;
                o_alu[`EQ]   <= alu_eq_d;
                o_alu[`NEQ]  <= alu_neq_d;
                o_alu[`GE]   <= alu_ge_d;
                o_alu[`GEU]  <= alu_geu_d;

                // Opcode type select (one-hot)
                o_opcode[`RTYPE]  <= opcode_rtype_d;
                o_opcode[`ITYPE]  <= opcode_itype_d;
                o_opcode[`LOAD]   <= opcode_load_d;
                o_opcode[`STORE]  <= opcode_store_d;
                o_opcode[`BRANCH] <= opcode_branch_d;
                o_opcode[`JAL]    <= opcode_jal_d;
                o_opcode[`JALR]   <= opcode_jalr_d;
                o_opcode[`LUI]    <= opcode_lui_d;
                o_opcode[`AUIPC]  <= opcode_auipc_d;
                o_opcode[`SYSTEM] <= opcode_system_d;
                o_opcode[`FENCE]  <= opcode_fence_d;

                // Exception detection
                o_exception[`ILLEGAL] <= !valid_opcode || illegal_shift;
                o_exception[`ECALL]   <= (system_noncsr && i_inst[21:20] == 2'b00);
                o_exception[`EBREAK]  <= (system_noncsr && i_inst[21:20] == 2'b01);
                o_exception[`MRET]    <= (system_noncsr && i_inst[21:20] == 2'b10);
            end

            // Pipeline control: flush and stall propagation
            if (i_flush && !stall_bit)
                o_ce <= 0;
            else if (!stall_bit)
                o_ce <= i_ce;
            else if (stall_bit && !i_stall)
                o_ce <= 0;  // Pipeline bubble
        end
    end

    // ──────────────────────────────────────────────
    //  Opcode Type Decode (combinational)
    // ──────────────────────────────────────────────
    always @* begin
        opcode_rtype_d  = (opcode == `OPCODE_RTYPE);
        opcode_itype_d  = (opcode == `OPCODE_ITYPE);
        opcode_load_d   = (opcode == `OPCODE_LOAD);
        opcode_store_d  = (opcode == `OPCODE_STORE);
        opcode_branch_d = (opcode == `OPCODE_BRANCH);
        opcode_jal_d    = (opcode == `OPCODE_JAL);
        opcode_jalr_d   = (opcode == `OPCODE_JALR);
        opcode_lui_d    = (opcode == `OPCODE_LUI);
        opcode_auipc_d  = (opcode == `OPCODE_AUIPC);
        opcode_system_d = (opcode == `OPCODE_SYSTEM);
        opcode_fence_d  = (opcode == `OPCODE_FENCE);

        // Exception detection
        system_noncsr = (opcode == `OPCODE_SYSTEM) && (funct3_d == 0);
        valid_opcode  = opcode_rtype_d || opcode_itype_d || opcode_load_d  ||
                        opcode_store_d || opcode_branch_d || opcode_jal_d   ||
                        opcode_jalr_d  || opcode_lui_d    || opcode_auipc_d ||
                        opcode_system_d || opcode_fence_d;
        illegal_shift = (opcode_itype_d && (alu_sll_d || alu_srl_d || alu_sra_d)) && i_inst[25];
    end

    // ──────────────────────────────────────────────
    //  ALU Operation Decode + Immediate Extraction
    // ──────────────────────────────────────────────
    always @* begin
        o_stall = i_stall;
        o_flush = i_flush;
        imm_d       = 0;
        alu_add_d   = 0;  alu_sub_d  = 0;
        alu_slt_d   = 0;  alu_sltu_d = 0;
        alu_xor_d   = 0;  alu_or_d   = 0;  alu_and_d = 0;
        alu_sll_d   = 0;  alu_srl_d  = 0;  alu_sra_d = 0;
        alu_eq_d    = 0;  alu_neq_d  = 0;
        alu_ge_d    = 0;  alu_geu_d  = 0;

        // ── ALU Operation Decode ──
        if (opcode == `OPCODE_RTYPE || opcode == `OPCODE_ITYPE) begin
            // R-type: ADD vs SUB distinguished by inst[30]
            if (opcode == `OPCODE_RTYPE) begin
                alu_add_d = (funct3_d == `FUNCT3_ADD) ? !i_inst[30] : 0;
                alu_sub_d = (funct3_d == `FUNCT3_ADD) ?  i_inst[30] : 0;
            end
            else begin
                alu_add_d = (funct3_d == `FUNCT3_ADD);  // I-type ADD (ADDI)
            end
            alu_slt_d  = (funct3_d == `FUNCT3_SLT);
            alu_sltu_d = (funct3_d == `FUNCT3_SLTU);
            alu_xor_d  = (funct3_d == `FUNCT3_XOR);
            alu_or_d   = (funct3_d == `FUNCT3_OR);
            alu_and_d  = (funct3_d == `FUNCT3_AND);
            alu_sll_d  = (funct3_d == `FUNCT3_SLL);
            // SRL vs SRA distinguished by inst[30]
            alu_srl_d  = (funct3_d == `FUNCT3_SRA) ? !i_inst[30] : 0;
            alu_sra_d  = (funct3_d == `FUNCT3_SRA) ?  i_inst[30] : 0;
        end
        else if (opcode == `OPCODE_BRANCH) begin
            alu_eq_d   = (funct3_d == `FUNCT3_EQ);
            alu_neq_d  = (funct3_d == `FUNCT3_NEQ);
            alu_slt_d  = (funct3_d == `FUNCT3_LT);
            alu_ge_d   = (funct3_d == `FUNCT3_GE);
            alu_sltu_d = (funct3_d == `FUNCT3_LTU);
            alu_geu_d  = (funct3_d == `FUNCT3_GEU);
        end
        else begin
            alu_add_d = 1'b1;  // Default: ADD (used by LOAD, STORE, JAL, etc.)
        end

        // ── Immediate Value Extraction (sign-extended to 32 bits) ──
        // Each instruction format places immediate bits differently
        case (opcode)
            `OPCODE_ITYPE, `OPCODE_LOAD, `OPCODE_JALR:
                // I-type: imm[11:0] = inst[31:20]
                imm_d = {{20{i_inst[31]}}, i_inst[31:20]};

            `OPCODE_STORE:
                // S-type: imm[11:5|4:0] = inst[31:25|11:7]
                imm_d = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};

            `OPCODE_BRANCH:
                // B-type: imm[12|10:5|4:1|11] = inst[31|30:25|11:8|7]
                imm_d = {{19{i_inst[31]}}, i_inst[31], i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};

            `OPCODE_JAL:
                // J-type: imm[20|10:1|11|19:12] = inst[31|30:21|20|19:12]
                imm_d = {{11{i_inst[31]}}, i_inst[31], i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};

            `OPCODE_LUI, `OPCODE_AUIPC:
                // U-type: imm[31:12] = inst[31:12], lower 12 bits = 0
                imm_d = {i_inst[31:12], 12'h000};

            `OPCODE_SYSTEM, `OPCODE_FENCE:
                // CSR/FENCE: imm = inst[31:20] (zero-extended)
                imm_d = {20'b0, i_inst[31:20]};

            default:
                imm_d = 0;
        endcase
    end

endmodule
