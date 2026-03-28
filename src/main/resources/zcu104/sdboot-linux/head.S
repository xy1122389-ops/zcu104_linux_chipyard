// Minimal Linux handoff bootrom for ZCU104.
#include <platform.h>

#define DDR_SENTINEL  0x8FF00000

  .section .text.init
  .option norvc
  .globl _hang

_hang:
  li t3, DDR_SENTINEL
  li t4, 0x11111111
  sw t4, 0(t3)
1:
  j 1b

  .section .text.hang80, "ax", @progbits
  .globl _hang80
_hang80:
  j _hang

  .section .dtb
  .align 3
dtb:
