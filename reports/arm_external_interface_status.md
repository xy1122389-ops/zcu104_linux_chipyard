# ARM External Interface Status

## Scope

This note records the final state of all *currently available* deeper debug
entries reachable from the local environment, after internal repo-side trial
and error was stopped.

## Newly Confirmed Interface Facts

- `gdbremote connect` exists, but it is **not** a local ARM-side register
  extractor by itself. It requires an external GDB remote server argument.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:35)
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:77)
- `xsdbserver start` exists and starts an XSDB command server, but it is still
  just an XSDB command proxy, not a dedicated ARM exception register channel.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:37)
  [xsdb_roundB_server_session_20260322_162804.log](/root/chipyard/fpga/logs/xsdb_roundB_server_session_20260322_162804.log:34)
- `osa` exists, but its help text confirms it is OS awareness over a symbol
  file, not an exception-state or ARM fetch interface.
  Evidence:
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:36)
- `jtag device_properties` confirms an `arm_dap` device on the chain with
  `idcode 0x5ba00477` and `irlen 4`.
  Evidence:
  [xsdb_roundD_jtag_probe_20260322_162528.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe_20260322_162528.log:38)
- `jtag sequence` is genuinely executable at the raw JTAG/DAP level once the
  JTAG target is selected. A minimal DR capture returned `7704a05b`.
  Evidence:
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:42)
- `rrd sys` is not a real readable register namespace in the current XSDB path.
  `rrd -defs sys` does not resolve, and both `rrd sys <n>` and `rrd sys.n`
  fail with `no register match`.
  Evidence:
  [xsdb_stage2_sys_probe_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe_20260322_172610.log:29)
  [xsdb_stage2_sys_probe2_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe2_20260322_172610.log:29)

## What This Means

- We still do **not** have a usable path to:
  - `ELR_ELx`
  - `ESR_ELx`
  - `VBAR_ELx`
  - `FAR_ELx`
  - `SPSR_ELx`
- We still do **not** have ARM-side trace or fetch visibility.
- We **do** have proof that the JTAG chain reaches a live `arm_dap`, but only
  at raw sequence level so far.

## Current Interface-Layer Boundary

The current hard boundary is now:

`raw JTAG/DAP reachable`  
`but no decoded ARMv8 exception sysreg / trace access path available`

## Minimum External Capability Still Needed

One of the following must be added:

1. An ARM-side debug/trace path that can read ARMv8 exception system registers
   or equivalent trace/fetch state.
2. A tool layer on top of the already-reachable `arm_dap` that can decode and
   access CoreSight / debug components.
3. A board-side observability path for the real PS-side early boot stub source.

## Direct Next Action Once Such Capability Exists

- First priority: bind the new interface to `A53#0` in the stable `PC=0x200`
  state.
- Then immediately try to read:
  `ELR`, `ESR`, `VBAR`, `FAR`, `SPSR`
- If sysregs are unavailable but trace/fetch exists, capture real ARM-side
  instruction flow for `0x1F0..0x220`.
