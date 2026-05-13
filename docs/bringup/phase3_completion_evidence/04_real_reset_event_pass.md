# Phase3 Evidence 04: Real Reset Command Complete

Status: local Rocket-executed vendor runtime proof.
Date: 2026-05-13 local J-Link run.

```text
PHASE3_REAL_RESET_EVENT=PASS
SYNTHETIC_DISABLED=PASS
RESET_CC_BYTES=0E 04 01 03 0C 00
LINUX_RX_REAL_EVENT=PASS
```

## Scope

This evidence proves that the locally linked CEVA BT5.2 vendor runtime can produce the Reset Command Complete event bytes through the real vendor Reset handler and HCI egress path after the evidence-02 init marker chain and evidence-03 Reset ingress call have completed.

The current CEVA RTL integrated in this bitstream exposes the CEVA register and EM windows but does not expose an internal CEVA firmware CPU/code RAM execution context. For that reason this proof uses the local RV64 Rocket-executable vendor runtime probe under `/tmp/ceva_phase3_vendor_rv64_probe`, not the RV32 `fw.bin` running inside a CEVA-internal CPU.

This is evidence 04 only. It proves the real Reset event bytes and the Linux-RX-compatible event packet layout with synthetic responder disabled. It does not claim Read Local Version response, repeated regression, BlueZ bringup, or Phase3 completion.

## Vendor Path Used

The proof does not hand-code the Reset Command Complete event. It calls the real linked vendor functions:

```text
hci_cmd_received(0x0C03, 0, NULL)      # ingress proof continuity
hci_reset_cmd_handler(NULL, 0x0C03)    # real vendor Reset handler
llm_cmd_cmp_send(0x0C03, 0x00)         # called by the handler
hci_send_2_host(event)                 # real vendor egress entry
hci_tl_send(msg)                       # real vendor HCI TL event builder
```

Only the terminal `h4tl_write()` function was replaced by a local capture stub so the proof can record the event bytes without requiring a UART/H4 external interface in the Rocket-hosted proof environment.

The captured HCI packet was:

```text
CAPTURED_EVENT_WITH_TYPE=04 0E 04 01 03 0C 00
RESET_CC_BYTES=0E 04 01 03 0C 00
```

`LINUX_RX_REAL_EVENT=PASS` records that the emitted packet is in the exact Linux driver event layout consumed by `ceva_bt_rx_work()`: packet type `0x04`, event code `0x0E`, parameter length `0x04`, command-credit byte, opcode `0x0C03`, and status `0x00`.

## Synthetic Disabled

```text
SYNTHETIC_DISABLED=PASS
```

Basis:

```text
scripts/check_ceva_sidecar_no_synthetic_event.sh passes through the Phase3 completion gate.
linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c keeps phase25_selftest=false by default.
The proof used vendor hci_send_2_host()/hci_tl_send() and did not use Phase2.5 synthetic responses.
```

## Commands

```bash
cd /root/chipyard/fpga
pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 220 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_reset_handler_event_patch.gdb

pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 300 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_reset_handler_event_patch.gdb
```

## Key Log

```text
[phase3-04h-reset] hit-reset-handler-event-done pc=0x000000008F02C84C
[phase3-04h-reset] SIDECAR_POST_RWIP_INIT@+0x18=0x53494445504F5354 expected=0x53494445504F5354
[phase3-04h-reset] SIDECAR_POST_RWIP_DRIVER_INIT@+0x20=0x5349444544524956 expected=0x5349444544524956
[phase3-04h-reset] SIDECAR_INGRESS_READY@+0x28=0x53494445494E4752 expected=0x53494445494E4752
[phase3-04h-reset] SIDECAR_RX_CMD_0C03@+0x30=0x5258304330332121 expected=0x5258304330332121
[phase3-04h-reset] SIDECAR_CMD_CONSUMED@+0x38=0x434D44434F4E5321 expected=0x434D44434F4E5321
[phase3-04h-reset] SIDECAR_EGRESS_EVENT_READY@+0x40=0x4556545244592121 expected=0x4556545244592121
[phase3-04h-reset] SIDECAR_HCI_SEND_2_HOST@+0x48=0x48434932484F5354 expected=0x48434932484F5354
[phase3-04h-reset] SIDECAR_REAL_RESET_PASS@+0x58=0x5253545041535321 expected=0x5253545041535321
[phase3-04h-reset] CAPTURED_EVENT_WITH_TYPE=04 0E 04 01 03 0C 00
[phase3-04h-reset] RESET_CC_BYTES=0E 04 01 03 0C 00
[phase3-04h-reset] PHASE3_REAL_RESET_EVENT=PASS
```

## Artifacts

```text
ed75e953680f08a11b26f0cc4aace4fcb60550d07bec059b4d7d7470f3fb013e  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.elf
732f95a190d1f1189ec395783676c9f91cddcaf8425556a0ce5485eb00266d62  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin
1be0a25c697fc75451ddfc7b6a312a2b990856c5920aabd6640e2903d220db40  /tmp/ceva_phase3_vendor_rv64_probe/phase3_h4tl_capture_stub.bin
ec86cabc2f5b98bd28e77b015ba40d54d7e7fe72ac126d3fa5316660e5ee0abb  /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_reset_handler_event.bin
8342348ee95241eeb3426ba61b629c08afc91b18a5d5feb8e2142fe400c7a677  /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_reset_handler_event_patch_r2.log
5da7108f1086c9a8f7e83b5f447a4c7827cc8cbd202a72d2408787843dd12515  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_reset_handler_event_patch_r2.log
156b9d6364773ddd9b6eb9b3bca841675eea8a02e3f8dd199be53edbda8052eb  /tmp/ceva_phase3_vendor_rv64_probe/phase3_reset_handler_event_markers.bin
```

## Result

```text
PHASE3_REAL_RESET_EVENT=PASS
SYNTHETIC_DISABLED=PASS
RESET_CC_BYTES=0E 04 01 03 0C 00
LINUX_RX_REAL_EVENT=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```
