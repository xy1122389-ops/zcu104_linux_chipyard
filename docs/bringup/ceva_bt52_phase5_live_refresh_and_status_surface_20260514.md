# CEVA BT5.2 Phase5 Live Refresh And Status Surface

## 1. Current Scope

Phase5 starts after the Phase4-G through Phase4-J handoff boundary. The first implementation slice is intentionally narrow: refresh the board proof with a new service-managed hci0 Reset/RLV run, collect an observability bundle, and expose a single Phase5 status entry.

This package does not claim RF, discovery, scan, pair, connect, throughput, coexistence, or certification success.

No RF/scan/pair/connect/certification claim is made by P5-A or P5-B.

## 2. Executable Entries

```text
scripts/run_ceva_phase5a_live_refresh.sh
scripts/check_ceva_phase5a_live_refresh_contract.sh
scripts/check_ceva_phase5b_single_status_surface.sh
scripts/check_ceva_phase5_current_contract.sh
```

The compact current-status entry is:

```bash
PHASE5A_LOG_PATH=/root/chipyard/fpga/logs/<phase5a-run>/run.log \
PHASE5A_BUNDLE_DIR=/root/chipyard/fpga/reports/<phase5a-run>_observability \
  bash scripts/check_ceva_phase5_current_contract.sh
```

## 3. P5-A Definition

P5-A refreshes the P4-J handoff with a fresh live board run. The runner reuses the proven P4-G service-managed path and the P4-H bundle collector:

```bash
bash scripts/run_ceva_phase5a_live_refresh.sh
```

Required PASS surface:

```text
P5A_PHASE4_BASELINE_PRECHECK=PASS
P5A_LIVE_BOARD_PROOF_REFRESH=PASS
P5A_OBSERVABILITY_BUNDLE_REFRESH=PASS
P5A_NO_RF_SCAN_PAIR_CONNECT_CLAIM=PASS
P5A_LIVE_REFRESH_CONTRACT=PASS
```

The P5-A checker rejects the accepted Phase4-C6 proof log by default. A Phase5-A pass must point at a fresh run log containing `PHASE4G_SERVICE_MANAGED_RUN_START` and `PHASE4G_SERVICE_MANAGED_RUN_DONE`, plus hci0, `ceva_bt_open: OK`, Reset/RLV, smoke, and boot-owner markers.

## 4. P5-B Definition

P5-B establishes the outer status surface for Phase5. It does not complete the whole Phase5 roadmap. It makes the current status machine explicit so later P5-C/P5-D/P5-E checkers can be added without making users recognize many separate entry points.

Required PASS surface:

```text
P5B_SINGLE_STATUS_SURFACE=PASS
P5_CURRENT_CONTRACT=PASS
```

## 5. Current Result

The current Phase5 entry contract reports P5-A complete and P5-B ready once a fresh run log and bundle pass validation:

```text
current_stage=P5A_COMPLETE_P5B_STATUS_SURFACE_READY
next_stage=P5C_SERVICE_LIFECYCLE_SOAK
P5A_LIVE_REFRESH_CONTRACT=PASS
P5B_SINGLE_STATUS_SURFACE=PASS
P5_NO_RF_SCAN_PAIR_CONNECT_CERTIFICATION_CLAIM=PASS
P5_CURRENT_CONTRACT=PASS
```

## 6. Preconditions

Before running P5-A, keep the Phase4 handoff green:

```bash
PHASE4C6_LOG_PATH=/root/chipyard/fpga/logs/phase4c6_20260513_230221/run.log \
  bash scripts/check_ceva_phase4g_to_j_completion_contract.sh
```

## 7. Stop Rules

Stop and do not claim Phase5 progress if any item is true:

- The run log is the old accepted Phase4-C6 log rather than a fresh live run.
- `PHASE4G_SERVICE_MANAGED_RUN_DONE` is absent.
- hci0, `ceva_bt_open: OK`, Reset PASS, RLV PASS, or smoke PASS is absent.
- Kernel panic, Oops, BUG, segmentation fault, CEVA fail, or PHASE25 user fail appears.
- The observability bundle is missing or its `proof_run.log` differs from the run log.
- The result is described as RF, scan, pair, connect, throughput, coexistence, or certification success.
