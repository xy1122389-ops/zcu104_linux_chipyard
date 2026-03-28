# ZCU104 Linux UART Blocker Report

## Goal Status

Final goal not yet reached:

- No stable Linux-related serial text has been captured.

This report records why the current blocker has been narrowed to a manual
board-level UART verification step.

## Current Proven Bitstream

- Bitstream:
  [ZCU104FPGATestHarness.bit](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit)
- SHA256:
  `e0b9ed3e0ccb42fc1b29eb402e2bb86a3fd0b7c418e580a35c38850c1d9a6823`
- mtime:
  `2026-03-26 18:57:22 +0800`
- Build log:
  [zcu104_linuxbringup_make_bitstream_20260326_173746.log](/root/chipyard/fpga/logs/zcu104_linuxbringup_make_bitstream_20260326_173746.log)

The build log contains:

- `Router Completed Successfully`
- `The design met the timing requirement`
- `Bitgen Completed Successfully`

## Current Proven Payload

- Payload:
  `/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin`

Payload load evidence:

- [uart_linux_com7_20260326_180148/load_payload.log](/root/chipyard/fpga/logs/uart_linux_com7_20260326_180148/load_payload.log)
- [uart_linux_com7_20260326_180442/load_payload.log](/root/chipyard/fpga/logs/uart_linux_com7_20260326_180442/load_payload.log)

Both runs show:

- payload written to `PS DDR @ 0x00000000`
- boot address register written to `0x80000000`
- MSIP asserted

## Current Proven UART Routing

Generated shell constraints now bind UART to the board FT4232 UART2 path with
the corrected direction:

- [shell.xdc](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.shell.xdc)

Key lines:

- `uart_rxd -> A20`
- `uart_txd -> C19`
- `IOSTANDARD -> LVCMOS18`

Post-route IO report confirms the same final assignment:

- [io.txt](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/report/io.txt)

Relevant lines:

- `A20 | uart_rxd | LVCMOS18`
- `C19 | uart_txd | LVCMOS18`

## Current Proven Host Serial Mapping

Windows FT4232 enumeration confirms:

- `USB Serial Converter D`
- `FTDIBUS\VID_0403+PID_6011+07198D\0000`
- host serial port `COM7`

Evidence:

- [collect_ft4232_driver_state.ps1](/root/chipyard/fpga/scripts/collect_ft4232_driver_state.ps1)
- `/mnt/c/Windows/Temp/ft4232_driver_state_now/ft4232_devices.txt`

## Linux Serial Capture Result On New Bit

Targeted capture on `COM7` with the new bitstream:

- [uart_linux_com7_dualbaud_check.sh](/root/chipyard/fpga/scripts/uart_linux_com7_dualbaud_check.sh)
- [uart_linux_com7_dualbaud_20260326_180148](/root/chipyard/fpga/logs/uart_linux_com7_dualbaud_20260326_180148)

Per-baud runs:

- [uart_linux_com7_20260326_180148](/root/chipyard/fpga/logs/uart_linux_com7_20260326_180148)
- [uart_linux_com7_20260326_180442](/root/chipyard/fpga/logs/uart_linux_com7_20260326_180442)

Observed result:

- `COM7.log` contains only `UART_OPEN_OK\r\n`
- no `OpenSBI`
- no `U-Boot`
- no `Linux version`
- no extra raw bytes beyond the port-open marker

## Active DUT UART Injection Result On Corrected-Direction Bit

Single-port check:

- [uart_dut_uart_com7_check.sh](/root/chipyard/fpga/scripts/uart_dut_uart_com7_check.sh)
- [uart_dut_uart_com7_20260326_180853](/root/chipyard/fpga/logs/uart_dut_uart_com7_20260326_180853)

Triplet check:

- [uart_triplet_inject_check.sh](/root/chipyard/fpga/scripts/uart_triplet_inject_check.sh)
- [uart_inject_triplet_20260326_181201](/root/chipyard/fpga/logs/uart_inject_triplet_20260326_181201)

Observed result:

- `COM5.log` contains only `UART_OPEN_OK\r\n`
- `COM6.log` contains only `UART_OPEN_OK\r\n`
- `COM7.log` contains only `UART_OPEN_OK\r\n`
- no injected `UART_TEST_ZCU104_115200` text on any of the three visible FT4232 serial ports

Corrected-direction evidence:

- [uart_dut_uart_com7_20260326_190203](/root/chipyard/fpga/logs/uart_dut_uart_com7_20260326_190203)
- [uart_inject_triplet_20260326_190323](/root/chipyard/fpga/logs/uart_inject_triplet_20260326_190323)

Injection-side evidence shows the software-side write path was exercised:

- `TXCTRL=1`
- `DIV=0x1B1`
- bytes were written to `TXDATA`

Evidence:

- [uart_dut_uart_com7_20260326_180853/inject.log](/root/chipyard/fpga/logs/uart_dut_uart_com7_20260326_180853/inject.log)
- [uart_inject_triplet_20260326_181201/inject.log](/root/chipyard/fpga/logs/uart_inject_triplet_20260326_181201/inject.log)
- [uart_dut_uart_com7_20260326_190203/inject.log](/root/chipyard/fpga/logs/uart_dut_uart_com7_20260326_190203/inject.log)
- [uart_inject_triplet_20260326_190323/inject.log](/root/chipyard/fpga/logs/uart_inject_triplet_20260326_190323/inject.log)

## Reverse Path Check On Corrected-Direction Bit

Host-side send to `COM7` was probed against DUT UART RX MMIO:

- [uart_host_to_com7_check_20260326_190442.log](/root/chipyard/fpga/logs/uart_host_to_com7_check_20260326_190442.log)

Observed result:

- host-side `COM7` send returned `SEND_OK`
- DUT-side `RXDATA` remained `0x33333333`
- DUT-side `RXDATA_BYTE` remained `0x33`

So after correcting the TX/RX direction, the board-visible reverse path
`COM7 -> DUT RX` still does not produce a meaningful UART receive byte.

## Top-Level Netlist Evidence

Generated top-level netlist shows:

- top ports are present as `uart_txd` and `uart_rxd`
- `uart_txd_OBUFT_inst` exists
- `uart_txd_OBUFT_inst.T = 1'b0`
- `uart_rxd_IBUF_inst` exists

Evidence:

- [ZCU104FPGATestHarness.v](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.v)

This means the TX path is not trivially disabled by a permanently asserted
three-state control.

## Remaining Design Warning

Final DRC still reports:

- `RPBF-3: Device port uart_rxd expects both input and output buffering but the buffers are incomplete`
- `RPBF-3: Device port uart_txd expects both input and output buffering but the buffers are incomplete`

Evidence:

- [drc.txt](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/report/drc.txt)

This is a real warning, but it is no longer enough by itself to identify the
board-visible failure point, because the design still routes and produces a
bitstream successfully.

## Final Narrowed Blocker

The current blocker is no longer:

- payload load
- boot address programming
- MSIP kicking
- wrong host COM choice among `COM5/COM6/COM7`
- old `J9/K9` UART routing
- missing bitstream

The blocker has been narrowed to:

`manual board-level verification of the actual FPGA UART2 physical path`

because:

1. the corrected `A20/C19` bitstream is built and loaded
2. software actively writes the DUT UART MMIO
3. no bytes appear on any visible FT4232 serial port
4. even the reverse path `COM7 -> DUT RX` still does not produce a valid UART
   receive word

## Required Manual Actions

Run these in order:

1. Keep the corrected bitstream loaded.
2. Run:
   [uart_triplet_inject_check.sh](/root/chipyard/fpga/scripts/uart_triplet_inject_check.sh)
   or
   [uart_dut_uart_com7_check.sh](/root/chipyard/fpga/scripts/uart_dut_uart_com7_check.sh)
3. While the script is injecting, probe the board-level UART2 path with a scope
   or logic analyzer at the FPGA UART pins corresponding to:
   - `A20` for DUT TX
   - `C19` for DUT RX
4. Compare outcomes:

If `C19` toggles during injection:

- FPGA-side TX exists
- blocker moves to board FT4232 UART2 channel visibility / board routing / host exposure

If `C19` does not toggle during injection:

- blocker remains inside the design-side UART output path despite successful bit generation
- next step is deeper RTL/IO-buffer investigation, not more serial-port scanning

## Reproduction Chain

1. Build corrected bitstream:
   [rebuild_linuxbringup_make_bitstream.sh](/root/chipyard/fpga/scripts/rebuild_linuxbringup_make_bitstream.sh)
2. Load bitstream and payload:
   [run_ps_ddr_init_linux.sh](/root/chipyard/fpga/scripts/run_ps_ddr_init_linux.sh)
   [load_linux_fw_payload.sh](/root/chipyard/fpga/scripts/load_linux_fw_payload.sh)
3. Try Linux serial capture on the most likely port:
   [uart_linux_com7_dualbaud_check.sh](/root/chipyard/fpga/scripts/uart_linux_com7_dualbaud_check.sh)
4. Try active DUT UART injection:
   [uart_dut_uart_com7_check.sh](/root/chipyard/fpga/scripts/uart_dut_uart_com7_check.sh)
   [uart_triplet_inject_check.sh](/root/chipyard/fpga/scripts/uart_triplet_inject_check.sh)
