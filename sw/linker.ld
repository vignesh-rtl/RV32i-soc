ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 4K
}

SECTIONS
{
  .text : { *(.text*) } > ROM
  .data : { *(.data*) } > RAM
  .bss  : { *(.bss*)  } > RAM
}

