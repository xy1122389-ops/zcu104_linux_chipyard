# OpenOCD Variant Comparison

## Scope

This note compares the currently relevant Windows OpenOCD configuration
variants and freezes the mainline for the next stage.

## Confirmed

### Why `custom_serial` is the only mainline

- It uses the board's currently confirmed FT4232H identity:
  - `VID_0403`
  - `PID_6011`
  - serial prefix `07198`
- It is the only variant family intentionally constrained to the known device
  serial, which removes ambiguity when multiple FTDI devices or interfaces may
  exist on the host.
- Per the current accepted working facts for this stage, both `custom` and
  `custom_serial` have already advanced past plain open-device failure and into
  `C_jtag_scan_progressed`, with `custom_serial` specifically showing:
  - `tap/device found`
  - `JTAG-DP STICKY ERROR`
  - `[uscale.a53.0] Examination failed`
  - `[uscale.axi] Examination succeed`
- Therefore, the correct mainline is:
  **`custom_serial`**

### Why `hs2`, `hs3`, and `smt2_nc` are eliminated from the mainline

Historical logs in this repo show:

- `hs2` fails with:
  `unable to open ftdi device with description 'Digilent Adept USB Device'`
- `hs3` fails with:
  `unable to open ftdi device with description 'Digilent USB Device'`
- `smt2_nc` fails with:
  `unable to open ftdi device with description 'Digilent USB Device'`

Evidence:
- [windows_openocd_sweep_20260322_190148/hs2.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/hs2.log)
- [windows_openocd_sweep_20260322_190148/hs3.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/hs3.log)
- [windows_openocd_sweep_20260322_190148/smt2_nc.log](/root/chipyard/fpga/logs/windows_openocd_sweep_20260322_190148/smt2_nc.log)

These variants are therefore excluded from the mainline because they fail
earlier, at device-open stage, before any useful `A53`-side progress.

## Direct Failure Comparison

### `hs2`

- direct cause: FTDI device open failure
- likely explanation: wrong interface description/layout for the present board
  cable
- classification: `B_open_device_failed`

### `hs3`

- direct cause: FTDI device open failure
- likely explanation: wrong board/interface description for the current cable
- classification: `B_open_device_failed`

### `smt2_nc`

- direct cause: FTDI device open failure
- likely explanation: wrong Digilent USB description / wrong layout path for
  the current cable
- classification: `B_open_device_failed`

### `custom`

- current repo-local historical evidence:
  after correcting to `PID 6011`, it still failed at `libusb_open`
- current accepted stage fact:
  it can now progress into JTAG scan / A53 examination stage

### `custom_serial`

- current accepted stage fact:
  progresses into JTAG scan / A53 examination stage
- preferred over `custom` because it binds to the known `07198` serial path
- this makes it the only mainline variant to continue using

## Confirmed Stage Movement

The blocker has moved:

- from **USB driver open failure**
- to **A53 examination failure**

More specifically, the current accepted mainline blocker is no longer:

- FTDI open
- cable identification
- basic OpenOCD target-script parsing

It is now:

- `JTAG-DP STICKY ERROR`
- `[uscale.a53.0] Examination failed`

while still seeing:

- `tap/device found`
- `[uscale.axi] Examination succeed`

That is a significantly deeper failure layer than the old `B_open_device_failed`
class.

## Excluded

- `hs2` as mainline
- `hs3` as mainline
- `smt2_nc` as mainline
- any mainline that does not pin the known FT4232H serial identity

## Unknown

- Whether speed `1000/500/200` changes the sticky-error behavior
- Whether `custom` and `custom_serial` are still equivalent once speed is
  swept
- Whether the next blocker after sticky-error will be DAP-protocol, core-debug,
  or ARM exception-layer

## Mainline Freeze

Mainline is now frozen to:

- `openocd_zcu104_win_custom_serial_1000.cfg`
- `openocd_zcu104_win_custom_serial_500.cfg`
- `openocd_zcu104_win_custom_serial_200.cfg`

and the only valid next matrix is the speed sweep under that family.
