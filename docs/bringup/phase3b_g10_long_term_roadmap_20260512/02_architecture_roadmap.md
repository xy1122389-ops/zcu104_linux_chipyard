# 长期架构路线图

## 1. 目标架构

```text
BlueZ / userspace tools
  -> Linux Bluetooth core
  -> Linux ceva_bt52 host shim
  -> EM/SWINT bridge contract
  -> sidecar transport adapter
  -> CEVA vendor runtime
       -> rwip_init / rwip_reset
       -> rwip_driver_init
       -> hci_cmd_received
       -> hci_send_2_host
  -> EM/SWINT event return
  -> Linux hci_recv_frame
```

这条路线把 Host 与 Controller 分开：Linux 负责 host stack，CEVA vendor runtime 负责 controller stack。项目不重写蓝牙协议栈，只做必要 bridge 和 platform integration。

## 2. 架构不变量

- Linux-side `hci0` 是 host-facing 入口，不是 controller runtime。
- EM/SWINT 是 bridge transport contract，不是 vendor runtime 本身。
- H4 是 HCI framing，不是协议栈。
- Vendor runtime 必须在 sidecar/firmware context 中拥有 scheduler、heap、timer、interrupt 和 CEVA IP reset/init。
- Synthetic responder 只能作为诊断 fallback，不能作为长期成功定义。

## 3. Workstream 划分

| Workstream | 范围 | 负责人边界 | 首个 phase | 完成标志 |
|---|---|---|---|---|
| WS-A Baseline and guardrails | repo 状态、禁止项、文档矩阵 | 不提交生成物，不触碰 protected files | G10 | G10 文档集 |
| WS-B Sidecar foundation | skeleton、linker、marker、execution context | 不接 vendor runtime | H1 | sidecar marker proof |
| WS-C Bridge transport | EM/SWINT ingress/egress contract | 不 fake controller success | H5 | marker-backed command/event transport |
| WS-D Vendor runtime inclusion | approved source/blob、build config、runtime link | 不提交未获批 vendor asset | H7 | `rwip_init` / `rwip_driver_init` markers |
| WS-E Real HCI validation | Reset/RLV real event | synthetic 默认关闭 | H11 | Reset/RLV real PASS |
| WS-F Bluetooth bringup | BlueZ scan/pair/connect | 只在 real HCI baseline 后执行 | H15 | controlled BlueZ evidence |

## 4. 数据流

### 4.1 Ingress

```text
Linux HCI command skb
  -> ceva_bt52 send path
  -> EM[64..] command bytes
  -> EM[72] ready
  -> SWINT doorbell
  -> sidecar copies command
  -> hci_cmd_received(opcode, parlen, payload)
```

Linux-to-sidecar v0 不把 H4 type byte 作为外部契约。Sidecar 内部如果采用 H4TL，可自行合成 H4 command packet。

### 4.2 Egress

```text
CEVA vendor event
  -> hci_send_2_host(param)
  -> HCI TL / sidecar egress adapter
  -> EM[96..] event bytes
  -> EM[73] ready
  -> Linux RX path
  -> hci_recv_frame
```

EM[96] 默认存放 HCI event payload，不含 H4 type byte。packet type 用 metadata 表示。

## 5. Control points

| Control point | 目的 | 不通过时 |
|---|---|---|
| `SIDECAR_START` | 证明 sidecar PC 执行 | 回到 H1/H3 |
| `SIDECAR_INGRESS_READY` | 证明 bridge 接收端准备好 | 不改 Linux driver |
| `SIDECAR_RX_CMD_0C03` | 证明 Reset 到达 sidecar | 查 EM/SWINT contract |
| `SIDECAR_CMD_CONSUMED` | 证明 command 进入 vendor ingress | 查 `hci_cmd_received` seam |
| `SIDECAR_HCI_SEND_2_HOST` | 证明 vendor egress 触发 | 查 HCI TL / event mask |
| `LINUX_RX_REAL_EVENT` | 证明 Linux 收到 real event | 查 EM[73]/EM[96] 和 RX path |
| `REAL_RESET_PASS` | 真实 Reset Command Complete | 才能进入 RLV |
| `REAL_RLV_PASS` | 真实 Read Local Version | 才能进入 BlueZ bringup |

## 6. 长期风险控制

- 每次进入新 workstream 前，先回读上一 phase 的 PASS evidence。
- 每次写代码前，先明确 rollback point。
- 每次涉及 payload/DTB/bitstream 前，另开受控 phase，不混入 G10/G9 文档提交。
- 所有 generated outputs 默认只本地存在，不提交。
- 如果 vendor asset approval 卡住，停在 Route C，不用 synthetic 冒充真实控制器。
