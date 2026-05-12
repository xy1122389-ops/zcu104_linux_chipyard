# Phase Gate PASS / FAIL / STOP Matrix

## 1. Gate philosophy

每个阶段只证明一个新的事实。没有 marker、log、byte-level evidence 或 explicit document gate，就不能把后续阶段的能力提前声明为成功。

## 2. Major gates

| Gate | PASS | FAIL | STOP |
|---|---|---|---|
| G0 Baseline | repo/status/docs 已审计 | key docs 缺失 | dirty generated outputs 阻塞 |
| G1 Sidecar skeleton | source builds, marker constants frozen | build/link fails | 无 execution context |
| G2 Marker proof | marker page 可清零/写入/读取 | stale marker 无法排除 | marker memory 不可保留 |
| G3 Ingress skeleton | Reset opcode 到达 sidecar marker | Linux 写了 EM 但 sidecar 未见 | ingress 需要 RTL change |
| G4 Egress skeleton | sidecar event window 被 Linux 读到 | ready/payload/len 不一致 | egress 需要 Linux HCI core 大重构 |
| G5 Vendor build | approved runtime asset 能 link | 缺少 config/stub 边界 | vendor asset 不可用 |
| G6 Vendor init | `rwip_init` / `rwip_driver_init` marker | runtime assert/fault | 只能 kernel port 才能跑 |
| G7 Real Reset | Reset CC real event | command consumed no event | event 只能 synthetic |
| G8 Real RLV | RLV CC real event | Reset pass but RLV fail | controller state unstable |
| G9 BlueZ entry | Reset/RLV repeated real pass | BlueZ 前置条件不满足 | scan 掩盖 controller bug |

## 3. What cannot be claimed early

- `hci0` exists does not mean Bluetooth controller works.
- HCI Reset synthetic response does not mean CEVA runtime works.
- EM command-ready set does not mean command was consumed.
- SWINT asserted does not mean vendor scheduler ran.
- Sidecar skeleton started does not mean `rwip_init()` ran.
- `rwip_init()` marker does not mean Reset passed.
- Reset real pass does not mean scan/pair/connect are ready.

## 4. Evidence requirements

| Claim | Required evidence |
|---|---|
| command published | EM[64..], EM[72], SWINT evidence |
| command consumed | `SIDECAR_CMD_CONSUMED`, seq match, opcode marker |
| vendor ingress alive | `hci_cmd_received` seam marker or equivalent vendor ingress marker |
| vendor egress alive | `SIDECAR_HCI_SEND_2_HOST`, EM[96] event bytes |
| Linux real RX alive | `LINUX_RX_REAL_EVENT`, synthetic disabled evidence |
| Reset real pass | `0E 04 01 03 0C 00`, sidecar marker chain, Linux RX marker |
| RLV real pass | `0E 0C 01 01 10 00 ...`, sidecar marker chain, Linux RX marker |

## 5. Escalation rules

- Legal/vendor asset blocker escalates to project owner, not to code workaround.
- Execution context blocker escalates to platform/boot owner.
- Memory reservation blocker escalates to DT/OpenSBI owner.
- Bridge contract blocker escalates to driver/sidecar interface owner.
- RTL/Vivado blocker is only opened after software-first bridge proof fails for a specific reason.
