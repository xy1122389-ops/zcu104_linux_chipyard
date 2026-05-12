# CEVA BT5.2 Phase 2.5 Difficulties And Lessons - 2026-05-12

## Final rerun result

- Final rerun log: `logs/phase25_rerun_20260512_140511/run.log`
- This rerun was executed with the fixed constraints used throughout this phase: `SKIP_DDR_INIT=1`, `JLINK_HOST=127.0.0.1`, `JLINK_PORT=3333`, `KERNEL_RUN_SECS=120`.
- Driver-side PASS markers present in the rerun log:
  - `CEVA_PHASE25_HCI_RESET_PASS`
  - `CEVA_PHASE25_READ_LOCAL_VERSION_PASS`
  - `CEVA_PHASE25_SELFTEST_PASS`
- Userspace PASS markers present in the rerun log:
  - `PHASE25_USER_HCI_RESET_PASS`
  - `PHASE25_USER_HCI_RLV_PASS`
  - `PHASE25_USER_SMOKE_PASS`
- Init-flow breadcrumbs present in the rerun log:
  - `PHASE25_AFTER_HCI_WAIT result=present`
  - `PHASE25_AFTER_SMOKE_EXEC rc=0`
- No `Oops`, `Segmentation fault`, `Unable to handle kernel paging request`, `Network is down`, or `File descriptor in bad state` markers appear in the final rerun log.
- One residual warning remains in the generic phase-2 hardware summary:
  - `CHECK 2: BT_RWBTCNTL bit8 CLEAR - FAIL/WARN (driver open not called)`
- This warning is not a phase2.5 stop condition in the final successful run, because the same log also contains:
  - `ceva_bt_open: initializing hardware`
  - `BT core running (CLKN 5/5 OK)`
  - `ceva_bt_open: OK`
  - full driver-side and userspace-side phase2.5 PASS evidence.

## Scope and non-negotiable constraints during this phase

- Do not modify RTL.
- Do not rebuild or change the bitstream for phase2.5 validation.
- Stop adding new markers or evidence drops into `ceva_bt52.c` once enough observability existed.
- Keep validation inside the Linux/initramfs/userspace path unless a software-only path is exhausted.
- Keep the J-Link path fixed at `127.0.0.1:3333`.
- Keep the run path on the existing ZCU104/J100-only flow.

## What phase2.5 actually needed to prove

- The target was not merely “driver probe passes”.
- The target was not merely “driver-side selftest PASS”.
- The target was: from initramfs userspace, directly operate on `hci0` and complete at least:
  - `HCI Reset`
  - `Read Local Version`
- A valid success condition therefore required both sides simultaneously:
  - driver-side CEVA phase2.5 responder markers clean
  - userspace smoke actually receiving `Command Complete` and printing PASS.

## Main blocker chain and how each one was resolved

| Stage | Run / evidence anchor | Symptom | Actual cause | Resolution |
| --- | --- | --- | --- | --- |
| 1 | payload rebuild path before latest reruns | `rebuild_payload.sh` could fail around in-tree BT/crypto modules | `crypto/ecc`, `crypto/ecdh_generic`, and `net/bluetooth/bluetooth` are config-dependent; current kernel had them built-in, but the script treated them as unconditional module targets | `rebuild_payload.sh` was fixed to build/copy these only when `.config` says `=m`, otherwise log `builtin-or-absent` |
| 2 | `phase25_smoke_probe_20260512_120443` | userspace stalled around `PHASE25_USER_STEP_HCIDEVUP` | The smoke path assumed `HCIDEVUP` was part of the minimal proof, but the real goal was direct command send/receive on `hci0` | Stop treating `HCIDEVUP` as mandatory for this validation path |
| 3 | `phase25_skip_hcidevup_ioctl_20260512_121420` | removing the ioctl was still not enough; execution stayed stuck on the wait path | `wait_until_hci_up()` remained a second gate that still blocked progress | Remove the hot-path dependency on waiting for `HCI_UP` |
| 4 | `logs/phase25_direct_bind_20260512_122233/run.log` | direct RAW bind/send reached `PHASE25_USER_STEP_HCI_RESET` but `send()` failed with `errno=100 (Network is down)` | RAW HCI socket send is gated by BlueZ core state; in this state the device was not considered `HCI_UP` for RAW send semantics | Stop assuming RAW is the only valid validation socket when the device is running but not fully UP |
| 5 | `phase25_selftest_on_20260512_123511` | driver side showed contradictory FAIL/PASS results after enabling selftest | Early selftest response injection at probe/open time was too early and did not reflect the real command path; it created confusing evidence | Move selftest behavior away from probe/open pre-injection and onto real opcode handling in `send_frame` |
| 6 | `phase25_min_hci_init_20260512_124719` and `phase25_local_cmds_fix_20260512_125515` | Bluetooth core init advanced, but synthetic replies still broke on specific opcodes | The driver responder was missing some core init responses and had packet length errors | Fill in the required synthetic `Command Complete` replies for init commands and fix packet formatting/length |
| 7 | `phase25_local_name_fix_20260512_131354` | driver side became clean, but userspace still did not finish the smoke pass | The driver was now capable of responding, but userspace receive-side behavior was still incorrect | Shift the debug focus from driver responder coverage to socket semantics and userspace receive behavior |
| 8 | `logs/phase25_send_wait_probe_20260512_132308/run.log` | proof advanced to `AFTER_SEND` and `WAIT_RESULT`, but never reached `POLL_READY` | The command was no longer failing before send; the blocker moved to userspace event recovery after send | Confirmed that the next fix surface was recv-path semantics, not driver init reachability |
| 9 | `logs/phase25_mmio_confirm_20260512_133425/run.log` | smoke crashed with `PHASE25_AFTER_SMOKE_EXEC rc=139`, `Unable to handle kernel paging request`, `Segmentation fault` | The `/dev/mem` MMIO clear/write path used to reset phase2.5 event shadow from userspace was unsafe on this kernel/platform | Remove the `/dev/mem` write-based validation path entirely |
| 10 | `logs/phase25_user_channel_20260512_134359/run.log` | binding `HCI_CHANNEL_USER` succeeded, but `setsockopt(HCI_FILTER)` failed with `errno=77 (File descriptor in bad state)` | USER channel does not support RAW-channel socket options like `HCI_FILTER` | Update userspace smoke to skip `HCI_FILTER` on USER channel |
| 11 | `logs/phase25_user_channel_v2_20260512_135329/run.log` | userspace finally reached recv PASS | The correct phase2.5 socket model is USER channel plus userspace-side opcode filtering | Keep H4 packet type prefix on send, skip `HCI_FILTER`, filter `CMD_COMPLETE`/`CMD_STATUS` in userspace |
| 12 | `logs/phase25_rerun_20260512_140511/run.log` | clean rerun confirmed the path is reproducible | Final software-only validation path is stable under the fixed constraints | Phase2.5 considered complete |

## The most important technical pivots

### 1. Payload rebuild had to become config-aware

- `rebuild_payload.sh` must treat `crypto/ecc.ko`, `crypto/ecdh_generic.ko`, and `net/bluetooth/bluetooth.ko` as config-dependent artifacts.
- When the kernel has `CONFIG_BT=y`, `CONFIG_CRYPTO_ECC=y`, and `CONFIG_CRYPTO_ECDH=y`, forcing these as `.ko` targets causes modpost/module failures.
- Correct pattern:
  - append in-tree module targets only when the matching config entry is `=m`
  - copy a `.ko` into initramfs only if the file exists
  - otherwise log `builtin-or-absent`
- This was required before any later phase2.5 validation could be trusted.

### 2. The real blocker moved from “bring hci0 up” to “what channel semantics are valid now”

- Early in the session, the smoke logic assumed that `HCIDEVUP` and `wait_until_hci_up()` were part of the minimum viable path.
- That assumption was wrong for this phase.
- The real need was to issue direct HCI commands as soon as the device was usable enough, even if the device was not yet flagged `HCI_UP` in the way RAW sockets require.

### 3. Driver-side selftest must answer real commands, not invent early fake success

- Probe/open-time “pre-injected” selftest responses were misleading.
- They created mixed evidence such as FAIL and PASS appearing in the same run.
- The right place for phase2.5 responder logic was the real outbound command path.
- Once responder behavior moved onto real opcode observation, debugging became coherent again.

### 4. Userspace and driver were blocked on different layers

- After the synthetic response coverage improved, driver-side evidence turned clean before userspace passed.
- That distinction mattered.
- A clean driver-side `CEVA_PHASE25_*_PASS` set did not automatically mean the socket validation path was correct.
- The decisive next step was therefore socket semantics, not more responder markers.

### 5. `/dev/mem` looked attractive as a confirmation path but was the wrong direction

- The idea was to clear/read CEVA event shadow directly from userspace to confirm whether events existed even when recv stalled.
- In practice this caused a kernel paging fault and userspace `SIGSEGV`.
- For this phase, `/dev/mem` writes into the CEVA MMIO/event-shadow area are not a safe observability tool.
- This path should be considered a known bad detour for phase2.5 work.

### 6. USER channel was the correct answer, but only with USER-channel semantics

- `HCIGETDEVINFO` showing `flags=0x00000004` was the key signal.
- In that window the device is running enough to use USER channel, but not ready for RAW socket assumptions.
- Binding `HCI_CHANNEL_USER` was necessary.
- But USER channel is not “RAW channel with a different bind value”.
- Kernel rule from `net/bluetooth/hci_sock.c`:
  - `HCI_FILTER`, `HCI_DATA_DIR`, and `HCI_TIME_STAMP` are only valid on `HCI_CHANNEL_RAW`
  - applying `HCI_FILTER` to USER channel returns `-EBADFD` / `errno=77`
- Final working userspace pattern:
  - bind USER channel when `hci0` is not `HCI_UP`
  - keep the H4 packet-type prefix on send (`HCI_COMMAND_PKT`)
  - skip `HCI_FILTER` on USER channel
  - filter `CMD_COMPLETE` / `CMD_STATUS` by opcode in userspace after recv/poll

## Exact failure anchors worth remembering

### Raw direct-bind failure

- Log: `logs/phase25_direct_bind_20260512_122233/run.log`
- Important evidence:
  - `PHASE25_USER_IOCTL_HCIGETDEVINFO name=hci0 flags=0x00000206 type=0`
  - `PHASE25_USER_HCI_RESET_SEND rc=-1 errno=100 (Network is down) opcode=0x0c03`
  - `PHASE25_USER_HCI_RESET_FAIL`
- Meaning:
  - the path had progressed far enough to attempt the send
  - the problem was no longer device discovery
  - the problem was channel/state semantics.

### Send-after success but no event delivery yet

- Log: `logs/phase25_send_wait_probe_20260512_132308/run.log`
- Important evidence:
  - `PHASE25_USER_CMD_0c03_AFTER_SEND`
  - `PHASE25_USER_CMD_0c03_WAIT_RESULT`
- What mattered was not only what appeared, but also what did not appear:
  - no `PHASE25_USER_CMD_0c03_POLL_READY`
  - no `PHASE25_USER_HCI_RESET_PASS`
- Meaning:
  - command transmission had moved forward
  - the remaining bug sat in the event recovery path.

### MMIO-confirm detour crash

- Log: `logs/phase25_mmio_confirm_20260512_133425/run.log`
- Important evidence:
  - `PHASE25_USER_CMD_0c03_FILTER_OK`
  - `PHASE25_AFTER_SMOKE_EXEC rc=139`
  - `Unable to handle kernel paging request at virtual address ffffffd7e501018080`
  - `Segmentation fault`
- Meaning:
  - the crash happened before the expected send-probe progression
  - the newly added `/dev/mem` clear/write path itself was the failure source.

### USER channel first try still failed because it was configured like RAW

- Log: `logs/phase25_user_channel_20260512_134359/run.log`
- Important evidence:
  - `PHASE25_USER_BIND_CHANNEL_USER`
  - `PHASE25_USER_BIND rc=0 errno=0 (OK)`
  - `PHASE25_USER_SETSOCKOPT rc=-1 errno=77 (File descriptor in bad state)`
  - `PHASE25_USER_HCI_RESET_FAIL`
- Meaning:
  - selecting USER channel was correct
  - but the socket was still being used with RAW-channel rules.

### Final stable path

- Logs:
  - `logs/phase25_user_channel_v2_20260512_135329/run.log`
  - `logs/phase25_rerun_20260512_140511/run.log`
- Important evidence from the final rerun:
  - `PHASE25_USER_HCI_RESET_PASS`
  - `PHASE25_USER_HCI_RLV_PASS`
  - `PHASE25_USER_SMOKE_PASS`
  - `CEVA_PHASE25_HCI_RESET_PASS`
  - `CEVA_PHASE25_READ_LOCAL_VERSION_PASS`
  - `CEVA_PHASE25_SELFTEST_PASS`
  - `PHASE25_AFTER_HCI_WAIT result=present`
  - `PHASE25_AFTER_SMOKE_EXEC rc=0`

## What not to do next time

- Do not reopen the RTL/bitstream path when the failure is clearly inside Linux socket semantics.
- Do not keep adding markers to `ceva_bt52.c` once the driver already proves probe/open/send-frame progress.
- Do not assume `driver-side PASS` means `userspace path PASS`.
- Do not assume USER channel accepts RAW-channel `setsockopt` behavior.
- Do not use `/dev/mem` writes as the default confirmation mechanism for CEVA EM phase2.5 event shadow.
- Do not use `HCIDEVUP` or `wait_until_hci_up()` as mandatory gates for this specific userspace smoke proof.
- Do not interpret the generic `BT_RWBTCNTL bit8 CLEAR` warning in isolation when richer evidence shows `ceva_bt_open: OK` and both driver/userspace phase2.5 PASS.

## What to do first next time

- Reuse the current stable validation path before attempting any deeper changes.
- Re-run with:

```bash
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"
cd /root/chipyard/fpga
RUN_TAG="phase25_rerun_$(date +%Y%m%d_%H%M%S)"
mkdir -p "logs/$RUN_TAG"
env SKIP_DDR_INIT=1 JLINK_HOST=127.0.0.1 JLINK_PORT=3333 KERNEL_RUN_SECS=120 RUN_TAG="$RUN_TAG" bash run_phase2_ceva_bt_linux.sh 2>&1 | tee "logs/$RUN_TAG/run.log"
```

- First inspect these markers before changing any code:
  - `PHASE25_USER_HCI_RESET_PASS`
  - `PHASE25_USER_HCI_RLV_PASS`
  - `PHASE25_USER_SMOKE_PASS`
  - `CEVA_PHASE25_HCI_RESET_PASS`
  - `CEVA_PHASE25_READ_LOCAL_VERSION_PASS`
  - `CEVA_PHASE25_SELFTEST_PASS`
- If those exist together, phase2.5 is still healthy.

## Short operational checklist

- J-Link endpoint must remain `127.0.0.1:3333`.
- Prefer guarded J-Link precheck before the boot run.
- Keep `SKIP_DDR_INIT=1` only when the board is already in the expected programmed state.
- Treat initramfs module sync as config-aware.
- For userspace smoke:
  - inspect `HCIGETDEVINFO flags`
  - if not `HCI_UP`, prefer `HCI_CHANNEL_USER`
  - skip `HCI_FILTER` on USER channel
  - keep H4 packet type on outbound command buffer
  - do recv-side opcode filtering in userspace.

## Bottom line

- The decisive phase2.5 breakthrough was not a new RTL change, not a new bitstream, and not more driver markers.
- The decisive breakthrough was correcting the Linux userspace validation strategy to match BlueZ HCI socket semantics for the actual device state.
- Final proven recipe:
  - config-aware payload rebuild
  - real-opcode driver responder
  - no `/dev/mem` shadow writes
  - USER channel when `hci0` is running but not fully UP
  - no `HCI_FILTER` on USER channel
  - userspace recv confirmation by opcode.
