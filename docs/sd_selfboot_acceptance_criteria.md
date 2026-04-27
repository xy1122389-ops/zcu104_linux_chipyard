# SD 自引导验收标准 — ZCU104 PL Rocket J100 (Phase F)

**版本**: v0  
**日期**: 2026-04-25  
**依赖**: Phase A-E 全部完成

---

## F.1 验收目标

ZCU104 插入 SD 卡后，**无需任何外部工具（XSDB/J-Link/GDB）介入**，  
在上电 60 秒内完成从 Rocket BootROM 到 Fedora systemd 的完整引导。

---

## F.2 必要的硬件状态

| 检查项 | 期望状态 |
|--------|---------|
| ZCU104 Boot Mode (SW6) | SD1 模式 (1110) |
| SD 卡插入 J100 | 已插入 |
| UART 连接 | J83 USB UART 连接到主机 |
| J-Link | **不需要连接** (SD 自引导时不使用) |
| SD 卡 p1 (FAT32) | 包含 BOOT.BIN |
| SD 卡 raw sectors | fw_payload @ LBA 4096, DTB @ LBA 65536, Manifest @ LBA 2048 |
| SD 卡 p3 (btrfs) | Fedora rootfs 完整，未被污染 |

---

## F.3 必须按序出现的日志字符串

以下字符串必须在 UART 串口（115200 bps）中**按顺序**出现：

### F.3.1 FSBL 阶段 (ARM, 串口 J83)

```raw
Xilinx First Stage Boot Loader
...
FSBL done
```

或自定义 FSBL 输出（如有）。

### F.3.2 BootROM 阶段 (Rocket UART, 115200 bps, 串口 J83)

必须包含（顺序）：

```raw
[NEWBIT] ds39-uart-build-*
[sdboot] sd_loader_v0 start
[sdboot] sdhci reset ok
[sdboot] card init ok
[sdboot] manifest ok  magic=53445230 version=1
[sdboot] loading fw_payload...  size=17628680 lba=4096
[sdboot] fw ok
[sdboot] fw crc32 ok
[sdboot] dtb ok
[sdboot] jumping to 0x80000000  a0=0 a1=84000000
```

### F.3.3 OpenSBI 阶段

```raw
OpenSBI v*.*
Platform Name: Generic
```

### F.3.4 Linux 内核阶段

```raw
[    0.000000] Linux version 6.6.0-fpga-min-g67bc4513761f-dirty #129 Thu Apr 23 18:56:45 CST 2026
[    0.000000] earlycon: sifive0 at MMIO 0x0000000064000000 (options '115200n8')
```

SD 驱动加载：

```raw
[    *.******] mmc0: SDHCI controller found [arasan,sdhci-8.9a]
[    *.******] mmc0: new high speed SDHC card at address 0001
[    *.******] mmcblk0: mmc0:0001
[    *.******]  mmcblk0: p1 p2 p3
```

PIO 模式确认（必须**没有**以下字符串）：

```raw
# 以下字符串不得出现 (DMA 相关):
"mmc0: ADMA error"
"sdhci: ADMA"
"mmc0: SDMA"
```

### F.3.5 Fedora userspace 阶段

```raw
[    *.******] Freeing unused kernel image
[    *.******] Run /init as init process
Welcome to Fedora Linux *
[  OK  ] Started Journal Service.
systemd[1]: Detected architecture riscv64.
```

---

## F.4 量化验收指标

| 指标 | 最小值 | 期望值 |
|------|--------|--------|
| 上电到 `systemd[1]` | < 90s | < 60s |
| BootROM sd_loader_v0 读取时间 | < 15s | < 10s |
| fw_payload CRC32 验证 | 必须通过 | - |
| DTB magic 匹配 | 必须匹配 (0xD00DFEED) | - |
| stage_mark @ 0x8F000000 | ≥ 0x5354474500000010 | ≥ 0x5354474500000011 |
| Fedora 持续运行时间 | ≥ 60s (无 panic) | ≥ 300s |

---

## F.5 自动化验收脚本框架

```bash
#!/bin/bash
# sd_selfboot_acceptance_test.sh

set -euo pipefail

UART_DEV=${UART_DEV:-/dev/ttyUSB0}
BAUD=115200
TIMEOUT_BOOT=120    # 上电到 systemd 的最大允许时间(秒)
TIMEOUT_STABLE=300  # 稳定运行时间

echo "[test] 监听 UART: $UART_DEV @ $BAUD"
echo "[test] 请上电 ZCU104 (或按 POR)..."

# 捕获 UART 输出到日志
LOG="/tmp/sd_selfboot_$(date +%Y%m%d_%H%M%S).log"
stty -F $UART_DEV $BAUD raw -echo
timeout $TIMEOUT_BOOT cat $UART_DEV | tee $LOG &
CAT_PID=$!

# 等待关键字符串
check_string() {
    local str="$1"
    local wait=$2
    timeout $wait grep -q "$str" <(tail -f $LOG) && echo "[PASS] found: $str" || {
        echo "[FAIL] timeout waiting for: $str"
        return 1
    }
}

check_string "sd_loader_v0 start"     30
check_string "card init ok"           40
check_string "manifest ok"            40
check_string "fw crc32 ok"            60
check_string "jumping to 0x80000000"  70
check_string "Linux version 6.6.0"    80
check_string "mmcblk0: p1 p2 p3"      90
check_string "systemd\[1\]"           $TIMEOUT_BOOT

echo ""
echo "=== ACCEPTANCE TEST PASSED ==="
echo "Log: $LOG"
```

---

## F.6 Negative Tests (必须确认不发生)

| 场景 | 期望结果 |
|------|---------|
| fw_payload CRC32 故意写错 | BootROM 打印 "fw crc32 mismatch" 并 halt (LED 错误闪烁) |
| Manifest magic 错误 | BootROM 打印 "manifest magic mismatch" 并 halt |
| SD 卡未插入 | BootROM 卡在 "sdhci init" 或 "card init" 阶段，重试后 halt |
| DTB magic 错误 | BootROM 打印 "dtb magic mismatch" 并 halt |
| ADMA 误启用 | 内核打印 "ADMA error" → **此情况不得发生** |

---

## F.7 与 Golden Baseline 的对比

| 项目 | Golden Baseline (Phase A) | SD 自引导目标 |
|------|--------------------------|-------------|
| 引导触发 | J-Link GDB + XSDB | 上电自动 |
| fw_payload 来源 | GDB SBA 写入 DDR | SD raw sector 读取 |
| 引导时间 | ~40 分钟 (GDB SBA) | < 90 秒 |
| 工具依赖 | XSDB + J-Link + GDB | 无 |
| fw_payload SHA256 | 759db54b... (相同) | 759db54b... (相同) |
| DTB | 相同 | 相同 |
| 内核版本 | #129 Apr 23 | 相同 |
| Fedora rootfs | 相同 | 相同 |
| PIO 模式 | sdhci-caps-mask=0x10480000 | 相同 |

---

## F.8 不变约束 (从 Phase A-E 延续)

1. **J100-ONLY**: 所有 SD 访问通过 PS SDIO1 @ Rocket PA 0x60170000
2. **PIO ONLY**: 永不使用 DMA (物理上不可能)
3. **不解析文件系统**: 第一版完全用 raw sector 寻址
4. **不修改 fw_payload**: SHA256 = 759db54b9bebf2b77945b5b7e861517f564443d370bd1efe4625538f8de31480
5. **不修改内核**: Linux #129 Apr 23 锁定
6. **不破坏 Fedora p3**: btrfs rootfs 不可污染
7. **如修改比特流**: 必须独立提交，Golden Baseline 路径仍可用

---

## F.9 回归测试要求

在每次 sd_loader_v0 代码变更后，必须同时通过：

1. **SD 自引导验收测试** (本文档 F.3-F.5)
2. **Golden Baseline 回归测试**:
   KERNEL_RUN_SECS=300 bash /root/chipyard/fpga/run_fedora_v3fix_pio.sh
   # 期望: stage_mark >= 0x5354474500000011
```raw

两者都必须通过，才能视为变更合格。

```