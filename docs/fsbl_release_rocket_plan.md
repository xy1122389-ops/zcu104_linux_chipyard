# FSBL 强化计划 — ZCU104 SD 自引导 (Phase E)

**版本**: v0  
**日期**: 2026-04-25  
**依赖**: Phase C/D (sd_loader_v0 实现) 完成后实施

---

## E.1 当前初始化流程 (XSDB 手动模式)

```raw
上电
  └─ ZynqMP BootROM (ARM) → JTAG 引导模式
       └─ XSDB: connect → psu_init → fpga(bitstream) → isolation_removal
            └─ Rocket 释放, BootROM 开始运行
                 └─ DDR 测试 → 轮询 0x80001000
                      └─ J-Link GDB 写入 fw_payload
                           └─ BootROM 跳转 → OpenSBI → Linux → Fedora
```

**问题**: 每次启动需要 XSDB + J-Link GDB 介入，无法自主引导。

---

## E.2 目标初始化流程 (SD 自引导模式)

```raw
SD 卡 FAT p1 分区放置:
  ├── BOOT.BIN   (FSBL + bitstream + ARM stub)
  └── boot.scr   (可选)

上电, Boot Mode = SD1 (MIO)
  └─ ZynqMP BootROM (ARM) → 从 SD p1 读取 BOOT.BIN
       └─ FSBL 运行:
            1. psu_init (DDR, clocks, MIO 配置)
            2. fpga(ZCU104FPGATestHarness.bit)  ← 从 BOOT.BIN 提取
            3. psu_ps_pl_isolation_removal       ← 立即! 不等待
            4. ARM stub: WFE 循环 (不干扰 PL)
       └─ Rocket 自动释放 (PS-PL isolation 解除后)
            └─ BootROM (sd_loader_v0): SDHCI PIO 读取 SD raw sectors
                 └─ fw_payload + DTB → OpenSBI → Linux → Fedora
```

---

## E.3 BOOT.BIN 内容构成

ZynqMP BOOT.BIN 使用 Bootgen 工具生成，包含以下分区：

```raw
BOOT.BIN
├── FSBL (First Stage Boot Loader)
│   ├── psu_init.tcl 对应的初始化代码 (内嵌)
│   ├── 关键: AFIFM2=128-bit, AFIFM6=32-bit
│   └── 关键: MIO 46-51 = SDIO1
├── Bitstream: ZCU104FPGATestHarness.bit
└── ARM stub: arm_stub.elf (WFE 循环，释放 Rocket 后 ARM 永久休眠)
```

### E.3.1 Bootgen BIF 文件

```raw
// zcu104_sdboot.bif
the_ROM_image:
{
    [bootloader, destination_cpu=a53-0] fsbl_a53.elf
    [destination_device=pl] ZCU104FPGATestHarness.bit
    [destination_cpu=a53-0, exception_level=el-3] arm_stub.elf
}
```

生成命令:
```bash
bootgen -image zcu104_sdboot.bif -arch zynqmp -o BOOT.BIN -w on
```

---

## E.4 FSBL 关键配置要求

### E.4.1 psu_init 必须配置

以下是 `xsdb_stable_init.tcl` 中 `psu_init` 执行的关键初始化，  
FSBL 内嵌的 psu_init 必须包含相同配置：

| 寄存器 | 地址 | 期望值 | 用途 |
|--------|------|--------|------|
| AFIFM2_RDCTRL | 0xFD380000 | 0x0 | S_AXI_HP0 读 = 128-bit |
| AFIFM2_WRCTRL | 0xFD380014 | 0x0 | S_AXI_HP0 写 = 128-bit |
| AFIFM6_RDCTRL | 0xFF9B0000 | 0x2 | S_AXI_LPD 读 = 32-bit |
| AFIFM6_WRCTRL | 0xFF9B0014 | 0x2 | S_AXI_LPD 写 = 32-bit |
| SDIO1_REF_CTRL | 0xFF5E0070 | 见 psu_init_gpl.c | SDIO1 时钟使能 |
| MIO_PIN_46 | 0xFF1800B8 | 0x10 | SDIO1 DAT0 |
| MIO_PIN_47 | 0xFF1800BC | 0x10 | SDIO1 DAT1 |
| MIO_PIN_48 | 0xFF1800C0 | 0x10 | SDIO1 DAT2 |
| MIO_PIN_49 | 0xFF1800C4 | 0x10 | SDIO1 DAT3 |
| MIO_PIN_50 | 0xFF1800C8 | 0x10 | SDIO1 CMD |
| MIO_PIN_51 | 0xFF1800CC | 0x10 | SDIO1 CLK |

MIO 配置来源：`psu_init_gpl.c` (L2_SEL=2 → SDIO1)。

### E.4.2 PS-PL Isolation 解除时序

**关键**: 必须在 bitstream 编程完成后**立即**解除 PS-PL isolation，  
不能延迟超过 500ms，否则 Rocket BootROM 到达 DDR 测试时 AXI 通路未开放，  
导致 TileLink bus hang，核心永久挂死（调试模块也无法 halt）。

```tcl
# 正确时序 (来自 xsdb_stable_init.tcl):
fpga $bit_file                     # 1. 加载比特流
psu_ps_pl_isolation_removal        # 2. 立即解除 isolation (< 1ms 后)
# 不需要 after 等待 — BootROM 会自己完成 DDR 测试
```

FSBL C 代码中对应的调用：
```c
// FSBL 中 XFsbl_FabricInit() 之后，FSBL 必须调用:
Status = XFsbl_IsolationRestore();  // ← 比特流后立即调用
if (Status != XFSBL_SUCCESS) {
    XFsbl_Printf("Isolation removal failed!\r\n");
}
```

### E.4.3 Card Detect 绕过

ZCU104 J100 microSD 没有 Card Detect 引脚直接连到 MIO。  
DTB 中已配置 `broken-cd` + `xlnx,fails-without-test-cd`。

在 sd_loader_v0 裸机代码中，不需要检查 CD 引脚，直接初始化卡即可。  
SDHCI Present State 寄存器的 CARD_DETECT_SIGNAL 位在 `broken-cd` 情况下被忽略。

**裸机处理方式**:  
在 sd_loader_v0 中，直接执行 CMD0 初始化，如果没有回应则重试或报错。

---

## E.5 ARM Stub (arm_stub.elf)

FSBL 加载完 bitstream + isolation_removal 后，需要一个 ARM "application" 不干扰 PL。

最小 ARM stub (AArch64 裸机):

```asm
// arm_stub.S - 加载到 EL3 后立即 WFE 循环
.globl _start
_start:
1:
    wfe
    b 1b
```

编译：
```bash
aarch64-linux-gnu-gcc -nostartfiles -nostdlib -o arm_stub.elf arm_stub.S
```

该 stub 占用极小空间（< 64 字节），仅确保 FSBL 有"第三阶段"可加载。

---

## E.6 SD 卡分区要求

为支持 FSBL SD 引导，SD 卡 p1 分区必须是 FAT32 格式，并包含：

```raw
p1 (FAT32, 建议 256MB):
├── BOOT.BIN
└── (可选) boot.scr, uEnv.txt

p2: (Fedora /boot, ext4 — 已存在)
p3: (Fedora rootfs, btrfs — 已存在, NEVER TOUCH)
```

> **注意**: p1 必须在 LBA 67594 以上（参见 Phase B sd_raw_boot_layout.md）。  
> BOOT.BIN + 固件 raw sectors 都在 LBA 0-65546 范围内，与 p1 FAT32 不冲突。

---

## E.7 Boot Mode 配置 (ZCU104 SW6)

ZCU104 通过 SW6 DIP 开关选择引导模式：

| 模式 | SW6[4:1] | 说明 |
|------|----------|------|
| JTAG | 0000 | 当前使用模式 |
| SD1 (J100) | 1110 | SD 自引导模式（目标） |
| QSPI | 0010 | 不使用 |

切换到 SD 引导：`SW6 = 1110`（bit4=1, bit3=1, bit2=1, bit1=0，从低到高）

> ⚠️ **在完成 sd_loader_v0 验证前，不要切换 Boot Mode！**  
> 应先用 XSDB 模拟完整流程，确认 sd_loader_v0 能正确读卡并跳转，  
> 然后才切换 Boot Mode 到 SD1。

---

## E.8 FSBL 构建方式

### 选项 A: 使用 Xilinx 预编译 FSBL (推荐用于初期验证)

Vivado 2021.2 SDK 可以生成标准 ZCU104 FSBL。在 Vivado 中：

```raw
File → New Project (Hardware Platform) → ZCU104
→ File → Export → Export Hardware (include bitstream)
→ Vitis → New Platform Project → ZCU104 BSP
→ Generate FSBL application
→ Build → fsbl_a53.elf
```

### 选项 B: 最小化修改版 FSBL

修改官方 FSBL 的 `xfsbl_main.c`，在 `XFsbl_IsolationRestore()` 后：
1. 添加 AFIFM2/AFIFM6 验证日志
2. 确保不触碰 SDIO1 寄存器（让 psu_init 的配置保持）
3. 调用 `XFsbl_JumpToHypervisor(arm_stub)` 进入 WFE

---

## E.9 关键验证步骤

在切换到 SD 引导前，用 XSDB 模拟完整流程验证：

```tcl
# 1. 正常 XSDB 初始化 (psu_init + fpga + isolation)
source xsdb_stable_init.tcl

# 2. 验证 AFIFM 设置
mrd -force 0xFD380000  # 期望: 0 (AFIFM2 RD = 128-bit)
mrd -force 0xFD380014  # 期望: 0 (AFIFM2 WR = 128-bit)
mrd -force 0xFF9B0000  # 期望: 2 (AFIFM6 RD = 32-bit)
mrd -force 0xFF9B0014  # 期望: 2 (AFIFM6 WR = 32-bit)

# 3. 验证 SD 卡 raw sector 写入 (在主机上先 dd 写好 fw+dtb)
# 4. 通过 J-Link 监控 Rocket BootROM 的 UART 输出
# 5. 确认 "[sdboot] sdhci init ok" 等打印出现
```

---

## E.10 实施顺序

```raw
Phase C/D 完成 (sd_loader_v0 实现 + 比特流重建)
    │
    ↓
E.1 构建 arm_stub.elf
    │
E.2 生成 FSBL (Vitis 或 Xilinx 预编译)
    │
E.3 创建 BOOT.BIN (bootgen)
    │
E.4 写入 SD 卡:
    - BOOT.BIN → FAT32 p1
    - fw_payload → raw LBA 4096
    - DTB → raw LBA 65536
    - Manifest → raw LBA 2048
    │
E.5 XSDB 验证 (仍用 JTAG 模式) — 确认 sd_loader_v0 工作
    │
E.6 切换 SW6 → SD1 引导模式
    │
E.7 完整 SD 自引导测试 (无 XSDB/J-Link 介入)
```

---

## E.11 已知风险

| 风险 | 来源 | 缓解措施 |
|------|------|---------|
| FSBL 延迟 isolation_removal | FSBL 代码路径 | 检查 FSBL 源码中 XFsbl_FabricInit 后是否立即调用 IsolationRestore |
| psu_init DDR 配置与当前 TCL 不一致 | Vivado 生成的 psu_init.tcl 有 64-bit DDR bug | 必须用修正后的 psu_init.tcl（参见 `/memories/repo/` 中的 DDR bug 记录） |
| AFIFM6 未配置为 32-bit | FSBL 默认 AFIFM6=64-bit | FSBL 后置检查: mrd 0xFF9B0000 必须 = 2 |
| ARM boot core 与 Rocket 竞争 SDIO | ARM FSBL 完成后留在 SDIO 驱动 | arm_stub WFE 循环后不再访问 SDIO1 |
| BOOT.BIN 超过 SD p1 起始位置 | BOOT.BIN > 33MB | BOOT.BIN 典型大小 < 20MB，安全 |
