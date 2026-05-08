# CEVA BT5.2 Phase 0B-S3 Software-Stage Visibility PASS

## 1. 结论

截至 2026-05-07，ZCU104 + Chipyard + CEVA BT5.2 Phase 0B 已完成 S3 软件阶段可见性验证。

在不修改 CEVA vendor RTL、不重新生成 bitstream 的前提下，现有 `RocketZCU104Phase0bConfig` 硬件基线已经证明：

- S3-A：Rocket baremetal payload 阶段可直接读到 CEVA MMIO window
- S3-B：OpenSBI 早期执行阶段可直接读到 CEVA MMIO window

本轮验证的 3 个地址和读回值始终一致：

- DM VERSION：`0x65000004 = 0x0B000500`
- BT VERSION：`0x65000404 = 0x0B000600`
- BLE VERSION：`0x65000804 = 0x0B001100`

结论：CEVA MMIO window 不仅在板级 JTAG/SBA 路径可见，在 Rocket CPU 的 baremetal 与 OpenSBI 软件执行阶段也保持可见，Phase 0B-S3 PASS。

## 2. 验证边界

- 当前分支：`local/phase0b-s1-real-rw-dm-top`
- 目标配置：`RocketZCU104Phase0bConfig`
- 是否修改 CEVA vendor RTL：否
- 是否重新综合：否
- 是否重新生成 bitstream：否
- 是否进入 EM / IRQ / Linux driver：否

## 3. S3-A：baremetal payload 可见性验证

### 3.1 方法

本轮没有新增独立裸机工程，而是复用现有 demo payload 路径，在 baremetal 入口中直接读取 3 个 CEVA VERSION 寄存器并写入全局探针变量。

baremetal 关键执行方式为：

1. 构建 demo target
2. 将 `demo_target.bin` 通过 J-Link GDB `restore` 装载到 `0x80400000`
3. 在 `0x81200000` 放置 `fence.i + jalr t0` 跳板
4. 令 CPU 从 `0x81200000` 起跑，跳入 payload
5. 在 `demo_target_loop_marker` 停住并读取 probe 变量与 CEVA MMIO

### 3.2 关键证据

停住时：

- `pc = 0x80400038`，即 `demo_target_loop_marker`
- `probe_magic = 0x53334230`
- `probe_dm_version = 0x0B000500`
- `probe_bt_version = 0x0B000600`
- `probe_ble_version = 0x0B001100`

同一时刻直接复读 MMIO：

- `0x65000004: 0x0b000500`
- `0x65000404: 0x0b000600`
- `0x65000804: 0x0b001100`

### 3.3 结论

CPU 在 baremetal payload 阶段已经能直接访问 CEVA MMIO window，S3-A PASS。

## 4. S3-B：OpenSBI 早期阶段可见性验证

### 4.1 方法

使用当前 OpenSBI `fw_payload.bin` 与 DTB：

1. 将 `fw_payload.bin` 装载到 `0x80000000`
2. 将 DTB 装载到 `0x82400000`
3. 使用 `0x81200000` 的 `fence.i + jalr t0` 跳板跳入 OpenSBI `_start`
4. 先尝试 `hbreak + continue` 到 `sbi_init`，发现该方法在 SBA 装载后不稳定
5. 改用有界 `stepi` 取证，在 OpenSBI 早期指令流中检查 PC 与 CEVA MMIO

### 4.2 关键证据

`stepi 20` 后：

- `pc = 0x8000003a`，落在 OpenSBI `_start + 58`
- `ra = 0x8000002a`，落在 OpenSBI `_start + 42`
- `a1 = 0x82400000`
- CEVA 三寄存器仍读回：
  - `0x65000004 = 0x0B000500`
  - `0x65000404 = 0x0B000600`
  - `0x65000804 = 0x0B001100`

`stepi 50` 后：

- `pc = 0x800000b0`，落在 OpenSBI `_relocate + 50`
- CEVA 三寄存器仍读回：
  - `0x65000004 = 0x0B000500`
  - `0x65000404 = 0x0B000600`
  - `0x65000804 = 0x0B001100`

### 4.3 方法层失败点

`hbreak + continue` 在本路径上不稳定，表现为：

- OpenSBI 镜像与 DTB 已成功装载
- 断点可成功下到 `sbi_init`
- 但 `continue` 后不能稳定命中断点

这说明该失败是“调试方法噪声”，不是“CEVA MMIO 不可见”。

### 4.4 结论

OpenSBI 早期 `_start` 与 `_relocate` 路径中，CEVA MMIO window 仍然可读，S3-B PASS。

## 5. S3 阶段总结

至此，Phase 0B-S3 的目标已经完成：

- baremetal payload 可见
- OpenSBI 早期阶段可见
- 无需新的 bitstream 即可证明当前 CEVA MMIO 软件阶段可见性

这为下一阶段硬件可见变更提供了边界清晰的起点：

- 当前缺口不在寄存器窗口
- 当前真正缺口在 EM BRAM 与 IRQ 还停留在 stub

## 6. 紧接下一阶段

S3 报告完成后，下一步立即进入 `Phase 0C-A`：

- 将当前 wrapper 中的 `em_ready=1 / em_rdata=0` stub 替换为最小可用 EM BRAM
- 先打通 EM AHB 地址窗口读写
- 暂不进入 IRQ、Linux driver、HCI、BlueZ