# Phase3 Evidence 06: Synthetic-Off Repeated Reset/RLV Regression

Status: local Rocket-executed vendor runtime regression proof.
Date: 2026-05-13 local J-Link run.

```text
PHASE3_SYNTHETIC_OFF_REGRESSION=PASS
RESET_RLV_REPEAT_COUNT=4
SYNTHETIC_DISABLED=PASS
```

## Scope

This evidence repeats the evidence-04 Reset event proof and evidence-05 Read Local Version event proof twice each under the same synthetic-off local vendor runtime configuration.

The repeated runs reload the local RV64 vendor runtime image, restart J-Link, execute the real vendor handlers, capture the event bytes at the terminal H4TL boundary, and verify the exact required Reset/RLV event tokens.

This evidence does not add a new runtime claim beyond evidence 04 and 05. It proves repeatability of those real vendor event paths and that the Phase2.5 synthetic responder remains disabled.

## Commands

The regression loop ran two Reset repetitions and two RLV repetitions:

```bash
cd /root/chipyard/fpga
# For i = 1..2:
#   restore + run phase3_restore_image_with_reset_handler_event_patch.gdb
#   restore + run phase3_run_reset_handler_event_patch.gdb
#   restore + run phase3_restore_image_with_rlv_handler_event_patch.gdb
#   restore + run phase3_run_rlv_handler_event_patch.gdb
```

## Key Log

```text
=== RESET_REPEAT_1 ===
[phase3-04h-reset] RESET_CC_BYTES=0E 04 01 03 0C 00
[phase3-04h-reset] PHASE3_REAL_RESET_EVENT=PASS
=== RLV_REPEAT_1 ===
[phase3-05-rlv] RLV_CC_PREFIX=0E 0C 01 01 10 00
[phase3-05-rlv] PHASE3_REAL_RLV_EVENT=PASS
=== RESET_REPEAT_2 ===
[phase3-04h-reset] RESET_CC_BYTES=0E 04 01 03 0C 00
[phase3-04h-reset] PHASE3_REAL_RESET_EVENT=PASS
=== RLV_REPEAT_2 ===
[phase3-05-rlv] RLV_CC_PREFIX=0E 0C 01 01 10 00
[phase3-05-rlv] PHASE3_REAL_RLV_EVENT=PASS
RESET_RLV_REPEAT_COUNT=4
```

## Synthetic Disabled

```text
SYNTHETIC_DISABLED=PASS
```

Basis:

```text
scripts/check_ceva_sidecar_no_synthetic_event.sh passes through the Phase3 completion gate.
linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c keeps phase25_selftest=false by default.
The repeated Reset/RLV runs used vendor hci_send_2_host()/hci_tl_send() and did not use Phase2.5 synthetic responses.
```

## Artifacts

```text
5da7108f1086c9a8f7e83b5f447a4c7827cc8cbd202a72d2408787843dd12515  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_reset_1_run.log
81ca696e055d47b86776e1ffb21c9bce2e341fd86118ab5f849750edbe323a73  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_reset_2_run.log
d6eedae84f44271ac9ec42f3bc83c4ea5bce293eeda0d99f0f42653918f46c2c  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_rlv_1_run.log
fd14ec3b23200789c955f445855d9ea300c7dca99ff8d469e87cca51fcf931c0  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_rlv_2_run.log
99966cb2627b7d3eb9db731968706dfdf3c30417aa2aeac099d21015d0c21255  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_summary.log
```

## Result

```text
PHASE3_SYNTHETIC_OFF_REGRESSION=PASS
RESET_RLV_REPEAT_COUNT=4
NO_VENDOR_SOURCE_COMMITTED=PASS
```
