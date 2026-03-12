// ============================================================================
// csr.v — Control and Status Register Unit (Zicsr Extension)
// ============================================================================
//
// PURPOSE:
//   Implements the Machine-mode CSR registers required by the RISC-V
//   privileged specification. Handles:
//     - Interrupt detection and trap entry/exit
//     - CSR read/write instructions (CSRRW, CSRRS, CSRRC + immediate variants)
//     - Performance counters (mcycle, minstret)
//     - Exception detection (illegal instruction, misaligned address, etc.)
//
// INPUTS FROM:
//   - ALU stage: opcode, funct3, rs1, immediate (CSR index), PC, ALU result
//   - External: interrupt signals (external, software, timer)
//
// OUTPUTS TO:
//   - Writeback stage: CSR read value (o_csr_out), trap signals
//   - Fetch stage (via Writeback): trap address (mtvec), return address (mepc)
//
// KEY CONCEPTS:
//   CSR Registers Implemented:
//     Machine Info: mvendorid, marchid, mimpid, mhartid
//     Machine Trap Setup: mstatus, misa, mie, mtvec
//     Machine Trap Handling: mscratch, mepc, mcause, mtval, mip
//     Machine Counters: mcycle, minstret, mcountinhibit
//
//   Trap Priority (highest first):
//     1. External interrupt
//     2. Software interrupt
//     3. Timer interrupt
//     4. Illegal instruction
//     5. Address misalignment
//     6. ECALL / EBREAK
//
//   Trap Entry: saves PC to mepc, disables interrupts (mie=0), jumps to mtvec
//   Trap Exit (MRET): restores interrupts (mie=mpie), jumps to mepc
//
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "header.vh"

module csr #(
    parameter TRAP_ADDRESS = 0    // Default trap vector address
)(
    input  wire        i_clk,             // System clock
    input  wire        i_rst_n,           // Active-low reset

    // ── Interrupt Inputs ──
    input  wire        i_external_interrupt, // External interrupt source
    input  wire        i_software_interrupt, // Software interrupt (IPI)
    input  wire        i_timer_interrupt,    // Timer interrupt (CLINT)

    // ── Exception Inputs (from ALU stage) ──
    input  wire        i_is_inst_illegal,   // Illegal instruction detected
    input  wire        i_is_ecall,          // ECALL instruction
    input  wire        i_is_ebreak,         // EBREAK instruction
    input  wire        i_is_mret,           // MRET instruction

    // ── Instruction Info (for misaligned detection) ──
    input  wire [`OPCODE_WIDTH-1:0] i_opcode, // Opcode from ALU
    input  wire [31:0] i_y,                   // ALU result (address for LOAD/STORE/JUMP)

    // ── CSR Instruction Interface ──
    input  wire [2:0]  i_funct3,           // CSR operation type
    input  wire [11:0] i_csr_index,        // CSR register address (12-bit)
    input  wire [31:0] i_imm,              // Unsigned immediate for CSRRWI/CSRRSI/CSRRCI
    input  wire [31:0] i_rs1,              // rs1 value for CSRRW/CSRRS/CSRRC
    output reg  [31:0] o_csr_out,          // CSR value read (to register file via Writeback)

    // ── Trap Handler Interface ──
    input  wire [31:0] i_pc,               // Program counter from ALU stage
    input  wire        writeback_change_pc, // Writeback is changing PC (overrides this stage)
    output reg  [31:0] o_return_address,   // mepc value (where to return after trap)
    output reg  [31:0] o_trap_address,     // mtvec value (trap handler entry)
    output reg         o_go_to_trap_q,     // Registered: entering trap this cycle
    output reg         o_return_from_trap_q, // Registered: returning from trap this cycle

    // ── Performance Counter ──
    input  wire        i_minstret_inc,     // Increment minstret (1 per completed instruction)

    // ── Pipeline Control ──
    input  wire        i_ce,               // Clock enable from ALU
    input  wire        i_stall             // Stall from downstream
);

    // ── CSR Operation Type Encoding ──
    localparam CSRRW  = 3'b001,   // CSR Read-Write
               CSRRS  = 3'b010,   // CSR Read-Set (bitwise OR)
               CSRRC  = 3'b011,   // CSR Read-Clear (bitwise AND-NOT)
               CSRRWI = 3'b101,   // CSR Read-Write Immediate
               CSRRSI = 3'b110,   // CSR Read-Set Immediate
               CSRRCI = 3'b111;   // CSR Read-Clear Immediate

    // ── CSR Address Map ──
    // Machine Information
    localparam MVENDORID = 12'hF11,   // Vendor ID (JEDEC)
               MARCHID   = 12'hF12,   // Architecture ID
               MIMPID    = 12'hF13,   // Implementation ID
               MHARTID   = 12'hF14;   // Hardware Thread ID

    // Machine Trap Setup
    localparam MSTATUS   = 12'h300,   // Machine Status
               MISA      = 12'h301,   // Machine ISA
               MIE       = 12'h304,   // Machine Interrupt Enable
               MTVEC     = 12'h305;   // Machine Trap Vector

    // Machine Trap Handling
    localparam MSCRATCH  = 12'h340,   // Machine Scratch Register
               MEPC      = 12'h341,   // Machine Exception PC
               MCAUSE    = 12'h342,   // Machine Cause
               MTVAL     = 12'h343,   // Machine Trap Value
               MIP       = 12'h344;   // Machine Interrupt Pending

    // Machine Counters
    localparam MCYCLE         = 12'hB00,  // Cycle counter (lower 32)
               MCYCLEH        = 12'hB80,  // Cycle counter (upper 32)
               MINSTRET       = 12'hB02,  // Instruction counter (lower 32)
               MINSTRETH      = 12'hBB2,  // Instruction counter (upper 32)
               MCOUNTINHIBIT  = 12'h320;  // Counter inhibit control

    // ── mcause Exception/Interrupt Codes ──
    localparam MACHINE_SOFTWARE_INTERRUPT     = 3,
               MACHINE_TIMER_INTERRUPT        = 7,
               MACHINE_EXTERNAL_INTERRUPT     = 11,
               INSTRUCTION_ADDRESS_MISALIGNED = 0,
               ILLEGAL_INSTRUCTION            = 2,
               EBREAK_CODE                    = 3,
               LOAD_ADDRESS_MISALIGNED        = 4,
               STORE_ADDRESS_MISALIGNED       = 6,
               ECALL_CODE                     = 11;

    // ── Opcode convenience wires ──
    wire opcode_store  = i_opcode[`STORE];
    wire opcode_load   = i_opcode[`LOAD];
    wire opcode_branch = i_opcode[`BRANCH];
    wire opcode_jal    = i_opcode[`JAL];
    wire opcode_jalr   = i_opcode[`JALR];
    wire opcode_system = i_opcode[`SYSTEM];

    // ── Internal signals ──
    reg [31:0] csr_in;        // Value to be written to CSR
    reg [31:0] csr_data;      // Current value at CSR address
    wire       csr_enable = opcode_system && i_funct3 != 0 && i_ce && !writeback_change_pc;

    reg [1:0]  new_pc;                    // For misaligned instruction detection
    reg        go_to_trap;                // Trap entry signal
    reg        return_from_trap;          // Trap exit signal
    reg        is_load_addr_misaligned;
    reg        is_store_addr_misaligned;
    reg        is_inst_addr_misaligned;
    reg        external_interrupt_pending;
    reg        software_interrupt_pending;
    reg        timer_interrupt_pending;
    reg        is_interrupt;
    reg        is_exception;
    reg        is_trap;
    wire       stall_bit = i_stall;

    // ── CSR Register Storage ──
    // MSTATUS fields
    reg        mstatus_mie;           // Machine Interrupt Enable
    reg        mstatus_mpie;          // Machine Previous Interrupt Enable
    reg [1:0]  mstatus_mpp;           // Machine Previous Privilege

    // MIE fields (interrupt enable bits)
    reg        mie_meie;              // Machine External Interrupt Enable
    reg        mie_mtie;              // Machine Timer Interrupt Enable
    reg        mie_msie;              // Machine Software Interrupt Enable

    // MTVEC (trap vector)
    reg [29:0] mtvec_base;            // Trap base address [31:2]
    reg [1:0]  mtvec_mode;            // 0=Direct, 1=Vectored

    // Trap handling registers
    reg [31:0] mscratch;              // Scratch register for trap handlers
    reg [31:0] mepc;                  // Exception PC (saved PC)
    reg        mcause_intbit;         // 1=interrupt, 0=exception
    reg [3:0]  mcause_code;           // Cause code
    reg [31:0] mtval;                 // Trap value (offending address)

    // MIP fields (interrupt pending)
    reg        mip_meip;              // External interrupt pending
    reg        mip_mtip;              // Timer interrupt pending
    reg        mip_msip;              // Software interrupt pending

    // Performance counters
    reg [63:0] mcycle;                // Clock cycle counter
    reg [63:0] minstret;              // Instruction retired counter
    reg        mcountinhibit_cy;      // Inhibit mcycle increment
    reg        mcountinhibit_ir;      // Inhibit minstret increment

    // ──────────────────────────────────────────────
    //  Misaligned Address Detection (combinational)
    // ──────────────────────────────────────────────
    always @* begin
        is_load_addr_misaligned  = 0;
        is_store_addr_misaligned = 0;
        is_inst_addr_misaligned  = 0;
        new_pc = 0;

        // Halfword: address must be 2-byte aligned
        if (i_funct3[1:0] == 2'b01) begin
            is_load_addr_misaligned  = opcode_load  ? i_y[0] : 0;
            is_store_addr_misaligned = opcode_store ? i_y[0] : 0;
        end
        // Word: address must be 4-byte aligned
        if (i_funct3[1:0] == 2'b10) begin
            is_load_addr_misaligned  = opcode_load  ? (i_y[1:0] != 2'b00) : 0;
            is_store_addr_misaligned = opcode_store ? (i_y[1:0] != 2'b00) : 0;
        end

        // Instruction address misalignment (branches, jumps)
        if ((opcode_branch && i_y[0]) || opcode_jal || opcode_jalr) begin
            new_pc = i_pc[1:0] + i_csr_index[1:0];
            if (opcode_jalr) new_pc = i_rs1[1:0] + i_csr_index[1:0];
            is_inst_addr_misaligned = (new_pc != 2'b00);
        end
    end

    // ──────────────────────────────────────────────
    //  CSR Write Logic (sequential)
    // ──────────────────────────────────────────────
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_go_to_trap_q       <= 0;
            o_return_from_trap_q <= 0;
            mstatus_mie          <= 0;
            mstatus_mpie         <= 0;
            mstatus_mpp          <= 2'b11;
            mie_meie             <= 0;
            mie_mtie             <= 0;
            mie_msie             <= 0;
            mtvec_base           <= TRAP_ADDRESS[31:2];
            mtvec_mode           <= TRAP_ADDRESS[1:0];
            mscratch             <= 0;
            mepc                 <= 0;
            mcause_intbit        <= 0;
            mcause_code          <= 0;
            mtval                <= 0;
            mip_meip             <= 0;
            mip_mtip             <= 0;
            mip_msip             <= 0;
            mcycle               <= 0;
            minstret             <= 0;
            mcountinhibit_cy     <= 0;
            mcountinhibit_ir     <= 0;
        end
        else if (!stall_bit) begin
            // ── MSTATUS: interrupt enable management ──
            if (i_csr_index == MSTATUS && csr_enable) begin
                mstatus_mie  <= csr_in[3];
                mstatus_mpie <= csr_in[7];
            end
            else begin
                if (go_to_trap && !o_go_to_trap_q) begin
                    mstatus_mie  <= 0;              // Disable interrupts on trap entry
                    mstatus_mpie <= mstatus_mie;     // Save previous MIE
                    mstatus_mpp  <= 2'b11;           // Save previous privilege
                end
                else if (return_from_trap) begin
                    mstatus_mie  <= mstatus_mpie;    // Restore MIE on trap exit
                    mstatus_mpie <= 1;
                    mstatus_mpp  <= 2'b11;
                end
            end

            // ── MIE: interrupt enable bits ──
            if (i_csr_index == MIE && csr_enable) begin
                mie_msie <= csr_in[3];
                mie_mtie <= csr_in[7];
                mie_meie <= csr_in[11];
            end

            // ── MTVEC: trap vector configuration ──
            if (i_csr_index == MTVEC && csr_enable) begin
                mtvec_base <= csr_in[31:2];
                mtvec_mode <= csr_in[1:0];
            end

            // ── MSCRATCH: scratch register for trap handlers ──
            if (i_csr_index == MSCRATCH && csr_enable)
                mscratch <= csr_in;

            // ── MEPC: exception PC ──
            if (i_csr_index == MEPC && csr_enable)
                mepc <= {csr_in[31:2], 2'b00};
            if (go_to_trap && !o_go_to_trap_q)
                mepc <= i_pc;  // Save current PC on trap entry

            // ── MCAUSE: trap cause ──
            if (i_csr_index == MCAUSE && csr_enable) begin
                mcause_intbit <= csr_in[31];
                mcause_code   <= csr_in[3:0];
            end
            if (go_to_trap && !o_go_to_trap_q) begin
                if (external_interrupt_pending)      begin mcause_code <= MACHINE_EXTERNAL_INTERRUPT;     mcause_intbit <= 1; end
                else if (software_interrupt_pending)  begin mcause_code <= MACHINE_SOFTWARE_INTERRUPT;     mcause_intbit <= 1; end
                else if (timer_interrupt_pending)     begin mcause_code <= MACHINE_TIMER_INTERRUPT;        mcause_intbit <= 1; end
                else if (i_is_inst_illegal)           begin mcause_code <= ILLEGAL_INSTRUCTION;            mcause_intbit <= 0; end
                else if (is_inst_addr_misaligned)     begin mcause_code <= INSTRUCTION_ADDRESS_MISALIGNED; mcause_intbit <= 0; end
                else if (i_is_ecall)                  begin mcause_code <= ECALL_CODE;                     mcause_intbit <= 0; end
                else if (i_is_ebreak)                 begin mcause_code <= EBREAK_CODE;                    mcause_intbit <= 0; end
                else if (is_load_addr_misaligned)     begin mcause_code <= LOAD_ADDRESS_MISALIGNED;        mcause_intbit <= 0; end
                else if (is_store_addr_misaligned)    begin mcause_code <= STORE_ADDRESS_MISALIGNED;       mcause_intbit <= 0; end
            end

            // ── MTVAL: trap value ──
            if (i_csr_index == MTVAL && csr_enable)
                mtval <= csr_in;
            if (go_to_trap && !o_go_to_trap_q) begin
                if (is_load_addr_misaligned || is_store_addr_misaligned)
                    mtval <= i_y;  // Save offending address
            end

            // ── MCYCLE: cycle counter ──
            if (i_csr_index == MCYCLE && csr_enable)   mcycle[31:0]  <= csr_in;
            if (i_csr_index == MCYCLEH && csr_enable)  mcycle[63:32] <= csr_in;
            mcycle <= mcountinhibit_cy ? mcycle : mcycle + 1;

            // ── MIP: interrupt pending (updated from external signals) ──
            mip_msip <= i_software_interrupt;
            mip_mtip <= i_timer_interrupt;
            mip_meip <= i_external_interrupt;

            // ── MINSTRET: instruction counter ──
            if (i_csr_index == MINSTRET && csr_enable)  minstret[31:0]  <= csr_in;
            if (i_csr_index == MINSTRETH && csr_enable) minstret[63:32] <= csr_in;
            minstret <= mcountinhibit_ir ? minstret : minstret + {63'b0, (i_minstret_inc && !o_go_to_trap_q && !o_return_from_trap_q)};

            // ── MCOUNTINHIBIT ──
            if (i_csr_index == MCOUNTINHIBIT && csr_enable) begin
                mcountinhibit_cy <= csr_in[0];
                mcountinhibit_ir <= csr_in[2];
            end

            // ── Registered Trap Handler Outputs ──
            if (i_ce) begin
                o_go_to_trap_q       <= go_to_trap;
                o_return_from_trap_q <= return_from_trap;
                o_return_address     <= mepc;
                if (mtvec_mode[1] && is_interrupt)
                    o_trap_address <= {mtvec_base, 2'b00} + {28'b0, mcause_code << 2};
                else
                    o_trap_address <= {mtvec_base, 2'b00};
                o_csr_out <= csr_data;
            end
            else begin
                o_go_to_trap_q       <= 0;
                o_return_from_trap_q <= 0;
            end
        end
        else begin
            // Even when stalled, counters keep counting
            mcycle   <= mcountinhibit_cy ? mcycle   : mcycle + 1;
            minstret <= mcountinhibit_ir ? minstret : minstret + {63'b0, (i_minstret_inc && !o_go_to_trap_q && !o_return_from_trap_q)};
        end
    end

    // ──────────────────────────────────────────────
    //  Trap Detection + CSR Read/Write (combinational)
    // ──────────────────────────────────────────────
    always @* begin
        external_interrupt_pending = 0;
        software_interrupt_pending = 0;
        timer_interrupt_pending    = 0;
        is_interrupt       = 0;
        is_exception       = 0;
        is_trap            = 0;
        go_to_trap         = 0;
        return_from_trap   = 0;

        if (i_ce) begin
            // Interrupt pending: requires global enable + specific enable + pending
            external_interrupt_pending = mstatus_mie && mie_meie && mip_meip;
            software_interrupt_pending = mstatus_mie && mie_msie && mip_msip;
            timer_interrupt_pending    = mstatus_mie && mie_mtie && mip_mtip;

            is_interrupt = external_interrupt_pending || software_interrupt_pending || timer_interrupt_pending;
            is_exception = (i_is_inst_illegal || is_inst_addr_misaligned || i_is_ecall ||
                           i_is_ebreak || is_load_addr_misaligned || is_store_addr_misaligned) && !writeback_change_pc;
            is_trap = is_interrupt || is_exception;

            go_to_trap       = is_trap;
            return_from_trap = i_is_mret;
        end

        // ── CSR Read: return current value at CSR address ──
        csr_data = 0;
        case (i_csr_index)
            MVENDORID: csr_data = 32'h0;
            MARCHID:   csr_data = 32'h0;
            MIMPID:    csr_data = 32'h0;
            MHARTID:   csr_data = 32'h0;
            MSTATUS:   begin csr_data[3] = mstatus_mie; csr_data[7] = mstatus_mpie; csr_data[12:11] = mstatus_mpp; end
            MISA:      begin csr_data[8] = 1'b1; csr_data[31:30] = 2'b01; end
            MIE:       begin csr_data[3] = mie_msie; csr_data[7] = mie_mtie; csr_data[11] = mie_meie; end
            MTVEC:     csr_data = {mtvec_base, mtvec_mode};
            MSCRATCH:  csr_data = mscratch;
            MEPC:      csr_data = mepc;
            MCAUSE:    begin csr_data[31] = mcause_intbit; csr_data[3:0] = mcause_code; end
            MTVAL:     csr_data = mtval;
            MIP:       begin csr_data[3] = mip_msip; csr_data[7] = mip_mtip; csr_data[11] = mip_meip; end
            MCYCLE:    csr_data = mcycle[31:0];
            MCYCLEH:   csr_data = mcycle[63:32];
            MINSTRET:  csr_data = minstret[31:0];
            MINSTRETH: csr_data = minstret[63:32];
            MCOUNTINHIBIT: begin csr_data[0] = mcountinhibit_cy; csr_data[2] = mcountinhibit_ir; end
            default:   csr_data = 0;
        endcase

        // ── CSR Write: compute new value based on operation type ──
        csr_in = 0;
        case (i_funct3)
            CSRRW:  csr_in = i_rs1;                    // Write rs1 to CSR
            CSRRS:  csr_in = csr_data | i_rs1;         // Set bits from rs1
            CSRRC:  csr_in = csr_data & (~i_rs1);      // Clear bits from rs1
            CSRRWI: csr_in = i_imm;                    // Write immediate to CSR
            CSRRSI: csr_in = csr_data | i_imm;         // Set bits from immediate
            CSRRCI: csr_in = csr_data & (~i_imm);      // Clear bits from immediate
            default: csr_in = 0;
        endcase
    end

endmodule
