// See LICENSE.Sifive for license details.
#include <platform.h>

  .section .text.init
  .option norvc
  .globl _prog_start
  .globl phase0e_irq_trap_entry
  .extern phase0e_irq_trap_handler
  .extern _sp
_prog_start:
  la sp, _sp
  la t0, phase0e_irq_trap_entry
  csrw mtvec, t0
  call main
1:
  j 1b

  .align 2
phase0e_irq_trap_entry:
  addi sp, sp, -144
  sd ra, 0(sp)
  sd gp, 8(sp)
  sd tp, 16(sp)
  sd t0, 24(sp)
  sd t1, 32(sp)
  sd t2, 40(sp)
  sd a0, 48(sp)
  sd a1, 56(sp)
  sd a2, 64(sp)
  sd a3, 72(sp)
  sd a4, 80(sp)
  sd a5, 88(sp)
  sd a6, 96(sp)
  sd a7, 104(sp)
  sd t3, 112(sp)
  sd t4, 120(sp)
  sd t5, 128(sp)
  sd t6, 136(sp)
  call phase0e_irq_trap_handler
  ld ra, 0(sp)
  ld gp, 8(sp)
  ld tp, 16(sp)
  ld t0, 24(sp)
  ld t1, 32(sp)
  ld t2, 40(sp)
  ld a0, 48(sp)
  ld a1, 56(sp)
  ld a2, 64(sp)
  ld a3, 72(sp)
  ld a4, 80(sp)
  ld a5, 88(sp)
  ld a6, 96(sp)
  ld a7, 104(sp)
  ld t3, 112(sp)
  ld t4, 120(sp)
  ld t5, 128(sp)
  ld t6, 136(sp)
  addi sp, sp, 144
  mret

  .section .dtb
  .align 3
dtb:
