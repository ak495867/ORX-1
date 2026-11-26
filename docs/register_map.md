# ORX-1 Register Map

ORX-1 exposes peripherals through a single 32-bit memory-mapped data interface. Register accesses are word-oriented and use byte addresses.

| Region | Base address | Size | Purpose |
|---|---:|---:|---|
| Boot ROM window | `0x00000000` | `0x400` | Instruction and read-only boot region in the reference top level |
| SRAM | `0x00010000` | `0x2000` | 8 KiB on-chip data and instruction memory |
| Sensor pipeline | `0x40000000` | `0x100` | Sensor enable, clear, decimation, thresholding, and alert status |
| Neural accelerator | `0x40001000` | `0x100` | 4x4 INT8 MAC array, bias, ReLU, clamp, anomaly threshold, shadow weights |
| Secure boot | `0x40002000` | `0x100` | Multi-block SHA-256 / FNV-1a verification, lockable eFuse storage, boot status |
| UART core | `0x40003000` | `0x100` | Full-duplex 8-N-1 UART TX and RX transceiver with 8-byte FIFOs |
| Energy monitor | `0x40004000` | `0x100` | Activity, sleep/active cycle counters, and weighted energy proxy |
| System Timer | `0x40005000` | `0x100` | RISC-V 64-bit real-time counter and comparator |
| Micro-DMA | `0x40006000` | `0x100` | 2-channel autonomous DMA memory and peripheral-streaming engine |
| CORDIC Coprocessor | `0x40007000` | `0x100` | 16-stage vector rotation and magnitude engine |
| Interrupt Controller | `0x40008000` | `0x100` | Maskable external peripheral interrupt controller |
| GPIO Controller | `0x40009000` | `0x100` | 16-pin bidirectional GPIO with rising-edge interrupts |
| SPI Master | `0x4000A000` | `0x100` | Configurable SPI Mode 0-3 master for external Flash/sensors |
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

## Neural accelerator

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Write Bit 0: start; Bit 1: clear done; Bit 2: accumulate; Bit 3: ReLU; Bit 4: bias; Bit 5: 4x4 Matrix; Bit 6: swap shadow weights; Bit 7: 2:4 Sparsity; Bit 8: INT8 clamp (`[-128,127]`); Bit 9: anomaly-threshold IRQ filter. Read Bit 0: busy; Bit 1: done; Bits 9:2: config flags |
| `0x04` | RO | Signed 32-bit computation result row 0 |
| `0x08` | RW | Signed 32-bit bias value row 0 |
| `0x0c` | RW | 5-bit quantization right-shift amount (`result >>> shift`) |
| `0x10` to `0x1c` | RW | Four individual signed INT8 activation registers |
| `0x20` to `0x2c` | RW | Four individual signed INT8 weight registers (row 0) |
| `0x30` | RW | Packed 4x INT8 activations `{act[3], act[2], act[1], act[0]}` |
| `0x34` to `0x40` | RW | Packed 4x INT8 weights rows 0..3 |
| `0x44` to `0x4c` | RO | Signed 32-bit computation results rows 1..3 |
| `0x50` to `0x5c` | RW | Packed shadow weights rows 0..3 (ping-pong double buffer) |
| `0x60` to `0x68` | RW | Signed 32-bit bias values rows 1..3 |
| `0x6c` | RW | Signed 32-bit anomaly threshold for IRQ filtering (`result >= threshold`) |

## Secure boot

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW or RO | Bit 0: start; Bit 1: clear complete; Bit 2: complete; Bit 3: boot release; Bit 4: failure; Bit 5: SHA-256 mode; Bit 6: sticky eFuse lock |
| `0x04` | RO | Current rolling digest (FNV-1a or lower word of SHA-256) |
| `0x08` | RW | Expected digest lower word |
| `0x0c` | RW | eFuse word index (0..7) |
| `0x10` | RW | eFuse 32-bit data word at selected index (ignored when locked) |
| `0x14` | RW | Image word count (`1..256`, defaults to `WORDS`) |

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

## CORDIC Coprocessor

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
| `0x00` | RW | Bit 0: CPU hold reset (host-writable); Bit 1: hardware boot-gate enable (host-writable); Bit 2: WDT reset occurred flag (W1C) |
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

The core implements the **RV32I** integer base ISA along with:
* **RV32M Standard Extension:** Shared 33x33 multiplier (`MUL`, `MULH`, `MULHSU`, `MULHU`) and 32-cycle sequential restoring divider (`DIV`, `DIVU`, `REM`, `REMU`).
* **Machine-Mode CSRs:** `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`, `mcycle`, `minstret`.
* **Privileged & Exception Handling:** `WFI` (Wait-For-Interrupt with `core_sleep`), `MRET`, `ECALL`, `EBREAK`, `FENCE`, and misaligned/bus-fault vectoring.
