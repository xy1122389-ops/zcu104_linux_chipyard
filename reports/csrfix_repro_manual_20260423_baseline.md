# Baseline Record - csrfix_repro_manual_20260423_121543

Date: 2026-04-23
Purpose: handoff baseline for the next SPI-SD / Fedora rootfs stage.

## Run Summary

- RUN_TAG: csrfix_repro_manual_20260423_121543
- Launch probe succeeded before boot: /tmp/agent_probe.txt was created from the active VS Code terminal.
- Boot command completed successfully: bash scripts/start_linux_boot.sh 300
- Run /init: YES
- sdhci: YES
- mmc0: YES
- mmcblk: YES
- fedora-rootfs lines: 31
- Key stop line recovered: fedora-rootfs: wait tick=0s loop=0 /dev/mmcblk0p3 still missing
- panic: no
- oops: no
- stage_mark last u64: 0x5354474500000001
- Timed halt line: target halted at PC = 0x000000008000b1d2 after the 300s window

## Artifact Freshness

- Linux Image
  - Path: /root/chipyard/software/firemarshal/boards/default/linux-clean/arch/riscv/boot/Image
  - Mtime: 2026-04-23 11:25:42.108478033 +0800
  - Size: 15471616 bytes
- OpenSBI payload
  - Path: /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
  - Mtime: 2026-04-23 11:25:45.524477265 +0800
  - Size: 17568776 bytes

## Run Artifacts

These files were produced by the successful repro run and currently live under /tmp.

- /tmp/boot_csrfix_repro_manual_20260423_121543.log
- /tmp/boot_csrfix_repro_manual_20260423_121543.strings
- /tmp/klog_csrfix_repro_manual_20260423_121543.bin
- /tmp/stage_csrfix_repro_manual_20260423_121543.bin

Important: the /tmp artifacts are ephemeral. This report is the persistent handoff note.

## Source State

- arch/riscv/include/asm/timex.h
  - get_cycles uses CSR_TIME
  - get_cycles_hi uses CSR_TIMEH
- arch/riscv/include/asm/vdso/gettimeofday.h
  - __arch_get_hw_counter returns csr_read(CSR_TIME)
- arch/riscv/kernel/cpufeature.c
  - check_unaligned_access still has the early return that marks unaligned access as slow and skips the boot-time probe
  - current message string: cpu%d: skipping unaligned access speed probe, assuming slow
- drivers/mmc/host/sdhci.c
  - current file is byte-identical to sdhci.c.v4.bak

Working tree status relative to the linux-clean tree:

- modified: arch/riscv/kernel/cpufeature.c
- modified: drivers/mmc/host/sdhci.c
- clean: arch/riscv/include/asm/timex.h
- clean: arch/riscv/include/asm/vdso/gettimeofday.h

## Practical Meaning

- This run re-established the csrfix success baseline.
- The current good stop point is not full Fedora userspace handoff.
- The current good stop point is: Run /init works, mmcblk is back, fedora-rootfs output is back, and the flow stops at /dev/mmcblk0p3 still missing.
- Use this payload and source combination as the restore point before any further SPI-SD / Fedora rootfs changes.