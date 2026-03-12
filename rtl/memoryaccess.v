// ============================================================================
// memoryaccess.v — Memory Access Stage (Stage 4 of 5)
// ============================================================================
//
// PURPOSE:
//   Handles data memory read (LOAD) and write (STORE) operations via the
//   Wishbone bus interface. Also performs byte/halfword alignment and
//   sign/zero extension for loaded data.
//
// INPUTS FROM:
//   - ALU stage: computed memory address (i_y), store data (i_rs2),
//     opcode, funct3, rd value/address
//
// OUTPUTS TO:
//   - Wishbone data bus: address, data, byte strobes, control signals
//   - Writeback stage: rd value, loaded data, opcode, funct3
//   - Forwarding unit: rd_addr, wr_rd (for hazard resolution)
//
// KEY CONCEPTS:
//   - LOAD/STORE instructions use the Wishbone bus to access data memory
//   - funct3 determines data width: byte (00), halfword (01), word (10)
//   - Byte/halfword stores are aligned using byte strobes (wb_sel)
//   - Byte/halfword loads select the correct byte(s) and sign/zero extend
//   - This stage stalls while waiting for memory acknowledgment (wb_ack)
//   - The Wishbone strobe (wb_stb) goes high for 1 cycle, then waits for ack
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module memoryaccess (
    input  wire        i_clk,          // System clock
    input  wire        i_rst_n,        // Active-low reset

    // ── Data from ALU Stage ──
    input  wire [31:0] i_rs2,          // Store data (always rs2)
    input  wire [31:0] i_y,            // ALU result (memory address for LOAD/STORE)
    input  wire [2:0]  i_funct3,       // Data width: 000=byte, 001=half, 010=word
    output reg  [2:0]  o_funct3,       // Passed to Writeback
    input  wire [`OPCODE_WIDTH-1:0] i_opcode,  // Opcode from ALU
    output reg  [`OPCODE_WIDTH-1:0] o_opcode,  // Passed to Writeback
    input  wire [31:0] i_pc,           // PC from ALU
    output reg  [31:0] o_pc,           // Passed to Writeback

    // ── Register Writeback Control ──
    input  wire        i_wr_rd,        // Write enable from ALU
    output reg         o_wr_rd,        // Passed to Writeback
    input  wire [4:0]  i_rd_addr,      // Destination register from ALU
    output reg  [4:0]  o_rd_addr,      // Passed to Writeback
    input  wire [31:0] i_rd,           // rd value from ALU (non-LOAD instructions)
    output reg  [31:0] o_rd,           // Passed to Writeback

    // ── Wishbone Data Memory Bus ──
    output reg         o_wb_cyc_data,  // Bus cycle active
    output reg         o_wb_stb_data,  // Read/write request strobe
    output reg         o_wb_we_data,   // Write enable (1=write, 0=read)
    output reg  [31:0] o_wb_addr_data, // Memory address
    output reg  [31:0] o_wb_data_data, // Write data (byte-aligned)
    output reg  [3:0]  o_wb_sel_data,  // Byte strobe {byte3, byte2, byte1, byte0}
    input  wire        i_wb_ack_data,  // Acknowledgment from memory
    input  wire        i_wb_stall_data,// Memory is busy (cannot accept request)
    input  wire [31:0] i_wb_data_data, // Read data from memory

    // ── Loaded Data Output ──
    output reg  [31:0] o_data_load,    // Loaded data (sign/zero extended)

    // ── Pipeline Control ──
    input  wire        i_stall_from_alu, // ALU says: incoming LOAD/STORE, prepare stall
    input  wire        i_ce,             // Clock enable from ALU
    output reg         o_ce,             // Clock enable to Writeback
    input  wire        i_stall,          // Stall from downstream
    output reg         o_stall,          // Stall to upstream
    input  wire        i_flush,          // Flush from downstream
    output reg         o_flush           // Flush to upstream
);

    // ── Internal signals ──
    reg [31:0] data_store_d;       // Byte-aligned store data
    reg [31:0] data_load_d;        // Extracted and extended load data
    reg [3:0]  wr_mask_d;          // Byte write mask
    reg        pending_request;     // High while waiting for memory ack

    wire [1:0] addr_2   = i_y[1:0];  // Low 2 bits of address (byte offset)
    wire       stall_bit = i_stall || o_stall;

    // ──────────────────────────────────────────────
    //  Pipeline Register + Wishbone Bus Control
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_wr_rd         <= 0;
            o_wb_we_data    <= 0;
            o_ce            <= 0;
            o_wb_stb_data   <= 0;
            pending_request <= 0;
            o_wb_cyc_data   <= 0;
        end
        else begin
            // Bus cycle follows stage enable
            o_wb_cyc_data <= i_ce;

            // Clear pending request when memory acknowledges
            if (i_wb_ack_data)
                pending_request <= 0;

            // Update pipeline registers when not stalled
            if (i_ce && !stall_bit) begin
                o_rd_addr  <= i_rd_addr;
                o_funct3   <= i_funct3;
                o_opcode   <= i_opcode;
                o_pc       <= i_pc;
                o_wr_rd    <= i_wr_rd;
                o_rd       <= i_rd;
                o_data_load <= data_load_d;
            end

            // Issue memory request when no pending request
            if (i_ce && !pending_request) begin
                o_wb_stb_data   <= i_opcode[`LOAD] || i_opcode[`STORE];
                o_wb_sel_data   <= wr_mask_d;
                o_wb_we_data    <= i_opcode[`STORE];
                pending_request <= i_opcode[`LOAD] || i_opcode[`STORE];
                o_wb_addr_data  <= i_y;
                o_wb_data_data  <= data_store_d;
            end

            // De-assert strobe after memory accepts request
            if (pending_request && !i_wb_stall_data)
                o_wb_stb_data <= 0;

            // No request when stage is disabled
            if (!i_ce)
                o_wb_stb_data <= 0;

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
    //  Data Alignment + Sign Extension (combinational)
    //  Handles byte, halfword, and word LOAD/STORE.
    // ──────────────────────────────────────────────
    always @* begin
        // Stall while waiting for memory acknowledgment
        o_stall      = ((i_stall_from_alu && i_ce && !i_wb_ack_data) || i_stall) && !i_flush;
        o_flush      = i_flush;
        data_store_d = 0;
        data_load_d  = 0;
        wr_mask_d    = 0;

        case (i_funct3[1:0])
            2'b00: begin  // ── BYTE (LB/LBU/SB) ──
                // Load: select 1 of 4 bytes based on address[1:0]
                case (addr_2)
                    2'b00: data_load_d = {24'b0, i_wb_data_data[7:0]};
                    2'b01: data_load_d = {24'b0, i_wb_data_data[15:8]};
                    2'b10: data_load_d = {24'b0, i_wb_data_data[23:16]};
                    2'b11: data_load_d = {24'b0, i_wb_data_data[31:24]};
                endcase
                // Sign extend (LB) or zero extend (LBU) — funct3[2] selects
                data_load_d  = {{{24{!i_funct3[2]}} & {24{data_load_d[7]}}}, data_load_d[7:0]};
                // Store: shift byte to correct position
                wr_mask_d    = 4'b0001 << addr_2;
                data_store_d = i_rs2 << {addr_2, 3'b000};
            end

            2'b01: begin  // ── HALFWORD (LH/LHU/SH) ──
                // Load: select upper or lower halfword
                data_load_d  = addr_2[1] ? {16'b0, i_wb_data_data[31:16]}
                                         : {16'b0, i_wb_data_data[15:0]};
                // Sign extend (LH) or zero extend (LHU)
                data_load_d  = {{{16{!i_funct3[2]}} & {16{data_load_d[15]}}}, data_load_d[15:0]};
                // Store: shift halfword to correct position
                wr_mask_d    = 4'b0011 << {addr_2[1], 1'b0};
                data_store_d = i_rs2 << {addr_2[1], 4'b0000};
            end

            2'b10: begin  // ── WORD (LW/SW) ──
                data_load_d  = i_wb_data_data;
                wr_mask_d    = 4'b1111;
                data_store_d = i_rs2;
            end

            default: begin
                data_store_d = 0;
                data_load_d  = 0;
                wr_mask_d    = 0;
            end
        endcase
    end

endmodule
