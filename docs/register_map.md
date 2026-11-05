# ORX-1 Register Map

ORX-1 exposes peripherals through a single 32-bit memory-mapped data interface. Register accesses are word-oriented and use byte addresses.

| Region | Base address | Size | Purpose |
|---|---:|---:|---|
| Boot ROM window | `0x00000000` | `0x400` | Instruction and read-only boot region in the reference top level |
| SRAM | `0x00010000` | `0x1000` | Small on-chip data memory |
| Sensor pipeline | `0x40000000` | `0x100` | Sensor enable, clear, decimation, thresholding, and alert status |
| Neural accelerator | `0x40001000` | `0x100` | 2D Matrix Systolic Array, INT8 operands, bias, ReLU, packed registers, shadow weights |
| Secure boot | `0x40002000` | `0x100` | SHA-256 / FNV-1a verification, eFuse storage, and boot status |
| UART core | `0x40003000` | `0x100` | Full-duplex 8-N-1 UART TX and RX transceiver |
| Energy monitor | `0x40004000` | `0x100` | Activity counters and weighted energy proxy |
| System Timer | `0x40005000` | `0x100` | RISC-V 64-bit real-time counter and comparator |
| Micro-DMA | `0x40006000` | `0x100` | 2-channel autonomous DMA memory engine |

## Sensor pipeline

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0: enable sample acceptance; Bit 1: enable threshold alerts; Bit 2: enable autonomous streaming to neural accelerator |
| `0x04` | RO | Bit 0 reflects the result interrupt pulse |
| `0x08` | WO or RO | Write injects a sample; read returns the latest average |
| `0x0c` | RO | Bit 0 indicates a valid result pulse |
| `0x10` | RW | Filter depth: `0` = 1 sample, `1` = 2 samples, `2` = 4 samples (default) |
| `0x14` | RW | Lower threshold limit (16-bit) |
| `0x18` | RW | Upper threshold limit (16-bit) |
| `0x1c` | RO | Bit 0 reflects current out-of-bounds alert status |

The filter accepts incoming samples and computes an integer average according to the selected decimation depth. When autonomous streaming is enabled, each valid filter output automatically triggers an inference cycle in the neural accelerator.

## Neural accelerator

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0: start computation; Bit 1: clear done; Bit 2: accumulate mode; Bit 3: ReLU mode; Bit 4: bias addition; Bit 5: 4x4 Matrix mode; Bit 6: swap shadow weights |
| `0x04` | RO | Signed 32-bit computation result row 0 |
| `0x08` | RW | Signed 32-bit bias value |
| `0x0c` | RW | 5-bit quantization right-shift amount (`result >>> shift`) |
| `0x10` to `0x1c` | RW | Four individual signed INT8 activation registers |
| `0x20` to `0x2c` | RW | Four individual signed INT8 weight registers (row 0) |
| `0x30` | RW | Packed 4x INT8 activations `{act[3], act[2], act[1], act[0]}` |
| `0x34` | RW | Packed 4x INT8 weights row 0 `{w03, w02, w01, w00}` |
| `0x38` | RW | Packed 4x INT8 weights row 1 `{w13, w12, w11, w10}` |
| `0x3c` | RW | Packed 4x INT8 weights row 2 `{w23, w22, w21, w20}` |
| `0x40` | RW | Packed 4x INT8 weights row 3 `{w33, w32, w31, w30}` |
| `0x44` | RO | Signed 32-bit computation result row 1 |
| `0x48` | RO | Signed 32-bit computation result row 2 |
| `0x4c` | RO | Signed 32-bit computation result row 3 |
| `0x50` | RW | Packed shadow weights row 0 (ping-pong double buffer) |

In Matrix Mode (`Bit 5`), all 16 weights are multiplied with the 4-element activation vector in parallel, evaluating a $4 \times 4$ matrix-vector multiplication in a single step (16 MACs). Zero-skipping dynamically gates multipliers when activations are zero. Shadow weight registers allow ping-pong loading without stalling computation.

## Secure boot

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW or RO | Bit 0: start verification; Bit 1: clear complete; Bit 2: complete; Bit 3: boot release; Bit 4: failure; Bit 5: enable SHA-256 mode |
| `0x04` | RO | Current rolling digest (FNV-1a or lower word of SHA-256) |
| `0x08` | RW | Expected digest lower word |
| `0x0c` | RW | eFuse word index (0..7) |
| `0x10` | RW | eFuse 32-bit data word at selected index |

In SHA-256 mode, the integrated hardware SHA-256 engine hashes the boot image and verifies it against the 256-bit eFuse hash register before asserting boot release.

## UART core (Full-Duplex)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Data register: write transmits TX byte; read retrieves RX byte |
| `0x04` | RO | Status: Bit 0: TX busy; Bit 1: TX done; Bit 2: RX valid; Bit 3: RX overrun |
| `0x08` | RW | Baud rate clock divider |
| `0x0c` | WO | Write Bit 0 to clear RX valid; Bit 1 to clear RX overrun |

## System Timer (`mtime`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | `mtime` lower 32 bits |
| `0x04` | RW | `mtime` upper 32 bits |
| `0x08` | RW | `mtimecmp` lower 32 bits |
| `0x0c` | RW | `mtimecmp` upper 32 bits |

When `mtime >= mtimecmp`, the hardware timer asserts `timer_irq`, directly triggering standard RISC-V timer interrupt handling.

## Micro-DMA controller

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Channel 0 source address |
| `0x04` | RW | Channel 0 destination address |
| `0x08` | RW | Channel 0 word count |
| `0x0c` | RW | Channel 0 control: Bit 0: start; Bit 1: busy; Bit 2: done; Bit 3: auto-restart on sensor event |

## Energy monitor

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Active cycle counter |
| `0x04` | RO | Sensor event counter |
| `0x08` | RO | Accelerator completion counter |
| `0x0c` | RO | Data-bus event counter |
| `0x10` | RO | Weighted activity score |
| `0x14` | WO | Write bit 0 to clear all counters |

## CPU architecture & instruction set

The core implements the **RV32I** integer base ISA along with:
* **RV32M Standard Extension:** Hardware `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`.
* **Machine-Mode CSRs:** `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`, `mcycle`, `minstret`.
* **Privileged Instructions:** `WFI` (Wait-For-Interrupt) and `MRET` (Machine Exception Return).
* **Interrupt Controller:** Direct vectoring to `mtvec` for timer interrupts and external interrupts.
