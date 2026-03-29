// Minimal Linux front-chain entry for standalone JTAG-loaded payload work.
#include <platform.h>

  .section .text.init
  .option norvc
  .globl _prog_start
  .extern _stack_top
_prog_start:
  la sp, _stack_top
  call main
1:
  j 1b
