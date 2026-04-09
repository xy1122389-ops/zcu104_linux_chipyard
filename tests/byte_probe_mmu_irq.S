/*
 * byte_probe_mmu_irq.S — Byte-access probe with S-mode software interrupts
 *
 * Uses SSI (SSIP via csrs sip) to trigger an interrupt between
 * sb and ld on EVERY iteration.  Tests whether interrupt context
 * switch (trap frame save/restore, TLB/cache interaction) corrupts
 * byte store results.
 *
 * Memory map (identity-mapped 1 GB megapage):
 *   0x8120_0000  Code
 *   0x8120_4000  SV39 root PT        (4 KB)
 *   0x8121_0000  Test buffer          (80 KB)
 *   0x8122_4000  Result block         (256 B)
 *   0x8122_4100  IRQ scratch area     (256 B)
 *   0x8123_0000  Stack top
 *
 * Result +0x78 = irq_count
 */

.section .text
.globl _start

.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ BUF_BASE,      0x81210000
.equ RES_BASE,      0x81224000
.equ IRQ_SCRATCH,   0x81224100
.equ STACK_TOP,     0x81230000
.equ TOTAL_ITERS,   10000
.equ MEGAPAGE_PTE,  0x200000CF

_start:
    csrr    t0, mstatus
    li      t1, 0x20000
    not     t1, t1
    and     t0, t0, t1
    csrw    mstatus, t0
    csrw    satp, zero
    sfence.vma

    /* Self-copyback */
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

    /* Megapage PTE entry[2] */
    li      t0, PT_BASE
    li      t1, MEGAPAGE_PTE
    sd      t1, 16(t0)

    /* Zero result + scratch areas */
    li      t0, RES_BASE
    li      t1, RES_BASE + 512
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    /* stvec */
    la      t0, s_trap_vector
    csrw    stvec, t0

    /* Delegate: keep illegal-insn (2) and ecall-from-S (9) in M-mode */
    li      t0, 0xFDFB
    csrw    medeleg, t0
    /* Delegate SSI(1), STI(5), SEI(9) to S-mode */
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

    li      t0, 8
    slli    t0, t0, 60
    li      t1, (PT_BASE >> 12)
    or      t0, t0, t1
    csrw    satp, t0

    sfence.vma
    fence.i
    mret

/* ============================================================ */
.balign 16
s_mode_entry:
    fence.i
    li      sp, STACK_TOP

    /* Pattern */
    li      s2, 0x01020304
    slli    s2, s2, 32
    li      t0, 0x05060708
    or      s2, s2, t0

    li      s3, 0xAA
    li      s4, 0xFF
    li      a0, BUF_BASE
    li      s0, TOTAL_ITERS
    li      s1, RES_BASE

    /* Enable SSI: sie.SSIE (bit 1) — do NOT enable STIE */
    li      t0, 0x2
    csrs    sie, t0
    /* Clear any pending STIP from previous runs (disable STIE first) */
    li      t0, 0x20
    csrc    sie, t0               /* disable STIE so pending STIP won't fire */

    /* Enable global S-mode interrupts: sstatus.SIE (bit 1) */
    li      t0, 0x2
    csrs    sstatus, t0

    /* ---- Part A: sd → sb → SSI → ld verify ---- */
    li      a1, 0
    li      a2, 0
    li      a3, 0
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

    /* Trigger SSI by setting SSIP — interrupt taken before next insn */
    csrs    sip, 0x2

    ld      t3, 0(t0)              /* verify */

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

    /* ---- Part B: sd → SSI → lbu verify ---- */
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

    /* Trigger SSI */
    csrs    sip, 0x2

    andi    t1, a1, 7
    add     t2, t0, t1
    lbu     t3, 0(t2)

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
    /* Disable interrupts */
    li      t0, 0x2
    csrc    sstatus, t0

    /* Write results */
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

    /* Read irq_count */
    li      t0, IRQ_SCRATCH
    ld      t1, 0(t0)
    sd      t1, 0x78(s1)

    /* Flush D-cache */
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

/* ============================================================
 *  S-mode trap vector
 * ============================================================ */
.balign 16
s_trap_vector:
    addi    sp, sp, -128
    sd      ra,   0(sp)
    sd      t0,   8(sp)
    sd      t1,  16(sp)
    sd      t2,  24(sp)
    sd      t3,  32(sp)
    sd      t4,  40(sp)
    sd      t5,  48(sp)
    sd      t6,  56(sp)
    sd      a7,  64(sp)

    csrr    t0, scause
    bltz    t0, .Lis_interrupt

    /* Exception */
    li      t1, RES_BASE
    li      t2, 0x54524150
    sd      t2, 0x00(t1)
    sd      t0, 0x60(t1)
    csrr    t2, stval
    sd      t2, 0x68(t1)
    csrr    t2, sepc
    sd      t2, 0x70(t1)
    li      t2, 0x82000000
    li      t3, 0x82010000
.Lef:
    ld      t4, 0(t2)
    addi    t2, t2, 64
    blt     t2, t3, .Lef
    fence
.Les:
    wfi
    j       .Les

.Lis_interrupt:
    /* Check cause: bit63 + 1 = SSI */
    slli    t1, t0, 1
    srli    t1, t1, 1              /* clear bit 63 */
    li      t2, 1                  /* cause 1 = SSI */
    bne     t1, t2, .Lother_irq

    /* ---- SSI handler ---- */
    /* Clear SSIP to acknowledge */
    csrc    sip, 0x2

    /* Bump irq_count */
    li      t0, IRQ_SCRATCH
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    /* Touch cache lines to simulate realistic handler pressure */
    sd      t1,  8(t0)
    sd      t1, 72(t0)
    sd      t1, 136(t0)
    sd      t1, 200(t0)
    ld      t2, 16(t0)
    ld      t2, 80(t0)
    ld      t2, 144(t0)
    ld      t2, 208(t0)

    j       .Ltrap_ret

.Lother_irq:
    /* Unknown interrupt — just return */

.Ltrap_ret:
    ld      ra,   0(sp)
    ld      t0,   8(sp)
    ld      t1,  16(sp)
    ld      t2,  24(sp)
    ld      t3,  32(sp)
    ld      t4,  40(sp)
    ld      t5,  48(sp)
    ld      t6,  56(sp)
    ld      a7,  64(sp)
    addi    sp, sp, 128
    sret
