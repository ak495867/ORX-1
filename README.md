# ORX-1

## Edge-AI SoC Reference Design (RV32IM + INT8 Neural Accelerator + Formal Contracts)

ORX-1 is a compact, open SystemVerilog reference SoC for autonomous sensing and low-power TinyML inference at the edge. It integrates an **RV32IM** control core with machine-mode interrupts and `WFI` sleep, an autonomous sensor-to-NPU pipeline with predictive delta streaming, a 4x4 signed INT8 neural accelerator supporting 2:4 structured sparsity and shadow weights, a multi-block SHA-256 / FNV-1a secure-boot engine, a 3-master x 14-slave Wishbone B4 crossbar, hardware DMA and CORDIC engines, formal interface properties, and RTL activity counters for reproducible energy-proxy benchmarking.

The project is scoped as an open, synthesizable reference architecture for RTL simulation, linting, formal verification, and OpenLane 2 / Caravel exploration. Physical tapeout signoff and calibrated silicon power measurements require target PDK signoff flows.

> ORX-1 makes the control, autonomous sensing, neural inference, boot integrity, and verification boundaries explicit in a compact codebase with reproducible RTL and C benchmarks.

## Repository status

| Area | Current state | Scope of the reference implementation |
|---|---|---|
| Control core (`rv32i_core`) | Implemented | RV32IM ISA (`MUL`/`DIV`/`REM`), machine-mode CSRs, `WFI` sleep (`core_sleep`), `MRET`, external/timer interrupts, misaligned/bus fault traps |
| On-chip memory (`boot_rom`, `sram_sp`) | Implemented | `1 KiB` boot ROM window (`0x00000000`–`0x000003FF`) + `8 KiB` single-port SRAM (`0x00010000`–`0x00011FFF`), both executable for instruction fetch |
| Interconnect (`wb_interconnect`) | Implemented | 3-master (CPU, 2-ch Micro-DMA, external WB host) x 14-slave Wishbone B4 crossbar |
| Sensor pipeline (`sensor_pipeline`) | Implemented | Depth 1/2/4 moving average + Predictive Adaptive Delta-Stream (PADS) mode, low/high thresholds, and direct auto-inference trigger |
| Neural accelerator (`neural_accel`) | Implemented | 4x4 INT8 MAC array, multi-tile accumulation, bias add, shift, fused ReLU, INT8 clamp, 2:4 sparsity, shadow weight swap, threshold IRQ filter |
| Secure boot (`secure_boot`, `sha256_engine`) | Implemented | Multi-block SHA-256 and FNV-1a verification over boot ROM words, lockable 256-bit eFuse words, explicit `boot_release` and `fail` states |
| Peripherals | Implemented | 8-byte FIFO 8-N-1 UART, 64-bit `mtime`/`mtimecmp`, 2-ch Micro-DMA, 16-stage CORDIC, 6-source IRQ controller, 16-pin GPIO, SPI master, System Control / WDT |
| Energy accounting (`energy_monitor`) | Implemented | Cycle, sensor, accelerator, data-bus, CPU performance, active/sleep cycle, and weighted activity counters |
| Formal checks (`formal/`) | Included | `interface_sva.sv` bind assertions + SymbiYosys Z3 bounded harnesses (`cpu_bus.sby`, `wb_xbar.sby`) |
| Bare-metal C & TinyML SDK (`sw/`) | Implemented | HAL register definitions, tiled dense + 2:4 sparse INT8 inference API, host regression (`test_tinyml`), and multi-layer benchmark (`bench_models`) |
| Physical implementation (`openlane/`) | Scaffolded | OpenLane configs targeting 50 MHz SkyWater 130nm (`sky130_fd_sc_hd`) and Caravel wrapper; post-layout tapeout signoff not claimed |

## Architecture

```mermaid
flowchart LR
  S["Sensor Stream"] --> P["Sensor Pipeline (Moving Avg + PADS)"]
  P -->|"Auto-Trigger"| A["4x4 INT8 Neural Accelerator (Sparse + Shadow)"]
  C["RV32IM Core (CSR + WFI + MRET)"] --> M["3x14 Wishbone B4 Crossbar"]
  D["2-Ch Micro-DMA"] --> M
  H["External WB Host"] --> M
  M --> R["Boot ROM (1 KiB) + SRAM (8 KiB)"]
  M --> P
  M --> A
  M --> B["Secure Boot + SHA-256 + eFuse"]
  M --> E["Energy & Sleep Monitor"]
  M --> IO["UART / Timer / CORDIC / IRQ / GPIO / SPI / WDT"]
  F["Formal SVA & SBY Harnesses"] -.-> M
```

1. **Zero-CPU Autonomous Sensing (`WFI` Wake-on-Anomaly)**: When enabled, [`rtl/sensor_pipeline.sv`](rtl/sensor_pipeline.sv) pushes samples directly to [`rtl/neural_accel.sv`](rtl/neural_accel.sv) while [`rtl/rv32i_core.sv`](rtl/rv32i_core.sv) sleeps in `WFI` (`core_sleep = 1`). With `cfg_thresh_irq` enabled, NPU completions below `anomaly_thresh` are absorbed silently without waking the core, asserting `irq` only on threshold crossings.
2. **RV32IM & Dual-Region Instruction Fetch**: [`rtl/orx1_soc.sv`](rtl/orx1_soc.sv) fetches instructions from either the `1 KiB` boot ROM (`0x00000000`–`0x000003FF`, default zeroed unless `BOOT_HEX` or host WB writes populate it) or the `8 KiB` SRAM (`0x00010000`–`0x00011FFF`). The CPU supports RV32I + M extension (`MUL*` via shared 33x33 multiplier, 32-cycle `DIV*`/`REM*`), `mstatus`/`mie`/`mtvec`/`mepc`/`mcause`/`mip`/`mcycle`/`minstret`, `WFI`, and `MRET`.
3. **Hardware Security & System Control**: [`rtl/secure_boot.sv`](rtl/secure_boot.sv) supports multi-block SHA-256 (via [`rtl/sha256_engine.sv`](rtl/sha256_engine.sv)) or rolling FNV-1a verification against lockable eFuse registers, while [`rtl/sys_ctrl.sv`](rtl/sys_ctrl.sv) provides host boot-gate/CPU-hold control and a hardware watchdog timer.

## Memory map

| Slave | Region | Base address | Size | Function |
|---:|---|---:|---:|---|
| 0 | Boot ROM window | `0x00000000` | `0x400` | Read-only boot window (host-writable over WB Master 2 when unlocked) |
| 1 | SRAM (`sram_sp`) | `0x00010000` | `0x2000` | `8 KiB` single-port data and executable instruction memory |
| 2 | Sensor pipeline | `0x40000000` | `0x100` | Sample inject, filter depth (`0..3` incl. PADS), thresholds, auto-infer enable |
| 3 | Neural accelerator | `0x40001000` | `0x100` | 4x4 INT8 operands, shift/bias/ReLU/clamp/accum/sparse/shadow/threshold CSRs |
| 4 | Secure boot | `0x40002000` | `0x100` | Multi-block SHA-256 / FNV-1a verification control and lockable eFuse words |
| 5 | UART core | `0x40003000` | `0x100` | Full-duplex 8-N-1 UART with 8-byte TX/RX FIFOs and IRQ masks |
| 6 | Energy monitor | `0x40004000` | `0x100` | Total/active/`WFI`-sleep cycles, CPU perf counters, and weighted activity proxy |
| 7 | System Timer | `0x40005000` | `0x100` | RISC-V 64-bit real-time counter (`mtime` / `mtimecmp`) |
| 8 | Micro-DMA | `0x40006000` | `0x100` | 2-channel autonomous DMA (`auto-restart`, `src_fixed`/`dst_fixed`) |
| 9 | CORDIC coprocessor | `0x40007000` | `0x100` | 16-stage vectoring magnitude and rotation engine |
| 10 | Interrupt controller | `0x40008000` | `0x100` | 6-source maskable peripheral IRQ aggregator (`sensor`, `accel`, `alert/gpio`, `uart`, `dma`, `cordic/spi`) |
| 11 | GPIO controller | `0x40009000` | `0x100` | 16-pin bidirectional GPIO with rising-edge interrupts |
| 12 | SPI master | `0x4000A000` | `0x100` | Configurable SPI Mode 0–3 master (`8`/`32`-bit transfers) |
| 13 | System control / WDT | `0x4000B000` | `0x100` | Host CPU boot-hold/boot-gate control and hardware watchdog timer |

Complete register definitions and bitfields are documented in [`docs/register_map.md`](docs/register_map.md) and [`docs/bus.md`](docs/bus.md).

## Model & speed benchmarks

### Hardware RTL simulation (`tb/tb_model_bench.sv` @ 50 MHz)

[`tb/tb_model_bench.sv`](tb/tb_model_bench.sv) boots via a 2-word `boot_rom` trampoline into `0x00011000` SRAM (`276/1024` words), executes real quantized INT8 neural workloads and peripheral kernels on `orx1_soc`, checks outputs against golden references, and logs cycle, instruction, sleep, and `energy_monitor` counters (`MODEL_BENCH_PASS total_cycles=1856`):

| Workload | Cycles | Instr | CPI | Latency @ 50MHz | Throughput (`inf/s`) | MACs | MAC/cyc | MOPS @ 50MHz | Accel Events | Sleep Cyc | Wakeups | Weighted Energy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `cpu_mlp_4x4` | 302 | 207 | 1.46 | 6.04 us | 165,563 | 16 | 0.05 | 5.3 | 0 | 0 | 0 | 502 |
| `npu_mlp_4x4` | 103 | 46 | 2.24 | 2.06 us | 485,437 | 16 | 0.16 | 15.5 | 1 | 0 | 0 | 267 |
| `npu_mlp_8x4x4_x4` | 773 | 390 | 1.98 | 15.46 us | 64,683 | 192 | 0.25 | 24.8 | 12 | 0 | 0 | 1965 |
| `npu_sparse_2_4` | 102 | 45 | 2.27 | 2.04 us | 490,196 | 8 | 0.08 | 7.8 | 1 | 0 | 0 | 266 |
| `dma_burst_16w` | 125 | 72 | 1.74 | 2.50 us | 400,000 | — | 0.00 | 0.0 | 0 | 0 | 0 | 377 |
| `cordic_vec_mag` | 64 | 37 | 1.73 | 1.28 us | 781,250 | — | 0.00 | 0.0 | 0 | 0 | 0 | 148 |
| `auto_stream_wfi` | 187 | 42 | 4.45 | 3.74 us | 267,380 | 68 | 0.36 | 36.4 | 1 | 117 | 1 | 200 |

- **4x4 Dense INT8 Layer + ReLU + Clamp (`npu_mlp_4x4` vs `cpu_mlp_4x4`)**: **2.93x speedup** (`103` vs `302` cycles) and **1.88x lower weighted energy counter** (`267` vs `502`).
- **Multi-layer 2-Tile MLP (`npu_mlp_8x4x4_x4`)**: 4 samples of `8->4->4` (`192` MACs) using hardware `cfg_accum` achieve **24.8 MOPS** @ 50 MHz (`3.87 us/sample`) with bit-exact match against the testbench golden reference.
- **Autonomous Streaming (`auto_stream_wfi`)**: `rv32i_core` stays asleep in `WFI` for `117` cycles across `16` benign sensor pushes (`16'h0505`) with zero spurious wakeups and wakes once (`wake=1`, `accel=1`) when `16'h5050` crosses `anomaly_thresh = 100`.

### Host C TinyML SDK benchmark (`sw/tests/bench_models.c`)

[`sw/tests/bench_models.c`](sw/tests/bench_models.c) compiles [`sw/tinyml/tinyml.c`](sw/tinyml/tinyml.c) with `-O2 -Wall -Wextra -Werror -DORX1_HOST_TEST` against an exact register-level `orx1_host_reg` model of `neural_accel`, verifying multi-tile accumulation and 2:4 sparse weight indexing bit-for-bit against a pure-C reference (`ref_dense`) and measuring host SDK execution throughput (`BENCH_MODELS_PASS`):

| Model | Inferences | MACs/Inf | NPU Calls | Host API Time | Host `inf/s` | Host MOPS | Pure-C `ref_t` | Logit Match | Argmax Match |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `mlp_8x4x4` | 1,600,000 | 48 | 4,800,000 | 0.349s | 4,584,527 | 440.1 | 0.006s | 64/64 | 16/16 |
| `mlp_16x8x4` | 800,000 | 160 | 8,000,000 | 0.500s | 1,600,000 | 512.0 | 0.024s | 64/64 | 16/16 |
| `sparse_2_4_16x4` | 1,600,000 | 32 | 6,400,000 | 0.345s | 4,637,681 | 296.8 | 0.006s | 64/64 | N/A |

*(Host C timings reflect running the `tinyml.c` HAL + register emulator on the host CPU and are complementary to the cycle-accurate RTL SoC table above.)*

## Verification strategy

ORX-1 uses layered verification across unit, SoC, software, compliance, lint/synthesis, and formal checks:

- **C Host SDK & Model Suites**: `test_tinyml.c` (`SW_TINYML_TEST_PASS`) and `bench_models.c` (`BENCH_MODELS_PASS`).
- **RTL Simulation Suite (`iverilog` + `vvp`)**:
  - [`tb/tb_orx1.sv`](tb/tb_orx1.sv) (`ORX1_TEST_PASS`) — datapath unit checks
  - [`tb/tb_secure_boot.sv`](tb/tb_secure_boot.sv) (`SECURE_BOOT_TEST_PASS`) — SHA-256/FNV-1a match, mismatch block, eFuse lock
  - [`tb/tb_soc.sv`](tb/tb_soc.sv) (`SOC_TEST_PASS`) — SoC integration & Wishbone routing
  - [`tb/tb_firmware.sv`](tb/tb_firmware.sv) (`FIRMWARE_TEST_PASS cycles=173`) — boot ROM execution
  - [`tb/tb_interrupts.sv`](tb/tb_interrupts.sv) (`INTERRUPT_TEST_PASS cycles=230`) — `WFI` + external/timer IRQ + `MRET`
  - [`tb/tb_peripherals.sv`](tb/tb_peripherals.sv) (`PERIPHERALS_TEST_PASS cycles=0`) — UART FIFO, GPIO, SPI, DMA, CORDIC, SYS_CTRL/WDT
  - [`tb/tb_cpu_benchmark.sv`](tb/tb_cpu_benchmark.sv) (`BENCHMARK_TEST_PASS`) — CPU microbenchmark
  - [`tb/tb_model_bench.sv`](tb/tb_model_bench.sv) (`MODEL_BENCH_PASS total_cycles=1856`) — TinyML/peripheral speed & energy suite
  - [`tb/tb_riscv_compliance.sv`](tb/tb_riscv_compliance.sv) (`RISCV_COMPLIANCE_PASS cycles=4`) — compliance harness
- **Formal Checks**: `interface_sva.sv` / `orx1_bind.sv` plus bounded SymbiYosys Z3 proofs in [`formal/cpu_bus.sby`](formal/cpu_bus.sby) and [`formal/wb_xbar.sby`](formal/wb_xbar.sby). See [`docs/verification.md`](docs/verification.md) and [`formal/README.md`](formal/README.md).

## Reproducible commands

The [`Makefile`](Makefile) targets require a Unix-like shell (`/bin/bash`) with `gcc`, Icarus Verilog (`iverilog`/`vvp`), Verilator, Yosys, and SymbiYosys (`sby` + `z3`) on `PATH` (optional `riscv64-unknown-elf-gcc` for `make sw`). Generated logs and CSVs are written under `build/`.

| Command | Purpose |
|---|---|
| `make test-sw` | Compile and run host C TinyML unit tests (`test_tinyml`) and model benchmarks (`bench_models`) |
| `make sim` | Run the 6 functional RTL regressions (`tb_orx1`, `tb_secure_boot`, `tb_soc`, `tb_firmware`, `tb_interrupts`, `tb_peripherals`) |
| `make bench` | Run `tb_cpu_benchmark` and save `build/benchmark.log` |
| `make model-bench` | Run `tb_model_bench` and `bench_models`, saving `build/model_benchmark.{log,csv}` and `build/c_model_benchmark.{log,csv}` |
| `make compliance` | Run the RISC-V architectural compliance test harness (`tb_riscv_compliance`) |
| `make sw` | Cross-compile bare-metal RV32IM example (`tinyml_anomaly_detector.{elf,hex}`) if `riscv64-unknown-elf-gcc` is installed |
| `make lint` | Run `verilator --lint-only -Wall` on `orx1_soc` |
| `make synth` | Elaborate, optimize, check, and print resource stats with Yosys |
| `make formal` | Run SymbiYosys Z3 formal proofs (`formal/cpu_bus.sby` and `formal/wb_xbar.sby`) |
| `make all` | Execute `test-sw`, `sim`, `bench`, `model-bench`, `compliance`, `lint`, `synth`, and `formal` |
| `make clean` | Remove generated `build/` artifacts |
| `./scripts/run_sim.sh` | Run the 8 base Icarus Verilog simulation testbenches directly |
| `./scripts/check_rtl.sh` | Run Verilator and Yosys checks directly |
| `./scripts/run_openlane.sh` | Invoke the OpenLane SkyWater 130nm physical flow |

## Open-source silicon ecosystem & TinyML SDK

### 1. Wishbone B4 interconnect & Caravel ASIC harness
* [`rtl/wb_interconnect.sv`](rtl/wb_interconnect.sv): 3-master (CPU, 2-channel Micro-DMA, external WB host), 14-slave Wishbone B4 crossbar with round-robin DMA/CPU arbitration and priority host boot-load path.
* [`rtl/caravel_user_project_wrapper.sv`](rtl/caravel_user_project_wrapper.sv): Efabless Caravel padframe wrapper mapping ORX-1 to SkyWater 130nm (`sky130_fd_sc_hd`) user project pins, Wishbone slave port, GPIO, SPI, UART, and logic analyzer probes.

### 2. RISC-V architectural compliance
* [`tb/tb_riscv_compliance.sv`](tb/tb_riscv_compliance.sv): Compliance test harness supporting hex image loading, `tohost` handshakes, and signature checks.
* [`sw/compliance/model_test.h`](sw/compliance/model_test.h): Official `riscv-arch-test` macro header.

### 3. Physical ASIC flow (OpenLane 2 / SkyWater 130nm)
* [`openlane/config.json`](openlane/config.json) & [`openlane/user_project_wrapper/config.json`](openlane/user_project_wrapper/config.json): OpenLane configurations targeting 50 MHz timing closure.
* [`openlane/pin_order.cfg`](openlane/pin_order.cfg) & [`openlane/constraints.sdc`](openlane/constraints.sdc): Caravel die pin order and Synopsys Design Constraints.

### 4. Bare-metal C & TinyML runtime
* [`sw/include/orx1.h`](sw/include/orx1.h): Peripheral base addresses, CSR/register macros, CORDIC/UART/timer inline helpers, and `ORX1_HOST_TEST` hook.
* [`sw/tinyml/tinyml.h`](sw/tinyml/tinyml.h) & [`sw/tinyml/tinyml.c`](sw/tinyml/tinyml.c): Tiled quantized INT8 inference API (`tinyml_dense_4x4`, `tinyml_sparse_2_4`, `tinyml_dense`) with hardware bias, shift, and ReLU.
* [`sw/examples/tinyml_anomaly_detector.c`](sw/examples/tinyml_anomaly_detector.c): Bare-metal streaming anomaly detector example.
* [`sw/tests/test_tinyml.c`](sw/tests/test_tinyml.c) & [`sw/tests/bench_models.c`](sw/tests/bench_models.c): Host C unit tests and multi-layer model throughput benchmarks.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `make test-sw`, `make sim`, `make bench`, `make compliance`, `make lint`, `make synth`, and `make formal` on pushes and pull requests to `main`, uploading `build/` outputs as workflow artifacts.

## Limitations and next steps

- **Boot image provisioning**: The reference `boot_rom` initializes to zero unless a `BOOT_HEX` parameter image is provided or the external Wishbone host (`m2`) loads code into `boot_rom` / SRAM while holding CPU reset via `sys_ctrl`. A production tapeout requires fused/masked boot ROM and a reviewed cryptographic root of trust.
- **CPU privilege scope**: `rv32i_core` implements machine-mode (`M`-mode) CSRs, `RV32IM`, `WFI`, and traps, but does not implement Supervisor/User modes, physical memory protection (PMP), instruction/data caches, or atomic (`A`) / compressed (`C`) extensions.
- **Energy proxy vs. silicon power**: `energy_monitor` accumulates weighted RTL activity events (`cycles`, active/sleep cycles, sensor, NPU, and bus events). Accurate physical mW/uJ numbers require gate-level VCD switching activity back-annotated against technology standard-cell and SRAM macro liberty models.
- **Code style convention**: All SystemVerilog and C/H source files (`rtl/`, `tb/`, `formal/`, `sw/`) intentionally contain zero inline comments; behavioral details live in `docs/`.

## License

ORX-1 is distributed under the MIT License. See [`LICENSE`](LICENSE) for the full text.
