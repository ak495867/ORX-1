# ORX-1 Data Bus & Crossbar Contract

The ORX-1 SoC routes transactions across a **4-master x 14-slave** round-robin Wishbone B4 crossbar ([`rtl/wb_interconnect.sv`](../rtl/wb_interconnect.sv)):

* **`m0` (`rv32i_core` LSU):** CPU load/store requests with non-blocking posted-store overlap in the execution stage.
* **`m1` (`dma_ctrl`):** 2-channel zero-bubble peripheral/SRAM DMA engine.
* **`m2` (`wb_host_*`):** External Wishbone management host (Caravel `wbs_*`), also permitted to write the boot ROM window in behavioral simulation.
* **`m3` (`neural_accel` Tensor-DMA):** Autonomous block tensor reader/writer fetching packed activations, weights, and biases from `16 KiB` SRAM and writing clamped INT8 outputs directly back to SRAM.

At the CPU interface ([`rtl/rv32i_core.sv`](../rtl/rv32i_core.sv)), a data request is presented with `req_valid`, address, direction, write data, and byte strobes. The fabric accepts it on the rising edge when `req_ready` is high, and returns `rsp_valid` with `rsp_rdata` or `rsp_err` on unmapped/illegal accesses.

| Signal | Direction | Meaning |
|---|---|---|
| `req_valid` | master to fabric | Request is present and must remain stable until accepted. |
| `req_ready` | fabric to master | Fabric accepts the request on the rising edge. |
| `req_write` | master to fabric | `1` for a write, `0` for a read. |
| `req_addr` | master to fabric | Byte address. |
| `req_wdata` | master to fabric | Write payload. |
| `req_wstrb` | master to fabric | Active byte lanes, low bit is the least-significant byte. |
| `rsp_valid` | fabric to master | Response is present. |
| `rsp_rdata` | fabric to master | Read response data. |
| `rsp_err` | fabric to master | Access was unmapped or otherwise invalid. |

Boot ROM and register-mapped slaves acknowledge in a single cycle; [`rtl/sram_sp.sv`](../rtl/sram_sp.sv) acknowledges writes in 1 cycle and reads in 2 cycles (matching synchronous `sky130_sram_2kbyte_1rw1r_32x512_8` OpenRAM macros). The CPU retains full multi-cycle `wait_pending` tracking verified under unconstrained stalls and `rsp_err` injection in [`formal/cpu_bus.sby`](../formal/cpu_bus.sby).
