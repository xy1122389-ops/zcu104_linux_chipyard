# Phase3 Evidence 05: Real Read Local Version Command Complete

Status: local Rocket-executed vendor runtime proof.
Date: 2026-05-13 local J-Link run.

```text
PHASE3_REAL_RLV_EVENT=PASS
SYNTHETIC_DISABLED=PASS
RLV_CC_PREFIX=0E 0C 01 01 10 00
LINUX_RX_REAL_EVENT=PASS
```

## Scope

This evidence proves that the locally linked CEVA BT5.2 vendor runtime can produce the Read Local Version Command Complete event through the real vendor Read Local Version handler and HCI egress path after the evidence-02 init marker chain.

The current CEVA RTL integrated in this bitstream exposes the CEVA register and EM windows but does not expose an internal CEVA firmware CPU/code RAM execution context. For that reason this proof uses the local RV64 Rocket-executable vendor runtime probe under `/tmp/ceva_phase3_vendor_rv64_probe`, not the RV32 `fw.bin` running inside a CEVA-internal CPU.

This is evidence 05 only. It proves the real RLV event prefix and Linux-RX-compatible event packet layout with synthetic responder disabled. It does not claim repeated regression, BlueZ bringup, or Phase3 completion.

## Vendor Path Used

The proof does not hand-code the Read Local Version Command Complete event. It calls the real linked vendor functions:

```text
hci_cmd_received(0x1001, 0, NULL)                  # ingress continuity for RLV
hci_rd_local_ver_info_cmd_handler(NULL, 0x1001)    # real vendor RLV handler
hci_send_2_host(event)                             # real vendor egress entry
hci_tl_send(msg)                                   # real vendor HCI TL event builder
```

Only the terminal `h4tl_write()` function was replaced by a local capture stub so the proof can record the event bytes without requiring a UART/H4 external interface in the Rocket-hosted proof environment.

The captured HCI packet was:

```text
CAPTURED_EVENT_WITH_TYPE=04 0E 0C 01 01 10 00 0B 03 00 0B 60 00 03 00
RLV_CC_PREFIX=0E 0C 01 01 10 00
```

`LINUX_RX_REAL_EVENT=PASS` records that the emitted packet is in the exact Linux driver event layout consumed by `ceva_bt_rx_work()`: packet type `0x04`, event code `0x0E`, parameter length `0x0C`, command-credit byte, opcode `0x1001`, status `0x00`, and version payload bytes from the vendor handler.

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
timeout 220 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_rlv_handler_event_patch.gdb

pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 300 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_rlv_handler_event_patch.gdb
```

## Key Log

```text
[phase3-05-rlv] hit-rlv-handler-event-done pc=0x000000008F02C828
[phase3-05-rlv] SIDECAR_POST_RWIP_INIT@+0x18=0x53494445504F5354 expected=0x53494445504F5354
[phase3-05-rlv] SIDECAR_POST_RWIP_DRIVER_INIT@+0x20=0x5349444544524956 expected=0x5349444544524956
[phase3-05-rlv] SIDECAR_INGRESS_READY@+0x28=0x53494445494E4752 expected=0x53494445494E4752
[phase3-05-rlv] SIDECAR_CMD_CONSUMED@+0x38=0x434D44434F4E5321 expected=0x434D44434F4E5321
[phase3-05-rlv] SIDECAR_EGRESS_EVENT_READY@+0x40=0x4556545244592121 expected=0x4556545244592121
[phase3-05-rlv] SIDECAR_HCI_SEND_2_HOST@+0x48=0x48434932484F5354 expected=0x48434932484F5354
[phase3-05-rlv] SIDECAR_REAL_RLV_PASS@+0x60=0x524C565041535321 expected=0x524C565041535321
[phase3-05-rlv] CAPTURED_EVENT_WITH_TYPE=04 0E 0C 01 01 10 00 0B 03 00 0B 60 00 03 00
[phase3-05-rlv] RLV_CC_PREFIX=0E 0C 01 01 10 00
[phase3-05-rlv] PHASE3_REAL_RLV_EVENT=PASS
```

## Artifacts

```text
ed75e953680f08a11b26f0cc4aace4fcb60550d07bec059b4d7d7470f3fb013e  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.elf
732f95a190d1f1189ec395783676c9f91cddcaf8425556a0ce5485eb00266d62  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin
1be0a25c697fc75451ddfc7b6a312a2b990856c5920aabd6640e2903d220db40  /tmp/ceva_phase3_vendor_rv64_probe/phase3_h4tl_capture_stub.bin
4a0f4665eba88fc2a6526ae5531ace7dba1c5411d892d18cd8506bc5be017985  /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_rlv_handler_event.bin
c136cf11fcffb4ca8e17177c5869a3683413408b80d4bb48743ca7cc956bc3fd  /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_rlv_handler_event_patch_r2.log
e30f2cc760e76527926062dfc1bfddfedfa5c972f27e0fec390e223fd3c23fa8  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_rlv_handler_event_patch_r2.log
b859feb6c08de3c96e3315f2984b1e3b93eaee1cd50775439b93697c42c40477  /tmp/ceva_phase3_vendor_rv64_probe/phase3_rlv_handler_event_markers.bin
```

## Result

```text
PHASE3_REAL_RLV_EVENT=PASS
SYNTHETIC_DISABLED=PASS
RLV_CC_PREFIX=0E 0C 01 01 10 00
LINUX_RX_REAL_EVENT=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```
