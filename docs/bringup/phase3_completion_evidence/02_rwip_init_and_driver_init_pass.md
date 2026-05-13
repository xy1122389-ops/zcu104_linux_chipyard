# Phase3 Evidence 02: rwip_init and rwip_driver_init Marker Chain Pass

Status: local Rocket-executed vendor runtime proof.
Date: 2026-05-13 local J-Link run.

```text
PHASE3_RWIP_INIT=PASS
PHASE3_RWIP_DRIVER_INIT=PASS
SIDECAR_POST_RWIP_INIT=0x53494445504F5354
SIDECAR_POST_RWIP_DRIVER_INIT=0x5349444544524956
```

## Scope

This evidence proves that the locally linked CEVA BT5.2 vendor runtime can execute the `rwip_init()` and `rwip_driver_init()` call chain far enough to write the Phase3 post-init markers on the ZCU104 Rocket target.

The current CEVA RTL integrated in this bitstream exposes the CEVA register and EM windows but does not expose an internal CEVA firmware CPU/code RAM execution context. For that reason this proof uses the local RV64 Rocket-executable vendor runtime probe under `/tmp/ceva_phase3_vendor_rv64_probe`, not the RV32 `fw.bin` running inside a CEVA-internal CPU.

This is evidence 02 only. It does not claim real HCI Reset/RLV ingress consumption, real vendor HCI event egress, Linux HCI RX delivery, synthetic-off repeated regression, BlueZ bringup, or Phase3 completion.

## Execution Shape

The proof image is the local RV64 vendor runtime build with linker wrappers around:

```text
__wrap_rwip_init
__wrap_rwip_driver_init
```

The run starts from the vendor reset handler so the vendor C runtime initializes `.sbss`, `.bss`, `.stack`, and `.data`. The temporary proof patch then calls `__wrap_rwip_init()` from `main` and stops at the patch done label after the wrapper returns.

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

The proof did not stub `rwip_init()` or `rwip_driver_init()`. The driver marker was observed after the wrapped `rwip_driver_init()` path, and the init marker was observed after `__wrap_rwip_init()` returned.

## Commands

```bash
cd /root/chipyard/fpga
pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 220 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_main_patch.gdb

pkill -9 riscv64-unknown-elf-gdb || true
JLINK_FORCE_RESTART=1 bash scripts/start_jlink_server.sh
timeout 300 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -q -batch -x /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_patched_main_rwip.gdb
```

## Key Log

Restore log:

```text
[phase3-02-patch-restore] target=127.0.0.1:3333
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_zero_markers.bin into memory (0x8f010000 to 0x8f010090)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin into memory (0x8f020000 to 0x8f0b0fa8)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_instrumented.bin into memory (0x8f02c75c to 0x8f02c7c4)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02470a to 0x8f02470e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f026bf6 to 0x8f026bfa)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f020220 to 0x8f020224)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02bfe8 to 0x8f02bfec)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02b154 to 0x8f02b158)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02bd0a to 0x8f02bd0e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f02f16a to 0x8f02f16e)
Restoring binary file /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin into memory (0x8f020aba to 0x8f020abe)
[phase3-02-patch-restore] RESTORE_PATCH_DONE=PASS
```

Run log:

```text
[phase3-02-patched] target=127.0.0.1:3333
Hardware assisted breakpoint 1 at 0x8f02c7c0
$1 = 0x8f020094
Program stopped at 0x8000b1ca.
[phase3-02-patched] continue reset_handler=0x8f020094 to patched_done=0x8f02c7c0

Breakpoint 1, 0x000000008f02c7c0 in ?? ()
[phase3-02-patched] hit-patched-done pc=0x000000008F02C7C0
[phase3-02-patched] PATCH_PRE_RWIP@+0x10=0x5052455F52574950 expected=0x5052455F52574950
[phase3-02-patched] SIDECAR_POST_RWIP_INIT@+0x18=0x53494445504F5354 expected=0x53494445504F5354
[phase3-02-patched] SIDECAR_POST_RWIP_DRIVER_INIT@+0x20=0x5349444544524956 expected=0x5349444544524956
[phase3-02-patched] PATCH_POST_RWIP@+0x28=0x504F535452574950 expected=0x504F535452574950
[phase3-02-patched] PHASE3_RWIP_MARKER_PROBE=PASS
```

## Artifacts

```text
ed75e953680f08a11b26f0cc4aace4fcb60550d07bec059b4d7d7470f3fb013e  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.elf
732f95a190d1f1189ec395783676c9f91cddcaf8425556a0ce5485eb00266d62  /tmp/ceva_phase3_vendor_rv64_probe/build/btdm-bluegrip/fw.bin
468e4a8d5a071c6a8e2f93c34efc774a6d58f7399b3360b659e02c574a4684d6  /tmp/ceva_phase3_vendor_rv64_probe/phase3_main_patch_instrumented.bin
4e8fbb4715c05fadf82f24986b5df1fcb855235807f130c0981c52a5c49e0ab0  /tmp/ceva_phase3_vendor_rv64_probe/phase3_ret_stub.bin
0ac5088a7daa7eaac396173a29517815c34d1381f830d758cb45bf30a46dc6fe  /tmp/ceva_phase3_vendor_rv64_probe/phase3_restore_image_with_main_patch.log
a4718ddf1fec3a4ef89f14b60f03e2a2e87ef8a8a58ed564ddd554f64a6204ab  /tmp/ceva_phase3_vendor_rv64_probe/phase3_run_patched_main_rwip.log
71d5275b0adb6fbf4567ca41dd99d3093810b30ec052fdb527e2f4f30f3880fb  /tmp/ceva_phase3_vendor_rv64_probe/phase3_rwip_post_markers.bin
```

## Result

```text
PHASE3_RWIP_INIT=PASS
PHASE3_RWIP_DRIVER_INIT=PASS
SIDECAR_POST_RWIP_INIT=PASS
SIDECAR_POST_RWIP_DRIVER_INIT=PASS
PHASE3_RWIP_MARKER_PROBE=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```