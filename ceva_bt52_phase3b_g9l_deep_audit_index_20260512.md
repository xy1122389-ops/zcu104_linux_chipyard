# CEVA BT5.2 Phase 3B-G9L Deep Audit Index

## 1. 审计目录

本轮扩展审计输出目录：

```text
logs/phase3b_g9_extended_20260512_215738
```

核心 evidence 文件：

- `00_run_tag.txt`: run tag。
- `01_repo_baseline.log`: branch、recent commits、dirty status。
- `02_g9_master_plan.log`: G9 master plan 快照。
- `09_vendor_roots.txt`: vendor root 清单。
- `10_vendor_candidate_files.txt`: vendor candidate files 初筛。
- `12_source_text_files.txt`: source-only bounded file list。
- `11_vendor_dependency_grep.txt`: dependency grep。
- `20_entry_function_tree.txt`: entry function tree evidence。
- `21_runtime_services.txt`: ke/co/runtime service evidence。
- `22_hci_buffer_desc_refs.txt`: HCI buffer/descriptor references。
- `23_register_access_refs.txt`: register/EM access references。
- `60_payload_boot_boundary.txt`: current payload/init/GDB boundary evidence。

## 2. 今晚生成的文档

| 顺序 | 文档 | 用途 |
|---:|---|---|
| 1 | `ceva_bt52_phase3b_g9a_vendor_runtime_minimal_asset_manifest_20260512.md` | 冻结 vendor runtime 最小资产、可选资产、不需要资产和 approval 风险。 |
| 2 | `ceva_bt52_phase3b_g9b_vendor_runtime_dependency_tree_20260512.md` | 展开 `rwip_init` 到 HCI ingress/egress 的依赖树和编译模型。 |
| 3 | `ceva_bt52_phase3b_g9c_sidecar_execution_context_decision_20260512.md` | 决定 sidecar 运行在哪里，并列出否决项和 STOP 条件。 |
| 4 | `ceva_bt52_phase3b_g9d_ingress_bridge_protocol_v0_20260512.md` | 定义 Linux 到 sidecar 的 EM/SWINT ingress 协议。 |
| 5 | `ceva_bt52_phase3b_g9e_egress_bridge_protocol_v0_20260512.md` | 定义 sidecar 到 Linux 的 event egress 协议和 HCI event 校验。 |
| 6 | `ceva_bt52_phase3b_g9f_sidecar_boot_image_packaging_plan_20260512.md` | 定义 sidecar image 放置、加载、地址、启动和 packaging 计划。 |
| 7 | `ceva_bt52_phase3b_g9g_sidecar_instrumentation_marker_plan_20260512.md` | 定义 sidecar/bootstrap/ingress/egress/Linux real event marker。 |
| 8 | `ceva_bt52_phase3b_g9h_first_patch_plan_20260512.md` | 排序三种首刀方案，并给出推荐 patch 文件清单。 |
| 9 | `ceva_bt52_phase3b_g9i_management_risk_brief_20260512.md` | 给管理层解释为什么 Phase 2.5 不是完整蓝牙成功，以及为什么转 sidecar。 |
| 10 | `ceva_bt52_phase3b_g9j_7day_execution_schedule_20260512.md` | 给出后续 7 天按天执行计划、命令、PASS 和失败回退。 |
| 11 | `ceva_bt52_phase3b_g9k_forbidden_actions_and_rollback_plan_20260512.md` | 固化禁止动作、禁止提交文件、允许范围和回滚点。 |
| 12 | `ceva_bt52_phase3b_g9l_deep_audit_index_20260512.md` | 总索引，列出文档用途和下一步推荐顺序。 |

## 3. 下一步推荐顺序

1. 先审阅 G9-A，确认 vendor runtime 资产和 legal/vendor approval。
2. 审阅 G9-B，确认 runtime 依赖树和 stub 边界。
3. 审阅 G9-C，确认 sidecar execution context 是否存在。
4. 审阅 G9-G，确认 marker base 和 capture 设计。
5. 按 G9-H 执行第一刀 sidecar skeleton。
6. skeleton build 通过后，按 G9-F 接 packaging/launch proof。
7. sidecar marker boot 通过后，按 G9-D 接 ingress。
8. ingress pass 后，按 G9-E 接 egress。
9. Reset real path pass 后，按 G9-J Day 7 做 RLV 和 cleanup。
10. 全程按 G9-K 禁止项和回滚计划守住边界。

## 4. Open Blockers 汇总

- Vendor runtime source/blob 是否允许构建和打包。
- 正式 build config、feature macro、linker/startup 文件来源。
- Sidecar 独立 PC/执行流的具体承载方式。
- Candidate memory region 是否能 reserved，且不覆盖 Linux。
- CEVA internal controller firmware context 是否存在且可用。
- NVDS/default params 如何提供给 `rwip_param.get()`。

## 5. 本轮完成判定

G9-A 到 G9-L 文档已经把 vendor runtime sidecar + EM/SWINT bridge 路线规划到可以开始第一刀 skeleton 代码的程度。当前仍不能直接声称真实 Bluetooth controller path 已完成；下一阶段最小代码目标是 sidecar skeleton marker proof。
