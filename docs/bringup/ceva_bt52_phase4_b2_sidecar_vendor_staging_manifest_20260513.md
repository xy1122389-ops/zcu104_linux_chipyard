# CEVA BT5.2 Phase4-B2 Sidecar / Vendor Staging Manifest Contract

## 1. Goal

Phase4-B2 extends the existing runtime launch manifest so the future boot owner can see sidecar staging, marker-page placement, vendor-runtime staging, proof-image staging, and launch-owner metadata through a stable metadata contract.

PASS in the current contract means the metadata is present, validated, consumable by OpenSBI-owned reserved staging, and aligned with the P4-C no-map reserved-memory envelope.

## 2. Non-Goals

- This phase does not remove the GDB payload bootstrap fallback.
- This phase does not make OpenSBI auto-start the sidecar or vendor runtime before the release policy allows it.
- This phase does not re-enable OpenSBI root-domain carveout.
- This phase does not prove BlueZ scan, pair, connect, RF, or production controller behavior.
- This phase does not modify vendor source, vendor blob, generated RTL, bitstreams, or payload binaries.

## 3. Current Ownership Boundary

- Current launch owner is `OPENSBI`.
- Target owner is `OPENSBI`.
- Payload bootstrap remains `GDB` as `DEBUG_FALLBACK_ONLY`.
- Staging consumer is `OPENSBI_RESERVED_STAGING`.
- `CEVA_RUNTIME_STAGING_ACTIVE=1` marks the reserved staging contract active without claiming sidecar auto-start.

## 4. Why P4-C Owns The Reserved Envelope

P4-C now owns the reserved envelope through Linux `no-map` reserved memory plus OpenSBI validate/marker ownership. P4-B2 staging metadata must therefore use the same `0x8FBE0000..0x8FEFFFFF` window family instead of a private address copy.

## 5. Added Manifest Fields

| Field | Value | Meaning |
|---|---|---|
| `CEVA_RUNTIME_LAUNCH_OWNER_CURRENT` | `OPENSBI` | Current launch authority is the OpenSBI-owned runtime contract. |
| `CEVA_RUNTIME_LAUNCH_OWNER_TARGET` | `OPENSBI` | Production owner target. |
| `CEVA_RUNTIME_STAGING_OWNER` | `OPENSBI` | Current staging path owner. |
| `CEVA_RUNTIME_STAGING_CONSUMER` | `OPENSBI_RESERVED_STAGING` | OpenSBI/build chain consumes the reserved staging contract. |
| `CEVA_RUNTIME_STAGING_ACTIVE` | `1` | Reserved staging contract is active. |
| `CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR` | `0x8FBF0000` | Sidecar staging window base. |
| `CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE` | `0x00010000` | Sidecar staging window size, aligned to the frozen H4 64 KiB window. |
| `CEVA_RUNTIME_SIDECAR_ENTRY_ADDR` | `0x8FBF0000` | Sidecar entry point within the sidecar staging window. |
| `CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR` | `0x8FBE0000` | Marker page base. |
| `CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE` | `0x00001000` | Marker page size. |
| `CEVA_RUNTIME_SIDECAR_MARKER_WINDOW_MODE` | `INDEPENDENT` | Marker page is outside the sidecar image window and intentionally kept separate. |
| `CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR` | `0x8FC00000` | Reserved vendor-runtime staging base. |
| `CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE` | `0x00200000` | Reserved vendor-runtime staging size. |
| `CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR` | `0x8FE00000` | Reserved proof-image staging base. |
| `CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE` | `0x00100000` | Reserved proof-image staging size. |

The sidecar addresses stay anchored to the shared P4-C memory contract. The `0x8FBE0000` envelope was selected after board proof rejected the earlier high-address candidates for this target.

## 6. Address Window Table

| Window | Start | End | Size | Reason |
|---|---:|---:|---:|---|
| Sidecar marker page | `0x8FBE0000` | `0x8FBE0FFF` | 4 KiB | OpenSBI boot-owner marker page. |
| Sidecar image | `0x8FBF0000` | `0x8FBFFFFF` | 64 KiB | Sidecar staging window. |
| Vendor runtime image | `0x8FC00000` | `0x8FDFFFFF` | 2 MiB | Vendor runtime staging window. |
| Proof image | `0x8FE00000` | `0x8FEFFFFF` | 1 MiB | Proof image staging window. |

These windows are intentionally above the documented OpenSBI, Linux image, future payload/initramfs, DTB, and front-chain regions in [linux-bringup/ADDRESS_PLAN.md](linux-bringup/ADDRESS_PLAN.md).

## 7. Checker Rules

The Phase4-B checker validates:

1. The manifest exists.
2. All P4-B2 fields exist.
3. Address and size fields use `0x`-prefixed hex format.
4. The sidecar entry lies within the sidecar window.
5. The marker page is either inside the sidecar window or explicitly marked as an `INDEPENDENT` marker window.
6. Marker, sidecar, vendor, and proof windows do not overlap each other.
7. Marker, sidecar, vendor, and proof windows do not overlap documented payload, DTB, OpenSBI, Linux, or legacy stage regions.
8. `CEVA_RUNTIME_LAUNCH_OWNER_CURRENT` remains `OPENSBI`.
9. `CEVA_RUNTIME_STAGING_ACTIVE` remains `1`.
10. The checker reports owner-transfer/runtime-start contract PASS while the sidecar start policy remains explicit.

## 8. PASS / FAIL / DEFERRED Semantics

- `P4B_SIDECAR_VENDOR_STAGING_METADATA=PASS` means the metadata contract is present and statically validated.
- `P4B_LAUNCH_OWNER_TRANSFER=PASS` means the launch contract names OpenSBI as current and target owner, with GDB retained only as debug bootstrap fallback.
- `P4B_OPENSBI_RUNTIME_START=PASS` means the runtime-start contract is present and checked; it does not override `CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY=DEFERRED_UNTIL_OWNER_TRANSFER`.

This phase must not be described as a production launch pass, a runtime-start pass, or a full Bluetooth functional pass.

## 9. Next Suggested Step

The next safe step is P4-D vendor build reproducibility, with P4-B staging and P4-C reserved-memory ownership kept green through their single checkers.