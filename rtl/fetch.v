// ============================================================================
// fetch.v — Instruction Fetch Stage (Stage 1 of 5)
// ============================================================================
//
// PURPOSE:
//   Fetches 32-bit instructions from instruction memory (BRAM) and passes
//   them to the Decode stage. Manages the Program Counter (PC), which
//   normally increments by 4 each cycle (each instruction is 4 bytes).
//
// INPUTS FROM:
//   - Instruction memory (BRAM): i_inst (32-bit instruction data)
//   - ALU stage: branch/jump target PC
//   - Writeback stage: trap handler PC
//   - Pipeline control: stall and flush signals
//
// OUTPUTS TO:
//   - Decode stage: o_inst (instruction), o_pc (PC of that instruction)
//   - Instruction memory: o_iaddr (next address to fetch)
//
// KEY CONCEPTS:
//   - PC increments by 4 each cycle (sequential execution)
//   - Branches/jumps from ALU stage override the PC
//   - Traps from Writeback stage also override the PC (higher priority)
//   - When PC changes, a pipeline bubble is inserted (o_ce goes low)
//     to prevent the already-fetched instructions from executing
//   - When stalled, the fetched instruction and PC are saved so they
//     can be replayed when the stall ends
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module fetch #(
    parameter PC_RESET = 32'h00000000  // Initial PC value after reset
)(
    input  wire        i_clk,          // System clock
    input  wire        i_rst_n,        // Active-low reset

    // ── Instruction Memory Interface ──
    output reg  [31:0] o_iaddr,        // Address sent to instruction memory
    input  wire [31:0] i_inst,         // Instruction received from memory
    output reg  [31:0] o_inst,         // Instruction passed to Decode stage
    output wire        o_stb_inst,     // Strobe: request for new instruction
    input  wire        i_ack_inst,     // Ack: instruction memory has responded

    // ── PC Output to Decode Stage ──
    output reg  [31:0] o_pc,           // PC of the instruction in o_inst

    // ── PC Override from Later Stages ──
    input  wire        i_writeback_change_pc, // Writeback says: change PC (trap)
    input  wire [31:0] i_writeback_next_pc,   // New PC from Writeback (trap address)
    input  wire        i_alu_change_pc,       // ALU says: change PC (branch/jump)
    input  wire [31:0] i_alu_next_pc,         // New PC from ALU (branch target)

    // ── Pipeline Control ──
    output reg         o_ce,           // Clock enable for Decode stage
    input  wire        i_stall,        // Stall signal from downstream stages
    input  wire        i_flush         // Flush this stage (discard current work)
);

    // ── Internal Registers ──
    reg [31:0] iaddr_d;           // Next instruction address (combinational)
    reg [31:0] prev_pc;           // Previous cycle's address (aligns PC to pipeline)
    reg [31:0] stalled_inst;      // Saved instruction during stall
    reg [31:0] stalled_pc;        // Saved PC during stall
    reg        ce;                // Internal clock enable
    reg        ce_d;              // Next clock enable (combinational)
    reg        stall_fetch;       // Internal stall for this stage
    reg        stall_q;           // Registered stall indicator

    // Stall conditions:
    //   1. Downstream stages are stalled (i_stall)
    //   2. We have a pending request but no ack yet
    //   3. We haven't sent a request at all (nothing to execute)
    wire stall_bit = stall_fetch || i_stall || (o_stb_inst && !i_ack_inst) || !o_stb_inst;

    // Request a new instruction whenever this stage is enabled
    assign o_stb_inst = ce;

    // ──────────────────────────────────────────────
    //  Clock Enable Logic
    //  Creates a 1-cycle bubble when PC needs to change,
    //  so the next stage doesn't execute stale instructions.
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            ce <= 0;
        else if ((i_alu_change_pc || i_writeback_change_pc) && !(i_stall || stall_fetch))
            ce <= 0;  // Insert bubble: disable fetch for 1 cycle during PC change
        else
            ce <= 1;  // Normal: fetch is always enabled
    end

    // ──────────────────────────────────────────────
    //  Main Pipeline Register Logic
    //  Updates instruction, PC, and handles stall recovery.
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_ce         <= 0;
            o_iaddr      <= PC_RESET;
            prev_pc      <= PC_RESET;
            stalled_inst <= 0;
            o_pc         <= 0;
        end
        else begin
            // Update outputs when not stalled (or recovering from stall)
            if ((ce && !stall_bit) || (stall_bit && !o_ce && ce) || i_writeback_change_pc) begin
                o_iaddr <= iaddr_d;
                o_pc    <= stall_q ? stalled_pc   : prev_pc;
                o_inst  <= stall_q ? stalled_inst : i_inst;
            end

            // Flush: disable next stage's clock enable
            if (i_flush && !stall_bit)
                o_ce <= 0;
            else if (!stall_bit)
                o_ce <= ce_d;   // Normal: propagate enable to Decode stage
            else if (stall_bit && !i_stall)
                o_ce <= 0;      // Pipeline bubble: this stage stalled but next isn't

            // Track stall state
            stall_q <= i_stall || stall_fetch;

            // Save instruction and PC when entering stall (for replay later)
            if (stall_bit && !stall_q) begin
                stalled_pc   <= prev_pc;
                stalled_inst <= i_inst;
            end

            // Delay PC by 1 cycle to align with pipeline timing
            prev_pc <= o_iaddr;
        end
    end

    // ──────────────────────────────────────────────
    //  Next PC and Clock Enable Computation
    //  Priority: Writeback (trap) > ALU (branch/jump) > PC+4 (sequential)
    // ──────────────────────────────────────────────
    always @* begin
        iaddr_d     = 0;
        ce_d        = 0;
        stall_fetch = i_stall;

        if (i_writeback_change_pc) begin
            // HIGHEST PRIORITY: Trap handler redirect
            iaddr_d = i_writeback_next_pc;
            ce_d    = 0;  // Bubble: don't enable Decode yet
        end
        else if (i_alu_change_pc) begin
            // Branch or jump taken
            iaddr_d = i_alu_next_pc;
            ce_d    = 0;  // Bubble: don't enable Decode yet
        end
        else begin
            // Normal sequential execution: PC = PC + 4
            iaddr_d = o_iaddr + 32'd4;
            ce_d    = ce;
        end
    end

endmodule
