# CEVA BT5.2 Phase 0E-B1.6 - Repo Closure Note

## Goal

This note only closes the repository state for the minimal single-IRQ hookup landed in Phase 0E-B1/B1.5. It does not add new hardware scope and does not reopen the already-closed RTL forensics.

Out of scope for this step:

- no bitstream build
- no synthesis
- no Device Tree change
- no Linux driver work
- no BlueZ work
- no extra CEVA IRQs beyond dm_sw_irq
- no commit

## Repo baseline at closure time

| Repo | Branch | Note |
|---|---|---|
| outer `/root/chipyard` | `main` | real generator/wrapper ownership |
| inner `/root/chipyard/fpga` | `local/phase0b-s1-real-rw-dm-top` | bring-up docs and FPGA workflow |

## Files in the Phase 0E-B1 closure set

| Repo | Path | Tracking state | Working-tree state | Role |
|---|---|---|---|---|
| outer | `generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v` | tracked | modified | exports the single CEVA IRQ upward |
| outer | `generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala` | untracked | new | adds the BlackBox IRQ port, `IntSourceNode(num = 1)`, and `ibus.fromSync` hookup |
| inner | `docs/bringup/ceva_bt52_phase0e_irq_plan.md` | untracked | new | carries the A2/A3/B1/B1.5 evidence and validation narrative |

The closure set above is intentionally small. The functional hardware delta remains confined to two outer-repo source files, while the detailed bring-up analysis remains in the inner repo.

## Static closure facts

### 1. Wrapper scope remains single-IRQ only

The outer wrapper exports only `dm_sw_irq` into the Chipyard-facing boundary. Other raw CEVA IRQ outputs remain disconnected in the vendor-top instance.

This preserves the Phase 0E constraint that the first bring-up path must keep exactly one CEVA interrupt connected.

### 2. Scala integration remains single-source only

The outer CEVA generator currently implements the minimal interrupt shape:

- `dm_sw_irq` on the BlackBox IO
- `IntSourceNode(IntSourcePortSimple(num = 1, resources = device.int))`
- `intOut(0) := ceva.io.dm_sw_irq`
- `baseSubsystem.ibus.fromSync := ceva.intNode`

This means the integration remains a one-source insertion into the Rocket interrupt fabric, with no added DT, Linux, or software-side IRQ plumbing in this phase.

### 3. B1.5 evidence is already sufficient and should be reused

Phase 0E-B1.5 already produced the clean generation evidence needed for this closure:

- `/tmp/phase0e_b1_make_verilog.log`
- `generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/...`

The previously checked evidence established all three points below:

1. clean `make SUB_PROJECT=zcu104 CONFIG=RocketZCU104Phase0bConfig verilog` succeeded once `firtool` was placed on `PATH`
2. generated collateral showed the CEVA interrupt path in the interrupt map
3. generated DTS collateral showed `ceva-dm@65000000` with `interrupts = <1>`

Because this evidence already exists, B1.6 does not need another heavy build or a broader repo sweep.

## Ownership conclusion

The repository boundary is now clear:

1. the real hardware hookup belongs to the outer repo
2. the active analysis report belongs to the inner repo
3. Phase 0E should continue to treat `dm_sw_irq` as the only connected CEVA IRQ until board-level validation proves the path end to end

## Next-step handoff

After this closure step, the next allowed work item is a draft-only B2 validation package:

- a minimal J-Link/GDB script draft for `dm_sw_irq`
- a matching bring-up note describing prerequisites, placeholders, and expected observations

That B2 draft should stay script-and-doc only. It should not run on board in this phase and should not widen scope beyond the single IRQ path already validated in B1/B1.5.