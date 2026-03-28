# ZCU104 Debug+BSCAN Field-Length Finding

## confirmed

- `nested tunnel` 的 `select IR` 回包家族，当前**主要跟 payload field 的实际 bit 长度走**，而不是跟包内编码的 `7-bit width field` 走。
- 新的正式矩阵脚本在：
  - [bscan_nested_select_sweep.sh](/root/chipyard/fpga/scripts/bscan_nested_select_sweep.sh)
  - [manual_dmi_width_validation.sh](/root/chipyard/fpga/scripts/manual_dmi_width_validation.sh)
  - [orthogonal_width_payloadlen_probe.sh](/root/chipyard/fpga/scripts/orthogonal_width_payloadlen_probe.sh)
- 关键日志：
  - [bscan_nested_select_sweep_20260324_162147](/root/chipyard/fpga/logs/bscan_nested_select_sweep_20260324_162147/summary.txt)
  - [manual_dmi_width_validation_m0_w5_p10_20260324_162407](/root/chipyard/fpga/logs/manual_dmi_width_validation_m0_w5_p10_20260324_162407/summary.txt)
  - [manual_dmi_width_validation_m0_w8_p10_20260324_162410](/root/chipyard/fpga/logs/manual_dmi_width_validation_m0_w8_p10_20260324_162410/summary.txt)
  - [manual_dmi_width_validation_m1_w6_p10_20260324_162535](/root/chipyard/fpga/logs/manual_dmi_width_validation_m1_w6_p10_20260324_162535/summary.txt)
  - [manual_dmi_width_validation_m1_w8_p10_20260324_162531](/root/chipyard/fpga/logs/manual_dmi_width_validation_m1_w8_p10_20260324_162531/summary.txt)
  - [manual_ir_select_plus1_probe_20260324_163002](/root/chipyard/fpga/logs/manual_ir_select_plus1_probe_20260324_163002/summary.txt)
  - [orthogonal_width_payloadlen_probe_20260324_163303](/root/chipyard/fpga/logs/orthogonal_width_payloadlen_probe_20260324_163303/summary.txt)
  - [orthogonal_dmi_width_payloadlen_probe_20260324_163553](/root/chipyard/fpga/logs/orthogonal_dmi_width_payloadlen_probe_20260324_163553/summary.txt)
  - [single_field_raw_packet_probe_20260324_165109](/root/chipyard/fpga/logs/single_field_raw_packet_probe_20260324_165109/summary.txt)

## core findings

### 1. payload value still does not matter

- 在 `mode0/mode1` 下，只要 `payload bit length` 固定，`payload` 从 `0x08/0x09/0x10/0x11/0x12/0x18` 切换时，`DTMCS` 家族不变。
- 这一步已经把“只是 IR 值选错了”继续压低了。

### 2. width family changes DTMCS family

- `payload bit length = 5` 时，`DTMCS` 家族固定为：
  - `01/24/01eed1c7e2/07`
- `payload bit length = 6` 时，`DTMCS` 家族固定为：
  - `00/12/01dc01f759/01`
- `payload bit length = 7` 时，`DTMCS` 家族固定为：
  - `00/49/018c6d7d04/01`
- `payload bit length = 8` 时，`DTMCS` 家族固定为：
  - `01/24/01ec5a38e2/07`

### 3. orthogonal probe: family tracks payload length, not encoded width field

- `width_field=6, payload_len=5`：
  - 仍落在 `payload_len=5` 家族
- `width_field=8, payload_len=5`：
  - 仍落在 `payload_len=5` 家族
- `width_field=5, payload_len=7`：
  - 直接跳到 `payload_len=7` 家族

这一步的硬意义是：

`当前 nested tunnel 的实际语义，显著受 payload field 实际移出的 bit 数控制，而不是受包里编码的 width 值控制。`

### 4. the same pattern now holds on DMI packets too

- 新加的 [orthogonal_dmi_width_payloadlen_probe.sh](/root/chipyard/fpga/scripts/orthogonal_dmi_width_payloadlen_probe.sh) 把 `DMI` 请求也做了同样的正交切分：
  - `width_field=41, payload_len=41`
  - `width_field=41, payload_len=42`
  - `width_field=41, payload_len=43`
  - `width_field=42, payload_len=42`
  - 地址同时比对 `0x10` 和 `0x11`
- 结果：
  - `REQ` 回包对 `width_field`、`payload_len`、`addr=0x10/0x11` 都基本不敏感
  - `NOP1/NOP2` 家族继续主要跟 `payload_len` 走
  - `addr=0x10` 和 `addr=0x11` 仍然不分家

这一步把根因进一步压缩成：

`问题已经不是单个 shift/单个地址字段提取点，而是 nested tunnel 的 packet framing / field-boundary / RTL 时序假设整体不匹配。`

### 5. single-field raw packet probe excludes Tcl multi-field packing as the main cause

- 我新增了 [single_field_raw_packet_probe.sh](/root/chipyard/fpga/scripts/single_field_raw_packet_probe.sh)，把 `select IR / DTMCS / DMI / NOP` 都打成单个 `drscan uscale.ps <bits> <hex>` raw packet。
- 结果：
  - `mode0_w5` 与 `mode1_w5` 完全同家族
  - `mode0_w8` 与 `mode1_w8` 完全同家族
  - 但 `w5` 和 `w8` 仍然分家
- 这一步说明：

`当前现象不是 Tcl 多字段 drscan 的拼接顺序假象。`

## DMI meaning

- `width family` 改变后，`DMI` 的后续 `NOP` 回包家族也会跟着变。
- 但在同一个 family 内，`0x10/0x11/0x12/0x16` 仍然没有分家。
- 所以当前还不能认为 `dmcontrol / dmstatus / hartinfo / abstractcs` 已经可信。

## excluded

- 不是“还差一个 payload 值”。
- 不是“mode0 和 mode1 的字段顺序不同，所以只是选错 mode”。
- 不是“仅仅 Windows openocd.exe 再补一个 `shift=1` 就会好”。

## unknown

- 是 `OpenOCD nested select_dmi` 自身就少了 `+1 skew bit`，还是当前 `JTAGTUNNEL` 对 nested IR scan 的时序理解和 OpenOCD 文档不一致。
- 是 `inner IR select` 本身错了，还是 `IR select` 对了但后续 `DMI` 帧还有第二层 field-boundary 失配。

## extra check

- 我额外加了一个简化模型搜索脚本：
  - [search_bscan_tunnel_models.py](/root/chipyard/fpga/scripts/search_bscan_tunnel_models.py)
- 它搜索了一批“单一偏移/单一 enter-shift 语义”类的简化时序模型，目标是解释：
  - `w5_len5 == w6_len5 == w8_len5`
  - `w5_len6` 与上面不同
  - `w5_len7` 与上面不同
  - `mode0/mode1` 在 family 上一致
- 当前搜索结果是：
  - `matches=0`

这说明当前现象不像单纯的 `+1/-1` 计数偏差，进一步提高了“整体 packet framing / field-boundary 假设错误”的概率。

## external reference correction

- 我把公开参考实现和文章也对上了：
  - [研究 Rocket Chip 的 BSCAN 调试原理](https://jia.je/hardware/2020/02/09/rocket-chip-bscan-analysis/)
  - [/tmp/fpga-rocket-chip-cnrv/verilog/peri/JtagTunnel.v](/tmp/fpga-rocket-chip-cnrv/verilog/peri/JtagTunnel.v)
- 这条参考明确说明：
  - `nested select IR` 包在参考实现里本来就是 `1 bit select + 7 bit width + payload(ir_width) + 3 bit zero`
  - 不是简单的 `payload(ir_width+1)`

这一步修正了一个风险判断：

`当前问题不能再简单归因成 “OpenOCD nested select_dmi 少了一个 +1 skew bit”。`

## next action

下一步最值钱的是：

1. 继续沿 `frame model / field-boundary` 主线，而不是继续追单个 `+1`
2. 把当前“family 跟 payload_len 走”的证据，反喂给 RTL/仿真模型
3. 重点验证：
   - 为什么参考 RTL 预期 `payload` 应该决定 inner IR
   - 但当前板上现象却表现成 `payload_len` 家族主导、`payload value` 基本无效
4. 再决定是改 `JTAGTUNNEL` RTL 时序，还是继续补 OpenOCD 的 packet 假设
