# ORX-1 Register Map

ORX-1 exposes peripherals through a single 32-bit memory-mapped data interface. Register accesses are word-oriented and use byte addresses.

| Region | Base address | Size | Purpose |
|---|---:|---:|---|
| Boot ROM window | `0x00000000` | `0x400` | Instruction and read-only boot region in the reference top level |
| SRAM | `0x00010000` | `0x1000` | Small on-chip data memory |
| Sensor pipeline | `0x40000000` | `0x100` | Sensor enable, clear, result, and interrupt status |
| Neural accelerator | `0x40001000` | `0x100` | INT8 operands, control, result, and completion status |
| Secure boot | `0x40002000` | `0x100` | Digest expectation, start control, and boot status |
| UART placeholder | `0x40003000` | `0x100` | Reserved integration window |
| Energy monitor | `0x40004000` | `0x100` | Activity counters and weighted energy proxy |

## Sensor pipeline

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0 enables sample acceptance |
| `0x04` | RO | Bit 0 reflects the result interrupt pulse |
| `0x08` | WO or RO | Write injects a sample; read returns the latest average |
| `0x0c` | RO | Bit 0 indicates a valid result pulse |

The reference filter accepts four samples and emits the integer average when the fourth sample is accepted. An external sample may also be supplied through the top-level sensor interface.

## Neural accelerator

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW | Bit 0 starts a dot product; bit 1 clears done |
| `0x04` | RO | Signed 32-bit result |
| `0x10` to `0x1c` | RW | Four signed INT8 activation registers |
| `0x20` to `0x2c` | RW | Four signed INT8 weight registers |

The accelerator computes `a0*w0 + a1*w1 + a2*w2 + a3*w3`. Start acceptance is followed by a one-cycle busy interval and a completion interrupt pulse.

## Secure boot

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RW or RO | Bit 0 starts verification; bit 1 clears complete; bit 2 indicates complete; bit 3 indicates boot release; bit 4 indicates failure |
| `0x04` | RO | Current rolling digest |
| `0x08` | RW | Expected digest |

The supplied reference top level drives a deterministic zero-word boot image into the controller. The digest mechanism is intentionally a compact integration primitive rather than a production cryptographic implementation. A production derivative should replace it with a reviewed cryptographic hash and an immutable trust anchor.

## Energy monitor

| Offset | Access | Meaning |
|---:|:---:|---|
| `0x00` | RO | Active cycle counter |
| `0x04` | RO | Sensor event counter |
| `0x08` | RO | Accelerator completion counter |
| `0x0c` | RO | Data-bus event counter |
| `0x10` | RO | Weighted activity score |
| `0x14` | WO | Write bit 0 to clear all counters |

The weighted activity score is an RTL-observable proxy for end-to-end energy accounting. It is not a measured electrical power value and must not be used as a silicon power claim.
