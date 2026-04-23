# /init 静默失败回归 —— 根因分析与修复报告

**日期**：2026-04-22  
**平台**：ZCU104 + Chipyard Rocket（RV64GC, 50 MHz, SV39）  
**内核**：Linux 6.6 RISC-V（Chipyard firemarshal `boards/default/linux-clean`）  
**固件**：OpenSBI fw_payload，`FW_PAYLOAD_FDT_ADDR=0x84000000`  
**调试通道**：J-Link GDB Server V7.82b（Windows 主机） → WSL 中继 `127.0.0.1:3333`

---

## 1. 问题现象

一次曾经能进入 userspace（`systemd` 启动、`fedora-rootfs` 循环运行）的内核构建，在后续增量改动后退化为**/init 静默死亡**：

| 指标 | 好构建（2026-04-22 13:14） | 坏构建（2026-04-22 14:51 之后） |
|---|---|---|
| `Run /init as init process` | YES | YES |
| `initline kernel_exec exit: ret=0` | YES | YES |
| `INIT_ENTRY` / `hard_echo` / `fedora-rootfs` 输出 | 有 | **零条** |
| `busybox` / `/bin/sh` / `Welcome` 字符串 | 有 | 无 |
| `stage_mark` u64 @ PA `0x8F000000` | 非零 | 全 0 |
| JTAG halt 状态 | userspace `sepc=0x3fbb…` | `dpc=handle_exception`, `scause=0x8000…0009`（S-ext IRQ 风暴） |

也就是说：**内核完成 `kernel_execve("/init")`，用户态进程成功被创建，但没有任何 stdout/kmsg/物理地址痕迹**。外在像「`/init` 根本没跑」，其实是跑了但一个字节都 `write()` 不出来。

---

## 2. 排错方法论

### 2.1 建立可重复的观测闭环（Phase A）

1. **Phase A1**：在 `scripts/linux_boot.gdb` 中加入 `stage_mark` 自动 dump —— 每次 JTAG halt 前后读取 PA `0x8F000000` 处 256 字节，解码首个 u64 的 tag/sub 字段。
2. **Phase A2**：在 `scripts/start_linux_boot.sh` 结尾追加 `xxd` + Python u64 LE 解码，把 stage 值打印到日志末尾。
3. **Phase A3**：基线跑 300 s，确认回归确实存在，与历史好日志对比。

### 2.2 在 `/init` 首行埋断点（Phase B）

在 `linux-bringup/initramfs/rootfs/init` 里添加：
- `hard_echo()`：同时 `printf` 到 `/dev/kmsg` 和 `/dev/console`
- 四个 breadcrumb：`INIT_ENTRY pid=$$ argv0=$0`、`INIT_AFTER_PSEUDO_MOUNTS`、`INIT_BEFORE_FIRST_STAGE_MARK`、`INIT_AFTER_FIRST_STAGE_MARK sm=0x01`
- `mark_stage()` 调 `/sbin/stage_mark` 写 u64 到 PA `0x8F000000`

结果：**没有任何一条 breadcrumb 出现**。意味着 `/init` 进程在跑到脚本第一行 `exec` 之前就被信号杀死，或者 `write()` 本身失败。→ 问题在内核→用户态过渡路径，不在 `/init` 脚本本身。

### 2.3 逐层二分（Phase C）

工作区里有 18 个 `git status -M` 的文件。按 mtime 和嫌疑度分组，用 `git stash push -- <paths>` 做**集合二分**：

| 实验 | 恢复的修改 | /init 是否执行 | 结论 |
|---|---|---|---|
| `revert_sdhci_v1` | 只回退 `sdhci.c` 到 HEAD，其余 17 个保留 | ✗ 静默 | sdhci.c 不是根因 |
| `oldcpio_v1` | 同上 + 用 11:30 的老 cpio | ✗ 静默 | cpio 不是根因 |
| `stashed_v1` | **全部 17 个 stash 掉**（只留 `tty/sifive.c`） | ✓ `fedora-rootfs` 31 条、`mmcblk` 枚举 | 根因确定在这 17 个里 |
| `archriscv_v1` | 仅恢复 `arch/riscv/{timex.h, vdso/gettimeofday.h, cpufeature.c}` | ✗ 甚至退到更早阶段 | **根因锁定在 arch/riscv/** |

第四次实验 halt 状态变为 `scause=0x0c`（instruction page fault）、`sepc=0x80201048`，内核连 `/init` 都到不了 —— 对拍出 arch/riscv 三件套是罪魁。

### 2.4 读 diff 定位单一根因

```raw
arch/riscv/include/asm/vdso/gettimeofday.h:
-    return csr_read(CSR_TIME);
+    return csr_read(CSR_CYCLE);

arch/riscv/include/asm/timex.h:
-    return csr_read(CSR_TIME);       // get_cycles()
+    return csr_read(CSR_CYCLE);
-    return csr_read(CSR_TIMEH);      // get_cycles_hi()
+    return csr_read(CSR_CYCLEH);

arch/riscv/kernel/cpufeature.c:
+ // check_unaligned_access(): skip benchmark, assume SLOW
```

**关键观察**：`arch/riscv/include/asm/vdso/gettimeofday.h::__arch_get_hw_counter()` 是 vDSO 代码，**在 U-mode 直接执行**。把 `CSR_TIME` 换成 `CSR_CYCLE` 之后：
- Rocket 的 `scounteren.CY` 位**未置 1**（Chipyard 默认不放开 CYCLE 给 U-mode）
- 任何用户态进程首次调用 `clock_gettime()` / `gettimeofday()` / `time()` 走 vDSO 快路径 → 读 `cycle` → **非法指令异常**
- glibc 启动阶段就会调时间相关系统调用 → 进程在第一条指令附近收到 SIGILL → 被内核静默终止
- 因此用户态零输出，symptom 完美吻合

`cpufeature.c` 的早退是良性调试措施（跳过 unaligned-access 微基准），不造成回归。

---

## 3. 修复

只回退两个 vDSO/timex 的 CSR 改动，保留 cpufeature.c 的早退：

```bash
cd /root/chipyard/software/firemarshal/boards/default/linux-clean
git checkout HEAD -- arch/riscv/include/asm/timex.h
git checkout HEAD -- arch/riscv/include/asm/vdso/gettimeofday.h
# cpufeature.c 保持修改
```

重建：

```bash
ARCH=riscv CROSS_COMPILE=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-linux-gnu- \
  make -j$(nproc) Image
bash /root/chipyard/fpga/linux-bringup/scripts/build_opensbi_linux_payload.sh
```

---

## 4. 验证（RUN_TAG=csrfix_v1，300 s JTAG 跑测）

- `Run /init: YES`
- `mmcblk: YES`、`sdhci: YES`、`arasan: YES`
- klog 中出现 **31 条 `fedora-rootfs:` 输出**
- 末尾状态：`fedora-rootfs: wait tick=0s loop=0 /dev/mmcblk0p3 still missing` —— `/init` 已进入分区轮询主循环（SD 卡未就绪是另一个独立议题，不阻塞结论）
- `[post-check] Initramfs magic @ PA 0x80d2c0f0: 0x37303730 0x00003130 (OK)`

回归彻底修复。

### 4.1 初始化日志摘录（成功修复后的 `/init` 输出）

下列摘录来自同一次成功运行的 klog strings，证明 `/init` 已经真正进入脚本主体并开始执行 Fedora rootfs 轮询逻辑：

```text
841: Run /init as init process
842:   with arguments:
843:     /init
844:   with environment:
845:     HOME=/
846:     TERM=linux
847: fedora-rootfs: SPI-SD Fedora bringup start (conservative, total wait 1800s)
848: fedora-rootfs: uname: Linux ucb 6.6.0-fpga-min-g67bc4513761f-dirty #120 Wed Apr 22 21:31:37 CST 2026 riscv64 GNU/Linux
849: fedora-rootfs: /proc/filesystems:
850: fedora-rootfs: fs: nodev
851: fedora-rootfs: fs: nodev
852: fedora-rootfs: fs: nodev
853: fedora-rootfs: fs: nodev
854: fedora-rootfs: fs: nodev
855: fedora-rootfs: fs: nodev
856: fedora-rootfs: fs: nodev
857: devtmpfs
858: fedora-rootfs: fs: nodev
859: securityfs
860: fedora-rootfs: fs: nodev
861: fedora-rootfs: fs: nodev
862: fedora-rootfs: fs: nodev
863: fedora-rootfs: fs: nodev
864: fedora-rootfs: fs: nodev
865: hugetlbfs
866: fedora-rootfs: fs: nodev
867: fedora-rootfs: fs: ext3
868: fedora-rootfs: fs: ext4
869: fedora-rootfs: fs: ext2
870: fedora-rootfs: fs: vfat
871: fedora-rootfs: fs: msdos
872: fedora-rootfs: fs: iso9660
873: fedora-rootfs: fs: nodev
874: fedora-rootfs: fs: nodev
875: fedora-rootfs: fs: btrfs
876: fedora-rootfs: wait tick=0s loop=0 /dev/mmcblk0p3 still missing
877: fedora-rootfs: dev: ls: /dev/mmcblk0*: No such file or directory
878: fedora-rootfs: /proc/partitions:
879: fedora-rootfs: part: major minor  #blocks  name
880: fedora-rootfs: part:
```

### 4.2 内核日志摘录（成功修复后的同次 klog）

这段摘录展示的是同一次 `csrfix_v1` 运行中的内核启动期 printk，可用于说明修复后系统已经稳定走到正常内核初始化，再进入 `/init`：

```text
0: Linux version 6.6.0-fpga-min-g67bc4513761f-dirty (root@YXY) (riscv64-unknown-linux-gnu-gcc (g04696df0963) 14.2.0, GNU ld
1: Machine model: ucb-bar,chipyard
2: SBI specification v1.0 detected
3: SBI implementation ID=0x1 Version=0x1000202
4: SBI TIME extension detected
5: SBI IPI extension detected
6: SBI RFENCE extension detected
7: earlycon: sifive0 at MMIO 0x0000000064000000 (options '')
8: printk: bootconsole [sifive0] enabled
9: printk: debug: ignoring loglevel setting
10: efi: UEFI not found
11: OF: reserved mem: 0x0000000080000000..0x000000008001ffff (128 KiB) map non-reusable mmode_resv0@80000000
12: OF: reserved mem: 0x0000000080020000..0x000000008003ffff (128 KiB) map non-reusable mmode_resv1@80020000
13: Zone ranges:
14:   DMA32    [mem 0x0000000080000000-0x00000000ffffffff]
15:   Normal   empty
16: Movable zone start for each node
17: Early memory node ranges
18:   node   0: [mem 0x0000000080000000-0x00000000ffffffff]
19: Initmem setup node 0 [mem 0x0000000080000000-0x00000000ffffffff]
20: Falling back to deprecated "riscv,isa"
21: riscv: base ISA extensions abcdfim
22: riscv: ELF capabilities acdfim
23: pcpu-alloc: s0 r0 d32768 u32768 alloc=1*32768
24: pcpu-alloc: [0] 0
25: Kernel command line: earlycon=sifive,0x64000000 console=ttySIF0,115200n8 init=/init loglevel=8 ignore_loglevel initcall_debug
38: Memory: 2044592K/2097152K available (5185K kernel code, 3718K rwdata, 2048K rodata, 3257K init, 392K bss, 52560K reserved)
41: riscv-intc: 64 local interrupts mapped
42: plic: interrupt-controller@c000000: mapped 4 interrupts with 1 handlers for 2 contexts
43: clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0xb8812736b, max_idle_ns: 440795202655 ns
44: sched_clock: 64 bits at 50MHz, resolution 20ns, wraps every 4398046511100ns
45: Calibrating delay loop (skipped), value calculated using timer frequency.. 100.00 BogoMIPS (lpj=200000)
```

同次 300 s halt 的关键状态如下，可作为 run 末状态采样：

```text
[state] PC = 0x000000008000b1d2
[state] satp = 0x8000000000082143
[state] scause = 0x8000000000000005
[state] sepc = 0xffffffff8050d9c2
[state] stval = 0x0000000000000000
[state] mcause = 0x0000000000000009
[state] mepc = 0xffffffff80006be2
[state] mtval = 0x0000000000000000
[state] dcsr = 0x000000004000f0c1
[state] dpc = 0xffffffff800030c0
```

---

## 5. 所用方法与工具

1. **JTAG/GDB 无侵入观测**：`scripts/start_linux_boot.sh` + `scripts/linux_boot.gdb`（基于 J-Link SBA 内存读，不打断 CPU 运行）
2. **多层 breadcrumb**：内核 `SENTINEL_*` printk + userspace `hard_echo` + PA `0x8F000000` stage_mark 三级验证
3. **符号化 halt 分析**：`System.map` + `awk '$1 <= "sepc" {prev=$0}'` 把 `sepc/dpc/mepc` 定位到内核符号
4. **集合式 git stash 二分**：按 mtime 粗分层，用 `git stash push -- <paths>` 批量装/卸，逐轮缩小嫌疑集
5. **diff 精读 + ISA 语义**：锁定集合后读 `git diff HEAD`，结合 RISC-V `scounteren` 的 U-mode 可见性语义，推断 SIGILL 路径
6. **对照实验矩阵**：每轮修改都跑同一 300 s 脚本，milestone 表格对拍（`Run /init` / `mmcblk` / `Welcome` / stage_mark）

---

## 6. 经验归档

- Rocket（以及很多 FPGA 软核）默认 `scounteren` 不放开 `CY/IR/HPMn` 给 U-mode。任何让 vDSO 读 `cycle` / `instret` / `hpmcounter*` 的补丁都会把用户态全员送 SIGILL —— 且因为发生在进程第一条指令附近，**表现形式是「`/init` 成功 exec 但零输出」**，极易被误诊为 initramfs、shell、SDHCI 问题。
- 正确做法是**不要改 vDSO 快路径**；如果确实想换 time source，需要同时修改 `csr_set(CSR_SCOUNTEREN, 1<<0 /*CY*/)`，并在 OpenSBI 里也开 `mcounteren`。
- 相关归档：`/memories/repo/riscv-vdso-csr-cycle-regression.md`（简版）。

---

## 7. 产物清单

- 被修改回滚的文件：
  - `boards/default/linux-clean/arch/riscv/include/asm/timex.h`（回 HEAD）
  - `boards/default/linux-clean/arch/riscv/include/asm/vdso/gettimeofday.h`（回 HEAD）
- 其余 14 个 driver/fs/init 改动目前仍在 `git stash@{0}: regression_bisect_all`（包含 `sdhci.c` v4 PIO 补丁）；需要 SDHCI 功能时可按需恢复单个文件
- 备份：`drivers/mmc/host/sdhci.c.v4.bak`（5631 行 CMD17 PIO 诊断版）
- 调试脚本：`scripts/start_linux_boot.sh`、`scripts/linux_boot.gdb`、`linux-bringup/initramfs/rootfs/init`（保留 breadcrumb 供后续长跑用）
- 实验日志（均位于 `/tmp/`）：
  - `boot_revert_sdhci_v1.*`、`boot_oldcpio_v1.*`、`boot_stashed_v1.*`、`boot_archriscv_v1.*`、`boot_csrfix_v1.*`
