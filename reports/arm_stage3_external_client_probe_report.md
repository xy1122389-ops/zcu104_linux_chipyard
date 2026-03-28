# ARM Stage 3 External Client Probe Report

## Scope

This report records the first attempt to move beyond the confirmed raw
`arm_dap` boundary by attaching a real external DAP/CoreSight-aware client
toolchain.

The objective of this stage was not to re-run internal XSDB experiments, but
to determine whether an external client path could be brought up at all from
the current environment.

## Confirmed

- Linux-side external client tooling is now installed:
  - `/usr/bin/openocd`
  - `/usr/bin/gdb-multiarch`
- OpenOCD includes the exact target script needed for the board family:
  [xilinx_zynqmp.cfg](/usr/share/openocd/scripts/target/xilinx_zynqmp.cfg)
- OpenOCD also includes Digilent/FTDI interface scripts compatible with the
  expected board-side FT4232H style adapters:
  [digilent-hs2.cfg](/usr/share/openocd/scripts/interface/ftdi/digilent-hs2.cfg)
  [digilent_jtag_smt2.cfg](/usr/share/openocd/scripts/interface/ftdi/digilent_jtag_smt2.cfg)
  [digilent_jtag_smt2_nc.cfg](/usr/share/openocd/scripts/interface/ftdi/digilent_jtag_smt2_nc.cfg)
- A minimal ZynqMP OpenOCD config was prepared:
  [openocd_zcu104_win_try.cfg](/root/chipyard/fpga/scripts/openocd_zcu104_win_try.cfg)
- Windows-side OpenOCD installation succeeded through Winget and was located at:
  `/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe`
- Attempting to launch Windows-side `openocd.exe` from the current WSL session
  fails *before* OpenOCD itself starts, with a WSL vsock bridge error.
  Evidence:
  [windows_openocd_zcu104_try_20260322_175607.log](/root/chipyard/fpga/logs/windows_openocd_zcu104_try_20260322_175607.log)
- The same WSL environment also fails even for trivial `cmd.exe` and
  `powershell.exe` invocations with the same vsock error, proving the issue is
  not OpenOCD-specific.
  Evidence came from the same command-line retry loop during this stage.
- Attempting Linux-side OpenOCD directly does start the client, but fails at
  USB access with:
  `libusb_init() failed with LIBUSB_ERROR_OTHER`
  Evidence:
  [linux_openocd_zcu104_try_20260322_175652.log](/root/chipyard/fpga/logs/linux_openocd_zcu104_try_20260322_175652.log)

## Excluded

- The failure is not in the repo-controlled boot path.
- The failure is not in the already-proven raw `arm_dap` / XSDB discovery path.
- The failure is not because OpenOCD support for ZynqMP is missing.
- The failure is not because the board target script is unavailable.

## Unknown

- Whether Windows-side OpenOCD would successfully enumerate the FT4232H and the
  ZynqMP chain if launched outside the current WSL-vsock-broken environment.
- Whether Linux-side OpenOCD would succeed if USB passthrough to WSL were
  available.
- Whether the first successful external client will expose:
  - ARMv8 exception sysregs
  - ARM-side trace/fetch
  - or only a deeper CoreSight/DAP layer that still needs another client

## Current Stuck Layer

The stuck layer has now moved and become more precise:

- Internal repo layer: excluded
- XSDB discovery layer: excluded
- Raw `arm_dap` layer: confirmed reachable
- External client process launch on Windows from current WSL session:
  **blocked**
- External client USB access on Linux from current WSL session:
  **blocked**

So the current immediate blocker is now:

`tool / OS bridge / USB visibility layer`

not the repo, not the board-mode setup, and not the existence of a suitable
client target definition.

## Minimal Log Set

- [windows_openocd_zcu104_try_20260322_175607.log](/root/chipyard/fpga/logs/windows_openocd_zcu104_try_20260322_175607.log)
- [linux_openocd_zcu104_try_20260322_175652.log](/root/chipyard/fpga/logs/linux_openocd_zcu104_try_20260322_175652.log)
- [xilinx_zynqmp.cfg](/usr/share/openocd/scripts/target/xilinx_zynqmp.cfg)
- [openocd_zcu104_win_try.cfg](/root/chipyard/fpga/scripts/openocd_zcu104_win_try.cfg)

## Direct Decision

Current decision: **D**

External capability gap still exists, but the boundary is tighter:

- We now know what external client to use (`openocd` + `gdb-multiarch`)
- We now know the correct target family script exists (`xilinx_zynqmp.cfg`)
- We now know the current environment fails *before* ARM sysreg/trace access:
  at Windows process bridging and Linux USB visibility

## Smallest Next External Requirement

One of the following must be provided:

1. A Windows-side shell or host process environment from which `openocd.exe`
   can be launched directly against the board FT4232H, bypassing the current
   WSL vsock failure.
2. Working USB passthrough from the board FT4232H into WSL so Linux-side
   OpenOCD can talk to the board.
3. Another external debugger that can attach to the same `arm_dap` without
   relying on the currently blocked Windows/WSL bridge path.

## One-Line Summary

The next blocker is no longer ARM debug semantics; it is external client
attachment at the OS bridge / USB visibility layer.
