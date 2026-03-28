# External Capability Integration Pack

## Goal

Prepare the next stage of debugging without further internal trial-and-error in
the current repo, bitstream, bootrom, UART, payload, or shallow XSDB command
surface.

## Current Local Tool Paths

- `XSDB batch launcher`
  [xsdb.bat](/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat)
- `XSDB executable backend`
  [rdi_xsdb.exe](/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/unwrapped/win64.o/rdi_xsdb.exe)
- `ARM Cortex-A53 register header from Xilinx BSP`
  [xreg_cortexa53.h](/mnt/e/PRO_APP/xilinx/Vivado/2021.2/data/embeddedsw/lib/bsp/standalone_v7_4/src/arm/ARMv8/64bit/xreg_cortexa53.h:14)

## Already Verified XSDB Deep Entries

- `gdbremote connect`
  Confirmed command exists.
  Confirmed requirement: external `<server>`.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:35)
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:77)
- `xsdbserver start`
  Confirmed command exists.
  Confirmed it starts an XSDB command server and returns host/port.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:37)
  [xsdb_roundB_server_session_20260322_162804.log](/root/chipyard/fpga/logs/xsdb_roundB_server_session_20260322_162804.log:34)
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:95)
- `osa`
  Confirmed command exists.
  Confirmed purpose: OS awareness over a symbol file.
  Not an exception/trace interface by itself.
  Evidence:
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:36)
- `jtag device_properties`
  Confirmed command exists.
  Confirmed `arm_dap` target shape:
  `idcode 0x5ba00477`, `irlen 4`, name `arm_dap`.
  Evidence:
  [xsdb_roundD_jtag_probe_20260322_162528.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe_20260322_162528.log:38)
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:244)
- `jtag sequence`
  Confirmed command exists.
  Confirmed a sequence object can be created and executed when the JTAG target
  is explicitly selected.
  Confirmed raw readback value: `7704a05b`.
  Evidence:
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:40)
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:42)

## Current Raw DAP Evidence

- JTAG chain enumerates:
  `xczu7` FPGA device plus `arm_dap` device.
  Evidence:
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:34)
- `arm_dap` is definitely accessible as a JTAG target.
- Raw `jtag sequence` execution is working.
- What is still missing is not physical access, but a higher-level DAP/CoreSight
  protocol layer that can turn this raw path into ARMv8 exception or fetch
  evidence.

## What Has Not Been Obtained

- No `ELR_ELx`
- No `ESR_ELx`
- No `VBAR_ELx`
- No `FAR_ELx`
- No `SPSR_ELx`
- No ARM-side instruction trace or fetch stream

## Most Likely External Capability Paths

1. ARM-side exception sysreg visibility over a deeper debugger path
2. ARM-side trace/fetch visibility over a deeper debugger path
3. External observability or replacement of the true PS-side early boot ROM/stub

## First External Validation Targets

- Can we read `ELR`?
- Can we read `ESR`?
- Can we read `VBAR`?
- Can we read `FAR`?
- Can we read `SPSR`?
- Can we see real A53 ARM-side fetch or trace around `0x1F0..0x220`?

## External Entry Plans

### Scenario A: ARM-side exception sysreg capability becomes available

First round:

1. Recover to stable `A53#0 @ PC=0x200`.
2. Read `ELR_ELx`, `ESR_ELx`, `VBAR_ELx`, `FAR_ELx`, `SPSR_ELx`.
3. Record current exception level and exception-return address.
4. Decide whether `0x200` is:
   an exception landing point,
   a debug vector path,
   or a stub reached by non-exception control flow.

Expected decision output:

- current exception level
- exception return address
- exception syndrome / reason
- vector base
- direct explanation of why `A53` is at `0x200`

### Scenario B: ARM-side trace or fetch capability becomes available

First round:

1. Recover to stable `A53#0 @ PC=0x200`.
2. Capture true ARM-side fetch or trace for at least `0x1F0..0x220`.
3. Determine whether the bytes there are valid A64 instructions.
4. Classify the path as:
   branch loop,
   undefined/fault path,
   exception vector stub,
   debug stub,
   or another early stub.

Expected decision output:

- real ARM instruction bytes
- decoded A64 instructions
- whether `0x200` is a valid instruction boundary
- whether the current non-progress is real execution or debug presentation

### Scenario C: Real PS-side boot ROM/stub observability or replacement becomes available

First round:

1. Identify the actual board-visible early stub source.
2. Apply a minimal sentinel or equivalent perturbation there.
3. Re-check whether `A53@0x200` and/or the visible low window changes.
4. Use that perturbation to connect the observed `A53` state back to a real
   source image.

Expected decision output:

- actual stub source
- whether `A53@0x200` depends on it
- whether the low window and A53 state shift together

## Candidate Source Ranking And Validation Entry

1. PS/ARM-side fixed early boot / exception / debug vector
   Validation entry: ARM-side exception sysregs or trace
2. Board-side real ROM or stub outside repo-controlled `TLROM`
   Validation entry: external observability or replacement of that stub source
3. PS-side PMC/PMU or other fixed handoff path
   Validation entry: PS/PMC/PMU-side boot observation interface
4. Repo-controlled `TLROM`
   Already excluded by sentinel A/B
5. Repo-controlled payload/bootaddr
   Already excluded as a true early boot source

## Ready-To-Use Handoff Statement

The next productive step is no longer an internal repo modification. The next
productive step is to attach a deeper ARM-side exception/trace capability, or a
board-side early boot source observation capability, and then immediately run
the first-round validation flow above.
