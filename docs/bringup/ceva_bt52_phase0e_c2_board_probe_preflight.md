# CEVA BT5.2 Phase 0E-C2 - Board Probe Preflight

## One-line status

C2 is the first future board-facing probe-read stage, but it must not be treated as valid unless the Phase 0E bitstream with `dm_sw_irq -> PLIC` wiring has been built and loaded.

## Required preconditions

Before running the C1.5 probe reader on board, all must be true:

1. Phase 0E hardware wiring exists in the loaded bitstream:
   - `dm_sw_irq`
   - wrapper output
   - `CevaDmBlackBox`
   - `IntSourceNode(num = 1)`
   - `ibus.fromSync`
   - PLIC
2. The board has been initialized with the standard PS DDR / PS-PL init flow.
3. J-Link GDB Server is listening on `127.0.0.1:3333`.
4. The C1 `sdboot.bin` / `sdboot.elf` pair is from the compile-passed trap/claim/complete skeleton.
5. The GDB probe reader uses the matching ELF for symbols.
6. The C1 sdboot image has been loaded and allowed to run to the point where it can arm PLIC, trigger CEVA `dm_sw_irq`, and populate the probe globals.
7. CEVA VERSION registers still read:
   - `0x65000004 = 0x0B000500`
   - `0x65000404 = 0x0B000600`
   - `0x65000804 = 0x0B001100`

## Important warning

Running the probe reader on an old Phase 0B, 0C, or 0D bitstream is expected to fail or timeout for IRQ purposes, because those bitstreams do not contain the `dm_sw_irq -> PLIC` path.

That would not prove the C1 software is wrong.

Likewise, attaching the probe reader before the C1 sdboot image has been loaded and allowed to run makes the readout uninterpretable, because the probe globals may still be zero.

## Hard PASS candidates

The first hard PASS should focus on these probe facts:

| Item | Expected |
|---|---|
| probe magic | valid C1 magic |
| handler count | non-zero |
| mcause | machine external interrupt |
| PLIC claim id | CEVA source id |
| CEVA INTSTAT before ack | `INTSTAT1[3] = 1` |
| CEVA INTSTAT after ack | `INTSTAT1[3] = 0` |
| done flag | set |

## Observation-only fields for first board pass

These should be printed but not treated as hard failure in the first run:

- PLIC pending before handler
- PLIC pending after ack
- PLIC pending after complete or at the final halt point
- completion-written mirror probe
- timeout probe

Reason: PLIC pending visibility depends on where the sample is taken relative to claim and complete. For the first board pass, claim ID and CEVA status clear are stronger evidence than any single pending snapshot.

The current C1 skeleton only exports dedicated probe variables for pending-before-claim and pending-after-ack. A later post-handler live PLIC pending read is still useful, but should remain auxiliary evidence in the first pass.

## Next step after preflight

After this runbook is reviewed, proceed to the actual hardware-visible stage:

```text
Phase 0E-D:
  build new Phase 0E bitstream
  load bitstream
  run C1 sdboot
  read C1.5 probes
```