# ARM Early Boot Hard Evidence Report

## Scope

This report consolidates the hard evidence collected so far for the current
`A53#0 @ 0x200` stall, and explicitly separates confirmed facts from excluded
branches and still-missing evidence.

## Confirmed Facts

- `A53#0` can be recovered back to visible debug state through the existing
  recovery chain. This is no longer the main blocker.
- In a stable halted state, `A53#0` sits at `PC=0x200` with
  `CPSR=0x000003cd`.
  Evidence:
  [runtime_a53_halt_cause_probe_20260322_142226.log](/root/chipyard/fpga/logs/runtime_a53_halt_cause_probe_20260322_142226.log:36)
- In that same halted state, `RECOVERY_USED=NO`, so the core was already at
  `0x200`; this was not an artifact of the last recovery action.
  Evidence:
  [runtime_a53_halt_cause_probe_20260322_142226.log](/root/chipyard/fpga/logs/runtime_a53_halt_cause_probe_20260322_142226.log:55)
- The target-side stop reason in the stable state is
  `Hardware Breakpoint, EL3(S)/A64`.
  Evidence:
  [runtime_a53_halt_cause_probe_20260322_142226.log](/root/chipyard/fpga/logs/runtime_a53_halt_cause_probe_20260322_142226.log:57)
- Address breakpoint ladder results show that only `0x200` is a true hit.
  `0x1F0`, `0x1F8`, `0x1FC`, `0x204`, `0x208`, `0x20C`, `0x210`, and `0x220`
  all fail to hit and stop back at `PC=0x200`.
  Evidence:
  [runtime_a53_bp_ladder_20260322_150520.log](/root/chipyard/fpga/logs/runtime_a53_bp_ladder_20260322_150520.log:251)
- Plain stepping and instruction-stepping both fail to advance architected
  state. `stp`, `stpi`, `nxti`, and short `con/stop` all leave
  `PC/CPSR/R0/SP` unchanged at `0x200`.
  Evidence:
  [runtime_a53_instr_step_probe_20260322_151426.log](/root/chipyard/fpga/logs/runtime_a53_instr_step_probe_20260322_151426.log:62)
- XSDB `dis` can disassemble the `A53` target side at the current address, and
  `0x200` shows up as `.word 0x008a3783`, not a recognized A64 instruction.
  Evidence:
  [runtime_a53_fetch_probe_20260322_150902.log](/root/chipyard/fpga/logs/runtime_a53_fetch_probe_20260322_150902.log:92)
  [runtime_a53_instr_step_probe_20260322_151426.log](/root/chipyard/fpga/logs/runtime_a53_instr_step_probe_20260322_151426.log:56)
- The low address window `0x0000..0x1FFF` is not random. It behaves like a
  broad alias/remap window matching `fw_payload.bin@(addr+0x2000)`.
  Evidence:
  [runtime_payload_offset_evidence_20260322_144649.log](/root/chipyard/fpga/logs/runtime_payload_offset_evidence_20260322_144649.log:2249)
- The alias/remap window is not global. It switches to `self-match` at
  `0x2000`, with the transition interval between `0x1FC0` and `0x2000`.
  Evidence:
  [runtime_payload_offset_evidence_20260322_144649.log](/root/chipyard/fpga/logs/runtime_payload_offset_evidence_20260322_144649.log:2251)
- `0x1000/0x1004` are indeed MMIO and create a hole in the low alias window.
  The only partial `+0x2000` match in the full scan is `0x1000`.
  Evidence:
  [runtime_payload_offset_evidence_20260322_144649.log](/root/chipyard/fpga/logs/runtime_payload_offset_evidence_20260322_144649.log:2246)
- The low window `0x1C0..0x240` matches the payload file window
  `fw_payload.bin@0x21C0..0x2240` word-for-word (`32/32`).
  Evidence:
  [runtime_0200_instruction_evidence_20260322_144213.log](/root/chipyard/fpga/logs/runtime_0200_instruction_evidence_20260322_144213.log:85)
- The corresponding payload-side RISC-V instructions at `0x800021fc..0x80002220`
  are now known, but they are evidence about the alias window contents, not
  direct proof of A53 ARM-side fetch.
  Evidence:
  [runtime_0200_instruction_evidence_20260322_144213.log](/root/chipyard/fpga/logs/runtime_0200_instruction_evidence_20260322_144213.log:215)
- A sentinel was successfully inserted into the Linux handoff bootrom source
  and propagated into both the rebuilt `sdboot-linux.bin` and the regenerated
  `TLROM.sv`.
  Evidence:
  [linux_handoff.c](/root/chipyard/fpga/src/main/resources/zcu104/sdboot-linux/linux_handoff.c:10)
  [TLROM.sv](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/gen-collateral/TLROM.sv:935)
- Despite that, board reads at `rom@0x10320..0x1035C` do not change between
  pre-sentinel and sentinel bitstreams, and repeated reads are identical.
  Evidence:
  [runtime_bootrom_addr_probe_A_pre_sentinel_20260322_160532.log](/root/chipyard/fpga/logs/runtime_bootrom_addr_probe_A_pre_sentinel_20260322_160532.log:46)
  [runtime_bootrom_addr_probe_B_sentinel_20260322_160742.log](/root/chipyard/fpga/logs/runtime_bootrom_addr_probe_B_sentinel_20260322_160742.log:46)
  [runtime_bootrom_addr_probe_B_sentinel_repeat_20260322_160842.log](/root/chipyard/fpga/logs/runtime_bootrom_addr_probe_B_sentinel_repeat_20260322_160842.log:46)
- Therefore, the repo-controlled `TLROM/rom@0x10000` path is not the board's
  true effective early boot ROM path for the currently observed `A53@0x200`
  behavior.

## Excluded Branches

- Repo-controlled `TLROM/rom@0x10000` is the true board early boot source.
  Excluded by the sentinel A/B experiment.
- `payload/bootaddr` is the true early boot source.
  Excluded because it explains alias window contents but not the board ROM
  invariance.
- UART emptiness is the current blocker.
  Excluded long ago; it is downstream of the current stall.
- Regular stepping or instruction stepping can advance the core past `0x200`.
  Excluded by `stp`, `stpi`, `nxti`, and breakpoint ladder results.
- XSDB's already-explored high-level register path can directly provide
  `ELR/ESR/VBAR`.
  Excluded by `rrd`/`rrd -defs`/`sysreg` probing so far.

## Most Likely Source Ranking

1. PS/ARM-side fixed early boot, exception, or debug vector path.
2. Board-resident ROM or stub source outside the current repo-controlled
   `TLROM` path.
3. PS-side PMC/PMU or other fixed handoff path not exposed in the current repo.
4. Repo `TLROM/rom@0x10000` path.
5. Repo payload/bootaddr path.

## Why The Ranking Looks This Way

- The sentinel A/B result rules out rank 4 as the active source.
- The alias window evidence explains data mirroring, but not the board ROM
  invariance, so rank 5 is insufficient as a root source.
- The remaining strongest explanations are therefore PS-side or board-side
  sources outside the repo-controlled ROM image.

## Current Minimal External Need

- ARM-side exception system register visibility:
  `ELR_ELx`, `ESR_ELx`, `VBAR_ELx`, `FAR_ELx`, `SPSR_ELx`
- Or equivalent ARM-side trace/fetch visibility
- Or an external way to observe or replace the board's real PS-side early boot
  stub / ROM source

## Bottom Line

The current repo-controlled bootrom and bitstream are no longer the main
uncertainty. The unresolved root cause now lives behind a deeper ARM-side
exception/trace boundary or a board-side early boot source boundary.
