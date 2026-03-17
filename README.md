# RV32I SoC Development Repository

This repository contains the ongoing RTL and firmware bring-up flow for an RV32I-based SoC.

> **Project status:** Under active development and updates.

## What This Repo Covers

- RV32I RTL building blocks (currently fetch, decoder, and base register modules)
- Simulation testbenches for RTL verification
- Module documentation PDFs
- Firmware flow to compile C code (with drivers) into a memory image (`.mem`) for SoC/program memory use

## Repository Structure

- `rtl/` — Core RTL modules
- `sim/` — Simulation testbenches
- `icarus/` — Icarus-Verilog-oriented testbench setup
- `docs/` — Module-level documentation PDFs
- `firmware/` — C firmware, driver code, and build flow for generating `.mem` files *(work in progress / being integrated)*

## RTL Modules (Current)

| File | Description |
|---|---|
| `rtl/rv_fetch.v` | Instruction fetch stage |
| `rtl/rv_decoder.v` | Instruction decode stage |
| `rtl/rv_basereg.v` | Base register file |
| `rtl/rv_header.vh` | Shared RTL definitions |

## Documentation

- `docs/rv32i_fetch_documentation.pdf`
- `docs/rv_fetch_document.pdf`
- `docs/zyn_basereg_documentation.pdf`

## Firmware Flow (C to `.mem`)

Firmware support in this project is intended for:
- Writing application code in C
- Using driver code for SoC/peripheral access
- Building firmware with an RV32I toolchain
- Generating a `.mem` image to load into simulation/SoC memory

> Exact firmware build scripts and usage are being updated along with the codebase.

## Simulation Example (Icarus Verilog)

From repository root:

```bash
iverilog -o sim/out sim/rv_fetch_TB.v rtl/rv_fetch.v rtl/rv_header.vh && vvp sim/out
```

## Version Notes

- Older milestones are available via tags: `v1.0`, `v2.0`

## Open-Source Reference

- Angelo Jacobo — RISC-V reference repository: https://github.com/AngeloJacobo/RISC-V
