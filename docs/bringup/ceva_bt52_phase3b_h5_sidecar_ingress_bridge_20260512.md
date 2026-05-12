# CEVA BT5.2 Phase 3B-H5 Sidecar Ingress Bridge

## 1. Goal

H5 adds the first sidecar-side ingress scaffold for the existing Linux host shim EM command mailbox.

This phase consumes command-ready state and records markers only. It does not synthesize HCI events, does not set event-ready, does not claim HCI Reset PASS, and does not enter CEVA vendor runtime.

## 2. Source Changes

| File | Change |
|---|---|
| `sidecar/ceva_bt52_sidecar/bridge_contract.h` | Adds MMIO/EM base constants, ready values, packet type, and mailbox sizes matching the Linux driver layout. |
| `sidecar/ceva_bt52_sidecar/marker.h` | Adds marker values for Reset command observation and command consumption. |
| `sidecar/ceva_bt52_sidecar/main.c` | Polls EM command-ready, extracts HCI opcode, records markers, and clears command-ready. |

## 3. Contract With Linux Host Shim

Current Linux host shim writes commands as:

```text
CEVA MMIO base        = 0x65000000
EM window offset      = 0x00010000
EM command words      = EM[64..71]
EM command-ready word = EM[72]
EM event-ready word   = EM[73]
EM event words        = EM[96..111]
command-ready value   = 0xA5A5A5A5
event-ready value     = 0x5A5A5A5A
```

H5 sidecar behavior:

1. Poll `EM[72]`.
2. If it equals `0xA5A5A5A5`, read `EM[64]`.
3. Decode packet type from byte 0 and opcode from bytes 1..2.
4. Write opcode marker at `CEVA_BT52_MARKER_OFFSET_OPCODE`.
5. If opcode is HCI Reset `0x0C03`, write `CEVA_BT52_MARKER_OFFSET_RX_CMD_0C03`.
6. Write `CEVA_BT52_MARKER_OFFSET_CMD_CONSUMED`.
7. Clear `EM[72]` to `0`.

H5 intentionally does not write `EM[73]` and does not write `EM[96..111]`.

## 4. Why This Is Not Synthetic Controller Success

Earlier Phase 2.5 synthetic response paths could make Linux observe a dummy event. H5 does not do that. It only proves that a sidecar-side consumer can see and consume the host command mailbox.

The expected Linux-side outcome before vendor runtime exists is still timeout or no real event. The H5 evidence is the sidecar marker chain, not Bluetooth stack success.

## 5. Validation

Validation command:

```bash
bash scripts/build_ceva_sidecar.sh
```

Expected result:

- Build succeeds.
- `sidecar.elf`, `sidecar.bin`, `sidecar.map`, and `sidecar.dump` are generated locally only.
- Generated build outputs are cleaned before commit.

## 6. PASS / PARTIAL / BLOCKED

PASS:

- Sidecar command ingress scaffold builds.
- The bridge contract matches the Linux driver's current EM word layout and ready values.
- H5 does not emit synthetic HCI events.

PARTIAL:

- H5 is not hardware-validated in this commit.
- No Linux RX real event is produced yet.

BLOCKED:

- Real command completion remains blocked by vendor runtime integration and H7 approval.

## 7. Next Safe Action

Proceed to H6 event egress boundary as a gated path that can only publish real vendor-produced events. Do not add dummy Command Complete generation.
