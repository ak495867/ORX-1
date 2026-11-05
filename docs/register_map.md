# ORX-1 Register Map

ORX-1 exposes peripherals through a single 32-bit memory-mapped data interface. Register accesses are word-oriented and use byte addresses.

| Region | Base address | Size | Purpose |
|---|---:|---:|---|
| Boot ROM window | `0x00000000` | `0x400` | Instruction and read-only boot region in the reference top level |
| SRAM | `0x00010000` | `0x1000` | Small on-chip data memory |
| Sensor pipeline | `0x40000000` | `0x100` | Sensor enable, clear, decimation, thresholding, and alert status |
| Neural accelerator | `0x40001000` | `0x100` | INT8 operands, bias, ReLU, packed registers, and control |
| Secure boot | `0x40002000` | `0x100` | Digest expectation, start control, and boot status |
| UART transmitter | `0x40003000` | `0x100` | Hardware 8-N-1 UART TX transmitter |
| Energy monitor | `0x40004000` | `0x100` | Activity counters and weighted energy proxy |

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
| `0x00` | RW | Bit 0: start computation; Bit 1: clear done; Bit 2: accumulate mode; Bit 3: ReLU mode; Bit 4: bias addition |
| `0x04` | RO | Signed 32-bit computation result |
| `0x08` | RW | Signed 32-bit bias value |
| `0x0c` | RW | 5-bit quantization right-shift amount (`result >>> shift`) |
| `0x10` to `0x1c` | RW | Four individual signed INT8 activation registers |
| `0x20` to `0x2c` | RW | Four individual signed INT8 weight registers |
| `0x30` | RW | Packed 4x INT8 activations `{act[3], act[2], act[1], act[0]}` |
| `0x34` | RW | Packed 4x INT8 weights `{wt[3], wt[2], wt[1], wt[0]}` |

The accelerator executes a dot product over four INT8 activation/weight pairs. With packed registers, an entire 4-element vector is loaded in a single bus transaction. When enabled, bias addition, accumulation, quantization shift, and ReLU clipping are evaluated in a single step.

## Secure boot

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW or RO | Bit 0 starts verification; bit 1 clears complete; bit 2 indicates complete; bit 3 indicates boot release; bit 4 indicates failure |
| `0x04` | RO | Current rolling digest |
| `0x08` | RW | Expected digest |

The controller streams words from `boot_rom` and calculates an FNV-1a rolling digest. A match releases the boot signal; a mismatch signals failure.

## UART transmitter

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | TX payload byte (write initiates 8-N-1 serial frame transmission) |
| `0x04` | RO | Bit 0 indicates transmitter busy; Bit 1 indicates last transmission done |
| `0x08` | RW | Baud rate clock divider (cycles per bit period, default 16) |

The transmitter drives the top-level `uart_tx` serial pin at the configured baud rate.

## Energy monitor

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Active cycle counter |
| `0x04` | RO | Sensor event counter |
| `0x08` | RO | Accelerator completion counter |
| `0x0c` | RO | Data-bus event counter |
| `0x10` | RO | Weighted activity score |
| `0x14` | WO | Write bit 0 to clear all counters |

The weighted activity score is an RTL-observable proxy for end-to-end energy accounting.

## CPU performance counters

The cycle-accurate CPU counters are exposed through the energy-monitor window. They count clock cycles, retired instructions, completed loads, completed stores, branch instructions, accepted data-bus requests, and cycles spent waiting for a response.

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x18` | RO | CPU cycle counter |
| `0x1c` | RO | Retired instruction counter |
| `0x20` | RO | Completed load counter |
| `0x24` | RO | Completed store counter |
| `0x28` | RO | Branch instruction counter |
| `0x2c` | RO | Accepted CPU data-bus request counter |
| `0x30` | RO | CPU response-wait cycle counter |

The core additionally implements the standard RISC-V `WFI` instruction (`32'h10500073`), halting the core pipeline in a low-power wait state until an interrupt occurs.
