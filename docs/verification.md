# ORX-1 Verification and Benchmarking

## Simulation and benchmark

Run the complete simulation and performance benchmark with:

```sh
make sim
make bench
```

The benchmark executes a deterministic integer loop and reports cycle count, retired instructions, branches, loads, stores, bus requests, and wait cycles. The result is printed in `build/benchmark.log`. It is a reproducible RTL cycle benchmark, not a silicon performance claim.

The CPU counters are also visible through the energy-monitor CSR region. Software can sample the counters before and after a workload and compute modulo-2^32 deltas.

## SymbiYosys formal proof

Install Yosys, SymbiYosys, and an SMT solver such as Z3. Then run:

```sh
make formal
```

The `formal/cpu_bus.sby` job proves the CPU request/response safety contracts over a bounded proof depth. The harness checks that responses do not appear without requests, request fields remain stable while stalled, and performance counters are monotonic. The harness currently assumes an always-ready target for the default proof; the request-hold property remains present so a future latency-enabled harness can prove it under arbitrary stalls.

The existing interface SVA files remain available for simulators or formal engines with full concurrent-assertion support. The SymbiYosys harness is intentionally self-contained so the open-source Yosys SMT flow can execute in CI.
