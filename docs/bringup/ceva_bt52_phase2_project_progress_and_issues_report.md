# ZCU104 + Chipyard + CEVA BT5.2 项目阶段总结与问题复盘

## 1. 一句话结论

截至冻结点 phase2-linux-hci0-pass-20260510，ZCU104 + Chipyard + CEVA BT5.2 已完成从硬件 MMIO/EM 可达性、J-Link 稳定恢复、Phase 1A incremental rebuild、到 Linux minimal driver probe / hci0 注册的闭环验证。

当前冻结点是：

Phase 2 Linux minimal driver probe PASS

这表示：

- Linux 内核中 bluetooth.ko 与 ceva_bt52.ko 可以成功装载。
- CEVA BT5.2 驱动可以在内核中注册为 hci0。
- DM_VERSION、BT_RWBTCNTL、EM[0]、klog 中的 hci0 证据都满足最终 4/4 PASS 判据。

这不表示：

- 完整蓝牙通信已完成。
- BlueZ scan / pair / connect 已完成。
- HCI Reset / Read Local Version 已作为冻结目标完成。
- 真实 RF 空口验证已完成。

## 2. 冻结名称与边界

冻结名称：phase2-linux-hci0-pass-20260510

冻结含义：

- 冻结到 Linux minimal driver probe / hci0 注册阶段。
- 冻结以 fpga 内层仓库源码为主，不包含外层 chipyard 仓库当前大量无关脏改动。
- 不纳入 generated-src、bit、dcp、Vivado log、target、elf、bin、dump、临时 logs 等生成物。
- 不把 Phase 2.5 的 HCI probe 试验路径作为冻结目标。

## 3. 已完成里程碑

### 3.1 Phase 1A EM MMIO 验证

- 已验证 CPU EM MMIO window 在 0x65010000 可访问，EM[0..15]、边界地址、上半区读写和 CEVA 运行后复读均通过。
- 结论性日志：logs/phase1a_guarded_20260510_172436.log
  - line 209: PASS: CPU EM MMIO window FULLY VERIFIED — EM accessible at 0x65010000
  - line 210: VERDICT: PASS

### 3.2 Phase 1A incremental rebuild 主链

- 已修复 incremental rebuild 主链脚本问题，Vivado 能完成约束绑定并最终成功生成 bitstream。
- 结论性日志：generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/incremental_rebuild.log
  - line 15038: Generated shell constraint summary (pre-bitgen): 15/15 representative ports constrained
  - line 15107: INFO: [Vivado 12-1842] Bitgen Completed Successfully.
  - line 15111: write_bitstream completed successfully

### 3.3 J-Link guard / server lifecycle 修复

- 已建立稳定恢复链：jlink_guard.sh -> start/reuse server -> jlink_precheck.gdb。
- 已修复的关键问题：
  - Windows J-Link server 日志为 UTF-16LE，不能直接 cat 后 grep。
  - 启动锁 fd 会被后台 PowerShell 继承，导致后续调用卡住。
  - ready 判定不能只看端口监听，必须等到 Connected to target / Waiting for GDB connection。
- 结论性日志：logs/jlink_guard_restart_fix_20260510_210052.log
  - line 72: Connected to target
  - line 89: GDB Server already listening on :3333 — reusing existing instance
  - line 117: PASS: J-Link server and target precheck succeeded

### 3.4 Phase 2 minimal Linux driver probe

- 已建立 guarded Linux bringup 路径，并在最终归档中达到 4/4 hardware checks PASS。
- 结论性日志：logs/phase2_autofix_20260510_214733/phase2_final_4of4_20260510_223728_extract.log
  - line 263: ceva-bt52: bluetooth.ko OK
  - line 268: ceva-bt52 65000000.ceva-dm: CEVA BT5.2 registered as hci0 (IRQ 15, EM@0x65010000)
  - line 273: ceva-bt52: ceva_bt52.ko OK
  - line 289: CHECK 1: DM_VERSION=0x0B000500 - PASS (CEVA accessible)
  - line 290: CHECK 2: BT_RWBTCNTL bit8 SET - PASS (driver called open())
  - line 291: CHECK 3: EM[0]=0x00000000 - PASS (EM MMIO accessible)
  - line 292: CHECK 4: hci0 registration found in klog - PASS
  - line 294: [result] 4/4 hardware checks PASS

## 4. 本阶段解决过的关键问题

### 4.1 Phase 1A / 硬件侧

- 修复 Phase 1A incremental rebuild 主链中的 Tcl 参数解析、IP 可见性和 generated shell XDC 发现问题。
- 在 synth.tcl 中强制单线程综合，规避 Vivado 2021.2 在 HardFloat + SiFive L2 组合上的 multithread synth deadlock。
- 在 zcu104-master.xdc 中对已知 CEVA hready_reg_0 组合环做受控 ALLOW_COMBINATORIAL_LOOPS 旁路，以通过 write_bitstream。

### 4.2 J-Link / 恢复链路

- 增加 jlink_guard.sh 和 run_phase1a_guarded.sh 作为统一入口，避免手工 Stop-Process 与重复启动造成竞态。
- start_jlink_server.sh 现在支持稳定复用现存 server，而不是无条件重启。
- 发生 attach timeout 时，已验证的恢复路径是先 program_phase0b_bit，再 jlink_guard。

### 4.3 Linux / 模块装载链

- 修复 external CEVA BT 模块构建时默认注入 KBUILD_EXTRA_SYMBOLS 带来的 modpost/export 冲突。
- 修复 rebuild_payload.sh 顺序错误：必须先将 ecc.ko、ecdh_generic.ko、bluetooth.ko、ceva_bt52.ko 同步进 rootfs，再 repack initramfs，再 rebuild Image 和 fw_payload。
- 修复 DTS 中 CEVA 节点与 PLIC 中断编号，使 Linux minimal driver probe 路径可用。

## 5. 本次 freeze 纳入的源码面

本次冻结只纳入与当前里程碑直接相关的源码与文档：

- Phase 1A / rebuild 主链：
  - fpga-shells/xilinx/common/tcl/synth.tcl
  - fpga-shells/xilinx/zcu104/constraints/zcu104-master.xdc
  - scripts/incremental_rebuild_phase1a.tcl
  - scripts/run_incremental_rebuild_phase1a.sh
  - scripts/ceva_phase1a_jlink_em_mmio.gdb
  - scripts/run_phase1a_guarded.sh
- J-Link 恢复链：
  - scripts/start_jlink_server.sh
  - scripts/jlink_guard.sh
- Phase 2 Linux minimal probe：
  - linux-bringup/dtb/chipyard-zcu104-fedora.dts
  - linux-bringup/initramfs/rootfs/init
  - linux-bringup/kernel/ceva-bt52-driver/Makefile
  - linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c
  - rebuild_payload.sh
  - run_phase2_ceva_bt_linux.sh
  - scripts/linux_boot_phase2.gdb

生成物与日志不纳入 commit。

## 6. 明确不宣称完成的内容

以下内容不是本次冻结结论的一部分：

- Phase 2.5 HCI Reset / Read Local Version
- bluetoothctl scan / pair / connect
- L2CAP / RFCOMM / userspace BT stack 完整功能
- 真实 RF 空口验证
- 完整产品级蓝牙 bringup

## 7. 当前剩余问题与后续方向

冻结后仍保留的真实边界：

- 当前只证明内核驱动装载、open 路径和 hci0 注册成立。
- 未冻结 HCI 命令级闭环；因此不能把控制面命令成功当作现状结论。
- 若未来继续推进，应从驱动内核态直接打印 HCI Reset / Read Local Version 结果，而不是把当前 freeze 误描述成已完成蓝牙通信。

## 8. 冻结结论

本项目当前最稳、最可复现、且有完整日志硬证据支撑的冻结点是：

ZCU104 + Chipyard + CEVA BT5.2 已达到 Linux minimal driver probe PASS，驱动已注册为 hci0，Phase 2 最终 4/4 hardware checks PASS。

因此，本次 freeze 应以 phase2-linux-hci0-pass-20260510 为准，不向上扩展到 Phase 2.5，也不向外扩展到 BlueZ / RF 验证。