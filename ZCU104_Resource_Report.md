# 八、正式版资源报告（ZCU104 — RocketZCU104LinuxBringupConfig + UART1）

- **设计名称**: `ZCU104FPGATestHarness`
- **目标器件**: `xczu7ev-ffvc1156-2-e`（Xilinx ZCU104 开发板）
- **Vivado 版本**: v2021.2 (win64)
- **报告日期**: 2026-04-06（Post-Route Physopt）
- **主时钟**: `clk_out1_harnessSysPLL` = 50 MHz（周期 20 ns）

## 资源利用率总表

| 类别 | 指标 | 当前数值 | 器件总量 | 占用比例 | 备注 |
|:------:|:------|----------:|---------:|----------:|:------|
| Logic | LUT | 47,057 | 230,400 | **20.4%** | 含 Logic LUT 43,431 + LUTRAM 3,608 + SRL 18 |
| Logic | FF | 23,908 | 460,800 | **5.2%** | 触发器占用率很低 |
| Memory | LUTRAM | 3,608 | 101,760 | **3.5%** | 分布式 RAM（含 Queue/Buffer） |
| Memory | BRAM (36Kb) | 136 | 312 | **43.6%** | 主要消耗者：L2 Cache (120) + Scratchpad (16) |
| Memory | BRAM (18Kb) | 84 | 624 | **13.5%** | |
| Memory | BRAM（等效 36Kb） | 178 | 312 | **57.1%** | = 136×36Kb + 84×18Kb/2 |
| Memory | URAM | 0 | 96 | **0.0%** | 未使用 |
| Compute | DSP48E2 | 25 | 1,728 | **1.4%** | |
| Clocking | BUFG/MMCM/PLL | 1 MMCM | 4 MMCM / 8 PLL | **25.0%** (MMCM) | harnessSysPLL: 125 MHz → 50 MHz |
| IO | IO Pins | 17 | ~240 | **~7.1%** | 详见下方引脚分配表 |
| Timing | WNS (Setup) | +8.522 ns | — | — | ✅ 正值 = 时序满足 |
| Timing | TNS (Setup) | 0.000 ns | — | — | ✅ 无违例 |
| Timing | Fmax / 关键时钟 | **87.1 MHz** | 目标 50 MHz | 余量 74% | Fmax = 1/(20−8.522) ns |

## IO 引脚分配详情

| 信号 | 引脚 | 电平标准 | 用途 |
|:------|:------|:---------|:------|
| sys_clock_p | F23 | LVDS | 125 MHz 差分参考时钟（P） |
| sys_clock_n | E23 | LVDS | 125 MHz 差分参考时钟（N） |
| uart_txd | J9 | LVCMOS33 | UART0 TX（控制台） |
| uart_rxd | K9 | LVCMOS33 | UART0 RX（控制台） |
| **uart1_txd** | **K8** | **LVCMOS33** | **UART1 TX（SLIP 网络）— PMOD1_3** |
| **uart1_rxd** | **L8** | **LVCMOS33** | **UART1 RX（SLIP 网络）— PMOD1_2** |
| sdio_spi_clk | E12 | LVCMOS18 | SD 卡 SPI 时钟 |
| sdio_spi_cs | F11 | LVCMOS18 | SD 卡 SPI 片选 |
| sdio_spi_dat_0 | D12 | LVCMOS18 | SD 卡 SPI 数据 0 |
| sdio_spi_dat_1 | C12 | LVCMOS18 | SD 卡 SPI 数据 1 |
| sdio_spi_dat_2 | B12 | LVCMOS18 | SD 卡 SPI 数据 2 |
| sdio_spi_dat_3 | A12 | LVCMOS18 | SD 卡 SPI 数据 3 |
| jtag_jtag_TDI | G6 | LVCMOS33 | JTAG 调试 |
| jtag_jtag_TMS | H6 | LVCMOS33 | JTAG 调试 |
| jtag_jtag_TCK | J6 | LVCMOS33 | JTAG 调试 |
| jtag_jtag_TDO | J7 | LVCMOS33 | JTAG 调试 |
| gpio_led_2_ls | A5 | LVCMOS33 | 心跳 LED |

## 时钟域

| 时钟名 | 周期 (ns) | 频率 (MHz) | 来源 |
|:-------|----------:|----------:|:------|
| sys_clock | 8.000 | 125.000 | 板载晶振（差分 LVDS） |
| clk_out1_harnessSysPLL | 20.000 | 50.000 | MMCM 分频（Rocket Core 主时钟） |
| clk_pl_0 | 10.312 | 96.974 | PS 输出时钟（Zynq US+ PS Block） |

## 主要模块资源分布

| 模块 | LUT | FF | BRAM36 | 说明 |
|:------|------:|------:|------:|:------|
| DigitalTop (system) | 43,150 | 19,384 | 136 | SoC 核心（含下列子模块） |
| └ L2 InclusiveCache (l2) | 5,534 | 2,691 | 120 | L2 缓存（最大 BRAM 消耗） |
| └ PeripheryBus (cbus) | 2,150 | 566 | 0 | 外设总线 + 原子操作 |
| └ ScratchpadBank (bank) | 215 | 113 | 16 | 片上 Scratchpad RAM |
| └ BootROM | 856 | 0 | 0 | LUT 实现的启动 ROM |
| Shell / Harness | 3,904 | 4,524 | 0 | IO overlay + PS wrapper |

## 结论

- **时序裕量充足**：WNS = +8.522 ns，Fmax 可达 87 MHz（目标 50 MHz），余量 74%
- **LUT 占用适中**（20.4%），FF 极低（5.2%），有大量空间加功能
- **BRAM 是瓶颈资源**：等效 36Kb 占用 **57.1%**，主要被 L2 InclusiveCache 消耗（120/312 = 38.5%）
- **UART1 新增资源开销极小**：仅增加 2 个 IO 引脚 + 少量 LUT/FF（UART 控制器）
- **所有时序约束均满足**，TNS = 0，无 setup/hold 违例
