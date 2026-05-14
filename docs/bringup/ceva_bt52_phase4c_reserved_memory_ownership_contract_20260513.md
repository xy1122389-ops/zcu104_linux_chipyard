# CEVA BT5.2 Phase4-C Reserved-Memory Ownership Contract

## 1. Status

Phase4-C is now closed at C6: the shared memory contract, DT reserved-memory node, OpenSBI validation/boot-owner marker, Linux no-map consumption, hci0 registration, driver selftest, and userspace HCI reset/RLV smoke all pass through the single outer checker.

```text
P4C_MEMORY_OWNERSHIP_CONTRACT=PASS
P4C_BOOT_OWNER_MEMORY_ALIGNMENT=PASS
P4C_DT_RESERVED_MEMORY_STUB=PASS
P4C_OPENSBI_RESERVED_MEMORY_CONSUMPTION=PASS
P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS
P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS
P4C_LINUX_RESERVED_MEMORY_E2E=PASS
P4C_RESERVED_MEMORY_TRANSFER=PASS
CURRENT_MEMORY_MODE=reserved-memory+opensbi-boot-owner
TARGET_MEMORY_MODE=reserved-memory+opensbi-boot-owner
ROLLBACK_MODE=return-to-debug-bootstrap-fallback
```

This is now a reserved-memory implementation pass for Phase4-C. It does not claim P4-D vendor build reproducibility, P4-E driver lifecycle hardening, or P4-F interrupt/timer/power hardening.

## 2. Contract Files

The current ownership contract is now centralized in:

```text
scripts/ceva_reserved_memory_contract.sh
scripts/check_ceva_sidecar_memory_contract.sh
scripts/check_ceva_phase4c_memory_ownership_contract.sh
scripts/check_ceva_phase4c2_reservation_transfer_readiness.sh
scripts/check_ceva_phase4c3_dt_reserved_memory_stub.sh
scripts/check_ceva_phase4c4_opensbi_reserved_memory_consumption.sh
scripts/check_ceva_phase4c5_opensbi_root_domain_carveout.sh
scripts/check_ceva_phase4c5_runtime_root_domain_proof.sh
scripts/check_ceva_phase4b3_boot_owner_readiness.sh
linux-bringup/ADDRESS_PLAN.md
docs/bringup/ceva_bt52_phase3b_h4_sidecar_reserved_memory_packaging_20260512.md
docs/bringup/ceva_bt52_phase4_c5a_runtime_root_domain_proof_20260513.md
```

The important change is that the H4 static checker no longer carries a private copy of the address ranges. Phase4 and H4 now consume the same contract.

## 3. Current Contracted Windows

```text
Legacy stage/P3BD: 0x8F000000..0x8F0000D8
Sidecar marker:    0x8FBE0000..0x8FBE0FFF
Sidecar image:     0x8FBF0000..0x8FBFFFFF
Vendor image:      0x8FC00000..0x8FDFFFFF
Proof image:       0x8FE00000..0x8FEFFFFF
Reserved DT node:  0x8FBE0000..0x8FEFFFFF
```

The validated non-overlap regions remain:

```text
OpenSBI:                0x80000000..0x80020DE8
Linux image:            0x80200000..0x830D4808
Future payload/initrd:  0x83000000..0x86FFFFFF
DTB:                    0x84000000..0x8401FFFF
Front-chain:            0x88000000..0x883FFFFF
Legacy stage/P3BD:      0x8F000000..0x8F0000D8
```

## 4. What PASS Means Right Now

Current PASS means only this:

- the sidecar marker/image windows are frozen in one shared contract;
- the vendor/proof staging windows now use the same shared contract as P4-B2/P4-B3;
- H4 static overlap validation still passes;
- the boot-owner readiness checker agrees with the memory ownership checker on the same window set;
- the DT reserved-memory node exists in DTS source using the published contract envelope;
- OpenSBI generic platform consumes the reserved-memory metadata, validates it against the published contract, and claims the boot-owner marker;
- OpenSBI root-domain carveout is intentionally disabled so Linux does not receive overlapping `mmode_resv*` nodes for the same range;
- Linux consumes `ceva_runtime_reserved@8fbe0000` as a `no-map` reserved-memory region without overlap warnings;
- the board-level C6 proof reaches Linux, registers hci0, passes CEVA driver Reset/RLV selftest evidence, and passes userspace HCI Reset/RLV smoke evidence;
- the address plan and H4 packaging doc agree with the contract;
- the target ownership and rollback modes are explicit.

It does not mean P4-D/E/F are complete; those remain the next reproducibility and hardening phases.

## 5. Target Ownership Direction

P4-C should converge toward one of these accepted end states:

1. DT reserved-memory node consumed by Linux and respected by the boot chain.
2. OpenSBI validation plus boot-owner marker claim before Linux boots.
3. Equivalent earlier bootloader reservation with the same published contract.

The selected path is Linux reserved-memory ownership plus OpenSBI validation/boot-owner marker. A root-domain carveout was rejected because it generated overlapping `mmode_resv*` reserved-memory nodes on this single-PMP board.

The current contract also freezes the first reservation-transfer metadata inputs without editing protected files:

```text
transfer_policy=OPENSBI_BOOT_OWNER_ACTIVE
transfer_target=DT_RESERVED_MEMORY_PLUS_OPENSBI_VALIDATE_MARKER
boot_owner_target=OPENSBI
dtb_node=ceva_runtime_reserved
dtb_compat=shared-dma-pool
reusable=0
no_map=1
transfer_active=1
opensbi_carveout_policy=LINUX_NO_MAP_OWNS_RESERVED_RANGE
opensbi_carveout_active=0
```

These values back the DTS reserved-memory node, OpenSBI validation path, boot-owner marker claim, and Linux end-to-end runtime proof used by `scripts/check_ceva_phase4c_memory_ownership_contract.sh`.

## 6. Rollback Rule

If a future reserved-memory patch regresses boot or overlaps a protected Linux region, rollback must be immediate:

```text
remove reservation patch
return to debug-bootstrap fallback
keep marker/image addresses unchanged
revalidate with scripts/check_ceva_sidecar_memory_contract.sh
```

## 7. Stop Rules

Do not claim P4-C completion if any item is still true:

- `scripts/check_ceva_phase4c_memory_ownership_contract.sh` is not PASS;
- DTB/DTS reservation is only documented but not implemented;
- OpenSBI boot-owner marker ownership is absent;
- Linux does not consume `ceva_runtime_reserved@8fbe0000` as no-map reserved memory;
- any `mmode_resv*` node overlaps `ceva_runtime_reserved`;
- P4-B3 boot-owner readiness and P4-C memory windows describe different staging ranges;
- marker/image windows are moved without updating the shared contract and checker;
- reservation changes are mixed into unrelated dirty DTB/DTS edits.