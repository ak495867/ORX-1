#ifndef _MODEL_TEST_H
#define _MODEL_TEST_H

#define RVMODEL_DATA_BEGIN \
  .align 4; .global begin_regstate; begin_regstate: \
  .word 0; \
  .align 4; .global end_regstate; end_regstate: \
  .word 0; \
  .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END \
  .align 4; .global end_signature; end_signature: \
  .word 0;

#define RVMODEL_BOOT \
  .section .text.init; \
  .globl _start; \
  _start: \
    la sp, 0x00010ff0; \
    j test_entry;

#define RVMODEL_HALT \
  la t0, 0x00011000; \
  li t1, 1; \
  sw t1, 0(t0); \
  1: j 1b;

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R1, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_R1, _R2, _VAL)

#endif
