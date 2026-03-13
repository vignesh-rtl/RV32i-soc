# =====================================================
# RV32I SoC Universal Firmware Build System
# =====================================================
# Usage:
#   make APP=name            - Build specific app
#   make clean APP=name      - Clean build artifacts for app
#   make clean_all           - Clean everything
#
# Examples:
#   make APP=led_blink
#   make APP=uart_mem
# =====================================================

# ---- Configurables ----
# App to build (default if not specified)
APP ?= led_blink

# RISC-V Toolchain Prefix
PREFIX ?= /opt/riscv/bin/riscv32-unknown-elf-

# Output executable name
ONAME = firmware

# Output directory for the app
BUILD_DIR = build/$(APP)

# Output files
OUT_ELF = $(BUILD_DIR)/$(ONAME).out
OUT_BIN = $(BUILD_DIR)/$(ONAME).bin
OUT_DUMP = $(BUILD_DIR)/$(ONAME).dump
OUT_MEM = $(BUILD_DIR)/memory.mem
OUT_MAP = $(BUILD_DIR)/linker.map

# Source Directories
BSP_DIR = bsp
LIB_DIR = lib
APP_DIR = apps/$(APP)

# Files
LINKER_SCRIPT = $(BSP_DIR)/rv32i_linkerscript.ld
ENTRY_CODE = $(BSP_DIR)/entry.s
C_SOURCES = $(APP_DIR)/main.c $(wildcard $(LIB_DIR)/*.c)
ALL_SOURCES = $(ENTRY_CODE) $(C_SOURCES)

# ---- Toolchain ----
CC = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE = $(PREFIX)size

# ---- Flags ----
MARCH = rv32i_zicsr
MABI = ilp32
GCC_FLAGS = -march=$(MARCH) -mabi=$(MABI) -ffunction-sections -fdata-sections -nostartfiles -fpic -I./$(LIB_DIR)
LINK_FLAGS = -Wl,--gc-sections -Wl,-T,$(LINKER_SCRIPT) -Wl,-Map,$(OUT_MAP) -lm -lc -lgcc

# ---- Targets ----
.PHONY: all clean clean_all help dirs check_app

all: check_app dirs $(OUT_MEM)
	@echo ""
	@echo "========================================"
	@echo "  Build successful for app: $(APP)"
	@echo "  Memory file generated: $(OUT_MEM)"
	@echo "========================================"

dirs:
	@mkdir -p $(BUILD_DIR)

check_app:
	@if [ ! -d "$(APP_DIR)" ]; then \
		echo "ERROR: Application '$(APP_DIR)' not found."; \
		echo "Available apps:"; \
		ls apps/; \
		exit 1; \
	fi

$(OUT_ELF): $(ALL_SOURCES) $(LINKER_SCRIPT)
	@echo "========================================"
	@echo "[CC] Compiling $(APP)..."
	@echo "========================================"
	$(CC) $(GCC_FLAGS) $(LINK_FLAGS) -o $(OUT_ELF) $(ALL_SOURCES)
	@echo ""
	@echo "[SIZE]"
	$(SIZE) $(OUT_ELF)
	@echo ""

$(OUT_BIN): $(OUT_ELF)
	@echo "[OBJCOPY] Creating binary..."
	$(OBJCOPY) -O binary $(OUT_ELF) $(OUT_BIN)

$(OUT_DUMP): $(OUT_ELF)
	@echo "[OBJDUMP] Creating disassembly..."
	$(OBJDUMP) -D $(OUT_ELF) > $(OUT_DUMP)

$(OUT_MEM): $(OUT_BIN) $(OUT_DUMP)
	@echo "[HEX] Converting to Verilog hex format..."
	od -t x4 -An -w4 -v $(OUT_BIN) | awk '{print $$1}' > $(OUT_MEM)

clean:
	@echo "[CLEAN] Removing build artifacts for $(APP)..."
	rm -rf $(BUILD_DIR)

clean_all:
	@echo "[CLEAN] Removing all build artifacts..."
	rm -rf build/

help:
	@echo "RV32I SoC Universal Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make APP=<app_name>      - Build the specified application"
	@echo "  make clean APP=<name>    - Clean artifacts for specific app"
	@echo "  make clean_all           - Clean all builds"
	@echo "  make help                - Show this help"
	@echo ""
	@echo "Available apps:"
	@ls -1 apps/
