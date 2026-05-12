# CEVA BT5.2 Phase 3B-H8 Vendor Adapter Boundary

## 1. Goal

H8 defines the local sidecar-to-vendor adapter boundary that future CEVA runtime integration must satisfy after the H7 approval gate is closed.

This phase does not copy CEVA vendor source, does not include CEVA vendor headers, does not link CEVA objects, does not produce a runtime image, and does not claim `rwip_init()` or HCI Reset PASS.

## 2. Added Local Boundary

File:

- `sidecar/ceva_bt52_sidecar/vendor_adapter_boundary.h`

The header defines only local project-owned types:

- `ceva_bt52_vendor_gate_status`
- `ceva_bt52_vendor_result`
- `ceva_bt52_hci_cmd_view`
- `ceva_bt52_hci_event_view`
- `ceva_bt52_vendor_host_ops`
- `ceva_bt52_vendor_runtime_ops`

No CEVA source or CEVA header content is imported into this repository.

## 3. Runtime Boundary Shape

Future local adapter code must expose a `ceva_bt52_vendor_runtime_ops` instance with:

| Callback | Purpose |
|---|---|
| `probe()` | Verify host callbacks and gate status before vendor runtime use. |
| `init()` | Enter vendor runtime initialization after approval and platform glue are available. |
| `poll()` | Advance runtime work without assuming interrupts are already wired. |
| `handle_hci_cmd()` | Consume one HCI command view and optionally produce one HCI event view. |

The sidecar provides `ceva_bt52_vendor_host_ops` callbacks for marker writes, EM reads/writes, SW IRQ raise, and timebase reads.

## 4. H7 Gate Preservation

The H7 gate is still closed for vendor link/copy. H8 only prepares the ABI boundary. Future code must not call vendor functions directly from common sidecar code unless the adapter implementation is explicitly isolated and the H7 approval gate is closed.

## 5. Symbol Inventory Mapping

The H7 read-only audit found these candidate vendor anchors:

| Future local adapter responsibility | Candidate vendor anchor |
|---|---|
| Runtime init sequencing | `rwip_init(uint32_t error)` in `src/modules/rwip/src/rwip.c:721` |
| Driver init sequencing | `rwip_driver_init(uint8_t init_type)` in `src/modules/rwip/src/rwip_driver.c:683` |
| H4 transport setup | `h4tl_init(uint8_t tl_itf, ...)` in `src/modules/h4tl/src/h4tl.c:1126` |
| HCI command ingress | `hci_cmd_received(uint16_t opcode, ...)` in `src/ip/hci/src/hci_tl.c:1574` |
| Platform EIF glue | `rwip_eif_get(uint8_t idx)` in `src/plf/refip/src/arch/main/arch_main.c:481` |

These are inventory anchors only. They are not included or linked by H8.

## 6. Validation

Validation command:

```bash
printf '#include "sidecar/ceva_bt52_sidecar/vendor_adapter_boundary.h"\nint main(void) { return 0; }\n' \
  | riscv64-unknown-elf-gcc -I. -ffreestanding -nostdlib -nostartfiles \
      -mcmodel=medany -march=rv64imac -mabi=lp64 -x c -fsyntax-only -
```

Expected result: syntax-only compile succeeds.

## 7. PASS / PARTIAL / BLOCKED

PASS:

- Local adapter boundary is defined.
- Header is independent of CEVA vendor headers.
- RV64 freestanding syntax-only validation passes.

PARTIAL:

- No adapter implementation exists yet.
- No vendor runtime is linked.

BLOCKED:

- Real vendor runtime integration remains blocked by H7 approval.

## 8. Next Safe Action

Proceed with local bridge preparation or symbol-inventory documentation only. Do not link CEVA runtime until the H7 approval gate is explicitly closed.
