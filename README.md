# RV32I SoC RTL Project

This repository contains an in-progress RV32I SoC RTL implementation.

> **Status:** Code is under active update.

## Repository Structure

- `rtl/` — RTL source modules (fetch, decoder, base register, shared header)
- `sim/` — Main simulation testbench sources
- `icarus/` — Icarus Verilog-specific testbench files
- `docs/` — PDF documentation for implemented modules

## RTL Modules (`rtl/`)

| File | Description |
|---|---|
| `rtl/rv_fetch.v` | Instruction fetch stage RTL |
| `rtl/rv_decoder.v` | RV32I instruction decoder RTL |
| `rtl/rv_basereg.v` | Base register file RTL |
| `rtl/rv_header.vh` | Shared RTL defines/macros |

## Documentation (`docs/`)

- `docs/rv32i_fetch_documentation.pdf`
- `docs/rv_fetch_document.pdf`
- `docs/zyn_basereg_documentation.pdf`

## Current Development Coverage

Implemented so far and being refined:
- Fetch stage
- Decoder stage
- Base register block

## Simulation (Icarus Verilog)

Example run from repository root:

```bash
iverilog -o sim/out sim/rv_fetch_TB.v rtl/rv_fetch.v rtl/rv_header.vh && vvp sim/out
```

## Version Notes

- Previous versions are available through tags: `v1.0`, `v2.0`

## Open-Source Reference

- Angelo Jacobo — RISC-V reference repository: https://github.com/AngeloJacobo/RISC-V
