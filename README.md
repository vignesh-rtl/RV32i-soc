# RV32I Zyn_SoC (v3.0)

A work-in-progress RV32I RTL SoC project.

> **Status:** Codes are under update.

## Repository Structure (Current)

- `rtl/` — Core RTL modules (active development)
- `sim/` — Simulation testbench sources
- `icarus/` — Icarus-oriented testbench variants
- `docs/` — Design and module documentation PDFs

## `rtl/` Folder Overview (Current Files)

| File | Purpose (3 words) |
|---|---|
| `rtl/rv_fetch.v` | Instruction fetch stage |
| `rtl/rv_decoder.v` | Instruction decode logic |
| `rtl/rv_basereg.v` | Base register file |
| `rtl/rv_header.vh` | Shared RTL definitions |
| `rtl/rv_forwarding.v` | Pipeline forwarding logic |

## Current Development Scope 

Implemented and being refined:
- Fetch stage
- Decoder stage
- Base register block
- 
- Forwarding module

## Simulation Note

To run Icarus Verilog simulation (example):
A learning-oriented RTL System-on-Chip project for a RISC-V RV32I core.

> **Project status:** Codes are under update.

## Simulation Notes

- `sim/rv_fetch_TB.v` is used for `rv_fetch.v` simulation.
- `icarus/TB_rv_fetch.v` contains the Icarus Verilog testbench setup.

### Example Icarus Run Command

```bash
iverilog -o sim TB_rv_fetch.v rv_fetch.v rv_header.vh && vvp sim
```

## Version Notes

- Previous versions are available via tags: `v1.0`, `v2.0`

## Open-Source Reference

- Angelo Jacobo’s RISC-V repository: https://github.com/AngeloJacobo/RISC-V
