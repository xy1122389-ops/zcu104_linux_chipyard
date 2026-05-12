# CEVA BT5.2 Phase 3B-B Selftest-off Observation Mode

## Purpose

This change adds a runtime switch for observing the real CEVA EM and IRQ HCI path without deleting the stable Phase 2.5 selftest-on replay path.

## Runtime behavior

Default behavior remains Phase 2.5-compatible selftest-on replay.

Without any extra kernel cmdline token, init still loads ceva_bt52.ko with:

```text
phase25_selftest=1 phase25_selftest_delay_ms=0
```

This preserves the existing replay control group.

## Selftest-off observation switch

If the kernel cmdline contains:

```text
ceva_phase25_selftest=0
```

then init loads ceva_bt52.ko with:

```text
phase25_selftest=0
```

In that mode, the driver no longer gets forced into the Phase 2.5 synthetic responder path by init.

## What stays unchanged

- ceva_bt52.c is unchanged.
- RTL is unchanged.
- No bitstream rebuild is involved.
- The selftest-on replay control path remains available by default.
- Existing capture scripts remain the observation mechanism for EM command, EM event, and IRQ state.

## Files changed

- [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init)
- [ceva_bt52_phase3b_selftest_off_observation_note_20260512.md](ceva_bt52_phase3b_selftest_off_observation_note_20260512.md)

## Expected use

- Control group: boot normally, no special cmdline token.
- Observation group: boot with kernel cmdline token `ceva_phase25_selftest=0`.

The observation group is intended to answer whether real CEVA firmware or hardware returns any EM event through the existing driver EM and IRQ path, using the existing capture flow rather than synthetic replay.