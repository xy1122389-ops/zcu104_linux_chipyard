/*
 * byte_probe_mmu.S — Bare-metal S-mode + SV39 byte-access hardware probe
 *
 * Purpose: Determine whether Rocket's D-cache byte load/store path has a
 *          hardware bug that manifests only when the MMU (SV39) is active.
 *
 * Test plan:
 *   Part A  —  sd pattern; sb 0xAA to one byte; ld verify   (×10 000)
 *   Part B  —  sd pattern; lbu one byte; compare            (×10 000)
 *
 * Memory map (identity-mapped 1 GB megapage 0x8000_0000–0xBFFF_FFFF):
 *   0x8120_0000  Code          (~1 KB)
 *   0x8120_4000  SV39 root PT  (4 KB, 1 entry used)
 *   0x8121_0000  Test buffer   (80 KB = 10 000 × 8 B)
 *   0x8122_4000  Result block  (128 B)
 *   0x8123_0000  Stack top     (grows down)
 *
 * Result block layout (all 8-byte slots):
 *   +0x00  magic         0x444F4E45="DONE" | 0x54524150="TRAP"
 *   +0x08  sb_mismatch
 *   +0x10  total_iters   (10 000)
 *   +0x18  sb_1st_iter   (1-based, 0 = no fail)
 *   +0x20  sb_1st_exp
 *   +0x28  sb_1st_act
 *   +0x30  sb_1st_addr
 *   +0x38  lbu_mismatch
 *   +0x40  lbu_1st_iter  (1-based, 0 = no fail)
 *   +0x48  lbu_1st_exp
 *   +0x50  lbu_1st_act
 *   +0x58  pass_fail     0x50415353="PASS" | 0x4641494C="FAIL"
 *   +0x60  trap_cause    (only if TRAP)
 *   +0x68  trap_val
 *   +0x70  trap_epc
 *
 * Build:
 *   riscv64-unknown-elf-as -march=rv64gc -o byte_probe_mmu.o byte_probe_mmu.S
 *   riscv64-unknown-elf-ld -Ttext=0x81200000 -o byte_probe_mmu.elf byte_probe_mmu.o
 *   riscv64-unknown-elf-objcopy -O binary byte_probe_mmu.elf byte_probe_mmu.bin
 */

.section .text
.globl _start

/* ============================================================
 *  Constants
 * ============================================================ */
.equ CODE_BASE,     0x81200000
.equ PT_BASE,       0x81204000
.equ BUF_BASE,      0x81210000
.equ RES_BASE,      0x81224000
.equ STACK_TOP,     0x81230000
.equ TOTAL_ITERS,   10000

/* SV39 1-GB megapage PTE for PA 0x8000_0000:
 *   PPN[2]=2 → bits[53:28] = 2 → (2 << 28)
 *   D=1 A=1 G=0 U=0 X=1 W=1 R=1 V=1 → 0xCF
 */
.equ MEGAPAGE_PTE,  0x200000CF

/* ============================================================
 *  M-mode entry — runs at physical address 0x8120_0000
 * ============================================================ */
_start:
    /* ---- housekeeping: clear MPRV, disable old MMU ---- */
    csrr    t0, mstatus
    li      t1, 0x20000             /* MPRV bit (17) */
    not     t1, t1
    and     t0, t0, t1
    csrw    mstatus, t0
    csrw    satp, zero
    sfence.vma

    /* ---- Phase 0: self-copyback  (dirty L2 lines) ---- */
    li      t0, CODE_BASE
    li      t1, STACK_TOP           /* 192 KB covers everything */
.Lcb:
    ld      t2, 0(t0)
    sd      t2, 0(t0)
    addi    t0, t0, 64
    blt     t0, t1, .Lcb
    fence

    /* ---- Zero page table (4 KB) ---- */
    li      t0, PT_BASE
    li      t1, PT_BASE + 4096
.Lpt0:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lpt0

    /* ---- Write megapage PTE at entry[2] ---- */
    li      t0, PT_BASE
    li      t1, MEGAPAGE_PTE
    sd      t1, 16(t0)             /* index 2, offset = 16 */

    /* ---- Zero result block ---- */
    li      t0, RES_BASE
    li      t1, RES_BASE + 128
.Lrz:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    blt     t0, t1, .Lrz
    fence

    /* ---- Set stvec (S-mode trap handler) ---- */
    la      t0, s_trap_handler
    csrw    stvec, t0

    /* ---- Delegate exceptions & interrupts to S-mode ---- */
    li      t0, 0xFFFF
    csrw    medeleg, t0
    li      t0, 0x222              /* SSI + STI + SEI */
    csrw    mideleg, t0

    /* ---- mstatus: MPP = S-mode (01), clear MPRV ---- */
    csrr    t0, mstatus
    li      t1, 0x21800            /* MPP[12:11] | MPRV[17] */
    not     t1, t1
    and     t0, t0, t1             /* clear */
    li      t1, 0x0800             /* MPP = 01 */
    or      t0, t0, t1
    csrw    mstatus, t0

    /* ---- mepc = S-mode entry ---- */
    la      t0, s_mode_entry
    csrw    mepc, t0

    /* ---- satp: SV39 | PPN of root PT ---- */
    li      t0, 8
    slli    t0, t0, 60             /* mode = 8 (SV39) */
    li      t1, (PT_BASE >> 12)    /* PPN = 0x81204 */
    or      t0, t0, t1
    csrw    satp, t0

    sfence.vma
    fence.i

    mret

/* ============================================================
 *  S-mode entry — MMU is now active (identity-mapped)
 * ============================================================ */
.balign 16
s_mode_entry:
    fence.i
    li      sp, STACK_TOP

    /* ---- build pattern 0x0102030405060708 ---- */
    /*  each byte = its 1-based position; no sign-ext issues   */
    li      s2, 0x01020304
    slli    s2, s2, 32
    li      t0, 0x05060708
    or      s2, s2, t0             /* s2 = pattern */

    li      s3, 0xAA               /* probe byte */
    li      s4, 0xFF               /* byte mask */

    /* ---- registers for Part A (sb test) ---- */
    li      a0, BUF_BASE
    li      a1, 0                  /* iter */
    li      a2, 0                  /* sb mismatch cnt */
    li      a3, 0                  /* 1st-fail iter */
    li      a4, 0                  /* 1st-fail expected */
    li      a5, 0                  /* 1st-fail actual */
    li      a6, 0                  /* 1st-fail addr */
    li      s0, TOTAL_ITERS
    li      s1, RES_BASE

/* ---------- Part A: sb + ld verify ---------- */
.Lsb_loop:
    bge     a1, s0, .Lsb_done

    slli    t0, a1, 3
    add     t0, a0, t0             /* slot addr */

    sd      s2, 0(t0)              /* write pattern */

    andi    t1, a1, 7              /* byte_pos = i & 7 */
    add     t2, t0, t1
    sb      s3, 0(t2)              /* sb 0xAA */

    ld      t3, 0(t0)              /* readback */

    /* expected = (pattern & ~(0xFF<<shift)) | (0xAA<<shift) */
    slli    t4, t1, 3              /* shift = byte_pos * 8 */
    sll     t5, s4, t4             /* 0xFF << shift */
    not     t5, t5
    and     t6, s2, t5             /* clear byte */
    sll     t5, s3, t4             /* 0xAA << shift */
    or      t5, t6, t5             /* expected */

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
    /* stash Part A results in s5–s9 */
    mv      s5, a2                 /* sb_mismatch */
    mv      s6, a3                 /* sb_1st_iter */
    mv      s7, a4                 /* sb_1st_exp */
    mv      s8, a5                 /* sb_1st_act */
    mv      s9, a6                 /* sb_1st_addr */

/* ---------- Part B: lbu verify ---------- */
    li      a1, 0                  /* iter */
    li      a2, 0                  /* lbu mismatch cnt */
    li      a3, 0                  /* 1st-fail iter */
    li      a4, 0                  /* 1st-fail exp byte */
    li      a5, 0                  /* 1st-fail act byte */

.Llbu_loop:
    bge     a1, s0, .Llbu_done

    slli    t0, a1, 3
    add     t0, a0, t0

    sd      s2, 0(t0)              /* write pattern */

    andi    t1, a1, 7
    add     t2, t0, t1
    lbu     t3, 0(t2)              /* load byte */

    slli    t4, t1, 3
    srl     t5, s2, t4
    and     t5, t5, s4             /* expected byte */

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

/* ---------- Write results ---------- */
    li      t0, 0x444F4E45        /* "DONE" */
    sd      t0, 0x00(s1)
    sd      s5, 0x08(s1)          /* sb_mismatch */
    sd      s0, 0x10(s1)          /* total_iters */
    sd      s6, 0x18(s1)          /* sb_1st_iter */
    sd      s7, 0x20(s1)          /* sb_1st_exp */
    sd      s8, 0x28(s1)          /* sb_1st_act */
    sd      s9, 0x30(s1)          /* sb_1st_addr */
    sd      a2, 0x38(s1)          /* lbu_mismatch */
    sd      a3, 0x40(s1)          /* lbu_1st_iter */
    sd      a4, 0x48(s1)          /* lbu_1st_exp */
    sd      a5, 0x50(s1)          /* lbu_1st_act */

    or      t0, s5, a2
    bnez    t0, .Lfail
    li      t0, 0x50415353        /* "PASS" */
    j       .Lwpf
.Lfail:
    li      t0, 0x4641494C        /* "FAIL" */
.Lwpf:
    sd      t0, 0x58(s1)

    /* ---- flush D-cache → L2 so GDB SBA can read results ---- */
    /* read 64 KB (2× D-cache) of OTHER memory to evict our lines */
    /* NOTE: 0x80000000 is PMP-protected (OpenSBI fw), use 0x82000000 */
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
 *  S-mode trap handler — record cause & spin
 * ============================================================ */
.balign 16
s_trap_handler:
    li      t0, RES_BASE
    li      t1, 0x54524150        /* "TRAP" */
    sd      t1, 0x00(t0)
    csrr    t1, scause
    sd      t1, 0x60(t0)
    csrr    t1, stval
    sd      t1, 0x68(t0)
    csrr    t1, sepc
    sd      t1, 0x70(t0)

    /* flush — avoid 0x80000000 (PMP-protected by OpenSBI) */
    li      t2, 0x82000000
    li      t3, 0x82010000
.Ltflush:
    ld      t4, 0(t2)
    addi    t2, t2, 64
    blt     t2, t3, .Ltflush
    fence

.Ltspin:
    wfi
    j       .Ltspin
