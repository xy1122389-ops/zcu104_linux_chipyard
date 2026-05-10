# Phase 0F: CEVA BT5.2 软件初始化路径调研报告

**RUN_TAG**: phase0f0g_20260509_211507  
**日期**: 2026-05-09  
**分支**: local/phase0b-s1-real-rw-dm-top  
**冻结基线**: phase0e-d-dm-sw-irq-repeated-pass-20260509

---

## 1. 结论摘要

- **无需 SW 栈运行**：Phase 0G "单 CEVA 活性验证" 的 PASS 标准可完全由 baremetal C 代码（Rocket CPU 侧）达成。
- **最小 active mode 入口**：向 RWBTLECNTL 寄存器写 RWBLE_EN=1，即可让 RW-DM Core 进入 active mode，并开始产生 dm_hslot_irq（每 312.5 µs 一次）。
- **观测方式**：轮询 INTSTAT1[CLKNINTSTAT] (bit 0)，无需 ILA / 示波器 / 新硬件综合。
- **档位决定**：**档 I**（纯寄存器观测，零硬件变更）。

---

## 2. CEVA IP 配置（来自 Phase 0b 冻结状态）

| 配置项 | 值 | 来源 |
|--------|-----|------|
| 射频接口 | ExtRC (`RW_DM_EXTRC_INST`) | user_defines_dm.v |
| 中断模式 | Level-triggered (`RW_DM_INT_MODE_LEVEL`) | user_defines_dm.v |
| 时序生成 | External LP (`RW_DM_TIMING_GEN_LP_EXTERNAL`) | ceva_phase0b_build_overrides.v |
| EM 地址宽度 | 16 位 | user_defines_dm.v |
| AHB→EM 路径 | 使能 (`RW_DM_AHB_TO_EM_PATH_ENABLE`) | user_defines_dm.v |
| AES 解密 | 使能 | user_defines_dm.v |
| WLAN Coex | 使能 | user_defines_dm.v |

---

## 3. 寄存器地址映射（以 CEVA_BASE = 0x65000000 为基准）

### 3.1 DM 寄存器区 (offset 0x000–0x3FF)

| 寄存器 | 偏移 | 确认方式 |
|--------|------|---------|
| RWDMCNTL | +0x000 | baremetal.c Phase 0E confirmed |
| VERSION | +0x004 | Phase 0D read: 0x0B000500 |
| INTCNTL0 | +0x008 | 顺序推算 |
| INTSTAT0 | +0x00C | 顺序推算 |
| INTACK0 | +0x010 | 顺序推算 |
| (reserved) | +0x014 | — |
| INTCNTL1 | +0x018 | **baremetal.c Phase 0E confirmed** |
| INTSTAT1 | +0x01C | **baremetal.c Phase 0E confirmed** |
| INTACK1 | +0x020 | **baremetal.c Phase 0E confirmed** |
| ACTFIFOSTAT | +0x024 | 顺序推算 |
| ETPTR | +0x028 | 顺序推算 |
| DEEPSLCNTL | +0x02C | 顺序推算 |

### 3.2 BLE 子系统寄存器区 (offset 0x400–0x7FF)

| 寄存器 | 地址 | 说明 |
|--------|------|------|
| RWBTLECNTL (=RWBLECNTL) | **0x65000400** (**RTL 确认**) | BLE 子系统首寄存器，BLE 块内偏移 0x000 |
| RWBLE_EN | **bit 8** of RWBTLECNTL (**RTL 确认**，mask=0x100) | 驱动 blemaster1_gclk |

> **注意**: 0x65000400 基于 FS 地址空间划分（DM=0x000-0x3FF, BLE=0x400-0x7FF, BT=0x800-0xBFF）推算。  
> Phase 0G 需先读取该地址验证为 0x0 后再写入。

### 3.3 BR/EDR 子系统寄存器区 (offset 0x800–0xBFF)

| 寄存器 | 地址 | 说明 |
|--------|------|------|
| RWBTCNTL | **0x65000800** (BT 块内偏移 0x000) | BT 子系统首寄存器 |
| RWBTEN | bit 8 (RTL: `int_reg_dw[8]` 同 BLE 结构) | 驱动 btmaster1_gclk |

### 3.4 Exchange Memory 区

| 区域 | 地址范围 |
|------|---------|
| EM 基址 (EM_BASE) | 0x65010000 |
| EM 末址 | 0x6501FFFF (64KB, 16-bit addr width) |

---

## 4. INTSTAT1 位域定义

从 FS "Register 3-7 INTSTAT1" + baremetal.c Phase 0E 确认：

| bit | 信号名 | 描述 | 确认方式 |
|-----|--------|------|---------|
| 0 | CLKNINTSTAT | dm_hslot_irq — 每 312.5 µs 触发一次，active mode 下持续 | FS 文字 |
| 1 | SLPINTSTAT | dm_slp_irq — 从深睡眠唤醒 | FS |
| 2 | CRYPTINTSTAT | dm_crypt_irq — AES 加解密完成 | FS |
| **3** | **SWINTSTAT** | **dm_sw_irq — 软件触发中断** | **baremetal.c CONFIRMED** |
| 4 | FINETGTINTSTAT | dm_finetgt_irq — fine timer 到期 | FS |
| 5 | TIMESTAMPTGT1INTSTAT | dm_timestamp_tgt1_irq | FS |
| 6 | TIMESTAMPTGT2INTSTAT | dm_timestamp_tgt2_irq | FS |
| 7 | TIMESTAMPTGT3INTSTAT | dm_timestamp_tgt3_irq | FS |
| 8+ | FIFOINTSTAT | dm_fifo_irq + ACTFIFO data | FS |

**关键验证**：SWINTSTAT = bit 3（mask = 0x00000008）已在 Phase 0E 板上确认。  
**Phase 0G 观测目标**：CLKNINTSTAT = bit 0（mask = 0x00000001）。

---

## 5. RWDMCNTL 关键位

| bit | 字段名 | Phase 0E 使用情况 |
|-----|--------|-------------------|
| 27 | SWINT_REQ | **已在 Phase 0E 写入验证**（PHASE0E_SWINT_TRIGGER_MASK = 1<<27）|
| ~15 | MASTER_SOFT_RST | SW 栈 rwip_driver_init 写 1 自动清零（全域软复位） |
| ~16 | MASTER_TGSOFT_RST | 时序生成器软复位 |
| ~17 | REG_SOFT_RST | 寄存器块软复位 |
| ~18 | RADIOCNTL_SOFT_RST | 射频控制器软复位 |

> MASTER_SOFT_RST 精确位号待板上验证（推测在 bit 15–18 区间）。

---

## 6. SW 栈初始化关键函数链（不在 Phase 0G 运行，仅文档参考）

```raw
rwip_init(RESET_NO_ERROR)
  ├── ke_init()                      // 内核事件队列
  ├── ke_mem_init() × 4              // 堆内存初始化
  ├── rf_init(&rwip_rf)              // ExtRC 射频驱动
  ├── ecc_init()                     // 椭圆曲线
  ├── h4tl_init()                    // HCI transport layer
  ├── hci_init()                     // HCI
  ├── rwbt_init()                    // BT 子系统初始化
  ├── rwble_init()                   // BLE 子系统初始化
  ├── rwip_driver_init(RWIP_INIT)    // 硬件驱动初始化
  │     ├── ip_rwdmcntl_master_soft_rst_setf(1)  // 全域软复位
  │     ├── while(master_soft_rst_getf());        // 等待自清零
  │     └── ip_intcntl1_set(FIFO|CRYPT|SW|SLP)  // 使能中断
  └── rwip_reset()                   // 首次复位状态机
```

---

## 7. EM 布局（来自 em_map.h）

```raw
EM_BASE (0x65010000):
  [0x0000] Exchange Table (ET) — 16 entries × REG_EM_ET_SIZE
  [ET_END] Frequency Table (FT) — 80 bytes (BT+BLE, ExtRC/Ripple variant)
  [FT_END] RF SW SPI — 8 bytes (ExtRC uses same layout as Ripple)
  [...]    BLE-only regions
  [...]    BT-only regions
```

Phase 0G 前置检查：EM 区域已可读写（Phase 0D 已验证 EM sweep）。  
dm_hslot_irq 触发后，EM FT 区内容会被 HW 读取（频率表访问），但无 radio 时不会有真实 SPI 输出。

---

## 8. ExtRC 射频信号摘要（radio_out/radio_in 关键 bit）

| 信号 | radio_out bit | 方向 | Phase 0G 状态 |
|------|--------------|------|----------------|
| TxData[2:0] | [2:0] | CEVA→radio | 无真实 radio，悬空 |
| TxEN | [3] | CEVA→radio | 无 radio，悬空但可接 ILA |
| rate[1:0] | [5:4] | CEVA→radio | 悬空 |
| TX_START | [6] | CEVA→radio | 悬空 |
| FREQWORD[7:0] | [15:8] | CEVA→radio | 含频率表值 |
| SYNC_P_OUT | [16] | CEVA→radio | 同步脉冲 |
| TX_POWER[10:0] | [40:30] | CEVA→radio | 发射功率字 |
| RSSI_REQ | [41] | CEVA→radio | RSSI 采样请求 |
| AGC_RSSI[7:0] | radio_in[13:6] | radio→CEVA | Phase 0G 接 0 |
| AGC_RSSI_READY | radio_in[14] | radio→CEVA | Phase 0G 接 0 |
| sync_p (in) | radio_in[16] | radio→CEVA | Phase 0G 接 0 |

> 所有未使用的 radio_in 已在 wrapper 中接 0（符合 ExtRC-UM Table 2-5 要求）。  
> Phase 0G 不观测 radio_out（无 ILA / 示波器），仅观测 INTSTAT1。

---

## 9. Phase 0G PASS 标准（档 I）

| 检查点 | 期望值 | 方法 |
|--------|--------|------|
| VERSION@0x65000004 | 0x0B000500 | 读寄存器 |
| INTSTAT1@0x6500001C 初始值 | ~0x00000000 | 读寄存器 |
| 设置 RWBLE_EN 后 5ms 内 CLKNINTSTAT 翻转 | 至少 10 次 | 轮询 |
| INTSTAT0@0x6500000C (error) | 始终 0x0 | 读寄存器 |
| EM 区域 FT 可读且非全 FF | 内容变化 | 读 EM |

---

*文档生成于 phase0f0g_20260509_211507 session，基于 RW-DM-CORE-FS v11.0.05、RW-DM-CORE-EXTRC-UM v11.0.04、rwip_driver.c v11_0_3*
