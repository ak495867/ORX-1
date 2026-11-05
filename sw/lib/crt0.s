.section .text.init
.globl _start
_start:
  la sp, __stack_top
  la a0, __bss_start
  la a1, __bss_end
bss_clear_loop:
  bge a0, a1, bss_clear_done
  sw zero, 0(a0)
  addi a0, a0, 4
  j bss_clear_loop
bss_clear_done:
  call main
halt_loop:
  wfi
  j halt_loop
