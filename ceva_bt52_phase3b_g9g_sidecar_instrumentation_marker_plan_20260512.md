# CEVA BT5.2 Phase 3B-G9G Sidecar Instrumentation / Marker 设计

## 1. 结论

后续跑板前必须先有 marker 设计。G9-G 定义一个候选 marker page，把 sidecar image、bootstrap、vendor runtime init、ingress、egress 和 Linux real RX 分开证明。每个 marker 都必须有唯一写入方、读取方、清理规则和误判控制。

## 2. Marker 地址候选

候选 base：`0x8F010000`

原因：当前 Phase 2.5 已使用 `0x8F000000` 作为 stage marker，sidecar marker 不复用该 base，避免覆盖已有证据。

Open Blocker: `0x8F010000` 必须在代码阶段通过 reserved-memory 或 boot memory map 确认不被 Linux 使用。本文件只冻结候选 layout，不声称该地址已安全。

Marker 格式：每个 slot 8 bytes，写 64-bit value。清零表示未发生。需要 sequence 的 marker 在下一个 slot 写 seq/opcode。

## 3. Marker 表

| marker | address/offset | 写入方 | 读取方 | 触发时机 | 清理规则 |
|---|---|---|---|---|---|
| `SIDECAR_IMAGE_PRESENT` | base + `0x00` | loader / launch hook | capture script | sidecar image 已加载或 staging manifest 已验证 | launch 前清零 |
| `SIDECAR_START` | base + `0x08` | sidecar `_start` | capture script | sidecar 获得 PC 并执行第一段代码 | launch 前清零 |
| `SIDECAR_PRE_RWIP_INIT` | base + `0x10` | sidecar main | capture script | 调用 `rwip_init()` 前 | launch 前清零 |
| `SIDECAR_POST_RWIP_INIT` | base + `0x18` | sidecar runtime | capture script | `rwip_init()` 返回或进入 post-init path | launch 前清零 |
| `SIDECAR_POST_RWIP_DRIVER_INIT` | base + `0x20` | sidecar runtime | capture script | `rwip_driver_init()` 完成 | launch 前清零 |
| `SIDECAR_INGRESS_READY` | base + `0x28` | sidecar bridge | Linux/capture | bridge eif/poll loop 已准备接命令 | launch 前清零 |
| `SIDECAR_RX_CMD_0C03` | base + `0x30` | sidecar ingress | capture script | sidecar 解析到 Reset opcode `0x0C03` | 每次 launch 清零，运行中覆盖 seq |
| `SIDECAR_CMD_CONSUMED` | base + `0x38` | sidecar ingress | Linux/capture | command 已复制并调用 vendor ingress | 每次 launch 清零，运行中覆盖 seq |
| `SIDECAR_EGRESS_EVENT_READY` | base + `0x40` | sidecar egress | Linux/capture | sidecar 已写 EM[96] 并置 EM[73] | Linux 读后保留到 capture |
| `SIDECAR_HCI_SEND_2_HOST` | base + `0x48` | sidecar HCI seam | capture script | vendor `hci_send_2_host()` 或等价 seam 被触发 | launch 前清零 |
| `LINUX_RX_REAL_EVENT` | base + `0x50` | Linux driver rx path | capture script | Linux 从 EM[96] 读到 real event | launch 前清零 |
| `REAL_RESET_PASS` | base + `0x58` | Linux validation | capture script | Reset CC opcode/status 校验成功且非 synthetic | launch 前清零 |
| `REAL_RLV_PASS` | base + `0x60` | Linux validation | capture script | Read Local Version CC 校验成功且非 synthetic | launch 前清零 |

## 4. 辅助 slots

| name | address/offset | 写入方 | 内容 |
|---|---|---|---|
| `MARKER_SEQ` | base + `0x68` | sidecar/Linux | last command/event seq |
| `MARKER_OPCODE` | base + `0x70` | sidecar/Linux | last opcode, Reset=`0x0C03`, RLV=`0x1001` |
| `MARKER_EVENT_CODE` | base + `0x78` | sidecar/Linux | last HCI event code, CC=`0x0E`, CS=`0x0F` |
| `MARKER_ERROR` | base + `0x80` | any writer | first fatal error code; only first writer wins |

## 5. Capture 脚本需要新增什么

未来 `scripts/linux_boot_phase2_capture.gdb` 或新 capture 脚本需要新增：

```text
dump 0x8F010000..0x8F010090 marker page
print each marker slot as 64-bit value
read EM[64..79] ingress control words
read EM[88..96] egress control words
read EM[96..127] event payload bytes
decode Reset CC and RLV CC bytes
record whether synthetic responder branch was disabled
```

Capture 输出必须区分：

- sidecar 没启动。
- sidecar 启动但没进入 runtime。
- runtime 进入但没收命令。
- 命令被消费但没事件。
- event 到 Linux 但 validation 失败。
- real Reset/RLV pass。

## 6. 误判风险

| 风险 | 防护 |
|---|---|
| stale marker 没清零 | launch/capture 前强制清 marker page，并记录清零成功。 |
| Linux synthetic responder 写 pass | synthetic 默认关闭；real pass 必须要求 sidecar marker 链完整。 |
| Linux 覆盖 marker page | reserved-memory 或 boot map carveout；capture 同时检查 marker magic 是否被破坏。 |
| Rocket cache / PS-side dump 不一致 | sidecar 写 marker 后执行 fence；capture 尽量用同一可见路径读。 |
| sidecar 写了 marker 但没有真正调用 vendor seam | `SIDECAR_HCI_SEND_2_HOST` 与 EM payload/opcode 交叉校验。 |
| H4 byte 混入 payload 导致假 decode | egress parser 校验 event code 必须在 EM[96] byte 0。 |

## 7. 清理规则

- 每次 launch 前清零 entire marker page。
- Sidecar 只写自己的 marker，不清 Linux marker。
- Linux 只写 `LINUX_RX_REAL_EVENT`、`REAL_RESET_PASS`、`REAL_RLV_PASS` 和 consumed seq。
- Fatal error 只允许 first writer 写 `MARKER_ERROR`，后续错误写 secondary log。
- Capture 完成后不自动清 marker，保留现场证据。

## 8. PASS / FAIL / STOP

PASS 条件：

- Marker table 与 bridge contract 对齐。
- 每个 marker 有唯一 owner。
- Capture 增项能独立定位 bootstrap/ingress/egress 断点。

FAIL 条件：

- 只用一个 pass/fail marker，无法定位断点。
- synthetic 和 real event 使用同一 marker。
- marker 地址与已有 stage marker 冲突。

STOP 条件：

- 无法为 marker page 提供稳定可读写内存。
- marker proof 需要改 RTL 才能实现。
- capture 无法区分 stale marker 与本轮 marker。
