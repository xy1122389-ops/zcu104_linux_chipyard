# CEVA BT5.2 Phase 0F-A - Linux Probe Planning

## 1. 目标

Phase 0F-A 只做 Linux probe 前置规划，不写 driver，不改 DT，不碰 BlueZ，不上板。

本轮要收敛的问题只有一个：在已经证明 CEVA MMIO 和 `dm_sw_irq -> PLIC` 硬件路径成立的前提下，Linux 第一版应该用什么最小形态接入，才能先证明 probe、MMIO 访问、IRQ 绑定和本地 ack 语义都闭环。

一句话结论：

> 第一版应走“DT-backed minimal platform debug driver”，而不是 UIO，也不是 HCI/BlueZ 路线。

---

## 2. 本轮读取到的证据

### 2.1 Phase 0E-D 板级冻结结果

从 `docs/bringup/ceva_bt52_phase0e_d_dm_sw_irq_repeated_board_pass.md` 可直接确认：

- `dm_sw_irq` repeated board PASS，`8/8` 成功
- `PROBE_MCAUSE = 0x800000000000000B`
- `PROBE_CLAIM_ID = 0x00000001`
- `PROBE_CEVA_STATUS_BEFORE_ACK = 0x00000008`
- `PROBE_CEVA_STATUS_AFTER_ACK = 0x00000000`
- `PROBE_HANDLER_COUNT = 8`
- `PROBE_TARGET_COUNT = 8`
- `PROBE_DONE = 1`
- `PROBE_TIMEOUT = 0`

这说明：

1. CEVA `dm_sw_irq` 的硬件中断路径已经闭环。
2. PLIC source id 已经实测闭环为 `1`。
3. CEVA 本地 `INTACK1[3]` 确实能把本地 status 清掉。
4. 该 IRQ 当前语义按现有 build 应按 level-triggered 对待。

### 2.2 Phase 0E-B2.5 生成产物结论

从 `docs/bringup/ceva_bt52_phase0e_b25_plic_source_lookup.md` 可直接确认，Phase 0E 冻结时曾基于 generated DTS / memmap / regmap / make verilog log 得出以下结论：

- `PLIC base = 0x0c000000`
- generated DTS 中存在 `ceva-dm@65000000`
- 该 CEVA 节点的 IRQ 表达是 `interrupt-parent = <&L16>; interrupts = <1>;`
- 保存下来的生成日志中有 `Interrupt map (2 harts 5 interrupts): [1, 1] => ceva`

这说明：

1. CEVA 在硬件冻结时已经进入 interrupt map。
2. CEVA 的 Linux/DT 表达应当是一个普通 PLIC 子设备，而不是额外的 `interrupts-extended` 设备。
3. Phase 0E 硬件冻结时的 PLIC 总源数已经不是当前 Linux bringup DTS 中的旧值。

### 2.3 当前工作树里的 Linux DTS 现状

当前工作树里没有保留 `generated-src/` 目录，也没有现成的 Phase 0E generated DTS / memmap / regmap 文件可直接复读。

但当前 `linux-bringup/dtb/chipyard-zcu104-fedora.dts` 和 `linux-bringup/dtb/chipyard-zcu104-linux-slip.dts` 仍能看到旧 DTS 状态：

- `interrupt-controller@c000000` 仍是 `riscv,ndev = <4>`
- `serial@64000000` 仍占用 `interrupts = <1>`
- `serial@64003000` 仍占用 `interrupts = <2>`
- `spi@64001000` 仍占用 `interrupts = <4>`

这和 Phase 0E 冻结证据里的 `ceva-dm@65000000 { interrupts = <1>; }` 明显不一致。

因此，当前 `linux-bringup/dtb/*.dts` 只能作为旧 bringup 背景参考，不能直接拿来作为 CEVA Linux probe 的真实 IRQ 描述来源。

---

## 3. 已闭环的硬件事实

| 项目 | 值 |
|---|---|
| CEVA base | `0x65000000` |
| DM VERSION | `0x65000004 -> 0x0B000500` |
| BT VERSION | `0x65000404 -> 0x0B000600` |
| BLE VERSION | `0x65000804 -> 0x0B001100` |
| EM debug window | `0x65010000 ~ 0x6501ffff` |
| IRQ source | `dm_sw_irq` |
| PLIC source id | `1` |
| IRQ mode | level-triggered |
| Trigger | `0x65000000` bit `27` |
| Mask | `0x65000018` bit `3` |
| Status | `0x6500001c` bit `3` |
| Ack | `0x65000020` bit `3` |

这些事实已经足够支撑“最小 Linux probe 驱动”的设计，不需要先碰 HCI、BlueZ、RF/PHY 或真实蓝牙流量。

---

## 4. Phase 0F 的最小 Linux 接入路线

## 4.1 MMIO base/size 应如何写

推荐第一版只暴露一个最小 control window：

```dts
ceva_dm: ceva-dm@65000000 {
    compatible = "ceva,rw-dm-top-debug";
    reg = <0x65000000 0x1000>;
    interrupt-parent = <&plic>;
    interrupts = <1>;
};
```

理由：

1. 第一版 driver 只需要访问 `0x000`, `0x018`, `0x01c`, `0x020`, `0x004`, `0x404`, `0x804`，全部落在 `0x1000` 之内。
2. `0x65010000 ~ 0x6501ffff` 的 EM debug window 目前不是 probe 最小闭环所必需，不应在 v1 把范围放大到 `0x20000`。
3. 先把控制寄存器窗口单独收敛，更利于后续把 EM window 作为第二个 resource 单独加入，而不是一开始就把整个 CEVA 空间都映进来。

因此，Phase 0F 建议：

- v1 只写 `reg = <0x65000000 0x1000>`
- EM window 若未来确实需要，再单独加第二个 resource，例如 `reg = <0x65010000 0x10000>`

## 4.2 CEVA IRQ 应如何表达

第一版应按“普通 PLIC 子设备”表达：

```dts
interrupt-parent = <&plic>;
interrupts = <1>;
```

不建议在 CEVA 设备节点上写 `interrupts-extended`，因为：

1. `interrupts-extended = <&cpu_intc ...>` 是 PLIC 控制器节点描述 CPU context 用的，不是 PLIC 子设备 source 的常规写法。
2. Phase 0E 冻结时的 generated DTS 证据已经指向 `interrupt-parent + interrupts = <1>` 这一表达。

但这里有一个必须单独强调的前提：

当前 `linux-bringup/dtb/*.dts` 还是旧的 `riscv,ndev = <4>` 版本，且把 IRQ 1 绑给了 `serial@64000000`。因此未来真做 DT patch 时，不能只把 CEVA 节点硬塞进当前 DTS；必须以 Phase 0E 冻结时的硬件/生成证据为准，同步修正整个 PLIC source map。

换句话说：

- CEVA 节点的 IRQ 写法本身是 `interrupts = <1>`
- 但真正落地 DT 时，必须保证整份 DTS 的 `riscv,ndev` 和其他设备 source id 与 Phase 0E 硬件一致
- 不能把当前旧 DTS 当成 source-id 真相

## 4.3 第一版走 platform driver 还是 UIO/debug driver

推荐：

> 第一版走 minimal platform debug driver。

不推荐第一版走 UIO，原因如下：

1. 当前要验证的是 Linux 内核侧的 `probe + ioremap + request_irq + local ack`，这本来就是 kernel driver 的职责，不是 userspace mmap 的职责。
2. `dm_sw_irq` 当前按 level-triggered 对待，source ack 放在 userspace 会把时序和 root cause 拉复杂，反而不利于第一次闭环。
3. UIO 依然需要 kernel stub 和 DT 节点，省不掉关键工作，却会把最小目标从“内核证明硬件路径成立”扩展成“内核 + 用户态协作”。
4. 当前明确要求不碰 BlueZ、不注册 `hci_dev`，那么第一版最合适的归类就不是 Bluetooth stack，而是一个纯 bringup/debug 平台驱动。

推荐放置形态：

- 类型：built-in debug platform driver
- 位置倾向：`drivers/misc/` 或 `drivers/soc/`
- 不建议一开始就放进 `drivers/bluetooth/`

---

## 5. 第一版 driver 的最小职责

第一版只做下面这五件事：

1. `probe()` 里 `devm_platform_ioremap_resource()`
2. 读取并打印三组 VERSION
3. `platform_get_irq()` / `devm_request_irq()`
4. 中断处理函数里只做 CEVA 本地 `INTACK1[3]`
5. 明确不注册 `hci_dev`，不接 BlueZ

推荐的最小 probe 逻辑如下：

```c
probe()
  base = devm_platform_ioremap_resource(pdev, 0)
  read DM/BT/BLE version
  writel(BIT(3), base + 0x20)   // clear stale local status once
  irq = platform_get_irq(pdev, 0)
  devm_request_irq(dev, irq, ceva_irq_handler, 0, "ceva-bt52", drv)
  dev_info(... versions ...)
```

推荐的最小 IRQ handler 逻辑如下：

```c
irq_handler()
  writel(BIT(3), base + 0x20)
  return IRQ_HANDLED
```

关键点：

1. Linux 驱动不需要自己去碰 PLIC claim/complete 寄存器。那是 PLIC 控制器驱动的职责。
2. CEVA 设备驱动只需要清自己的 local source，也就是写 `INTACK1[3]`。
3. v1 driver 不做 trigger，不做自测循环，不做 EM window dump，不做 HCI 注册。

## 5.1 关于 `INTCNTL1[3]` mask 的取舍

严格按本轮最小目标，v1 driver 可以先不把“主动 enable source”纳入 probe 主线，只保留 VERSION 读和 stale-ack。

原因：

1. 本轮目标是规划 probe 最小入口，不是立刻定义完整 Linux IRQ 触发实验。
2. 用户已明确把第一版范围收窄为 `probe + ioremap + VERSION read + request_irq + INTACK1[3]`。

但必须记录一个工程现实：

- 如果下一阶段要真正在 Linux 下观察 live `dm_sw_irq` 进入 handler，那么届时最小增量通常还要把 `INTCNTL1[3]` 打开。

因此，本计划建议把 `INTCNTL1[3]` enable 明确留给下一实现步，而不是在 Phase 0F-A 里把范围偷偷放大。

---

## 6. 为什么当前不建议先走 polling 或 UIO fallback

仓库历史里已经有一个重要经验：当 DT 的 IRQ 号超出 PLIC `ndev` 时，Linux PLIC 映射会访问不存在的 MMIO，直接导致 TileLink bus hang。

这条经验来自既有 Linux bringup 文档，说明“错误 IRQ 描述”是灾难性的，不能轻率碰。

但这并不意味着 CEVA 路线应该默认退回 polling 或 `platform_get_irq_optional()`：

1. CEVA 硬件 IRQ 路径已经在 baremetal 被证明是真实存在的，不是像 PS SDIO 那样根本没进 PLIC。
2. CEVA 这里的核心问题不是“没有中断线”，而是“当前 Linux DTS 还是旧映射”。
3. 所以 CEVA 的主路线应该是“先把 DT 映射描述修到与 Phase 0E 硬件一致，再上真正 request_irq 的平台驱动”，而不是把 polling 变成默认架构。

如果后续为了拆问题，临时做一个“只读 VERSION、不要 IRQ 的 debug probe”也可以，但那只能算临时绕行，不应成为主路线。

---

## 7. 当前最大的前置风险

当前最需要写进 planning 的风险不是 driver 代码本身，而是 DTS 资产不一致：

1. 当前工作树没有现成 `generated-src/` 可回读。
2. 当前 `linux-bringup/dtb/*.dts` 仍是旧的 `riscv,ndev = <4>` 版本。
3. Phase 0E 冻结证据则明确指向“5 interrupts + CEVA source id 1”。

这意味着未来真正进入实现阶段时，第一步不是写复杂 driver，而是先拿到一份与冻结 bitstream 一致的 DTS 事实源。

这份事实源有两种可接受来源：

1. 恢复或重新生成与 `RocketZCU104Phase0bConfig` 对应的 generated DTS / memmap / regmap
2. 若短期内不能恢复 generated-src，则至少把 Phase 0E 已冻结文档中的 DTS / interrupt-map 事实整理成一个单独、可复核的静态参考

在拿到这份事实源之前，不应把当前 `linux-bringup/dtb/chipyard-zcu104-fedora.dts` 直接拿去扩 CEVA 节点。

---

## 8. 推荐的后续实现顺序

以下顺序是给未来 Phase 0F-B/0F-C 用的，不是本轮执行项：

1. 先补齐一份与 Phase 0E 冻结硬件一致的 DTS / memmap 事实源。
2. 再做最小 DT patch，只同步 CEVA 节点和正确的 PLIC source map，不夹带 BlueZ/HCI 变更。
3. 再加一个 built-in minimal platform debug driver。
4. 第一次 Linux 验证只看：probe 是否成功、三组 VERSION 是否正确、IRQ 是否可申请、handler 是否只靠 `INTACK1[3]` 清源。
5. 在这一步通过之前，不做 `hci_dev`、不接 BlueZ、不进入协议栈。

---

## 9. Phase 0F-A 结论

Phase 0F-A 的 Linux probe 最小路线已经足够明确：

- MMIO：v1 只暴露 `0x65000000 + 0x1000`
- IRQ：CEVA 节点应表达为 `interrupt-parent = <&plic>; interrupts = <1>`
- 驱动类型：选 minimal platform debug driver，不选 UIO
- v1 driver：只做 `probe + ioremap + VERSION read + request_irq + INTACK1[3]`
- 明确不做：`hci_dev`、BlueZ、EM window 扩展、协议栈接入

唯一必须先记住的风险是：

> 当前 Linux bringup DTS 仍是旧 IRQ 映射，不能直接拿来做 CEVA probe 的 DT 基线。

在这个风险被单独消化之前，最小 CEVA Linux probe 路线应保持为“DT 对齐后的一版 platform debug driver”，而不是贸然把旧 DTS、UIO、BlueZ 或 polling 混在一起推进。