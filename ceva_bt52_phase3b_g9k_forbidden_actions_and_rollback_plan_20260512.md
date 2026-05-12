# CEVA BT5.2 Phase 3B-G9K 禁止项和回滚计划

## 1. 禁止提交文件

以下文件或目录不得提交：

- `fw_payload.bin`
- `initramfs.cpio`
- `initramfs.cpio.gz`
- `stage_mark` 生成物
- `phase25_user_hci_smoke` 生成物
- `build_verify.log`
- `rebuild_payload_execution.log`
- `generated-src/**` 新增/重生成内容
- `target/**`
- `obj/**`
- `*.bit`
- `*.dcp`
- `*.elf`
- `*.bin`
- `*.dump`
- 本地 `linux-bringup/dtb/*.dtb`
- 本地 `linux-bringup/dtb/*.dts`
- [scripts/run_ps_ddr_init.tcl](scripts/run_ps_ddr_init.tcl)
- vendor source/binary，除非 legal/vendor approval 明确允许且另开受控提交

## 2. 禁止动作

本路线在 sidecar bootstrap proof 之前禁止：

- 跑板。
- 启动 J-Link。
- rebuild payload。
- 修改 Linux driver。
- 修改 RTL。
- 运行 Vivado。
- 提交生成物。
- 提交 DTS/DTB。
- 提交 `run_ps_ddr_init.tcl`。
- 扩展 synthetic responder。
- 做 BlueZ scan/pair/connect。
- 把 H4TL/vendor runtime 直接塞进 Linux kernel。
- 把 Linux userspace helper 伪装成 controller。
- 在没有 marker 链证据时声称 real Reset pass。

## 3. 允许改动范围

当前规划阶段允许：

- 新增 G9-A 到 G9-L 规划文档。
- 新增纯文本 manifest 草案。
- 新增 dependency map 草案。
- 新增 bridge contract 草案。
- 新增伪代码级设计文档。
- 新增下一步 patch plan。

未来代码阶段在批准后允许：

- 新增 `sidecar/ceva_bt52_sidecar/` source。
- 修改 capture/launch 脚本以支持 sidecar marker proof。
- 在 sidecar proof 后，受控修改 Linux driver 的 bridge metadata 和 real-event marker。
- 在 packaging proof 阶段，受控修改 `rebuild_payload.sh`。

## 4. 每个 phase 的回滚点

| phase | 回滚点 | 回滚方式 |
|---|---|---|
| G9-A assets | 文档/manifest only | 保留 G9 总体规划，删除未获批 manifest 条目。 |
| G9-B dependency/build model | 文档 only | 回到 G9-A asset freeze，不进入 code。 |
| G9-C execution context | sidecar context decision | 如果无独立执行流，停在 Route C 并升级。 |
| G9-D ingress protocol | bridge contract v0 | 回到 EM/SWINT observation baseline，不改 driver。 |
| G9-E egress protocol | event contract v0 | 保留 ingress proof，关闭 egress hook。 |
| G9-F packaging | sidecar build/launch plan | 移除 launch hook，不提交 build output。 |
| G9-G markers | marker table | 清 marker additions，保留 old stage marker。 |
| G9-H first patch | sidecar skeleton | 删除 `sidecar/ceva_bt52_sidecar/` patch 和本地 build output。 |
| G9-I risk brief | management doc | 更新风险，不影响 code。 |
| G9-J schedule | execution plan | 重排，不影响 code。 |
| G9-K forbidden/rollback | guardrail doc | 更新规则，不影响 code。 |
| G9-L index | index doc | 更新链接，不影响 code。 |

## 5. 如果误提交生成物怎么恢复

如果生成物只是 staged：

```bash
git restore --staged <generated-file>
```

确认文件可再生成后，从工作区删除该生成物，或移动到 repo 外的临时目录。删除前先确认不是用户手工资产。

如果生成物已经进入 commit：

- 新建一个修正提交，只移除生成物。
- 保留源文件和构建规则。
- 在修正提交说明中记录生成物误入原因。
- 不用重写历史，除非用户明确要求。

如果误提交 vendor source/binary：

- 立即停止继续传播。
- 记录具体路径。
- 请求 legal/vendor owner 确认处理方式。
- 在未获批前移除该内容并停止相关构建。

## 6. 如果 sidecar 方案失败怎么回到 G9 文档基线

回退步骤：

1. 关闭 sidecar launch hook。
2. 移除 `rebuild_payload.sh` 中的 sidecar staging。
3. 保留 G9-A 到 G9-L 文档作为失败证据和后续 Route 评审材料。
4. 恢复默认 Linux boot/smoke baseline。
5. 不回到 synthetic success 路线作为真实 pass。
6. 不因 sidecar fail 自动打开 RTL/Vivado；只有 Open Blocker 指向硬件分区问题时才另开硬件评审。

## 7. Agent 后续执行守则

- 先读当前 `git status --short`，区分用户已有 dirty file 和本任务改动。
- 不 revert 用户已有改动。
- 不碰 `linux-bringup/dtb/chipyard-zcu104-fedora.dtb`、`.dts` 和 `scripts/run_ps_ddr_init.tcl`。
- 长命令要有 watchdog，不让全 `/mnt` 搜索挂死。
- `rg` 不存在时用限定文件列表和 `grep -I`，不扫 binary image。
- 每次生成文档后跑 placeholder check。
- 每次结束前跑 forbidden generated output check。
