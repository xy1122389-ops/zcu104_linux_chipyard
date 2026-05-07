# CEVA BT5.2 Phase 0B-S1 Board PASS 冻结报告

## 1. 结论

截至 2026-05-07，`RocketZCU104Phase0bConfig` 已经完成 Phase 0B-S1 的板级关键目标验证：

- `phase0b_full_init.sh` 已完成 PS DDR init、bitstream download、PS-PL isolation removal。
- `phase0b_start_jlink.sh` 可把 J-Link GDB Server 拉起到 `127.0.0.1:3333`。
- `read_ceva_version.sh` 已经在板上稳定读回 `0x65000004 = 0x0B000500`。

这说明当前阶段已经从 S0 的“硬编码寄存器假值可读”推进到 S1 的“真实 CEVA DM 路径板上可见”。

## 2. 本次冻结对应对象

- 工作目录：`/root/chipyard/fpga`
- 当前 git 仓库根：`/root/chipyard/fpga`
- 冻结分支：`local/phase0b-s1-real-rw-dm-top`
- 目标配置：`RocketZCU104Phase0bConfig`

## 3. 板级成功证据

### 3.1 Phase0b 完整初始化

当前使用的入口脚本：

- `scripts/phase0b_full_init.sh`
- `scripts/program_phase0b_bit.sh`

`phase0b_full_init.sh` 当前内容是固定调用：

```bash
exec bash "$SCRIPT_DIR/program_phase0b_bit.sh" --cfg RocketZCU104Phase0bConfig
```

根据本轮终端成功记录，初始化链路已经完整走通，最终输出包含：

- `PS DDR init + FPGA download + isolation removal completed.`
- `Configured ZCU104 target: RocketZCU104Phase0bConfig`

因此可以确认：

- PS DDR init 已完成
- bitstream 已下载
- PS-PL isolation 已释放

### 3.2 J-Link 启动成功

当前使用的入口脚本：

- `scripts/phase0b_start_jlink.sh`

该脚本的行为是：

1. 先直接调用 `start_jlink_server.sh`
2. 若命中已知 halt timeout，再补做一轮 `phase0b_full_init.sh` 后重试

本轮重新验证 `read_ceva_version.sh` 时，脚本自动拉起了 J-Link，并得到：

```text
[jlink] GDB Server is listening on :3333
[jlink] Ready for GDB connections.
```

因此可以确认 J-Link GDB Server 监听正常。

### 3.3 CEVA VERSION 板级读回 PASS

当前读取脚本：

- `scripts/read_ceva_version.sh`

读取目标：

- 地址：`0x65000004`
- 期望值：`0x0B000500`

本轮重新执行后得到：

```text
0x65000004:     0x0b000500
✓ PASS: 0x65000004 = 0x0B000500 (CEVA DM VERSION 正确)
```

这条证据是当前冻结的核心证明。

## 4. Bitstream 冻结信息

当前找到的有效 bitstream：

- 路径：`./generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/ZCU104FPGATestHarness.bit`
- 大小：`12M`
- 时间戳：`2026-05-07 19:47`
- sha256：`8f881c010b45713ce6469fa7e023f8df1ba3908d2623825c8667ba5f264b76a5`

说明：

- bitstream 已成功生成并用于本次板级验证。
- 该 `.bit` 文件属于构建产物，本次提交不会纳入 git。

## 5. S1 阶段已完成的里程碑

### M1. 从 S0 假实现切换到 S1 真实集成目标

S1 的目标不是继续保留 `RegField.r` 的硬编码版本值，而是把真实 CEVA DM 路径接到 Chipyard。

### M2. 建立真实 CEVA 接入骨架

当前 ZCU104 配置入口已经切到：

- `WithCevaBt52Phase0b`
- `RocketZCU104Phase0bConfig`

并且本地适配层 `src/main/scala/zcu104/CevaBt52Phase0b.scala` 已经从旧的 stub 实现收敛为转发到真实 generator 实现的薄封装。

### M3. 修复 Windows Vivado under WSL 构建入口

`scripts/build_bitstream_wsl.sh` 已修复：

- WSL UNC 路径导致 Windows cwd 失效的问题
- Windows manifest 生成流程
- CEVA vendor 文件顺序保护

### M4. 修复 CEVA 文件顺序与宏可见性问题

本阶段新增：

- `scripts/gen_ceva_dm_phase0b_filelist.sh`
- `scripts/ceva_phase0b_build_overrides.v`

目的：

- 用 CEVA 官方 `create_comp_file.pl` 生成有序 filelist
- 在 `user_defines_dm.v` / `defines.v` 之前强制打开 `RW_DM_TIMING_GEN_LP_EXTERNAL`

### M5. 本地 bitstream 构建成功

Windows Vivado 已完成：

- synthesis
- implementation
- write_bitstream

且最终 bit 已用于板级验证。

### M6. ZCU104 板上成功读回真实 CEVA VERSION

最终读回：

- `0x65000004 = 0x0B000500`

这标志着 Phase 0B-S1 当前阶段完成。

## 6. 本次提交实际冻结哪些文件

本次提交只冻结当前 `fpga` git 仓库中真正需要的源码、脚本和报告，不包含构建副产物。

### 6.1 本次提交包含

- `scripts/build_bitstream_wsl.sh`
- `src/main/scala/zcu104/CevaBt52Phase0b.scala`
- `scripts/gen_ceva_dm_phase0b_filelist.sh`
- `scripts/ceva_phase0b_build_overrides.v`
- `docs/bringup/ceva_bt52_phase0b_s1_board_pass.md`

### 6.2 本次提交明确不包含

- `target/`
- `generated-src/`
- `*.bit`
- `*.log`
- `*.jou`
- Vivado 临时目录
- 大型构建中间产物
- CEVA 原始 vendor RTL

## 7. 当前 git 仓库边界说明

当前执行冻结和 push 的仓库根是：

- `/root/chipyard/fpga`

因此，本次提交能冻结的是 **fpga 仓库内** 的改动。

需要额外说明的是：S1 真正的 generator 主实现和真实 wrapper 文件位于上层目录，例如：

- `/root/chipyard/generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala`
- `/root/chipyard/generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v`

这些文件 **不在当前 `/root/chipyard/fpga` git root 内**，因此不会被本次 `fpga` 仓库提交一起带走。

这意味着：

- 本次提交可以冻结当前 `fpga` 仓库内的 S1 配套脚本和入口状态。
- 但如果要完整冻结整个 S1 源码状态，还需要在包含上述 generator/wrapper 文件的上层仓库中单独提交。

## 8. 本次冻结前遇到的主要问题与解决方法

### 8.1 `firtool` 环境问题

问题：`verilog` 阶段曾被环境问题卡住。
解决：显式导出 OCLAW 和 RISCV 工具链路径。

### 8.2 Windows Vivado UNC cwd 问题

问题：直接从 WSL UNC 路径启动 Windows Vivado 时，cwd 会掉回 Windows 默认目录。
解决：在 `build_bitstream_wsl.sh` 中使用 `Z:` 映射 WSL 根目录。

### 8.3 CEVA vendor 文件顺序导致宏丢失

问题：`user_defines_dm.v` / `defines.v` 被 generic manifest 流程排到依赖文件后面。
解决：新增官方 filelist 生成脚本，并在 Windows manifest 中保留 CEVA 有序块。

### 8.4 `rw_dm_top_tglp_ext` 低功耗端口形态不匹配

问题：若未预先打开 `RW_DM_TIMING_GEN_LP_EXTERNAL`，wrapper 与 CEVA 低功耗端口形态不一致。
解决：新增 `ceva_phase0b_build_overrides.v`，并强制排在 vendor 头文件之前。

## 9. 当前阶段建议

按照你的要求，本次操作到此为止，不再继续新增功能实验。

后续若继续推进，建议只做两类工作：

1. 在包含 generator/wrapper 的上层仓库里补做一次对应冻结提交。
2. 在当前 fpga 仓库内，以这个 commit/tag 作为 Phase 0B-S1 的板级 PASS 基线。

## 10. 冻结口径

本次冻结口径可以表述为：

> Phase 0B-S1 当前已完成板级 PASS：ZCU104 完成 PS+PL 初始化后，通过 J-Link 从 `0x65000004` 成功读回 CEVA DM VERSION `0x0B000500`。当前 `fpga` 仓库内与该状态直接相关的脚本、入口适配层、filelist/override 和阶段性报告已完成冻结提交。