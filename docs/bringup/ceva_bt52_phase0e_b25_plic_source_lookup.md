# CEVA BT5.2 Phase 0E-B2.5 - PLIC Source Lookup Note

## Goal

Derive the PLIC-side information needed for the future `dm_sw_irq` board test.

This note does not run the board and does not prove IRQ behavior. It only records what can be derived from generated artifacts and the saved `make verilog` log.

## Inputs

The lookup below uses only these evidence sources:

- `generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig.dts`
- `generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig.memmap.json`
- `generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig.0xc000000.0.regmap.json`
- `/tmp/phase0e_b1_make_verilog.log`

## Known CEVA-side IRQ registers

| Purpose | Address | Bit |
|---|---:|---:|
| Trigger | `0x65000000` | `RWDMCNTL[27]` |
| Mask | `0x65000018` | `INTCNTL1[3]` |
| Status | `0x6500001c` | `INTSTAT1[3]` |
| Ack | `0x65000020` | `INTACK1[3]` |

## Closed PLIC lookup

### 1. PLIC base is closed

Three independent generated artifacts agree on the same base:

- DTS: `interrupt-controller@c000000 { reg = <0xc000000 0x4000000>; }`
- memmap: `interrupt-controller@c000000` at base `0x0c000000`
- PLIC regmap: `baseAddress : 0xc000000`

Conclusion: `PLIC base = 0x0c000000`.

### 2. CEVA source ID is closed

Two generated sources agree on the CEVA source index:

- saved `make verilog` log: `Interrupt map (2 harts 5 interrupts): [1, 1] => ceva`
- DTS: `ceva-dm@65000000 { interrupt-parent = <&L16>; interrupts = <1>; }`

Conclusion: `CEVA dm_sw_irq PLIC source ID = 1`.

### 3. Source-scoped PLIC registers are closed

From the PLIC regmap:

- `priority_1` is at byte offset `0x4`
- `pending_1` is at byte offset `0x1000`, bit offset `1`

With `PLIC base = 0x0c000000`, this yields:

| Item | Value | Evidence |
|---|---|---|
| Priority register address | `0x0c000004` | `priority_1` byte offset `0x4` |
| Pending register address | `0x0c001000` | `pending_1` byte offset `0x1000` |
| Pending bit | `1` | `pending_1` bit offset `1` |

## Context-scoped PLIC registers

The DTS exposes two PLIC contexts through:

- `interrupts-extended = <&L12 11 &L12 9>`

The regmap exposes two matching target contexts:

- `enables_0`, `threshold_0`, `claim_complete_0`
- `enables_1`, `threshold_1`, `claim_complete_1`

The generated artifacts therefore close the raw addresses below.

### First context / target 0

| Item | Value | Evidence |
|---|---|---|
| Enable register address | `0x0c002000` | `enables_0` byte offset `0x2000` |
| Enable bit | `1` | `enables_0` bit offset `1` |
| Threshold address | `0x0c200000` | `threshold_0` byte offset `0x200000` |
| Claim/complete address | `0x0c200004` | `claim_complete_0` byte offset `0x200000`, bit offset `32` |

### Second context / target 1

| Item | Value | Evidence |
|---|---|---|
| Enable register address | `0x0c002080` | `enables_1` byte offset `0x2080` |
| Enable bit | `1` | `enables_1` bit offset `1` |
| Threshold address | `0x0c201000` | `threshold_1` byte offset `0x201000` |
| Claim/complete address | `0x0c201004` | `claim_complete_1` byte offset `0x201000`, bit offset `32` |

## What B2 uses by default

The Phase 0E-B2 script now fills in these defaults:

| Item | Default |
|---|---|
| `CEVA_PLIC_SOURCE_ID` | `1` |
| `PLIC_BASE` | `0x0c000000` |
| `PLIC_PENDING_ADDR` | `0x0c001000` |
| `PLIC_ENABLE_ADDR` | `0x0c002000` |
| `PLIC_PRIORITY_ADDR` | `0x0c000004` |
| `PLIC_THRESHOLD_ADDR` | `0x0c200000` |
| `PLIC_CLAIM_COMPLETE_ADDR` | `0x0c200004` |

Those defaults intentionally use the first PLIC context for the future baremetal path. The current J-Link one-shot step only reads the pending word and does not touch claim/complete.

## Remaining caution

One item remains deliberately out of the active B2 J-Link read sequence even though its address is known:

- `claim/complete`

Reason: PLIC claim/complete reads are destructive. Reading that register during the pending-only phase would mutate the interrupt state and would invalidate the simpler `INTSTAT1` plus pending-bit observation flow.

## Closure status

For the current generated collateral, the lookup is closed for:

- PLIC base
- CEVA source ID
- pending register address and bit
- priority register address
- both context enable addresses and bits
- both context threshold addresses
- both context claim/complete addresses

No PLIC-side field above remains `TBD` for the current `RocketZCU104Phase0bConfig` collateral.