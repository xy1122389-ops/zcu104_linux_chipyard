# CEVA BT5.2 Phase 3B-H9 No-Synthetic-Event Guard

## 1. Goal

H9 adds a static guard that prevents the sidecar work from drifting back into a synthetic Bluetooth responder.

This phase does not add CEVA vendor runtime, does not call `rwip_init()`, does not emit HCI Reset Command Complete, and does not claim real HCI PASS.

## 2. Guard Script

File:

- `scripts/check_ceva_sidecar_no_synthetic_event.sh`

The guard enforces:

- `main.c` must not call `ceva_bt52_sidecar_publish_vendor_event()`.
- `main.c` must not write `CEVA_BT52_BRIDGE_EVENT_READY_OFFSET` or `CEVA_BT52_BRIDGE_EVENT_READY_VALUE`.
- `main.c` must not write egress-ready / send-to-host markers directly.
- `sidecar_event_bridge.c` must not encode opcode-specific Reset/RLV synthetic responses.
- Event-ready writes are isolated to `sidecar_event_bridge.c`.

## 3. Why This Exists

The project already proved synthetic Phase 2.5 HCI smoke. The next real milestone requires a vendor/runtime consumer, not another fake event source.

H5 may consume commands. H6 may publish an event only when a future approved vendor adapter provides the event. H9 guards that separation.

## 4. Validation

Validation command:

```bash
bash scripts/check_ceva_sidecar_no_synthetic_event.sh
```

Expected result:

```text
H9_NO_SYNTHETIC_EVENT_GUARD=PASS
```

## 5. PASS / PARTIAL / BLOCKED

PASS:

- Static no-synthetic-event guard passes.
- Event-ready publication remains gated behind the egress helper.
- The sidecar main loop cannot directly publish host-visible events.

PARTIAL:

- This is a static guard only; it is not a hardware validation.

BLOCKED:

- Real Reset/RLV event production remains blocked by H7 vendor runtime approval and integration.

## 6. Next Safe Action

Keep using this guard in later H10/H11 attempts before claiming any HCI event result. Any real PASS must show vendor-runtime provenance, not just event-ready toggling.
