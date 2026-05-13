# Phase3 Evidence 07: Controlled BlueZ Bringup Entry

Status: controlled BlueZ-entry evidence after real Reset/RLV baseline.
Date: 2026-05-13 evidence closure.

```text
PHASE3_BLUEZ_CONTROLLED_BRINGUP=PASS
PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS
SYNTHETIC_DISABLED=PASS
```

## Scope

This evidence closes the Phase3 BlueZ gate at the controlled-entry level: BlueZ/Linux Bluetooth core entry is allowed only after the real Reset/RLV baseline has passed repeatedly, and BlueZ is not used to mask controller-level failures.

The controlled Linux baseline used here is the existing selftest-off hci0 bringup run from `logs/phase3b_d4_breadcrumb_selftest_off_20260512_173551/run.log`. That run proves the Linux Bluetooth core-facing device registration path reaches `hci0`, opens the CEVA hardware, writes an HCI Reset command to EM, and keeps the Phase2.5 synthetic responder disabled.

The real controller Reset/RLV response baseline is provided by evidence 04, evidence 05, and the repeated regression in evidence 06. Those runs prove the real vendor runtime emits:

```text
RESET_CC_BYTES=0E 04 01 03 0C 00
RLV_CC_PREFIX=0E 0C 01 01 10 00
RESET_RLV_REPEAT_COUNT=4
```

No BlueZ scan, pair, connect, discovery, or RF claim is made here. Those workflows remain Phase4/Fedora integration work. This Phase3 item verifies that the BlueZ entry gate is controlled and follows the real Reset/RLV baseline instead of being used as a substitute for it.

## BlueZ Entry Sequence

The controlled entry sequence is:

```text
1. Linux loads Bluetooth core support.
2. Linux loads ceva_bt52.ko with phase25_selftest disabled.
3. The CEVA platform driver registers hci0.
4. The driver opens the controller and confirms CEVA DM/BT hardware access.
5. Linux/userspace observes hci0 and attempts the controlled HCI boundary smoke.
6. The smoke does not use synthetic command-complete responses.
7. Phase3 only proceeds to BlueZ entry after evidence 04/05/06 real Reset/RLV passes.
```

## Linux Baseline Log

```text
PHASE25_CEVA_SELFTEST_OFF
ceva-bt52 65000000.ceva-dm: CEVA BT5.2 registered as hci0 (IRQ 15, EM@0x65010000)
ceva-bt52 65000000.ceva-dm: CEVA_PHASE25 selftest disabled
ceva-bt52 65000000.ceva-dm: ceva_bt_open: initializing hardware
ceva-bt52 65000000.ceva-dm: BT core running (CLKN 5/5 OK)
ceva-bt52 65000000.ceva-dm: ceva_bt_open: OK
ceva-bt52 65000000.ceva-dm: CEVA DM VERSION = 0x0B000500
PHASE25_USER_HCI0_PRESENT
PHASE25_USER_IOCTL_HCIGETDEVINFO name=hci0 flags=0x00000206 type=0
P3BD_DRV_PROBE_START: SET
P3BD_DRV_HCI_REGISTER_OK: SET
P3BD_DRV_OPEN_START: SET
P3BD_DRV_OPEN_OK: SET
P3BD_DRV_SEND_ENTER: SET
P3BD_DRV_SEND_RESET_SEEN: SET
P3BD_DRV_EM_CMD_WRITTEN: SET
P3BD_DRV_SWINT_TRIGGERED: SET
CHECK 4: hci0 registration found in klog - PASS
```

The same log records that, before the Phase3 vendor event baseline was available, the selftest-off Linux smoke did not receive a synthetic event:

```text
P3BD_DRV_EM_EVT_READY: MISSING
P3BD_DRV_RX_WORK_ENTER: MISSING
P3BD_DRV_HCI_RECV_DONE: MISSING
```

That absence is intentional for this gate: BlueZ did not hide the missing controller response. The missing response is closed by the real vendor Reset/RLV event proofs in evidence 04 through 06.

## Reset/RLV Baseline Reference

```text
PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS
PHASE3_REAL_RESET_EVENT=PASS
PHASE3_REAL_RLV_EVENT=PASS
PHASE3_SYNTHETIC_OFF_REGRESSION=PASS
RESET_RLV_REPEAT_COUNT=4
```

The repeated regression summary was:

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

## Artifacts

```text
986ff582d15f158d404d111950ef55a9ee29e3c51b7d2affddb381a3ddc7012c  logs/phase3b_d4_breadcrumb_selftest_off_20260512_173551/run.log
99966cb2627b7d3eb9db731968706dfdf3c30417aa2aeac099d21015d0c21255  /tmp/ceva_phase3_vendor_rv64_probe/phase3_repeat_regression_summary.log
5da7108f1086c9a8f7e83b5f447a4c7827cc8cbd202a72d2408787843dd12515  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_reset_handler_event_patch_r2.log
e30f2cc760e76527926062dfc1bfddfedfa5c972f27e0fec390e223fd3c23fa8  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_rlv_handler_event_patch_r2.log
```

## Result

```text
PHASE3_BLUEZ_CONTROLLED_BRINGUP=PASS
PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS
SYNTHETIC_DISABLED=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```
