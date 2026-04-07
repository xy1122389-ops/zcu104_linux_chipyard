# 项目目标
- 最终目标：在 Chipyard RISC-V Rocket core (ZCU104 FPGA) 上成功启动 Linux 到用户态 /init
- 当前阶段目标：定位并修复内核早期 init 阶段的 page fault crash

# Repo 信息
- repo 根目录：`/root/chipyard`
- branch：`main`
- HEAD commit：`9df625fe` — "update local chipyard changes"
- FPGA 工作目录：`/root/chipyard/fpga`
- git status 要点：
  - fpga/ 下大量 untracked 文件（scripts/、linux-bringup/、src/main/scala/zcu104/ 等均为本项目新增）
  - tracked 文件有少量 modified（fpga/Makefile、fpga/.gitignore 等）
  - linux-clean kernel source 和 firemarshal 子模块未做 commit

# 当前板子实时状态（开新窗口前最后更新）
- FPGA 当前烧录配置：**RocketZCU104Config**（有 L2），bitstream 日期 2026-04-02
- 当前 payload / DTB / initramfs 是否已构建好：**是**，payload md5 `c446286854a704b1161395696a38246a`，DTB 和 initramfs 均就绪
- fw_chunks_new 是否已刷新：**是**，`/tmp/fw_chunks_new/chunk_0{0,1,2,3}.bin` 与当前 payload 一致（2026-04-07 11:13 生成）
- Windows 侧 J-Link GDB Server 是否需要先重启：**是**，上次 GDB 会话（L2_compare1）已退出，必须重启后才能连
- 当前推荐先跑 L2 还是 no-L2：**L2**（当前 FPGA 上已烧 L2 配置，无需重新编程；跑 no-L2 需要先 `run_ps_ddr_init.sh` 重烧）

# 当前状态（只写最新有效状态）
- 已经完成：OpenSBI → mret → Linux _start → 内核前 10 行 printk 输出（clocksource、iommu、io scheduler 等全部正常打印）
- 当前卡点：内核在 `do_one_initcall` 阶段调用各种 init 函数时，`strlen` 等函数触发 load page fault (cause=0xd)，地址形如 `ffffff80000000xx`
- 最新 crash（L2 配置）：`strlen+0x6` in `kobject_uevent_env` ← `legacy_pty_init`，badaddr=`ffffff8000000007`
- 最新 crash（no-L2 配置）：`vmap_pages_pte_range+0xe8` ← `dma_atomic_pool_init`，badaddr=`ffffff8000000107`
- 是否已到过 Linux 用户态 / /init / /bin/sh：**否**，从未到达

# 历史最好结果
- 最好日志：`/tmp/boot_multi_3_234647.strings`（L2 配置，旧版内核 build #9，含 NET/MODULES）
  - 92 行正常 klog 输出后 crash
  - 到达了内存统计（524288 pages RAM）、workqueue 初始化
  - crash 点：`async_run_entry_fn` 中的 workqueue event
- 当前最新（L2 配置，build #13，无 NET/MODULES）：
  - `/tmp/boot_L2_compare1.strings` — 11 行正常输出后 crash in `legacy_pty_init`
  - crash 更早，说明禁掉 NET/MODULES 后 initcall 顺序变了，不代表退步
- 所有 crash 共同特征：badaddr 均为 `ffffff80000000xx`，cause 均为 `0xd`

# 已验证事实
- 事实1：**L2 和 no-L2 配置都崩溃**，crash 模式一致（strlen/vmap page fault on `ffffff80000000xx`），与有无 L2 Cache 无关
- 事实2：**klog 转储存在系统性的末尾 2 字节重复**：`slow` → `slowow`、`pages` → `pageses`、`Translated` → `Translateded`。45 行中 32 行命中此模式。这是 SBA 读路径的数据完整性问题
- 事实3：crash 寄存器 dump 中也有同样的重复：`cause: 000000000000000d0d`（末尾 `0d` 重复）、`0000000707`（`07` 重复）——证明 SBA 读的字节重复污染了 klog 解析，但 crash 本身的 badaddr 值需要打折看
- 事实4：payload（OpenSBI + Linux Image）通过 GDB SBA `restore binary memory` 写入 DDR，klog 由 CPU 写入 DDR 后用 GDB SBA `dump binary memory` 读回——SBA 读路径有 2 字节重复 bug 已确认
- 事实5：CPU store → SBA read 路径全部读回 0（store_diag.gdb 验证），原因是 write-back D-cache 对 SBA 不可见，这是预期行为
- 事实6：`si`（单步执行）在此目标上完全不能用——总是 trap 到 PC=0x0
- 事实7：tiny initramfs（2560 bytes，纯静态 /init）已消除了之前的 "invalid magic" panic
- 事实8：禁用 RPMSG 消除了 rpmsg crash，但 crash 只是移到了下一个 initcall

# 已排除方向
- 排除1：**D-cache/L2 一致性问题不是根因** —— L2 配置同样崩溃
- 排除2：**initramfs 格式问题** —— tiny initramfs 已修复，当前 panic 不在 initramfs 解析阶段
- 排除3：**DTB 问题** —— 换过多个 DTB（有/无 cache-controller、有/无 initrd 节点），crash 模式不变
- 排除4：**特定驱动问题** —— 禁掉 RPMSG、SYSCTL 后 crash 只是换了 initcall，不是某个驱动的 bug
- 排除5：**socat relay (port 12331)** —— 不稳定且无必要，直连 2331 即可

# 当前最可能根因
- 根因候选：**SBA 写路径也存在类似的字节级数据损坏**，导致 payload（kernel binary）在 DDR 中是损坏的。CPU 执行的是被 SBA 写坏的 kernel image
- 依据：
  1. SBA 读已确认有系统性 2 字节重复 bug
  2. payload 也是通过 SBA 写入的（`restore binary memory`）
  3. crash 总在不同 initcall 的类似代码路径（strlen/vmap 等访存密集函数），符合"代码/数据轻微损坏"的特征
  4. crash 地址 `ffffff80000000xx` 看起来像被截断/损坏的指针
- **注意**：SBA 写损坏目前是推测，尚未直接验证。也可能只有 SBA 读有问题而写是正确的

# 改过的关键文件
- `/root/chipyard/fpga/scripts/linux_boot_nol2_direct.gdb`：
  - 改了什么：加了 `JLINK_HOST` / `JLINK_PORT` / `DTB_PATH` / `RUN_TAG` / `KERNEL_RUN_SECS` 环境变量支持；默认直连 `172.19.128.1:2331`；DTB 默认用 no-L2 版
  - 为什么改：支持 L2/no-L2 对比测试，去掉对 socat relay 的依赖
- `/root/chipyard/software/firemarshal/boards/default/linux-clean/.config`：
  - 改了什么：`CONFIG_RPMSG_VIRTIO=n`，`CONFIG_INITRAMFS_SOURCE` 指向 tiny initramfs cpio，`CONFIG_NET=n`，`CONFIG_MODULES=n`
  - 为什么改：消除 rpmsg crash，嵌入 tiny initramfs，裁减内核
- `/root/chipyard/fpga/linux-bringup/initramfs/initramfs.cpio`：
  - 改了什么：替换为 2560 字节的极简 cpio（只含 /init + /dev/{console,null,kmsg}）
  - 为什么改：消除 "invalid magic" panic
- `/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb`：
  - 改了什么：新建，L2 版 DTB，bootargs 加 `init=/init`
- `/root/chipyard/fpga/linux-bringup/demo-assets/dtb/generated/chipyard-zcu104-nol2-minimal.dtb`：
  - 改了什么：新建，no-L2 版 DTB（无 cache-controller 节点）

# 当前主入口脚本 / 对照脚本 / 废弃脚本

## 主入口（当前使用）
| 脚本 | 用途 |
|------|------|
| `/root/chipyard/fpga/scripts/linux_boot_nol2_direct.gdb` | **主 GDB boot 脚本**：SBA payload restore → OpenSBI → mret → Linux → klog dump。支持 L2/no-L2 |
| `/root/chipyard/fpga/scripts/run_ps_ddr_init.sh` | FPGA 编程 + PS DDR 初始化（调 XSDB） |
| `/root/chipyard/fpga/linux-bringup/scripts/build_opensbi_linux_payload.sh` | 构建 OpenSBI fw_payload（内嵌 Linux Image） |

## 辅助诊断（按需使用）
| 脚本 | 用途 |
|------|------|
| `/root/chipyard/fpga/scripts/store_diag.gdb` | 裸机 store 诊断：CPU store → SBA read 验证 |
| `/root/chipyard/fpga/scripts/sba_coherency_test.gdb` | SBA write → CPU read 一致性测试（未成功，hbreak 超时） |
| `/root/chipyard/fpga/scripts/sba_read_diag.gdb` | SBA 读取诊断 |
| `/root/chipyard/fpga/scripts/sba_verify.gdb` | SBA 校验脚本 |
| `/root/chipyard/fpga/scripts/linux_klog_dump.gdb` | 单独 klog dump（不含 boot 流程） |

## 已废弃 / 过渡版本（不要再用）
| 脚本 | 原因 |
|------|------|
| `/root/chipyard/fpga/scripts/start_linux_boot.sh` | 旧 wrapper，走 socat relay 12331，已不需要 |
| `/root/chipyard/fpga/scripts/multi_boot.sh` | 旧多轮 boot wrapper，依赖 start_linux_boot.sh |
| `/root/chipyard/fpga/scripts/linux_boot.gdb` | 旧版 GDB 脚本，被 linux_boot_nol2_direct.gdb 替代 |
| `/root/chipyard/fpga/scripts/linux_boot_nol2_repair_initramfs.gdb` | 旧版 initramfs 修复脚本，已不需要 |
| `/root/chipyard/fpga/scripts/linux_boot_diag.gdb` | 旧版诊断脚本 |
| `/root/chipyard/fpga/scripts/linux_boot_minimal.gdb` | 旧版最小化 boot |
| `/root/chipyard/fpga/scripts/linux_boot_continue.gdb` | 旧版续跑脚本 |
| `/root/chipyard/fpga/scripts/linux_boot_resume_once.gdb` | 旧版单次续跑 |
| `/root/chipyard/fpga/scripts/linux_reboot_dump.gdb` | 旧版 reboot+dump |

# 关键脚本/命令（可直接复制）

## 1. FPGA 编程 + DDR 初始化
```bash
# L2 配置
cd /root/chipyard/fpga && CHIPYARD_ZCU104_CFG=RocketZCU104Config bash scripts/run_ps_ddr_init.sh

# no-L2 配置
cd /root/chipyard/fpga && CHIPYARD_ZCU104_CFG=RocketZCU104NoL2LinuxConfig bash scripts/run_ps_ddr_init.sh
```

## 2. L2 配置 boot（最近一次实际执行的命令）
```bash
cd /root/chipyard/fpga && \
  DTB_PATH=/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb \
  CHIPYARD_ZCU104_CFG=RocketZCU104Config \
  JLINK_PORT=2331 \
  KERNEL_RUN_SECS=120 \
  RUN_TAG=L2_run1 \
  /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -batch \
    -x scripts/linux_boot_nol2_direct.gdb \
  2>&1 | tee /tmp/boot_L2_run1.log
```

## 3. no-L2 配置 boot
```bash
cd /root/chipyard/fpga && \
  CHIPYARD_ZCU104_CFG=RocketZCU104NoL2LinuxConfig \
  JLINK_PORT=2331 \
  KERNEL_RUN_SECS=120 \
  RUN_TAG=noL2_run1 \
  /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -batch \
    -x scripts/linux_boot_nol2_direct.gdb \
  2>&1 | tee /tmp/boot_noL2_run1.log
```
（no-L2 默认 DTB 为 `/root/chipyard/fpga/linux-bringup/demo-assets/dtb/generated/chipyard-zcu104-nol2-minimal.dtb`，不需设 DTB_PATH）

## 4. 内核编译
```bash
cd /root/chipyard/software/firemarshal/boards/default/linux-clean && \
  make ARCH=riscv CROSS_COMPILE=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-linux-gnu- olddefconfig && \
  make -j4 ARCH=riscv CROSS_COMPILE=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-linux-gnu- Image
```

## 5. OpenSBI payload 构建
```bash
cd /root/chipyard/fpga && bash linux-bringup/scripts/build_opensbi_linux_payload.sh
```

## 6. payload 分块（GDB restore 用）
```bash
rm -rf /tmp/fw_chunks_new && mkdir -p /tmp/fw_chunks_new && \
  split -b 4194304 -d -a 2 \
    /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin \
    /tmp/fw_chunks_new/chunk_ && \
  for f in /tmp/fw_chunks_new/chunk_*; do mv "$f" "$f.bin"; done && \
  ls -l /tmp/fw_chunks_new/
```

## 7. bitstream 编译（no-L2 示例，约 1-2 小时）
```bash
cd /root/chipyard/fpga && \
  PATH="$PWD/scripts:/root/chipyard/.oclaw-env/bin:$PATH" \
  make SUB_PROJECT=zcu104 CONFIG=RocketZCU104NoL2LinuxConfig bitstream
```

## 8. 验证端口连通
```bash
nc -zv -w3 172.19.128.1 2331
```

## 9. Windows 侧 J-Link GDB Server 恢复
在 Windows **PowerShell** 或 **CMD** 中执行：
```powershell
# PowerShell
Stop-Process -Name JLinkGDBServerCL -Force -ErrorAction SilentlyContinue
Start-Process "C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe" -ArgumentList "-device RISC-V -if JTAG -speed 1000 -port 2331 -localhostonly 0"
```
```cmd
:: CMD
taskkill /IM JLinkGDBServerCL.exe /F >NUL 2>&1
start "" "C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe" -device RISC-V -if JTAG -speed 1000 -port 2331 -localhostonly 0
```
> J-Link 是**单连接模式**，每次 GDB 会话结束后**必须** Windows 侧重启 GDB Server 才能再次连接。

## bitstream 配置名
| 配置名 | L2 | J-Link | 状态 |
|--------|-----|--------|------|
| `RocketZCU104Config` | 有 | ✅ 可连 | 当前 FPGA 上烧的 |
| `RocketZCU104NoL2LinuxConfig` | 无 | ✅ 可连 | 有效 |
| `RocketZCU104LinuxBringupConfig` | 有 | ❌ 连不上 | **废弃，不要用** |

# 当前 kernel 关键 config 清单

内核源码：`/root/chipyard/software/firemarshal/boards/default/linux-clean/`
.config 位置：`/root/chipyard/software/firemarshal/boards/default/linux-clean/.config`
内核版本：`6.6.0`，build `#13`

### 已启用（关键项）
| Config | 值 |
|--------|-----|
| `CONFIG_MMU` | y |
| `CONFIG_FPU` | y |
| `CONFIG_RISCV_ISA_C` | y |
| `CONFIG_SPARSEMEM` | y |
| `CONFIG_SPARSEMEM_VMEMMAP` | y |
| `CONFIG_PRINTK` | y |
| `CONFIG_PRINTK_TIME` | y |
| `CONFIG_SERIAL_SIFIVE` | y |
| `CONFIG_SERIAL_SIFIVE_CONSOLE` | y |
| `CONFIG_SERIAL_EARLYCON` | y |
| `CONFIG_TTY` | y |
| `CONFIG_DEVTMPFS` | y |
| `CONFIG_DEVTMPFS_MOUNT` | y |
| `CONFIG_PROC_FS` | y |
| `CONFIG_TMPFS` | y |
| `CONFIG_BLOCK` | y |
| `CONFIG_BLK_DEV_INITRD` | y |
| `CONFIG_INITRAMFS_SOURCE` | `/root/chipyard/fpga/linux-bringup/initramfs/initramfs.cpio` |
| `CONFIG_DMA_COHERENT_POOL` | y |
| `CONFIG_SYSCTL` | y |
| `CONFIG_VIRTIO` | y（含 VIRTIO_MMIO、VIRTIO_BLK、VIRTIO_CONSOLE） |

### 已禁用（关键项）
| Config | 说明 |
|--------|------|
| `CONFIG_MODULES` | 禁用，不加载模块 |
| `CONFIG_NET` | 禁用，无网络栈 |
| `CONFIG_RPMSG_VIRTIO` | 禁用，消除 rpmsg crash |
| `CONFIG_SMP` | 未启用（单核） |

### 总计
- `=y` 选项数：748

# 最新有效产物
- 最新有效 log：
  - L2：`/tmp/boot_L2_compare1.log` + `/tmp/boot_L2_compare1.strings`
  - no-L2：`/tmp/boot_noL2_shortcmd1.log` + `/tmp/boot_noL2_shortcmd1.strings`
  - 历史最好：`/tmp/boot_multi_3_234647.strings`
- klog 原始 bin：`/tmp/klog_L2_compare1.bin`
- 最新 bitstream：
  - `/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Config/obj/ZCU104FPGATestHarness.bit`（2026-04-02）
  - `/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104NoL2LinuxConfig/obj/ZCU104FPGATestHarness.bit`（2026-04-06）
- 最新 DTB：
  - L2 用：`/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb`（4201 bytes）
  - no-L2 用：`/root/chipyard/fpga/linux-bringup/demo-assets/dtb/generated/chipyard-zcu104-nol2-minimal.dtb`（3685 bytes）
- 最新 payload：`/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin`
  - md5: `c446286854a704b1161395696a38246a`
  - 分块在：`/tmp/fw_chunks_new/chunk_0{0,1,2,3}.bin`（4MB × 3 + 2.76MB × 1）
- 最新 initramfs：`/root/chipyard/fpga/linux-bringup/initramfs/initramfs.cpio`（2560 bytes）

# 新窗口先读的 8 个文件

1. `/root/chipyard/fpga/linux-bringup/CHIPYARD_LINUX_BOOT_GUIDE.md` — 本文件
2. `/root/chipyard/fpga/scripts/linux_boot_nol2_direct.gdb` — 主 boot 脚本，理解 Phase 1-4 流程
3. `/root/chipyard/fpga/scripts/run_ps_ddr_init.sh` — FPGA 编程脚本，理解 XSDB 调用
4. `/root/chipyard/fpga/linux-bringup/scripts/build_opensbi_linux_payload.sh` — payload 构建流程
5. `/root/chipyard/software/firemarshal/boards/default/linux-clean/.config` — 当前内核配置
6. `/tmp/boot_L2_compare1.strings` — 最新 L2 crash log
7. `/tmp/boot_noL2_shortcmd1.strings` — 最新 no-L2 crash log
8. `/root/chipyard/fpga/scripts/store_diag.gdb` — SBA 诊断脚本，理解已验证的事实

# 验证 SBA 写完整性（具体执行步骤）

**目的**：确认 GDB SBA `restore binary memory` 写入 DDR 的 payload 是否与原始文件一致。

### 前置条件
- FPGA 已编程（`run_ps_ddr_init.sh`）
- J-Link GDB Server 已在 Windows 启动
- `nc -zv -w3 172.19.128.1 2331` 返回 succeeded

### 步骤 1：写一个 payload 校验 GDB 脚本
创建 `/root/chipyard/fpga/scripts/sba_write_verify.gdb`，内容：
- Phase A：用 `restore binary memory` 把 fw_payload.bin 写入 0x80000000（与正常 boot 流程相同）
- Phase B：立即用 `dump binary memory` 读回 0x80000000 ~ 0x80ec2c08 到 `/tmp/payload_readback.bin`
- 不执行 CPU 任何指令（不 `continue`、不 `stepi`），纯 SBA 写+读

### 步骤 2：执行校验脚本
```bash
cd /root/chipyard/fpga && \
  JLINK_PORT=2331 \
  /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb -batch \
    -x scripts/sba_write_verify.gdb \
  2>&1 | tee /tmp/sba_write_verify.log
```

### 步骤 3：对比分析
```bash
python3 -c "
import sys
orig = open('/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin', 'rb').read()
readback = open('/tmp/payload_readback.bin', 'rb').read()
min_len = min(len(orig), len(readback))
diffs = []
for i in range(min_len):
    if orig[i] != readback[i]:
        diffs.append(i)
print(f'orig={len(orig)} readback={len(readback)} diffs={len(diffs)}')
if diffs:
    for d in diffs[:20]:
        print(f'  offset {d:#010x}: orig={orig[d]:#04x} readback={readback[d]:#04x}')
    if len(diffs) > 20:
        print(f'  ... and {len(diffs)-20} more')
else:
    print('MATCH — SBA write is clean')
"
```

### 解读
- 如果 `diffs=0`：SBA 写是正确的，SBA 读也正确，crash 不是 payload 损坏。回到内核/DTB 调试
- 如果 diffs 呈现末尾 2 字节重复模式：可能只是 SBA **读** 的 bug，需要进一步用 XSDB 交叉验证
- 如果 diffs 是随机位置/随机值：SBA 写路径真的有数据损坏

### 交叉验证（用 XSDB 绕过 SBA）
如果 GDB 读回有差异，需要用 XSDB/XSCT 读同一段内存来排除 SBA 读 bug：
```bash
# 用 XSDB 读回同一个 payload 区域（走 DAP 通路，不走 J-Link SBA）
cd /root/chipyard/fpga && xsdb -eval '
  connect
  targets -set -filter {name =~ "APU*"}
  mrd -bin -file /tmp/payload_xsdb_readback.bin 0x80000000 3868964
  exit
'
# 然后同样做 python3 对比
```

# 下一步最短路径（只保留最有价值的 3 步）
1. 写并执行 `sba_write_verify.gdb`，对比 payload 写入后的读回与原始文件
2. 如果 SBA 写有问题：改用 XSDB `mwr` 写入 payload 绕过 J-Link SBA；如果写没问题：用 `addr2line` 反查 crash EPC 对应的源码行
3. 根据对比结果决定：修复 SBA 传输路径 OR 调试内核页表初始化逻辑

# 不要再犯
- 不要再用 socat relay (port 12331) —— 直连 172.19.128.1:2331 就行，relay 不稳定浪费大量时间
- 不要再用 `RocketZCU104LinuxBringupConfig` —— J-Link 连不上这个配置，原因不明，别再试
- 不要再用 `si`（单步）调试 —— 在这个目标上 si 会 trap 到 PC=0x0，只能用 `hbreak` + `continue`
- 不要再逐个禁用内核驱动来 "移动" crash 点 —— crash 不是特定驱动的 bug，是 payload 数据完整性或页表级别的问题
- 不要忘记：每次 GDB 退出后必须 Windows 侧重启 J-Link GDB Server，否则下次连不上
- klog strings 中的末尾 2 字节重复是 SBA 读 bug，解析 crash 寄存器值时要注意去掉重复（如 `0d0d` 实际是 `0d`）
- PATH 问题：bitstream 编译需要 `PATH="$PWD/scripts:/root/chipyard/.oclaw-env/bin:$PATH"` 前缀，否则找不到 vivado wrapper

# 新窗口首条消息（可直接复制）

```raw
继续 ZCU104 Linux 启动项目。

当前状态：L2 和 no-L2 配置都在 do_one_initcall 阶段 crash（strlen page fault，badaddr ffffff80000000xx）。已确认 SBA 读路径有系统性的 2 字节重复 bug（klog 每行末尾 2 字节重复）。SBA 写路径（用于恢复 payload 到 DDR）是否也有损坏尚未验证。

请先读 /root/chipyard/fpga/linux-bringup/CHIPYARD_LINUX_BOOT_GUIDE.md 了解全部上下文，然后帮我做以下验证：
1. 写一个 GDB 脚本 scripts/sba_write_verify.gdb，在 payload restore 完成后，立即用 dump binary memory 把 0x80000000~0x80ec2c08 读回到 /tmp/payload_readback.bin
2. 然后写 Python 脚本对比 /tmp/payload_readback.bin 和原始 fw_payload.bin，统计差异字节数和位置，并判断差异是否符合"末尾 2 字节重复"的 SBA 读 bug 模式
3. 根据对比结果告诉我 SBA 写入是否可信

J-Link 直连 172.19.128.1:2331，FPGA 上目前烧的是 RocketZCU104Config（有 L2）。运行前需要我先在 Windows 重启 J-Link GDB Server。
```
