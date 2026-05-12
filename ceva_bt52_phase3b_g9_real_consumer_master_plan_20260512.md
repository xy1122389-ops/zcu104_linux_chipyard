# CEVA BT5.2 Phase 3B-G9 真实 Consumer 总体规划

## 1. 执行决策

当前项目路线是 Route C。

在 Route C 通过之后，唯一允许落地的架构是 Route B。

Route A 被否决。直接把 H4TL 或完整 vendor runtime 移植进 Linux 内核不是本项目路线。

Route D 被否决。继续沿着当前仅有 EM 加 SWINT 的 Linux-only 路径推进，并假设只靠更多 MMIO 或 IRQ 调优就能把它变成真实控制器，也不是本项目路线。

一句话的项目结论是：把真正的 vendor runtime 集成为一个外部 sidecar 固件上下文，Linux 保持为面向主机的 shim，并把 Linux 的 HCI 流量桥接到 vendor runtime；不要再在当前镜像里继续追一个并不存在的 consumer。

## 2. 当前已被证明的事实

1. 当前 Linux 驱动会发布命令，但不会引导 vendor runtime。在 [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c) 中，`ceva_bt_send_frame()` 会把 HCI 命令写入从 EM word 64 开始的区域，把 EM word 72 置为 ready，并拉起 `DM_SWINT_REQ`。RX 路径只会等待 EM word 73 以及从 EM word 96 开始的区域变为 ready。`ceva_bt_open()` 和 `ceva_bt_setup()` 都不会启动任何 vendor consumer。

2. 当前启动流程只会启动 Linux 驱动和 userspace smoke helper。在 [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init) 中，流程是 `insmod /lib/modules/ceva_bt52.ko`，等待 `/sys/class/bluetooth/hci0`，然后运行 `/sbin/phase25_user_hci_smoke`。这里没有 vendor runtime loader，没有 sidecar launcher，也没有 firmware bootstrap hook。

3. 当前 payload 重建路径只会打包 Linux 侧资产。在 [rebuild_payload.sh](rebuild_payload.sh) 中，被 staging 的产物是 `bluetooth.ko`、`ceva_bt52.ko`、`phase25_user_hci_smoke`、`stage_mark`、initramfs、Linux `Image` 以及 OpenSBI `fw_payload.bin`。这里没有任何 vendor runtime 源码、blob、archive 或 helper image 被打进 payload。

4. 当前 GDB 脚本仅用于观察 Linux 侧路径。[scripts/linux_boot_phase2_launch.gdb](scripts/linux_boot_phase2_launch.gdb) 会清空 breadcrumb 和 EM 窗口。[scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb) 会读取 init marker、P3BD 槽位、`DM_INTSTAT1`、`DM_INTACK1`、`EM[64]`、`EM[72]`、`EM[73]` 和 `EM[96..]`。它们不会启动 controller runtime。

5. 工作区里集成的 CEVA collateral 是 RTL，不是 runtime software。[generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list) 是一个硬件 filelist，指向 vendor hardware tree 下的 Verilog RTL。它不是软件纳入路径。

6. 外部 vendor runtime 是一个完整的软件栈，拥有自己的初始化、调度器、传输抽象以及硬件驱动。直接证据如下：

- 在外部 vendor 的 `rwip.c` 中，`rwip_init()` 会调用 `ke_init()`、`ke_mem_init()`、`h4tl_init()`、`hci_init()`、`rwbt_init()`、`rwble_init()`、`rwip_driver_init()`，最后再调用 `rwip_reset()`。这是一条 runtime bootstrap 链，而不是一个辅助函数。
- 在外部 vendor 的 `h4tl.c` 中，H4 传输 RX 最终会走到 `hci_cmd_received()`，TX 则使用外部接口回调表。
- 在外部 vendor 的 `hci.c` 中，`hci_send_2_host()` 是回到主机侧的事件出口路径。
- 在外部 vendor 的 `rwip.h` 中，`struct rwip_eif_api` 定义了诸如 read 和 write 等传输回调。在外部 vendor 的 `arch_main.c` 中，`rwip_eif_get(0)` 返回 `uart_api`，这证明 stock runtime 预期存在一个平台传输提供者和一个独立的平台层。
- 在外部 vendor 的 `rwip_driver.c` 中，`rwip_driver_init()` 会执行 `ip_rwdmcntl_master_soft_rst_setf(1)`，然后通过 `ip_intcntl1_set(...)` 使能默认的公共中断 `FIFO`、`CRYPT`、`SW` 和 `SLP`。这属于 runtime 自己负责的硬件 bring-up。
- 在外部 vendor 的 `mailbox.h` 和 `ceva_link_mailbox.h` 中，已经存在平台 mailbox 原语，但当前 Linux payload 流程里没有任何地方会把该平台层纳入并启动。

7. 更早的 Phase 0F software-init 研究已经指向了同一条 runtime 链。参见 [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md)。

## 3. Phase 2.5 证明了什么，以及没有证明什么

Phase 2.5 已经证明了以下事实：

- Linux 可以创建 `hci0` 并暴露一个面向主机的控制平面。
- Userspace 可以通过 Linux 驱动路径发送 HCI 命令。
- 驱动会把命令写入 EM，置位 command-ready 标志，并拉起 SWINT。
- Breadcrumb 和 GDB 抓取可以证明命令已被发布以及中断状态已被观察到。
- 一条 synthetic response 路径可以让 Linux 主机侧看起来像是活着的。

Phase 2.5 没有证明以下事实：

- 没有证据证明真实的 CEVA vendor runtime 已经存在于镜像中。
- 没有证据证明任何 runtime 在这个镜像上执行了 `rwip_init()` 或 `rwip_reset()`。
- 没有证据证明任何 runtime 通过 `hci_cmd_received()` 或等价的 vendor ingress 路径消费了已发布的 Reset 命令。
- 没有证据证明 `hci_send_2_host()` 或其他真实 vendor egress 路径已经回接到 Linux。
- 没有证据证明当前的 EM 加 SWINT 边界，在另一侧连接着一个真实 consumer。

## 4. 为什么当前仅有 EM 加 SWINT 仍然不够

当前 Linux 路径停在命令发布这一步。它把字节写进 EM，然后拉起一个 software interrupt。这只是一条主机到 consumer 的边界，不是 consumer 本身。

当前 RX 路径同样是被动的。它等待 EM event-ready 状态，然后把数据向上传递。它不会生成真实事件。如果没有一个正在运行的 vendor consumer，EM event-ready 永远不会变成真实的控制器响应。

这意味着继续做更多 Linux 侧局部修补，已经不再是根因路径。IRQ 复查、mask 调优或者 EM 轮询，也许能改善观测效果，但它们无法凭空创造缺失的 vendor runtime。

## 5. 为什么否决“直接把 H4TL 或 vendor runtime 放进 Linux 内核”

否决 direct H4TL-in-kernel 是出于结构性原因，而不是因为某一个 hook 缺失。

1. `h4tl` 不是一个独立 parser。它依赖 `rwip_eif_api`、`ke_event`、`ke_malloc`、传输流控以及 vendor scheduler model。
2. `rwip_init()` 和 `rwip_reset()` 依赖于 vendor runtime 内部的队列、heap 初始化、timer、全局中断宏以及硬件驱动所有权。
3. `arch_main.c` 显示 stock runtime 是围绕一个平台主循环和一个类似 `uart_api` 的传输提供者来编写的，而不是围绕 Linux HCI-driver 回调来编写的。
4. `rwip_driver_init()` 拥有控制器 reset 和 interrupt-enable 的时序所有权。把整个生命周期折叠进当前 Linux 驱动，将会是一次大型平台移植，而不是一次狭义的传输集成。
5. 当前 Linux 驱动是刻意做薄且面向主机的。把它变成整个 vendor controller runtime 的执行宿主，会把两套不同的调度和中断模型耦合在一起，并在尚无真实证据之前就显著扩大 diff 面。

因此，本项目路线不是把 H4TL 直接放进 Linux 内核。

## 6. 推荐路线

后续项目统一采用以下路线定义：

- Route A：把 H4TL 或 vendor runtime 直接移植进 Linux 内核，并让当前驱动直接调用它。
- Route B：Linux 保持为面向主机的 shim，把真实 vendor runtime 运行在一个外部 firmware 上下文中，并在 Linux 与 vendor runtime 之间桥接命令和事件。
- Route C：在 vendor runtime 资产、build inclusion、bootstrap path 和 bridge seam 都真正落地之前，停止在当前镜像上继续追真实 Reset。
- Route D：继续把当前仅有 EM 加 SWINT 的 Linux-only 路径当成最终路线推进，并假设缺失的 consumer 可以仅靠 driver 或 MMIO 工作自己出现。

决策是：现在走 Route C，下一步落到 Route B。Route A 和 Route D 都被否决。

这意味着，项目的下一阶段不是再跑一次 Reset 重试。真正的下一阶段是冻结 vendor-runtime 资产，并规划和实现 sidecar bootstrap。

## 7. 对“选 H4 还是选我们自己的方案”的最终回答

系统路线不是 direct H4TL。

系统路线也不是当前仅有 EM 加 SWINT。

系统路线是：桥接到真实 vendor runtime。

更具体地说：

- 真正的 consumer 必须是 vendor runtime，而不是我们自己造的控制器栈。
- Linux 可见边界应该继续保持为我们自己的 bridge boundary，而不是字面意义上的外部 UART H4 契约。
- 当前 EM 加 SWINT 路径只应被保留为第一版 bridge transport contract，因为它已经存在且可观测。
- 只有在它是启动 vendor stack 的最低改动方案时，H4TL 才可以作为 sidecar 内部实现细节保留下来；但它不是外部架构答案，也不是 Linux 边界。

## 8. Runtime 放置决策

Vendor runtime 不应该驻留在 Linux 内核中。

Vendor runtime 也不应该是一个伪装成控制器的 Linux userspace helper。

被选定的放置方式是：一个独立的 baremetal sidecar 或 firmware context，负责拥有：

- `rwip_init()` 和 `rwip_reset()`
- `rwip_driver_init()` 以及 CEVA 硬件 bring-up
- vendor 的 scheduler、timer、heap 和 interrupt ownership
- 从 bridge 指向 `hci_cmd_received()` 的 ingress
- 从 `hci_send_2_host()` 回到 Linux 的 egress

Linux 继续负责：

- 向 userspace 暴露的主机侧 HCI device
- Linux 侧的 bridge TX 和 RX endpoint
- 启动编排和验证工具链

## 9. 最低缺失资产

在能够声称“真实 consumer 已存在”之前，至少必须补齐以下资产：

1. 一套获批的 vendor runtime 资产，足以构建或打包真实控制器 runtime。最低限度必须包含 `rwip`、`h4tl`、`hci`、`ke`、`co`、platform 以及 `rwip_init()` 和 `rwip_driver_init()` 所需的寄存器访问部分。
2. 一个 bridge transport adapter，用来替代 stock vendor 对 `uart_api` 和 `rwip_eif_get()` 的假设，使其改为所选 Linux-to-sidecar transport。
3. 一套 sidecar build rule 和 packaging rule，用于把该 runtime 放进最终发布的镜像表面。
4. 一个 boot 或 launch hook，确保 sidecar 在 Linux smoke test 期待真实控制器响应之前就已启动。
5. 一条从 `hci_send_2_host()` 回到 Linux 驱动 RX boundary 的 event egress adapter。
6. Sidecar 可见的 instrumentation marker，用于独立证明 bootstrap、ingress 和 egress，而不必依赖一次完整 Reset PASS。

## 10. 提议架构

Bridge-first 架构如下：

```text
userspace HCI RAW or USER socket
  -> Linux ceva_bt52 host shim
  -> bridge TX using current EM command window and SWINT doorbell first
  -> sidecar transport adapter
  -> vendor ingress at hci_cmd_received or an internal unchanged h4tl path
  -> vendor runtime rwip or hci or rwbt or rwble core
  -> vendor egress at hci_send_2_host
  -> sidecar bridge RX using current EM event window and SWINT doorbell first
  -> Linux rx_work and hci_recv_frame
  -> userspace result
```

这里最重要的决策是：当前的 EM words 64、72、96、73 以及 SWINT 只保留为第一版桥接契约，因为这样可以最小化 Linux 改动并避免立刻触碰 RTL。它们并不是对“真实 consumer 究竟在哪里”的最终解释。

## 11. 后续五个阶段

### G9-A. 冻结 Vendor 资产与 Bridge 契约

目标：在任何板级工作开始之前，冻结 vendor runtime 的精确子集、执行上下文以及 bridge seam。

实现面：

- 导入或引用 sidecar bootstrap 所需的精确 vendor 文件或已批准 blob 集
- 定义 ingress 是直接走 `hci_cmd_received()`，还是走建立在模拟 `rwip_eif_api` transport 之上的内部 `h4tl`
- 优先使用当前 EM 加 SWINT 布局，定义精确的 Linux-to-sidecar TX 和 RX 契约
- 定义谁是启动 sidecar 的 boot owner

仅当以下项目都以文件名、函数名和 ownership 的形式被冻结时，才算 PASS：

- vendor 资产清单
- 将运行 sidecar 的执行上下文
- ingress seam
- egress seam
- build 与 packaging owner
- launch hook

只要其中任何一项仍然停留在猜测层面，就算 FAIL。

如果 licensing 或 redistribution 规则阻止资产落地，则 STOP。

### G9-B. 证明 Sidecar 已被引导并进入镜像

目标：把 sidecar 纳入正式镜像流，并证明在 Linux smoke 路径请求真实响应之前，它已经启动。

实现面：

- 把 sidecar packaging 纳入 payload 流
- 把 launch hook 纳入 boot 流
- 增加 sidecar start、pre-init、post-`rwip_init()` 和 post-`rwip_driver_init()` 的 stage marker

如果一次 boot capture 能证明以下事实，则 PASS：

- sidecar binary 存在于最终镜像中
- sidecar start hook 已执行
- 已到达 `rwip_init()`
- `rwip_driver_init()` 的副作用可见，或 sidecar marker 能证明其完成

如果 sidecar 不在镜像里，或从未启动，则 FAIL。

如果不存在 Linux host path 之外的可运行执行上下文，则 STOP。

### G9-C. 证明 Ingress Bridge

目标：证明 Linux 发布的一个 Reset 命令确实到达了真实 vendor ingress 路径。

实现面：

- 把当前 Linux TX 路径桥接到 sidecar ingress
- 除非 transport shim 被证明不可行，否则优先保留当前 EM 加 SWINT 传输
- 在 sidecar ingress seam 周围增加 opcode marker

当 opcode `0x0C03` 能在选定 ingress seam 处被观察到并被 sidecar 消费，而且没有 synthetic responder 参与时，才算 PASS。

如果 Linux 仍然发布 Reset，但 sidecar 从未看到它，则 FAIL。

如果选定 ingress seam 需要一次完整的 vendor runtime 内核移植，而不是一个桥接适配器，则 STOP。

### G9-D. 证明 Egress Bridge

目标：证明一个真实的 vendor-generated event 能到达 Linux HCI device。

实现面：

- 把 `hci_send_2_host()` 或选定的 sidecar egress seam 回接到 Linux RX boundary
- 把 sidecar 输出转换成当前 Linux 驱动的 RX 契约
- 仅把驱动中的 synthetic code 作为默认关闭的 fallback instrumentation 保留

当 Linux 用户态 smoke 收到来自 vendor runtime 的真实、非 synthetic Reset 结果时，才算 PASS。真实的 Command Complete 是首选 PASS。真实 vendor 产生的 status 或 error event 也可以作为中间 PASS，但前提是它确实证明了 vendor egress path 已经活着。

如果 sidecar 已消费命令，但没有任何真实事件到达 Linux，则 FAIL。

如果 event egress path 逼迫 Linux HCI 架构进行侵入式重构，而不是一个狭义 bridge adapter，则 STOP。

### G9-E. 清理真实路径并做回归

目标：冻结真实 consumer 路径，并去掉对 synthetic success 的依赖。

实现面：

- 在默认验证路径里关闭 synthetic completion
- 仅保留现场调试所需的 observation marker
- 把验证范围从 Reset 扩展到至少一个额外的低风险命令，比如 Read Local Version

当重复启动都能稳定得到真实 vendor 对 Reset 以及至少另一个命令的响应，并且完全不再依赖 synthetic completion 时，才算 PASS。

如果仍然只有一次性成功，或仍依赖 synthetic-assisted success，则 FAIL。

如果 bridge 只成功一次，随后却破坏了更广泛的 Linux boot 或 controller state machine，则 STOP。

## 12. 未来最可能变更的文件

在后续执行阶段中，最可能被修改的现有工作区文件如下：

- [rebuild_payload.sh](rebuild_payload.sh)
- [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init)
- [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c)
- [scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb)
- [scripts/linux_boot_phase2_launch.gdb](scripts/linux_boot_phase2_launch.gdb)

Sidecar build、sidecar packaging、sidecar stage marker 以及 vendor 资产清单很可能还需要新增文件，但这些名字应该在 G9-A 中被正式冻结，而不是在这里先猜。

## 13. 现在还不能碰的文件和区域

在 G9-A 和 G9-B 通过之前，不要为了真实 consumer 路线去触碰以下区域：

- `fpga-shells/**`
- `generated-src/**`
- Vivado 输入、输出以及 RTL collateral
- G8 中已明确不提交的受保护本地文件：[linux-bringup/dtb/chipyard-zcu104-fedora.dtb](linux-bringup/dtb/chipyard-zcu104-fedora.dtb)、[linux-bringup/dtb/chipyard-zcu104-fedora.dts](linux-bringup/dtb/chipyard-zcu104-fedora.dts) 以及 [scripts/run_ps_ddr_init.tcl](scripts/run_ps_ddr_init.tcl)

所选路线假定先做软件集成。在还没有 software bootstrap proof 之前就重新打开 RTL，只会扩大范围而不会带来证明收益。

## 14. 明确禁止的动作

本计划明确禁止以下动作：

- 不要继续把 Linux-only 的 MMIO 或 IRQ 修补当成缺失 consumer 的替代方案
- 不要把 `h4tl` 或整个 vendor runtime 作为第一步移植进 Linux 内核
- 不要构造一个伪装成控制器 runtime 的 Linux userspace helper
- 在没有 sidecar bootstrap proof 之前，不要声称当前镜像已经具备真实 Reset 路径
- 在软件侧 bootstrap 和 bridge contract 尚未因具体原因失败之前，不要碰 RTL，也不要运行 Vivado
- 不要提交生成出来的 payload 产物或本地调试输出
- 对于本次规划阶段本身：不跑板、不重建 payload、不改驱动、不改 RTL，也不跑 Vivado

## 15. 主要风险

1. Vendor 资产审批风险。该路线依赖于以合法且可执行的方式纳入真实 vendor runtime 子集。
2. 执行上下文风险。该路线需要一个位于当前 Linux-host shim 行为之外的 runtime context。
3. Transport-shim 风险。Bridge adapter 必须满足 vendor 传输与调度假设，同时不能膨胀成一次完整内核移植。
4. Interrupt ownership 风险。Sidecar 必须能够拥有 CEVA runtime bring-up，同时不能破坏 Linux 可见边界。
5. Scope-creep 风险。如果 H4TL 内部细节泄漏到系统边界之外，bridge 可能会意外退化回 Route A。

## 16. 停止条件

如果出现以下任一情况，应立即停止该路线并升级处理：

- 无法落地或引用获批的 vendor runtime 资产集
- 不存在可以承载 sidecar runtime 的独立执行上下文
- 想要构建 bridge，结果却等价于把整个 vendor runtime 重新移植进 Linux 内核
- 第一个可行 transport 就要求进行足够大的 RTL 或硬件分区变更，从而使 software-first 计划失效
- vendor runtime bootstrap 只有在破坏 Linux 主机侧 HCI ownership model 的前提下才能成功

## 17. 面向管理层的最终回答

如果管理层问我们现在到底在走哪条路线，回答是：

我们不会继续追更多 Linux 侧 CEVA MMIO 调整，也不会把 H4TL 移植进内核；我们将转向 vendor-runtime sidecar bridge 架构，因为当前镜像已经证明了命令发布成立，但它并不包含真实 consumer。