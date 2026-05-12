# CEVA BT5.2 Phase 3B-G10 长期 Master Plan

## 1. G10 总结论

G10 把当前项目从 Phase 2.5 synthetic HCI smoke 和 Phase 3B-G9 sidecar 路线，扩展成 Phase 0A 到 Phase 3B-H15 的长期工程路线图。

长期路线保持不变：

```text
Linux Bluetooth core / BlueZ
  -> Linux host shim
  -> EM/SWINT bridge
  -> baremetal sidecar / firmware context
  -> CEVA vendor runtime
  -> real HCI event
  -> Linux HCI RX path
```

关键判断也保持不变：Phase 2.5 不是完整蓝牙成功，只是 synthetic HCI control-plane smoke。real HCI Reset 没通过的根因不是 userspace 没发包，也不是 driver send path 没进，而是当前镜像没有真实 CEVA consumer 消费 EM command。

## 2. 当前路线约束

本 master plan 明确遵守以下工程边界：

- 不自己写完整蓝牙协议栈。
- Linux Host 侧由 Linux Bluetooth core / BlueZ 负责。
- Controller 侧由 CEVA vendor runtime 负责。
- H4 只是 HCI transport framing，不是蓝牙协议栈。
- 不把 vendor runtime 塞进 Linux kernel。
- 不做 Linux userspace fake controller helper。
- 第一刀长期实现不是改 `ceva_bt52.c`，也不是改 RTL，而是新增 sidecar skeleton。

## 3. 已完成阶段回看

| 阶段 | 状态 | 已证明内容 | 明确未证明内容 |
|---|---|---|---|
| Phase 0A | retrospective baseline | repo/toolchain/collateral intake 作为长期路线起点 | 不宣称硬件或蓝牙能力 |
| Phase 0B | PASS | CEVA RTL 集成、VERSION MMIO、board visibility | 不宣称 EM layout 或 IRQ 完整 |
| Phase 0C | PASS | EM range/layout 可读写验证 | 不宣称 block sweep 全覆盖 |
| Phase 0D | PASS | EM block sweep 和稳定窗口 | 不宣称 IRQ 或 runtime consumer |
| Phase 0E | PASS | PLIC/SWINT/claim-complete 路线和 dm_sw_irq board pass | 不宣称 Linux HCI controller |
| Phase 0F | PASS as audit/planning | Linux probe、DTS/IRQ 事实、vendor init 调研 | 不运行 vendor runtime |
| Phase 0G | PASS | 单 IP 活性、CLKN/初始化观测路线 | 不宣称 HCI consumer |
| Phase 1A | PASS as integration hardening | bitstream/build/J-Link/EM MMIO/guard 经验 | 不宣称 controller runtime |
| Phase 2 | PASS as minimal Linux bringup | Linux module/probe/hci0 方向基础 | 不宣称真实 HCI event |
| Phase 2.5 | PASS as synthetic smoke | Linux HCI control-plane、USER channel、synthetic response | 不宣称完整蓝牙成功 |
| Phase 3A | PASS as host-plane baseline | host-facing control plane 与 smoke 经验 | 不宣称 real consumer |
| Phase 3B-D/E/F/G6/G7/G8/G9 | PASS as diagnosis and planning | real consumer 缺失、Route C now / Route B next、sidecar route | 不宣称 real Reset pass |

## 4. 未来主线

G10 后的长期执行分三段：

1. Phase 3B-H1 到 H4: 建立 sidecar skeleton、marker、内存/boot/packaging 基础设施。
2. Phase 3B-H5 到 H8: 建立 EM/SWINT bridge skeleton、vendor asset/build 入口和 runtime link model。
3. Phase 3B-H9 到 H15: 接入 vendor runtime，完成真实 Reset、Read Local Version、regression、再进入受控 BlueZ bringup。

## 5. 成功定义分层

| 层级 | 成功定义 | 不允许混淆成 |
|---|---|---|
| Control-plane smoke | Linux 能创建 HCI device、发 HCI command、收到 synthetic 或 test response | 完整蓝牙成功 |
| Sidecar skeleton proof | sidecar image 能启动、写 marker、保持独立执行流 | vendor runtime 已运行 |
| Bridge skeleton proof | EM/SWINT ingress/egress contract 能传递 marker-backed packet | real controller event |
| Vendor bootstrap proof | `rwip_init()` / `rwip_driver_init()` marker 链成立 | real Reset pass |
| Real Reset proof | Reset `0x0C03` 被 vendor runtime 消费并返回真实 HCI event | BlueZ scan success |
| RLV proof | Read Local Version 返回真实 Command Complete | pair/connect success |
| Bluetooth bringup | BlueZ scan/pair/connect 在 real controller path 后启动 | synthetic path continuation |

## 6. 最小下一步

G10 之后的第一刀仍然是 Phase 3B-H1：新增 sidecar skeleton source 和 marker header，不改 driver、不改 RTL、不改 payload。只有 H1/H2/H3 证明 sidecar 执行上下文和 marker 捕获之后，才进入 ingress/egress bridge skeleton。

## 7. Open Blockers

- Vendor runtime source/blob 的 legal/vendor approval。
- CEVA internal firmware context 是否存在且可用。
- Sidecar 独立 PC/执行流承载方式。
- reserved memory / marker page 是否不会被 Linux 覆盖。
- `rwip_config.h`、linker/startup、NVDS/default params 的正式来源。
- future packaging 是否由 OpenSBI、GDB dev loader，还是 vendor loader 负责。
