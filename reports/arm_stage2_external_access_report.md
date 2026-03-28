# ARM Stage 2 External Access Report

## Scope

This report captures the *post-XSDB-boundary* stage: after repo-controlled
bootrom/bitstream/payload/UART paths were formally ruled out, and after the
existing XSDB high-level and semi-deep entries were explored.

The goal of this stage was to determine whether the current local environment
could be extended far enough to expose one of the following:

- ARMv8 exception system registers (`ELR/ESR/VBAR/FAR/SPSR`)
- ARM-side trace/fetch
- a clearly deeper CoreSight / ARM debug-component path

## Confirmed

### Confirmed tool-layer reachability

- `gdbremote connect` exists as a command, but requires an external remote GDB
  server argument.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:35)
- `xsdbserver start` exists and can start an XSDB command server, returning a
  host/port.
  Evidence:
  [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log:37)
  [xsdb_roundB_server_session_20260322_162804.log](/root/chipyard/fpga/logs/xsdb_roundB_server_session_20260322_162804.log:34)
- `osa` exists, but its help explicitly identifies it as OS awareness over a
  symbol file, not exception-state visibility.
  Evidence:
  [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log:36)
- `jtag device_properties` exists and confirms a reachable `arm_dap` device:
  `idcode 0x5ba00477`, `irlen 4`.
  Evidence:
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:34)
  [xsdb_jtag_prop_probe_20260322_172818.log](/root/chipyard/fpga/logs/xsdb_jtag_prop_probe_20260322_172818.log:29)
- `jtag sequence` exists and can execute on the selected `arm_dap` target.
  Raw DR capture succeeded and returned `7704a05b`.
  Evidence:
  [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log:42)

### Confirmed current depth boundary

- The current environment can reach **raw JTAG / ARM DAP bit-level access**.
- The current environment does **not** expose ARMv8 exception system registers
  through `rrd`.
- `rrd sys`, `rrd sys <n>`, and `rrd sys.n` all fail with `no register match`.
  Evidence:
  [xsdb_stage2_sys_probe_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe_20260322_172610.log:29)
  [xsdb_stage2_sys_probe2_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe2_20260322_172610.log:29)
- The JTAG register-name database for `arm_dap` does **not** include `IDCODE`,
  `DPACC`, `APACC`, or `ABORT` as named registers through XSDB's
  `sequence irshift -register` path. The only exposed names are
  `init_done_check` and `init_done_check_mask`.
  Evidence:
  [xsdb_dap_instr_probe_20260322_172903.log](/root/chipyard/fpga/logs/xsdb_dap_instr_probe_20260322_172903.log:34)

### Confirmed current most-specific stuck layer

The current stack now looks like this:

- Tool layer: reachable
- XSDB command layer: reachable
- raw JTAG / `arm_dap` layer: reachable
- ARM debug-component / CoreSight / decoded DAP register layer: **not reached**
- ARMv8 exception sysreg / trace layer: **not reached**

## Excluded

- The current local XSDB command surface contains a still-unused direct route to
  `ELR/ESR/VBAR/FAR/SPSR`.
- `gdbremote connect` is sufficient by itself to expose the live `A53` target.
- `xsdbserver start` is an ARM exception or fetch transport by itself.
- `osa` can serve as an exception-state workaround.
- The current named-register support on `arm_dap` is enough to directly step up
  to `DPACC/APACC` using only XSDB register-name abstractions.

## Unknown

- Whether an external DAP/CoreSight-aware client can be placed on top of the
  already confirmed raw `arm_dap` path without changing hardware.
- Whether a vendor-specific or licensed ARM-side debugger can immediately expose
  `ELR/ESR/VBAR/FAR/SPSR` over the same physical chain.
- Whether the real PS-side early boot source can be externally observed faster
  than the ARM exception path can be opened.

## Minimal Execution Log Set

These logs are the minimal set needed to reproduce the current interface
boundary:

- [xsdb_roundA_callability2_20260322_162326.log](/root/chipyard/fpga/logs/xsdb_roundA_callability2_20260322_162326.log)
- [xsdb_roundA_callability3_20260322_162419.log](/root/chipyard/fpga/logs/xsdb_roundA_callability3_20260322_162419.log)
- [xsdb_roundD_jtag_probe2_20260322_162655.log](/root/chipyard/fpga/logs/xsdb_roundD_jtag_probe2_20260322_162655.log)
- [xsdb_roundB_server_session_20260322_162804.log](/root/chipyard/fpga/logs/xsdb_roundB_server_session_20260322_162804.log)
- [xsdb_stage2_sys_probe_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe_20260322_172610.log)
- [xsdb_stage2_sys_probe2_20260322_172610.log](/root/chipyard/fpga/logs/xsdb_stage2_sys_probe2_20260322_172610.log)
- [xsdb_dap_instr_probe_20260322_172903.log](/root/chipyard/fpga/logs/xsdb_dap_instr_probe_20260322_172903.log)
- [xsdb_jtag_prop_probe_20260322_172818.log](/root/chipyard/fpga/logs/xsdb_jtag_prop_probe_20260322_172818.log)

## Direct Decision

Current decision: **D**

`external capability gap still exists, but the boundary is tighter`

More specifically:

- We are no longer blocked at the repo layer.
- We are no longer blocked at the generic XSDB command-discovery layer.
- We are blocked at the transition between raw `arm_dap` access and actual ARM
  debug-component / CoreSight / exception-sysreg visibility.

## Most Useful Next External Requirement

One of the following will directly move the investigation forward:

1. A debugger or client layer that can sit on top of the already reachable
   `arm_dap` and expose CoreSight / DAP register access in a decoded form.
2. A debugger that can directly read ARMv8 exception system registers:
   `ELR/ESR/VBAR/FAR/SPSR`.
3. An ARM-side trace/fetch source that can observe real A53 execution around
   `0x200`.

## One-Line Summary

The boundary is now precise: the existing environment reaches raw `arm_dap`
bits, but not the ARM debug-component layer that would expose exception
registers or trace.
