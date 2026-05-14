# CEVA BT5.2 Phase4-B3 Boot Owner Readiness

## 1. Goal

Phase4-B3 records the boot-owner side of the Phase4-B contract with OpenSBI as the current and target launch owner, while retaining GDB only as a debug bootstrap fallback.

This phase publishes a stable boot-owner action model so OpenSBI can consume the manifest and derive the required pre-Linux actions in a repeatable way.

## 2. Non-Goals

- This phase does not start the sidecar.
- This phase does not load vendor runtime from OpenSBI.
- This phase does not remove the GDB debug bootstrap fallback.
- This phase does not modify protected DTB/DTS/TCL files.
- This phase does not claim BlueZ scan, pair, connect, or RF validation.

## 3. Boot Owner Metadata Fields

The launch manifest now includes a small boot-owner readiness subset:

| Field | Value | Meaning |
|---|---|---|
| `CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION` | `1` | Version of the boot-owner readiness contract. |
| `CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY` | `CLEAR_BEFORE_LOAD` | Future boot owner must clear the marker page before observing or loading sidecar assets. |
| `CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER` | `MARKER,SIDECAR,VENDOR,PROOF` | Declared observation/load order for the current metadata contract. |
| `CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY` | `CONTINUE_WITHOUT_RUNTIME_START` | Linux boot must continue without claiming sidecar runtime start. |
| `CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY` | `DEFERRED_UNTIL_OWNER_TRANSFER` | Sidecar execution release is blocked until a later owner-transfer phase. |
| `CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER` | `SIDECAR_INGRESS_READY` | Future owner-transfer phase must use this marker as the first acceptable pre-Linux readiness point. |

## 4. Action Plan Semantics

The new readiness checker translates the manifest into this action model:

1. Clear the marker page.
2. Observe the sidecar staging window.
3. Observe the vendor staging window.
4. Observe the proof staging window.
5. Do not release sidecar execution yet.
6. Continue Linux boot without runtime start.

That means OpenSBI can already consume the metadata. Sidecar auto-start remains intentionally controlled by `CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY`.

## 5. Why This Phase Exists

P4-B2 made sidecar/vendor/proof staging metadata visible. P4-B3 turns that metadata into a concrete OpenSBI-owned action plan without making an uncontrolled sidecar auto-start claim.

This avoids two common failure modes:

- calling metadata visibility a real owner-transfer pass;
- starting sidecar runtime before reserved-memory ownership is accepted in P4-C.

## 6. Checker

The Phase4-B3 checker is:

```bash
bash scripts/check_ceva_phase4b3_boot_owner_readiness.sh
```

Expected result in the current phase:

```text
P4B_BOOT_OWNER_METADATA_CONSUMPTION=PASS
P4B_BOOT_OWNER_ACTION_PLAN=PASS
P4B_BOOT_OWNER_RUNTIME_RELEASE=PASS
```

## 7. Exit Criteria For The Next Phase

P4-B3 is complete when the manifest and checker consistently describe a boot-owner-readable action plan while preserving these facts:

- current owner is `OPENSBI`;
- staging consumer is `OPENSBI_RESERVED_STAGING`;
- staging is active (`1`);
- sidecar runtime release is still deferred.

The next implementation phase is P4-D vendor build reproducibility, while this action model remains aligned with P4-C reserved-memory ownership.