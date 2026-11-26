OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K
  RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > RAM

  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    __bss_end = .;
  } > RAM

  _end = .;
  PROVIDE(__stack_top = 0x00011000);
}
