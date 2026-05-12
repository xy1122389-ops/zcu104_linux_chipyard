# CEVA BT5.2 Phase 3B-G9F Sidecar Boot / Image Packaging 方案

## 1. 结论

当前 `rebuild_payload.sh`、initramfs 和 GDB launch flow 只打包/加载 Linux-side assets。G9-F 的下一步不是立即改 payload，而是定义 sidecar image staging、reserved memory、launch owner 和 marker proof。推荐第一版以 sidecar skeleton image 建立 build 和 launch contract；真实 vendor runtime 纳入要等 legal/vendor approval 和 memory reservation 确认后进行。

## 2. 当前边界

当前 payload/boot 证据显示：

- `rebuild_payload.sh` staging `bluetooth.ko`、`ceva_bt52.ko`、`phase25_user_hci_smoke`、`stage_mark`、initramfs、Linux `Image`、OpenSBI `fw_payload.bin`。
- `linux-bringup/initramfs/rootfs/init` 只负责 insmod、等待 `hci0`、运行 Phase 2.5 smoke。
- `scripts/linux_boot_phase2*.gdb` 负责加载 payload/DTB、清 marker、运行/capture Linux evidence。
- 当前没有 sidecar binary、sidecar loader、sidecar reserved memory、sidecar marker capture。

## 3. Sidecar binary 放哪

推荐 repo 内新增 source，不提交 build output：

```text
sidecar/ceva_bt52_sidecar/
  Makefile
  linker.ld
  start.S
  main.c
  marker.h
  bridge_contract.h
```

推荐生成物路径，仅本地构建使用，不提交：

```text
sidecar/ceva_bt52_sidecar/build/ceva_bt52_sidecar.elf
sidecar/ceva_bt52_sidecar/build/ceva_bt52_sidecar.bin
```

未来 packaging staging 路径：

```text
linux-bringup/payload/sidecar/ceva_bt52_sidecar.bin
```

该 staging 路径只在确认 legal/vendor approval 后用于真实 vendor runtime。skeleton 阶段可以只构建本地 artifact，不提交 `.elf` 或 `.bin`。

## 4. 由谁加载

分两级：

1. 开发 proof: GDB launch script 可以加载 sidecar skeleton 到候选 DDR 地址并启动，用来证明 marker 和 memory layout。该方式不能算最终交付路径。
2. 正式路线: OpenSBI 或更早 boot owner 负责加载 sidecar image、设置 stack/entry、释放 sidecar execution context，然后再进入 Linux。

如果 vendor 提供 CEVA internal firmware loader，则 loader owner 改为 vendor-defined boot path，OpenSBI 只负责不破坏 host-facing Linux boot。

## 5. 地址 / 内存区规划

候选规划如下，编码前必须用 DTB reserved-memory 或 boot memory map 锁定：

| region | candidate address | size | owner | 用途 |
|---|---:|---:|---|---|
| sidecar text/data | `0x8E000000` | 512 KiB | sidecar | skeleton 或 vendor runtime image |
| sidecar heap | `0x8E080000` | 256 KiB | sidecar | `ke_mem` / runtime heap first slice |
| sidecar stack | `0x8E0E0000` | 64 KiB | sidecar | baremetal stack |
| bridge marker | `0x8F010000` | 4 KiB | shared debug | G9-G marker page |
| legacy stage marker | `0x8F000000` | existing | Linux/GDB | 保留当前 Phase 2.5 marker，不复用为 sidecar base |

Open Blocker: exact DDR free range must be validated against Linux physical memory, initramfs, kernel image, DTB load address `0x84000000`, and any existing marker users before coding.

## 6. 何时启动

推荐启动顺序：

```text
boot owner clears marker page
boot owner loads sidecar image
boot owner starts sidecar execution context
sidecar writes SIDECAR_START
sidecar reaches SIDECAR_INGRESS_READY
Linux boots or continues
Linux driver publishes HCI Reset over ingress bridge
```

真实 Reset/RLV proof 要求 sidecar 在 Linux smoke 发送 HCI command 前已经到达 ingress-ready。

## 7. 如何证明启动

最小启动 proof：

- build log 中存在 sidecar image size/hash。
- capture script 读取 marker page，看到 `SIDECAR_IMAGE_PRESENT`。
- sidecar `_start` 写 `SIDECAR_START`。
- sidecar main 写 `SIDECAR_PRE_RWIP_INIT`。
- skeleton 阶段写 `SIDECAR_INGRESS_READY`。
- Linux baseline 仍启动，不出现内存覆盖或 panic。

接入 vendor runtime 后追加：

- `SIDECAR_POST_RWIP_INIT`
- `SIDECAR_POST_RWIP_DRIVER_INIT`
- `SIDECAR_HCI_SEND_2_HOST`

## 8. 是否影响 Linux boot

如果不做 reserved memory，风险很高。Linux 可能把 sidecar text/heap/marker 当作普通内存覆盖。正式进入代码前必须至少完成一种保护：

- DTB reserved-memory。
- OpenSBI 从 FDT memory node 中 carve out。
- dev-only GDB proof 在 Linux 使用范围之外加载，并通过 capture 证明未覆盖。

在 G9-F 文档阶段不改 DTS/DTB。未来如需 DTS/DTB 变更，必须另开受控 patch，且遵守禁止提交本地 DTB/DTS 生成物的规则。

## 9. 是否需要修改 GDB launch

需要，未来开发 proof 会新增：

- 清 `SIDECAR_MARKER_BASE` page。
- 加载 sidecar `.bin` 到候选 address。
- 可选设置 sidecar PC / hart start / release sequence。
- capture marker page。
- capture EM ingress/egress control words。

当前规划阶段不修改脚本。

## 10. 是否需要修改 `rebuild_payload.sh`

需要，但不是第一刀。未来当 sidecar source/build skeleton 已存在后，`rebuild_payload.sh` 可以增加：

- build sidecar skeleton 或引用预构建 sidecar binary。
- stage sidecar manifest 到 initramfs 或 payload metadata。
- 记录 sidecar image hash。
- 保证 `.elf`、`.bin` 不被提交。

第一刀不改 `rebuild_payload.sh` 的原因是：先证明 sidecar source 和 marker contract，再把它纳入 payload，避免把不存在的 runtime 打包成假路线。

## 11. PASS / FAIL / STOP

PASS 条件：

- sidecar source layout、build output path、candidate load address、marker base 已冻结。
- 明确 dev proof loader 与正式 loader 的区别。
- 明确未来需要 reserved memory，不在本轮提交 DTS/DTB。

FAIL 条件：

- sidecar binary 只存在于 initramfs 但没有任何执行路径。
- GDB 手工加载被当作最终产品 boot。
- build output `.elf` / `.bin` 被提交。

STOP 条件：

- 无法找到不被 Linux 覆盖的 memory region。
- 无法定义 sidecar entry/stack。
- sidecar 启动必须破坏当前 Linux boot baseline。
