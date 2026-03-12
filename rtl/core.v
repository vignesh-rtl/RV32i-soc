// ============================================================================
// core.v — RV32I 5-Stage Pipelined RISC-V Processor Core (Top-Level)
// ============================================================================
//
// PURPOSE:
//   Top-level module that connects all 5 pipeline stages and supporting
//   units into a complete RV32I RISC-V processor core.
//
// ARCHITECTURE:
//   ┌───────┐   ┌─────────┐   ┌─────┐   ┌──────────────┐   ┌───────────┐
//   │ FETCH │──→│ DECODER │──→│ ALU │──→│ MEMORYACCESS │──→│ WRITEBACK │
//   │ (S1)  │   │  (S2)   │   │(S3) │   │    (S4)      │   │   (S5)    │
//   └───────┘   └─────────┘   └─────┘   └──────────────┘   └───────────┘
//       ↑            ↑           ↑             ↑                  │
//       │     ┌──────────────┐   │      ┌─────────────┐           │
//       │     │  FORWARDING  │───┘      │     CSR     │           │
//       │     └──────────────┘          └─────────────┘           │
//       │                                                         │
//       └─────────────────────────────────────────────────────────┘
//                    (PC redirect: branches, jumps, traps)
//
// SUPPORTING UNITS:
//   - BASEREG:    32 x 32-bit integer register file
//   - FORWARDING: Resolves data hazards via operand forwarding
//   - CSR:        Control/Status Registers (Zicsr extension, optional)
//
// INTERFACES:
//   - Instruction Memory: read-only, 32-bit, strobe/ack handshake
//   - Data Memory: read/write, 32-bit Wishbone bus interface
//   - Interrupts: external, software, timer (active-high)
//
// PARAMETERS:
//   - PC_RESET:        Initial PC value after reset (default: 0x0)
//   - TRAP_ADDRESS:    Default mtvec value (default: 0x0)
//   - ZICSR_EXTENSION: Enable CSR unit (1=yes, 0=no)
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module core #(
    parameter PC_RESET        = 32'h00000000,  // Reset PC value
    parameter TRAP_ADDRESS    = 0,              // Default trap handler address
    parameter ZICSR_EXTENSION = 1              // 1 = enable CSR unit
)(
    input  wire        i_clk,              // System clock
    input  wire        i_rst_n,            // Active-low reset

    // ── Instruction Memory Interface ──
    input  wire [31:0] i_inst,             // 32-bit instruction from memory
    output wire [31:0] o_iaddr,            // Instruction address to memory
    output wire        o_stb_inst,         // Instruction read request
    input  wire        i_ack_inst,         // Instruction memory acknowledge

    // ── Data Memory Interface (Wishbone Bus) ──
    output wire        o_wb_cyc_data,      // Bus cycle active
    output wire        o_wb_stb_data,      // Read/write request
    output wire        o_wb_we_data,       // Write enable
    output wire [31:0] o_wb_addr_data,     // Data memory address
    output wire [31:0] o_wb_data_data,     // Write data
    output wire [3:0]  o_wb_sel_data,      // Byte strobes
    input  wire        i_wb_ack_data,      // Data memory acknowledge
    input  wire        i_wb_stall_data,    // Data memory busy
    input  wire [31:0] i_wb_data_data,     // Read data from memory

    // ── Interrupt Inputs ──
    input  wire        i_external_interrupt,  // External interrupt
    input  wire        i_software_interrupt,  // Software interrupt (IPI)
    input  wire        i_timer_interrupt      // Timer interrupt (CLINT)
);

    // ════════════════════════════════════════════════
    //  INTERNAL WIRES: Stage-to-Stage Connections
    // ════════════════════════════════════════════════

    // Register file ↔ Forwarding
    wire [31:0] rs1_orig, rs2_orig;   // Original values from register file
    wire [31:0] rs1, rs2;             // Forwarded values (to ALU)
    wire        ce_read;              // Register file read enable

    // Fetch → Decode
    wire [31:0] fetch_pc;
    wire [31:0] fetch_inst;

    // Decode → ALU
    wire [`ALU_WIDTH-1:0]       decoder_alu;
    wire [`OPCODE_WIDTH-1:0]    decoder_opcode;
    wire [31:0]                 decoder_pc;
    wire [4:0]                  decoder_rs1_addr, decoder_rs2_addr;
    wire [4:0]                  decoder_rs1_addr_q, decoder_rs2_addr_q;
    wire [4:0]                  decoder_rd_addr;
    wire [31:0]                 decoder_imm;
    wire [2:0]                  decoder_funct3;
    wire [`EXCEPTION_WIDTH-1:0] decoder_exception;
    wire                        decoder_ce;
    wire                        decoder_flush;

    // ALU → Memory Access
    wire [`OPCODE_WIDTH-1:0]    alu_opcode;
    wire [4:0]                  alu_rs1_addr;
    wire [31:0]                 alu_rs1, alu_rs2;
    wire [11:0]                 alu_imm;
    wire [2:0]                  alu_funct3;
    wire [31:0]                 alu_y;
    wire [31:0]                 alu_pc;
    wire [31:0]                 alu_next_pc;
    wire                        alu_change_pc;
    wire                        alu_wr_rd;
    wire [4:0]                  alu_rd_addr;
    wire [31:0]                 alu_rd;
    wire                        alu_rd_valid;
    wire [`EXCEPTION_WIDTH-1:0] alu_exception;
    wire                        alu_ce;
    wire                        alu_flush;
    wire                        alu_force_stall;
    wire                        stall_from_alu;

    // Memory Access → Writeback
    wire [`OPCODE_WIDTH-1:0]    memoryaccess_opcode;
    wire [2:0]                  memoryaccess_funct3;
    wire [31:0]                 memoryaccess_pc;
    wire                        memoryaccess_wr_rd;
    wire [4:0]                  memoryaccess_rd_addr;
    wire [31:0]                 memoryaccess_rd;
    wire [31:0]                 memoryaccess_data_load;
    wire                        memoryaccess_ce;
    wire                        memoryaccess_flush;

    // Writeback outputs
    wire        writeback_wr_rd;
    wire [4:0]  writeback_rd_addr;
    wire [31:0] writeback_rd;
    wire [31:0] writeback_next_pc;
    wire        writeback_change_pc;
    wire        writeback_ce;
    wire        writeback_flush;

    // CSR outputs
    wire [31:0] csr_out;
    wire [31:0] csr_return_address;
    wire [31:0] csr_trap_address;
    wire        csr_go_to_trap;
    wire        csr_return_from_trap;

    // Stall signals (each stage can stall the pipeline)
    wire stall_decoder, stall_alu, stall_memoryaccess, stall_writeback;

    // Register file reads during Decode (only when not stalled)
    assign ce_read = decoder_ce && !stall_decoder;


    // ════════════════════════════════════════════════
    //  MODULE INSTANTIATIONS
    // ════════════════════════════════════════════════

    // ── Operand Forwarding Unit ──
    forwarding u_forwarding (
        .i_rs1_orig            (rs1_orig),
        .i_rs2_orig            (rs2_orig),
        .i_decoder_rs1_addr_q  (decoder_rs1_addr_q),
        .i_decoder_rs2_addr_q  (decoder_rs2_addr_q),
        .o_alu_force_stall     (alu_force_stall),
        .o_rs1                 (rs1),
        .o_rs2                 (rs2),
        // Stage 4 (Memory Access)
        .i_alu_rd_addr         (alu_rd_addr),
        .i_alu_wr_rd           (alu_wr_rd),
        .i_alu_rd_valid        (alu_rd_valid),
        .i_alu_rd              (alu_rd),
        .i_memoryaccess_ce     (memoryaccess_ce),
        // Stage 5 (Writeback)
        .i_memoryaccess_rd_addr(memoryaccess_rd_addr),
        .i_memoryaccess_wr_rd  (memoryaccess_wr_rd),
        .i_writeback_rd        (writeback_rd),
        .i_writeback_ce        (writeback_ce)
    );

    // ── Integer Register File (32 x 32-bit) ──
    basereg u_basereg (
        .i_clk      (i_clk),
        .i_ce_read  (ce_read),
        .i_rs1_addr (decoder_rs1_addr),
        .i_rs2_addr (decoder_rs2_addr),
        .i_rd_addr  (writeback_rd_addr),
        .i_rd       (writeback_rd),
        .i_wr       (writeback_wr_rd),
        .o_rs1      (rs1_orig),
        .o_rs2      (rs2_orig)
    );

    // ── Stage 1: Instruction Fetch ──
    fetch #(.PC_RESET(PC_RESET)) u_fetch (
        .i_clk                 (i_clk),
        .i_rst_n               (i_rst_n),
        .o_iaddr               (o_iaddr),
        .o_pc                  (fetch_pc),
        .i_inst                (i_inst),
        .o_inst                (fetch_inst),
        .o_stb_inst            (o_stb_inst),
        .i_ack_inst            (i_ack_inst),
        // PC redirect
        .i_writeback_change_pc (writeback_change_pc),
        .i_writeback_next_pc   (writeback_next_pc),
        .i_alu_change_pc       (alu_change_pc),
        .i_alu_next_pc         (alu_next_pc),
        // Pipeline control
        .o_ce                  (decoder_ce),
        .i_stall               (stall_decoder || stall_alu || stall_memoryaccess || stall_writeback),
        .i_flush               (decoder_flush)
    );

    // ── Stage 2: Instruction Decode ──
    decoder u_decoder (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_inst         (fetch_inst),
        .i_pc           (fetch_pc),
        .o_pc           (decoder_pc),
        .o_rs1_addr     (decoder_rs1_addr),
        .o_rs1_addr_q   (decoder_rs1_addr_q),
        .o_rs2_addr     (decoder_rs2_addr),
        .o_rs2_addr_q   (decoder_rs2_addr_q),
        .o_rd_addr      (decoder_rd_addr),
        .o_imm          (decoder_imm),
        .o_funct3       (decoder_funct3),
        .o_alu          (decoder_alu),
        .o_opcode       (decoder_opcode),
        .o_exception    (decoder_exception),
        // Pipeline control
        .i_ce           (decoder_ce),
        .o_ce           (alu_ce),
        .i_stall        (stall_alu || stall_memoryaccess || stall_writeback),
        .o_stall        (stall_decoder),
        .i_flush        (alu_flush),
        .o_flush        (decoder_flush)
    );

    // ── Stage 3: Execute (ALU) ──
    alu u_alu (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        .i_alu             (decoder_alu),
        .i_rs1_addr        (decoder_rs1_addr_q),
        .o_rs1_addr        (alu_rs1_addr),
        .i_rs1             (rs1),
        .o_rs1             (alu_rs1),
        .i_rs2             (rs2),
        .o_rs2             (alu_rs2),
        .i_imm             (decoder_imm),
        .o_imm             (alu_imm),
        .i_funct3          (decoder_funct3),
        .o_funct3          (alu_funct3),
        .i_opcode          (decoder_opcode),
        .o_opcode          (alu_opcode),
        .i_exception       (decoder_exception),
        .o_exception       (alu_exception),
        .o_y               (alu_y),
        // PC control
        .i_pc              (decoder_pc),
        .o_pc              (alu_pc),
        .o_next_pc         (alu_next_pc),
        .o_change_pc       (alu_change_pc),
        // Basereg control
        .o_wr_rd           (alu_wr_rd),
        .i_rd_addr         (decoder_rd_addr),
        .o_rd_addr         (alu_rd_addr),
        .o_rd              (alu_rd),
        .o_rd_valid        (alu_rd_valid),
        // Pipeline control
        .o_stall_from_alu  (stall_from_alu),
        .i_ce              (alu_ce),
        .o_ce              (memoryaccess_ce),
        .i_stall           (stall_memoryaccess || stall_writeback),
        .i_force_stall     (alu_force_stall),
        .o_stall           (stall_alu),
        .i_flush           (memoryaccess_flush),
        .o_flush           (alu_flush)
    );

    // ── Stage 4: Memory Access ──
    memoryaccess u_memoryaccess (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        .i_rs2             (alu_rs2),
        .i_y               (alu_y),
        .i_funct3          (alu_funct3),
        .o_funct3          (memoryaccess_funct3),
        .i_opcode          (alu_opcode),
        .o_opcode          (memoryaccess_opcode),
        .i_pc              (alu_pc),
        .o_pc              (memoryaccess_pc),
        // Basereg control
        .i_wr_rd           (alu_wr_rd),
        .o_wr_rd           (memoryaccess_wr_rd),
        .i_rd_addr         (alu_rd_addr),
        .o_rd_addr         (memoryaccess_rd_addr),
        .i_rd              (alu_rd),
        .o_rd              (memoryaccess_rd),
        // Wishbone data bus
        .o_wb_cyc_data     (o_wb_cyc_data),
        .o_wb_stb_data     (o_wb_stb_data),
        .o_wb_we_data      (o_wb_we_data),
        .o_wb_addr_data    (o_wb_addr_data),
        .o_wb_data_data    (o_wb_data_data),
        .o_wb_sel_data     (o_wb_sel_data),
        .i_wb_ack_data     (i_wb_ack_data),
        .i_wb_stall_data   (i_wb_stall_data),
        .i_wb_data_data    (i_wb_data_data),
        .o_data_load       (memoryaccess_data_load),
        // Pipeline control
        .i_stall_from_alu  (stall_from_alu),
        .i_ce              (memoryaccess_ce),
        .o_ce              (writeback_ce),
        .i_stall           (stall_writeback),
        .o_stall           (stall_memoryaccess),
        .i_flush           (writeback_flush),
        .o_flush           (memoryaccess_flush)
    );

    // ── Stage 5: Writeback ──
    writeback u_writeback (
        .i_funct3          (memoryaccess_funct3),
        .i_data_load       (memoryaccess_data_load),
        .i_csr_out         (csr_out),
        .i_opcode_load     (memoryaccess_opcode[`LOAD]),
        .i_opcode_system   (memoryaccess_opcode[`SYSTEM]),
        // Basereg control
        .i_wr_rd           (memoryaccess_wr_rd),
        .o_wr_rd           (writeback_wr_rd),
        .i_rd_addr         (memoryaccess_rd_addr),
        .o_rd_addr         (writeback_rd_addr),
        .i_rd              (memoryaccess_rd),
        .o_rd              (writeback_rd),
        // PC control (traps)
        .i_pc              (memoryaccess_pc),
        .o_next_pc         (writeback_next_pc),
        .o_change_pc       (writeback_change_pc),
        // Trap handler
        .i_go_to_trap      (csr_go_to_trap),
        .i_return_from_trap(csr_return_from_trap),
        .i_return_address  (csr_return_address),
        .i_trap_address    (csr_trap_address),
        // Pipeline control
        .i_ce              (writeback_ce),
        .o_stall           (stall_writeback),
        .o_flush           (writeback_flush)
    );

    // ── Zicsr Extension: CSR Unit (optional) ──
    if (ZICSR_EXTENSION == 1) begin : zicsr
        csr #(.TRAP_ADDRESS(TRAP_ADDRESS)) u_csr (
            .i_clk                 (i_clk),
            .i_rst_n               (i_rst_n),
            // Interrupts
            .i_external_interrupt  (i_external_interrupt),
            .i_software_interrupt  (i_software_interrupt),
            .i_timer_interrupt     (i_timer_interrupt),
            // Exceptions
            .i_is_inst_illegal     (alu_exception[`ILLEGAL]),
            .i_is_ecall            (alu_exception[`ECALL]),
            .i_is_ebreak           (alu_exception[`EBREAK]),
            .i_is_mret             (alu_exception[`MRET]),
            // Misaligned detection
            .i_opcode              (alu_opcode),
            .i_y                   (alu_y),
            // CSR instructions
            .i_funct3              (alu_funct3),
            .i_csr_index           (alu_imm),
            .i_imm                 ({27'b0, alu_rs1_addr}),
            .i_rs1                 (alu_rs1),
            .o_csr_out             (csr_out),
            // Trap handler
            .i_pc                  (alu_pc),
            .writeback_change_pc   (writeback_change_pc),
            .o_return_address      (csr_return_address),
            .o_trap_address        (csr_trap_address),
            .o_go_to_trap_q        (csr_go_to_trap),
            .o_return_from_trap_q  (csr_return_from_trap),
            .i_minstret_inc        (writeback_ce),
            // Pipeline control
            .i_ce                  (memoryaccess_ce),
            .i_stall               (stall_writeback || stall_memoryaccess)
        );
    end
    else begin : zicsr
        // CSR disabled: tie all outputs to zero
        assign csr_out             = 0;
        assign csr_return_address  = 0;
        assign csr_trap_address    = 0;
        assign csr_go_to_trap      = 0;
        assign csr_return_from_trap = 0;
    end

endmodule
