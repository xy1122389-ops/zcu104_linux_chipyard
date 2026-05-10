# Phase 0G: 观测档位决策文档

**RUN_TAG**: phase0f0g_20260509_211507  
**日期**: 2026-05-09  
**决策结果**: **档 I — 纯寄存器轮询，无需新硬件**

---

## 1. 档位定义

| 档位 | 定义 | 代价 |
|------|------|------|
| 档 I | 仅 MMIO 读取（baremetal C 轮询寄存器） | 零：无需综合、无需示波器 |
| 档 II | EM 内存差分（SBA 读取 EM 区，对比前后） | 低：仅需重新 GDB 连接 |
| 档 III | ILA 抓取 radio_out 波形 | 高：需要 Vivado 综合（12h+） |

---

## 2. 档 I 可观测量分析

### 2.1 dm_hslot_irq（CLKNINTSTAT，INTSTAT1 bit 0）

- **信号定义**：每 312.5 µs（半时隙）产生一次中断，**仅在 active mode 下**
- **active mode 触发条件**：RWBTLECNTL[RWBLE_EN]=1 OR RWBTCNTL[RWBTEN]=1
- **读取寄存器**：INTSTAT1 @ CEVA_BASE + 0x01C = **0x6500001C**
- **bit 位**：bit 0 (mask = 0x00000001)
- **观测方法**：
  // baremetal C 轮询（无 IRQ 处理器）
  uint32_t count = 0, prev = 0, now;
  for (uint32_t i = 0; i < 10000000; i++) {
      now = ceva_read(INTSTAT1_OFFSET) & 0x1;
      if (now != prev) {
          count++;
          // ACK: 写 INTACK1 bit 0 = 1
          ceva_write(INTACK1_OFFSET, 0x1);
          prev = now;
      }
  }
  // 期望: count >= 10 (10次翻转 = 3.125ms)
- **PASS 标准**：5ms 内 CLKNINTSTAT 翻转 ≥ 10 次（即 ≥ 10 个 hslot 中断）

### 2.2 INTSTAT0[ERRORINTSTAT]（错误检测）

- **读取寄存器**：INTSTAT0 @ CEVA_BASE + 0x00C = **0x6500000C**
- **bit 0** = ERRORINTSTAT（BR/EDR + BLE sub-system 错误）
- **PASS 标准**：始终为 0x0（无错误）

### 2.3 VERSION 寄存器（sanity check）

- **地址**：0x65000004
- **期望**：0x0B000500（Phase 0D 已确认）

---

## 3. 档 II 补充观测（非强制，但建议追加）

在 Phase 0G 运行完成后，通过 GDB/J-Link SBA 读取 EM 区：

```python
# GDB 命令
dump binary memory /tmp/em_after_active.bin 0x65010000 0x65010100
```

比较 EM FT（Frequency Table）区域与 Phase 0D baseline：
- **Phase 0D baseline**：EM 初始全 0 or 随机
- **Phase 0G after**：FT 区（EM_BASE + ET_SIZE 起的 80 bytes）应被 HW 初始化

此步骤为**可选**，不影响 PASS/FAIL 判定。

---

## 4. 档 III 排除理由

| 考虑点 | 结论 |
|--------|------|
| radio_out TxEN 可否用 ILA 抓取 | 可以，但 ExtRC 无真实 radio，TxEN 不会 toggle |
| Phase 0G 目标是"活性验证"还是"空口发包" | 活性验证，无需 radio 动作 |
| ILA 综合代价 | ~12h，增加风险窗口 |
| dm_hslot_irq 已足以证明时钟/内部调度工作 | **是** |

→ **档 III 推迟到 Phase 0H（实际发包验证）时考虑**。

---

## 5. RWBLE_EN 设置的关键不确定性

| 项目 | 状态 | 说明 |
|------|------|------|
| RWBTLECNTL 地址 = 0x65000400 | **RTL 确认** | rw_ble_reg.v: RWBLECNTL_ADDR_CT=0x00, BLE 块起始 0x400 |
| RWBLE_EN = **bit 8**（mask=0x100） | **RTL 确认** | rw_ble_reg.v L2722: `int_rwble_en<=int_reg_dw[8]`; TB: WR 0x000=0x100 |
| Phase 0G 先读后写验证 | **必须** | 先读 0x65000400 确认为 0x0，再写 0x1，再读回确认 |

---

## 6. 完整观测流程（Phase 0G 执行步骤）

```raw
Step 0: J-Link 连接, halt CPU
Step 1: 读 VERSION @ 0x65000004 → 期望 0x0B000500
Step 2: 读 INTSTAT1 @ 0x6500001C → 期望 0x00000000
Step 3: 读 RWBTLECNTL @ 0x65000400 → 期望 0x00000000
Step 4: 写 INTCNTL1 @ 0x65000018 |= 0x00000001  (使能 CLKN/HSLOT 中断)
Step 5: 写 RWBTLECNTL @ 0x65000400 = 0x00000100  (RWBLE_EN=bit8=1)
Step 6: 延迟 1ms
Step 7: 轮询 INTSTAT1[0] 5ms，统计翻转次数
Step 8: 写 INTACK1 @ 0x65000020 = 0x00000001  (ACK 所有 HSLOT IRQ)
Step 9: 读 INTSTAT0 @ 0x6500000C → 期望 0x00000000 (无错误)
Step 10: 输出 PASS/FAIL
```

---

## 7. FAIL 分析路径

| 现象 | 可能原因 | 下一步 |
|------|---------|--------|
| INTSTAT1 bit 0 从不置 1 | ①RWBLE_EN 地址/bit 错误 ②时钟不工作 | 读 0x65000400 确认写入生效 |
| INTSTAT1 bit 0 置 1 但不清除 | ACK 机制错误 | 检查 INTACK1 地址 |
| INTSTAT0[0] 置 1 | BLE 子系统报错 | 读 ERRORTYPESTAT @ CEVA_BASE+0x050 |
| 翻转次数 < 10 但 > 0 | 计时不准 | 延长观测窗口至 20ms |
| CPU 在访问 0x65000400 时 hang | TileLink 地址映射问题 | 确认 CEVA 子系统地址段是否包含 0x400-0x7FF |

---

*决策锁定时间: 2026-05-09, RUN_TAG: phase0f0g_20260509_211507*
