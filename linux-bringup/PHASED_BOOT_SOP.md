# 分阶段可控启动 SOP
# ZCU104 ZynqMP + Rocket RISC-V — JTAG 受控启动 → SD selfboot

## 总体策略

从 JTAG 完全可控状态开始，逐步验证每一层：
```raw
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
JTAG模式    PS链路    Rocket PC  DDR内容   Linux进入   SD全自动
```

每个 Phase 通过后才进入下一个。如果任何 Phase 失败 → 停在该 Phase 诊断。

---

## Phase 0: SW6 切换到 JTAG 模式

### 操作步骤

1. **断电** ZCU104（拨掉电源开关）

2. **切换 SW6** (6 位 DIP 开关，active-LOW = ON=0，OFF=1):

   | 目标模式 | MODE[3] | MODE[2] | MODE[1] | MODE[0] | SW6 实物 |
   |---------|---------|---------|---------|---------|---------|
   | **JTAG** (调试) | OFF | OFF | OFF | OFF | 全部 OFF |
   | SD1 SDR50 (selfboot) | ON | ON | ON | OFF | 前3个ON，最后OFF |

   **JTAG 模式**: 所有 SW6 拨到 OFF 位置 (PS_MODE[3:0]=0b0000)

3. **上电** ZCU104

4. **验证**: 用 XSDB 看到 PSU / APU / DAP 目标
   如果上电后 targets 为空 → SW6 可能未正确切换

---

## Phase 1: 验证 PS 侧链路 (PMUFW/FSBL/bitstream/arm_stub)

### 前提
- SW6 处于 JTAG 模式
- BOOT_v2.BIN 在 SD p1 (不会被访问，仅备用)
- PS JTAG (USB J4 / FT4232H) 连接到 Windows

### 运行命令
```bash
cd /root/chipyard/fpga
bash scripts/phase1_verify_ps_chain.sh
```

或者指定特定 config:
```bash
bash scripts/phase1_verify_ps_chain.sh --cfg RocketZCU104LinuxBringupConfig
```

### 成功标准 (全部满足)
- [ ] XSDB `targets` 输出中有 `PSU`, `APU`, `A53#0`
- [ ] DS35 (DONE) LED 变绿 ← PL bitstream 加载成功
- [ ] DS1 (PS_OK) LED 变绿 ← FSBL 运行成功
- [ ] psu_init 无 `AP transaction timeout` 错误
- [ ] PCAP_CTRL bit0=1 (PL configured)
- [ ] OCM 0xFFFC0000 非零 (FSBL code 在此)
- [ ] PS UART COM6 有 FSBL 输出 (115200 8N1)
- [ ] arm_stub at 0xFFFEA000: A53 在 EL3 WFE loop

### 失败诊断
| 症状 | 原因 | 解决 |
|------|------|------|
| XSDB targets 为空 | SW6 未切到 JTAG | 检查 SW6 设置 |
| psu_init AP timeout | DDR 配置错误 | 检查 psu_init.tcl 版本 |
| DS35 不亮 | bitstream 未加载 | 检查 XSDB 报错 |
| DS1 红灯 | FSBL 失败 (OCM 无代码) | 检查 FSBL ELF 完整性 |

---

## Phase 2: Rocket PC 检查 (无 payload)

### 前提
- Phase 1 通过
- J-Link 硬件连接: J55 PMOD0 (G6/H6/J6/J7)
- J-Link Pro S/N 601012542

### 运行命令
```bash
cd /root/chipyard/fpga
bash scripts/phase2_check_rocket_pc.sh
```

### 成功标准
- [ ] J-Link IDCODE 正确 (RISC-V debug spec 0.13, IR len 5)
- [ ] J-Link 可 halt Rocket (无 halt timeout)
- [ ] PC 落在 BootROM 范围 (0x10000~0x1FFFF)
- [ ] BootROM 内容非零 (TLROM 代码在此)
- [ ] mcause=0 (无异常)

### 如果 Phase 1 通过但 Phase 2 J-Link 失败
```raw
J-Link 连不上 ≠ bitstream 没加载
检查顺序:
  1. J-Link USB 驱动 (VID_1366 Status=OK?)
  2. VMware USB 仲裁冲突 → Stop-Service VMUSBArbService
  3. 断电重上电后 JTAG TAP 未恢复 → 检查 VTref 电压
  4. PMOD0 接线确认 (G6/H6/J6/J7 对应 TDI/TMS/TCK/TDO)
```

---

## Phase 3: sd_loader DDR 内容验证

### 前提
- Phase 1 + Phase 2 通过
- SD 卡 p2 有 manifest + fw_payload + DTB
- J-Link GDB Server 正在运行 (phase2 已启动)

### 运行命令
```bash
cd /root/chipyard/fpga
bash scripts/phase3_check_ddr_payload.sh
```

### 成功标准
- [ ] 0x80000000 非零 + RISC-V JAL/ELF magic (OpenSBI 入口)
- [ ] 0x84000000 = 0xD00DFEED (DTB magic)
- [ ] 0x82000000 非零 (payload 中段，确认完整加载)

### sd_loader 地址布局参考
```raw
p2 扇区布局:
  +0 (manifest)   : SD p2 sector 0
  +2048 (fw)      : SD p2 sector 2048  → DDR 0x80000000
  +98304 (dtb)    : SD p2 sector 98304 → DDR 0x84000000

fw_payload 约 50MB，sd_loader 加载需要约 10-20 秒
如果 15s 后 DDR 仍为 0:
  → sd_loader 还在运行 → 增加 PHASE3_WAIT_SECS=30 重试
  → 或者 sd_loader 从未启动 → 检查 Phase 2 BootROM 内容
```

---

## Phase 4: OpenSBI/Linux 进入检查

### 前提
- Phase 1-3 全部通过

### 运行命令
```bash
cd /root/chipyard/fpga
bash scripts/phase4_check_opensbi_linux.sh

# 可调整运行时间 (默认 60s)
PHASE4_RUN_SECS=120 bash scripts/phase4_check_opensbi_linux.sh
```

### 成功标准
- [ ] PC 最终落在 DDR 范围 (0x80000000+) 或 kernel VA (0xffffffff8xxxxxxx)
- [ ] PS UART COM6 有 Linux 输出 (监听: 115200 8N1)
- [ ] klog 有 "Linux version" 或 "OpenSBI" 文本
- [ ] stage_mark @ 0x8F000000 非零 (若 /init 执行)

---

## Phase 5: SW6 切到 SD boot 全自动测试

### 仅在 Phase 1-4 全部通过后执行

1. **断电** ZCU104

2. **切换 SW6** 到 SD1 SDR50 模式:
   - MODE[0]=OFF, MODE[1]=ON, MODE[2]=ON, MODE[3]=ON
   - (SW6: 1=OFF, 2=ON, 3=ON, 4=ON — 从右往左)

3. **上电**，监控 PS UART COM6

4. 观察 DS35 + DS1 是否变绿 + UART 有 FSBL/Linux 输出

---

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/phase1_verify_ps_chain.sh` | Phase 1: PS 链路验证 (XSDB) |
| `scripts/phase1_verify_ps_chain.tcl` | Phase 1 TCL 脚本 |
| `scripts/phase2_check_rocket_pc.sh` | Phase 2: Rocket PC 只读检查 |
| `scripts/phase2_check_rocket_pc.gdb` | Phase 2 GDB 脚本 |
| `scripts/phase3_check_ddr_payload.sh` | Phase 3: DDR payload 验证 |
| `scripts/phase3_check_ddr_payload.gdb` | Phase 3 GDB 脚本 |
| `scripts/phase4_check_opensbi_linux.sh` | Phase 4: Linux 进入检查 |
| `scripts/phase4_check_opensbi_linux.gdb` | Phase 4 GDB 脚本 |
| `scripts/run_ps_ddr_init.sh` | 现有: 完整 PS 初始化 + 释放 Rocket |
| `scripts/run_ps_ddr_init_no_release.sh` | 现有: PS 初始化但不释放 Rocket |
| `scripts/jlink_jtag_diag.sh` | 现有: J-Link JTAG 链诊断 |

---

## 禁止事项 (PERMANENT LOCK)

- ❌ 不要重写 SD 卡
- ❌ 不要重分区
- ❌ 不要启用 DMA (PIO 模式唯一可行)
- ❌ 不要一上来就跑 `linux_boot.gdb` restore payload
- ❌ 不要把 J-Link 连不上等同于 bitstream 没加载
- ❌ 不要在任何 Phase 未通过时跳到下一个 Phase

## 关键硬件配置 (PERMANENT — DO NOT CHANGE)

- J-Link JTAG: J55 PMOD0 — TDI=G6, TMS=H6, TCK=J6, TDO=J7
- J55 Pin 12 = VTref, Pin 10 = GND
- IOSTANDARD: LVCMOS33
- J87 PMOD1 = UART (TX/RX), 不是 JTAG
- PS UART: FT4232H Channel B = COM6, 115200 8N1
- SD 启动: J100 MicroSD = SD1 (PS MIO 46-51)
- sdhci-of-arasan PIO 模式: caps-mask=0x10480000
