# CEVA BT5.2 Phase 0D EM Block Sweep PASS

## 1. 一句话结论

Phase 0D EM block sweep 板级通过。

## 2. 当前分支和提交

- Branch: `local/phase0b-s1-real-rw-dm-top`
- Commit: `35ebaed` (`Phase0C: validate CEVA EM BRAM window on board`)

## 3. 与 Phase 0C 的关系

Phase 0C 证明代表性点可独立寻址。

Phase 0D 在同一套 Phase 0C J-Link/GDB bringup 路径上，把验证从“代表性点”扩展为“连续区块整块写后整块回读”，证明连续区块可稳定写读。

## 4. 测试窗口

- `0x65010000 .. 0x6501ffff`

测试前先打开 CEVA EM debug range：

- `DEBUGADDMAX = 0x65000058 <- 0xffffffff`
- `DEBUGADDMIN = 0x6500005c <- 0x00000000`

## 5. 测试 block

- low block: `0x65010000`, 256B
- middle block: `0x65011000`, 4KB
- top block: `0x6501f000`, 4KB

## 6. Pattern 规则

本轮 block sweep 对每个 block 都依次覆盖以下三类 32-bit pattern：

- 地址相关 pattern: `expected = addr ^ 0xa5a50000`
- 反码 pattern: `expected = ~(addr ^ 0x5a5a0000)`
- 固定交替 pattern: `0x55aa33cc / 0xaa55cc33`

脚本以 32-bit word 为单位写完整个 block，然后对整个 block 做完整回读，并对每个 word 执行 `expected` / `actual` 比较；任意 mismatch 即立即 FAIL。

## 7. 是否修改 RTL / bitstream / wrapper

- 是否修改 RTL：否
- 是否重新综合 bitstream：否
- 是否修改 wrapper：否

## 8. 板测结果摘要

执行脚本：

- `bash scripts/read_ceva_phase0d_em_block_sweep.sh`

日志：

- `/tmp/phase0d_em_block_sweep.log`

执行策略：

- 单一 GDB 会话（single GDB session）完成整轮 block sweep，避免多次重连 J-Link 带来的连接掉线干扰。

板测结果：

- low block: 三类 pattern 全部 PASS
- middle block: 三类 pattern 全部 PASS
- top block: 三类 pattern 全部 PASS
- 最终输出：`PASS: Phase 0D EM block sweep passed`

本轮 sweep 实际覆盖：

- low block: `0x65010000 .. 0x650100ff`
- middle block: `0x65011000 .. 0x65011fff`
- top block: `0x6501f000 .. 0x6501ffff`

日志证据摘录：

- `[plan] single GDB session, total words per pattern set=2112`
- `PASS: low block all patterns`
- `PASS: middle block all patterns`
- `PASS: top block all patterns`
- `PASS: Phase 0D EM block sweep passed`
- `PHASE0D_EM_BLOCK_SWEEP_PASS`

## 9. 结论边界

当前结论只证明 EM window 连续区块的板级读写稳定性已经成立。

当前仍未完成的内容包括：

- 尚未定义真实 CEVA firmware / mailbox 协议
- 尚未接 IRQ
- 尚未写 Linux driver

## 10. 下一阶段建议

Phase 0E 可以准备单 IRQ 接入，但本轮不实现。