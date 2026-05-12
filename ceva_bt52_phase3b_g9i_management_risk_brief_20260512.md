# CEVA BT5.2 Phase 3B-G9I 管理层风险说明

## 1. 一句话结论

Phase 2.5 证明了 Linux 侧 HCI command 能发布到 EM/SWINT 边界，但没有证明真实 CEVA controller runtime 已经运行。下一阶段必须把 vendor runtime 作为 sidecar/firmware context 接起来，而不是继续扩 synthetic 或直接做 BlueZ scan。

## 2. 为什么 Phase 2.5 不是完整蓝牙成功

Phase 2.5 的成功点是 host-facing control plane：Linux 能创建 `hci0`，userspace 能发 HCI command，driver 能写 EM 并拉 SWINT，capture 能看到发布证据。

缺失点是 real consumer：当前镜像里没有证据显示 vendor runtime 执行了 `rwip_init()`、`rwip_driver_init()`、`hci_cmd_received()` 或 `hci_send_2_host()`。没有这个 consumer，HCI Reset 的真实 controller 响应就不会自然出现。

## 3. 为什么现在不能继续 BlueZ scan

BlueZ scan 需要 controller 已经完成 Reset、Read Local Version、feature setup、LE setup 和 event return。当前还没有真实 Reset/RLV path。继续 scan 只会把问题从缺失 runtime 混到更高层协议，调试信号更差。

下一步最小成功不是 scan，而是：真实 vendor runtime 对 Reset 和 Read Local Version 产生非 synthetic event。

## 4. 为什么不是直接 H4

H4TL 不是单独的 UART parser。它依赖 vendor `rwip_eif_api`、`ke_event`、`ke_malloc`、HCI TL queue、command descriptor、scheduler 和 runtime memory model。

把 H4TL 直接塞进 Linux kernel，会变成大规模 vendor OS port。正确做法是保留 Linux 作为 host shim，在 sidecar 内部按 vendor 模型运行 runtime；H4TL 只作为 sidecar 内部可选实现细节。

## 5. 为什么不是继续 synthetic

Synthetic response 对验证 Linux host path 很有用，但它不能证明 CEVA controller runtime 活着。继续扩 synthetic 会制造更漂亮的假成功，风险是项目误以为 controller path 已完成，后续 scan/pair/connect 全部建立在虚假基础上。

Synthetic 只能保留为默认关闭的 diagnostic fallback。

## 6. 为什么要 sidecar

Vendor runtime 需要自己的：

- 初始化链：`rwip_init()`、`rwip_reset()`。
- 硬件 bring-up：`rwip_driver_init()`。
- scheduler / timer / heap / message queue。
- HCI ingress：`hci_cmd_received()`。
- HCI egress：`hci_send_2_host()`。
- interrupt ownership。

这些不属于 Linux HCI driver 的职责。Sidecar 把 vendor runtime 放回它适合的 firmware context，Linux 只负责 HCI host-facing shim 和 bridge。

## 7. 需要老板/导师确认的 vendor 资产

需要确认以下资产是否可用、可构建、可纳入本项目：

- Vendor runtime source 或官方 controller firmware blob。
- 对应目标平台的 build config、feature macro、linker/startup 文件。
- `rwip_config.h`、platform config、NVDS/default params。
- `reg_ipcore.h`、`em_map.h`、`reg_access.h` 等寄存器访问生成头。
- 是否允许本 repo 引用外部 vendor path 构建。
- 是否允许把 sidecar binary 打入 payload 或发给测试环境。
- 是否存在 CEVA internal firmware context 或官方 loader。

## 8. 本阶段最小成功

G9 extended planning 的最小成功是文档层面：把资产、依赖、执行上下文、ingress/egress 契约、packaging、marker、首刀 patch、排期、回滚全部规划到下一步能写代码。

下一代码阶段的最小成功是 sidecar skeleton：不接 Bluetooth，不接 vendor runtime，只证明 sidecar image 能构建、启动并写 marker。

真实路径最小成功是：Reset `0x0C03` 被 sidecar/vendor runtime 消费，真实 vendor event 回到 Linux，且 synthetic 默认关闭。

## 9. 管理风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| vendor 资产不可用 | sidecar 无法真实运行 | 先锁 legal/vendor approval 和 blob/source 交付方式。 |
| 无独立 execution context | runtime 无法与 Linux 共存 | 优先确认 CEVA internal context 或 secondary hart/OpenSBI path。 |
| 内存未隔离 | sidecar 被 Linux 覆盖 | 引入 reserved memory，先做 marker proof。 |
| 误把 synthetic 当成功 | 方向错误 | real pass 必须要求 sidecar marker 链完整。 |
| 过早改 RTL | 变量扩大 | software-first proof 失败前不跑 Vivado。 |

## 10. 决策请求

需要管理层确认：

1. 是否允许使用 vendor runtime source/blob。
2. 是否接受 sidecar firmware context 作为下一阶段路线。
3. 是否优先向 vendor 索取内部 controller firmware/loader 文档。
4. 是否批准第一刀只做 sidecar skeleton 和 marker proof，而不继续追 BlueZ scan。
