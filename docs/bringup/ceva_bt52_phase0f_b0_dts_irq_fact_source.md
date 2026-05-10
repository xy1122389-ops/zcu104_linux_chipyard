# CEVA BT5.2 Phase 0F-B0 - DTS and IRQ Fact Source

## 1. 目标

Phase 0F-B0 的目标不是修改 DTS，也不是实现 Linux driver。

本轮只做一件事：把 Phase 0E 冻结硬件对应的 Linux-visible 事实源补齐，明确哪些结论来自 Phase 0E 冻结证据，哪些内容只是当前 linux-bringup DTS 的旧状态，从而为后续最小 DT patch 提供可靠基线。

本轮不做以下事项：

- 不改 DTS
- 不写 driver
- 不改 RTL / wrapper / Scala
- 不综合，不生成 bitstream
- 不上板
- 不碰 BlueZ / HCI

---

## 2. 本轮使用的事实来源

本轮只整理以下现有文件中的证据：

- docs/bringup/ceva_bt52_phase0f_linux_probe_plan.md
- docs/bringup/ceva_bt52_phase0e_b25_plic_source_lookup.md
- docs/bringup/ceva_bt52_phase0e_d_dm_sw_irq_repeated_board_pass.md
- linux-bringup/dtb/chipyard-zcu104-fedora.dts
- linux-bringup/dtb/chipyard-zcu104-linux-slip.dts

其中，Phase 0E 冻结硬件事实主要来自前 3 份 bringup 文档；当前 linux-bringup DTS 只用于确认旧 IRQ 映射仍然存在，不能反过来覆盖冻结硬件事实。

---

## 3. Phase 0E 冻结硬件事实

下列事实应视为 Phase 0E bitstream 对应的 Linux-visible 硬件基线。

### 3.1 CEVA 和 PLIC 基本地址

| 项目 | 值 | 依据 |
|---|---|---|
| CEVA base | 0x65000000 | Phase 0E 文档中的寄存器窗口与 VERSION 寄存器验证 |
| PLIC base | 0x0c000000 | Phase 0E-B2.5 从 generated DTS / memmap / regmap 闭环得出 |

### 3.2 CEVA IRQ 冻结结论

| 项目 | 值 | 依据 |
|---|---|---|
| CEVA IRQ source | dm_sw_irq | Phase 0E 全程只接这一根 CEVA IRQ |
| CEVA PLIC source id | 1 | Phase 0E-B2.5 generated evidence + Phase 0E-D board pass |
| IRQ 结果 | repeated 8/8 PASS | Phase 0E-D board pass |
| IRQ 语义 | 当前 build 按 level-triggered 对待 | Phase 0F-A 规划文档收敛结论 |

### 3.3 generated interrupt map 和 generated DTS 结论

Phase 0E 冻结时，已有文档把 generated collateral 的关键结论固定下来：

1. 保存下来的 make verilog 日志包含：

   Interrupt map (2 harts 5 interrupts): [1, 1] => ceva

2. generated DTS 曾包含 CEVA 节点：

   ceva-dm@65000000

3. 该 CEVA 节点的 IRQ 写法已经被 Phase 0E 文档固定为：

   interrupt-parent = <&L16>
   interrupts = <1>

这三点合在一起，足以固定下面几个硬件事实：

- Phase 0E generated interrupt map 是 5 interrupts，而不是当前 linux-bringup DTS 里的 4 interrupts
- CEVA 在 Phase 0E 硬件中已经是 Linux-visible 的 PLIC 子设备
- CEVA 节点写法应为 interrupt-parent 加 interrupts = <1>

### 3.4 板级闭环对 source id 的再次确认

Phase 0E-D repeated board pass 又从板上把同一件事闭了一次：

- PROBE_CLAIM_ID = 0x00000001
- PROBE_CEVA_STATUS_BEFORE_ACK = 0x00000008
- PROBE_CEVA_STATUS_AFTER_ACK = 0x00000000
- PROBE_HANDLER_COUNT = 0x00000008
- PROBE_TARGET_COUNT = 0x00000008

这说明 source id = 1 不是只停留在 generated 文本里，而是已经在冻结 bitstream 对应的真实硬件路径上被重复验证。

---

## 4. 当前 linux-bringup DTS 的旧状态

当前工作树里的两个 DTS：

- linux-bringup/dtb/chipyard-zcu104-fedora.dts
- linux-bringup/dtb/chipyard-zcu104-linux-slip.dts

都仍处于旧 IRQ 映射状态，至少包含以下共同事实：

| 项目 | 当前旧状态 |
|---|---|
| PLIC ndev | riscv,ndev = <4> |
| serial@64000000 | interrupts = <1> |
| serial@64003000 | interrupts = <2> |
| spi@64001000 | interrupts = <4> |

这说明当前 linux-bringup DTS 仍然反映的是旧的 4-source PLIC 视图，并没有同步 Phase 0E 冻结后的 CEVA IRQ 接入结果。

换句话说：

- 当前 DTS 里 IRQ 1 仍然被 serial@64000000 占用
- 当前 DTS 里还没有可直接使用的 ceva-dm@65000000 节点
- 当前 DTS 的 ndev 也还停留在旧值 4

因此，当前 linux-bringup/dtb 下的 DTS 只能作为旧 bringup 背景资料，不能直接作为 CEVA Linux probe 的基线。

---

## 5. 为什么当前 DTS 不能直接拿来做 CEVA probe 基线

原因不是 CEVA 路径不存在，而是当前 DTS 与 Phase 0E 冻结 bitstream 不一致。

必须明确区分两类事实：

1. 冻结硬件事实

- 来自 Phase 0E generated 证据和板级 repeated pass
- 说明 CEVA 已经进入 PLIC interrupt map
- 说明 CEVA source id 已固定为 1

2. 当前 linux-bringup DTS 现场状态

- 仍是旧 4-source PLIC 布局
- 仍把 IRQ 1 分给 UART
- 尚未反映 CEVA 节点

所以，当前 DTS 不能被当成 Phase 0E 冻结硬件的权威描述，只能被当成“尚未同步”的旧软件资产。

---

## 6. 下一步 DT patch 原则

后续如果进入最小 DT patch 阶段，必须遵守以下原则：

### 6.1 不能只硬塞 CEVA 节点

不能在当前旧 DTS 上只追加一个 ceva-dm@65000000 节点，然后简单写 interrupts = <1> 就结束。

原因很直接：当前 DTS 里 IRQ 1 仍然属于 serial@64000000，riscv,ndev 也还是 4。只加 CEVA 节点会让整份 PLIC source map 自相矛盾。

### 6.2 必须同步整份 PLIC source map

后续 DT patch 必须同步修正：

- riscv,ndev
- 已占用 source id 的设备分配
- CEVA 节点的 source id 表达
- 与 Phase 0E generated interrupt map 相关的整体可见 source 布局

目标不是“让 DTS 里出现 CEVA 字样”，而是让整份 DTS 对 PLIC 的描述与冻结 bitstream 完整一致。

### 6.3 必须保证 DTS 与 Phase 0E bitstream 一致

后续 DT patch 的真基线只能是：

- Phase 0E 冻结时的 generated DTS / memmap / regmap 结论
- Phase 0E-D repeated board pass 的硬件实证

不能把当前 linux-bringup DTS 的旧值当成真相，再去倒推 CEVA source map。

### 6.4 不碰 BlueZ / HCI

后续最小 Linux 接入仍应保持在 bringup/debug 范围内：

- 不碰 BlueZ
- 不注册 hci_dev
- 不把 CEVA 最小 probe 变成 Bluetooth stack 接入任务

这条边界与 Phase 0F-A 规划保持一致。

---

## 7. 当前可执行结论

到 Phase 0F-B0 为止，可以把后续 Linux-visible 事实源固定为下面几条：

1. CEVA base = 0x65000000
2. PLIC base = 0x0c000000
3. CEVA PLIC source id = 1
4. Phase 0E generated interrupt map 是 5 interrupts
5. generated DTS 曾有 ceva-dm@65000000
6. CEVA 节点写法应为 interrupt-parent 加 interrupts = <1>
7. 当前 linux-bringup/dtb 下的 DTS 仍是旧状态：ndev = 4，IRQ 1/2/4 仍被 UART/SPI 占用
8. 因此，当前 DTS 不能直接作为 CEVA Linux probe 的基线
9. 下一步 DT patch 必须同步整份 PLIC source map，且必须与 Phase 0E bitstream 一致
10. 后续仍不碰 BlueZ / HCI，不注册 hci_dev

---

## 8. 本轮结论

Phase 0F-B0 已完成“冻结硬件事实源”补齐。

本轮没有修改任何 DTS，也没有实现 driver，而是把后续 DT patch 必须依赖的事实源分成了两层：

- 第一层：Phase 0E 冻结硬件事实，是后续 patch 的权威来源
- 第二层：当前 linux-bringup DTS 旧状态，只是待修正的软件现场

后续只要严格按这个分层推进，就能避免在旧 DTS 上做局部硬塞，进而避免把 CEVA Linux probe 建立在错误 IRQ 映射之上。