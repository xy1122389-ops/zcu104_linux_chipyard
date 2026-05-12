# CEVA BT5.2 Phase 2.5 Runbook - 2026-05-12

## Phase 2.5 one-line goal

From initramfs userspace, directly operate on `hci0`, issue `HCI Reset` and `Read Local Version`, and receive `Command Complete` for both commands.

## Replay command

```bash
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"
cd /root/chipyard/fpga
RUN_TAG="phase25_rerun_$(date +%Y%m%d_%H%M%S)"
mkdir -p "logs/$RUN_TAG"
env SKIP_DDR_INIT=1 JLINK_HOST=127.0.0.1 JLINK_PORT=3333 KERNEL_RUN_SECS=120 RUN_TAG="$RUN_TAG" bash run_phase2_ceva_bt_linux.sh 2>&1 | tee "logs/$RUN_TAG/run.log"
```

## PASS criteria

The run is Phase 2.5 PASS only if the log contains all of these:

- `PHASE25_USER_HCI_RESET_PASS`
- `PHASE25_USER_HCI_RLV_PASS`
- `PHASE25_USER_SMOKE_PASS`
- `CEVA_PHASE25_HCI_RESET_PASS`
- `CEVA_PHASE25_READ_LOCAL_VERSION_PASS`
- `CEVA_PHASE25_SELFTEST_PASS`

Known-good final reference log:

- `logs/phase25_rerun_20260512_140511/run.log`

## First failure checks

Check in this order:

1. J-Link on `127.0.0.1:3333` can still halt the target.
2. `fw_payload.bin` was rebuilt from the expected kernel/initramfs payload.
3. initramfs still contains `phase25_user_hci_smoke`.
4. `hci0` appears in the boot log.
5. userspace smoke bound `HCI_CHANNEL_USER` when `hci0` is running but not fully `HCI_UP`.
6. USER channel path did not wrongly call `HCI_FILTER`.
7. The log does not show `Network is down` / `errno=100`.
8. The log does not show `errno=77` / `File descriptor in bad state`.
9. The log does not show `Oops` / `Segmentation fault`.

## Core lessons

- `HCI_CHANNEL_USER` is not `HCI_CHANNEL_RAW`.
- USER channel does not support `HCI_FILTER`.
- When `hci0` is `HCI_RUNNING` but not `HCI_UP`, prefer USER channel for the minimal smoke.
- Do not treat driver-side PASS as userspace PASS.
- Do not use `/dev/mem` writes to CEVA shadow state as the default validation path.
- Do not re-synthesize or change RTL/bitstream for Phase 2.5.

## Current success boundary

Proven:

- Linux userspace -> `hci0` -> `ceva_bt52` driver -> synthetic `Command Complete` -> userspace receive PASS.

Not proven:

- Real CEVA firmware protocol stack behavior.
- Real RF/VPHY behavior.
- BlueZ scan / pair / connect end-to-end behavior.

## See also

- `docs/bringup/ceva_bt52_phase25_difficulties_and_lessons_20260512.md`
