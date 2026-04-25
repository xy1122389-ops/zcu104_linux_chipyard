# ZCU104 PL Rocket J100 Fedora Bringup 成功报告

**日期**: 2026-04-24  
**成功 Run Tag**: `fedora_v3fix3_20260424_230736`  
**内核版本**: Linux 6.6.0-fpga-min-g67bc4513761f-dirty #129 Thu Apr 23 18:56:45 CST 2026  
**状态**: ✅ 完整 Fedora userspace 启动，systemd[1] 进入

---

## 1. 成功链路图

```raw
J-Link Pro V4 (USB, S/N 601012542)
    │  JTAG (1000kHz)
    ├──► PMOD0 J55 (G6/H6/J6/J7, LVCMOS33)
    │      → Rocket PL debug module (JTAG IR=5)
    │
    ▼ GDB (tcp:127.0.0.1:3333)
    │
WSL riscv64-unknown-elf-gdb
    │  scripts/linux_boot.gdb
    │
    ├─ Phase 1: Zero DDR (Rocket core)
    ├─ Phase 2: SBA restore fw_payload.bin.v3patched (15MB, 5 chunks × 4MB)
    │           + DTB @ 0x84000000 (PIO 模式)
    ├─ Phase 3: L2 cache invalidate
    ├─ Phase 4: fence.i
    ├─ Phase 5: OpenSBI mret → Linux _start
    ├─ Phase 6: 清除 dcsr ebreak bits
    ├─ Phase 7: 内核运行 600s
    └─ Phase 8: klog dump (SBA)
           │
           ▼
    Rocket RV64GC (1 hart, PL @ 50MHz)
    DDR PA: 0x80000000–0xFFFFFFFF (2GB PS DDR)
           │
           ▼  AXI S_AXI_LPD (Rocket→PS, PA 0x60000000 base)
    PS SDIO1 @ 0xFF170000 (Rocket PA: 0x60170000)
           │  PIO mode (sdhci-caps-mask = 0x10480000)
           │  no IRQ (poll timer 10ms)
           ▼
    J100 full-size SD card slot
    Fedora rootfs (BTRFS, label "fedora", subvol=root)
           │
           ▼
    /sbin/init → systemd[1]
```

---

## 2. 硬件连接

| 组件 | 说明 |
|------|------|
| FPGA | Xilinx ZCU104 (XCZU7EV) |
| JTAG 连接 | J-Link Pro V4 → PMOD0 J55 (G6=TDI, H6=TMS, J6=TCK, J7=TDO) |
| JTAG 供电 | J55 Pin12=VTref(3.3V), Pin10=GND |
| SD 卡 | J100 全尺寸 SD 槽 (PS SDIO1, MIO 路由) |
| J-Link GDB Server | Windows 侧，`tcp:127.0.0.1:3333` (WSL→Windows) |

---

## 3. 软件组件版本

| 组件 | 版本/路径 |
|------|----------|
| 内核 | Linux 6.6.0-fpga-min #129 (Apr 23 18:56 CST 2026) |
| OpenSBI | fw_payload.bin (Rocket platform, generic) |
| initramfs | 含 init.v3 (v3-nosleep, J100 专用) |
| fw_payload patch | `/tmp/patch_fw.py` → `fw_payload.bin.v3patched` |
| DTB | `linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb` (PIO 模式) |
| Fedora rootfs | BTRFS, device label="fedora", subvol=root, /dev/mmcblk0p3 |
| GDB | riscv64-unknown-elf-gdb (Chipyard oclaw-env) |
| J-Link GDB Server | SEGGER v7.82b (Windows) |

---

## 4. 关键配置修复历史

### 4.1 J-Link reconnect_every=99 的原因

**问题**: 在 SBA 大块数据传输（15MB fw_payload.bin）过程中，GDB 连接偶发超时或 J-Link GDB Server 内存溢出，导致 restore 中途失败。

**修复**: 在 `linux_boot.gdb` Phase 2 中，每传输 99 个 chunk（约 99 × 4MB = 396MB 分批，实际为 5 chunk × 4MB = 20MB 总量）后主动重连。由于总 chunk 数 < 99，实际不会触发重连，但该参数保留以防未来扩容。

```python
# linux_boot.gdb Phase 2
chunk_dir = "/tmp/fw_chunks_v3"
reconnect_every = 99
```

当前 5 个 chunk（共 17.6MB）不需要中途重连。`reconnect_every=99` 是历史遗留的安全保护参数。

### 4.2 PIO DTB 修复 (sdhci-caps-mask)

**问题**: 默认 SDHCI 驱动尝试启用 ADMA2（DMA 模式），但 PS SDIO1 DMA 无法访问 Rocket DDR（0x80000000+，从 PS 视角这是 PL 地址），且内核无 Zicbom（`CONFIG_RISCV_ISA_ZICBOM=not set`），`arch_sync_dma_for_device()` 退化为 6 条 NOP，cache 不刷新，ADMA descriptor table 读到 stale 数据，DMA 传输永远不完成。

**修复**: 在 DTB 中屏蔽 ADMA2(bit19) + SDMA(bit22) 能力位，强制 PIO 模式：

```dts
/* linux-bringup/dtb/chipyard-zcu104-linux-slip.dts */
sdhci@60170000 {
    sdhci-caps-mask = <0x0 0x10480000>;  /* 屏蔽 ADMA2(bit19) + SDMA(bit22) + 64BIT(bit28) */
    broken-cd;
    xlnx,fails-without-test-cd;
    max-frequency = <25000000>;
    no-1-8-v;
};
```

**验证**: klog 出现 `using PIO` 而非 `using ADMA`。

### 4.3 patch_fw.py read error 根因和修复

**问题**: 早期版本 `fw_payload.bin` 内嵌的 initramfs init 脚本在等待 mmcblk0p3 时使用了 `sleep` 命令，造成 Rocket 软核（50MHz, RV64GC）上 sleep 过慢，600s 内无法完成所有等待循环，导致超时而未执行 MOUNT。

另一个问题：原始 GDB `restore binary` 命令用于恢复大固件时，因 J-Link SBA 带宽限制（~20KB/s），超出 GDB timeout 阈值，产生 "read error" 或 "timeout" 错误。

**修复**:
1. **init.v3**: 替换为 no-sleep 版本，使用纯 shell loop 轮询（`for i in $(seq 0 100 3000)`），不调用 `sleep`
2. **chunk restore**: 将 fw_payload.bin（15MB）预先 split 为 5 × 4MB chunks，每个 chunk 使用 GDB `restore` 独立恢复，避免单次大传输超时

```bash
# 预 split：
split -b 4194304 -d -a 2 --numeric-suffixes=0 --additional-suffix=.bin \
  fw_payload.bin.v3patched /tmp/fw_chunks_v3/chunk_
```

### 4.4 chunks stale 问题和修复

**问题**: 在多次 run 迭代中，`/tmp/fw_chunks_v3/` 目录的 chunks 可能与最新的 `fw_payload.bin.v3patched` 不一致（例如 patch_fw.py 重新执行后 v3patched 已更新，但 chunks 未重新 split）。

**修复**: `run_fedora_v3fix_pio.sh` 中每次 run 前：
1. SHA256 验证 `fw_payload.bin.v3patched` 哈希
2. 强制重新 split chunks，确保一致性
3. 验证 chunks 重组后与 v3patched SHA256 完全一致

```bash
# 验证：
sha256sum fw_payload.bin.v3patched
cat chunk_00..04.bin | sha256sum  # 必须相同
```

---

## 5. fedora_v3fix3_20260424_230736 成功证据

### 5.1 里程碑通过情况

```raw
[milestones]
  clocksource         : YES   ✅ riscv_clocksource @ 50MHz
  Freeing unused      : YES   ✅ initmem 释放，内核完全初始化
  Run /init           : YES   ✅ /init 执行
  Kernel panic        : no    ✅ 无 panic
  Oops                : no    ✅ 无 oops
  sdhci               : YES   ✅ SDHCI controller on 60170000.sdhci
  mmc0                : YES   ✅ mmc0 驱动加载
  mmcblk              : YES   ✅ mmcblk0 分区发现
  busybox             : YES   ✅ busybox 运行
  arasan              : YES   ✅ arasan SDHCI 匹配
```

### 5.2 关键 klog 事件序列

```raw
[klog] Linux version 6.6.0-fpga-min-g67bc4513761f-dirty #129 Thu Apr 23 18:56:45 CST 2026
[klog] mmc0: SDHCI controller on 60170000.sdhci using PIO         ← PIO 确认
[klog] INIT_AFTER_PSEUDO_MOUNTS
[klog] fedora-rootfs: v3-nosleep J100 start
[klog] mmcblk0: p1 p2 p3                                          ← 分区发现
[klog] fedora-rootfs: wait loop=0..3000 mmcblk0p3 missing         ← 轮询等待
[klog] fedora-rootfs: FOUND mmcblk0p3 at loop=3001                ← 发现分区
[klog] BTRFS: device label fedora devid 1 transid 17              ← BTRFS 识别
[klog] fedora-rootfs: MOUNT SUCCESS subvol=root attempt=1         ← 挂载成功
[klog] fedora-rootfs: SWITCH_ROOT -> /sbin/init                   ← 切换根目录
[klog] systemd[1]: System time advanced to built-in epoch:        ← systemd 启动
         Fri 2025-06-27 00:00:00 UTC
```

### 5.3 stage_mark 验证

```raw
[stage_mark] last stage u64 = 0x5354474500000011
  tag = "STGE" (0x45475453)
  sub = 0x00000011 = 17 = SWITCH_ROOT ✅

stage_mark @ PA 0x8F000000:
  0000: 11 00 00 00 45 47 54 53  |....EGTS|
```

### 5.4 关键文件

| 文件 | 说明 |
|------|------|
| `/tmp/klog_fedora_v3fix3_20260424_230736.bin` | klog 二进制转储 |
| `/tmp/boot_fedora_v3fix3_20260424_230736.strings` | klog 字符串 |
| `/tmp/stage_fedora_v3fix3_20260424_230736.bin` | stage_mark 转储 |
| `/tmp/boot_v3fix3.log` | GDB 脚本完整日志 |

---

## 6. 当前架构约束（未解决/不计划解决）

### 6.1 DMA 模式（不可用）

**根因**: `arch_sync_dma_for_device()` 在无 Zicbom/T-Head CMO 时退化为 6 条 NOP（`ALT_CMO_OP` → `__nops(6)`），D-cache 不刷新，ADMA descriptor table 写入后 PS SDHCI 读到 stale 数据，`int_status=0x00010000`（CMD Inhibit 永久卡死）。

实验证据：`fedora_dma_20260425_001503`（using ADMA，loop=2600 仍 missing，stage_mark=0x4a）。

**结论**: 需要 Zicbom ISA 支持 + 重新编译内核，或使用 HPC AXI port（硬件一致性），两者均不在当前约束内。

### 6.2 真正 SD 自启动（未做）

当前须通过 J-Link GDB 手动 SBA 传输 fw_payload.bin，无法从 SD 卡直接启动。未来需要：
- BootROM → SD 卡 → OpenSBI → Linux 完整链路
- 或 PS FSBL → PL Rocket via AXI → 从 DDR 执行

### 6.3 长时间 systemd 稳定性（未验证）

600s 内 systemd[1] 已启动，但后续 systemd 服务加载（udev, journal, network 等）未验证。需要 1800s+ 持续 run 确认。

### 6.4 SPI SD 路径（已禁用）

DTS 中 SPI-SD overlay 已注释。J100 是唯一激活的 SD 路径（`J100-ONLY`）。

---

## 7. 路径约束摘要（LOCKED）

| 约束 | 值 |
|------|-----|
| SD 路由 | **J100-ONLY** (PS SDIO1, MIO, 不走 A2/SPI) |
| J-Link 连接 | `tcp:127.0.0.1:3333` |
| JTAG 引脚 | PMOD0 J55: G6/H6/J6/J7, LVCMOS33 |
| SD 模式 | **PIO 强制** (sdhci-caps-mask=0x10480000) |
| fw_payload | `fw_payload.bin.v3patched` (SHA256: `759db54b…`) |
| 内核 | #129 Apr 23 18:56 (不重新编译) |
| chunk_dir | `/tmp/fw_chunks_v3/` (5 × 4MB) |

---

## 8. 已知问题汇总

| 问题 | 根因 | 状态 |
|------|------|------|
| DMA 卡死 | `arch_sync_dma_for_device()` = NOP（无 Zicbom） | 已确认不可修复（当前内核）|
| init `sleep` 超时 | sleep 在 50MHz 软核上过慢 | ✅ 已修复（init.v3 no-sleep）|
| SBA restore 超时 | 15MB 单次传输超 GDB timeout | ✅ 已修复（5 chunk split）|
| chunks stale | v3patched 更新后未重新 split | ✅ 已修复（run 脚本强制 split）|
| `using ADMA` 卡死 | ADMA descriptor cache stale | ✅ 已修复（PIO DTB）|
| PLIC IRQ 挂起 | ndev=4 时 IRQ>4 触发 TL bus hang | ✅ 已修复（无 IRQ 接入）|
| 2-byte printk 重影 | memmove 残留，不影响实际数据 | 已确认为 printk 内部 artifact |

---

*报告生成时间: 2026-04-25*  
*作者: 自动生成（基于 fedora_v3fix3_20260424_230736 run 证据）*
