CROSS_COMPILE ?= riscv64-unknown-elf-

CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

BUILD_DIR := build
TARGET := $(BUILD_DIR)/sidecar

CFLAGS := -Wall -Wextra -Werror -Os -g
CFLAGS += -ffreestanding -fno-builtin -fno-stack-protector
CFLAGS += -nostdlib -nostartfiles -mcmodel=medany -msmall-data-limit=0
CFLAGS += -march=rv64imac -mabi=lp64 -I.

LDFLAGS := -T linker.ld -nostdlib -nostartfiles
LDFLAGS += -Wl,--gc-sections -Wl,-Map=$(TARGET).map

OBJECTS := $(BUILD_DIR)/start.o $(BUILD_DIR)/main.o

.PHONY: all clean

all: $(TARGET).elf $(TARGET).bin $(TARGET).map $(TARGET).dump

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/%.o: %.S marker.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.o: %.c marker.h bridge_contract.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(TARGET).elf: $(OBJECTS) linker.ld
	$(CC) $(CFLAGS) $(OBJECTS) $(LDFLAGS) -o $@

$(TARGET).map: $(TARGET).elf
	@test -f $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).dump: $(TARGET).elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf $(BUILD_DIR)
