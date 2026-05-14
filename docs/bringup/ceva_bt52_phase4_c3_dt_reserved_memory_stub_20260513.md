# CEVA BT5.2 Phase4-C3 DT Reserved-Memory Stub

## 1. Goal

Phase4-C3 introduces the first protected-file implementation patch by adding a DT reserved-memory stub that matches the published Phase4-B3/P4-C contract.

This phase is intentionally limited to DTS source. The final C6 state uses the matching DTB, OpenSBI validate/marker logic, and Linux no-map ownership rather than an OpenSBI root-domain carveout.

## 2. Implemented Stub

The DTS now contains a reserved-memory envelope:

| Property | Value |
|---|---|
| Node | `ceva_runtime_reserved@8fbe0000` |
| Compat | `shared-dma-pool` |
| Range | `0x8FBE0000..0x8FEFFFFF` |
| Size | `0x00320000` |
| `no-map` | present |
| `reusable` | absent |

This is an envelope stub, not four separate nodes. The envelope keeps the first protected-file patch simple and preserves the current window layout published by P4-B2, P4-B3, P4-C1, and P4-C2.

## 3. Why The Envelope Starts At `0x8FBE0000`

The stub starts at the marker page and ends at the proof window so the reserved-memory declaration covers:

1. marker page,
2. sidecar image window,
3. vendor image window,
4. proof image window.

The small gap between the marker page and sidecar image is reserved as part of the envelope to keep one Linux no-map owner for the full CEVA runtime staging range.

## 4. Checker

```bash
bash scripts/check_ceva_phase4c3_dt_reserved_memory_stub.sh
```

Expected result in the current phase:

```text
P4C_DT_RESERVED_MEMORY_STUB=PASS
P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS
```

## 5. Non-Goals

- No DTB binary regeneration.
- No OpenSBI root-domain carveout implementation.
- No P4-D/E/F hardening claim.
- No runtime auto-start claim.

## 6. Next Step

The matching OpenSBI validate/marker path and C6 Linux proof now keep this DTS envelope unchanged.