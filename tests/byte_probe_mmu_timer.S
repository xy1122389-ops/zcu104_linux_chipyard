/*
 * byte_probe_mmu_timer.S — Byte-access probe with S-mode timer interrupts
 *
 * Same sb/lbu test, but with timer interrupts firing every ~500 cycles
 * via SBI set_timer.  Timer handler touches cache lines (realistic
 * pressure like kernel timer tick).
 *
 * Memory map (identity-mapped 1 GB megapage):
 *   0x8120_0000  Code
 *   0x8120_4000  SV39 root PT        (4 KB)
 *   0x8121_0000  Test buffer          (80 KB)
 *   0x8122_4000  Result block         (256 B)
 *   0x8122_4100  Timer scratch area   (256 B — handler touches this)
 *   0x8123_0000  Stack top
 *
 * Result block (+0x78..+0x80 extra fields):
 *   +0x78  timer_count   — number of timer interrupts taken
 */

.section .text
.globl _start

.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ BUF_BASE,      0x81210000
.equ RES_BASE,      0x81224000
.equ TIMER_SCRATCH, 0x81224100
.equ STACK_TOP,     0x81230000
.equ TOTAL_ITERS,   10000
.equ MEGAPAGE_PTE,  0x200000CF
.equ TIMER_INTERVAL, 500           /* cycles between timer IRQs */

_start:
    csrr    t0, mstatus
    li      t1, 0x20000
    not     t1, t1
    and     t0, t0, t1
    csrw    mstatus, t0
    csrw    satp, zero
    sfence.vma

    /* Phase 0: self-copyback */
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

    /* Zero result block (256 + 256 B) */
    li      t0, RES_BASE
    li      t1, RES_BASE + 512
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    /* stvec = S-mode trap vector (vectored: bit 0 = 0 → direct) */
    la      t0, s_trap_vector
    csrw    stvec, t0

    /* Delegate exceptions & interrupts */
    /* Keep in M-mode (OpenSBI): bit 2 (illegal-insn → rdtime emulation),
       bit 9 (ecall-from-S → SBI calls) */
    li      t0, 0xFDFB
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

    /* satp */
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

    /* ---- Arm first timer via SBI set_timer (legacy a7=0) ---- */
    rdtime  t0
    li      t1, TIMER_INTERVAL
    add     a0, t0, t1              /* absolute time for first fire */
    li      a7, 0                   /* SBI legacy set_timer */
    ecall

    /* Re-load a0 (SBI may have clobbered it) */
    li      a0, BUF_BASE

    /* Enable S-mode timer interrupt: sie.STIE (bit 5) */
    li      t0, 0x20
    csrs    sie, t0

    /* Enable global S-mode interrupts: sstatus.SIE (bit 1) */
    li      t0, 0x2
    csrs    sstatus, t0

    /* ---- Part A: sd → sb → ld verify (with timer IRQs) ---- */
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

    sd      s2, 0(t0)
    andi    t1, a1, 7
    add     t2, t0, t1
    sb      s3, 0(t2)

    ld      t3, 0(t0)

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

    /* ---- Part B: sd → lbu verify ---- */
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0

.Llbu_loop:
    bge     a1, s0, .Llbu_done

    slli    t0, a1, 3
    add     t0, a0, t0

    sd      s2, 0(t0)
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

    /* Read timer_count from scratch area word 0 */
    li      t0, TIMER_SCRATCH
    ld      t1, 0(t0)
    sd      t1, 0x78(s1)          /* result +0x78 = timer_count */

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
 *  S-mode trap vector (direct mode)
 *  scause bit 63 = 1 → interrupt, bits[62:0] = cause
 *  cause 5 = S-timer interrupt
 * ============================================================ */
.balign 16
s_trap_vector:
    /* Save minimal context on stack */
    addi    sp, sp, -128
    sd      ra,   0(sp)
    sd      t0,   8(sp)
    sd      t1,  16(sp)
    sd      t2,  24(sp)
    sd      t3,  32(sp)
    sd      t4,  40(sp)
    sd      t5,  48(sp)
    sd      t6,  56(sp)
    sd      a0,  64(sp)
    sd      a7,  72(sp)

    csrr    t0, scause
    /* Check if it's an interrupt (bit 63) */
    bltz    t0, .Lis_interrupt

    /* ---- Exception path ---- */
    li      t1, RES_BASE
    li      t2, 0x54524150
    sd      t2, 0x00(t1)
    sd      t0, 0x60(t1)
    csrr    t2, stval
    sd      t2, 0x68(t1)
    csrr    t2, sepc
    sd      t2, 0x70(t1)
    /* flush & spin */
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
    /* Mask off bit 63 to get cause number */
    li      t1, 5                  /* S-timer */
    slli    t2, t0, 1
    srli    t2, t2, 1              /* clear bit 63 */
    bne     t2, t1, .Lunknown_irq

    /* ---- Timer interrupt handler ---- */
    /* Bump timer_count */
    li      t0, TIMER_SCRATCH
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    /* Touch a few cache lines in scratch area to add cache pressure */
    sd      t1, 8(t0)
    sd      t1, 72(t0)
    sd      t1, 136(t0)
    sd      t1, 200(t0)
    ld      t2, 16(t0)
    ld      t2, 80(t0)
    ld      t2, 144(t0)
    ld      t2, 208(t0)

    /* Re-arm timer: time + INTERVAL */
    rdtime  a0
    li      t1, TIMER_INTERVAL
    add     a0, a0, t1
    li      a7, 0                  /* SBI legacy set_timer */
    ecall

    /* Restore and return */
    ld      ra,   0(sp)
    ld      t0,   8(sp)
    ld      t1,  16(sp)
    ld      t2,  24(sp)
    ld      t3,  32(sp)
    ld      t4,  40(sp)
    ld      t5,  48(sp)
    ld      t6,  56(sp)
    ld      a0,  64(sp)
    ld      a7,  72(sp)
    addi    sp, sp, 128
    sret

.Lunknown_irq:
    /* Unknown interrupt — just clear and return */
    ld      ra,   0(sp)
    ld      t0,   8(sp)
    ld      t1,  16(sp)
    ld      t2,  24(sp)
    ld      t3,  32(sp)
    ld      t4,  40(sp)
    ld      t5,  48(sp)
    ld      t6,  56(sp)
    ld      a0,  64(sp)
    ld      a7,  72(sp)
    addi    sp, sp, 128
    sret
