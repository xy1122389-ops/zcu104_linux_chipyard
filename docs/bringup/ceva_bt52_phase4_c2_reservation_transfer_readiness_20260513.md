# CEVA BT5.2 Phase4-C2 Reservation Transfer Readiness

## 1. Goal

Phase4-C2 freezes the metadata and checker shape for the final reservation-transfer path used by the C6 proof.

The purpose is to make the protected-file implementation deterministic: the DT reserved-memory node name, compat, no-map policy, non-reusable policy, boot-owner target, and transfer-active gate are all published through the shared contract.

## 2. Current Readiness Contract

The shared memory contract now includes these reservation-transfer inputs:

| Field | Value | Meaning |
|---|---|---|
| `CEVA_RESERVED_MEMORY_TRANSFER_POLICY` | `OPENSBI_BOOT_OWNER_ACTIVE` | OpenSBI participates by validating the DT node and claiming the marker. |
| `CEVA_RESERVED_MEMORY_TRANSFER_TARGET` | `DT_RESERVED_MEMORY_PLUS_OPENSBI_VALIDATE_MARKER` | Final implementation route. |
| `CEVA_RESERVED_MEMORY_BOOT_OWNER_TARGET` | `OPENSBI` | Reservation is tied to the OpenSBI boot-owner marker contract. |
| `CEVA_RESERVED_MEMORY_DTB_NODE` | `ceva_runtime_reserved` | Planned reserved-memory node name. |
| `CEVA_RESERVED_MEMORY_DTB_COMPAT` | `shared-dma-pool` | Planned DT compat string. |
| `CEVA_RESERVED_MEMORY_REUSABLE` | `0` | Linux must not treat the window as reusable. |
| `CEVA_RESERVED_MEMORY_NO_MAP` | `1` | Linux must not map the window into the normal direct map. |
| `CEVA_RESERVED_MEMORY_TRANSFER_ACTIVE` | `1` | Real transfer is active and covered by C6 proof. |

## 3. Window Assumptions

The readiness checker assumes the current window order remains:

1. marker
2. sidecar
3. vendor
4. proof

and that the sidecar/vendor/proof windows remain contiguous. This keeps the first DT carveout patch simple and avoids introducing multiple moving ranges in one protected-file change.

## 4. Checker

```bash
bash scripts/check_ceva_phase4c2_reservation_transfer_readiness.sh
```

Expected result in the current phase:

```text
P4C_RESERVATION_TRANSFER_READINESS=PASS
P4C_RESERVED_MEMORY_DTB_STUB=PASS
P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS
```

## 5. Non-Goals

- No new DTS/DTB edit beyond the accepted reserved-memory node.
- No OpenSBI root-domain carveout re-enable.
- No P4-D/E/F hardening claim.
- No runtime start.

## 6. Next Step

The next safe step is P4-D vendor build reproducibility. The accepted implementation is:

1. a DT reserved-memory node using the frozen metadata;
2. an OpenSBI validate/marker path that consumes the same window set.

Future work must keep all window addresses unchanged unless the single P4-C checker and rollback notes are updated in the same change.