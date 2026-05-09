# CEVA BT5.2 Phase 0E-D dm_sw_irq Repeated Board PASS

## 1. 结论

截至 2026-05-09，ZCU104 + Chipyard + CEVA BT5.2 Phase 0E-D 已完成 baremetal repeated `dm_sw_irq` 板级验证。

在当前 `RocketZCU104Phase0bConfig` 新 bitstream 上，CEVA `dm_sw_irq` 通过 PLIC source id 1 进入 machine external interrupt 路径，连续 8 次触发全部成功，板级 hard-pass 条件满足：

- `PROBE_MAGIC = 0x30454331`
- `PROBE_MCAUSE = 0x800000000000000B`
- `PROBE_CLAIM_ID = 0x00000001`
- `PROBE_CEVA_STATUS_BEFORE_ACK = 0x00000008`
- `PROBE_CEVA_STATUS_AFTER_ACK = 0x00000000`
- `PROBE_HANDLER_COUNT = 0x00000008`
- `PROBE_TARGET_COUNT = 0x00000008`
- `PROBE_DONE = 0x00000001`
- `PROBE_TIMEOUT = 0x00000000`

结论：Phase 0E-D repeated `dm_sw_irq` board PASS。

## 2. 本次冻结对象

- 当前分支：`local/phase0b-s1-real-rw-dm-top`
- 当前 commit：`d39aaa0`
- 目标配置：`RocketZCU104Phase0bConfig`
- bitstream 路径：`generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/ZCU104FPGATestHarness.bit`
- bitstream mtime：`2026-05-09 15:19:18 +0800`
- bitstream sha256：`2054aeff301ed2c04555e8870ffd0b215d181888902333c44bc06116539e7bed`

对比本轮开始前的旧 bit：

- 旧 sha256：`a93564a86e19526fba803d88d038731f203c4b75c98a794a5a00eda079b706b8`

可以确认本轮 repeated IRQ 结果来自新 bit，而不是旧镜像复测。

## 3. 本轮最小闭环改动

本轮软件与构建闭环只扩大到 repeated IRQ 所必需的范围：

- `src/main/resources/zcu104/sdboot/baremetal.c`
  - 增加 `PHASE0E_IRQ_REPEAT_COUNT = 8`
  - 增加 `PHASE0E_IRQ_RETRIGGER_GAP_MS = 1`
  - 增加 `phase0e_irq_probe_target_count`
  - 用 `phase0e_irq_wait_for_count()` 代替单次 done 等待
  - 在 `main()` 中按 `expected_count = 1..8` 循环重触发 CEVA `dm_sw_irq`
  - trap handler 继续保留 first-trap sample，同时只在有效 CEVA machine-external 中断上递增 `phase0e_irq_probe_handler_count`
- `scripts/ceva_phase0e_c15_baremetal_probe_read.sh`
  - hard-pass 增加 `PROBE_TARGET_COUNT`
  - 新增 `PROBE_HANDLER_COUNT == PROBE_TARGET_COUNT` 判定
- `scripts/ceva_phase0e_c15_baremetal_probe_read.gdb`
  - 导出 `PROBE_ADDR_TARGET_COUNT` 与 `PROBE_TARGET_COUNT`
- `scripts/rebuild_incremental.tcl`
  - 在第一次 `post_route` 后执行 `report_route_status`
  - 若仍存在 routing errors，则从 `post_route.dcp` reopen 后补一轮 `route_design -directive Explore`
  - 只有 routing errors 清零后才继续 `write_bitstream`

## 4. Bitstream 收尾修复

本轮首次增量实现不是卡死，而是 route 后 bitgen 前置 DRC 暴露出部分未完全布线问题。最小修复不是再动 RTL，而是给增量脚本加一个 post-route 守门。

最终成功收尾日志要点：

- `Number of Failed Nets = 0`
- `Number of Unrouted Nets = 0`
- `Number of Partially Routed Nets = 0`
- `Number of Node Overlaps = 0`
- `INFO: [Route 35-16] Router Completed Successfully`
- `route_design completed successfully`
- `report_route_status` 显示 `# of nets with routing errors = 0`
- 随后 `write_bitstream` 成功写出新 bit

因此，这次 bit 成功落盘依赖的不只是 baremetal repeated 逻辑，也依赖 `scripts/rebuild_incremental.tcl` 中新增的 reroute cleanup 守门。

## 5. 板级验证流程

本次板级验证按以下顺序执行：

1. `bash scripts/phase0b_full_init.sh`
2. `bash scripts/start_jlink_server.sh`
3. `bash scripts/read_ceva_phase0b_s2_regs.sh`
4. `ELF=/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.elf bash scripts/ceva_phase0e_c15_baremetal_probe_read.sh`

其中：

- `phase0b_full_init.sh` 已完成 PS DDR init、bitstream download、PS-PL isolation removal
- J-Link GDB Server 复用了 `127.0.0.1:3333` 的现有监听实例

## 6. 板级结果

### 6.1 Phase 0B-S2 基线复核

`read_ceva_phase0b_s2_regs.sh` 返回：

- DM VERSION: `0x65000004 = 0x0b000500` PASS
- BT VERSION: `0x65000404 = 0x0b000600` PASS
- BLE VERSION: `0x65000804 = 0x0b001100` PASS

说明当前新 bit 没有破坏已闭环的 Phase 0B CEVA register windows。

### 6.2 Phase 0E-D repeated IRQ hard-pass

`ceva_phase0e_c15_baremetal_probe_read.sh` 返回的关键探针值为：

```text
LIVE_PC=0x0000000000010060
PROBE_MAGIC=0x30454331
PROBE_MCAUSE=0x800000000000000B
PROBE_MEPC=0x0000000000010698
PROBE_MTVAL=0x0000000000000000
PROBE_CLAIM_ID=0x00000001
PROBE_PLIC_PENDING_BEFORE_CLAIM=0x00000002
PROBE_PLIC_PENDING_AFTER_ACK=0x00000000
PROBE_CEVA_STATUS_BEFORE_ACK=0x00000008
PROBE_CEVA_STATUS_AFTER_ACK=0x00000000
PROBE_COMPLETION_WRITTEN=0x00000001
PROBE_HANDLER_COUNT=0x00000008
PROBE_TARGET_COUNT=0x00000008
PROBE_DONE=0x00000001
PROBE_TIMEOUT=0x00000000
LIVE_CEVA_MASK=0x0000800B
LIVE_CEVA_STATUS=0x00000000
LIVE_PLIC_PENDING=0x00000000
LIVE_PLIC_ENABLE=0x00000002
LIVE_PLIC_PRIORITY=0x00000001
LIVE_PLIC_THRESHOLD=0x00000000
```

脚本最终输出：

```text
PASS: hard-pass probes show repeated machine external interrupts reaching the expected target count, with CEVA claim id, CEVA status clear across ack, and final done
```

## 7. 变更边界

- 是否新增其他 CEVA IRQ：否，仅 `dm_sw_irq`
- 是否修改 DT / Linux / BlueZ：否
- 是否提交 commit：否
- 是否把生成产物作为提交内容：否
- 是否更换调试链路：否，仍为 `127.0.0.1:3333`

## 8. 结论

到本报告为止，Phase 0E-D 的目标已经闭环：

1. 新 repeated baremetal 路径已编入 BootROM 并传播到 TLROM / bitstream
2. 增量 Vivado 重建已通过 reroute cleanup 成功产出新 bit
3. 新 bit 已在板上完成 full init
4. CEVA S2 基线寄存器读取仍保持 PASS
5. repeated `dm_sw_irq` 已在板上达到 `8/8` hard-pass

当前可以把 Phase 0E-D 结论冻结为：`dm_sw_irq` repeated IRQ stable PASS。