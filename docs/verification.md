# ORX-1 Verification and Benchmarking

## Simulation and benchmarks

Run all unit, SoC, boot, peripheral, compliance, and speed benchmarks with:

```sh
make test-sw
make sim
make bench
make model-bench
make compliance
```

On Windows PowerShell (where GNU `make` and `/bin/bash` may not be present), run:

```powershell
./scripts/verify_all.ps1
```

- `tb/tb_cpu_benchmark.sv` executes a deterministic RV32IM loop and writes cycle/instruction/branch/load/store/bus/wait counters to `build/benchmark.log`.
- `tb/tb_model_bench.sv` boots into SRAM (`0x00011000`), benchmarks quantized CPU vs. NPU inference, 2-layer `8->4->4` MACs, 2:4 structured sparsity, DMA bursts, CORDIC vector magnitude, and autonomous `WFI` anomaly streaming, writing `build/model_benchmark.log` and `build/model_benchmark.csv`.
- `sw/tests/bench_models.c` links `sw/tinyml/tinyml.c` against a register-level `orx1_host_reg` hardware model and verifies bit-exact INT8 logits against a pure-C reference (`build/c_model_benchmark.log` and `build/c_model_benchmark.csv`).
- `tb/tb_boot_flash.sv` instantiates `orx1_soc #(.BUILTIN_BOOTLOADER(1'b1))` connected to a behavioral SPI flash model to verify valid SHA-256 boot handoff to SRAM and fault lockdown on a 1-bit flash tamper.
- `tb/tb_riscv_compliance.sv` runs 43 self-checking RV32I, RV32M (signed/unsigned multiply/divide/remainder corners), CSR (`misa`, `mhartid`, `mcycle`, `minstret`, `mtvec`, `mepc`, `mcause`), and synchronous trap (`ECALL`, `EBREAK`, illegal instruction `mcause=2`, read-only CSR write `mcause=2`, misaligned load/store `mcause=4/6`) checks, and accepts external `+HEX=` / `+SIG=` plusargs.

The energy-monitor counters remain reproducible RTL activity proxies with fixed weights rather than calibrated silicon power measurements.

## SymbiYosys formal proofs

Install Yosys, SymbiYosys, and Z3, then run:

```sh
make formal
```

- `formal/cpu_bus.sby` (`mode prove`, k-induction depth 8): verifies CPU bus handshake stability, single outstanding request ordering, reset postconditions, `TRAP`/`WFI` mutual exclusivity, and counter monotonicity under **unconstrained multi-cycle `req_ready`/`rsp_valid` stalls and `rsp_err` faults**.
- `formal/wb_xbar.sby` (`mode prove`, k-induction depth 10): verifies 3-master Wishbone arbitration mutual exclusion, `s_cyc_o`/`s_stb_o` one-hot slave selection, and starvation bounds across masters 0, 1, and 2.
- `formal/neural_accel.sby` (`mode prove`, k-induction depth 4): verifies single-cycle `irq` pulses, single-cycle `busy -> done` transition, CSR config flag readback, and bounded INT8 saturation (`[-128, 127]`) when `cfg_clamp` is active.
- `formal/secure_boot.sby` (`mode bmc`, depth 24): verifies `boot_release`/`fail` mutual exclusion, idle-vs-running status consistency, SRAM read gating, and sticky `efuse_lock` immutability.

The concurrent SVA properties in `formal/interface_sva.sv` and bind wrapper `formal/orx1_bind.sv` remain available for simulators with full SVA support.
