// See LICENSE.Sifive for license details.
#include <platform.h>

  .section .text.init
  .option norvc
  .globl _prog_start
  .extern _sp
_prog_start:
  la sp, _sp
  call main
1:
  j 1b

  .section .dtb
  .align 3
dtb:
