MEMORY
{
  bootrom_mem (rx) : ORIGIN = 0x10000, LENGTH = 0x2000
  /* Use the on-chip mbus scratchpad for stack and .bss to avoid requiring PS DDR init. */
  memory_mem (rwx) : ORIGIN = 0x08000000, LENGTH = 0x00010000
}
