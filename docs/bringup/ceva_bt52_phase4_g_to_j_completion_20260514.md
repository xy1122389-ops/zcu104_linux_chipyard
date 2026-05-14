# CEVA BT5.2 Phase4-G To Phase4-J Completion Package

## 1. Status

Phase4-G through Phase4-J are now closed as a controlled service-integration, regression-bundle, conditional-RTL gate, and handoff package. The completion package builds on the already passing P4-B, P4-C, and P4-D/F checker surfaces and uses the accepted C6 board proof log for hci0 Reset/RLV proof.

```text
P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS
P4G_SERVICE_CONTRACT=PASS
P4G_CONTROLLED_BLUEZ_WORKFLOW=PASS
P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS
P4H_ARTIFACT_BUNDLE_COLLECTOR=PASS
P4H_FAILURE_TRIAGE_SURFACE=PASS
P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS
P4I_RTL_VIVADO_ENTRY_RULE=PASS
P4I_RTL_VIVADO_NOT_ENTERED=PASS
P4J_FINAL_HANDOFF_PACKAGE=PASS
P4J_EVIDENCE_MATRIX=PASS
P4J_RECOVERY_SOP=PASS
P4J_NEXT_OWNER_HANDOFF=PASS
P4G_TO_J_COMPLETION_CONTRACT=PASS
```

## 2. Executable Entries

```text
scripts/run_ceva_phase4g_service_managed_smoke.sh
scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh
scripts/collect_ceva_phase4h_observability_bundle.sh
scripts/check_ceva_phase4h_regression_observability_bundle.sh
scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh
scripts/check_ceva_phase4j_final_handoff_package.sh
scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

The compact completion entry is:

```bash
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

## 3. P4-G Completion Definition

P4-G converts the earlier controlled BlueZ entry into a repeatable service-managed workflow contract. It does not claim RF, discovery, scan, pair, or connect certification.

The P4-G PASS surface requires:

- Phase3 completion gate remains PASS, including controlled BlueZ entry after real Reset/RLV baseline.
- P4-B, P4-C, and P4-D/F remain PASS.
- `run_ceva_phase4g_service_managed_smoke.sh` exists as the board refresh entry and uses J-Link recovery, the Linux/Fedora runner, and bounded kernel-run capture.
- The initramfs service path loads Bluetooth support, loads `ceva_bt52.ko`, honors `ceva_phase25_selftest=0`, waits for `hci0`, and runs the user HCI smoke.
- The proof log contains hci0 registration, `ceva_bt_open: OK`, HCI Reset PASS, Read Local Version PASS, smoke PASS, and no hard kernel failure marker.

Accepted proof inputs:

```text
runtime_log=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log
controlled_bluez_evidence=docs/bringup/phase3_completion_evidence/07_bluez_controlled_bringup_pass.md
```

## 4. P4-H Completion Definition

P4-H provides a repeatable observability and regression bundle. The bundle collector records:

- checker output for P4-C, P4-D/F, and P4-G;
- proof log copy and SHA256;
- runtime launch manifest copy and SHA256;
- runtime DTS copy and SHA256;
- sidecar binary hash when the P4-D build artifact exists;
- key hci0, Reset/RLV, boot-owner, and selftest markers;
- failure-marker scan output.

Collector entry:

```bash
PHASE4G_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/collect_ceva_phase4h_observability_bundle.sh
```

## 5. P4-I Conditional Gate

P4-I is complete as a closed decision gate, not as an RTL/Vivado change. The default result is `P4I_RTL_VIVADO_NOT_ENTERED=PASS` because no named post-P4F hardware defect is required for the current completion package.

Entering P4-I later requires all of the following:

```text
PHASE4I_ENTER=1
PHASE4I_DEFECT_BRIEF=/path/to/brief.md
PHASE4I_NAMED_HARDWARE_DEFECT=PASS
PHASE4I_MINIMAL_REPRO=PASS
PHASE4I_ROLLBACK_PLAN=PASS
```

## 6. P4-J Handoff Package

P4-J is the handoff layer for the current owner boundary. It points the next owner to the executable checkers, proof logs, recovery scripts, and remaining non-claims.

Evidence matrix:

| Area | Entry | Result |
|---|---|---|
| P4-B launch contract | `scripts/check_ceva_phase4b_runtime_launch_contract.sh` | PASS |
| P4-C memory ownership | `scripts/check_ceva_phase4c_memory_ownership_contract.sh` | PASS |
| P4-D/F hardening | `scripts/check_ceva_phase4d_to_f_hardening_contract.sh` | PASS |
| P4-G service workflow | `scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh` | PASS |
| P4-H observability bundle | `scripts/check_ceva_phase4h_regression_observability_bundle.sh` | PASS |
| P4-I RTL/Vivado gate | `scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh` | PASS |
| P4-J handoff | `scripts/check_ceva_phase4j_final_handoff_package.sh` | PASS |

Known limitations:

- No RF, discovery, scan, pair, connect, throughput, certification, or coexistence claim is made.
- P4-G is a service-managed controlled workflow gate around hci0 and Reset/RLV proof, not a full Bluetooth product validation.
- P4-I is intentionally not entered unless a named hardware defect appears after software paths are excluded.
- J-Link remains the board-control and proof-capture path for this package.

Recovery SOP:

```bash
cd /root/chipyard/fpga
bash scripts/start_jlink_server.sh
JLINK_HOST=127.0.0.1 JLINK_PORT=3333 bash scripts/jlink_recover_and_precheck.sh
bash scripts/program_phase0b_bit.sh
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

Next-owner instructions:

1. Keep the P4-G/J completion checker green before changing runtime ownership, DT reserved memory, CEVA driver lifecycle, or BlueZ service policy.
2. Use `run_ceva_phase4g_service_managed_smoke.sh` only when refreshing board proof; otherwise use the accepted proof log for offline regression.
3. Do not open RTL/Vivado work without a P4-I defect brief.
4. Do not describe this package as scan/pair/connect success.
5. If a board run regresses, collect a P4-H bundle before patching.
