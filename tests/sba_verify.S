/*
 * sba_verify.S — Verify SBA-loaded data integrity from CPU side
 *
 * Computes 64-bit XOR checksum of 1 MB at 0x80200000 (kernel text)
 * from S-mode with SV39 and writes result to 0x81224000.
 *
 * Host-side reference: 0x569883b8fd6c0509
 *
 * Must run AFTER fw_payload.bin is loaded via SBA.
 * Re-uses same page table setup as byte_probe_mmu.
 *
 * Result block:
 *   +0x00  magic "DONE"
 *   +0x08  xor_checksum
 *   +0x10  bytes_processed
 *   +0x18  match flag (1=match, 0=mismatch)
 */

.section .text
.globl _start

.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ RES_BASE,      0x81224000
.equ STACK_TOP,     0x81230000
.equ MEGAPAGE_PTE,  0x200000CF

.equ CHECK_BASE,    0x80200000
.equ CHECK_SIZE,    0x100000       /* 1 MB */

/* Expected checksum from host */
.equ EXPECT_HI,    0x569883B8
.equ EXPECT_LO,    0xFD6C0509

_start:
    csrr    t0, mstatus
    li      t1, 0x20000
    not     t1, t1
    and     t0, t0, t1
    csrw    mstatus, t0
    csrw    satp, zero
    sfence.vma

    /* Zero PT */
    li      t0, PT_BASE
    li      t1, PT_BASE + 4096
.Lpt0:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lpt0

    /* Megapage PTE entry[2] for 0x80000000-0xBFFFFFFF */
    li      t0, PT_BASE
    li      t1, MEGAPAGE_PTE
    sd      t1, 16(t0)

    /* Zero result block */
    li      t0, RES_BASE
    li      t1, RES_BASE + 64
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    /* stvec */
    la      t0, s_trap_handler
    csrw    stvec, t0

    li      t0, 0xFDFB
    csrw    medeleg, t0
    li      t0, 0x222
    csrw    mideleg, t0

    /* MPP = S */
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

.balign 16
s_mode_entry:
    fence.i
    li      sp, STACK_TOP

    /* XOR checksum loop */
    li      t0, CHECK_BASE
    li      t1, CHECK_BASE + CHECK_SIZE
    li      t2, 0                  /* running xor */

.Lxor:
    ld      t3, 0(t0)
    xor     t2, t2, t3
    addi    t0, t0, 8
    blt     t0, t1, .Lxor

    /* Write results */
    li      s1, RES_BASE
    li      t0, 0x444F4E45
    sd      t0, 0x00(s1)           /* magic */
    sd      t2, 0x08(s1)           /* checksum */
    li      t0, CHECK_SIZE
    sd      t0, 0x10(s1)           /* bytes */

    /* Compare with expected */
    li      t3, EXPECT_HI
    slli    t3, t3, 32
    li      t4, EXPECT_LO
    or      t3, t3, t4
    beq     t2, t3, .Lmatch
    sd      zero, 0x18(s1)         /* 0 = mismatch */
    j       .Lflush
.Lmatch:
    li      t0, 1
    sd      t0, 0x18(s1)           /* 1 = match */

.Lflush:
    li      t0, 0x82000000
    li      t1, 0x82010000
.Lfl:
    ld      t2, 0(t0)
    addi    t0, t0, 64
    blt     t0, t1, .Lfl
    fence

.Ldone:
    wfi
    j       .Ldone

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
