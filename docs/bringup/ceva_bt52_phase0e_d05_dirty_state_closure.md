# CEVA BT5.2 Phase 0E-D0.5 - Dirty State Closure

## Goal

Classify repository dirty state before allowing Phase 0E-D bitstream build.

D0 found that the Phase 0E technical prerequisites are mostly ready, but the outer repo contains existing `linux` and `driver` matched dirty paths. This note decides whether those paths are real blockers for the Phase 0E bitstream build.

## Build gate rule

Phase 0E-D bitstream build can proceed only if:

1. Phase 0E expected source changes are present.
2. Only `dm_sw_irq` is connected.
3. Other CEVA IRQ outputs remain unconnected.
4. No Device Tree, Linux driver, or BlueZ change is required for the bitstream build itself.
5. Existing unrelated dirty files are explicitly classified and not silently ignored.

## Phase 0E expected hardware-visible files

Outer repo:

```text
generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala
generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v
```

Observed status:

- `CevaBt52Phase0b.scala` exists and is currently untracked in the outer repo.
- `rw_dm_top_phase0b_real_wrapper.v` is modified in place and exports `dm_sw_irq`.

These are expected Phase 0E hardware-visible changes, not accidental noise.

## Phase 0E expected verification-only files

Inner repo files expected for the current staged closure:

```text
docs/bringup/ceva_bt52_phase0e_irq_plan.md
docs/bringup/ceva_bt52_phase0e_b1_repo_closure.md
docs/bringup/ceva_bt52_phase0e_b2_jlink_irq_validation_draft.md
docs/bringup/ceva_bt52_phase0e_b25_plic_source_lookup.md
docs/bringup/ceva_bt52_phase0e_c1_baremetal_skeleton_pass.md
docs/bringup/ceva_bt52_phase0e_c2_board_probe_preflight.md
docs/bringup/ceva_bt52_phase0e_c2_board_runbook.md
scripts/ceva_phase0e_b2_dm_sw_irq_jlink.sh
scripts/ceva_phase0e_b2_dm_sw_irq_jlink.gdb
scripts/ceva_phase0e_c15_baremetal_probe_read.sh
scripts/ceva_phase0e_c15_baremetal_probe_read.gdb
```

Observed status:

- all of the above files exist
- all of them are untracked in the inner repo, which is consistent with the current Phase 0E documentation and draft-tooling workflow

These files are expected verification collateral and do not change the hardware netlist.

## Additional expected local software state

The inner repo also has local modifications in:

```text
src/main/resources/zcu104/sdboot/head.S
src/main/resources/zcu104/sdboot/baremetal.c
```

Those files are part of the already-compiled C1 trap and probe skeleton and explain the matching `sdboot.elf`, `sdboot.bin`, and `sdboot.dump` outputs under `src/main/resources/zcu104/sdboot/build/`.

They are expected software-side Phase 0E state, not Linux or driver drift.

## Dirty state buckets

### Bucket A: expected Phase 0E files

This bucket contains the actual Phase 0E work:

- outer hardware-visible CEVA integration files
- inner Phase 0E reports and draft scripts
- inner C1 sdboot source changes and compiled artifacts

This bucket is allowed and required.

### Bucket B: expected generated build noise

This bucket includes inner repo generated outputs under `target/scala-2.13` and related Zinc or assembly streams.

These files are noisy but expected after local Scala and sdboot compilation. They are not the reason D0 returned a strict NO.

### Bucket C: existing unrelated outer-repo noise

The outer repo is broadly dirty across many non-Phase 0E paths, including docs, tooling, submodules, and software collateral. This is repository noise that predates the narrow Phase 0E build gate question.

It should not be treated as implicit approval, but it also does not automatically prove that the Phase 0E FPGA bitstream input path is contaminated.

### Bucket D: `linux` or `driver` matched paths

The exact matches found in D0.5 split into two groups.

Outer repo matches:

- conda lock files whose names include `linux`
- Firechip `driver.mk` files
- tutorial marshal configs whose names include `linux`
- `fpga/linux-bringup/`
- multiple `fpga/scripts/linux_*` or kernel-debug GDB helpers

Inner repo matches:

- generated `target/scala-2.13` class files whose config names include `Linux`

These matches are real dirty paths, but they are only name matches until proven to be direct Phase 0E-D bitstream inputs.

## Why the `linux` or `driver` matches are not direct Phase 0E-D build blockers

The current FPGA bitstream build entry path is driven by the FPGA Makefile and the WSL wrapper script for Vivado. The relevant flow is:

1. `fpga/Makefile` selects `SUB_PROJECT=zcu104` and the explicit `CONFIG`.
2. The bitstream target builds a source manifest and then launches Vivado on the generated build directory for that config.
3. `fpga/scripts/build_bitstream_wsl.sh` selects `BUILD_DIR` from `CONFIG_NAME` and converts that config's file manifest into the Windows-visible source list.
4. The CEVA-specific handling in `build_bitstream_wsl.sh` only appends the generated CEVA RTL order list and the CEVA wrapper for the selected config's build directory.

In this input path inspection, no direct dependency was found from the Phase 0E bitstream build entrypoints to:

- `fpga/linux-bringup/`
- `fpga/scripts/linux_*`
- `BlueZ`
- Linux driver source trees
- Device Tree or DTB assets as required bitstream inputs
- Firechip `driver.mk` files as required zcu104 FPGA bitstream inputs

The broad grep over `Makefile`, `scripts`, and `generators` did find many Linux bringup and DTB references, but they were in debug, load, observe, and software-bringup helper scripts rather than in the direct Phase 0E bitstream build entrypoints.

## Single-IRQ cleanliness check

The current CEVA IRQ hookup remains scoped to the single intended source:

- `dm_sw_irq` is exported by the wrapper
- `CevaDmBlackBox` exposes only `dm_sw_irq` as the interrupt output of interest
- `CevaDm` creates `IntSourceNode(IntSourcePortSimple(num = 1, resources = device.int))`
- `intOut(0) := ceva.io.dm_sw_irq`
- `baseSubsystem.ibus.fromSync := ceva.intNode`

Other CEVA IRQ outputs remain unconnected in the wrapper, including:

- `bt_error_irq`
- `ble_error_irq`
- `dm_fifo_irq`

This means the dirty-state exemption does not hide an accidental multi-IRQ widening.

## D0.5 decision

D0 returned a strict NO because it matched `linux` and `driver` in the outer repo dirty list.

After D0.5 classification, those matches are downgraded from hard blockers to explicitly recorded unrelated dirty state for the purpose of the narrow Phase 0E-D bitstream gate.

They are not silent exceptions. They are documented exceptions.

## Build gate exemption

Phase 0E-D bitstream build is allowed to proceed under a dirty-state exemption if and only if all of the following remain true:

1. the build is explicitly pinned to the Phase 0E config, not a Linux bringup config
2. the hardware-visible Phase 0E source of truth remains confined to:
   - `generators/chipyard/src/main/scala/ceva/CevaBt52Phase0b.scala`
   - `generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v`
3. the single live IRQ source remains `dm_sw_irq`
4. the current inner Phase 0E docs and scripts stay verification-only collateral
5. no one reinterprets the unrelated outer dirty files as part of the Phase 0E proof set

## Final gate result

For the narrow Phase 0E-D bitstream-build question, the current dirty `linux` and `driver` matched files are not direct blockers.

Final D0.5 result:

```text
READY_FOR_PHASE0E_D_BITSTREAM_BUILD=YES_WITH_DIRTY_STATE_EXEMPTION
```

That result does not mean the outer repo is clean. It means the currently observed dirty `linux` and `driver` matches are classified as unrelated to the direct Phase 0E FPGA bitstream build input path.

## Required caution for the next phase

When Phase 0E-D actually starts, keep the build invocation explicit and narrow. The intended build must stay pinned to the Phase 0E config rather than any Linux bringup flow.

Examples of acceptable intent:

```text
make SUB_PROJECT=zcu104 CONFIG=RocketZCU104Phase0bConfig bitstream
```

or the equivalent explicit wrapper flow with:

```text
CONFIG_NAME=RocketZCU104Phase0bConfig
```

Anything that silently falls back to a Linux bringup config invalidates this exemption and must be re-evaluated.