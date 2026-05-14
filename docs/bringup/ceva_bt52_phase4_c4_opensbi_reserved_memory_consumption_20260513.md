# CEVA BT5.2 Phase4-C4 OpenSBI Reserved-Memory Consumption

## 1. Goal

Phase4-C4 adds the first OpenSBI-side implementation that consumes the reserved-memory stub published by Phase4-C3.

The implementation is intentionally limited: OpenSBI generic platform now parses the reserved-memory node from FDT and validates its node name, compat, reg range, and no-map policy against build-time contract values.

## 2. What This Phase Does

- passes the reserved-memory contract values from `rebuild_payload.sh` into OpenSBI generic platform build flags;
- teaches OpenSBI generic platform to parse `/reserved-memory/ceva_runtime_reserved@8fbe0000`;
- validates `compatible`, `reg`, and `no-map` against the published contract;
- claims the boot-owner marker after validation and leaves Linux no-map as the owner of the reserved range.

## 3. What This Phase Does Not Do

- It does not start sidecar runtime.
- It does not start sidecar runtime automatically.
- It does not re-enable OpenSBI root-domain carveout.
- It does not claim P4-D/E/F hardening.

## 4. Checker

```bash
bash scripts/check_ceva_phase4c4_opensbi_reserved_memory_consumption.sh
```

Expected result in the current phase:

```text
P4C_OPENSBI_RESERVED_MEMORY_CONSUMPTION=PASS
P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS
P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS
```

## 5. Why This Matters

Before this phase, OpenSBI was only a planned reservation participant. After this phase, the OpenSBI build and generic platform code consume the published reserved-memory contract and reject a mismatched FDT node.

That is the first real boot-owner implementation step on the reservation path.

## 6. Next Step

The selected next step was the boot-owner marker action plus C6 Linux proof, while keeping the same reserved-memory node and range.