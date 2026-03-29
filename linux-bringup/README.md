# ZCU104 Linux Bring-up Skeleton

This directory is the stage-C Linux bring-up skeleton for the current
`RocketZCU104Config` flow.

Current default stable path:
- FPGA bitstream + PS DDR init: `bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh`
- Stable payload: `/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.elf`
- Runtime behavior: DS39 heartbeat + UART `count=` printing + external J-Link debug

This Linux skeleton does not replace the stable baremetal path.
It only provides a clean place to add Linux payload assets and future scripts.

Directory layout:
- `payload/`  : future packaged payload images
- `kernel/`   : future kernel image placement
- `dtb/`      : future device tree blobs
- `scripts/`  : future download and debug entry helpers

What is done now:
- skeleton directory structure
- README and placeholder scripts
- separation between stable baremetal path and future Linux path

What is not done yet:
- no kernel image integrated
- no DTB integrated
- no initramfs/rootfs integrated
- no Linux-specific bitstream/config switch added
- no Linux boot verified

Next expected integration steps:
1. drop kernel image into `kernel/`
2. drop DTB into `dtb/`
3. define payload packaging convention in `payload/`
4. implement download/load helper in `scripts/`
5. define GDB attach entry for Linux bring-up in `scripts/`
