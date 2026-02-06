
---

## RTL Directory (rtl/)

Contains synthesizable Verilog modules:

- core.v        : Top-level processor module
- data_path.v   : Datapath implementation
- control.v     : Control logic
- alu.v         : Arithmetic Logic Unit
- reg_file.v    : Register file
- ifu.v         : Instruction fetch unit
- instr_mem.v   : Instruction memory model

These modules together implement the RV32I single-cycle processor.

---

## Simulation Directory (sim/)

Contains simulation files used for functional verification:

- sim.v : Processor testbench

Simulation is used to verify instruction execution and control flow.

---

## Features (v1.0)

- RV32I base instruction support
- Single-cycle processor architecture
- Modular RTL design
- Functional simulation setup
- FPGA-ready RTL structure

---

## Future Work

- Pipeline implementation
- Memory interface improvements
- Peripheral integration
- SoC-level expansion

---

## Author

Vignesh D  
FPGA / RTL Design

