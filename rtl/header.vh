// ============================================================================
// header.vh — Global Defines and Constants for RV32I Pipeline
// ============================================================================
//
// This file defines all shared constants used across the pipeline modules:
//   - ALU operation codes (ADD, SUB, SLT, etc.)
//   - Opcode type identifiers (R-type, I-type, LOAD, STORE, etc.)
//   - Exception type identifiers (ILLEGAL, ECALL, EBREAK, MRET)
//   - RISC-V instruction opcode encodings (7-bit opcode field)
//   - RISC-V funct3 encodings for ALU and branch operations
//
// Usage: `include "header.vh" in every pipeline module
// ============================================================================


// ──────────────────────────────────────────────
//  ALU Operation Select (one-hot encoded)
//  These bits select which ALU operation to perform.
//  Only ONE bit is high at a time.
// ──────────────────────────────────────────────
`define ALU_WIDTH   14       // Total number of ALU operations

`define ADD         0        // Addition
`define SUB         1        // Subtraction
`define SLT         2        // Set Less Than (signed)
`define SLTU        3        // Set Less Than (unsigned)
`define XOR         4        // Bitwise XOR
`define OR          5        // Bitwise OR
`define AND         6        // Bitwise AND
`define SLL         7        // Shift Left Logical
`define SRL         8        // Shift Right Logical
`define SRA         9        // Shift Right Arithmetic
`define EQ          10       // Equal (for BEQ)
`define NEQ         11       // Not Equal (for BNE)
`define GE          12       // Greater or Equal (signed, for BGE)
`define GEU         13       // Greater or Equal (unsigned, for BGEU)


// ──────────────────────────────────────────────
//  Opcode Type Select (one-hot encoded)
//  Decoder asserts ONE of these to identify instruction type.
// ──────────────────────────────────────────────
`define OPCODE_WIDTH 11      // Total number of opcode types

`define RTYPE       0        // R-type (register-register: ADD, SUB, AND, OR, ...)
`define ITYPE       1        // I-type (register-immediate: ADDI, ANDI, ORI, ...)
`define LOAD        2        // Load (LB, LH, LW, LBU, LHU)
`define STORE       3        // Store (SB, SH, SW)
`define BRANCH      4        // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
`define JAL         5        // Jump And Link (JAL)
`define JALR        6        // Jump And Link Register (JALR)
`define LUI         7        // Load Upper Immediate (LUI)
`define AUIPC       8        // Add Upper Immediate to PC (AUIPC)
`define SYSTEM      9        // System instructions (CSR, ECALL, EBREAK, MRET)
`define FENCE       10       // Memory fence (FENCE)


// ──────────────────────────────────────────────
//  Exception Type Select (decoded by decoder)
// ──────────────────────────────────────────────
`define EXCEPTION_WIDTH 4    // Total number of exception types

`define ILLEGAL     0        // Illegal instruction detected
`define ECALL       1        // Environment call (trap to OS/firmware)
`define EBREAK      2        // Breakpoint (debug trap)
`define MRET        3        // Return from machine-mode trap


// ──────────────────────────────────────────────
//  RISC-V Instruction Opcode Encodings
//  These are the 7-bit opcode field values from the
//  RV32I instruction encoding (bits [6:0]).
// ──────────────────────────────────────────────
`define OPCODE_RTYPE    7'b0110011   // R-type instructions
`define OPCODE_ITYPE    7'b0010011   // I-type ALU instructions
`define OPCODE_LOAD     7'b0000011   // Load instructions
`define OPCODE_STORE    7'b0100011   // Store instructions
`define OPCODE_BRANCH   7'b1100011   // Branch instructions
`define OPCODE_JAL      7'b1101111   // JAL instruction
`define OPCODE_JALR     7'b1100111   // JALR instruction
`define OPCODE_LUI      7'b0110111   // LUI instruction
`define OPCODE_AUIPC    7'b0010111   // AUIPC instruction
`define OPCODE_SYSTEM   7'b1110011   // System (CSR/ECALL/EBREAK/MRET)
`define OPCODE_FENCE    7'b0001111   // FENCE instruction


// ──────────────────────────────────────────────
//  RISC-V funct3 Encodings
//  These are the 3-bit funct3 field values used to
//  distinguish operations within the same opcode.
// ──────────────────────────────────────────────

// ALU operations (used by R-type and I-type)
`define FUNCT3_ADD      3'b000       // ADD / SUB (distinguished by funct7 bit 30)
`define FUNCT3_SLT      3'b010       // SLT  (Set Less Than, signed)
`define FUNCT3_SLTU     3'b011       // SLTU (Set Less Than, unsigned)
`define FUNCT3_XOR      3'b100       // XOR
`define FUNCT3_OR       3'b110       // OR
`define FUNCT3_AND      3'b111       // AND
`define FUNCT3_SLL      3'b001       // SLL  (Shift Left Logical)
`define FUNCT3_SRA      3'b101       // SRL / SRA (distinguished by funct7 bit 30)

// Branch operations
`define FUNCT3_EQ       3'b000       // BEQ  (Branch if Equal)
`define FUNCT3_NEQ      3'b001       // BNE  (Branch if Not Equal)
`define FUNCT3_LT       3'b100       // BLT  (Branch if Less Than, signed)
`define FUNCT3_GE       3'b101       // BGE  (Branch if Greater or Equal, signed)
`define FUNCT3_LTU      3'b110       // BLTU (Branch if Less Than, unsigned)
`define FUNCT3_GEU      3'b111       // BGEU (Branch if Greater or Equal, unsigned)
