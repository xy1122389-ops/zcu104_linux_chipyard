# CEVA BT5.2 Phase 0E-C - Baremetal Claim/Complete Draft

## Goal

Define the smallest future baremetal step that proves the CPU can take the CEVA `dm_sw_irq`, claim it from the PLIC, clear the CEVA local source, and complete the interrupt back to the PLIC.

This document is a draft only. It does not run on board and does not modify the current payload in this step.

## Boundary

Included here:

- reuse of the current `RocketZCU104Phase0bConfig` hardware image
- reuse of the current `zcu104/sdboot` baremetal payload path
- first PLIC context / target 0 draft for M-mode external interrupt handling
- exact CEVA and PLIC register sequence for one-shot claim/complete

Out of scope here:

- no RTL change
- no wrapper change
- no Scala generator change
- no bitstream build
- no board run
- no Linux / DT / BlueZ work
- no repeated re-trigger loop yet

## Proven prerequisites already in hand

### 1. CEVA local trigger/ack path is already closed

From the earlier Phase 0E-A and Phase 0E-B work:

- trigger: `0x65000000`, `RWDMCNTL[27]`
- mask: `0x65000018`, `INTCNTL1[3]`
- status: `0x6500001c`, `INTSTAT1[3]`
- ack: `0x65000020`, `INTACK1[3]`

Current IRQ semantics remain level-triggered, and `swint_req` re-arm was already closed in RTL.

### 2. PLIC-side lookup is already closed

From Phase 0E-B2.5:

- PLIC base: `0x0c000000`
- CEVA source id: `1`
- pending word: `0x0c001000`, bit `1`
- priority register: `0x0c000004`
- enable register for target 0: `0x0c002000`, bit `1`
- threshold register for target 0: `0x0c200000`
- claim/complete register for target 0: `0x0c200004`

See `ceva_bt52_phase0e_b25_plic_source_lookup.md` for the full derivation and the alternate target-1 addresses.

### 3. CPU-side software visibility is already closed

Phase 0B-S3 already proved that the current baremetal payload path can read CEVA MMIO from the Rocket CPU.

That removes MMIO visibility as a blocker for Phase 0E-C.

### 4. The current zcu104 sdboot path has PLIC headers but no trap entry yet

The existing zcu104 sdboot sources already provide:

- `src/main/resources/zcu104/sdboot/include/platform.h`
- `src/main/resources/zcu104/sdboot/include/devices/plic.h`
- `src/main/resources/zcu104/sdboot/baremetal.c`

But the current startup path in `src/main/resources/zcu104/sdboot/head.S` is still only:

1. set `sp`
2. call `main`
3. spin forever after `main`

There is no trap vector or interrupt entry in the current payload. That is the first concrete software delta needed for Phase 0E-C.

## Draft implementation surface

The smallest future implementation should stay confined to the current zcu104 sdboot payload path.

### Files that would need changes in the future implementation step

| File | Draft role |
|---|---|
| `src/main/resources/zcu104/sdboot/head.S` | add a minimal trap entry or jump stub and point `mtvec` at it |
| `src/main/resources/zcu104/sdboot/baremetal.c` | add probe globals, PLIC init, CEVA trigger path, handler bookkeeping, and final spin loop |

### Files that do not need changes for the first software draft

- no CEVA RTL files
- no wrapper files
- no Scala generator files
- no Makefile change is strictly required for the first draft

## Draft interrupt context choice

This draft uses the first PLIC context, namely target 0.

Reasoning:

1. the DTS exposes `interrupts-extended = <&cpu_intc 11 &cpu_intc 9>` on the PLIC node
2. `11` is machine external interrupt and `9` is supervisor external interrupt
3. the generated PLIC regmap orders the first context as `threshold_0` / `claim_complete_0`
4. the current baremetal payload runs in M-mode

So the first candidate context for Phase 0E-C is:

- enable: `0x0c002000`, bit `1`
- threshold: `0x0c200000`
- claim/complete: `0x0c200004`

If later runtime evidence disproves this context mapping, Phase 0E-C should swap to the target-1 addresses already recorded in the B2.5 lookup note.

## Draft register plan

### CEVA-side writes and reads

| Purpose | Address | Value / bit |
|---|---|---|
| Open local mask | `0x65000018` | set bit `3` |
| Clear stale local IRQ | `0x65000020` | write bit `3` |
| Trigger local source | `0x65000000` | write bit `27` |
| Observe local status | `0x6500001c` | read bit `3` |
| Ack in handler | `0x65000020` | write bit `3` |

### PLIC-side writes and reads for target 0

| Purpose | Address | Value / bit |
|---|---|---|
| Priority source 1 | `0x0c000004` | write non-zero, e.g. `1` |
| Pending word | `0x0c001000` | observe bit `1` |
| Enable word | `0x0c002000` | set bit `1` |
| Threshold | `0x0c200000` | write `0` |
| Claim/complete | `0x0c200004` | read claim id, later write id back |

## Draft software sequence

### 1. Main path before enabling interrupts

The future payload should:

1. keep the current UART/GPIO bring-up path intact
2. zero the Phase 0E-C probe globals
3. program `priority_1 = 1`
4. set enable bit `1` in the target-0 enable word
5. set threshold to `0`
6. open CEVA local mask with `INTCNTL1[3] = 1`
7. clear stale CEVA local status with `INTACK1[3] = 1`
8. install `mtvec` to a minimal trap entry
9. set `mie.MEIE = 1`
10. set `mstatus.MIE = 1`
11. write `RWDMCNTL[27] = 1`
12. wait in a bounded loop for the handler to mark completion, then fall into a stable spin point for GDB observation

### 2. Trap entry

Because the current sdboot startup path has no trap handling, the future implementation needs a minimal trap entry.

The smallest acceptable form is:

1. save a compact register set sufficient for a leaf handler
2. call a C helper such as `phase0e_irq_handler()`
3. restore state
4. execute `mret`

The first draft should avoid vectored mode and should keep the trap path single-purpose.

### 3. Handler body

The C helper should perform the following ordered sequence:

1. read `mcause`
2. verify `mcause == MCAUSE_INT | 11`
3. snapshot the PLIC pending word before claim
4. read claim/complete and save the claimed id
5. verify claim id equals `1`
6. read CEVA `INTSTAT1` and save the pre-ack value
7. write CEVA `INTACK1[3] = 1`
8. read CEVA `INTSTAT1` again and save the post-ack value
9. read the PLIC pending word again and save the post-ack value
10. write the claimed id back to `0x0c200004`
11. increment a handler-count probe and mark the overall test as done

The key ordering point is that claim must happen inside the handler, not from GDB, because claim reads are destructive and belong to the software path being verified.

## Draft probe set

The first implementation should expose a small set of globals so GDB can inspect the result after the handler returns to a stable loop.

Recommended probe set:

```c
volatile uint32_t phase0e_irq_probe_magic;
volatile uint64_t phase0e_irq_probe_mcause;
volatile uint32_t phase0e_irq_probe_claim_id;
volatile uint32_t phase0e_irq_probe_plic_pending_before_claim;
volatile uint32_t phase0e_irq_probe_plic_pending_after_ack;
volatile uint32_t phase0e_irq_probe_ceva_status_before_ack;
volatile uint32_t phase0e_irq_probe_ceva_status_after_ack;
volatile uint32_t phase0e_irq_probe_handler_count;
volatile uint32_t phase0e_irq_probe_done;
```

This probe set is intentionally smaller than a full trap dump. The goal is only to prove the end-to-end claim/ack/complete path.

## Acceptance criteria

The future Phase 0E-C board step should only pass if all conditions below hold in one run:

1. `phase0e_irq_probe_mcause == MCAUSE_INT | 11`
2. `phase0e_irq_probe_claim_id == 1`
3. `phase0e_irq_probe_handler_count == 1`
4. `phase0e_irq_probe_ceva_status_before_ack & 0x8 != 0`
5. `phase0e_irq_probe_ceva_status_after_ack & 0x8 == 0`
6. `phase0e_irq_probe_plic_pending_before_claim & 0x2 != 0`
7. `phase0e_irq_probe_plic_pending_after_ack & 0x2 == 0`
8. `phase0e_irq_probe_done != 0`

## Failure split

If a future implementation reaches Phase 0E-C and fails, triage in this order:

1. no trap taken:
   likely `mtvec`, `mie.MEIE`, `mstatus.MIE`, or target/context selection issue
2. trap taken but wrong `mcause`:
   likely trap entry corruption or unintended exception before IRQ handling
3. claim id not equal to `1`:
   likely wrong PLIC context, wrong enable word, or stale source assumptions
4. claim id is `1` but CEVA status never clears after ack:
   likely wrong local ack write or stale source-level issue
5. local CEVA status clears but PLIC-side state does not settle:
   likely bad claim/complete ordering or wrong context address

## Immediate next implementation step

When Phase 0E-C is actually executed, the smallest safe next move is:

1. add the minimal trap entry to `head.S`
2. add the compact probe set and handler flow to `baremetal.c`
3. reuse the already-closed CEVA and PLIC addresses from Phase 0E-B2.5
4. stop after one successful claim/ack/complete cycle and inspect probes with GDB

This keeps the next step local, testable, and aligned with the current single-IRQ scope.