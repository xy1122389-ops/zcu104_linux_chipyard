ROOT_DIR := /root/chipyard/fpga/linux-bringup/payload/linux-chain
BUILD_DIR := $(ROOT_DIR)/build
RISCV ?= /root/chipyard/.oclaw-env/riscv-tools
CC := $(RISCV)/bin/riscv64-unknown-elf-gcc
OBJCOPY := $(RISCV)/bin/riscv64-unknown-elf-objcopy
OBJDUMP := $(RISCV)/bin/riscv64-unknown-elf-objdump
NM := $(RISCV)/bin/riscv64-unknown-elf-nm

INCLUDES := -I /root/chipyard/fpga/src/main/resources/zcu104/sdboot/include
CFLAGS := -march=rv64ima_zicsr_zifencei -mcmodel=medany -O0 -g -std=gnu11 -Wall -nostartfiles -fno-common -ffreestanding -mabi=lp64 -DTL_CLK="50UL"
LDFLAGS := -static -nostdlib -T $(ROOT_DIR)/linker.lds

ELF := $(BUILD_DIR)/linux_chain.elf
BIN := $(BUILD_DIR)/linux_chain.bin
DUMP := $(BUILD_DIR)/linux_chain.dump
NMOUT := $(BUILD_DIR)/linux_chain.nm
MANIFEST_ADDR := 0x803df000

.PHONY: all clean

all: $(ELF) $(BIN) $(DUMP) $(NMOUT)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): $(ROOT_DIR)/head.S $(ROOT_DIR)/linux_chain.c $(ROOT_DIR)/linker.lds | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(LDFLAGS) -o $@ $(ROOT_DIR)/head.S $(ROOT_DIR)/linux_chain.c

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(DUMP): $(ELF)
	$(OBJDUMP) -D -S $< > $@

$(NMOUT): $(ELF)
	$(NM) -n $< > $@

clean:
	rm -rf $(BUILD_DIR)
