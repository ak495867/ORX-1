# ORX-1 Verification, Benchmarking & Physical Checks

## Simulation, Lint, Synthesis & Floorplan

Run the complete Linux/macOS suite with:

```sh
make all
```

Or run stages individually (`make test-sw`, `make sim`, `make bench`, `make model-bench`, `make compliance`, `make lint`, `make synth`, `make floorplan`, `make formal`). On Windows PowerShell, execute:

```powershell
./scripts/verify_all.ps1
```

* [`tb/tb_cpu_benchmark.sv`](../tb/tb_cpu_benchmark.sv) executes a 100-iteration RV32IM loop (`BENCHMARK cycles=311 instructions=305 branches=101`) using the 2-stage BTB pipeline and writes `build/benchmark.log`.
* [`tb/tb_model_bench.sv`](../tb/tb_model_bench.sv) boots into `16 KiB` SRAM (`0x00011000`, `413/3072` code words) and benchmarks scalar CPU, `OP_CUSTOM0` INT8 SIMD, `4x4` NPU, `64`-MAC `8x8` wide NPU, polled `8->4->4` MLP, autonomous Tensor-DMA MLP, 2:4 sparsity, zero-bubble DMA, 2x CORDIC magnitude, and `WFI` anomaly streaming (`MODEL_BENCH_PASS total_cycles=2036`, writing `build/model_benchmark.log` and `build/model_benchmark.csv`).
* [`sw/tests/bench_models.c`](../sw/tests/bench_models.c) links [`sw/tinyml/tinyml.c`](../sw/tinyml/tinyml.c) against a register-accurate hardware/SRAM model and verifies bit-exact INT8 logits across `mlp_8x4x4`, `mlp_16x8x4`, `sparse_2_4_16x4`, `dense_16x16_8x8`, and `mlp_8x4x4_tdma` (`BENCH_MODELS_PASS`, `build/c_model_benchmark.log` & `build/c_model_benchmark.csv`).
* [`tb/tb_boot_flash.sv`](../tb/tb_boot_flash.sv) instantiates `orx1_soc #(.BUILTIN_BOOTLOADER(1'b1))` against an external SPI flash model and passes under both behavioral memory and `-D USE_OPENRAM` synchronous 8-bank SRAM (`BOOT_FLASH_TEST_PASS cycles=1709`). [`tb/tb_soc.sv`](../tb/tb_soc.sv) also runs under both default and `-D USE_OPENRAM` targets (`SOC_TEST_PASS`).
* [`tb/tb_riscv_compliance.sv`](../tb/tb_riscv_compliance.sv) executes **48** self-checking RV32I, RV32M (multiply/divide/remainder corners), `OP_CUSTOM0` SIMD (`ORX.DOT4`, `ORX.CLIP8`, `ORX.PACK4`), CSR (`misa`, `mhartid`, `mcycle`, `minstret`, `mtvec`, `mepc`, `mcause`), and synchronous trap (`ECALL`, `EBREAK`, illegal instruction, unsupported `OP_CUSTOM0`, read-only CSR write, misaligned load/store) checks (`RISCV_COMPLIANCE_PASS cycles=281 checks=48`), and supports `+HEX=` / `+SIG=` plusargs.
* `verilator --lint-only -Wall` passes with zero warnings across `orx1_soc` (default + `-DUSE_OPENRAM`) and `caravel_user_project_wrapper`; `yosys` `proc; opt; check; stat` passes cleanly under both default and `-DUSE_OPENRAM -DSYNTHESIS`.
* [`scripts/floorplan_analyze.py`](../scripts/floorplan_analyze.py) checks Caravel wrapper bounds, `0` macro overlaps across 8 OpenRAM banks (`683.1 x 416.5 um`) + `u_soc`, `>= 80 um` channels, `100 MHz` SDC match, `9/9` PDN hooks, and modeled utilization (`FLOORPLAN_CHECK_PASS`), writing `build/floorplan_metrics.json`.

The energy-monitor counters remain reproducible RTL activity proxies with fixed weights rather than calibrated silicon power measurements.

## SymbiYosys formal proofs

```sh
make formal
```

* [`formal/cpu_bus.sby`](../formal/cpu_bus.sby) (`mode prove`, k-induction depth 8): verifies CPU bus handshake stability, single outstanding request ordering, reset postconditions, `TRAP`/`WFI` mutual exclusivity, and counter monotonicity under unconstrained `req_ready`/`rsp_valid` stalls and `rsp_err` faults.
* [`formal/wb_xbar.sby`](../formal/wb_xbar.sby) (`mode prove`, k-induction depth 10): verifies 4-master Wishbone arbitration mutual exclusion, `s_cyc_o`/`s_stb_o` one-hot slave selection, and bounded starvation (`<= 8` wait cycles) across all four masters (`m0..m3`, including Tensor-DMA).
* [`formal/neural_accel.sby`](../formal/neural_accel.sby) (`mode prove`, k-induction depth 4): verifies single-cycle `irq` pulses, single-cycle `busy -> done` completion, idle Tensor-DMA bus quiescence (`tdma_req_valid == 0`, `tdma_req_wstrb == 4'b1111`), and bounded INT8 clamp (`[-128, 127]`).
* [`formal/secure_boot.sby`](../formal/secure_boot.sby) (`mode bmc`, depth 24): verifies `boot_release`/`fail` mutual exclusion, idle-vs-running consistency, SRAM read gating, and irreversible `efuse_lock` immutability.

Concurrent SVA properties in [`formal/interface_sva.sv`](../formal/interface_sva.sv) and [`formal/orx1_bind.sv`](../formal/orx1_bind.sv) remain available for native SVA simulators.
