# CEVA BT5.2 Phase 0E-C1 - Baremetal Trap/Claim/Complete Skeleton Build PASS

## One-line status

Phase 0E-C1 added the minimum baremetal software skeleton for future CEVA `dm_sw_irq` board validation and passed compile-only verification.

## Scope

This stage did not:

- build a bitstream
- run synthesis
- modify RTL, wrapper, or Scala generator code
- modify Device Tree, Linux drivers, or BlueZ
- run on board
- commit any change

## Source anchors

The C1 implementation is confined to the existing ZCU104 sdboot path:

- `src/main/resources/zcu104/sdboot/head.S`
  - sets `mtvec`
  - adds a direct-mode trap entry
  - saves a minimal register set
  - calls the C trap handler
  - restores registers and returns with `mret`
- `src/main/resources/zcu104/sdboot/baremetal.c`
  - defines the CEVA and PLIC constants for the current generated design
  - defines probe globals for future board-side readback
  - initializes PLIC target0 priority, enable, and threshold
  - triggers CEVA `RWDMCNTL[27]`
  - implements a trap handler that reads claim, samples probe state, writes `INTACK1[3]`, and writes PLIC complete

No other software path was widened for this stage.

## Build outputs

Compile-only validation used the existing ZCU104 sdboot build path and produced:

- `src/main/resources/zcu104/sdboot/build/sdboot.elf`
- `src/main/resources/zcu104/sdboot/build/sdboot.bin`
- `src/main/resources/zcu104/sdboot/build/sdboot.dump`

Build command:

```sh
cd /root/chipyard/fpga/src/main/resources/zcu104/sdboot
make RISCV=/root/chipyard/.oclaw-env/riscv-tools elf bin dump
```

## Compiled symbol proof

`riscv64-unknown-elf-nm` on `sdboot.elf` shows the expected C1 symbols are present in the compiled image:

```text
000000000001001c T phase0e_irq_trap_entry
00000000000101f0 T phase0e_irq_trap_handler
0000000008000030 B phase0e_irq_probe_magic
0000000008000028 B phase0e_irq_probe_mcause
0000000008000020 B phase0e_irq_probe_claim_id
000000000800001c B phase0e_irq_probe_plic_pending_before_claim
0000000008000018 B phase0e_irq_probe_plic_pending_after_ack
0000000008000014 B phase0e_irq_probe_ceva_status_before_ack
0000000008000010 B phase0e_irq_probe_ceva_status_after_ack
000000000800000c B phase0e_irq_probe_completion_written
0000000008000008 B phase0e_irq_probe_handler_count
0000000008000004 B phase0e_irq_probe_done
0000000008000000 B phase0e_irq_probe_timeout
```

`riscv64-unknown-elf-objdump -d` shows the expected trap instructions in the compiled image:

```text
10010: csrw mtvec,t0
10068: jal  101f0 <phase0e_irq_trap_handler>
100b8: mret
101f0: csrr a5,mcause
```
This is sufficient to close the compile-only question for C1: the trap entry and probe-capturing handler are not just present in source, they are present in the compiled ELF.

## Closed software constants for the current generated design

The C1 skeleton is built around the already-closed Phase 0E values:

- CEVA base: `0x65000000`
- `RWDMCNTL`: `0x65000000`, bit 27
- `INTCNTL1`: `0x65000018`, bit 3
- `INTSTAT1`: `0x6500001c`, bit 3
- `INTACK1`: `0x65000020`, bit 3
- PLIC base: `0x0c000000`
- CEVA PLIC source id: `1`
- PLIC pending: `0x0c001000`, bit 1
- PLIC enable target0: `0x0c002000`, bit 1
- PLIC priority source1: `0x0c000004`
- PLIC threshold target0: `0x0c200000`
- PLIC claim/complete target0: `0x0c200004`

## Probe map for future board readback

The baremetal image now exports the following reviewable probe set:

- `phase0e_irq_probe_magic`
- `phase0e_irq_probe_mcause`
- `phase0e_irq_probe_claim_id`
- `phase0e_irq_probe_plic_pending_before_claim`
- `phase0e_irq_probe_plic_pending_after_ack`
- `phase0e_irq_probe_ceva_status_before_ack`
- `phase0e_irq_probe_ceva_status_after_ack`
- `phase0e_irq_probe_completion_written`
- `phase0e_irq_probe_handler_count`
- `phase0e_irq_probe_done`
- `phase0e_irq_probe_timeout`

These probes are intended to answer the minimum C1 board question in one stop:

1. Did machine external interrupt fire?
2. Did PLIC claim source id 1?
3. Was CEVA status asserted before `INTACK1[3]`?
4. Was CEVA status cleared after `INTACK1[3]`?
5. Was the handler entered and allowed to finish?

## Conservative first-pass interpretation

For C1.6 and the first future board pass, the hard PASS or FAIL decision should only use these fields:

- `phase0e_irq_probe_magic`
- `phase0e_irq_probe_handler_count`
- `phase0e_irq_probe_mcause`
- `phase0e_irq_probe_claim_id`
- `phase0e_irq_probe_ceva_status_before_ack`
- `phase0e_irq_probe_ceva_status_after_ack`
- `phase0e_irq_probe_done`

The following fields should be printed and reviewed, but not treated as first-pass hard failure conditions:

- `phase0e_irq_probe_plic_pending_before_claim`
- `phase0e_irq_probe_plic_pending_after_ack`
- `phase0e_irq_probe_completion_written`
- `phase0e_irq_probe_timeout`
- any live PLIC pending read taken after the halt point

Reason: PLIC pending visibility depends on where the sample is taken relative to claim and complete. In the first board pass, claim ID and CEVA status clear are stronger evidence than any single pending snapshot.

## Draft follow-up readback tooling

Phase 0E-C1.6 keeps the draft-only readback scripts for later board use:

- `scripts/ceva_phase0e_c15_baremetal_probe_read.sh`
- `scripts/ceva_phase0e_c15_baremetal_probe_read.gdb`

These drafts are intentionally read-mostly:

- they use the compiled `sdboot.elf` for symbol resolution
- they halt the core and read the exported probe globals
- they read live CEVA and PLIC state that has no destructive read side effect
- they deliberately skip live reads from PLIC claim/complete because that register is destructive
- they now treat PLIC pending snapshots as auxiliary evidence, not first-pass hard PASS or FAIL conditions

The board-facing preflight checklist for the next phase is captured separately in:

- `docs/bringup/ceva_bt52_phase0e_c2_board_probe_preflight.md`

## Notes on repo state

The worktree currently contains unrelated generated artifacts under `target/` and several already-untracked Phase 0E docs and scripts. C1 closure only relies on the ZCU104 sdboot source files above and the directly-generated `build/` outputs listed in this report.