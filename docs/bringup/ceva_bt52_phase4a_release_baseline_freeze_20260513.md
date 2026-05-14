# CEVA BT5.2 Phase4-A Release Baseline Freeze

## 1. Status

Phase3 completion is now closed by gate, and the Phase4-A entry baseline is frozen at the current repository state.

```text
P4A_BASELINE_FREEZE=PASS
PHASE3_COMPLETION_GATE=PASS
P4B_RUNTIME_LAUNCH_CONTRACT=PASS
P4C_MEMORY_OWNERSHIP_CONTRACT=PASS
P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS
P4A_BASELINE_CFG=RocketZCU104Phase0bConfig
P4A_HEAD=2f6db364477e0fc91a7533d47d2ae25b5d1873de
P4A_BRANCH=wip/phase3_completion_plan_20260513_005944
```

The freeze entrypoint is:

```bash
bash scripts/collect_ceva_phase4a_baseline_freeze.sh /tmp/ceva_phase4a_baseline_freeze.txt
```

That script now records the current commit, Phase3 gate result, bitstream provenance, payload provenance, the stable CEVA runtime launch manifest, the evidence set, and the recovery chain with hashes.
It also records the current Phase4 entry contract state through the main Phase4-B and Phase4-C checkers, so outer status no longer needs to inspect C3/C4/C5 sub-checkers directly.

## 2. Frozen Core Artifacts

```text
20e045604c6b04f35c2e4c11243d122a8209ee3a7f4786af2d74f9441173c05e  generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/ZCU104FPGATestHarness.bit
83ee82e83d0bd5462eba38f54122ce26c579a1b058960c6c9dea5279b954e77b  linux-bringup/payload/fw_payload.bin
15f9df9c0f721da88dfc61307d6374215fa0e5f0f20ee5d2a37268b994ef9e41  linux-bringup/payload/ceva_runtime_launch_manifest.env
ca8489a60c3b5f9cd10cd728426d77fde9f8c6fc582a5dd1f1925305d1e55a03  linux-bringup/dtb/chipyard-zcu104-fedora.dtb
723b0e67522150b03830c38dbb162333f8299c4a4ffb8cd5ebe659c697474722  src/main/resources/zcu104/sdboot/build/sdboot.bin
```

For Phase4-A, bitstream freeze is defined as the exact programming input selected by `scripts/program_phase0b_bit.sh` plus its hash, not as a new committed binary policy.

## 3. Frozen Evidence Set

The freeze manifest hashes the full Phase3 evidence directory, including:

```text
00_vendor_approval_closed.md
01_vendor_runtime_link_pass.md
02_rwip_init_and_driver_init_pass.md
03_real_ingress_consumed_pass.md
04_real_reset_event_pass.md
05_real_rlv_event_pass.md
06_synthetic_off_repeated_regression_pass.md
07_bluez_controlled_bringup_pass.md
README.md
EVIDENCE_TEMPLATES.md
```

The Phase3 hard gate recorded in the freeze manifest is:

```text
PHASE3_COMPLETION_GATE=PASS
```

## 4. Frozen Recovery Chain

The current recovery chain is frozen as the following scripts and runbooks:

```text
scripts/program_phase0b_bit.sh
scripts/start_jlink_server.sh
scripts/jlink_guard.sh
run_phase2_ceva_bt_linux.sh
docs/bringup/ceva_bt52_phase25_runbook_20260512.md
docs/bringup/phase3b_recovery_reports/phase3b_h3_recovery_20260513_001254.md
```

The freeze entrypoint also records the current Phase4 entry checkers:

```text
scripts/check_ceva_phase4b_runtime_launch_contract.sh
scripts/check_ceva_phase4c_memory_ownership_contract.sh
```

This is the baseline recovery path for the current debug-owned bringup flow. It remains valid until P4-B replaces GDB restore ownership with a production boot owner.

## 5. Current Git State At Freeze

The freeze records, but does not overwrite, the existing dirty files:

```text
linux-bringup/dtb/chipyard-zcu104-fedora.dtb
linux-bringup/dtb/chipyard-zcu104-fedora.dts
scripts/run_ps_ddr_init.tcl
```

It also records the uncommitted Phase3 evidence closure and new Phase4 entry scripts. This is intentional: P4-A freezes the current baseline and provenance first; commit policy can follow after review.

## 6. Result

P4-A is now established as a repeatable, script-backed baseline freeze. The next work items are:

1. P4-B: replace the ad hoc launch path with an explicit runtime launch contract and then move loader ownership away from GDB.
2. P4-C: replace static non-overlap with actual reserved-memory ownership plus rollback, with outer status flowing through `scripts/check_ceva_phase4c_memory_ownership_contract.sh`.