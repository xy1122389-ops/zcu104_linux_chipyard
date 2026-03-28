# ARM Stage 4 OpenOCD Driver Boundary Report

## Scope

This report captures the first successful attachment of a real external
DAP/CoreSight-aware client toolchain into the workflow, and the exact point at
which that workflow now stops.

The intent was to move past the previously known boundary:

`raw arm_dap reachable, but no ARM debug-component visibility`

and determine whether an external client could start exposing ZynqMP A53 debug
targets.

## Confirmed

### External client toolchain is now present

- Linux-side tools are installed:
  - `/usr/bin/openocd`
  - `/usr/bin/gdb-multiarch`
- OpenOCD includes:
  - [xilinx_zynqmp.cfg](/usr/share/openocd/scripts/target/xilinx_zynqmp.cfg)
  - Digilent/FTDI interface scripts

### Windows-side OpenOCD can be launched directly

- Windows-side `openocd.exe` can be executed directly from the current WSL
  shell by calling the `.exe` path itself.
- This bypasses the previous `cmd.exe` / `powershell.exe` vsock failure mode.

### OpenOCD target configuration is valid

- Multiple OpenOCD configs successfully parse far enough to create the
  `uscale.a53.0` target:
  `Info : [uscale.a53.0] Hardware thread awareness created`
- This proves the `xilinx_zynqmp.cfg` target layer is correct and the failure
  is later than target-definition parsing.
  Evidence:
  [windows_openocd_sweep_20260322_190148/custom.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom.log)

### The board-side FTDI identity is now concretely known

- Windows PnP enumeration shows the board-side USB device is:
  - `VID_0403`
  - `PID_6011`
  - serial prefix `07198`
- It is bound to FTDI drivers, not generic WinUSB/libusb-style generic access.
  Evidence:
  [windows_pnp_connected_20260322_190044.log](/root/chipyard/fpga/logs/windows_pnp_connected_20260322_190044.log:91)
  [windows_pnp_connected_20260322_190044.log](/root/chipyard/fpga/logs/windows_pnp_connected_20260322_190044.log:693)
  [windows_pnp_connected_20260322_190044.log](/root/chipyard/fpga/logs/windows_pnp_connected_20260322_190044.log:1922)

### Correcting the FTDI PID still does not unlock access

- After correcting the custom OpenOCD config from `PID 6014` to `PID 6011`,
  OpenOCD still fails to open the device.
- The more specific failure is now:
  `libusb_open() failed with LIBUSB_ERROR_NOT_FOUND`
  Evidence:
  [windows_openocd_sweep_20260322_190148/custom.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom.log:9)
  [windows_openocd_sweep_20260322_190148/custom_serial.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom_serial.log:10)

## Excluded

- The failure is **not** due to missing OpenOCD ZynqMP target support.
- The failure is **not** due to the repo-controlled design, payload, bootaddr,
  TLROM, or current bitstream path.
- The failure is **not** due to raw `arm_dap` non-reachability.
- The failure is **not** due to using the wrong FTDI PID after the corrected
  `PID_6011` sweep.
- The failure is **not** simply `hw_server.exe` holding the cable; the sweep was
  run after killing `hw_server.exe`, and the failure persisted.

## Unknown

- Whether rebinding the FT4232H interface(s) to WinUSB/libusbK on Windows would
  immediately allow OpenOCD to attach.
- Whether another external debugger that can use the FTDI driver stack directly
  (without libusb) could reach the same `arm_dap`.
- Whether, after clearing the FTDI driver boundary, OpenOCD would immediately
  expose enough A53 state to read exception sysregs or only a deeper DAP layer.

## Current Stuck Layer

Current stuck layer is now narrower than before:

- repo layer: excluded
- XSDB discovery layer: excluded
- raw DAP existence layer: excluded
- target-script layer: excluded
- **Windows FTDI driver / libusb device-opening layer: current blocker**

This is no longer an abstract "external capability missing" statement. It is a
specific external client attachment failure at the FTDI driver boundary.

## Minimal Log Set

- [windows_openocd_sweep_20260322_190148/smt2_nc.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/smt2_nc.log)
- [windows_openocd_sweep_20260322_190148/hs2.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/hs2.log)
- [windows_openocd_sweep_20260322_190148/custom.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom.log)
- [windows_openocd_sweep_20260322_190148/custom_serial.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom_serial.log)
- [windows_pnp_connected_20260322_190044.log](/root/chipyard/fpga/logs/windows_pnp_connected_20260322_190044.log)
- [linux_openocd_zcu104_try_20260322_175652.log](/root/chipyard/fpga/logs/linux_openocd_zcu104_try_20260322_175652.log)

## Direct Decision

Current decision: **D**

External capability gap still exists, but the boundary is now:

`Windows FT4232H driver access layer`

not just a generic debugger capability gap.

## Smallest Next External Requirement

One of the following is now sufficient and necessary:

1. Rebind the relevant FT4232H interface to `WinUSB/libusbK` so that
   Windows-side OpenOCD can open the cable.
2. Use a debugger/client that can drive the FT4232H through the currently bound
   FTDI driver stack instead of `libusb`.
3. Provide WSL USB passthrough so Linux-side OpenOCD can access the device
   directly.

## One-Line Summary

The next blocker is no longer "missing ARM debug semantics"; it is the Windows
FT4232H driver layer preventing OpenOCD from opening the already-identified
board JTAG device.
