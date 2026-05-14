# CEVA BT5.2 Phase4-C1 Boot Owner / Memory Alignment

## 1. Goal

Phase4-C1 aligns the Phase4-B3 boot-owner readiness model with the Phase4-C shared memory ownership contract.

This phase originally aligned the Phase4-B3 boot-owner model with the Phase4-C shared memory ownership contract. The final C6 state keeps that alignment and uses Linux no-map reserved memory plus OpenSBI validate/marker ownership.

## 2. What Changed

- `scripts/ceva_reserved_memory_contract.sh` now publishes vendor and proof staging windows alongside marker and sidecar windows.
- `scripts/check_ceva_phase4c_memory_ownership_contract.sh` now depends on `scripts/check_ceva_phase4b3_boot_owner_readiness.sh`.
- The Phase4-C checker now reports that boot-owner readiness and memory ownership are aligned on one shared window set.

## 3. Shared Windows

| Window | Start | End |
|---|---:|---:|
| Marker | `0x8FBE0000` | `0x8FBE0FFF` |
| Sidecar | `0x8FBF0000` | `0x8FBFFFFF` |
| Vendor | `0x8FC00000` | `0x8FDFFFFF` |
| Proof | `0x8FE00000` | `0x8FEFFFFF` |

## 4. Checker Result Shape

Expected result for the current phase is:

```text
P4C_MEMORY_OWNERSHIP_CONTRACT=PASS
P4C_BOOT_OWNER_MEMORY_ALIGNMENT=PASS
P4C_RESERVED_MEMORY_TRANSFER=PASS
```

That means the memory contract and boot-owner contract agree on addresses, and the final reserved-memory transfer proof is available through the P4-C single checker.

## 5. Non-Goals

- No new DTB/DTS changes beyond the existing `ceva_runtime_reserved@8fbe0000` node.
- No OpenSBI root-domain carveout re-enable.
- No runtime start.
- No P4-D/E/F hardening claim.

## 6. Next Step

The next safe step is P4-D vendor build reproducibility while keeping these aligned windows unchanged.