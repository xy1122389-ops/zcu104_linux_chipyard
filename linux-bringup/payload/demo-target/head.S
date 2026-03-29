// Minimal demo jump target entry used to validate the first real jump closure.
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
