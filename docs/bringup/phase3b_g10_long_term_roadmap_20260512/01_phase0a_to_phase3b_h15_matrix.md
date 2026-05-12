# Phase 0A 到 Phase 3B-H15 总阶段矩阵

## 1. Phase 0A 到 Phase 3A

| Phase | 名称 | 目标 | PASS 标准 | 主要文档证据 | 下一步 |
|---|---|---|---|---|---|
| 0A | Repo / toolchain / vendor collateral intake | 建立 Chipyard/ZCU104/CEVA collateral 工作区、构建入口和约束边界 | repo 能定位，vendor RTL/SW root 能定位，禁止项明确 | G10 retrospective baseline | 0B |
| 0B-S1 | Real CEVA RTL board VERSION | 真实 CEVA RTL 纳入 bitstream 并读到 VERSION | board VERSION read PASS | `ceva_bt52_phase0b_s1_board_pass.md` | 0B-S2 |
| 0B-S2 | Multi-register board validation | 多寄存器读回确认地址窗口 | VERSION 和多寄存器稳定 | `ceva_bt52_phase0b_s2_multireg_board_pass.md` | 0B-S3 |
| 0B-S3 | Software-stage visibility | baremetal/OpenSBI 早期软件可见性 | software marker 与 MMIO 可见 | `ceva_bt52_phase0b_s3_software_visibility_pass.md` | 0C |
| 0C | EM layout/range validation | 验证 Exchange Memory 地址范围和基础布局 | EM range sweep PASS | `ceva_bt52_phase0c_em_range_pass.md` | 0D |
| 0D | EM block sweep | 扩展 EM block 和 pattern 覆盖 | block sweep PASS | `ceva_bt52_phase0d_em_block_sweep_pass.md` | 0E |
| 0E-A/B/C/D | IRQ / PLIC / SWINT bringup | 建立 dm_sw_irq、PLIC source、claim/complete 和 repeated IRQ pass | repeated dm_sw_irq board PASS | `ceva_bt52_phase0e_*` 文档集 | 0F |
| 0F | Linux probe and software init audit | Linux 接入计划、DTS/IRQ facts、vendor software init 调研 | 不碰 BlueZ/HCI，冻结 probe 和 runtime chain 事实 | `ceva_bt52_phase0f_*` | 0G |
| 0G | Single IP activity | 最小 CEVA active/CLKN 观测 | single IP activity report PASS | `ceva_bt52_phase0g_*` | 1A |
| 1A | Integration hardening | bitstream/J-Link/build/recovery/EM MMIO 主链硬化 | build/recovery/J-Link guard 经验冻结 | Phase 1A repo memories and logs | 2 |
| 2 | Minimal Linux driver probe | Linux module/probe/hci0 基础 | minimal Linux probe 和 project progress 冻结 | `ceva_bt52_phase2_project_progress_and_issues_report.md` | 2.5 |
| 2.5 | Synthetic HCI control-plane smoke | 证明 host-side HCI control plane 可发可收 synthetic smoke | USER channel smoke PASS | `ceva_bt52_phase25_runbook_20260512.md` | 3A/3B |
| 3A | Host control-plane baseline | 固化 Linux host-facing control plane 边界 | hci0/control-plane baseline 成立 | Phase 3A baseline notes | 3B |

## 2. Phase 3B-D 到 G10

| Phase | 名称 | 目标 | PASS 标准 | 下一步 |
|---|---|---|---|---|
| 3B-D | Breadcrumb diagnosis | 判断 send path / breadcrumb / EM publication | command publication 证据成立 | 3B-E |
| 3B-E1..E5 | Host-side hypothesis testing | 排除 IRQ/mask/diag 等 Linux-only 假设 | 证明问题不在 userspace 未发包 | 3B-F |
| 3B-F | Firmware/bootstrap/mailbox audit | 找出真实 consumer 缺口 | vendor runtime 不在当前 payload 内的结论成立 | 3B-G6 |
| 3B-G6 | Bootstrap hook locator | 定位最小 bootstrap 和 image inclusion hook | current build 不包含 vendor runtime | 3B-G7 |
| 3B-G7 | Route decision | 否决 direct H4/kernel 和 Linux-only route | Route C now, Route B next | 3B-G8 |
| 3B-G8 | Inclusion gate | 冻结 vendor runtime inclusion gate | 不把生成物/受保护文件纳入提交 | 3B-G9 |
| 3B-G9 | Real consumer master plan | 规划 sidecar + EM/SWINT bridge route | G9-A 到 G9-L 文档完成 | 3B-G10 |
| 3B-G10 | Long-term roadmap | 把路线扩展成 0A 到 H15 全阶段矩阵 | 本目录 G10 文档完成 | 3B-H1 |

## 3. Phase 3B-H1 到 H15

| Phase | 名称 | 目标 | 首要改动 | PASS 标准 | 禁止混淆 |
|---|---|---|---|---|---|
| H1 | Sidecar skeleton source | 新增最小 sidecar source，不接 vendor runtime | `sidecar/ceva_bt52_sidecar/marker.h`, `start.S`, `main.c` | 本地构建 skeleton，通过静态检查 | 不宣称 controller runtime |
| H2 | Marker/capture contract | 固化 marker page 和 capture decode | marker header + capture doc/script planning | marker 地址、owner、清理规则成立 | 不跑板前不宣称 runtime |
| H3 | Execution context proof | 证明 sidecar 独立执行流 | dev loader 或 boot owner skeleton proof | `SIDECAR_START` / `SIDECAR_INGRESS_READY` 可捕获 | 不接 vendor runtime |
| H4 | Packaging and memory plan | 定义 payload/OpenSBI/loader/reserved memory | packaging glue plan, reserved memory patch plan | sidecar 不覆盖 Linux，build output 不提交 | 不把 GDB-only 当产品路径 |
| H5 | Ingress bridge skeleton | Linux -> sidecar command metadata path | bridge ingress source + contract header | Reset opcode 到达 sidecar marker | 不调用 fake controller success |
| H6 | Egress bridge skeleton | sidecar -> Linux event transport proof | bridge egress source + capture decode | event window/ready/seq 能被 Linux 读取 | 不声明 real HCI event |
| H7 | Vendor asset build gate | 引入获批 vendor runtime build inputs | manifest/build config glue | legal approval + build inputs freeze | 不提交未获批 vendor source/blob |
| H8 | Vendor runtime link model | 编译/链接 vendor runtime 最小子集 | sidecar vendor adapter/stubs | `ke/co/hci/rwip` link model 通过 | 不空 stub 核心 runtime |
| H9 | `rwip_init()` bootstrap | sidecar 调用 vendor `rwip_init()` | runtime init adapter | `SIDECAR_POST_RWIP_INIT` | 不宣称 HCI Reset pass |
| H10 | `rwip_driver_init()` ownership | vendor driver 初始化 CEVA IP | register access and init path | `SIDECAR_POST_RWIP_DRIVER_INIT` | 不破坏 Linux boot |
| H11 | Real ingress Reset consumed | Reset `0x0C03` 到 `hci_cmd_received()` | ingress adapter to vendor seam | `SIDECAR_RX_CMD_0C03` + consumed marker | 不 synthetic success |
| H12 | Real Reset egress | vendor 返回 Reset event | egress adapter from `hci_send_2_host()` | real Reset CC `0E 04 01 03 0C 00` | 不进入 BlueZ scan |
| H13 | Real RLV egress | Read Local Version real response | RLV validation | RLV CC `0E 0C 01 01 10 00 ...` | 不把 one-shot 当 regression |
| H14 | Regression and cleanup | 多次 boot/Reset/RLV 稳定，synthetic 默认关闭 | cleanup + validation scripts | repeated real path PASS | 不保留默认 synthetic pass |
| H15 | Controlled BlueZ bringup | 在 real controller path 后进入 scan/pair/connect | BlueZ test runbook | scan 前 Reset/RLV 均真实通过 | 不用 BlueZ 掩盖 controller 问题 |

## 4. Phase gate 原则

每个 H phase 的输出必须包含：

- 要改的文件。
- 要跑的命令。
- PASS/FAIL/STOP 条件。
- 回滚点。
- 禁止动作确认。
- `git status --short` 检查。

任何 phase 如果触碰 forbidden artifact、扩大 synthetic、或绕过 marker 链，必须停下回到上一个已证明 gate。
