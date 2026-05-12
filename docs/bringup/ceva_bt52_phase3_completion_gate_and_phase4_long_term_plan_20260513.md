# CEVA BT5.2 Phase3 Completion Gate And Phase4 Long-Term Plan

## 1. Current Decision

Phase3 is not complete yet.

The current repository has strong Phase3B foundation evidence through H9: sidecar marker proof, memory contract, ingress scaffold, gated egress helper, vendor adapter boundary, vendor asset inventory, and no-synthetic-event guard. That is not the same as a real CEVA controller success.

The next long-term plan is therefore locked behind a Phase3 completion gate. Phase4 work must not execute until Phase3 proves a real vendor-runtime path from Linux HCI command to CEVA runtime to Linux RX event.

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

`--status` is for planning and reporting. It exits successfully while printing `PHASE3_COMPLETION_GATE=INCOMPLETE` when expected evidence is missing.

`--require-pass` is the hard lock for Phase4. It exits non-zero until every required Phase3 completion evidence file exists and the foundational H4/H9 guards pass.

Required future evidence files live under:

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
| P4-A Release baseline freeze | Freeze commit, bitstream, payload, evidence set, and recovery runbook. | Yes |
| P4-B Production packaging | Replace GDB dev restore with OpenSBI, bootloader, or approved vendor firmware launch. | Yes |
| P4-C Reserved-memory ownership | Move from dev-only memory contract to DT/OpenSBI/runtime reservation with rollback. | Yes |
| P4-D Vendor build reproducibility | Make approved vendor runtime build deterministic without committing restricted assets. | Yes |
| P4-E Driver lifecycle hardening | Harden probe/open/close/send/rx/recheck/error handling around real controller behavior. | Yes |
| P4-F Interrupt/timer/power hardening | Validate SWINT, timers, sleep policy, and active/no-deep-sleep mode under long runs. | Yes |
| P4-G BlueZ/Fedora integration | Move from controlled BlueZ proof to service-managed Fedora workflows. | Yes |
| P4-H Regression and observability | Build repeatable logs, marker dumps, HCI byte captures, and failure triage scripts. | Yes |
| P4-I Minimal RTL/Vivado follow-up | Open RTL/Vivado only for a specific post-Phase3 hardware defect. | Yes |
| P4-J Handoff package | Deliver docs, scripts, evidence matrix, and known limitations for the next owner. | Yes |

## 5. Execution Now

The only safe work to execute before Phase3 PASS is gate hardening and Phase3 completion preparation:

1. Add the Phase3 completion gate script.
2. Record this Phase4 plan as locked behind the gate.
3. Run H4 memory contract guard.
4. Run H9 no-synthetic-event guard.
5. Build the sidecar locally and clean generated outputs.
6. Run `check_ceva_phase3_completion_gate.sh --status` and record that Phase3 is currently incomplete.

No Phase4 implementation may begin in this state.

## 6. Current Expected Result

Expected current gate result:

```text
PHASE3_COMPLETION_GATE=INCOMPLETE
```

This is a correct result, not a failure of the plan. It means the project is still blocked at the real vendor-runtime completion path and must not graduate to Phase4 yet.

## 7. Stop Rules

Stop and do not claim Phase3 completion if any item is true:

- Vendor approval remains blocked.
- Runtime is not linked or is replaced by empty stubs.
- Reset/RLV evidence comes from synthetic code.
- Linux RX does not show real event bytes.
- BlueZ is used before real Reset/RLV repeated PASS.
- Generated bitstream, payload, DTB, ELF, BIN, MAP, DUMP, or log artifacts are staged.
