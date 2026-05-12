# CEVA BT5.2 Phase 3B-G9J 后续 7 天执行排期

## Day 1: 资产冻结

改哪些文件：

- `ceva_bt52_phase3b_g9a_vendor_runtime_minimal_asset_manifest_20260512.md`
- `ceva_bt52_phase3b_g9b_vendor_runtime_dependency_tree_20260512.md`
- 新增 vendor asset manifest 纯文本文件，例如 `sidecar/vendor_runtime_assets.manifest`

跑哪些命令：

```bash
grep -InE 'rwip_init|h4tl_init|hci_cmd_received|hci_send_2_host|rwip_driver_init' <approved-source-list>
git status --short
```

PASS 条件：

- vendor source/blob approval owner 已确认。
- 必须资产、可选资产、不需要资产、Open Blockers 已冻结。
- 没有提交 vendor source/binary。

FAIL 后怎么退：

- 停在 Route C。
- 只保留规划文档。
- 向 vendor/老板补齐授权和 build config。

## Day 2: sidecar skeleton

改哪些文件：

- `sidecar/ceva_bt52_sidecar/Makefile`
- `sidecar/ceva_bt52_sidecar/linker.ld`
- `sidecar/ceva_bt52_sidecar/start.S`
- `sidecar/ceva_bt52_sidecar/main.c`
- `sidecar/ceva_bt52_sidecar/marker.h`
- `sidecar/ceva_bt52_sidecar/README.md`

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar clean
make -C sidecar/ceva_bt52_sidecar
git status --short
```

PASS 条件：

- `.elf/.bin` 本地生成但不被提交。
- `start.S`、stack、marker constants 编译通过。
- 未修改 driver/RTL/DTB/DTS。

FAIL 后怎么退：

- 保留文档。
- 回滚 sidecar source patch 或修正 linker/toolchain。
- 不进入 bridge skeleton。

## Day 3: sidecar marker boot

改哪些文件：

- `scripts/linux_boot_phase2_launch.gdb` 或新增 sidecar 专用 launch 脚本。
- `scripts/linux_boot_phase2_capture.gdb` 或新增 sidecar marker capture 脚本。
- 如获批，新增 reserved-memory 计划文档；不提交本地 DTB/DTS 生成物。

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar
# board/J-Link run only after explicit unlock
git status --short
```

PASS 条件：

- Capture 看到 `SIDECAR_IMAGE_PRESENT`、`SIDECAR_START`、`SIDECAR_PRE_RWIP_INIT`、`SIDECAR_INGRESS_READY`。
- Linux baseline 未退化。

FAIL 后怎么退：

- 关闭 sidecar launch hook。
- 保留 skeleton source。
- 回到 Day 2 修 linker/startup/address。

## Day 4: ingress bridge

改哪些文件：

- `sidecar/ceva_bt52_sidecar/bridge_ingress.c`
- `sidecar/ceva_bt52_sidecar/bridge_contract.h`
- 后续受控修改 [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c)，写 `cmd_len/cmd_seq/cmd_status`。
- capture 脚本读取 EM[64..79]。

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar
make -C linux-bringup/kernel/ceva-bt52-driver  # exact command to be confirmed by existing kernel build flow
git status --short
```

PASS 条件：

- Reset `0x0C03` 触发 `SIDECAR_RX_CMD_0C03`。
- Sidecar 清 `cmd_ready` 并写 `SIDECAR_CMD_CONSUMED`。
- 不使用 synthetic responder。

FAIL 后怎么退：

- 关闭 driver ingress additions。
- 保留 sidecar marker proof。
- 回查 EM ownership、length/seq、SWINT ack。

## Day 5: egress bridge

改哪些文件：

- `sidecar/ceva_bt52_sidecar/bridge_egress.c`
- `sidecar/ceva_bt52_sidecar/hci_event_encode.c` 或 vendor egress adapter。
- [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c) 的 real event RX path marker。
- capture 脚本读取 EM[88..96] 和 EM[96..127]。

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar
git status --short
```

PASS 条件：

- Sidecar 写 `SIDECAR_EGRESS_EVENT_READY`。
- Linux 写 `LINUX_RX_REAL_EVENT`。
- EM[96] event bytes 通过 HCI event 格式校验。

FAIL 后怎么退：

- 保留 ingress proof。
- 关闭 egress hook。
- 回查 H4 type stripping、event_len、Linux skb packet type。

## Day 6: Reset real path

改哪些文件：

- sidecar vendor ingress adapter。
- sidecar vendor egress adapter。
- capture/validation 脚本增加 Reset CC 判定。
- synthetic responder 默认关闭配置。

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar
./run_phase2_ceva_bt_linux.sh  # only after board/J-Link unlock and run plan approval
git status --short
```

PASS 条件：

- `SIDECAR_RX_CMD_0C03`。
- `SIDECAR_HCI_SEND_2_HOST`。
- EM[96] contains `0E 04 01 03 0C 00`。
- `LINUX_RX_REAL_EVENT`。
- `REAL_RESET_PASS`。

FAIL 后怎么退：

- 禁止改 BlueZ scan。
- 禁止打开 synthetic success 伪装通过。
- 按 marker 链定位停在 ingress、vendor core、egress、Linux rx 哪一段。

## Day 7: RLV real path + cleanup

改哪些文件：

- validation script 加 Read Local Version `0x1001`。
- 文档更新真实 pass evidence。
- 清理 debug-only code，保留 marker。

跑哪些命令：

```bash
make -C sidecar/ceva_bt52_sidecar
git status --short
# board run only after unlock
```

PASS 条件：

- Reset real pass 重复成立。
- RLV event `0E 0C 01 01 10 00 ...` 成立。
- synthetic responder 默认关闭。
- 不提交 build output、payload、DTB/DTS、bitstream。

FAIL 后怎么退：

- 保留 Reset real path。
- 标记 RLV 为 Open Blocker。
- 不进入 scan/pair/connect。

## 总节奏

Day 1 到 Day 3 只证明资产和 sidecar execution。Day 4 到 Day 5 证明 bridge。Day 6 到 Day 7 才证明真实 HCI command/event。任何一天失败，都退回前一天的已证明 marker，不扩大到 BlueZ 或 RTL。
