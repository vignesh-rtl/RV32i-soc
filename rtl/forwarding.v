// ============================================================================
// forwarding.v — Operand Forwarding Unit (Data Hazard Resolution)
// ============================================================================
//
// PURPOSE:
//   Resolves data hazards in the pipeline by forwarding register values
//   from later pipeline stages (Memory Access, Writeback) back to the
//   ALU stage, BEFORE the register file is actually written.
//
//   Without this, the pipeline would need to stall for 1-2 cycles every
//   time an instruction depends on the result of a previous instruction.
//
// INPUTS FROM:
//   - Register file (basereg): original rs1/rs2 values
//   - Decode stage: rs1/rs2 addresses the ALU needs
//   - Memory Access stage (Stage 4): rd value being computed
//   - Writeback stage (Stage 5): rd value about to be written
//
// OUTPUTS TO:
//   - ALU stage: corrected rs1/rs2 values (forwarded if needed)
//   - ALU stage: force_stall signal (when value isn't ready yet)
//
// KEY CONCEPTS:
//   Data Hazard Example:
//     Instruction 1: ADD x5, x1, x2    ← writes to x5
//     Instruction 2: SUB x6, x5, x3    ← reads x5 (but x5 hasn't been written yet!)
//
//   Without forwarding: pipeline must stall until x5 is written back.
//   With forwarding: grab x5's value directly from Stage 4 or Stage 5.
//
//   Special case: LOAD instruction (e.g., LW x5, 0(x1))
//     The loaded value isn't available until Stage 5 (after memory read).
//     So if the NEXT instruction needs x5, we must stall for 1 cycle
//     until the load completes. This is called a "load-use hazard".
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module forwarding (
    // ── Original Register Values (from basereg) ──
    input  wire [31:0] i_rs1_orig,             // Original rs1 value from register file
    input  wire [31:0] i_rs2_orig,             // Original rs2 value from register file

    // ── Register Addresses (from Decode stage) ──
    input  wire [4:0]  i_decoder_rs1_addr_q,   // rs1 address the ALU will use
    input  wire [4:0]  i_decoder_rs2_addr_q,   // rs2 address the ALU will use

    // ── Forwarded Outputs (to ALU stage) ──
    output reg  [31:0] o_rs1,                  // Forwarded rs1 value
    output reg  [31:0] o_rs2,                  // Forwarded rs2 value
    output reg         o_alu_force_stall,       // Force ALU to stall (load-use hazard)

    // ── Stage 4 (Memory Access) — Most Recent Result ──
    input  wire [4:0]  i_alu_rd_addr,          // Destination register from ALU output
    input  wire        i_alu_wr_rd,            // Will this instruction write to rd?
    input  wire        i_alu_rd_valid,         // Is rd value available? (0 for LOAD/CSR)
    input  wire [31:0] i_alu_rd,               // rd value computed by ALU
    input  wire        i_memoryaccess_ce,       // Is Stage 4 active?

    // ── Stage 5 (Writeback) — Second Most Recent Result ──
    input  wire [4:0]  i_memoryaccess_rd_addr, // Destination register from Stage 4
    input  wire        i_memoryaccess_wr_rd,   // Will this instruction write to rd?
    input  wire [31:0] i_writeback_rd,         // Final rd value (ready to write)
    input  wire        i_writeback_ce          // Is Stage 5 active?
);

    always @* begin
        // Default: use original values from register file
        o_rs1             = i_rs1_orig;
        o_rs2             = i_rs2_orig;
        o_alu_force_stall = 0;

        // ──────────────────────────────────────────
        //  Operand Forwarding for rs1
        //  Check Stage 4 first (newest), then Stage 5.
        // ──────────────────────────────────────────
        if ((i_decoder_rs1_addr_q == i_alu_rd_addr) && i_alu_wr_rd && i_memoryaccess_ce) begin
            // Value is in Stage 4 (Memory Access)
            if (!i_alu_rd_valid) begin
                // LOAD or CSR: value NOT ready yet → must stall 1 cycle
                o_alu_force_stall = 1;
            end
            o_rs1 = i_alu_rd;
        end
        else if ((i_decoder_rs1_addr_q == i_memoryaccess_rd_addr) && i_memoryaccess_wr_rd && i_writeback_ce) begin
            // Value is in Stage 5 (Writeback) — always ready
            o_rs1 = i_writeback_rd;
        end

        // ──────────────────────────────────────────
        //  Operand Forwarding for rs2
        //  Same logic as rs1, applied to the second operand.
        // ──────────────────────────────────────────
        if ((i_decoder_rs2_addr_q == i_alu_rd_addr) && i_alu_wr_rd && i_memoryaccess_ce) begin
            // Value is in Stage 4 (Memory Access)
            if (!i_alu_rd_valid) begin
                // LOAD or CSR: value NOT ready yet → must stall 1 cycle
                o_alu_force_stall = 1;
            end
            o_rs2 = i_alu_rd;
        end
        else if ((i_decoder_rs2_addr_q == i_memoryaccess_rd_addr) && i_memoryaccess_wr_rd && i_writeback_ce) begin
            // Value is in Stage 5 (Writeback) — always ready
            o_rs2 = i_writeback_rd;
        end

        // ──────────────────────────────────────────
        //  x0 Override
        //  x0 is always zero — no forwarding needed.
        // ──────────────────────────────────────────
        if (i_decoder_rs1_addr_q == 0) o_rs1 = 0;
        if (i_decoder_rs2_addr_q == 0) o_rs2 = 0;
    end

endmodule
