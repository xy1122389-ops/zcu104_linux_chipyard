ENTRY(_prog_start)

MEMORY
{
  demo_target_mem (rwx) : ORIGIN = 0x80400000, LENGTH = 0x00020000
}

SECTIONS
{
  . = ORIGIN(demo_target_mem);

  .text.init : {
    *(.text.init)
  } > demo_target_mem

  .text : {
    *(.text .text.*)
  } > demo_target_mem

  .rodata : {
    *(.rodata .rodata.*)
  } > demo_target_mem

  .data : {
    *(.data .data.*)
  } > demo_target_mem

  .bss (NOLOAD) : {
    *(.bss .bss.*)
    *(COMMON)
  } > demo_target_mem

  . = ALIGN(16);
  _end = .;
  _stack_top = ORIGIN(demo_target_mem) + LENGTH(demo_target_mem);
}
