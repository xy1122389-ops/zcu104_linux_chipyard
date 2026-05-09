# CEVA BT5.2 Phase 0E-B2 - Minimal J-Link/GDB IRQ Validation Draft

## Goal

This note defines the draft-only board validation procedure for the single `dm_sw_irq` path introduced in Phase 0E-B1. It pairs with the two script artifacts below:

- `scripts/ceva_phase0e_b2_dm_sw_irq_jlink.sh`
- `scripts/ceva_phase0e_b2_dm_sw_irq_jlink.gdb`

This phase remains limited to J-Link/GDB observation. It does not run Linux, does not add a baremetal trap handler yet, and does not widen the hardware scope beyond one CEVA IRQ.

## Scope

Included in this draft:

- single IRQ only: `dm_sw_irq`
- one-shot trigger plus ack clear
- J-Link direct access through `127.0.0.1:3333`
- generated-collateral-backed PLIC lookup for the current `RocketZCU104Phase0bConfig` build

Explicitly out of scope:

- bitstream build or synthesis in this step
- board execution in this step
- Device Tree changes
- Linux driver or BlueZ work
- extra CEVA IRQ wiring
- repeated re-trigger loop by default

## Fixed CEVA register facts

| Item | Address | Bit | Meaning |
|---|---|---|---|
| trigger | `0x65000000` | `27` | `RWDMCNTL.swint_req` |
| mask | `0x65000018` | `3` | `INTCNTL1.swintmsk` |
| status | `0x6500001c` | `3` | `INTSTAT1.swintstat` |
| ack | `0x65000020` | `3` | `INTACK1.swintack` |

The shell wrapper therefore uses the following fixed CEVA-side write values:

- trigger value: `0x08000000`
- mask value: `0x00000008`
- ack value: `0x00000008`

## PLIC-side values derived from generated collateral

Phase 0E-B2.5 closes the PLIC lookup from generated DTS, memmap, PLIC regmap, and the saved `make verilog` log.

| Item | Value | Evidence summary |
|---|---|---|
| PLIC base | `0x0c000000` | DTS `interrupt-controller@c000000`, memmap `interrupt-controller@c000000`, PLIC regmap base `0xc000000` |
| CEVA PLIC source ID | `1` | make log `Interrupt map (2 harts 5 interrupts): [1, 1] => ceva`, DTS `ceva-dm@65000000 { interrupts = <1>; }` |
| Pending register | `0x0c001000`, bit `1` | PLIC regmap `pending_1` at byte offset `0x1000`, bit offset `1` |
| Priority register | `0x0c000004` | PLIC regmap `priority_1` at byte offset `0x4` |
| Enable register | `0x0c002000`, bit `1` | PLIC regmap `enables_0` at byte offset `0x2000`, bit offset `1` |
| Threshold register | `0x0c200000` | PLIC regmap `threshold_0` at byte offset `0x200000` |
| Claim/complete register | `0x0c200004` | PLIC regmap `claim_complete_0` at byte offset `0x200000`, bit offset `32` |

The full derivation and the alternate second-context addresses are recorded in `docs/bringup/ceva_bt52_phase0e_b25_plic_source_lookup.md`.

## Planned one-shot flow

1. Ensure the J-Link GDB Server is reachable on `127.0.0.1:3333`.
2. Halt the Rocket core.
3. Write `INTCNTL1[3] = 1` to open the `dm_sw_irq` mask.
4. Write `INTACK1[3] = 1` to clear any stale local status.
5. Read baseline `INTSTAT1` and the proven PLIC pending word at `0x0c001000`.
6. Write `RWDMCNTL[27] = 1`.
7. Read `INTSTAT1` again and confirm the local status bit sets.
8. Read the PLIC pending word again and confirm bit `1` sets.
9. Write `INTACK1[3] = 1`.
10. Read `INTSTAT1` again and confirm the local status bit clears.
11. Read the PLIC pending word again and confirm bit `1` clears.
12. Resume and detach.

## Expected acceptance criteria

Minimum local acceptance:

- `STATUS_BASELINE & 0x8 == 0`
- `STATUS_AFTER_TRIGGER & 0x8 != 0`
- `STATUS_AFTER_ACK & 0x8 == 0`

PLIC-side acceptance for the current generated collateral:

- `PLIC_PENDING_BASELINE & 0x2 == 0`
- `PLIC_PENDING_AFTER_TRIGGER & 0x2 != 0`
- `PLIC_PENDING_AFTER_ACK & 0x2 == 0`

The script also prints the proven priority, enable, and threshold addresses, but the current J-Link phase does not use them as pass/fail gates.
```bash
cd /root/chipyard/fpga
bash scripts/ceva_phase0e_b2_dm_sw_irq_jlink.sh
```
Override example if later collateral changes the source ID, context, or PLIC layout:
```bash
cd /root/chipyard/fpga
CEVA_PLIC_SOURCE_ID=1 \
PLIC_BASE=0x0c000000 \
PLIC_PENDING_ADDR=0x0c001000 \
PLIC_ENABLE_ADDR=0x0c002000 \
PLIC_PRIORITY_ADDR=0x0c000004 \
PLIC_THRESHOLD_ADDR=0x0c200000 \
PLIC_CLAIM_COMPLETE_ADDR=0x0c200004 \
  bash scripts/ceva_phase0e_b2_dm_sw_irq_jlink.sh
```
## Failure split

If the draft is eventually run and fails, triage it in this order:

1. local `INTSTAT1` never sets:
   likely single-IRQ hardware path mismatch, stale bitstream, or mask not opened
2. local `INTSTAT1` sets but PLIC pending bit 1 never sets:
   likely wrong hardware image, stale collateral, or CEVA-to-PLIC path not really present in that bitstream
3. local `INTSTAT1` does not clear after ack:
   likely stale state, wrong ack write, or the observation window is not actually reading the intended register

The current B2 J-Link step deliberately does not read the claim/complete register even though its address is known, because reads on that register are destructive.

## Handoff to the next phase

With the current generated collateral, the next extension should be narrowly scoped:

1. rerun the same one-shot draft unchanged
2. only after that passes, add a separate baremetal claim/complete step using the first PLIC context addresses
3. if later collateral changes, regenerate the B2.5 lookup note before changing defaults

This keeps Phase 0E-B2 aligned with the current constraint set: verify the single `dm_sw_irq` path first, and avoid widening scope before the basic PLIC visibility is proven.