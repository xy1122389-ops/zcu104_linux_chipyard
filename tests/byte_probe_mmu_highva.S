/*
 * byte_probe_mmu_highva.S — Byte probe with kernel-like non-identity VA mapping
 *
 * Tests sb/lbu using a HIGH VA mapping like the Linux kernel:
 *   VA 0xFFFFFFFF80000000 → PA 0x81210000  (test buffer)
 *
 * Uses a 3-level SV39 page table (root → level-1 → level-0 megapage)
 * to map the high VA.  Code and page tables remain at identity-mapped
 * low addresses.  The test stores/loads happen through the high VA.
 *
 * SV39 VA decomposition for 0xFFFFFFFF80000000:
 *   VPN[2] = bits[38:30] = 0x1FE  (510)
 *   VPN[1] = bits[29:21] = 0x1FC  (508)  -- wait, let me recalculate
 *
 * Actually: 0xFFFFFFFF80000000
 *   Bit 38 = 1 → sign-extended from bit 38 (SV39 uses bits 38:0)
 *   VA[38:0] = 0x7F_8000_0000
 *   VPN[2] = VA[38:30] = 0x1FE = 510
 *   VPN[1] = VA[29:21] = 0x000 = 0
 *   VPN[0] = VA[20:12] = 0x000 = 0
 *   offset  = VA[11:0]  = 0x000
 *
 * We'll use a 1 GB megapage at VPN[2]=510 to map to PA 0x80000000.
 * Then VA 0xFFFFFFFF81210000 maps to PA 0x81210000 (our buffer).
 *
 * Also keep the identity megapage at VPN[2]=2 for code.
 *
 * Memory map:
 *   0x8120_0000  Code (identity-mapped via entry[2])
 *   0x8120_4000  Page table root (512 entries × 8 B = 4 KB)
 *   0x8121_0000  Test buffer (identity-mapped AND high-VA-mapped)
 *   0x8122_4000  Result block
 *   0x8123_0000  Stack top (identity-mapped)
 *
 * High VA used for test buffer: 0xFFFFFFFF81210000
 */

.section .text
.globl _start

.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ BUF_BASE_PA,   0x81210000
.equ RES_BASE,      0x81224000
.equ STACK_TOP,     0x81230000
.equ TOTAL_ITERS,   10000
.equ MEGAPAGE_PTE,  0x200000CF      /* PA 0x80000000, D=A=1, XWRV */

/* High VA for test buffer: 0xFFFFFFFF81210000
 * = identity-map base 0xFFFFFFFF80000000 + offset 0x01210000
 * With megapage at VPN[2]=510 → PA 0x80000000+, this maps:
 *   VA 0xFFFFFFFF81210000 → PA 0x81210000
 */
.equ BUF_VA_HI,    0xFFFFFFFF
.equ BUF_VA_LO,    0x81210000

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

    /* Identity megapage: entry[2] → PA 0x80000000 */
    li      t0, PT_BASE
    li      t1, MEGAPAGE_PTE
    sd      t1, 16(t0)             /* entry[2], offset = 2×8 = 16 */

    /* High VA megapage: entry[510] → PA 0x80000000
     * Same PTE value (same physical range).
     * offset = 510 × 8 = 4080 = 0xFF0
     */
    addi    t2, t0, 0x7F8          /* t0 + 2040 */
    sd      t1, 0x7F8(t2)          /* 2040 + 2040 = 4080 = entry[510] */

    /* Zero result block */
    li      t0, RES_BASE
    li      t1, RES_BASE + 128
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    la      t0, s_trap_handler
    csrw    stvec, t0

    li      t0, 0xFDFB
    csrw    medeleg, t0
    li      t0, 0x222
    csrw    mideleg, t0

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

    /* Build HIGH VA for buffer: 0xFFFFFFFF81210000 */
    li      a0, BUF_VA_HI
    slli    a0, a0, 32
    li      t0, BUF_VA_LO
    or      a0, a0, t0             /* a0 = high-VA buffer pointer */

    /* Pattern */
    li      s2, 0x01020304
    slli    s2, s2, 32
    li      t0, 0x05060708
    or      s2, s2, t0

    li      s3, 0xAA
    li      s4, 0xFF
    li      s0, TOTAL_ITERS
    li      s1, RES_BASE           /* results at identity-mapped addr */

    /* ---- Part A: sd → sb → ld via HIGH VA ---- */
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0
    li      a6, 0

.Lsb_loop:
    bge     a1, s0, .Lsb_done

    slli    t0, a1, 3
    add     t0, a0, t0             /* high-VA slot addr */

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

    /* ---- Part B: sd → lbu via HIGH VA ---- */
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
    /* Write results (via identity-mapped RES_BASE) */
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

    /* D-cache flush */
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
