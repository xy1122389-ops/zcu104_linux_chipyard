# CEVA BT5.2 Phase4 D-J Completion And Script Inventory

## 1. Current Result

P4-D, P4-E, and P4-F have executable checker surfaces and pass locally against the accepted Phase4-C6 board proof log. P4-G through P4-J are now also closed by the aggregate completion checker, using the same accepted proof log plus the controlled BlueZ evidence and the new handoff package.

```bash
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4d_to_f_hardening_contract.sh
```

Expected D-F PASS surface:

```text
P4D_VENDOR_BUILD_REPRODUCIBILITY=PASS
P4E_DRIVER_LIFECYCLE_HARDENING=PASS
P4F_INTERRUPT_TIMER_POWER_HARDENING=PASS
P4D_TO_F_HARDENING_CONTRACT=PASS
```

The proof log is the same C6 run that shows Linux reaching `/init`, hci0 registration, CEVA driver selftest PASS, userspace HCI Reset PASS, userspace Read Local Version PASS, and the OpenSBI boot-owner marker for `0x8FBE0000..0x8FEFFFFF`.

The aggregate G-J checker closes the service-managed workflow, observability bundle, conditional RTL/Vivado gate, and final handoff surface:

```bash
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

Expected G-J PASS surface:

```text
P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS
P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS
P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS
P4J_FINAL_HANDOFF_PACKAGE=PASS
P4G_TO_J_COMPLETION_CONTRACT=PASS
```

## 2. Phase4 Stage Plan

| Stage | Status | Executable entry | Completion definition |
|---|---|---|---|
| P4-A Release baseline freeze | PASS | `scripts/collect_ceva_phase4a_baseline_freeze.sh` | Baseline artifacts, evidence, and recovery paths are recorded. |
| P4-B Production packaging | PASS | `scripts/check_ceva_phase4b_runtime_launch_contract.sh` | OpenSBI is the current/target launch owner; GDB remains debug fallback only. |
| P4-C Reserved-memory ownership | PASS | `scripts/check_ceva_phase4c_memory_ownership_contract.sh` | Linux no-map reserved memory plus OpenSBI validate/marker ownership passes C6 board proof. |
| P4-D Vendor build reproducibility | PASS | `scripts/check_ceva_phase4d_vendor_build_reproducibility.sh` | Sidecar/vendor adapter build is deterministic, freestanding, and free of committed restricted/generated assets. |
| P4-E Driver lifecycle hardening | PASS | `scripts/check_ceva_phase4e_driver_lifecycle_hardening.sh` | Probe/register/open/close/remove/send/rx/recheck cleanup gates pass with runtime hci0 Reset/RLV smoke proof. |
| P4-F Interrupt/timer/power hardening | PASS | `scripts/check_ceva_phase4f_interrupt_timer_power_hardening.sh` | SWINT/IRQ, bounded timer recheck, interrupt shutdown, and active/no-deep-sleep policy pass with runtime proof. |
| P4-G BlueZ/Fedora integration | PASS | `scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh` | Service-managed hci0 Reset/RLV workflow contract with controlled BlueZ/Fedora entry and no RF/scan/pair/connect claim. |
| P4-H Regression and observability | PASS | `scripts/check_ceva_phase4h_regression_observability_bundle.sh` | Repeatable proof-log, manifest, DTS, sidecar hash, marker, HCI, and failure-triage bundle. |
| P4-I Minimal RTL/Vivado follow-up | PASS / not entered | `scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh` | Closed conditional gate; requires named defect brief before any RTL/Vivado work. |
| P4-J Handoff package | PASS | `scripts/check_ceva_phase4j_final_handoff_package.sh` | Final docs, scripts, evidence matrix, known limitations, recovery SOP, and next-owner instructions. |

## 3. New Checkers

```text
scripts/check_ceva_phase4d_vendor_build_reproducibility.sh
scripts/check_ceva_phase4e_driver_lifecycle_hardening.sh
scripts/check_ceva_phase4f_interrupt_timer_power_hardening.sh
scripts/check_ceva_phase4d_to_f_hardening_contract.sh
scripts/run_ceva_phase4g_service_managed_smoke.sh
scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh
scripts/collect_ceva_phase4h_observability_bundle.sh
scripts/check_ceva_phase4h_regression_observability_bundle.sh
scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh
scripts/check_ceva_phase4j_final_handoff_package.sh
scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

P4-D also locks the sidecar skeleton back to the final P4-C6 address contract:

```text
marker:  0x8FBE0000..0x8FBE0FFF
sidecar: 0x8FBF0000..0x8FBFFFFF
vendor:  0x8FC00000..0x8FDFFFFF
proof:   0x8FE00000..0x8FEFFFFF
```

Updated source/script files:

```text
sidecar/ceva_bt52_sidecar/marker.h
sidecar/ceva_bt52_sidecar/linker.ld
sidecar/ceva_bt52_sidecar/README.md
scripts/check_ceva_sidecar_memory_contract.sh
scripts/linux_boot_sidecar_marker_probe.gdb
```

## 4. Board Scripts For Manual Testing

### Bitstream Programming

```text
scripts/program_phase0b_bit.sh
scripts/program_bit_only.sh
scripts/program_linuxbringup_bit.sh
scripts/program_bit_only.tcl
scripts/program_linuxbringup_bit.tcl
scripts/reprogram_fpga_only.tcl
scripts/xsdb_reprogram_fpga.tcl
scripts/build_bit_mcs.sh
scripts/build_bitstream_wsl.sh
```

Typical manual path:

```bash
cd /root/chipyard/fpga
bash scripts/program_phase0b_bit.sh
```

### DDR / PS / PL Init

```text
scripts/run_ps_ddr_init.sh
scripts/run_ps_ddr_init_no_release.sh
scripts/run_ps_ddr_init.tcl
scripts/run_ps_ddr_init_no_release.tcl
scripts/run_ps_pl_release.sh
scripts/run_ps_pl_release.tcl
scripts/phase0b_full_init.sh
scripts/stable_init.sh
scripts/xsdb_stable_init.tcl
scripts/xsdb_full_init_v2.tcl
scripts/xsdb_reset_recover.tcl
scripts/xsdb_recover_dap.tcl
scripts/xsdb_ddr_diag.tcl
scripts/xsdb_ddr_reset.tcl
scripts/xsdb_ddr_readback.tcl
```

Use full DDR/PL init after a bad PMP or instruction-access-fault state. `SKIP_DDR_INIT=1` is only safe when the board is already known clean.

### J-Link Connection And Recovery

```text
scripts/start_jlink_server.sh
scripts/jlink_recover_and_precheck.sh
scripts/jlink_guard.sh
scripts/jlink_status.sh
scripts/jlink_scan_chain.sh
scripts/jlink_topology.sh
scripts/jlink_jtag_diag.sh
scripts/jlink_precheck.gdb
scripts/jlink_smoke_test.gdb
scripts/phase0b_start_jlink.sh
scripts/start_rocket_gdb.sh
```

Stable route:

```bash
cd /root/chipyard/fpga
bash scripts/start_jlink_server.sh
JLINK_HOST=127.0.0.1 JLINK_PORT=3333 bash scripts/jlink_recover_and_precheck.sh
```

Do not use relay/12331 for the locked ZCU104 J100 route.

### Linux / Payload Boot And Capture

```text
rebuild_payload.sh
scripts/linux_boot.gdb
scripts/start_linux_boot.sh
scripts/linux_boot_phase2_launch.gdb
scripts/linux_boot_phase2_capture.gdb
scripts/linux_boot_phase2.gdb
scripts/linux_timed_halt_capture.gdb
scripts/dump_klog.sh
scripts/quick_klog_dump.gdb
run_phase2_ceva_bt_linux.sh
run_fedora_v3fix_pio.sh
run_stable1800.sh
```

Typical proof check without touching the board:

```bash
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4c_memory_ownership_contract.sh

PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4d_to_f_hardening_contract.sh
```

## 5. Stop Rules

Do not claim P4-D/F evidence from a fresh board run unless these stay true:

- P4-C single checker remains PASS with the same proof log or newer proof log.
- Sidecar marker/image/linker addresses match `0x8FBE0000` and `0x8FBF0000`.
- P4-D clean rebuild hash is stable across two builds.
- P4-E runtime proof has hci0, Reset PASS, RLV PASS, smoke PASS, and no hard kernel failure.
- P4-F runtime proof has SWINT/IRQ path, bounded poll/recheck evidence, and no panic/Oops/BUG.
- OpenSBI root-domain carveout stays disabled for the CEVA envelope; Linux no-map remains the owner.
