# ARM Stage 5 Windows Driver Rebind Plan

## Goal

Move the current boundary from:

`Windows FT4232H driver / libusb device-opening layer`

to a state where a DAP/CoreSight-aware client (`OpenOCD`) can at least:

- open the board cable,
- enumerate the JTAG chain,
- expose the ZynqMP A53 debug targets,
- and then attempt ARM-side exception sysregs or trace.

This plan does **not** execute the rebind. It is the implementation package for
the next operator step.

## Current Hard Evidence

- Windows-side `openocd.exe` starts successfully and loads
  `xilinx_zynqmp.cfg`.
- It successfully creates `uscale.a53.0` target definitions before failing.
- Failure occurs at FTDI device opening:
  `libusb_open() failed with LIBUSB_ERROR_NOT_FOUND`
- Current Windows enumeration shows the board USB device is:
  - parent composite: `USB\\VID_0403&PID_6011\\07198`
  - interfaces:
    - `USB\\VID_0403&PID_6011&MI_00\\...`
    - `USB\\VID_0403&PID_6011&MI_01\\...`
    - `USB\\VID_0403&PID_6011&MI_02\\...`
    - `USB\\VID_0403&PID_6011&MI_03\\...`
  - ports example:
    - `FTDIBUS\\VID_0403+PID_6011+07198B\\0000` -> `COM5`
- Current driver stack appears to be FTDI serial-stack based, not libusb/WinUSB
  based.

Evidence:
- [windows_pnp_connected_20260322_190044.log](/root/chipyard/fpga/logs/windows_pnp_connected_20260322_190044.log)
- [windows_openocd_sweep_20260322_190148/custom.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom.log)
- [windows_openocd_sweep_20260322_190148/custom_serial.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/custom_serial.log)

## Objects To Distinguish

### FT4232H composite parent

Current expected identity:

- `USB\VID_0403&PID_6011\07198`

This is the **preferred first binding target** for WinUSB/libusbK validation,
because it gives the cleanest answer to:

`can the whole board cable be opened by libusb-aware tooling at all?`

### FT4232H individual interfaces

Current expected identities:

- `USB\VID_0403&PID_6011&MI_00\...`
- `USB\VID_0403&PID_6011&MI_01\...`
- `USB\VID_0403&PID_6011&MI_02\...`
- `USB\VID_0403&PID_6011&MI_03\...`

These should only be used as a second choice if composite-parent rebinding is
not possible or does not affect OpenOCD attach behavior.

## Required Files

- Driver-state collector:
  [collect_ft4232_driver_state.ps1](/root/chipyard/fpga/scripts/collect_ft4232_driver_state.ps1)
- Post-rebind OpenOCD verifier:
  [verify_openocd_after_rebind.ps1](/root/chipyard/fpga/scripts/verify_openocd_after_rebind.ps1)

## Rebind Strategy

### Preferred order

1. Capture **pre-change** state with the collector script.
2. Attempt **composite parent** rebind to `WinUSB` or `libusbK`.
3. Re-run the verification script.
4. Only if composite-parent rebinding is impossible or ineffective:
   attempt interface-level rebind, one interface group at a time.

### Why composite parent first

- It gives the strongest yes/no answer about whether the FT4232H cable, as
  enumerated by Windows, is fundamentally available to libusb-aware tooling.
- It reduces ambiguity compared with changing one MI interface at a time.
- It makes rollback reasoning cleaner.

## Operator Procedure

### Step 1: capture baseline

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\collect_ft4232_driver_state.ps1
```

Expected outputs:

- parent + interface device list
- driver provider / INF / service
- hardware IDs
- compatible IDs
- parent / child relationship view
- current `hw_server.exe` presence
- current OpenOCD failure logs if available

### Step 2: perform rebind

Use your preferred Windows driver binding tool (for example Device Manager or a
WinUSB/libusbK binding tool such as Zadig) with this priority:

1. composite parent `USB\VID_0403&PID_6011\07198`
2. only if needed, the individual MI interfaces

Target binding:

- first try `WinUSB`
- if tooling policy prefers it, try `libusbK`

### Step 3: post-change verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify_openocd_after_rebind.ps1
```

Expected questions answered:

- Did OpenOCD get past `libusb_open()`?
- Did it enumerate FTDI successfully?
- Did it enumerate JTAG / `arm_dap`?
- Did it expose ZynqMP targets?

## Validation Checklist

### Before rebind

- Device enumeration saved
- Parent/interface mapping saved
- Driver provider / INF / service saved
- Current OpenOCD failure saved

### After rebind

- OpenOCD no longer fails at `libusb_open()`
- OpenOCD either:
  - reaches adapter open + JTAG scan
  - or fails later at chain/target stage

## Failure Classification

### A. Rebind succeeds and OpenOCD directly connects

Meaning:

- Driver boundary solved
- Next stage is ARM debug-component / exception sysreg or trace access

Next action:

- immediately attempt `targets`, `aarch64` target visibility, and exception
  sysreg / trace acquisition

### B. Rebind done, OpenOCD still cannot open device

Meaning:

- still stuck at Windows driver-binding layer
- likely wrong device bound or unsupported FTDI stack state

Next action:

- inspect collector output for parent/interface mismatch
- try the alternate driver (`WinUSB` vs `libusbK`)

### C. Rebind done, OpenOCD opens device but JTAG scan/target setup fails

Meaning:

- driver boundary is solved
- next blocker has moved to JTAG chain / target / DAP protocol stage

Next action:

- keep using external client path
- adjust OpenOCD interface/target config only

### D. Rebind impacts UART or other FTDI interfaces

Meaning:

- expected risk materialized

Next action:

- rollback immediately to original FTDI stack using the saved baseline state

## Rollback Plan

### What to restore

Restore the original FTDI-oriented stack captured by the collector:

- composite parent back to `usb.inf` if changed
- MI interfaces back to FTDI interface driver (`oem56.inf` in current evidence)
- COM-port function drivers back to FTDI serial-port driver (`oem57.inf` in
  current evidence)

### How to roll back

1. Open Device Manager
2. Use the saved baseline report from the collector script
3. Reassign the modified device(s) back to the original driver package(s)
4. Re-run the collector script to confirm:
   - `USB Serial Converter A/B/C/D`
   - `USB Serial Port (COMx)` return

### UART recovery check

If UART visibility is affected:

1. restore interface driver bindings first
2. confirm COM ports reappear
3. only then resume any serial-dependent workflow

## Confirmed / Excluded / Unknown

### confirmed

- The current blocker is the Windows FT4232H driver/libusb opening boundary.
- A real external client path now exists and reaches this boundary.
- Composite parent and interface identities are known and can be targeted
  precisely.

### excluded

- This is not a repo-controlled bootrom/TLROM/payload/UART problem.
- This is not an OpenOCD-target-script absence problem.
- This is not a raw `arm_dap` existence problem.

### unknown

- Whether composite-parent rebind alone is sufficient
- Whether `WinUSB` or `libusbK` is the correct working target in this setup
- Whether, after rebind, OpenOCD will immediately expose the A53 exception/trace
  layer or only the next-lower DAP/CoreSight layer

## Next Blocker

Windows FT4232H driver binding for libusb-aware external client access.

## Next Action

Run the collector script, perform the composite-parent-first rebind on Windows,
and then run the verifier script.
