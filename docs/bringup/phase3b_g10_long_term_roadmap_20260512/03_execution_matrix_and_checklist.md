# G10 Execution Matrix And Checklist

## 1. 长期执行矩阵

| Phase | 输入 | 改动面 | 验证命令类型 | PASS evidence | 回滚点 |
|---|---|---|---|---|---|
| H1 | G9H first patch plan | 新增 sidecar skeleton source | local compile only | `.elf/.bin` local build, source review | 删除 sidecar skeleton source |
| H2 | G9G marker plan | marker constants, capture decode plan | static check | marker owner/offset 清楚 | 回到 H1 |
| H3 | H1/H2 | launch/capture dev scripts | board run only after explicit unlock | marker page shows sidecar alive | disable launch hook |
| H4 | G9F packaging plan | packaging/reserved memory plan | build dry-run | no Linux memory collision by plan | remove packaging hook |
| H5 | G9D ingress v0 | bridge ingress skeleton | sidecar/unit/dev proof | Reset opcode marker | disable ingress hook |
| H6 | G9E egress v0 | bridge egress skeleton | sidecar/unit/dev proof | event-ready marker and EM bytes | disable egress hook |
| H7 | G9A assets | vendor manifest/build config | compile audit | approved asset set | remove vendor refs |
| H8 | G9B dependency tree | runtime link/stubs | sidecar compile | `ke/co/hci/rwip` link passes | revert vendor adapter |
| H9 | H8 | call `rwip_init` | marker proof | `SIDECAR_POST_RWIP_INIT` | disable runtime entry |
| H10 | H9 | call `rwip_driver_init` | marker + register proof | `SIDECAR_POST_RWIP_DRIVER_INIT` | disable driver init |
| H11 | H10 | real ingress adapter | Reset command proof | `SIDECAR_CMD_CONSUMED` | bridge-only fallback |
| H12 | H11 | real egress adapter | Reset CC proof | `REAL_RESET_PASS` | keep ingress, disable egress |
| H13 | H12 | RLV validation | RLV CC proof | `REAL_RLV_PASS` | keep Reset baseline |
| H14 | H13 | cleanup/regression | repeated boot proof | synthetic off, Reset/RLV repeat | rollback cleanup only |
| H15 | H14 | BlueZ controlled runbook | scan/pair/connect after unlock | BlueZ evidence on real controller | return to H14 |

## 2. Pre-flight checklist for every phase

- Read `git status --short` before edits.
- Identify user-existing dirty files and do not revert them.
- State forbidden actions for the phase.
- Confirm no board/J-Link/rebuild/Vivado unless that phase explicitly allows and user unlocks it.
- Confirm output files are source/docs only.
- Confirm generated outputs are ignored or outside commit scope.
- Confirm pass/fail/stop criteria before running validation.

## 3. H1 implementation checklist

- Add `sidecar/ceva_bt52_sidecar/marker.h`.
- Add `sidecar/ceva_bt52_sidecar/start.S`.
- Add `sidecar/ceva_bt52_sidecar/main.c`.
- Add `sidecar/ceva_bt52_sidecar/linker.ld`.
- Add `sidecar/ceva_bt52_sidecar/Makefile`.
- Add `sidecar/ceva_bt52_sidecar/README.md`.
- Build locally.
- Verify `.elf/.bin/.dump` are not staged.
- Do not edit `ceva_bt52.c`.
- Do not edit RTL.

## 4. H5/H6 bridge checklist

- Confirm `SIDECAR_INGRESS_READY` exists before Linux sends real command.
- Confirm EM[64..] command payload excludes H4 type byte.
- Confirm `cmd_len`, `cmd_seq`, `cmd_status`, `cmd_consumed_seq` semantics.
- Confirm sidecar clears `cmd_ready`, not Linux.
- Confirm EM[96] event payload starts with HCI event code.
- Confirm EM[73] is cleared by Linux after copy.
- Confirm synthetic responder is disabled for real path validation.

## 5. H7/H8 vendor inclusion checklist

- Verify approval for vendor source/blob use.
- Freeze exact vendor source paths or blob identifiers.
- Freeze `rwip_config.h` and feature macro set.
- Freeze linker/startup/vector/interrupt model.
- Freeze `rwip_param.get` default source.
- Link with real `ke_mem`, `ke_msg`, `ke_event`, `ke_task`, `co_list`, HCI descriptor tables.
- Do not empty-stub core runtime services.

## 6. H11/H12/H13 real HCI checklist

- Reset command bytes: `03 0C 00` in command payload.
- Reset consumed marker: `SIDECAR_RX_CMD_0C03` and `SIDECAR_CMD_CONSUMED`.
- Reset event bytes: `0E 04 01 03 0C 00`.
- RLV command bytes: `01 10 00`.
- RLV event prefix: `0E 0C 01 01 10 00`.
- Linux marker: `LINUX_RX_REAL_EVENT`.
- Real pass marker: `REAL_RESET_PASS` then `REAL_RLV_PASS`.
- No synthetic branch in pass path.

## 7. Stop checklist

Stop the current phase if any item is true:

- A required vendor asset cannot be legally used.
- A proof requires modifying RTL before sidecar skeleton exists.
- A proof requires putting vendor runtime into Linux kernel.
- A proof depends on Linux userspace fake controller helper.
- Generated bitstream/payload/DTB/ELF/BIN enters git status as tracked or staged.
- Marker chain cannot distinguish stale data from current run.
