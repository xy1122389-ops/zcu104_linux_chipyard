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
- `ADDRESS_PLAN.md` : Linux front-chain address planning table
- `payload/`  : packaged payload content and standalone front-chain ELF
- `kernel/`   : future kernel image placement
- `dtb/`      : future device tree blobs
- `scripts/`  : download/build/debug entry helpers

What is done now:
- skeleton directory structure
- standalone `linux_chain.elf` build flow
- observable UART prints for Linux front-chain stages
- GDB observation points for payload/kernel/dtb/jump stages
- separation between stable baremetal path and future Linux path

What is not done yet:
- no kernel image integrated into execution flow
- no DTB integrated into execution flow
- no initramfs/rootfs integrated
- no Linux-specific bitstream/config switch added
- no Linux boot verified
- no real jump to Linux entry yet

Next expected integration steps:
1. drop kernel image into `kernel/`
2. drop DTB into `dtb/`
3. use `download_linux_payload.sh` to validate paths and intended load order
4. load `linux_chain.elf` and observe markers with `linux_chain_observe.gdb`
5. replace placeholder jump with real Linux entry handoff
