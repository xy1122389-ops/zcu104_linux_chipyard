obj-m += ceva_bt52.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

# Cross-compilation for RISC-V
ARCH    ?= riscv
CROSS_COMPILE ?= riscv64-unknown-linux-gnu-

# Point to the Chipyard kernel build (adjust path as needed)
KDIR_RISCV ?= /root/chipyard/software/firemarshal/boards/default/linux-clean

# The external module build already sees the kernel tree's Module.symvers.
# Only pass an extra symvers file when a caller explicitly provides one.
BT_SYMVERS ?=

all:
	$(MAKE) -C $(KDIR_RISCV) M=$(PWD) modules \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		$(if $(strip $(BT_SYMVERS)),KBUILD_EXTRA_SYMBOLS=$(BT_SYMVERS))

clean:
	$(MAKE) -C $(KDIR_RISCV) M=$(PWD) clean \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE)


.PHONY: all clean host
