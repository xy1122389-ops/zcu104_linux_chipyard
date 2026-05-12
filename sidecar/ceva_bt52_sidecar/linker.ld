OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  SIDECAR (rwx) : ORIGIN = 0x000000008F020000, LENGTH = 64K
}

SECTIONS
{
  . = ORIGIN(SIDECAR);
  __sidecar_image_start = .;

  .text : ALIGN(4)
  {
    KEEP(*(.text.entry))
    *(.text*)
  } > SIDECAR

  .rodata : ALIGN(8)
  {
    *(.rodata*)
  } > SIDECAR

  .data : ALIGN(8)
  {
    *(.data*)
  } > SIDECAR

  .sdata : ALIGN(8)
  {
    *(.sdata*)
  } > SIDECAR

  .bss : ALIGN(8)
  {
    __bss_start = .;
    *(.sbss*)
    *(.bss*)
    *(COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > SIDECAR

  .stack (NOLOAD) : ALIGN(16)
  {
    __stack_bottom = .;
    . += 0x1000;
    . = ALIGN(16);
    __stack_top = .;
  } > SIDECAR

  __sidecar_image_end = .;

  /DISCARD/ :
  {
    *(.comment*)
    *(.eh_frame*)
  }
}

ASSERT(__sidecar_image_end <= ORIGIN(SIDECAR) + LENGTH(SIDECAR), "sidecar image exceeds reserved window")
