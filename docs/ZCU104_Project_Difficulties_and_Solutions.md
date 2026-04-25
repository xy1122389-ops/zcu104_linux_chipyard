# ZCU104 PL Rocket FPGA Linux Bringup — 全程困难与解决方式详细总结

> 时间跨度：2026-03-20 ～ 2026-04-25  
> 目标：在 ZCU104 FPGA 上的 RISC-V Rocket 软核（50MHz）中完整启动 Fedora Linux 进入 systemd[1]  
> 最终里程碑：2026-04-24 `fedora_v3fix3` run 达成 systemd[1] 完整用户态启动 ✅

---

## 目录

1. [硬件 & JTAG 调试层](#1-硬件--jtag-调试层)
2. [内存初始化 & DDR 一致性](#2-内存初始化--ddr-一致性)
3. [固件加载通道 (XSDB / GDB)](#3-固件加载通道-xsdb--gdb)
4. [OpenSBI / RISC-V M 态 Bug](#4-opensbi--risc-v-m-态-bug)
5. [Linux 内核启动阶段](#5-linux-内核启动阶段)
6. [SD 卡路径 — SPI-SD (失败路径)](#6-sd-卡路径--spi-sd-失败路径)
7. [SD 卡路径 — J100 SDHCI PIO (成功路径)](#7-sd-卡路径--j100-sdhci-pio-成功路径)
8. [DMA 不可行 (永久结论)](#8-dma-不可行-永久结论)
9. [Initramfs & Init 阶段](#9-initramfs--init-阶段)
10. [SiFive UART 驱动竞争条件](#10-sifive-uart-驱动竞争条件)
11. [Bitstream & Vivado 构建](#11-bitstream--vivado-构建)
12. [工具链 & 脚本工具问题](#12-工具链--脚本工具问题)
13. [完整成功链总结](#13-完整成功链总结)

---

## 1. 硬件 & JTAG 调试层

### 1.1 J-Link JTAG 接线错误
**困难**：初期将 JTAG 接到 J87 (PMOD1)，实际应接 J55 (PMOD0)。J87 是 UART。  
**解决**：锁定为 J55，引脚映射：G6=TDI, H6=TMS, J6=TCK, J7=TDO，LVCMOS33。此后**永不更改**。

### 1.2 JTAG 链争用 (XSDB + J-Link 同时占用)
**困难**：XSDB (`hw_server`) 与 J-Link GDB Server 同时访问 JTAG 链导致设备无响应、IDCODE 不可读、TDO 恒高。  
**解决**：调试流程严格串行化——先 XSDB 完成 PS 初始化，再 J-Link 接管 PL Rocket。不可并行。

### 1.3 板级"硬卡死"状态
**困难**：执行 `psu_init` 时出现 `Memory write error at 0xFF180090. AP transaction timeout`，之后 J-Link 显示 `TotalIRLen = ?`、无设备。软件 TCL 恢复脚本均无效。  
**解决**：唯一可靠恢复手段是**手动断电重启**板子，再重新走全套初始化流程。

### 1.4 Dupont 跳线松动导致 TDO 恒高
**困难**：J55 JTAG 杜邦线接触不良，J-Link 报告 "TDO constant high"，误以为 Rocket 未通电。  
**解决**：重新压实 J55 PMOD 排针连接，复现稳定。

### 1.5 JLink GDB Server 僵死 (kill -9 后)
**困难**：WSL 侧 `kill -9 gdb` 进程后，Windows JLink GDB Server 保留了半建立的 TCP 连接，拒绝新连接。  
**解决**：从 WSL 执行 PowerShell 重启 JLinkGDBServerCL 进程：
```bash
powershell.exe -Command 'Stop-Process -Name "JLinkGDBServer" -Force ...; Start-Process ...'
```

---

## 2. 内存初始化 & DDR 一致性

### 2.1 DDR 未清零导致 SLUB 随机崩溃
**困难**：SLUB 分配未初始化页面，返回含随机旧数据的内存，导致内核在 `kdevtmpfs`、`strscpy`、`dup_task_struct` 等处非确定性崩溃。  
**解决**：Phase 1 在固件加载**前**，通过 Rocket 核心运行 8 字节 store 循环，对全 DDR 2GB（跳过固件区）清零：
```raw
sd zero,0(a0); c.addi a0,8; blt a0,a1,loop; c.ebreak
```
2GB 清零约 30 秒（50MHz Rocket）。

### 2.2 J-Link 检测不到 ebreak 停机
**困难**：Rocket 硬件 `ebreak` 不触发 J-Link halt，DDR 清零循环运行后无法自动停止。  
**解决**：改用 `hbreak *<ebreak_addr>` 硬件断点，J-Link 可检测到。

### 2.3 SBA 写绕过 L2 缓存（核心一致性 Bug）
**困难**：GDB `restore` 通过 SBA (System Bus Access) 把固件写入 DDR，但完全绕过 Rocket L2 Cache。若 L2 中还有旧的 clean zero 行，Rocket 读固件时命中 L2 得到全零，而非 DDR 中正确的固件内容。症状：`strlen` 找不到 `\0`，CPU 读几亿字节后崩溃。  
**解决**：
1. Phase 1 DDR 清零循环按顺序地址写入，将 L2 中旧的固件区脏行全部 evict 到 DDR
2. Phase 1 后，L2 只含最后 512KB 地址的零行（高地址），不与固件区重叠
3. SBA 恢复固件后，Rocket 读固件会 miss L2，直接从 DDR 拿到正确数据 ✓

### 2.4 XSDB `mwr -force -bin` 32MB 偏移 Bug
**困难**：XSDB 对 >32MB 文件做 `mwr -force -bin`，32MB 边界后数据有 +0x2000 的目标地址偏移，导致固件上半部分写到错误位置。  
**解决**：0-32MB 用 XSDB 加载，32MB 之后的部分改用 GDB `restore` 补写到正确地址。

### 2.5 XSDB `mwr -force -bin` cache line 8 字节清零 Bug
**困难**：XSDB 会将每 64 字节 cache line 的**前 8 字节清零**，即使该 cache line 包含有效固件数据。  
**解决**：每次 XSDB 加载后，必须通过 GDB SBA **全量重写**一遍固件区，覆盖被清零的 8 字节。

### 2.6 DDR bit-13 地址别名问题
**困难**：ZCU104 DDR 控制器配置错误（DX4-DX7 被禁用），导致 DQ[32:63] 返回乱码，数据出现"2 字节重复"。实验中确认：  
- psu_init.tcl 使用了**错误的 32-bit 配置**  
- psu_init_gpl.c 是**正确的 64-bit 配置**  
**解决**：逐条对比 `(addr,mask)` 键，用 GPL 版本的正确值覆盖 TCL 版本，修复 DDR 64-bit 路径。MRCTRL0 (0xFD070010) 出现多次需特别注意。

---

## 3. 固件加载通道 (XSDB / GDB)

### 3.1 System.map 与 fw_payload.bin 不匹配
**困难**：System.map 来自未嵌入 initramfs 的构建，偏移差约 1.7MB。所有用 System.map 地址做的 GDB patch 都写到了错误的内核代码位置，导致 "invalid magic" panic（Run 9-11）。  
**解决**：禁用所有基于 System.map 的 GDB 地址补丁，改用在二进制中直接搜索 pattern 定位目标。

### 3.2 FW_PAYLOAD_FDT_ADDR 冲突
**困难**：原 DTB 地址 0x82400000 被 51MB fw_payload 固件覆盖（固件延伸到 0x830D4808），OpenSBI 传给内核的 DTB 地址是垃圾。  
**解决**：将 DTB 地址移到 0x84000000，同步修改 OpenSBI 编译参数 `FW_PAYLOAD_FDT_ADDR=0x84000000`。

### 3.3 SBA 大块传输速度极慢
**困难**：通过 J-Link JTAG 1000kHz SBA 传输 49MB 固件需约 40+ 分钟（吞吐量约 20KB/s）。  
**解决**：将固件切成 5 个 4MB chunk，GDB 分批 `restore`，同时设置 `reconnect_every=99`（每 99 次重连一次）防止 J-Link 超时断开。

### 3.4 chunks 文件陈旧（stale chunks）
**困难**：`/tmp/fw_chunks_slip/` 中保存的是旧版本 fw_payload.bin 的分片，重建内核后忘记重新分片，导致新的内核修改完全无效（花了多次 session 才发现）。  
**解决**：
1. 每次构建 fw_payload.bin 后必须立即重新分片
2. 启动脚本中加入 SHA256 验证：重组 chunks → 比对原文件 SHA256

---

## 4. OpenSBI / RISC-V M 态 Bug

### 4.1 OpenSBI trap handler t1 寄存器污染 Bug（核心 Bug）
**困难**：OpenSBI M 态 trap handler 在保存通用寄存器**之前**就把 `mcause` 读入 `t1`，导致 M 态中断（如定时器中断）发生时，S 态代码的 `t1` 被 `mcause` 的值（0x8000000000000007）覆盖后返回。症状：`strlen+6` 的 `lbu t0, 0(t1)` 以 0x8000000000000007 为地址触发访存异常，非确定性崩溃。  
**解决**：对 OpenSBI 二进制做 2 处字节级 patch：
```raw
PA 0x8000052a: csrrs t1,mcause → csrrs t0,mcause  (t0已入栈)
PA 0x8000053e: sd t1,0(t4)    → sd t0,0(t4)
```

### 4.2 J-Link 不能 stepi 跨越 mret
**困难**：从 M 态 `mret` 切换到 S 态时，J-Link 的 `stepi` 会卡死，无法单步进入内核。  
**解决**：在内核入口 `0x80200000` 设置 `hbreak`，然后 `continue`，让 CPU 自动运行到断点。

### 4.3 mtvec 残留旧值导致 double-fault
**困难**：板子没有完全清零，前一次 boot 遗留的 `mtvec` 值在新 boot 时仍然有效，第一个 M 态异常跳到无效地址，触发 double-fault 卡死。  
**解决**：boot 脚本开头预设 `mtvec = _start_hang` (0x800005b0)。

### 4.4 OpenSBI fw_payload 强制传 FW_PAYLOAD_FDT_ADDR
**困难**：OpenSBI fw_payload 无条件将 `FW_PAYLOAD_FDT_ADDR` 编码进 `a1` 传给内核，即使 GDB 里修改了 `a1` 也被覆盖。  
**解决**：在 OpenSBI 编译时将 `FW_PAYLOAD_FDT_ADDR` 固定为 0x84000000，确保 DTB 就在该地址。

### 4.5 scratch trampoline 覆盖 OpenSBI .bss
**困难**：在 `0x80036100/0x80036200` 安装辅助代码时，这些地址落在 OpenSBI `.bss`（`_fw_end=0x80037000`）范围内，导致 OpenSBI hart 初始化调用 `sbi_hart_hang`。  
**解决**：改用 `0x80038000/0x80038100`（`_fw_end` 之上安全区域）。

---

## 5. Linux 内核启动阶段

### 5.1 `init_on_alloc=1` 对早期页分配无效
**困难**：`CONFIG_INIT_ON_ALLOC_DEFAULT_ON` 未编译进内核，命令行参数 `init_on_alloc=1` 被接受但 static key 只在 `page_alloc_init_late` 才激活，早期 SLUB/页表分配仍用未初始化内存。  
**解决**：放弃依赖 `init_on_alloc`，改为在加载固件**之前** Phase 1 硬件清零全 DDR。

### 5.2 Zbb ISA 扩展导致 strlen 走 strlen_zbb 路径放大崩溃
**困难**：DTB 中声明了 `zbb` 扩展，内核启用了 `strlen_zbb`（SIMD 加速版），配合 L2 一致性问题导致 strlen 返回 22 亿的超长值直接撞到页边界崩溃。  
**解决**：从 DTB 的 `riscv,isa` 字符串中删除 `b zba zbb zbs`，改为纯标准 ISA。

### 5.3 `rcu_barrier()` 挂死（阻止 /init 执行长达 10+ session）
**困难**：内核 `mark_readonly()` 调用 `rcu_barrier()`，在单核 Rocket 上 RCU 回调永远不排空（无 preemption 下 kworker 被 init 线程饿死），导致内核卡在 `Freeing unused kernel image` 之后，永远不执行 `run_init_process()`。此 bug 导致 `/init` 无法运行长达 **10+ 个调试 session**。  
**解决**：patch `init/main.c::mark_readonly`，注释掉 `rcu_barrier()` 和 `rodata_test()` 调用：
```c
/* rcu_barrier(); -- hangs on ZCU104 Rocket */
mark_rodata_ro();
/* rodata_test(); */
```
修复后立即达成 `Run /init : YES` 里程碑。

### 5.4 sdhci probe 异步任务饿死（async_synchronize_full 挂起）
**困难**：`sdhci-of-arasan` 使用 `PROBE_PREFER_ASYNCHRONOUS`，在 `CONFIG_PREEMPT_NONE` + 50MHz CPU 下，kworker（mmc probe）被 init 线程饿死，`usleep_range(5000)` 永远不返回，内核在 `async_synchronize_full` 等待异步 probe 完成时挂死。  
**解决**：`KERNEL_RUN_SECS=300+`（给 kworker 足够的 CPU 时间调度），DTB 中加入 `broken-cd` + `xlnx,fails-without-test-cd`。

### 5.5 各类内核函数 Bug Patch（因 L2/DDR 问题引发）
以下函数因内存一致性问题或 BTF 损坏被发现并 patch 掉（`c.li a0,0; c.ret`）：
| 函数 | PA | 原因 |
|------|-----|------|
| `plist_test` | 0x8082e47a | CONFIG_DEBUG_PLIST BUG_ON |
| `dma_atomic_pool_init` | 0x8080c980 | vmap PTE collision |
| `pty_init` | 0x808223d4 | 损坏的 tty_driver 指针 |

---

## 6. SD 卡路径 — SPI-SD (失败路径)

### 6.1 SPI 引脚映射错误（B12 = GND）
**困难**：`ZCU104NewShell.scala` 将 `sdio_spi_dat_2` 映射到封装脚 `B12`，而 B12 实际是 GND 引脚。Vivado 报错 `'B12' is not a valid site or package pin name`。  
**解决**：修复 Scala shell 源码，更正引脚映射，重新生成 bitstream。

### 6.2 SPI CS/MOSI/MISO 信号交叉（RTL 级 bug）
**困难**：`SDIOOverlay.scala` 中 SPI 信号交叉连接：CS→spi_dat(3)、MOSI→spi_cs、MISO←spi_dat(0)。物理 Pmod MicroSD 接头必须按此交叉方式插接。

### 6.3 SPI-SD 无 CMD 响应（物理层故障）
**困难**：ILA 捕获显示 CS 下拉正常、CLK 正常翻转、TXD 正常输出，但 `sdio_spi_dat_0_IBUF`（MISO）全程为高，SD 卡没有任何响应。`CMD0/CMD8/CMD55/CMD1` 均以 `resp0=0` 超时。  
**根因**：物理/电气层问题（卡不在位、PMOD 方向错误、供电问题），无法通过固件修复。  
**解决**：**放弃 SPI-SD 路径**，切换到 J100 PS 原生 SDHCI 路径。

---

## 7. SD 卡路径 — J100 SDHCI PIO (成功路径)

### 7.1 J100 路径路由说明
**J100** = ZCU104 PS 原生 microSD 插槽，通过以下路径访问：
```raw
Rocket (PA 0x60170000) → AXI S_AXI_LPD → PS SDIO1 (0xFF170000) → J100 SD 插槽
```
无需修改 RTL，仅需 DTS 配置。

### 7.2 SDHCI 初始 CMD17 inhibit bit 卡死
**困难**：无 IRQ 模式下单块 PIO 读取完成后，仅调用 `sdhci_finish_data()` 不能清除控制器 data state machine。下一个 CMD17 进入 `sdhci_send_command_retry()` 时报 `Controller never released inhibit bit(s)`（`cmd_err=-5`）。  
**解决**：在 `sdhci_noirq_cmd17_finish_after_pio()` 中，先调用 `sdhci_reset_for(host, REQUEST_ERROR_DATA_ONLY)`，再调用 `sdhci_finish_data()`，并重写 `SDHCI_INT_ENABLE` 和 `SDHCI_SIGNAL_ENABLE`。

### 7.3 SDHCI DMA 模式误启用（ADMA2 descriptor stale）
**困难**：内核默认启用 ADMA2，但 DMA descriptor buffer 在 Rocket DDR 中，PS DMA 引擎无法访问（PS 看到的 0x80000000+ 是 PL，不是 PS DDR）。SWIOTLB bounce buffer 同样在 Rocket DDR，无法绕过。  
**解决**：DTB 中设置 `sdhci-caps-mask = <0x0 0x10480000>`，屏蔽：
- bit 19 (ADMA2 支持)
- bit 22 (SDMA 支持)  
- bit 28 (64-bit 系统总线)  
强制使用 **PIO 模式**。

### 7.4 DMA 架构上永久不可行（确认 2026-04-25）
**困难**：`CONFIG_RISCV_ISA_ZICBOM=not set`，`arch_sync_dma_for_device()` 展开为 `ALT_CMO_OP` → 6 NOP。即使 SWIOTLB，PS DMA 也无法访问 Rocket DDR。  
**结论**：PIO 模式是当前内核+硬件唯一可行路径，**永不更改**。

### 7.5 PLIC IRQ 号超出 ndev 导致 TileLink 总线挂死
**困难**：DTB 中给 sdhci 分配了超出 PLIC `ndev` 范围的 IRQ 号，Linux PLIC 驱动在 `irq_domain mapping` 时访问不存在的 MMIO 寄存器，触发 TileLink bus error，**永久**挂死 hart（debug module 无法 halt）。  
**解决**：DTB 中省略 `interrupt-parent/interrupts`，使用 `platform_get_irq_optional()` + 10ms poll timer，完全绕过 IRQ。

---

## 8. DMA 不可行 (永久结论)

| 项目 | 结论 |
|------|------|
| `arch_sync_dma_for_device()` | = `ALT_CMO_OP(clean,...)` = `__nops(6)`（无 Zicbom） |
| SWIOTLB bounce buffer | 在 Rocket DDR (0x80000000+)，PS DMA 不可见 |
| ADMA2 descriptor | 在 Rocket DDR，PS DMA 引擎不可访问 |
| DMA run 证据 | `using ADMA` → loop=2600 missing → `cmd_err=-110` → stage_mark=0x4a |
| **结论** | **PIO-only，sdhci-caps-mask=0x10480000，永不更改** |

---

## 9. Initramfs & Init 阶段

### 9.1 cpio archive invalid magic（因 patch 地址错误）
**困难**：使用错误 System.map 地址对内核做 GDB patch，随机破坏代码，导致 initramfs unpack 时报 "invalid magic at start of compressed archive"。  
**解决**：弃用 System.map 地址，改用二进制 pattern 搜索确定 patch 位置。

### 9.2 cpio stderr 混入输出文件
**困难**：重建 initramfs 时 `cpio` 命令的 stderr（"3546 blocks"）泄漏进 output 文件，内核 initramfs unpacker 遇到非 magic、非 null 字节时 panic。  
**解决**：所有 `cpio` 命令加 `2>/dev/null`。

### 9.3 init 使用 sleep 在 50MHz Rocket 上超时
**困难**：initramfs 中的 `/init` 脚本使用 `sleep 5` 等待设备出现，但 50MHz Rocket 上 `sleep` 的时间精度极差，等待窗口内 `/dev/mmcblk0p3` 未就绪，SD 挂载失败。  
**解决**：init.v3 改为纯 shell loop（无 sleep），持续轮询 `/dev/mmcblk0p3` 是否存在。

### 9.4 initramfs_size patch 规则
**困难**：`patch_fw.py` 需要修改 `fw_payload.bin` 中的 `__initramfs_size` 字段和 gzip 区域，位置在特定 offset，不能自己猜测计算。  
**锁定值**：
- fw_payload.bin offset `0xb683b0` = `__initramfs_size = 0x15c1a8`
- CPIO at offset `0xd2c1d0`，gzip at offset `0x27ca90`

---

## 10. SiFive UART 驱动竞争条件

### 10.1 probe 时 IRQ 早于 uart_add_one_port
**困难**：`sifive_serial` probe 中，`request_irq()` 在 `uart_add_one_port()` 之前被调用。如果 UART IRQ 在 probe 期间触发，`tty_insert_flip_char()` 会尝试访问 `port.state`（此时为 NULL），触发 NULL+0x98 解引用，内核 panic。非确定性，约 30% 概率复现。  
**错误解法**：J-Link `WriteU32 0x64000010 0x0`（清 UART IE 寄存器）——kernel probe 内部会重新 enable IE，竞争窗口仍在。  
**正确解法**：修改内核驱动 `sifive.c`：
1. probe 期间保持 UART IE 屏蔽，直到 `uart_add_one_port()` 完成
2. `sifive_serial_irq()` 中若 `!ssp->port.state`，立即 mask IE 并返回
3. `sifive_serial_console_write()` 中若 `port.state == NULL`，跳过 `spin_lock`

---

## 11. Bitstream & Vivado 构建

### 11.1 Vivado UNC 路径问题（Windows + WSL）
**困难**：超长 config 名生成的文件路径通过 UNC 方式传给 Vivado，`add_files` 报告文件不存在，即使 WSL 下可见。  
**解决**：在 `scripts/build_bitstream_wsl.sh` 中将所有 TCL 路径参数转换为映射的 `Z:` 盘路径。

### 11.2 Bitstream 来源混淆
**困难**：`generated-src/.../obj/ZCU104FPGATestHarness.bit` 时间戳为 Apr 6，而当前源码修改在 Apr 7 之后，导致行为归因错误（以为硬件问题，实则是旧 bitstream）。  
**解决**：修改任何 Scala/RTL 源文件后必须重新 `make bitstream`，不能复用旧 bit 文件。

### 11.3 XDC IOB 警告（`-of_objects` 接受 port 报错）
**困难**：`XilinxShell.scala::addIOB` 中用 `get_cells -of_objects [get_ports ...]`，Vivado 拒绝（`-of_objects` 不接受 port）。  
**解决**：先 `get_nets -of_objects <port>` 得到 net，再从 net 查 cells，并加 `if {[llength $cells] > 0}` 保护。

---

## 12. 工具链 & 脚本工具问题

### 12.1 GDB `continue` + hbreak 不可靠（长 SBA 传输后）
**困难**：长时间 SBA 传输后（如 49MB restore），`continue` + 硬件断点的组合不可靠，hbreak 不触发，或 GDB 无限阻塞。  
**解决**：改用 `monitor go` + `time.sleep()` + `monitor halt` + 检查 PC 的模式。

### 12.2 GDB `set *(uint32_t*)MMIO_ADDR = val` 挂死
**困难**：通过 SBA 写 MMIO 寄存器时，GDB 会挂死（MMIO 设备不支持 SBA 访问语义）。  
**解决**：改用 `monitor WriteU32 addr val` 直接写。

### 12.3 WSL PowerShell 退出码不传播
**困难**：从 WSL 调用 `powershell.exe -Command ...` 执行 Windows 侧 XSDB，退出码可能不正确传播（返回 0 但实际有错误）。  
**解决**：不依赖 `$?`，改为 grep 输出文本中的 `ERROR` 关键字判断成功/失败。

### 12.4 XSDB `rst -system` 后 PSU target 消失
**困难**：在 JTAG-boot / PS 未初始化状态下，XSDB 目标列表只有 `PS TAP/PMU/PL/DAP`，没有 `PSU`。  
**解决**：先从 `PS TAP` 执行 `rst -system`，等待 8 秒，`PSU` target 才出现。

---

## 13. 完整成功链总结

### 最终成功里程碑（fedora_v3fix3_20260424_230736）

| 里程碑 | 状态 |
|--------|------|
| J-Link JTAG 连接 Rocket debug module | ✅ |
| DDR 全量清零（Phase 1，Rocket 核心执行） | ✅ |
| fw_payload.bin.v3patched SBA 恢复（5×4MB chunks） | ✅ |
| DTB 加载 @ 0x84000000，PIO 模式 caps-mask=0x10480000 | ✅ |
| OpenSBI 启动 → mret → Linux kernel 入口 | ✅ |
| dcsr ebreak bits 清除（S 态 continue 不被 debug 中断） | ✅ |
| Linux 内核完整初始化（跳过 rcu_barrier/rodata_test） | ✅ |
| mmcblk0: p1 p2 p3 分区枚举 | ✅ |
| Btrfs subvol=root 挂载（MOUNT SUCCESS） | ✅ |
| SWITCH_ROOT → /sbin/init | ✅ |
| **systemd[1] 启动** | ✅ |
| stage_mark = 0x5354474500000011 | ✅ |

### 固定成功链约束

```raw
内核：Linux 6.6.0-fpga-min-g67bc4513761f-dirty #129 Thu Apr 23 18:56:45 CST 2026
固件：fw_payload.bin.v3patched（SHA256: 759db54b9bebf2b77945b5b7e861517f564443d370bd1efe4625538f8de31480）
DTB ：sdhci-caps-mask = <0x00 0x10480000>（PIO-only）
路径：J100-ONLY（PS SDIO1 via AXI S_AXI_LPD，Rocket PA 0x60170000）
IRQ ：无中断，10ms poll timer
```

### 关键修复汇总

| # | 修复项 | 受影响阶段 | 修复方式 |
|---|--------|-----------|---------|
| 1 | DDR 清零（Rocket 核心） | Phase 1 | 8B store loop，~30s |
| 2 | SBA L2 一致性（先清零驱逐旧行） | Phase 1→2 | 清零顺序策略 |
| 3 | OpenSBI t1/mcause 污染 | M-mode trap | 2 字节 binary patch |
| 4 | rcu_barrier 挂死 | kernel_init | patch init/main.c |
| 5 | UART probe race | sifive_serial | driver-level IE mask |
| 6 | CMD17 inhibit stuck | SDHCI CMD17 | data-reset before finish |
| 7 | ADMA2 禁用（强制 PIO） | SDHCI 所有 IO | sdhci-caps-mask DTB |
| 8 | sleep-free init（v3-nosleep） | initramfs /init | 纯 shell poll loop |
| 9 | chunks 强制重新分片+SHA256 验证 | fw 加载 | run 脚本逻辑 |
| 10 | reconnect_every=99 | SBA 传输 | GDB 脚本参数 |

---

## 当前 Run 状态（2026-04-25 13:27）

```raw
TAG : fedora_pio_stable_20260425_132754
LOG : /tmp/boot_fedora_pio_stable_20260425_132754.log
状态: Phase 7 已进入（kernel 运行中，1800s 稳定性测试）
GDB : pid 16761/16763 运行中
```

验收命令：
```bash
grep -E "mmcblk0.*p1 p2|MOUNT SUCCESS|SWITCH_ROOT|systemd\[1\]|stage_mark.*sub|Kernel panic" \
  /tmp/boot_fedora_pio_stable_20260425_132754.log | tail -20
```
