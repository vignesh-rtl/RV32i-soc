# Firmware Organization

This folder contains the firmware architecture for the RV32I SoC.

## Directory Structure

- `apps/`: Contains individual applications (e.g., `led_blink`, `uart_mem`). Each app has its own `main.c`.
- `bsp/`: Board Support Package (Linker script, startup/entry code).
- `lib/`: Hardware Abstraction Layer (HAL) libraries (`uart.c`, `gpio.c`, `rv32i.h`, etc.).
- `build/`: Auto-generated compilation artifacts, separated by application.

## How to Build

Use the universal `Makefile` to compile any app. 

### 1. Build an App
Run `make` and specify the `APP` name. It defaults to `led_blink` if none is provided.

```bash
cd firmware/
make APP=led_blink
make APP=uart_mem
```

### 2. Output Files
The compiled files are placed in a dedicated `build/<app_name>/` folder to prevent conflict between apps. 
The generated Verilog Hex file needed for Vivado is here:
- `firmware/build/<app_name>/memory.mem`

### 3. Clean
To clean a specific app:
```bash
make clean APP=led_blink
```
To clean all built apps:
```bash
make clean_all
```
