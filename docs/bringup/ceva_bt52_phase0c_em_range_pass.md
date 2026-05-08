# CEVA BT5.2 Phase 0C-B EM Range Sweep PASS

## 1. 结论

截至 2026-05-08，`RocketZCU104Phase0bConfig` 上的 CEVA EM debug window 已经完成一轮跨低位、中位和高位偏移的板级范围读写验证。

本轮不仅验证了 `0x65010000 / 0x65010004` 这两个相邻 word，还扩展验证了：

- 连续低地址 word
- 跨 cacheline / 小页步长
- 中间页地址位
- 高地址位
- top-of-window 边界 `0x6501fffc`

结论是：当前最小 EM BRAM 路径已经具备继续承载更具体 EM 区块布局的硬件正确性基础，Phase 0C-B PASS。

## 2. 执行方式

本轮执行脚本：

- `bash scripts/read_ceva_phase0c_em_window.sh`
- `bash scripts/read_ceva_phase0c_em_range.sh`

J-Link 路径：

- `127.0.0.1:3333`

EM debug window：

- `0x65010000 .. 0x6501ffff`

## 3. Range Sweep 覆盖偏移

本轮默认 sweep 偏移如下：

- `0x0000`
- `0x0004`
- `0x0008`
- `0x000c`
- `0x0010`
- `0x0020`
- `0x0040`
- `0x0100`
- `0x0400`
- `0x1000`
- `0x4000`
- `0xfffc`

这些偏移分别覆盖：

- 邻接 word
- 连续低位地址
- 中间页地址位
- 高位地址
- 窗口顶端边界

## 4. 板级结果

DEBUG 窗口控制寄存器先成功打开为全范围：

- `0x65000058 = 0xffffffff`
- `0x6500005c = 0x00000000`

随后 12 个代表性地址全部写后重读成功：

- `0x65010000 -> 0xC5000000`
- `0x65010004 -> 0xC5110012`
- `0x65010008 -> 0xC5220024`
- `0x6501000c -> 0xC5330036`
- `0x65010010 -> 0xC5440048`
- `0x65010020 -> 0xC555005D`
- `0x65010040 -> 0xC5660076`
- `0x65010100 -> 0xC57700B7`
- `0x65010400 -> 0xC5880188`
- `0x65011000 -> 0xC5990499`
- `0x65014000 -> 0xC5AA10AA`
- `0x6501fffc -> 0xC5BB40BA`

脚本最终输出：

- `PASS: Phase 0C-B CEVA EM range sweep passed`

## 5. 本轮证明了什么

本轮结果至少证明了以下几点：

- `0x65010000` 附近已经不存在此前那种相邻 word alias。
- wrapper 当前对 `em_addr` 的索引方式，已经正确覆盖从低地址到高地址的 word 索引。
- `0x6501fffc` 没有回绕到低地址，也没有被窗口内部其它位置镜像覆盖。
- 当前最小 EM BRAM 可以作为下一步 CEVA scratch / mailbox / sequence buffer 布局验证的基础。

## 6. 下一步边界

本轮 PASS 仍然只是 `Phase 0C` 的 bringup 基线，不等于已经完成 CEVA 正式 EM 功能定义。

下一步应在这个基线上继续做两件事：

- 把当前“代表性偏移”收敛成具体的 EM block 分区。
- 对候选分区再做更贴近真实 CEVA 使用方式的连续块读写验证。