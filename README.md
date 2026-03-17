# RV32I SoC (RTL Development)

This repository contains an RV32I SoC RTL project that is currently under development.

> **Status:** Code is under update.

## Repository Structure

- `rtl/` — RTL source files
- `sim/` — Simulation testbench files
- `icarus/` — Icarus Verilog testbench variant
- `docs/` — PDF documentation

## Current RTL Files

| File | Description |
|---|---|
| `rtl/rv_fetch.v` | Fetch stage logic |
| `rtl/rv_decoder.v` | Decoder stage logic |
| `rtl/rv_basereg.v` | Base register file |
| `rtl/rv_header.vh` | Common RTL definitions |

## Simulation Files

- `sim/rv_fetch_TB.v`
- `icarus/TB_rv_fetch.v`

## Documentation Files

- `docs/rv32i_fetch_documentation.pdf`
- `docs/rv_fetch_document.pdf`
- `docs/zyn_basereg_documentation.pdf`

## Example Icarus Run

```bash
iverilog -o sim/out sim/rv_fetch_TB.v rtl/rv_fetch.v rtl/rv_header.vh && vvp sim/out
```

## Reference

- Angelo Jacobo — RISC-V: https://github.com/AngeloJacobo/RISC-V
