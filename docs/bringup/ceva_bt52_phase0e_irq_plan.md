# CEVA BT5.2 Phase 0E-A — Single IRQ Bring-up Plan

## One-line goal

Phase 0E-A 的目标是在不引入 Linux driver、Device Tree、BlueZ、RF/PHY/真实蓝牙流量的前提下，只接入 **一根** CEVA 中断到 Chipyard/Rocket 中断路径，并为后续 baremetal/J-Link 板级验证准备最小、可控、可清除的 IRQ bring-up 方案。

## Current baseline

| Item | Status |
|---|---|
| Phase 0B VERSION read | PASS |
| Phase 0C EM sparse address validation | PASS |
| Phase 0D EM continuous block sweep | PASS |
| Current inner branch | `local/phase0b-s1-real-rw-dm-top` |
| Current inner HEAD | `d39aaa0` |
| Current CEVA MMIO base | `0x65000000` |
| Current EM debug window | `0x65010000 ~ 0x6501ffff` |
| Current CEVA IRQ wiring | **none** |

## Scope and evidence boundary

本轮允许读取真实 vendor RTL，并且已从当前生成产物中的 filelist / FIR 路径锁定并只读确认实际根路径：

- `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-dm-hw-v11_00_03`

本轮只读范围内已经直接验证到以下事实：

1. 当前 CEVA wrapper 已经暴露多根 IRQ 输出口，但全部悬空。
2. 当前 Chipyard CEVA 集成只接了 AHB MMIO，没有任何 `IntSourceNode` / `toPLIC` 接线。
3. `dm_sw_irq` 的 trigger/mask/status/ack bit 已能在真实 vendor RTL 中锚到寄存器级。
4. 当前 build 的中断模式不是“工程假设”，而是由 vendor define 明确定义为 level-triggered。
5. `dm_sw_irq` 的触发路径是纯 DM 寄存器路径，不依赖 RF/PHY/真实蓝牙协议流量。

本轮仍保持以下限制：

- 不改 RTL
- 不改 wrapper
- 不改 Scala / Chipyard generator
- 不 build bitstream
- 不改 DT / Linux driver / BlueZ

## Local code facts already proven

### 1. Current wrapper exposes raw CEVA IRQ outputs

当前 wrapper 文件：

- `generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v`

wrapper 里已经直接实例化 `rw_dm_top_tglp_ext`，并且当前可见的原始 IRQ 输出包括：

- `bt_error_irq`
- `ble_error_irq`
- `ble_hop_irq`
- `dm_sw_irq`
- `dm_hslot_irq`
- `dm_slp_irq`
- `dm_crypt_irq`
- `dm_timestamp_tgt1_irq`
- `dm_timestamp_tgt2_irq`
- `dm_timestamp_tgt3_irq`
- `dm_finetgt_irq`
- `dm_error_irq`
- `dm_fifo_irq`

但现状是这些信号全部接成 `()`，也就是 **wrapper 侧没有把任意 IRQ 暴露给上层 BlackBox/Chipyard**。

### 2. Current Scala integration has MMIO only, no interrupt node

当前 CEVA 集成文件：

- `generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala`

当前实现事实：

- `CevaDmBlackBox` 只暴露了 AHB MMIO 相关端口。
- `CevaDm` 目前只有 `AHBSlaveIdentityNode` / `AHBSlaveSinkNode`。
- `CevaPhase0bInjector` 当前只把设备挂到 `pbus`，没有任何 `IntSourceNode` / `ibus` 连接。

因此，**Phase 0E-A 的最小硬件改动层次应当是 generator + wrapper 暴露单 IRQ，而不是碰 Linux/DT/BlueZ。**

### 3. Existing Chipyard interrupt hookup pattern is already available

当前仓库可读到的 Rocket/Chipyard 中断范式包括：

- `generators/rocket-chip/src/main/scala/subsystem/InterruptBus.scala`
- `generators/chipyard/src/main/scala/Subsystem.scala`
- `generators/rocket-chip/src/main/scala/tile/BusErrorUnit.scala`

其中关键事实是：

- `ibus.toPLIC` 是 PLIC 的中断汇聚出口。
- 同步时钟域设备可通过 `ibus.fromSync := ...` 挂入中断总线。
- 单设备中断源的典型写法是 `IntSourceNode(IntSourcePortSimple(num = 1, resources = device.int))`。
- `BusErrorUnit` 给出了模块内真实驱动方式：
  - `val (int_out, _) = intNode.out(0)`
  - `int_out(0) := irq_bool`

### 4. `dm_sw_irq` bit-level evidence is now anchored in vendor RTL

本轮已经把 `dm_sw_irq` 的关键寄存器位定义锚到真实 RTL：

| Question | RTL-backed answer |
|---|---|
| Trigger register address | `RWDMCNTL` at CEVA DM base + `0x000` |
| Trigger bit | bit `27` (`swint_req`) |
| Delivery mask register | `INTCNTL1` at CEVA DM base + `0x018` |
| Delivery mask bit | bit `3` (`swintmsk`) |
| Status register | `INTSTAT1` at CEVA DM base + `0x01c` |
| Status bit | bit `3` (`swintstat`) |
| Clear/ack register | `INTACK1` at CEVA DM base + `0x020` |
| Clear/ack bit | bit `3` (`swintack`) |
| Trigger mode in current build | **Level-triggered** |
| CPU can trigger directly? | **Yes** |
| Depends on RF/PHY/real Bluetooth traffic? | **No** |

这些结论来自以下只读证据链：

1. `rw_dm_reg.v` 给出 DM 寄存器 word index：
   - `RW_DM_RWDMCNTL_ADDR_CT = 0`
   - `RW_DM_INTCNTL1_ADDR_CT = 6`
   - `RW_DM_INTSTAT1_ADDR_CT = 7`
   - `RW_DM_INTACK1_ADDR_CT = 8`
2. `rw_dm_ahb_if_ahb2reg.v` 把 `haddr & 16'h03FF` 写入 `reg_addr`，再输出 `dm_reg_add = reg_addr[...:1]`。
3. `rw_dm_reg.v` 用 `case (reg_add[...:1])` 做寄存器 decode，因此 **实际 byte offset = localparam index << 2**。
4. 这个换算和当前仓库板级脚本已交叉验证：`VERSION_ADDR_CT = 1` 对应 `0x65000004`，恰好匹配 `scripts/read_ceva_version.sh` 已验证通过的 `CEVA_VERSION_ADDR=0x65000004`。

### 5. `dm_sw_irq` is a pure DM-register path, not an RF/PHY/protocol path

当前真实 top 层路径已经能够直接串起来：

- `rw_dm_reg` 输出 `swint_req` / `swintmsk` / `swintack`
- `rw_dm_top.v` 里 `assign dm_swint = dm_swint_req`
- 同一个 `rw_dm_top.v` 实例化 `rw_cm_int_cntl`，把：
  - `.swint(dm_swint)`
  - `.swintmsk(dm_swintmsk)`
  - `.swintack(dm_swintack)`
  - `.sw_irq(dm_sw_irq)`
  直接连成一条链

因此，`dm_sw_irq` 的触发路径是：

```text
CPU MMIO write RWDMCNTL[27]
  -> rw_dm_reg.swint_req
  -> rw_dm_top.dm_swint_req
  -> assign dm_swint = dm_swint_req
  -> rw_cm_int_cntl.swint
  -> rw_cm_int_cntl.sw_irq
  -> dm_sw_irq output
```

这条路径中没有 RF 控制口、BLE event path、BT frame path、FIFO 数据流或真实协议流量参与，所以它是当前最干净的第一根 IRQ bring-up 候选。

### 6. Important semantic nuance: ack clears IRQ status, not necessarily the source latch

这一点必须单独说明，否则后续验证计划会误判：

1. `rw_dm_reg.v` 的 MMIO 写路径对 `RWDMCNTL[27]` 使用的是：
   - `int_swint_req <= int_reg_dw[27] || int_swint_req;`
   这说明 **CPU MMIO 侧是 write-one-set 语义**。
2. `rw_cm_int_cntl.v` 中：
   - `swintrawstat <= 1'b1` on `swint_rise`
   - `swintrawstat <= 1'b0` on `swintack`
   - `swintstat = swintrawstat & swintmsk`
3. 当前 build 是 level 模式时，`sw_irq = swintstat`。

因此：

- 写 `INTACK1[3]` 可以清掉 **IRQ raw/status/output**。
- 但本轮在 CPU 可见的 MMIO 写路径里 **没有看到 `swint_req` 的直接清零寄存器位**。
- `swint_req` 当前可见的清零路径是：
  - `soft_rst`
  - 外部硬件 update 端口 `swint_req_in_valid / swint_req_in`

这意味着：**CPU 可以直接触发一次 `dm_sw_irq`，并且可以通过 `INTACK1[3]` 清掉 IRQ 输出；但若后续需要“纯 MMIO 无 reset 地重复触发多次”，还需要额外证明 source re-arm 路径。**

### 7. Current PLIC constraint: do not fake an IRQ ID beyond real sources

本地文档和 DTS 备份已明确说明：

- 当前 Linux bring-up 路径里，PLIC 只实现了有限硬件源；过去给 PS SDIO 伪造一个超出 `ndev` 的 IRQ 号，已经验证会导致 TileLink bus hang。
- 因此 Phase 0E-A 不能走“先在 DT/软件里硬填一个 IRQ 号”的路线。
- **必须先让 CEVA 这根中断真正接入 Rocket/PLIC 中断网络，然后再由生成产物给出实际 source ID。**

## Candidate IRQ sources

下表区分“本轮已经在真实 RTL 中锚定的事实”和“其它候选仍未做同等深度证明的项”。

| Candidate IRQ | CPU-triggerable? | Trigger register/bit | Clear/ack register/bit | Level or pulse | Depends on RF/PHY/traffic? | Recommendation |
|---|---:|---|---|---|---|---|
| `dm_sw_irq` | **Yes** | `RWDMCNTL @ base+0x000 [27] swint_req` | `INTACK1 @ base+0x020 [3] swintack` | **Level in current build** | **No** | **Best candidate** |
| `dm_error_irq` | Possibly, but likely by forcing fault path rather than clean SW trigger | 未在本轮做 bit 级展开 | 未在本轮做 bit 级展开 | Unclear | Likely no direct clean CPU-only route | 不推荐；sticky/error 语义不利于最小 bring-up |
| `dm_fifo_irq` | Unclear | 未在本轮做 bit 级展开 | 未在本轮做 bit 级展开 | Unclear | Likely tied to FIFO/runtime state | 不推荐；过于依赖数据通路状态 |
| `ble_error_irq` | Unlikely for pure CPU-only trigger | 未在本轮做 bit 级展开 | 未在本轮做 bit 级展开 | Unclear | Likely yes | 不推荐；带 BLE side effect 风险 |
| `bt_error_irq` | Unlikely for pure CPU-only trigger | 未在本轮做 bit 级展开 | 未在本轮做 bit 级展开 | Unclear | Likely yes | 不推荐；带 BT side effect 风险 |

## Best candidate for Phase 0E

### Recommendation

**Phase 0E-A 最适合的单 IRQ bring-up 候选是 `dm_sw_irq`。**

### Why `dm_sw_irq` is the best fit

现在这个结论已经不再只是“基于命名猜测”，而是有真实 RTL 证据支撑：

1. CPU 可以直接通过 MMIO 写 `RWDMCNTL[27]` 触发它。
2. 这条路径完全位于 DM 寄存器和 common interrupt controller 之间，不依赖 RF/PHY/包流量/真实蓝牙协议活动。
3. 当前 build 已明确定义为 level-triggered，适合后续以 PLIC pending/claim/complete 做最小 bring-up。
4. 它比 `dm_error_irq` / `dm_fifo_irq` 更干净，因为前两者更像运行期状态/错误结果，不适合作为第一根验证 CEVA->PLIC 接线的中断源。

### What is now proven vs. what remains open

当前已经证明：

- `dm_sw_irq` 的 trigger register/bit
- `dm_sw_irq` 的 mask register/bit
- `dm_sw_irq` 的 status register/bit
- `dm_sw_irq` 的 clear/ack register/bit
- `dm_sw_irq` 当前 build 为 level-triggered
- `dm_sw_irq` 可由 CPU 直接经 MMIO 触发
- `dm_sw_irq` 不依赖 RF/PHY/真实蓝牙协议流量

当前仍然开放的问题只有两个：

1. 板级上是否接受“one-shot trigger + ack clear”作为 Phase 0E-B 的第一版验证目标。
2. 若需要“纯 MMIO 连续多次 re-trigger”，是否必须再补 source re-arm 路径，因为目前只看到 `swint_req` 的 W1S 置位和非 MMIO 清零路径。

## Interrupt connection design draft

### Minimal hardware route

建议 Phase 0E 的最小硬件路径是：
```text
CEVA dm_sw_irq
  -> wrapper output (single exported IRQ)
  -> CevaDmBlackBox Bool output
  -> CevaDm IntSourceNode(num = 1)
  -> baseSubsystem.ibus.fromSync
  -> PLIC
  -> Rocket external interrupt path
```

## Phase 0E-A3 addendum

本节 supersedes 上文中关于 re-arm “仍待证明”的旧表述。

- `RWDMCNTL[27]` 在 CPU MMIO 写路径上是 W1S，不是普通 RW bit。
- `INTACK1[3]` 清的是 `swintrawstat/swintstat/sw_irq`，不是直接清 `swint_req` source bit。
- `rw_dm_misc_logic.v` 把 `dm_swint_req_in` 固定为 `0`，并把 `dm_swint_req` 经 `simple_synchro` 回送到 `dm_swint_req_in_valid`；`rw_dm_reg.v` 随后用 hardware update 把 `int_swint_req` 自动回写为 `0`。
- 结论：第一次 trigger + ack 之后，不需要 reset；只要给 source 自动回落留出一个保守窗口，再写一次 `RWDMCNTL[27]`，就能再次产生新的 `swint_rise` / `dm_sw_irq`。

### Where to connect in wrapper / Chipyard

#### 1. Wrapper layer

目标文件：

- `generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v`

Phase 0E 最小修改方向应为：

- 新增一个单比特输出，例如 `ceva_irq_out`。
- 在 wrapper 内部把 `rw_dm_top_tglp_ext` 的 `dm_sw_irq` 接到该单输出。
- 仍保持其它 IRQ 悬空，不在 Phase 0E-A 一次性引出多根中断。

#### 2. BlackBox layer

目标文件：

- `generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala`

最小修改方向应为：

- 在 `CevaDmBlackBox.io` 新增 `Output(Bool())`，例如 `ceva_irq_out`。
- 在 `CevaDmModule` 中接出该 Bool。

#### 3. Diplomatic interrupt layer

同一文件内建议新增：

- `val intNode = IntSourceNode(IntSourcePortSimple(num = 1, resources = device.int))`

模块内驱动方式应比照 `BusErrorUnit`：

```scala
val (int_out, _) = outer.intNode.out(0)
int_out(0) := ceva.io.ceva_irq_out
```

#### 4. Subsystem injection layer

仍在 `CevaBt52Phase0b.scala` 的 `CevaPhase0bInjector` 中，建议把 CEVA 中断接到：

```scala
baseSubsystem.ibus.fromSync := ceva.intNode
```

选择 `fromSync` 的原因是：

- 当前 `CevaDmModule` 里 `ceva.io.ceva_clk := clock`，即默认跟模块时钟同域。
- Phase 0E-A 应优先走最小同步域假设，不额外引入 CDC 复杂度。
- 若后续 CEVA IRQ 被证明来自另一时钟域，再单独加 synchronizer；这不应当在本轮先验引入。

## Level vs pulse evidence

这项现在已经不是“工程假设”，而是被真实 vendor define 明确锚定：

1. `HW/env/CONF/user_defines_dm.v` 中：
   - `RW_DM_INT_MODE_PULSE` 被注释掉
   - `RW_DM_INT_MODE_LEVEL` 被定义
2. `HW/IPs/Src/DM/rw_dm_top/conf/defines.v` 中：
   - `RW_DM_INT_MODE_LEVEL` 继续传播为 `RW_CM_INT_MODE_LEVEL`
3. `HW/IPs/Src/CM/rw_cm_int_cntl/verilog/rtl/rw_cm_int_cntl.v` 中：
   - `sw_irq = swintstat` 在 `RW_CM_INT_MODE_LEVEL` 分支下成立

因此，**当前 build 里的 `dm_sw_irq` 是 level-triggered，不需要再把这件事列为待证据项。**

## Phase 0E-A3: `swint_req` re-arm evidence

这一步现在已经被真实 vendor RTL 闭环，并且直接回答了“第一次 trigger + ack 之后，CPU 能否不经 reset 再写 `RWDMCNTL[27]` 再次触发”的问题。

1. `rw_dm_reg.v` 中：
   - CPU MMIO 写 `RWDMCNTL[27]` 使用 `int_swint_req <= int_reg_dw[27] || int_swint_req;`
   - hardware update 路径使用 `if (swint_req_in_valid) int_swint_req <= swint_req_in;`
2. `rw_dm_misc_logic.v` 中：
   - `assign dm_swint_req_in = 1'b0;`
   - `simple_synchro u_master1_gclk_swint_req(... .srcdata(dm_swint_req), .dstdata(dm_swint_req_in_valid))`
3. `simple_synchro.v` 是两级同步器：
   - `srcdata_ff1_resync <= srcdata`
   - `dstdata_sampled <= srcdata_ff1_resync`
4. `rw_cm_int_cntl.v` 中：
   - `swint_rise = swint & (~swint_ff1)`
   - `swintrawstat <= 1'b1` on `swint_rise`
   - `swintrawstat <= 1'b0` on `swintack`
   - level 模式下 `sw_irq = swintstat`

因此，A3 的 RTL 结论是：

- `RWDMCNTL[27]` 是 W1S 风格，不是普通 RW bit。
- `INTACK1[3]` 清的是 `swintrawstat/swintstat/sw_irq`，不是直接清 `swint_req` source bit。
- `swint_req` 也不是只能靠 reset 才能回到 0；它会经 `rw_dm_misc_logic` 的反馈链自动回落到 0。
- 所以在第一次 trigger 之后，只要已经 ack，并给 `swint_req` 自动回落留出一个保守窗口，CPU 就可以不经 reset 再写 `RWDMCNTL[27]`，再次产生新的 `swint_rise` / `dm_sw_irq`。

## Baremetal / J-Link validation plan

### Validation objective

本轮已有 RTL 证据后，验证目标应收敛为以下五件事：

1. Rocket 侧能看到这根 CEVA IRQ 进入 PLIC。
2. CPU 端能够使能并观察到 pending/claim。
3. CEVA 侧可通过 MMIO 直接写 `RWDMCNTL[27]` 触发 `dm_sw_irq`。
4. CEVA 侧可通过 MMIO 写 `INTACK1[3]` 清掉 `swintstat` 和 IRQ 输出，PLIC pending 随之消失。
5. 若需要“纯 MMIO 连续多次 re-trigger”，当前 RTL 已证明可行；板级上只需在 `INTACK1[3]` 之后给 `swint_req` 自动回落留出一个保守窗口，再次写 `RWDMCNTL[27]`。

### Recommended bring-up order

#### Stage A. J-Link only, CPU interrupt disabled

目标：先证明 CEVA set/ack 会反映到 PLIC pending，而不依赖 trap handler。

建议步骤：

1. 未来 RTL 接线完成后，重新生成 bitstream 并更新硬件。
2. 用 J-Link 连接 Rocket，保持 CPU halt。
3. 通过 MMIO/J-Link 写 `INTCNTL1[3]=1`，确保 `dm_sw_irq` mask 打开。
4. 通过 MMIO/J-Link 写 `INTACK1[3]=1`，清空残留 `swintstat`。
5. 读取 `INTSTAT1[3]` 和 PLIC pending word，确认初始为 0。
6. 通过 MMIO/J-Link 写 `RWDMCNTL[27]=1`。
7. 重新读取 `INTSTAT1[3]`，确认 status 置位。
8. 再读取 PLIC pending word，确认出现单 bit pending。
9. 通过 MMIO/J-Link 写 `INTACK1[3]=1`。
10. 再次读取 `INTSTAT1[3]` 和 PLIC pending word，确认该 bit 消失。

这里建议第一轮板级验证明确按以下寄存器来做：

- trigger: `CEVA_DM_BASE + 0x000`, bit `27`
- mask: `CEVA_DM_BASE + 0x018`, bit `3`
- status: `CEVA_DM_BASE + 0x01c`, bit `3`
- ack: `CEVA_DM_BASE + 0x020`, bit `3`

这一阶段最关键，因为它把问题分解成“CEVA source 是否真的到了 PLIC”，避免把 trap handler、栈、软件初始化和中断路由纠缠在一起。

#### Stage B. Minimal baremetal external-interrupt handler

目标：证明 CPU 能实际响应并 claim/complete。

建议 baremetal 最小流程：

1. 初始化 PLIC：
   - 给 CEVA source 设置非零 priority
   - 为当前 hart context enable 该 source
   - threshold 设为 0
2. 初始化 CPU：
   - M-mode 下打开 `mie.MEIE`
   - 打开 `mstatus.MIE`
3. 先写 `INTCNTL1[3]=1`，再写 `INTACK1[3]=1` 清残留状态。
4. 写 `RWDMCNTL[27]` 触发 `dm_sw_irq`。
5. 在 trap handler 中：
   - 读 `mcause`，确认是 machine external interrupt
   - 读 PLIC claim/complete，拿到 source id
   - 记录 source id 到一个内存位置供 J-Link 查看
   - 写 CEVA `INTACK1[3]`
   - 向 PLIC 写回 complete
6. 返回后检查：
   - claim id 正确
   - `INTSTAT1[3]` 清零
   - pending 消失

#### Stage C. Re-trigger loop, only if repeated MMIO trigger is required

这一阶段现在不再是“补 RTL blocker”，而是可选的板级扩展验证。

原因是当前 RTL 已明确显示：

- `RWDMCNTL[27]` 在 CPU MMIO 写路径上是 `int_reg_dw[27] || int_swint_req`，即 W1S 风格
- `rw_dm_misc_logic.v` 把 `dm_swint_req_in` 固定为 `0`，并把 `dm_swint_req` 经过 `simple_synchro` 回送到 `dm_swint_req_in_valid`
- `rw_dm_reg.v` 在 hardware update 路径里用 `if (swint_req_in_valid) int_swint_req <= swint_req_in;`，因此 `swint_req` 会自动回落为 `0`
- `INTACK1[3]` 清的是 `swintrawstat/swintstat/sw_irq`，不是直接清 source bit

因此，若需要纯 MMIO 连续多次触发，建议板级步骤为：

1. 写 `INTCNTL1[3]=1`。
2. 写 `INTACK1[3]=1`，清残留 raw/status。
3. 写 `RWDMCNTL[27]=1`。
4. 观察 `INTSTAT1[3]=1` / PLIC pending 置位。
5. 写 `INTACK1[3]=1`。
6. 给 `swint_req` 自动回落留出一个保守等待窗口。
7. 再写一次 `RWDMCNTL[27]=1`。
8. 再次观察 `INTSTAT1[3]` / PLIC pending 重新置位。

如果第二次没有再次出 pending，第一优先级应当怀疑：

- 第二次 write 发生得太早，source 还没经反馈链回落到 0。
- `INTACK1[3]` 没有真正把 `swintrawstat` 清掉。
- PLIC claim/complete/pending 的观察顺序有误。

### Important caution on IRQ numbering

Phase 0E-A 不应在 bring-up 前先假设最终 IRQ 号。

理由：

- 当前文档已证明：给 PLIC 伪造超出 `ndev` 的 source id 会直接挂死 hart。
- CEVA 接入后，实际 source id 必须由生成后的硬件/headers/DT 结果决定。
- 因此 baremetal/J-Link 验证脚本里应当把“CEVA source id”作为 **生成后确认的值**，而不是现在在计划阶段写死。

## Final recommendation

### Recommended Phase 0E-A source

- **Use `dm_sw_irq` as the only IRQ connected in Phase 0E-A.**

### Why not the others first

- `dm_error_irq`: 触发路径不干净，sticky/error 语义容易把 bring-up 变成“故障注入”问题。
- `dm_fifo_irq`: 更像运行期队列状态，不适合做第一根中断。
- `ble_error_irq` / `bt_error_irq`: 太容易引入协议/链路/射频/时序副作用。

### Remaining items before Phase 0E-B execution

位级证据和 re-arm 语义都已经补齐，不再是 blocker。当前剩余项只包括：

1. 接线完成后，由生成产物确认实际 CEVA PLIC source id。
2. 决定 Phase 0E-B 的验收标准是否只要求“one-shot trigger + ack clear”，还是顺手把 repeated re-trigger loop 也纳入脚本。
3. 如果把 repeated re-trigger loop 纳入板级验收，在脚本里对 `INTACK1[3]` 之后加入一个保守等待窗口，再执行第二次 `RWDMCNTL[27]` 写入。

## Phase 0E-A conclusion

本轮在不改 RTL、不改 wrapper、不改 Linux/DT/driver 的前提下，已经把 Phase 0E 的最小单 IRQ bring-up 方向收敛为：

- **候选源：`dm_sw_irq`**
- **位级证据：`RWDMCNTL+0x000[27]` 触发，`INTCNTL1+0x018[3]` mask，`INTSTAT1+0x01c[3]` status，`INTACK1+0x020[3]` ack**
- **电平语义：当前 build 明确定义为 level-triggered**
- **触发属性：CPU 可直接通过 MMIO 触发，不依赖 RF/PHY/真实蓝牙协议流量**
- **re-arm 语义：`RWDMCNTL[27]` CPU 侧是 W1S，`INTACK1[3]` 清 raw/status/output，`swint_req` 通过 `rw_dm_misc_logic` 自动回落，因此可不经 reset 再次 MMIO 触发**
- **接线层：`rw_dm_top_phase0b_real_wrapper.v` + `CevaBt52Phase0b.scala`**
- **中断总线路径：`IntSourceNode(num = 1)` -> `baseSubsystem.ibus.fromSync` -> `PLIC`**
- **验证方式：先 J-Link 轮询 `INTSTAT1`/PLIC pending，再 baremetal trap claim/complete**

当前 A3 已闭环：`swint_req` 的 re-arm 语义在 RTL 上已经得到确认，不再是 Phase 0E-B 的设计 blocker。后续若要做纯 MMIO 多次重复触发，板级上只需在 ack 后加入一个保守等待窗口，再次写 `RWDMCNTL[27]` 即可。