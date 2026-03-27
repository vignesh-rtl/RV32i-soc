# RV32I Zyn_SoC (v3.0)

A learning-oriented, bare-metal RV32I System-on-Chip project targeting the **Digilent Cmod-S7** FPGA board.
Built from scratch with a 5-stage pipelined RV32I processor core, memory-mapped peripherals, and a clean bare-metal firmware build system.

> **Status:** RTL refactoring complete. Firmware verified on hardware (LED blink + UART).

---

## Repository Structure

```
.
├── rtl/            # All Verilog RTL source files (processor core + SoC peripherals)
├── firmware/       # Bare-metal C firmware (HAL drivers, startup code, applications)
├── icarus/         # Legacy Icarus Verilog testbench variants
├── docs/           # Module documentation and design reference PDFs
└── vivado/         # Vivado TCL scripts for synthesis and flashing
```

---

## RTL — `rtl/`

The full RV32I SoC is implemented across 11 Verilog files with comprehensive inline comments.

| File | Purpose |
|---|---|
| `header.vh` | Global definitions — opcodes, ALU ops, CSR addresses |
| `fetch.v` | Instruction fetch stage — PC, stall, and bubble logic |
| `decoder.v` | Instruction decode — immediate extraction, control signals |
| `alu.v` | Execute stage — ALU, branch resolution, operand selection |
| `basereg.v` | 32×32-bit register file (x0 hardwired to zero) |
| `forwarding.v` | Data hazard detection and operand forwarding |
| `memoryaccess.v` | Memory stage — Wishbone bus, byte/halfword alignment |
| `writeback.v` | Writeback stage — rd selection, trap entry/exit |
| `csr.v` | Control/Status Registers — MTVEC, MCAUSE, MEPC, interrupts |
| `core.v` | Top-level 5-stage pipeline integrating all above stages |
| `soc.v` | Top-level SoC — core + BRAM + UART + I2C + GPIO + CLINT |

### SoC Memory Map

| Address Range | Peripheral |
|---|---|
| `0x0000_0000 – 0x0001_3FFF` | 80KB Block RAM (instructions + data) |
| `0x8000_0000 – 0x8000_000F` | CLINT — `mtime`, `mtimecmp` |
| `0x8000_0010` | CLINT — `msip` (software interrupt) |
| `0x8000_0050 – 0x8000_005F` | UART TX/RX |
| `0x8000_00A0 – 0x8000_00BF` | I2C Master (SCCB mode) |
| `0x8000_00F0 – 0x8000_00FB` | GPIO (12-pin, bidirectional) |

### Top-Level SoC Parameters

| Parameter | Default | Description |
|---|---|---|
| `CLK_FREQ_MHZ` | `12` | Input clock frequency |
| `MEMORY_DEPTH` | `81920` | BRAM size in bytes (80KB) |
| `BAUD_RATE` | `9600` | UART baud rate |
| `GPIO_COUNT` | `12` | Number of GPIO pins |
| `PC_RESET` | `0x00000000` | Reset program counter |
| `MEM_INIT_FILE` | `memory.mem` | Firmware HEX file path |

---

## Firmware — `firmware/`

A clean, universal bare-metal build system for all software running on the SoC.

```
firmware/
├── apps/
│   ├── led_blink/    # 4-LED walking blink at 250ms using timer interrupt
│   └── uart_mem/     # UART + memory read/write test
├── bsp/
│   ├── entry.s            # Assembly startup code (register init, BSS clear, trap setup)
│   └── rv32i_linkerscript.ld  # Linker script (ROM: 0-64KB, RAM: 64-80KB)
├── lib/
│   ├── rv32i.h       # Memory map definitions, CSR addresses, peripheral APIs
│   ├── clint.c       # CLINT timer driver (mtime, mtimecmp, delay functions)
│   ├── gpio.c        # GPIO driver (read/write/toggle per pin)
│   ├── uart.c        # UART driver (blocking TX, RX buffer read)
│   ├── i2c.c         # I2C master driver (SCCB mode)
│   └── printf.c      # Lightweight printf for embedded systems
├── Makefile          # Universal build system
└── README.md
```

### How to Build Firmware

The `Makefile` is universal — just specify which app to build using the `APP` variable.

```bash
cd firmware/

# Build the LED blink application
make APP=led_blink

# Build the UART memory test
make APP=uart_mem

# Clean a specific app build
make clean APP=led_blink

# Clean all builds
make clean_all
```

The compiled Verilog hex memory file is automatically generated at:
```
firmware/build/<APP_NAME>/memory.mem
```

Point your Vivado project's `MEM_INIT_FILE` parameter to this path to load the firmware.

---

## Simulation — `sim/` and `icarus/`

Simulation testbenches are organized here for Icarus Verilog.

```bash
# Example: Run fetch stage simulation
iverilog -DICARUS -o sim sim/rv_fetch_TB.v rtl/fetch.v rtl/header.vh && vvp sim
```

> **Coming soon:** Verilator-based co-simulation and CDC/linting flow.

---

## FPGA Target — Cmod-S7-25

- **Device:** Spartan-7 XC7S25
- **Clock:** 12 MHz on-board oscillator
- **LEDs:** GPIO pins [8–11] → board LEDs
- **UART:** GPIO header pins (TX: B2, RX: B1)
- **Constraints file:** `rtl/soc_cmod_s7.xdc`

---

## Reference

- Base RTL design inspired by: [Angelo Jacobo's RISC-V](https://github.com/AngeloJacobo/RISC-V)
