    .section .text.entry, "ax", @progbits
    .globl _start
    .type _start, @function

_start:
    .option push
    .option norelax
    la sp, __stack_top
    .option pop

    la t0, __bss_start
    la t1, __bss_end

1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b

2:
    fence rw, rw
    call sidecar_start

3:
    fence rw, rw
    j 3b

    .size _start, . - _start
