// ============================================================================
// writeback.v — Writeback Stage (Stage 5 of 5)
// ============================================================================
//
// PURPOSE:
//   Final pipeline stage. Determines what value gets written to the
//   register file (rd) and handles trap entry/exit (changing the PC).
//
// INPUTS FROM:
//   - Memory Access stage: loaded data, rd value, opcode, funct3
//   - CSR unit: CSR read value, trap addresses, trap signals
//
// OUTPUTS TO:
//   - Register file (basereg): rd address, rd value, write enable
//   - Fetch stage: next PC, change_pc (for trap entry/exit)
//
// KEY CONCEPTS:
//   - For most instructions: rd was already computed by ALU (i_rd)
//   - For LOAD instructions: rd comes from memory (i_data_load)
//   - For CSR instructions: rd comes from CSR unit (i_csr_out)
//   - Trap entry (go_to_trap): PC jumps to mtvec (trap vector)
//   - Trap exit (return_from_trap): PC jumps to mepc (saved PC)
//   - This stage is purely combinational (no pipeline registers)
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module writeback (
    // ── Data from Memory Access Stage ──
    input  wire [2:0]  i_funct3,           // Function type (for CSR operations)
    input  wire [31:0] i_data_load,        // Data loaded from memory (LOAD instr)
    input  wire [31:0] i_csr_out,          // CSR value to be loaded to rd
    input  wire        i_opcode_load,      // 1 if instruction is LOAD
    input  wire        i_opcode_system,    // 1 if instruction is SYSTEM (CSR)

    // ── Register Writeback Control ──
    input  wire        i_wr_rd,            // Write enable from previous stage
    output reg         o_wr_rd,            // Write enable to register file
    input  wire [4:0]  i_rd_addr,          // Destination register address
    output reg  [4:0]  o_rd_addr,          // Destination register address
    input  wire [31:0] i_rd,               // rd value from ALU (default)
    output reg  [31:0] o_rd,               // Final rd value to register file

    // ── PC Control (Trap Handling) ──
    input  wire [31:0] i_pc,               // Current PC
    output reg  [31:0] o_next_pc,          // New PC (trap vector or return address)
    output reg         o_change_pc,        // 1 = redirect PC to o_next_pc

    // ── Trap Handler Signals (from CSR unit) ──
    input  wire        i_go_to_trap,       // Enter trap (exception/interrupt detected)
    input  wire        i_return_from_trap, // Return from trap (MRET instruction)
    input  wire [31:0] i_return_address,   // mepc: saved PC to return to
    input  wire [31:0] i_trap_address,     // mtvec: trap handler entry point

    // ── Pipeline Control ──
    input  wire        i_ce,               // Clock enable for this stage
    output reg         o_stall,            // Stall signal (currently unused)
    output reg         o_flush             // Flush all previous stages
);

    // ──────────────────────────────────────────────
    //  Writeback Logic (purely combinational)
    //  Determines rd value and PC redirect.
    // ──────────────────────────────────────────────
    always @* begin
        o_stall     = 0;
        o_flush     = 0;
        o_wr_rd     = i_wr_rd && i_ce && !o_stall;
        o_rd_addr   = i_rd_addr;
        o_rd        = 0;
        o_next_pc   = 0;
        o_change_pc = 0;

        // ── Trap Entry: jump to trap handler ──
        if (i_go_to_trap) begin
            o_change_pc = 1;
            o_next_pc   = i_trap_address;  // mtvec value
            o_flush     = i_ce;            // Flush pipeline
            o_wr_rd     = 0;               // Don't write rd during trap entry
        end

        // ── Trap Exit (MRET): return to saved PC ──
        else if (i_return_from_trap) begin
            o_change_pc = 1;
            o_next_pc   = i_return_address; // mepc value
            o_flush     = i_ce;             // Flush pipeline
            o_wr_rd     = 0;                // Don't write rd during trap exit
        end

        // ── Normal Operation: select rd value ── 
        else begin
            if (i_opcode_load)
                o_rd = i_data_load;                 // LOAD: data from memory
            else if (i_opcode_system && i_funct3 != 0)
                o_rd = i_csr_out;                   // CSR read: value from CSR unit
            else
                o_rd = i_rd;                        // All others: ALU result
        end
    end

endmodule
