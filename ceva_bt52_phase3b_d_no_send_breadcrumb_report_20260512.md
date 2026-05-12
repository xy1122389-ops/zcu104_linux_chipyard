# CEVA BT52 Phase 3B-D Breadcrumb Report (2026-05-12)

## Run

- Run tag: phase3b_d4_breadcrumb_selftest_off_20260512_173551
- Run log: logs/phase3b_d4_breadcrumb_selftest_off_20260512_173551/run.log
- Goal: distinguish init/userspace/driver causes for the previous selftest-off no-send classification

## Selftest-Off Status

- DTS bootargs still carried `ceva_phase25_selftest=0` before the run.
- Kernel log showed the token being passed to userspace and init printed `PHASE25_CEVA_SELFTEST_OFF` plus `PHASE25_REALPATH_OBSERVE selftest=0`.
- Driver probe printed `CEVA_PHASE25 selftest disabled`.
- Conclusion: selftest-off was effective in this run.

## Breadcrumb Storage

- Init/userspace persistent breadcrumb slots:
  - PA 0x8F000040 .. 0x8F0000D8
  - written through the `stage_mark` helper with fixed 64-bit slot values
  - launch script clears this range before `monitor go`
  - capture script dumps and decodes every slot
- Driver persistent breadcrumb markers:
  - EM high scratch words at EM+0x1000 / EM+0x4000 / EM+0xFFFC
  - magic: 0x50334244 (`P3BD`)
  - mirrored into EM command/event shadow words EM[68..70] and EM[100..102]
  - launch script clears these words before boot; capture prints decoded driver bits and aux opcode

## Init Layer Result

- `P3BD_INIT_START`, `P3BD_INIT_SELFTEST_OFF`, `P3BD_INSMOD_START`, `P3BD_INSMOD_DONE`, `P3BD_WAIT_HCI0_START`, `P3BD_WAIT_HCI0_FOUND`, `P3BD_USER_SMOKE_START`, and `P3BD_USER_SMOKE_DONE` were all set.
- `P3BD_WAIT_HCI0_TIMEOUT` stayed clear.
- Conclusion: init reached the selftest-off branch, loaded the driver, saw `hci0`, and launched userspace smoke.

## Userspace Layer Result

- klog contained:
  - `PHASE25_USER_SMOKE_START`
  - `PHASE25_USER_SOCKET rc=3 errno=0 (OK)`
  - `PHASE25_USER_IOCTL_HCIGETDEVINFO name=hci0 flags=0x00000206`
  - `PHASE25_USER_BIND rc=-1 errno=16 (Device or resource busy)` on USER channel
  - `PHASE25_USER_BIND rc=0 errno=0 (OK)` on RAW fallback
  - `PHASE25_USER_HCI_RESET_SEND rc=-1 errno=100 (Network is down) opcode=0x0c03`
  - `PHASE25_USER_HCI_RESET_FAIL`
- The fixed-slot userspace breadcrumb entries under 0x8F000088 .. 0x8F0000D8 remained clear in this run, so userspace persistence still depends on klog for now.
- Conclusion: userspace definitely started, opened the socket, attempted USER bind, fell back to RAW successfully, and attempted HCI Reset send.

## Driver Layer Result

- Driver breadcrumbs were present with bits `0x000001FF` and aux `0x00000C03`.
- Decoded driver state:
  - `P3BD_DRV_PROBE_START`: set
  - `P3BD_DRV_HCI_REGISTER_OK`: set
  - `P3BD_DRV_OPEN_START`: set
  - `P3BD_DRV_OPEN_OK`: set
  - `P3BD_DRV_SEND_ENTER`: set
  - `P3BD_DRV_SEND_RESET_SEEN`: set
  - `P3BD_DRV_EM_CMD_WRITTEN`: set
  - `P3BD_DRV_SWINT_TRIGGERED`: set
  - `P3BD_DRV_IRQ_ENTER`: set
  - `P3BD_DRV_EM_EVT_READY`: missing
  - `P3BD_DRV_RX_WORK_ENTER`: missing
  - `P3BD_DRV_HCI_RECV_DONE`: missing
- Conclusion: the path did reach `ceva_bt_send_frame`, recognized opcode 0x0C03, wrote the command into EM, and triggered the software interrupt.

## Hardware/EM Result

- `EM[64] = 0x000C0301` (command buffer written)
- `EM[68] = 0x50334244`, `EM[69] = 0x000001FF`, `EM[70] = 0x00000C03`
- `DM_INTSTAT1 = 0x00000001`
- `BT_RWBTCNTL bit8` was set
- `EM[96..99] = 0x00000000`
- `EM[100] = 0x50334244`, `EM[101] = 0x000001FF`, `EM[102] = 0x00000C03`
- Conclusion: the command and IRQ side are alive, but no event was written back to the EM event buffer.

## Final Classification

- Previous clean classification `no-send` is no longer true after the breadcrumb run.
- This run classifies as: `CLASS_IRQ_NO_EVENT`
- Reason:
  - init reached smoke
  - userspace attempted HCI Reset send
  - driver send path entered
  - opcode 0x0C03 was seen
  - EM[64] command write happened
  - SWINT/IRQ happened
  - EM[96] never became ready and RX work never ran

## Next Step

1. Investigate why CEVA/firmware leaves `EM_EVT_FLAG_WORD` and `EM[96..]` idle after reset command despite SWINT/IRQ activity.
2. Reconcile the userspace `send(...)=ENETDOWN` result with the driver breadcrumb proof that `ceva_bt_send_frame` still executed.
3. If persistent userspace-only proof is still required independent of klog, fix the userspace slot writer under 0x8F000088 .. 0x8F0000D8 and rerun once.
