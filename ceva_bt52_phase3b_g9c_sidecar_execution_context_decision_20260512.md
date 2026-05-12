# CEVA BT5.2 Phase 3B-G9C Sidecar 执行上下文决策

## 1. 推荐结论

推荐执行上下文是独立 firmware context，第一版工程实现以 baremetal sidecar skeleton 为起点，最终目标是 vendor controller runtime 独立拥有 PC、stack、heap、interrupt、timer 和 CEVA IP bring-up。Linux 继续只作为 host-facing HCI shim。

如果 vendor 架构提供 CEVA 内部 controller runtime context 或官方 firmware blob 入口，则该路径优先级高于 Rocket-side baremetal sidecar。当前审计尚未证明此内部执行上下文已经可用，因此第一版代码计划按外部 sidecar 设计。

## 2. 候选上下文评估

| 候选 | 决策 | 理由 |
|---|---|---|
| Linux kernel 内部 | 否决 | 会把 vendor scheduler、heap、task、timer、interrupt ownership 塞进 `ceva_bt52.c`，退化为 Route A。 |
| Linux userspace helper | 否决为 controller，允许作离线工具 | userspace helper 可以做 build/debug/packet injector，但不能伪装成 controller runtime，也不能拥有 CEVA IP interrupt 时序。 |
| Rocket 同核 baremetal sidecar | 不作为第一推荐 | 与 Linux 共用同一 hart/PC 不成立；除非设计成 Linux 前的短生命周期 loader，否则无法与 Linux 同时运行。 |
| 独立 firmware context | 推荐 | 满足独立 PC/stack/heap/interrupt/timer，最接近 vendor runtime 假设。 |
| CEVA 内部控制器 runtime context | 最高优先级但未证明 | 如果 vendor 提供内部 firmware CPU 或已编译 controller image，这是最接近原厂架构的路线。需要 vendor 资料确认。 |

## 3. 必须回答

### 3.1 sidecar 有没有独立 PC / 执行流

最终真实 runtime 必须有独立 PC 和执行流。没有独立执行流，就无法同时满足 Linux 继续运行和 vendor runtime 调度循环继续运行。

第一版 skeleton 的目标是证明这个执行流存在：启动后写 `SIDECAR_START`、`SIDECAR_PRE_RWIP_INIT` 等 marker，并保持在可观察 loop 或进入 runtime main loop。

### 3.2 当前系统是否有第二核 / 裸机区域可承载

Open Blocker: 当前 `RocketZCU104Phase0bConfig` 的可用 hart 数和 hart1 可启动状态需要由配置、DTB 和历史 bringup 证据共同确认。已有历史线索显示双核路径存在阻塞风险，因此不能把 hart1 当作已验证资源。

裸机区域同样需要 reserved memory 保护。候选地址可以规划，但在修改 DTB 或 boot memory map 前不能声称安全。

### 3.3 是否需要 Linux 启动前先运行 sidecar

真实 Reset/RLV 路径建议 sidecar 在 Linux userspace smoke 之前启动。更稳妥的顺序是：

```text
OpenSBI or launch hook
  -> load sidecar image into reserved memory
  -> start sidecar execution context
  -> sidecar writes bootstrap markers
  -> Linux boots and loads host-facing driver
  -> Linux sends HCI Reset over EM/SWINT bridge
```

如果 sidecar 是独立 CEVA internal context，也必须在 Linux HCI smoke 前完成 `rwip_init()` 和 bridge ready。

### 3.4 是否需要 OpenSBI 参与

需要规划 OpenSBI 参与，但第一版代码可以先通过 launch script proof 验证 image/marker。最终可交付路线应由 OpenSBI 或更早 boot owner 负责：

- 保留 sidecar memory。
- 加载 sidecar image。
- 释放 sidecar execution context。
- 把 sidecar marker 区和 bridge 区清零。

如果依赖 GDB/J-Link 手动加载才能运行，只能算开发 proof，不能算产品化 boot path。

### 3.5 是否需要新的 payload layout

需要。当前 payload 只包含 Linux `Image`、initramfs、DTB 和 Linux-side modules/helper。未来必须新增：

- sidecar source/build output staging 区。
- sidecar image load address。
- sidecar stack/heap 区。
- marker 区。
- reserved-memory 或等价内存保护。
- launch/capture 脚本对 sidecar image 和 marker 的支持。

## 4. 推荐执行上下文

G9-C 推荐：独立 firmware context，启动 owner 为 OpenSBI 或早期 launch hook；第一刀代码实现一个 baremetal sidecar skeleton，不接 vendor runtime，只证明 sidecar image、PC、stack、marker 写入和停留 loop。

推荐最小结构：

```text
sidecar/ceva_bt52_sidecar/
  start.S
  linker.ld
  marker.h
  main.c
  Makefile
```

第一版行为：

```text
_start
  -> setup stack
  -> zero bss
  -> write SIDECAR_START
  -> write SIDECAR_PRE_RWIP_INIT
  -> stay in sidecar_loop or call skeleton_main
```

## 5. 备选执行上下文

备选 1: CEVA vendor-provided firmware blob/context。

- 适用条件：vendor 提供可加载 controller image、entry address、mailbox/EM contract 和寄存器访问 ownership 文档。
- 优先级：如果资料齐全，超过自建 Rocket-side sidecar。

备选 2: OpenSBI-managed secondary hart。

- 适用条件：DTB、SBI、hardware config 已证明 hart1 可用且不会破坏 Linux。
- 风险：历史 dualcore bringup 风险高，不能作为无条件默认。

备选 3: Linux 前短生命周期 loader。

- 适用条件：只用于初始化 CEVA runtime image 或拷贝参数，不承载长期 runtime。
- 限制：不能处理 Linux 后续 HCI 命令，因此不能作为最终 real consumer。

## 6. 否决项

- 不把 vendor runtime 放进 Linux kernel。
- 不把 fake Linux userspace helper 当 controller。
- 不用 BlueZ scan/pair/connect 证明 sidecar。
- 不因 sidecar 未规划完成就改 RTL/Vivado。
- 不把 GDB-only 手工启动作为最终交付路径。

## 7. 第一版最小验证方式

第一版验证只需要证明 execution context，不证明 Bluetooth：

1. sidecar image 在 build output 中存在。
2. launch/boot flow 会把 image 放到候选地址。
3. sidecar `_start` 写 `SIDECAR_START`。
4. sidecar `main` 写 `SIDECAR_PRE_RWIP_INIT`。
5. Linux 仍能启动到当前 baseline，未被 sidecar memory 覆盖。

不调用 `rwip_init()`，不修改 Linux driver，不修改 RTL。

## 8. STOP 条件

- 无法获得独立 PC/执行流。
- 无法为 sidecar 预留不被 Linux 覆盖的内存。
- 启动 sidecar 必须破坏现有 Linux boot baseline。
- 唯一可行实现要求把 vendor runtime 放入 Linux kernel。
- vendor 确认 runtime 只能在未暴露的内部 CPU 上运行，但内部 CPU firmware 资产不可用。
