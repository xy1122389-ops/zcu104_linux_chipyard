ENTRY(_prog_start)

MEMORY
{
  linux_chain_mem (rwx) : ORIGIN = 0x80200000, LENGTH = 0x00200000
}

SECTIONS
{
  . = ORIGIN(linux_chain_mem);

  .text.init : {
    *(.text.init)
  } > linux_chain_mem

  .text : {
    *(.text .text.*)
  } > linux_chain_mem

  .rodata : {
    *(.rodata .rodata.*)
  } > linux_chain_mem

  .data : {
    *(.data .data.*)
  } > linux_chain_mem

  .bss (NOLOAD) : {
    *(.bss .bss.*)
    *(COMMON)
  } > linux_chain_mem

  . = ALIGN(16);
  _end = .;
  _stack_top = ORIGIN(linux_chain_mem) + LENGTH(linux_chain_mem);
}
