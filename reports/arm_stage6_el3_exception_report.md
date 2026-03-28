# ZCU104 A53 External Debug Stage 6

## Scope

This report captures the first successful ARM-side exception/sysreg evidence
obtained through the Windows xPack OpenOCD `xilinx_zynqmp.cfg` path, without
returning to repo-controlled bootrom/payload/UART experiments.

## Confirmed

- Windows xPack OpenOCD's `target/xilinx_zynqmp.cfg` includes:
  - `uscale.axi` on AP#0
  - `release_apu`, `resume_apu`, `start_apu`, `boot_apu`
  - CRF/APU reset and RVBAR helper logic
- `CRF_APB_RST_FPD_APU` is the real reset gate used by OpenOCD:
  - before release: `0x3d0f`
  - after `release_apu 0`: `0x380e`
- `EDPRSR` transitions prove the A53 debug power domain state changes:
  - before release and/or with reset asserted: `0x00000000` or `0x00000002`
  - after release: `0x00000009` then `0x00000001`
- `0x00000002` corresponds to `SPD=1, PU=0`, so the earlier examination failure
  was happening while the A53 core debug power domain was not powered.
- `release_apu 0` fixes the earlier `PU=0` condition and moves the problem out
  of the "cannot examine because core debug power domain is down" layer.
- With a pending debug request (`arp_halt` while running, even if it times out),
  then reassert-reset + `release_apu 0`, OpenOCD reliably halts A53#0 at:
  - `pc = 0xffff0000`
  - `cpsr = 0x000003cd`
  - current mode reported by OpenOCD: `EL3H`
  - `ELR_EL3 = 0xffff0000`
  - `ESR_EL3 = 0x02000000`
  - `SPSR_EL3 = 0x000001cd`
- Target memory at the halt address reads as:
  - `0xffff0000: deadbeef deadbeef deadbeef deadbeef ...`
- If `catch_exc sec_el3` is enabled and a single `step` is executed from that
  halted state, OpenOCD re-halts immediately with:
  - `debug_reason = exception-catch`
  - `pc = 0xffff0000`
  - `ELR_EL3 = 0xffff0000`
  - `ESR_EL3 = 0x02000000`
  - `SPSR_EL3 = 0x000001cd`

## Excluded

- The current OpenOCD reset/release path does **not** naturally run to `0x200`.
- The `0x200` hardware breakpoint, once `smp off` is used, can be programmed,
  but it does not trigger on the OpenOCD-driven reset/release path.
- The earlier `JTAG-DP STICKY ERROR` is **not** just a generic OpenOCD failure:
  it specifically occurred while A53 debug access was attempted with `PU=0`.
- Explicitly forcing `-ap-num 1` on the A53 target was **not** sufficient by
  itself to eliminate the examination failure.

## Unknown

- Why XSDB previously observed `A53@0x200` while the OpenOCD reset/release path
  now exposes a reproducible `A53@0xffff0000` EL3 reset-vector halt.
- Whether `0xdeadbeef` at `0xffff0000` is the true fetch content or a debug-side
  view of an invalid/placeholder early stub region.
- `VBAR_EL3` and `FAR_EL3` are still not exposed by the current OpenOCD
  register interface used here.

## Direct Interpretation

- The original OpenOCD blocker has been resolved one layer deeper:
  the A53 can now be examined once `release_apu 0` clears the APU reset bits and
  powers the core debug domain.
- The earliest ARM-side state currently captured by OpenOCD is an EL3 halt at
  `0xffff0000`, not `0x200`.
- The first stepped instruction path from that halt is consistent with an EL3
  exception catch at the same address. Combined with the `0xdeadbeef` memory
  pattern at `0xffff0000`, the strongest current inference is:
  the OpenOCD-visible reset vector path is landing on an invalid or placeholder
  early stub region, and the first instruction does not progress into a normal
  boot flow.

## Reproduction

- Start the Windows xPack OpenOCD server with
  [launch_windows_openocd_server.ps1](/root/chipyard/fpga/scripts/launch_windows_openocd_server.ps1)
- Run
  [openocd_a53_exception_probe.sh](/root/chipyard/fpga/scripts/openocd_a53_exception_probe.sh)

The probe log is written to:

- `logs/openocd_a53_exception_probe_<timestamp>.log`
