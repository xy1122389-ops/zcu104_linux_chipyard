# Phase3 Evidence 03: Real HCI Reset Ingress Consumed

Status: local Rocket-executed vendor runtime proof.
Date: 2026-05-13 local J-Link run.

```text
PHASE3_REAL_INGRESS_CONSUMED=PASS
SYNTHETIC_DISABLED=PASS
HCI_RESET_CMD=03 0C 00
SIDECAR_CMD_CONSUMED=0x434D44434F4E5321
```

## Scope

This evidence proves that the locally linked CEVA BT5.2 vendor runtime can consume a real HCI Reset command through the vendor ingress function `hci_cmd_received(0x0C03, 0, NULL)` after the evidence-02 `rwip_init()` and `rwip_driver_init()` marker chain has completed.

The current CEVA RTL integrated in this bitstream exposes the CEVA register and EM windows but does not expose an internal CEVA firmware CPU/code RAM execution context. For that reason this proof uses the local RV64 Rocket-executable vendor runtime probe under `/tmp/ceva_phase3_vendor_rv64_probe`, not the RV32 `fw.bin` running inside a CEVA-internal CPU.

This is evidence 03 only. It proves real vendor ingress call/return for HCI Reset, with synthetic responder disabled. It does not claim Reset Command Complete event egress, Linux HCI RX delivery, Read Local Version response, repeated regression, BlueZ bringup, or Phase3 completion.

## Vendor Ingress Used

Local source inspection found the real CEVA ingress function and a vendor Reset call path:

```text
/tmp/ceva_phase3_vendor_rv64_probe/sw/src/ip/hci/src/hci_tl.c:1574 hci_cmd_received(uint16_t opcode, uint8_t length, uint8_t *payload)
/tmp/ceva_phase3_vendor_rv64_probe/sw/src/modules/h4tl/src/h4tl.c:430 hci_cmd_received(HCI_RESET_CMD_OPCODE, 0, NULL)
```

The proof patch calls the linked vendor symbol directly at `0x8f09af9a` with:

```text
a0 = 0x0c03
a1 = 0
a2 = 0
```

The byte-level HCI command represented by that call is:

```text
HCI_RESET_CMD=03 0C 00
```

## Execution Shape

The proof image is the same local RV64 vendor runtime build used for evidence 02. The run starts from the vendor reset handler so the vendor C runtime initializes `.sbss`, `.bss`, `.stack`, and `.data`.

The temporary proof patch then:

```text
1. calls __wrap_rwip_init()
2. observes SIDECAR_POST_RWIP_INIT
3. observes SIDECAR_POST_RWIP_DRIVER_INIT
4. writes SIDECAR_INGRESS_READY
5. writes SIDECAR_RX_CMD_0C03
6. calls real hci_cmd_received(0x0C03, 0, NULL)
7. writes SIDECAR_CMD_CONSUMED only after hci_cmd_received returns
8. stops at the ingress done breakpoint
```

Temporary proof-only return stubs were applied to board/platform initializers that block in the Rocket-hosted environment before this bitstream has a CEVA-internal firmware execution context:

```text
dbg_init              0x8f02470a
rf_init               0x8f026bf6
display_add_config    0x8f020220
display_init          0x8f02bfe8
ecc_init              0x8f02b154
h4tl_init             0x8f02bd0a
rwbt_init             0x8f02f16a
rwip_reset            0x8f020aba
```

The proof did not stub `rwip_init()`, `rwip_driver_init()`, or `hci_cmd_received()`.

## Synthetic Disabled

The synthetic responder path remains disabled for Phase3 ingress evidence:

```text
SYNTHETIC_DISABLED=PASS
```

Basis:

```text
scripts/check_ceva_sidecar_no_synthetic_event.sh passes through the Phase3 completion gate.
linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c keeps phase25_selftest=false by default.
This proof used the vendor ingress function directly, not the Phase2.5 synthetic responder.
```

## Commands

```bash
cd /root/chipyard/fpga
pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 220 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_ingress_patch.gdb

pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 300 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_ingress_patch.gdb
```

## Key Log

Restore log:

```text
[phase3-03-restore] target=127.0.0.1:3333
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_zero_markers.bin into memory (0x8f010000 to 0x8f010090)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin into memory (0x8f020000 to 0x8f0b0fa8)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_ingress.bin into memory (0x8f02c75c to 0x8f02c84c)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02470a to 0x8f02470e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f026bf6 to 0x8f026bfa)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f020220 to 0x8f020224)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02bfe8 to 0x8f02bfec)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02b154 to 0x8f02b158)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02bd0a to 0x8f02bd0e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02f16a to 0x8f02f16e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f020aba to 0x8f020abe)
[phase3-03-restore] RESTORE_INGRESS_PATCH_DONE=PASS
```

Run log:

```text
[phase3-03-ingress] target=127.0.0.1:3333
Hardware assisted breakpoint 1 at 0x8f02c848
$1 = 0x8f020094
[phase3-03-ingress] continue reset_handler=0x8f020094 to ingress_done=0x8f02c848

Breakpoint 1, 0x000000008f02c848 in ?? ()
[phase3-03-ingress] hit-ingress-done pc=0x000000008F02C848
[phase3-03-ingress] PATCH_PRE_RWIP@+0x10=0x5052455F52574950 expected=0x5052455F52574950
[phase3-03-ingress] SIDECAR_POST_RWIP_INIT@+0x18=0x53494445504F5354 expected=0x53494445504F5354
[phase3-03-ingress] SIDECAR_POST_RWIP_DRIVER_INIT@+0x20=0x5349444544524956 expected=0x5349444544524956
[phase3-03-ingress] SIDECAR_INGRESS_READY@+0x28=0x53494445494E4752 expected=0x53494445494E4752
[phase3-03-ingress] SIDECAR_RX_CMD_0C03@+0x30=0x5258304330332121 expected=0x5258304330332121
[phase3-03-ingress] SIDECAR_CMD_CONSUMED@+0x38=0x434D44434F4E5321 expected=0x434D44434F4E5321
[phase3-03-ingress] PHASE3_REAL_INGRESS_CONSUMED=PASS
```

## Artifacts

```text
ed75e953680f08a11b26f0cc4aace4fcb60550d07bec059b4d7d7470f3fb013e  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.elf
732f95a190d1f1189ec395783676c9f91cddcaf8425556a0ce5485eb00266d62  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin
e0855c210d90ebe76c1f11b502320592a56246a184e40b732f2e28b457a3cc7c  /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_ingress.bin
4e8fbb4715c05fadf82f24986b5df1fcb855235807f130c0981c52a5c49e0ab0  /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin
826cdd2fb2731f0df2f3e192ee496941c6d011d7b79b1857628e3bdf93e02570  /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_ingress_patch.log
6929f42b1f831eea24983f103252b8d0f8cbe8b106feca7aaf80a85af827e11f  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_ingress_patch.log
5f423ff37c75fb6dc9aeb2b3526a54207af22fb9806f8d9fbdea0b03c92b697a  /tmp/ceva_phase3_vendor_rv64_probe/phase3_ingress_markers.bin
```

## Result

```text
PHASE3_REAL_INGRESS_CONSUMED=PASS
SYNTHETIC_DISABLED=PASS
HCI_RESET_CMD=03 0C 00
SIDECAR_CMD_CONSUMED=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```
