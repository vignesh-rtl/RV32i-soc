// ============================================================================
// basereg.v — Integer Register File (32 x 32-bit)
// ============================================================================
//
// PURPOSE:
//   Implements the RISC-V integer register file containing 32 general-purpose
//   registers (x0–x31), each 32 bits wide. Register x0 is hardwired to zero
//   per the RISC-V specification (writes to x0 are ignored, reads return 0).
//
// INPUTS FROM:
//   - Decode stage: rs1_addr, rs2_addr (which registers to read)
//   - Writeback stage: rd_addr, rd_data, wr_en (which register to write)
//
// OUTPUTS TO:
//   - Forwarding unit → ALU stage: rs1 and rs2 register values
//
// KEY CONCEPTS:
//   - Two read ports (rs1, rs2) and one write port (rd)
//   - Reads are registered (synchronous) to infer Block RAM on FPGA
//   - Writes happen in the same clock cycle (synchronous write)
//   - x0 is hardwired to zero: reads always return 0, writes are ignored
//   - Read happens during Decode stage (Stage 2)
//   - Write happens during Writeback stage (Stage 5)
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none

module basereg (
    input  wire        i_clk,          // System clock

    // ── Read Ports (used by Decode stage) ──
    input  wire        i_ce_read,      // Clock enable: read only when Decode is active
    input  wire [4:0]  i_rs1_addr,     // Source register 1 address (rs1)
    input  wire [4:0]  i_rs2_addr,     // Source register 2 address (rs2)
    output wire [31:0] o_rs1,          // Source register 1 value
    output wire [31:0] o_rs2,          // Source register 2 value

    // ── Write Port (used by Writeback stage) ──
    input  wire [4:0]  i_rd_addr,      // Destination register address (rd)
    input  wire [31:0] i_rd,           // Data to write to rd
    input  wire        i_wr            // Write enable (1 = write rd)
);

    // ── Internal Storage ──
    reg [4:0]  rs1_addr_q;                    // Registered rs1 address (for BRAM inference)
    reg [4:0]  rs2_addr_q;                    // Registered rs2 address (for BRAM inference)
    reg [31:0] base_regfile [31:1];           // 31 registers (x1–x31); x0 handled separately

    // Write enable: only write if rd != x0 (x0 is always zero)
    wire write_to_basereg = i_wr && (i_rd_addr != 0);

    // ──────────────────────────────────────────────
    //  Synchronous Read and Write
    //  Both read and write are clocked to allow FPGA
    //  synthesis tools to infer Block RAM.
    // ──────────────────────────────────────────────
    always @(posedge i_clk) begin
        // Write port: Writeback stage writes result to register file
        if (write_to_basereg) begin
            base_regfile[i_rd_addr] <= i_rd;
        end

        // Read ports: Decode stage reads source registers
        // Addresses are registered here (synchronous read for BRAM)
        if (i_ce_read) begin
            rs1_addr_q <= i_rs1_addr;
            rs2_addr_q <= i_rs2_addr;
        end
    end

    // ──────────────────────────────────────────────
    //  Output Multiplexers
    //  Return 0 for x0, otherwise return register value.
    // ──────────────────────────────────────────────
    assign o_rs1 = (rs1_addr_q == 0) ? 32'd0 : base_regfile[rs1_addr_q];
    assign o_rs2 = (rs2_addr_q == 0) ? 32'd0 : base_regfile[rs2_addr_q];

endmodule
