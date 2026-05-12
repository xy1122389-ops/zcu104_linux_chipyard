# CEVA BT5.2 Phase 3B-E1~E5 Diagnosis

## 1. Purpose

This document freezes the result of Phase 3B-E1~E5.

Goal of E1~E5 was to make selftest=0 real CEVA-owned HCI Reset reach a valid Command Complete.

Result: not PASS.

## 2. Starting point

Before E1~E5, Phase 3B-D had already moved the classification from no-send to CLASS_IRQ_NO_EVENT.

- selftest=0 observation mode was active, so the stable Phase 2.5 synthetic replay path was not the intended data source for this run. Evidence: [ceva_bt52_phase3b_selftest_off_observation_note_20260512.md](ceva_bt52_phase3b_selftest_off_observation_note_20260512.md).
- Breadcrumb evidence showed that userspace reached HCI Reset send, driver send path entered, opcode 0x0C03 was seen, EM command was written, and SWINT plus IRQ activity happened, but EM event ready never appeared. Evidence: [ceva_bt52_phase3b_d_no_send_breadcrumb_report_20260512.md](ceva_bt52_phase3b_d_no_send_breadcrumb_report_20260512.md).
- Phase 3A baseline had already recorded that the frozen baseline did not prove real CEVA firmware boot, real mailbox operation, or a real Command Complete producer. Evidence: [ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md](ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md#L90-L95).

So the local working hypothesis for E1~E5 was narrow: perhaps the real path was blocked by a host-side IRQ or MMIO bring-up gap, not by a missing firmware/bootstrap path.

## 3. Host-side hypotheses tested in E1~E5

### 3.1 Event-ready publication is late, and IRQ handling is too SWINT-centric

The current working tree added a short delayed event recheck after send and after SWINT IRQ handling. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L175), [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L351), [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1009).

This hypothesis predicts that, even if SWINT arrives before the event is published into EM, one of the recheck attempts should eventually observe EM_EVT_FLAG and drive RX work.

It was falsified by rerun evidence: [logs/phase3b_e_irqfix_20260512_182719/run.log](logs/phase3b_e_irqfix_20260512_182719/run.log#L397-L398) still shows EM command ready stuck and event ready clear, while [logs/phase3b_e_irqfix_20260512_182719/run.log](logs/phase3b_e_irqfix_20260512_182719/run.log#L481-L483) still shows EM_EVT_READY and HCI_RECV_DONE missing.

### 3.2 DM_INTCNTL1 mask is wrong after CLKN bring-up

The current working tree also switched post-CLKN interrupt enablement from a SWINT-only mask to the Phase 0M and Phase 0F style real-path mask FIFO|CRYPT|SW|SLP = 0x800E. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L116), [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L429).

This hypothesis predicts that runtime DM_INTCNTL1 should reach 0x800E and event return should stop being blocked by the wrong IRQ mask.

It was falsified by rerun evidence: [logs/phase3b_e_irqmask_20260512_183949/run.log](logs/phase3b_e_irqmask_20260512_183949/run.log#L387-L398) shows DM_INTCNTL1 = 0x0000800E and DM_INTSTAT1 = 0x00000000, but EM[72] still remains 0xA5A5A5A5 and EM[73] stays 0x00000000. [logs/phase3b_e_irqmask_20260512_183949/run.log](logs/phase3b_e_irqmask_20260512_183949/run.log#L481-L483) still reports EM_EVT_READY and HCI_RECV_DONE missing.

### 3.3 BT_DIAGCNTL reset omission is blocking real CEVA-owned processing

The current working tree added the Phase 0M-proven BT_DIAGCNTL = 0 write during hardware init. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L401), [scripts/ceva_phase0m_jlink_rwip_full.gdb](scripts/ceva_phase0m_jlink_rwip_full.gdb).

This hypothesis predicts that, once BT_DIAGCNTL is forced back to the known-good initialization sequence, the command should be consumed or at least progress should appear on the EM event side.

It was falsified by rerun evidence: [logs/phase3b_e_diagcntl_20260512_184949/run.log](logs/phase3b_e_diagcntl_20260512_184949/run.log#L387-L398) is materially identical to the previous run, and [logs/phase3b_e_diagcntl_20260512_184949/run.log](logs/phase3b_e_diagcntl_20260512_184949/run.log#L481-L483) still shows no event-ready marker and no receive completion marker.

## 4. Current working tree state during E6 freeze

At the time of this freeze, the working tree is intentionally dirty and contains both experimental source edits and generated rebuild artifacts.

Source-side dirty files:

- [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c)
- [scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb)
- [scripts/linux_boot_phase2_launch.gdb](scripts/linux_boot_phase2_launch.gdb)
- [linux-bringup/dtb/chipyard-zcu104-fedora.dts](linux-bringup/dtb/chipyard-zcu104-fedora.dts)
- [scripts/run_ps_ddr_init.tcl](scripts/run_ps_ddr_init.tcl)

Generated or rebuilt artifacts not suitable for commit in this phase:

- [linux-bringup/dtb/chipyard-zcu104-fedora.dtb](linux-bringup/dtb/chipyard-zcu104-fedora.dtb)
- [linux-bringup/initramfs/initramfs.cpio](linux-bringup/initramfs/initramfs.cpio)
- [linux-bringup/initramfs/initramfs.cpio.gz](linux-bringup/initramfs/initramfs.cpio.gz)
- [linux-bringup/initramfs/rootfs/sbin/stage_mark](linux-bringup/initramfs/rootfs/sbin/stage_mark)
- [linux-bringup/payload/fw_payload.bin](linux-bringup/payload/fw_payload.bin)
- [linux-bringup/initramfs/rootfs/sbin/phase25_user_hci_smoke](linux-bringup/initramfs/rootfs/sbin/phase25_user_hci_smoke)
- [linux-bringup/kernel/ceva-bt52-driver/build_verify.log](linux-bringup/kernel/ceva-bt52-driver/build_verify.log)
- [rebuild_payload_execution.log](rebuild_payload_execution.log)

These files record the E1~E5 experiments. They do not convert the outcome into a PASS.

## 5. Frozen rerun chain

### 5.1 E run with delayed event recheck and relaxed IRQ entry

- Log: [logs/phase3b_e_irqfix_20260512_182719/run.log](logs/phase3b_e_irqfix_20260512_182719/run.log)
- Result: DM_INTCNTL1 = 0x0000800B, DM_INTSTAT1 = CLKN only, EM[72] still set, EM[73] still clear, no RX completion markers. Evidence: [logs/phase3b_e_irqfix_20260512_182719/run.log](logs/phase3b_e_irqfix_20260512_182719/run.log#L387-L398), [logs/phase3b_e_irqfix_20260512_182719/run.log](logs/phase3b_e_irqfix_20260512_182719/run.log#L481-L483).

### 5.2 E run with exact DM_INTCNTL1 = 0x800E real-path mask

- Log: [logs/phase3b_e_irqmask_20260512_183949/run.log](logs/phase3b_e_irqmask_20260512_183949/run.log)
- Result: runtime DM_INTCNTL1 reaches 0x0000800E and DM_INTSTAT1 clears to zero, but EM command is still not consumed and no real event appears. Evidence: [logs/phase3b_e_irqmask_20260512_183949/run.log](logs/phase3b_e_irqmask_20260512_183949/run.log#L387-L398), [logs/phase3b_e_irqmask_20260512_183949/run.log](logs/phase3b_e_irqmask_20260512_183949/run.log#L481-L483).

### 5.3 E run with BT_DIAGCNTL = 0 included

- Log: [logs/phase3b_e_diagcntl_20260512_184949/run.log](logs/phase3b_e_diagcntl_20260512_184949/run.log)
- Result: still no event consumer visible. EM[72] stays at 0xA5A5A5A5, EM[73] stays zero, and receive-side driver markers remain missing. Evidence: [logs/phase3b_e_diagcntl_20260512_184949/run.log](logs/phase3b_e_diagcntl_20260512_184949/run.log#L387-L398), [logs/phase3b_e_diagcntl_20260512_184949/run.log](logs/phase3b_e_diagcntl_20260512_184949/run.log#L481-L483).

## 6. Frozen diagnosis

Phase 3B-E1~E5 does not produce a real HCI Reset PASS.

The strongest frozen conclusion is now:

- userspace reaches the real driver send path under selftest=0
- driver sees opcode 0x0C03
- driver writes EM command data and asserts SWINT_REQ
- host-side IRQ and MMIO bring-up fixes can be applied and observed at runtime
- but EM command is still not consumed by a real CEVA firmware or mailbox consumer
- therefore no real event is returned, EM_EVT_FLAG_WORD stays clear, and real Command Complete is still absent

In short, the failure is no longer best explained as a local Linux IRQ or hw_init defect.

## 7. Decision after E5

After this freeze, work should not continue as blind local edits in irq, rx_work, or hw_init.

The next phase must instead answer the upstream ownership question:

1. Does a real CEVA firmware, bootstrap sequence, H4TL path, or mailbox consumer exist in the current integrated system?
2. If it exists, what starts it?
3. If it does not exist, what integration step is missing between the current workspace and the vendor software stack?

Until that question is answered with evidence, neither real HCI Reset PASS nor real Read Local Version PASS should be claimed.