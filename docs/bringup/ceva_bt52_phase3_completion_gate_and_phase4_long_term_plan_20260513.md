# CEVA BT5.2 Phase3 Completion Gate And Phase4 Long-Term Plan

## 1. Current Decision

Phase3 completion gate is now PASS.

The current repository has closed Phase3 completion evidence through the real vendor-runtime path: vendor approval, runtime link, init markers, real ingress, real Reset/RLV events, repeated synthetic-off regression, and controlled BlueZ entry.

Phase4 is also closed through the current executable checker chain. P4-A through P4-J now have a recorded completion surface. P4-I is closed as a conditional RTL/Vivado gate and is not entered unless a named post-P4F hardware defect appears.

## 2. Phase3 Completion Definition

Phase3 is complete only when all of these are true:

| Gate | Required proof |
|---|---|
| Vendor approval closed | CEVA source/blob use is explicitly approved for the local build path. |
| Vendor runtime link | Approved `rwip` / `rwip_driver` / `hci` / `h4tl` / `ke` / `co` / `sch` / register access subset links into the sidecar or approved firmware context. |
| Vendor init markers | `rwip_init()` and `rwip_driver_init()` execute and publish non-stale markers. |
| Real ingress | HCI Reset command reaches a vendor ingress seam such as `hci_cmd_received()` or a documented equivalent. |
| Real Reset event | Linux receives real Reset Command Complete bytes `0E 04 01 03 0C 00` with synthetic responder disabled. |
| Real RLV event | Linux receives real Read Local Version Command Complete prefix `0E 0C 01 01 10 00 ...` with synthetic responder disabled. |
| Regression | Reset/RLV real path repeats across clean boots with no stale marker ambiguity. |
| Controlled BlueZ entry | BlueZ is run only after repeated real Reset/RLV pass and produces controlled evidence on the real controller path. |

## 3. Executable Gate

Gate script:

```bash
bash scripts/check_ceva_phase3_completion_gate.sh --status
bash scripts/check_ceva_phase3_completion_gate.sh --require-pass
```

`--status` is for planning and reporting. It exits successfully while printing the current gate state, including `PHASE3_COMPLETION_GATE=PASS` once the full evidence set is present.

`--require-pass` is the hard lock for Phase4. It exits non-zero until every required Phase3 completion evidence file exists and the foundational H4/H9 guards pass.

Required evidence files live under:

```text
docs/bringup/phase3_completion_evidence/
```

Required file names:

| File | Purpose |
|---|---|
| `00_vendor_approval_closed.md` | Approval for local vendor source/blob use. |
| `01_vendor_runtime_link_pass.md` | Approved runtime link proof. |
| `02_rwip_init_and_driver_init_pass.md` | `rwip_init()` and `rwip_driver_init()` marker proof. |
| `03_real_ingress_consumed_pass.md` | Reset command consumed by real vendor ingress. |
| `04_real_reset_event_pass.md` | Real Reset Command Complete proof. |
| `05_real_rlv_event_pass.md` | Real Read Local Version proof. |
| `06_synthetic_off_repeated_regression_pass.md` | Repeated clean-boot regression with synthetic disabled. |
| `07_bluez_controlled_bringup_pass.md` | Controlled BlueZ evidence after real controller baseline. |

## 4. Phase4 Long-Term Plan Locked Behind Phase3

Phase4 starts only after:

```bash
bash scripts/check_ceva_phase3_completion_gate.sh --require-pass
```

returns PASS.

| Phase4 stage | Goal | Allowed only after Phase3 PASS |
|---|---|---|
| P4-A Release baseline freeze | Freeze commit, bitstream, payload, evidence set, and recovery runbook. Current checker PASS. | Yes |
| P4-B Production packaging | Replace GDB dev restore with OpenSBI, bootloader, or approved vendor firmware launch. Current checker PASS. | Yes |
| P4-C Reserved-memory ownership | Move from dev-only memory contract to Linux `no-map` DT reservation plus OpenSBI validate/marker ownership proof with rollback. Current checker PASS. | Yes |
| P4-D Vendor build reproducibility | Make sidecar/vendor-adapter build deterministic without committing restricted assets. Current checker PASS. | Yes |
| P4-E Driver lifecycle hardening | Harden probe/open/close/send/rx/recheck/error handling around the real hci0 smoke path. Current checker PASS. | Yes |
| P4-F Interrupt/timer/power hardening | Validate SWINT, timers, bounded recheck, shutdown, and active/no-deep-sleep policy. Current checker PASS. | Yes |
| P4-G BlueZ/Fedora integration | Move from controlled BlueZ proof to service-managed Fedora workflows. Current checker PASS. | Yes |
| P4-H Regression and observability | Build repeatable logs, marker dumps, HCI byte captures, and failure triage scripts. Current checker PASS. | Yes |
| P4-I Minimal RTL/Vivado follow-up | Open RTL/Vivado only for a specific post-Phase3 hardware defect. Current conditional gate PASS; not entered. | Yes |
| P4-J Handoff package | Deliver docs, scripts, evidence matrix, and known limitations for the next owner. Current checker PASS. | Yes |

## 5. Execution Now

The current safe work after Phase3 PASS is the complete Phase4 checker chain:

1. Freeze the current release baseline with `scripts/collect_ceva_phase4a_baseline_freeze.sh`.
2. Keep `scripts/check_ceva_phase3_completion_gate.sh --require-pass` green while Phase4 work lands.
3. Validate the launch contract with `scripts/check_ceva_phase4b_runtime_launch_contract.sh`.
4. Validate the memory ownership contract with `scripts/check_ceva_phase4c_memory_ownership_contract.sh`.
5. Keep P4-B/P4-C evidence green through the single outer checker surface.
6. Validate the completed P4-D/E/F hardening surface with `scripts/check_ceva_phase4d_to_f_hardening_contract.sh`.
7. Validate the completed P4-G/J package with `scripts/check_ceva_phase4g_to_j_completion_contract.sh`.

Do not claim RF, scan, pair, connect, discovery, throughput, coexistence, or certification from the P4-G/J package. It closes the controlled service-managed hci0 Reset/RLV workflow and handoff surface.

## 6. Current Expected Result

Expected current gate results:

```text
PHASE3_COMPLETION_GATE=PASS
P4D_TO_F_HARDENING_CONTRACT=PASS
P4G_TO_J_COMPLETION_CONTRACT=PASS
```

This closes Phase4 through the current handoff boundary. P4-I remains a conditional gate and is not entered without a named hardware defect.

## 7. Stop Rules

Stop and do not claim completion if any item is true:

- Vendor approval remains blocked.
- Runtime is not linked or is replaced by empty stubs.
- Reset/RLV evidence comes from synthetic code.
- Linux RX does not show real event bytes.
- BlueZ is used before real Reset/RLV repeated PASS.
- Generated bitstream, payload, DTB, ELF, BIN, MAP, DUMP, or log artifacts are staged.
- P4-G is described as scan, pair, connect, discovery, RF, or certification success.
- P4-I is entered without a named defect brief, minimal repro, and rollback plan.

## 8. Execution Pack Added

The execution pack includes the Phase3 completion gate and the full Phase4 contract chain:

- `scripts/check_ceva_phase3_completion_gate.sh` checks required PASS tokens, marker tokens, and HCI byte tokens inside evidence files.
- `scripts/collect_ceva_phase3_status_snapshot.sh` captures git state, H4 memory guard, H9 no-synthetic guard, current completion gate output, and evidence-file inventory.
- `scripts/collect_ceva_phase4a_baseline_freeze.sh` captures the current commit, frozen bitstream/payload provenance, evidence set, and recovery chain.
- `scripts/ceva_runtime_launch_contract.sh` centralizes the current debug-owned launch inputs.
- `scripts/check_ceva_phase4b_runtime_launch_contract.sh` validates the extracted Phase4-B launch contract.
- `scripts/ceva_reserved_memory_contract.sh` centralizes the sidecar memory windows and protected regions.
- `scripts/check_ceva_phase4c_memory_ownership_contract.sh` is the single outer-status checker for the Phase4-C chain, including DTS reserved-memory, OpenSBI validate/marker ownership, root-domain carveout-disabled semantics, and Linux C6 runtime proof.
- `docs/bringup/phase3_completion_evidence/README.md` defines the evidence directory policy.
- `docs/bringup/phase3_completion_evidence/EVIDENCE_TEMPLATES.md` contains non-unlocking templates for the required future evidence files.
- `docs/bringup/ceva_bt52_phase3_completion_execution_runbook_20260513.md` records the execution order for completing Phase3.
- `docs/bringup/ceva_bt52_phase4a_release_baseline_freeze_20260513.md` freezes the Phase4-A entry baseline.
- `docs/bringup/ceva_bt52_phase4b_production_runtime_launch_contract_20260513.md` records the launch contract and target launch owner transition.
- `docs/bringup/ceva_bt52_phase4c_reserved_memory_ownership_contract_20260513.md` records the ownership contract and target reservation mode.
- `scripts/check_ceva_phase4d_vendor_build_reproducibility.sh` validates deterministic sidecar/vendor-adapter builds and restricted-asset hygiene.
- `scripts/check_ceva_phase4e_driver_lifecycle_hardening.sh` validates driver lifecycle hardening against static source gates and the C6 runtime proof log.
- `scripts/check_ceva_phase4f_interrupt_timer_power_hardening.sh` validates SWINT/IRQ, timer recheck, shutdown, and active/no-deep-sleep policy.
- `scripts/check_ceva_phase4d_to_f_hardening_contract.sh` is the compact P4-D/E/F hardening entry.
- `docs/bringup/ceva_bt52_phase4_d_to_f_completion_and_script_inventory_20260513.md` records P4-D/J completion and manual board script inventory.
- `scripts/run_ceva_phase4g_service_managed_smoke.sh` is the board refresh entry for service-managed hci0 Reset/RLV proof capture.
- `scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh` validates the P4-G service-managed BlueZ/Fedora integration contract.
- `scripts/collect_ceva_phase4h_observability_bundle.sh` collects the P4-H regression and observability bundle.
- `scripts/check_ceva_phase4h_regression_observability_bundle.sh` validates the P4-H bundle and triage surface.
- `scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh` closes P4-I as a conditional RTL/Vivado entry gate.
- `scripts/check_ceva_phase4j_final_handoff_package.sh` validates the P4-J handoff package.
- `scripts/check_ceva_phase4g_to_j_completion_contract.sh` is the compact P4-G/J completion entry.
- `docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md` records the P4-G/J completion package, evidence matrix, known limitations, recovery SOP, and next-owner instructions.

These files now establish the Phase4 baseline and record that P4-C through P4-J have passing executable gates, with P4-I retained as a conditional gate and no RF/scan/pair/connect claim made.
