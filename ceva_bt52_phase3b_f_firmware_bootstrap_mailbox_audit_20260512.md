# CEVA BT5.2 Phase 3B-F Firmware / Bootstrap / H4TL / Mailbox Consumer Audit

## 1. Purpose

This document records the Phase 3B-F pivot after Phase 3B-E failed to produce a real CEVA-owned HCI Reset PASS.

The question is no longer whether Linux-side IRQ gating or basic MMIO bring-up is correct enough.

The question is now:

Does the current integrated system actually contain and start a real CEVA firmware-side HCI command consumer and event producer?

## 2. What is already proven inside the workspace

### 2.1 Phase 2.5 only proved a synthetic control-plane baseline

Phase 2.5 proved the Linux-side control plane through the synthetic responder, not a real firmware-owned mailbox path. Evidence: [ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md](ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md#L12-L18), [ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md](ceva_bt52_phase3a_hci_control_plane_baseline_20260512.md#L82-L95).

### 2.2 selftest=0 observation mode exists specifically to observe the real path

Phase 3B-B added a runtime switch so the stable synthetic replay path can be turned off while the existing capture flow observes EM command, EM event, and IRQ state. Evidence: [ceva_bt52_phase3b_selftest_off_observation_note_20260512.md](ceva_bt52_phase3b_selftest_off_observation_note_20260512.md).

### 2.3 Phase 3B-D and 3B-E prove that command publication happens, but consumption does not

The D4 breadcrumb run already showed driver send entry, opcode 0x0C03, EM command write, and SWINT or IRQ activity, while EM event readiness remained absent. Evidence: [ceva_bt52_phase3b_d_no_send_breadcrumb_report_20260512.md](ceva_bt52_phase3b_d_no_send_breadcrumb_report_20260512.md).

The E1~E5 reruns then proved that better host-side masks and MMIO fidelity still do not cause a real event to appear. Evidence: [ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md](ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md).

## 3. What the current Linux driver actually does

The current driver performs hardware bring-up and Linux HCI device registration, but it does not perform a real firmware load, real firmware boot handshake, or H4TL bootstrap.

- `ceva_bt_open` calls hardware init, CLKN polling, and then switches to the selected interrupt mask. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L378-L429), [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1029-L1049).
- `ceva_bt_setup` only reads DM_VERSION and assigns manufacturer 0x0057. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1165-L1173).
- The capture script already dumps the exact fields needed to decide whether a real consumer has consumed the command: DM_RWDMCNTL, DM_INTCNTL1, DM_ACTFIFOSTAT, DM_ETPTR, EM[64], EM[72], EM[73], and EM[96..]. Evidence: [scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb#L211-L215), [scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb#L318-L335).

So the current in-workspace integration can observe the mailbox boundary, but it does not by itself establish that a real CEVA software stack has taken ownership of that boundary.

## 4. What exists outside the workspace

### 4.1 External vendor software stack has a real initialization and HCI consumer chain

The workspace already contains a read-only research note for the expected vendor software initialization chain:

- `rwip_init(RESET_NO_ERROR)`
- `h4tl_init()`
- `rwip_driver_init(RWIP_INIT)`
- `rwip_reset()`

Evidence: [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md#L116-L129).

Independent read-only audit of the external vendor software tree also confirms that functions such as `h4tl_init`, `hci_cmd_received`, `hci_send_2_host`, `rwip_init`, and `rwip_reset` exist there.

This is important because it proves that a real CEVA-side HCI consumer and event producer architecture exists in the vendor deliverables.

### 4.2 External vendor RTL tree contains the expected EM and packet-control blocks

The workspace file list for the current CEVA RTL points to external vendor sources that include EM and packet-control blocks relevant to command or event consumption:

- BT frame-control EM manager: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L111)
- BT packet-control EM access FSM: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L126)
- BLE event-control EM manager: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L152)
- BLE packet-control EM access FSM: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L169)
- DM AHB-to-EM bridge: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L179)
- DM EM controller: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list#L185)

These entries prove that the hardware side includes a plausible EM consumer path in the vendor design collateral.

## 5. What is not present as a proven workspace integration

The current workspace does not contain vendor software implementation files such as h4tl.c, rwip.c, hci_tl.c, or em_map.h in its own checked-in tree. Local file search for those implementation anchors returns no workspace files.

This means the current repo can reference or document the vendor software model, but it does not yet prove that the vendor software stack is compiled into the current Linux bring-up flow, loaded by the current payload, or booted by the current driver path.

The Phase 0F and Phase 0M materials therefore remain research and hardware-emulation references, not proof of current runtime ownership.

Evidence of that distinction:

- Phase 0F is a software-path research report, not an integrated boot record. Evidence: [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md#L1-L17).
- Phase 0M is a J-Link MMIO emulation of `rwip_init()` register programming, not a proof that vendor software is running in the current Linux system. Evidence: [scripts/ceva_phase0m_jlink_rwip_full.gdb](scripts/ceva_phase0m_jlink_rwip_full.gdb).
- Phase 0P is a J-Link hardware-equivalent reset experiment, not a proof that a runtime firmware consumer is booted and consuming EM commands. Evidence: [scripts/ceva_phase0p_jlink_hci_reset.gdb](scripts/ceva_phase0p_jlink_hci_reset.gdb).

## 6. Current Phase 3B-F conclusion

The best current reading is:

- a real CEVA consumer architecture exists in external vendor collateral
- the current workspace knows about that architecture through documentation, scripts, and external file lists
- but the current integrated Linux bring-up path still does not prove that a real CEVA firmware-side consumer is present, started, and consuming EM commands at runtime

The runtime symptom is consistent with that gap:

- EM command words are written
- EM command-ready flag remains set
- EM event-ready flag never rises
- EM event buffer stays zero
- driver receive completion markers never fire

That is exactly what would be expected if the command publication side exists but no real consumer has taken ownership of the mailbox path.

## 7. Gate before any future real PASS claim

Before retrying real HCI Reset PASS or real Read Local Version PASS, Phase 3B-G must first prove all of the following under selftest=0:

1. Identify the actual integrated real consumer owner in the current system image.
2. Show how that consumer is bootstrapped in the current flow.
3. Show that the consumer really starts in the current system, not only in a historical script or external vendor tree.
4. Show command consumption, not just command publication. At minimum, one of these must change for real reasons:
   - EM[72] clears after command ownership transfer
   - EM[73] becomes ready
   - EM[96..] contains a real event
   - another vendor-documented mailbox or pointer register advances in the capture
5. Show that the returned event is not coming from the synthetic responder path.

Only after those gates are met should the project retry real HCI Reset PASS and real Read Local Version PASS.

## 8. Recommended next step

The next useful step is not another blind Linux IRQ tweak.

The next useful step is a focused ownership audit for the current integrated image:

1. Determine where the real CEVA software stack would live in the present system, if anywhere.
2. Determine whether the current payload, init sequence, or driver has any bootstrap hook into that stack.
3. If not, define the smallest non-synthetic bootstrap experiment that can prove or disprove real consumer startup without changing RTL or widening scope into RF or BlueZ.