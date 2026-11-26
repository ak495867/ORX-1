# ORX-1 Register Map

ORX-1 exposes peripherals through a 32-bit Wishbone B4 memory-mapped data fabric (`4` masters x `14` slaves). Register accesses are word-oriented and use byte addresses.

| Region | Base address | Size | Purpose |
|---|---:|---:|---|
| Boot ROM window | `0x00000000` | `0x400` | Instruction and read-only boot region in the reference top level |
| SRAM | `0x00010000` | `0x4000` | `16 KiB` on-chip data and instruction memory (`8` x `2 KiB` OpenRAM banks under `USE_OPENRAM`) |
| Sensor pipeline | `0x40000000` | `0x100` | Sensor enable, clear, decimation, PADS, thresholding, and alert status |
| Neural accelerator | `0x40001000` | `0x100` | 64-MAC `8x8` INT8 NPU, bias, ReLU, clamp, packed results, shadow weights, and Tensor-DMA engine |
| Secure boot | `0x40002000` | `0x100` | Multi-block SHA-256 / FNV-1a verification, lockable eFuse storage, boot status |
| UART core | `0x40003000` | `0x100` | Full-duplex 8-N-1 UART TX and RX transceiver with 8-byte FIFOs |
| Energy monitor | `0x40004000` | `0x100` | Activity, sleep/active cycle counters, CPU perf counters, and weighted energy proxy |
| System Timer | `0x40005000` | `0x100` | RISC-V 64-bit real-time counter and comparator |
| Micro-DMA | `0x40006000` | `0x100` | Zero-bubble 2-channel autonomous DMA memory and peripheral-streaming engine |
| CORDIC Coprocessor | `0x40007000` | `0x100` | 2x/cycle unrolled (8-cycle) 16-step vector rotation and magnitude engine |
| Interrupt Controller | `0x40008000` | `0x100` | Maskable external peripheral interrupt controller |
| GPIO Controller | `0x40009000` | `0x100` | 16-pin bidirectional GPIO with rising-edge interrupts |
| SPI Master | `0x4000A000` | `0x100` | Configurable SPI Mode 0–3 master for external Flash/sensors |
| System Control / WDT | `0x4000B000` | `0x100` | Host CPU boot-hold/boot-gate control and hardware watchdog timer |

## Sensor pipeline

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0: enable sample acceptance; Bit 1: enable threshold alerts; Bit 2: enable autonomous streaming to neural accelerator |
| `0x04` | RO | Bit 0 reflects the result interrupt pulse |
| `0x08` | WO or RO | Write injects a sample; read returns the latest average |
| `0x0c` | RO | Bit 0 indicates a valid result pulse |
| `0x10` | RW | Filter depth: `0` = 1 sample, `1` = 2 samples, `2` = 4 samples (default), `3` = Predictive Adaptive Delta-Stream (PADS) mode |
| `0x14` | RW | Lower threshold limit (16-bit) |
| `0x18` | RW | Upper threshold limit (16-bit) |
| `0x1c` | RO | Bit 0 reflects current out-of-bounds alert status |

## Neural accelerator (`8x8` INT8 NPU + Tensor-DMA)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Write Bit 0: start; Bit 1: clear done; Bit 2: accumulate; Bit 3: ReLU; Bit 4: bias; Bit 5: 4x4 matrix; Bit 6: swap 4x4 shadow weights; Bit 7: 2:4 sparsity; Bit 8: INT8 clamp (`[-128,127]`); Bit 9: anomaly-threshold IRQ filter; Bit 10: wide 8x8 mode (`64` MACs). Read Bit 0: busy; Bit 1: done; Bits 9:2: config flags (`[6]=0`); Bit 10: `cfg_8x8`; Bit 11: `tdma_busy` |
| `0x04` | RO | Signed 32-bit computation result row 0 |
| `0x08` | RW | Signed 32-bit bias value row 0 |
| `0x0c` | RW | 5-bit quantization right-shift amount (`result >>> shift`) |
| `0x10` to `0x1c` | RW | Four individual signed INT8 activation registers (`act[0..3]`) |
| `0x20` to `0x2c` | RW | Four individual signed INT8 weight registers (row 0 cols 0..3) |
| `0x30` | RW | Packed 4x INT8 activations `{act[3], act[2], act[1], act[0]}` |
| `0x34` to `0x40` | RW | Packed 4x INT8 weights rows 0..3 cols 0..3 |
| `0x44` to `0x4c` | RO | Signed 32-bit computation results rows 1..3 |
| `0x50` to `0x5c` | RW | Packed 4x4 shadow weights rows 0..3 (ping-pong double buffer) |
| `0x60` to `0x68` | RW | Signed 32-bit bias values rows 1..3 |
| `0x6c` | RW | Signed 32-bit anomaly threshold for IRQ filtering (`result >= threshold`) |
| `0x70` | RO | `ACCEL_RESULT_PACKED`: clamped 4x INT8 results `{sat_s8(r3), sat_s8(r2), sat_s8(r1), sat_s8(r0)}` |
| `0x74` | RW | `ACCEL_ACT_HI_PACKED`: packed high 4x INT8 activations `{act[7], act[6], act[5], act[4]}` |
| `0x78` to `0x84` | RW | `ACCEL_W_HI_ROW0..3`: packed INT8 weights rows 0..3 cols 4..7 |
| `0x88` to `0x94` | RW | `ACCEL_W_ROW4..7`: packed INT8 weights rows 4..7 cols 0..3 |
| `0x98` to `0xa4` | RW | `ACCEL_W_HI_ROW4..7`: packed INT8 weights rows 4..7 cols 4..7 |
| `0xa8` to `0xb4` | RW | `ACCEL_BIAS_4..7`: signed 32-bit bias values rows 4..7 |
| `0xb8` to `0xc4` | RO | `ACCEL_RESULT_4..7`: signed 32-bit computation results rows 4..7 |
| `0xc8` | RO | `ACCEL_RESULT_HI_PACKED`: clamped 4x INT8 results `{sat_s8(r7), sat_s8(r6), sat_s8(r5), sat_s8(r4)}` |
| `0xcc` | RW | `ACCEL_TDMA_ACT_BASE`: activation tensor SRAM byte address (packed INT8) |
| `0xd0` | RW | `ACCEL_TDMA_W_BASE`: weight tensor SRAM byte address (`4`-byte words per k-chunk) |
| `0xd4` | RW | `ACCEL_TDMA_BIAS_BASE`: `int32_t` bias vector SRAM byte address |
| `0xd8` | RW | `ACCEL_TDMA_DST_BASE`: destination packed-INT8 output tensor SRAM byte address |
| `0xdc` | RW | `ACCEL_TDMA_SHAPE`: `[4:0] k_words` (groups of 4 input features, min 1); `[10:8] out_tiles` (min 1); `[23:16] batch_cnt` (min 1) |
| `0xe0` | RW | `ACCEL_TDMA_CTRL`: Write Bit 0 start; Bit 1 clear `tdma_done`; Bit 2 weight-stationary cache (`ws`, reuses weights when `k_words<=2` and `out_tiles==1`); Bit 3 ReLU; Bit 4 bias enable; Bit 5 INT8 clamp; `[10:6]` shift; Bit 11 `mode_8out` (`8` rows vs `4` rows). Read Bit 0 `tdma_busy`, Bit 1 `tdma_done`, `[11:2]` config |

## Secure boot

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW or RO | Write Bit 0: start; Bit 1: clear complete; Bit 5: SHA-256 mode; Bit 6: sticky eFuse lock; Bit 7: SRAM image source (`0` = Boot ROM, `1` = SRAM). Read Bit 0: running; Bit 1: complete; Bit 2: boot release; Bit 3: failure; Bit 4: SHA-256 mode; Bit 5: eFuse lock; Bit 7: SRAM image source |
| `0x04` | RO | Current rolling digest (FNV-1a or lower word of SHA-256) |
| `0x08` | RW | Expected digest lower word |
| `0x0c` | RW | eFuse / digest word index (`0..7`) |
| `0x10` | RW | eFuse 32-bit data word at selected index (ignored when locked) |
| `0x14` | RW | Image word count (`1..2048`, up to `8 KiB` verified image; defaults to `WORDS`) |
| `0x18` | RO | SHA-256 digest word at selected index `0..7` (`efuse_idx`) |

## UART core (Full-Duplex with 8-byte FIFOs)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Write pushes TX FIFO byte; read pops RX FIFO byte |
| `0x04` | RO | Bit 0: TX FIFO full; Bit 1: TX done; Bit 2: RX valid; Bit 3: RX overrun; Bit 4: TX shifter busy; Bit 5: TX FIFO empty; Bit 6: RX FIFO full |
| `0x08` | RW | Baud rate clock divider |
| `0x0c` | WO | Write Bit 0 to flush RX FIFO; Bit 1 to clear RX overrun; Bit 2 to clear TX done |
| `0x10` | RW | Interrupt enable: Bit 0: RX valid IRQ enable; Bit 1: TX done IRQ enable |

## System Timer (`mtime`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | `mtime` lower 32 bits |
| `0x04` | RW | `mtime` upper 32 bits |
| `0x08` | RW | `mtimecmp` lower 32 bits |
| `0x0c` | RW | `mtimecmp` upper 32 bits |

## Micro-DMA controller (2-Channel)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` / `0x10` | RW | Channel 0 / Channel 1 source address |
| `0x04` / `0x14` | RW | Channel 0 / Channel 1 destination address |
| `0x08` / `0x18` | RW | Channel 0 / Channel 1 word count |
| `0x0c` / `0x1c` | RW | Channel control: Write Bit 0: start; Bit 1: clear done; Bit 3: auto-restart on sensor event; Bit 4: fixed source addr; Bit 5: fixed dest addr. Read Bit 1: busy; Bit 2: done; Bit 3: auto-restart; Bits 5:4: fixed addr flags |

## CORDIC Coprocessor (2x/cycle Unrolled)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Write Bit 0: mode (0 = vectoring, 1 = rotation); Bit 1: clear done; Bit 2: start. Read Bit 0: mode; Bit 1: busy; Bit 2: done; Bit 3: IRQ |
| `0x04` | RW | 32-bit signed X coordinate / vector component |
| `0x08` | RW | 32-bit signed Y coordinate / vector component |
| `0x0c` | RW | 32-bit signed Z angle register |
| `0x10` | RO | 32-bit scaled magnitude output |

## Interrupt Controller (`irq_ctrl`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Raw pending IRQ sources: Bit 0: sensor; Bit 1: accel; Bit 2: sensor alert / GPIO; Bit 3: UART; Bit 4: DMA; Bit 5: CORDIC / SPI |
| `0x04` | RW | Interrupt enable bitmask (resets to `0`) |
| `0x08` | RO | Active masked IRQ status (`pending & enable`) |

## GPIO Controller (`gpio_ctrl`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Synchronized 16-bit GPIO input state |
| `0x04` | RW | 16-bit GPIO output value |
| `0x08` | RW | 16-bit GPIO output enable (`1` = output) |
| `0x0c` | RW | 16-bit rising-edge interrupt enable |
| `0x10` | RW | 16-bit pending edge IRQ flags (write `1` to clear) |

## SPI Master (`spi_master`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0: start; Bit 1: busy (RO); Bit 2: done (W1C); Bit 3: CS active (`spi_cs_n = 0`); Bit 4: CPOL; Bit 5: CPHA; Bit 6: 32-bit transfer (`0` = 8-bit) |
| `0x04` | RW | TX shift payload |
| `0x08` | RO | RX captured payload |
| `0x0c` | RW | Half-period SPI clock divider |

## System Control & Watchdog (`sys_ctrl`)

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0: CPU hold reset (host-writable); Bit 1: hardware boot-gate enable (host-writable); Bit 2: WDT reset occurred flag (W1C); Bit 3: Wishbone host unmapped/error flag (W1C) |
| `0x04` | RW | Watchdog countdown reload value |
| `0x08` | RW | Bit 0: enable WDT; Bit 1 (WO): kick/reload counter |
| `0x0c` | RO | Current watchdog countdown value |

## Energy monitor

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Total cycle counter |
| `0x04` | RO | Sensor event counter |
| `0x08` | RO | Accelerator completion counter |
| `0x0c` | RO | Data-bus event counter |
| `0x10` | RO | Weighted dynamic activity score |
| `0x14` | WO | Write bit 0 to clear all counters |
| `0x18` to `0x30` | RO | CPU performance counters (`cycles`, `instructions`, `loads`, `stores`, `branches`, `bus_requests`, `wait_cycles`) |
| `0x34` | RO | Active (non-sleep) cycle counter |
| `0x38` | RO | `WFI` sleep cycle counter |

## CPU architecture & instruction set

[`rtl/rv32i_core.sv`](../rtl/rv32i_core.sv) implements a **2-stage IF/EX pipeline** (with an 8-entry direct-mapped Branch Target Buffer and non-blocking posted store overlap) over the **RV32I** base ISA plus:

* **RV32M Standard Extension:** Shared 33x33 single-cycle multiplier (`MUL`, `MULH`, `MULHSU`, `MULHU`) and 16-cycle Radix-4 divider (`DIV`, `DIVU`, `REM`, `REMU`).
* **`OP_CUSTOM0` (`0b0001011`, `funct7 = 7'b0000000`) INT8 SIMD Instructions:**
  * `ORX.DOT4` (`funct3 = 3'b000`): Signed 4-lane INT8 dot product of packed 32-bit `rs1` and `rs2` into `rd`.
  * `ORX.CLIP8` (`funct3 = 3'b001`): Arithmetic right-shift `rs1 >>> rs2[4:0]`, optional ReLU (`rs2[5] = 1`), and signed INT8 saturation to `[-128, 127]`.
  * `ORX.PACK4` (`funct3 = 3'b010`): Shifts `rs1` right by 8 bits and inserts `rs2[7:0]` at bits `[31:24]`.
* **Machine-Mode CSRs:** `mstatus` (`0x300`), `misa` (`0x301` = `0x40001100`), `mie` (`0x304`), `mtvec` (`0x305`), `mepc` (`0x341`), `mcause` (`0x342`), `mip` (`0x344`), 64-bit `mcycle`/`mcycleh` (`0xb00`/`0xb80` & `0xc00`/`0xc80`), `minstret`/`minstreth` (`0xb02`/`0xb82` & `0xc02`/`0xc82`), and `mhartid` (`0xf14`).
* **Privileged & Exception Handling:** `WFI` (Wait-For-Interrupt with `core_sleep`), `MRET`, `ECALL`, `EBREAK`, `FENCE`, and synchronous exception trapping (`mcause = 0, 2, 3, 4, 5, 6, 7, 11` via `mtvec`, halting in `TRAP` only if `mtvec == 0`). Unsupported `OP_CUSTOM0` encodings trap with `mcause = 2`.
