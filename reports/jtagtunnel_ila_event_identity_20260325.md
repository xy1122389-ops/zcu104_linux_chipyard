# JTAGTUNNEL ILA Event Identity - 2026-03-25

## confirmed

- `JTAGTUNNEL` 内部状态机确实在跑。
  - `SHIFT` 有效
  - `TDI/TMS/tdiRegister` 有活动
  - `posCounter/negCounter` 会递增
- 对比下面三组刺激的 ILA CSV：
  - `mode0_w5`  
    [/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_raw_20260325_125007/jtagtunnel_ila.csv](/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_raw_20260325_125007/jtagtunnel_ila.csv)
  - `mode0_w8`  
    [/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_raw_20260325_125256/jtagtunnel_ila.csv](/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_raw_20260325_125256/jtagtunnel_ila.csv)
  - `bit1_len16`  
    [/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_custom_bit1_len16_20260325_130947/jtagtunnel_ila.csv](/root/chipyard/fpga/logs/jtagtunnel_ila_xsdb_custom_bit1_len16_20260325_130947/jtagtunnel_ila.csv)
- 去掉采样时间戳后，三者的 **event value sequence 完全一致**。
  - 证明不是 `w5/w8/bit1` 这几个低位 payload 差异导致了不同内部路径。
- 在三组波形的首个 `SHIFT` 窗口里：
  - `shiftCounter[6:0]` 全程保持 `00`
  - `tdiRegister` 都变成 `1`
  - `max_pos = 0x21`
  - `max_neg = 0x20`
- 这说明当前被 `JTAGTUNNEL` 消费的前导比特序列，在这三组刺激下被归一成了同一类行为；我们预期应该装进 `shiftCounter` 的那 7 个 bit，当前并没有按预期进入 width/IR 选择逻辑。
- 新增空刺激对照：
  - 只 `arm` ILA，不发任何 `XSDB USER4` raw 包，`hw_ila_1` 也会在 0 秒内进入 `FULL`
  - 说明当前 trigger 条件过宽，会捕获背景 JTAG 活动
  - 但空刺激波形与有刺激波形并不相同，第一处 value 差异出现在 `event index = 28`，对应：
    - `posCounter = 0x08`
    - `negCounter = 0x08`
  - 也就是说：
    - `posCounter = 0x01 .. 0x07` 这段对空刺激和有刺激完全相同
    - 第一处真正受 `XSDB raw payload` 影响的位置是在 `posCounter = 0x08`
- 这进一步说明：
  - 当前 `shiftCounter` 捕获窗口（`posCounter 1..7`）落在固定前缀里
  - 真正有语义差异的 payload，至少要到 `posCounter = 8` 才开始显现

## excluded

- 不是 Tcl 多字段 `drscan` 拼接顺序造成的假象。
- 不是 `mode0_w5`、`mode0_w8`、`bit1_len16` 真的走了不同的内部状态机路径。
- 不是单纯“再补一个 `shift=1`”就能解释的问题。
- 不是“ILA 抓到的全都是同一段背景活动”。
  - 空刺激和有刺激确实不同，只是差异出现得比当前 `shiftCounter` 采样窗口更晚。

## unknown

- 当前这条共同的内部事件序列，究竟是：
  - `USER4/XSDB drshift` 的固定前导包，
  - 还是 `nested tunnel` 入口本身就有固定 framing，
  - 还是我们当前原始 packet 模型和实际进入 `JTAGTUNNEL` 的 bit order/bit offset 仍然不一致。
- 还没拿到“哪一个输入 bit 位置会首次真正改变 `shiftCounter`”的最小映射。
- 还没把 ILA trigger 收紧到只抓 `XSDB raw USER4` 包本身，而不是“背景活动 + stimulus 叠加”。

## next

- 下一轮不再主打 `w5` vs `w8`。
- 下一轮主线改成两步：
  1. 先把 ILA trigger 收紧，尽量排掉背景 JTAG 活动
  2. 再做“bit 位置映射”：
     - 固定总长度
     - 只挪动单个 `1` 的位置
     - 找到第一个能让 `shiftCounter` 脱离 `00` 的 bit offset
- 一旦拿到这个 offset，就能判断是：
  - 外层 `USER4/BSCAN` 输入对齐问题
  - 还是 `JTAGTUNNEL` RTL 对 inner select/width 的解释问题
