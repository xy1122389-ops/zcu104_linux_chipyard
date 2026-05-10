# Phase 0G: CEVA BT5.2 单 IP 活性验证 — baremetal 初始化序列设计

**RUN_TAG**: phase0f0g_20260509_211507  
**日期**: 2026-05-09  
**目标**: 让 RW-DM Core 进入 active mode，观测 dm_hslot_irq 每 312.5 µs 触发

---

## 1. 最小初始化序列（Phase 0G 增量部分）

Phase 0E 已完成：PLIC 配置、CEVA sw_irq 测试×8。  
Phase 0G **增量步骤**（在 Phase 0E 测试之后执行）：

### Step G1: 读取 RWBTLECNTL 当前值（地址验证）

```c
#define PHASE0G_RWBTLECNTL_OFFSET   0x400u  // confirmed: BLE block base in DM space (RTL + FS Table 3-1)
#define PHASE0G_RWBLE_EN_MASK        (1u << 8)  // bit 8, confirmed from rw_ble_reg.v L2722
#define PHASE0G_RWBTCNTL_OFFSET     0x800u  // tentative — BT 子系统首寄存器

uint32_t ble_cntl_before = phase0g_ceva_read(PHASE0G_RWBTLECNTL_OFFSET);
// 期望 = 0x00000000 （复位后默认，未使能 BLE）
// 如果非零，日志警告但继续
uart_print_hex("RWBTLECNTL_before", ble_cntl_before);
```

### Step G2: 使能 HSLOT 中断掩码

```c
// INTCNTL1 |= CLKNINTMSK (bit 0 = 1)
#define PHASE0G_CLKNINTMSK    (1u << 0)  // HSLOT interrupt mask
uint32_t intcntl1 = phase0e_ceva_read(PHASE0E_INTCNTL1_OFFSET);
phase0e_ceva_write(PHASE0E_INTCNTL1_OFFSET, intcntl1 | PHASE0G_CLKNINTMSK);
uart_print_hex("INTCNTL1_after", phase0e_ceva_read(PHASE0E_INTCNTL1_OFFSET));
```

### Step G3: 设置 RWBLE_EN = 1（进入 active mode）

```c
// RWBTLECNTL |= RWBLE_EN (bit 8 = 1, mask=0x100, confirmed: rw_ble_reg.v L2722)
phase0e_ceva_write(PHASE0G_RWBTLECNTL_OFFSET, 
                   phase0g_ceva_read(PHASE0G_RWBTLECNTL_OFFSET) | PHASE0G_RWBLE_EN_MASK);
uart_print_hex("RWBTLECNTL_after", phase0g_ceva_read(PHASE0G_RWBTLECNTL_OFFSET));
```

### Step G4: 短暂延迟（等待时钟稳定）

```c
// ~1ms 延迟，允许 dm_hslot_irq 开始触发
for (volatile uint32_t d = 0; d < 1000000; d++) __asm__ volatile("nop");
```

### Step G5: 轮询 CLKNINTSTAT，统计 hslot 翻转次数

```c
#define PHASE0G_CLKNINTSTAT_MASK  (1u << 0)
#define PHASE0G_CLKNINTACK_MASK   (1u << 0)
#define PHASE0G_HSLOT_POLL_ITERS  50000000u  // ~5ms at 100MHz Rocket
#define PHASE0G_HSLOT_MIN_COUNT   10u

uint32_t hslot_count = 0;
uint32_t prev_intstat = 0;
uint32_t last_intstat1 = 0;
uint32_t error_intstat0 = 0;

for (uint32_t i = 0; i < PHASE0G_HSLOT_POLL_ITERS; i++) {
    uint32_t intstat1 = phase0e_ceva_read(PHASE0E_INTSTAT1_OFFSET);
    last_intstat1 = intstat1;

    if (intstat1 & PHASE0G_CLKNINTSTAT_MASK) {
        hslot_count++;
        // ACK the hslot interrupt
        phase0e_ceva_write(PHASE0E_INTACK1_OFFSET, PHASE0G_CLKNINTACK_MASK);
    }

    // Early exit if enough counts
    if (hslot_count >= PHASE0G_HSLOT_MIN_COUNT) break;
}

// Read error status
error_intstat0 = phase0e_ceva_read(0x00Cu);  // INTSTAT0

uart_print_hex("hslot_count", hslot_count);
uart_print_hex("last_intstat1", last_intstat1);
uart_print_hex("error_intstat0", error_intstat0);
```

### Step G6: 输出 PASS/FAIL

```c
if (hslot_count >= PHASE0G_HSLOT_MIN_COUNT && error_intstat0 == 0) {
    uart_print("PHASE0G: PASS — dm_hslot_irq active\n");
} else {
    uart_print("PHASE0G: FAIL\n");
    if (hslot_count < PHASE0G_HSLOT_MIN_COUNT)
        uart_print("  REASON: insufficient hslot count\n");
    if (error_intstat0 != 0)
        uart_print("  REASON: error_intstat0 non-zero\n");
}
```

---

## 2. 预期时序

| 时刻 | 事件 |
|------|------|
| T+0 | RWBLE_EN=1 写入 |
| T+0 to T+625µs | 第一个 BLE 基本时隙启动，FINECNT 开始计数 |
| T+312.5µs | 第一次 dm_hslot_irq（CLKNINTSTAT bit 0 → 1） |
| T+625µs | 第二次 dm_hslot_irq |
| T+3.125ms | 第 10 次 dm_hslot_irq → PASS 阈值 |

---

## 3. 副作用分析

| 操作 | 副作用 | 安全性 |
|------|--------|--------|
| RWBLE_EN=1 | 使能 blemaster1_gclk，BLE FSM 开始运行 | **安全**：ExtRC radio 已接 0（无真实发包） |
| CLKNINTMSK=1 | HSLOT IRQ 开始上报 | **安全**：baremetal 不使用 PLIC IRQ 路径，仅轮询 |
| 不做 MASTER_SOFT_RST | 使用上电复位状态 | **安全**：Phase 0E 已确认 IP 工作 |

---

## 4. FAIL 路径处理

### 4a: INTSTAT1 bit 0 从不置位

原因排查：
1. 读回 RWBTLECNTL（0x65000400）确认写入生效
2. 读回 INTCNTL1（0x65000018）确认 CLKNINTMSK 已置 1
3. 考虑 RWBTLECNTL 地址可能不是 0x400：尝试 0x800 (RWBTCNTL for BT enable)
4. 检查 CPU 访问是否 hang（可能 TileLink 映射问题）

### 4b: INTSTAT0 报错

1. 读 ERRORTYPESTAT @ 0x65000000+0x050
2. 可能原因：时钟异常、EM 访问越界

---

## 5. 成功状态快照目标

baremetal 日志期望输出（UART）：

```raw
[NEWBIT] Phase 0G: CEVA Active Mode Test
[NEWBIT] RWBTLECNTL_before: 0x00000000
[NEWBIT] INTCNTL1_after: 0x00000009  (HSLOT + SW 掩码)
[NEWBIT] RWBTLECNTL_after: 0x00000100
[NEWBIT] hslot_count: 0x0000000A  (>=10 = PASS)
[NEWBIT] last_intstat1: 0x00000001
[NEWBIT] error_intstat0: 0x00000000
[NEWBIT] PHASE0G: PASS — dm_hslot_irq active
```

---

*设计文档，基于 Phase 0F 调研结论，RUN_TAG: phase0f0g_20260509_211507*
