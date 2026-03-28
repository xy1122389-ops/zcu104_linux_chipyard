# ZCU104 / Chipyard / Linux Bring-up - 2026-03-23

## 今日完成

- 将 `MI_00` 从 `libwdi/oem63.inf` 恢复为 `FTDI/oem52.inf`，JTAG 控制链恢复。
- 重新验证 `XSDB` target 枚举已恢复，`PS TAP / PSU / APU / Cortex-A53 #0..#3` 可见。
- 重新打通 `psu_init + Linux bringup bitstream download`。
- 重新打通 `fw_payload.bin` 下发：
  - payload 已写入 `PS DDR @ 0x00000000`
  - `boot-address-reg` 已写为 `0x80000000`
  - `MSIP` 已置为 `1`
- 对启动控制寄存器做了现态检查：
  - `boot-address-reg@0x1000 = 0x80000000`
  - `tile-reset-setter@0x110000 = 0x00000000`
  - `msip@0x2000000 = 0x00000001`
  - `clock-gater@0x100000` 初始读到 `0x00000000`
- 新增了 `clock-gater=1 + bootaddr 重写 + msip 重脉冲` 启动链，并完成一次正式复测。
- 新增了 `tile-reset 1->0 pulse + msip 重脉冲` 启动链，并完成一次正式复测。
- 完成三口并行串口抓取：
  - `COM5`
  - `COM6`
  - `COM7`
  三口都能正常打开。
- 完成主动 UART 注入测试：
  - 直接对 `serial@0x64000000` 配置 `TXCTRL=1`
  - `DIV=0x1B1`（115200）
  - 写入测试字符串 `UART_TEST_ZCU104_115200`
  - 三个串口都未收到注入字符串。
- 重新梳理当前 Linux bring-up 设计的 UART 约束与板级物理路由。
- 发现当前 bitstream 的 DUT UART 物理路由不对，已将约束从 `J9/K9 @ LVCMOS33` 改到板载 FT4232 对应的 `A20/C19 @ LVCMOS18`。
- 已启动新的 Linux bring-up bitstream 重建：
  - `synth_1` 完成
  - `place_design` 完成
  - `phys_opt_design` 完成
  - `route_design` 进行中

## 新增硬结论

- `MI_00` 的 `libwdi` 绑定确实会导致 `XSDB` 看不到任何 target；恢复到 `FTDI/oem52.inf` 后，`XSDB` 控制链立即恢复。
- 当前 bring-up 失败已不再是 `XSDB` 控制链失明问题。
- `tile-reset-setter@0x110000` 不是当前主 blocker：
  - 历史可读值为 `0x00000000`
  - 今日现态仍为 `0x00000000`
  - 对它做 pulse 后，串口仍无 Linux 关键字
- `clock-gater@0x100000` 是一个真实启动变量：
  - 今日现态初始值为 `0x00000000`
  - 可被稳定写成 `0x00000001`
  - 但仅把它置 `1` 仍不足以带来 Linux 串口输出
- `bootaddr/msip/payload` 这条链当前是通的：
  - `bootaddr=0x80000000`
  - `MSIP=1`
  - payload 已成功写入 DDR
- 当前 bitstream 的 DUT UART 物理输出没有落到今天抓取的 `COM5/COM6/COM7` 对应通道上。
- 直接对 `serial@0x64000000` 做 UART 注入，但 `COM5/COM6/COM7` 全部无回显，说明问题不是“Linux没到串口”这么简单，而是“当前 bitstream 的 UART 物理路由和抓取口不匹配”。
- 当前主问题已从“启动链寄存器控制”进一步收敛为：
  `Linux bring-up bitstream 的 UART 物理约束/板级映射错误`

## 当前 blocker

- 修正 UART 物理路由后的新 bitstream 还未生成完成；当前卡在 `route_design -> write_bitstream` 阶段。
- 在新 bit 下载到板上之前，无法验证：
  - DUT UART 是否真正落到板载 FT4232 串口通道
  - Linux early print 是否能在串口出现

## 已排除项

- `MI_00` 驱动权限问题作为当前主 blocker
- `XSDB` target 枚举失明
- `payload` 未成功下发到 DDR
- `boot-address-reg` 未正确写入
- `MSIP` 未正确触发
- `tile-reset-setter` 持续把 hart 压在 reset
- 只差 `clock-gater=1` 这一项就能恢复 Linux 输出
- `COM5` 单口误判问题
  - 今日已并行验证 `COM5/COM6/COM7`
- “只是串口抓取脚本有问题”
  - 三口都能稳定打开
  - 但连主动 UART 注入都没有回显

## 明日计划

- 等待并确认新的 Linux bring-up bitstream 完成。
- 下载新 bitstream 到板上。
- 先做一次 `UART inject` 复测，确认 `COM5/COM6/COM7` 中哪个口真正接到 DUT UART。
- 在确认输出口后，重跑：
  - `psu_init`
  - `payload load`
  - `bootaddr/msip`
  - 串口 Linux 抓取
- 扫描并确认以下关键字是否出现：
  - `Linux version`
  - `Booting Linux`
  - `Starting kernel`
  - `Kernel command line`
- 如果新 bit 下三口仍然都没有 DUT UART 注入回显：
  - 直接回看新的 `io report / drc / shell.xdc`
  - 继续收敛真实 UART 物理映射，而不是回退到 payload / bootaddr / OpenOCD 老分支
