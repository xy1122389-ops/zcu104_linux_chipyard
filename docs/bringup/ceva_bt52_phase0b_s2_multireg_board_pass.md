# CEVA BT5.2 Phase 0B-S2 Multi-Register Board PASS

## 1. 结论

截至 2026-05-07，ZCU104 + Chipyard + CEVA BT5.2 Phase 0B 已完成 S2 板级多寄存器读取验证。

在不修改硬件、不重新综合、不修改 CEVA 原始 vendor RTL 的前提下，使用当前已通过的 `RocketZCU104Phase0bConfig` bitstream，经由 J-Link + GDB + SBA 成功读回以下 3 个只读版本寄存器：

- DM VERSION: `0x65000004 = 0x0B000500`
- BT VERSION: `0x65000404 = 0x0B000600`
- BLE VERSION: `0x65000804 = 0x0B001100`

结论：CEVA DM/BT/BLE VERSION register windows board PASS。

## 2. 本次冻结对象

- 当前分支：`local/phase0b-s1-real-rw-dm-top`
- 当前 commit：`ed31b9e058dc070296788a4d90e4f7602831e7d0`
- 目标配置：`RocketZCU104Phase0bConfig`
- bitstream 路径：`generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/ZCU104FPGATestHarness.bit`
- bitstream sha256：`8f881c010b45713ce6469fa7e023f8df1ba3908d2623825c8667ba5f264b76a5`

## 3. 初始化流程

本次板级验证沿用已冻结的 Phase 0B 流程：

1. `bash scripts/phase0b_full_init.sh`
2. `bash scripts/phase0b_start_jlink.sh`
3. `bash scripts/read_ceva_version.sh`
4. `bash scripts/read_ceva_phase0b_s2_regs.sh`

其中 `phase0b_full_init.sh` 已完成：

- PS DDR init
- FPGA bitstream download
- PS-PL isolation removal

## 4. J-Link 状态

本轮实测中，J-Link GDB Server 运行于：

- `127.0.0.1:3333`

启动日志确认：

- `Connected to target`
- `Waiting for GDB connection...`

随后再次执行 `phase0b_start_jlink.sh` 时，脚本正常复用现有实例并提示：

- `GDB Server already listening on :3333 — reusing existing instance`

因此可以确认：

- J-Link 监听正常
- Rocket 调试链路可连通
- 无需重启 J-Link Server 即可继续寄存器读取

## 5. 读取结果

### 5.1 S1 单寄存器复核

`read_ceva_version.sh` 读回：

- 地址：`0x65000004`
- 实际值：`0x0b000500`
- 期望值：`0x0B000500`
- 结果：PASS

### 5.2 S2 多寄存器验证

`read_ceva_phase0b_s2_regs.sh` 读回：

| 名称 | 地址 | 实际读回 | 期望值 | 结果 |
|------|------|----------|--------|------|
| DM VERSION | `0x65000004` | `0x0b000500` | `0x0B000500` | PASS |
| BT VERSION | `0x65000404` | `0x0b000600` | `0x0B000600` | PASS |
| BLE VERSION | `0x65000804` | `0x0b001100` | `0x0B001100` | PASS |

脚本最终输出：

```text
PASS: Phase 0B-S2 CEVA multi-register read passed
```

## 6. 变更边界

- 是否重新综合：否
- 是否重新生成 bitstream：否
- 是否修改 CEVA 原始 RTL：否
- 是否恢复 S0 硬编码 RegField 路线：否
- wrapper 是否改回直接实例化 `rw_dm_top`：否，仍保持 `rw_dm_top_tglp_ext` 路径

## 7. 结论与下一步

当前证据表明，CEVA AHB register window 已经不是单点 DM VERSION 可读，而是至少覆盖：

- DM register window
- BT register window
- BLE register window

下一步建议：

1. 进入 OpenSBI / baremetal payload 链路，继续验证 CEVA window 在更完整软件阶段下的可见性。
2. 并行准备 Linux device tree / driver 前置设计，但当前阶段仍不进入正式 Linux driver / HCI / BlueZ 集成。