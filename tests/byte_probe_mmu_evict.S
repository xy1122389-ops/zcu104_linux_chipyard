/*
 * byte_probe_mmu_evict.S — D-cache eviction variant of the byte-access probe
 *
 * Same as byte_probe_mmu.S but inserts a 64 KB D-cache flush between
 * the sb/lbu and the verification ld/lbu.  This forces the written
 * byte through the full D-cache → L2 → D-cache round-trip.
 *
 * Memory map  (identity-mapped 1 GB megapage 0x8000_0000–0xBFFF_FFFF):
 *   0x8120_0000  Code
 *   0x8120_4000  SV39 root PT  (4 KB)
 *   0x8121_0000  Test buffer   (80 KB)
 *   0x8122_4000  Result block  (256 B)
 *   0x8123_0000  Stack top
 *   0x8400_0000  Eviction buffer (64 KB read target — unrelated DDR)
 *
 * Result block:
 *   +0x00  magic         "DONE" / "TRAP"
 *   +0x08  sb_mm         (Part A: sb + evict + ld)
 *   +0x10  total_iters
 *   +0x18  sb_1st_iter
 *   +0x20  sb_1st_exp
 *   +0x28  sb_1st_act
 *   +0x30  sb_1st_addr
 *   +0x38  lbu_mm        (Part B: sd + evict + lbu)
 *   +0x40  lbu_1st_iter
 *   +0x48  lbu_1st_exp
 *   +0x50  lbu_1st_act
 *   +0x58  pass_fail     "PASS" / "FAIL"
 *   +0x60  trap_cause
 *   +0x68  trap_val
 *   +0x70  trap_epc
 */

.section .text
.globl _start

.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ BUF_BASE,      0x81210000
.equ RES_BASE,      0x81224000
.equ STACK_TOP,     0x81230000
.equ TOTAL_ITERS,   10000
.equ MEGAPAGE_PTE,  0x200000CF
.equ EVICT_BASE,    0x84000000
.equ EVICT_END,     0x84010000        /* 64 KB */

/* ============================================================
 *  M-mode entry
 * ============================================================ */
_start:
    /* clear MPRV, disable old MMU */
    csrr    t0, mstatus
    li      t1, 0x20000
    not     t1, t1
    and     t0, t0, t1
    csrw    mstatus, t0
    csrw    satp, zero
    sfence.vma

    /* Phase 0: self-copyback (dirty L2 lines) */
    li      t0, CODE_BASE
    li      t1, STACK_TOP
.Lcb:
    ld      t2, 0(t0)
    sd      t2, 0(t0)
    addi    t0, t0, 64
    blt     t0, t1, .Lcb
    fence

    /* Zero page table */
    li      t0, PT_BASE
    li      t1, PT_BASE + 4096
.Lpt0:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lpt0

    /* Write megapage PTE entry[2] */
    li      t0, PT_BASE
    li      t1, MEGAPAGE_PTE
    sd      t1, 16(t0)

    /* Also map 0x84000000 — same 1 GB megapage covers 0x80..0xBF */
    /* (already covered by entry[2]) */

    /* Zero result block (256 B) */
    li      t0, RES_BASE
    li      t1, RES_BASE + 256
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    /* Set stvec */
    la      t0, s_trap_handler
    csrw    stvec, t0

    /* Delegate exceptions & interrupts to S-mode */
    li      t0, 0xFFFF
    csrw    medeleg, t0
    li      t0, 0x222
    csrw    mideleg, t0

    /* mstatus: MPP = S-mode */
    csrr    t0, mstatus
    li      t1, 0x21800
    not     t1, t1
    and     t0, t0, t1
    li      t1, 0x0800
    or      t0, t0, t1
    csrw    mstatus, t0

    la      t0, s_mode_entry
    csrw    mepc, t0

    /* satp: SV39 | PPN */
    li      t0, 8
    slli    t0, t0, 60
    li      t1, (PT_BASE >> 12)
    or      t0, t0, t1
    csrw    satp, t0

    sfence.vma
    fence.i
    mret

/* ============================================================
 *  S-mode entry
 * ============================================================ */
.balign 16
s_mode_entry:
    fence.i
    li      sp, STACK_TOP

    /* Build pattern 0x0102030405060708 */
    li      s2, 0x01020304
    slli    s2, s2, 32
    li      t0, 0x05060708
    or      s2, s2, t0

    li      s3, 0xAA
    li      s4, 0xFF
    li      a0, BUF_BASE
    li      s0, TOTAL_ITERS
    li      s1, RES_BASE

    /* ---- Part A: sd → sb → EVICT → ld verify ---- */
    li      a1, 0           /* iter */
    li      a2, 0           /* mismatch */
    li      a3, 0           /* 1st fail iter */
    li      a4, 0
    li      a5, 0
    li      a6, 0

.Lsb_loop:
    bge     a1, s0, .Lsb_done

    slli    t0, a1, 3
    add     t0, a0, t0

    sd      s2, 0(t0)              /* write pattern */

    andi    t1, a1, 7
    add     t2, t0, t1
    sb      s3, 0(t2)              /* sb 0xAA */
    fence                          /* commit store */

    /* --- evict D-cache: read 64 KB --- */
    li      t6, EVICT_BASE
    li      a7, EVICT_END
.Lev1:
    ld      t3, 0(t6)
    addi    t6, t6, 64
    blt     t6, a7, .Lev1

    ld      t3, 0(t0)              /* re-read (must come from L2) */

    /* compute expected */
    slli    t4, t1, 3
    sll     t5, s4, t4
    not     t5, t5
    and     t6, s2, t5
    sll     t5, s3, t4
    or      t5, t6, t5

    beq     t3, t5, .Lsb_ok
    addi    a2, a2, 1
    bnez    a3, .Lsb_nf
    addi    a3, a1, 1
    mv      a4, t5
    mv      a5, t3
    mv      a6, t0
.Lsb_nf:
.Lsb_ok:
    addi    a1, a1, 1
    j       .Lsb_loop

.Lsb_done:
    mv      s5, a2
    mv      s6, a3
    mv      s7, a4
    mv      s8, a5
    mv      s9, a6

    /* ---- Part B: sd → EVICT → lbu verify ---- */
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0

.Llbu_loop:
    bge     a1, s0, .Llbu_done

    slli    t0, a1, 3
    add     t0, a0, t0

    sd      s2, 0(t0)              /* write pattern */
    fence

    /* --- evict D-cache: read 64 KB --- */
    li      t6, EVICT_BASE
    li      a7, EVICT_END
.Lev2:
    ld      t3, 0(t6)
    addi    t6, t6, 64
    blt     t6, a7, .Lev2

    andi    t1, a1, 7
    add     t2, t0, t1
    lbu     t3, 0(t2)              /* lbu (must reload from L2) */

    slli    t4, t1, 3
    srl     t5, s2, t4
    and     t5, t5, s4

    beq     t3, t5, .Llbu_ok
    addi    a2, a2, 1
    bnez    a3, .Llbu_nf
    addi    a3, a1, 1
    mv      a4, t5
    mv      a5, t3
.Llbu_nf:
.Llbu_ok:
    addi    a1, a1, 1
    j       .Llbu_loop

.Llbu_done:

    /* ---- Write results ---- */
    li      t0, 0x444F4E45
    sd      t0, 0x00(s1)
    sd      s5, 0x08(s1)
    sd      s0, 0x10(s1)
    sd      s6, 0x18(s1)
    sd      s7, 0x20(s1)
    sd      s8, 0x28(s1)
    sd      s9, 0x30(s1)
    sd      a2, 0x38(s1)
    sd      a3, 0x40(s1)
    sd      a4, 0x48(s1)
    sd      a5, 0x50(s1)

    or      t0, s5, a2
    bnez    t0, .Lfail
    li      t0, 0x50415353
    j       .Lwpf
.Lfail:
    li      t0, 0x4641494C
.Lwpf:
    sd      t0, 0x58(s1)

    /* flush D-cache → L2 */
    li      t0, 0x82000000
    li      t1, 0x82010000
.Lflush:
    ld      t2, 0(t0)
    addi    t0, t0, 64
    blt     t0, t1, .Lflush
    fence

.Ldone:
    wfi
    j       .Ldone

/* ============================================================ */
.balign 16
s_trap_handler:
    li      t0, RES_BASE
    li      t1, 0x54524150
    sd      t1, 0x00(t0)
    csrr    t1, scause
    sd      t1, 0x60(t0)
    csrr    t1, stval
    sd      t1, 0x68(t0)
    csrr    t1, sepc
    sd      t1, 0x70(t0)
    li      t2, 0x82000000
    li      t3, 0x82010000
.Ltf:
    ld      t4, 0(t2)
    addi    t2, t2, 64
    blt     t2, t3, .Ltf
    fence
.Lts:
    wfi
    j       .Lts
