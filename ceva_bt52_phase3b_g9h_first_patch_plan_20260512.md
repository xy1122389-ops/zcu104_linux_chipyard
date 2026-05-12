# CEVA BT5.2 Phase 3B-G9H 第一刀代码改动计划

## 1. 推荐结论

第一刀推荐方案是方案 2：新增 sidecar skeleton，不接 vendor runtime，只证明 sidecar 能构建、加载、获得执行流并写 marker。

这比直接改 `ceva_bt52.c` 更稳，因为当前根因不是 Linux 发不出命令，而是没有真实 consumer。先证明 sidecar execution context，才能让后续 ingress/egress bridge 有真实对端。

## 2. 三种方案排序

| 排名 | 方案 | 决策 | 目的 |
|---:|---|---|---|
| 1 | 方案 2: 新增 sidecar skeleton | 推荐第一刀 | 证明独立执行流和 marker，不碰 driver/RTL。 |
| 2 | 方案 1: 只改文档/manifest | 已由 G9-A..G9-L 覆盖 | 适合资产审批和路线冻结，不足以进入 execution proof。 |
| 3 | 方案 3: 新增 bridge skeleton，只做 ingress marker | 第二个代码阶段 | 需要 sidecar 已能启动后才有意义。 |

## 3. 第一个要改的文件是什么

第一个代码文件建议新增：

```text
sidecar/ceva_bt52_sidecar/marker.h
```

原因：marker contract 是 sidecar skeleton、capture script、未来 Linux rx proof 的共同接口。先冻结 `marker.h`，再写 `start.S` 和 `main.c`。

推荐 patch 文件清单：

```text
sidecar/ceva_bt52_sidecar/Makefile
sidecar/ceva_bt52_sidecar/linker.ld
sidecar/ceva_bt52_sidecar/start.S
sidecar/ceva_bt52_sidecar/main.c
sidecar/ceva_bt52_sidecar/marker.h
sidecar/ceva_bt52_sidecar/bridge_contract.h
sidecar/ceva_bt52_sidecar/README.md
```

不提交：

```text
sidecar/ceva_bt52_sidecar/build/*.elf
sidecar/ceva_bt52_sidecar/build/*.bin
sidecar/ceva_bt52_sidecar/build/*.dump
```

## 4. 为什么不是 `ceva_bt52.c`

`ceva_bt52.c` 当前已经能把 HCI command 写到 EM 并拉 SWINT。第一刀改它会继续扩大 Linux-only path，却仍无法证明真实 consumer 存在。

只有当 sidecar marker 证明 `SIDECAR_INGRESS_READY` 后，才轮到 driver 写 `cmd_len/cmd_seq/cmd_status` 或 real-event marker。

## 5. 为什么不是 RTL

当前目标是 software-first proof。Ingress v0 和 egress v0 都复用现有 EM/SWINT 观测面，不要求新增 RTL。没有 sidecar bootstrap proof 前改 RTL/Vivado 会扩大变量，且不能解决缺失 vendor runtime 的根因。

## 6. 为什么不是 init 里直接跑 fake userspace helper

Linux userspace helper 没有独立 controller execution context，不能拥有 CEVA IP reset、interrupt、timer，也不能证明 `rwip_init()` / `hci_cmd_received()` / `hci_send_2_host()` 的真实路径。它只能作为 packet/debug tool，不是 real consumer。

## 7. 最小 patch 内容

### 7.1 Sidecar skeleton

```text
_start:
  setup stack
  zero bss
  write_marker(SIDECAR_START)
  call main

main:
  write_marker(SIDECAR_PRE_RWIP_INIT)
  write_marker(SIDECAR_INGRESS_READY)
  loop forever
```

### 7.2 Build glue

Makefile 只构建 local `.elf/.bin`，不接 `rebuild_payload.sh`。使用现有 RISC-V baremetal toolchain，输出到 `build/`。

### 7.3 Documentation glue

README 写明：

- 这是 skeleton，不是 vendor runtime。
- 不接 HCI path。
- 不允许把 build output 提交。
- marker base 是 candidate，需要 G9-F/G9-G 批准后才能 run。

## 8. Build 验证

未来代码阶段的本地验证命令：

```bash
make -C sidecar/ceva_bt52_sidecar clean
make -C sidecar/ceva_bt52_sidecar
```

PASS：

- 生成 `.elf` 和 `.bin` 到 `build/`。
- map/dump 显示 entry、stack、marker constants 正确。
- `git status --short` 不出现 build output 被 staged。

FAIL 后退：

- 保留 source patch。
- 不改 driver/RTL。
- 修 linker/startup/toolchain 配置。

## 9. Run 验证

未来 board/J-Link 解锁后才运行。最小 run 验证：

- 清 marker page。
- 加载 skeleton。
- 启动 sidecar execution context。
- capture marker page。
- 看到 `SIDECAR_START`、`SIDECAR_PRE_RWIP_INIT`、`SIDECAR_INGRESS_READY`。
- Linux baseline 未退化。

本轮规划阶段不跑板、不启动 J-Link。

## 10. 回滚方式

方案 2 回滚简单：

- 删除或撤回 `sidecar/ceva_bt52_sidecar/` source patch。
- 删除本地 `build/` 产物。
- 不需要恢复 driver/RTL，因为第一刀不碰它们。
- 保留 G9 文档作为路线基线。

## 11. PASS / FAIL / STOP

PASS 条件：

- Sidecar skeleton source 能构建。
- 不修改 `ceva_bt52.c`、RTL、DTB/DTS、Vivado。
- 未来 run 能写 `SIDECAR_START` 和 `SIDECAR_INGRESS_READY`。

FAIL 条件：

- skeleton build 不通过。
- toolchain/linker/startup 缺失。
- build output 误入 git status staged set。

STOP 条件：

- 找不到任何可启动 execution context。
- skeleton 需要改 RTL 才能写 marker。
- sidecar memory 与 Linux 无法隔离。
