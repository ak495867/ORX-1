# ORX-1 Formal Checks

The `formal/` directory contains SymbiYosys + Z3 verification harnesses and SVA interface bind files:

* [`cpu_bus.sby`](cpu_bus.sby) / [`cpu_bus_formal.sv`](cpu_bus_formal.sv): k-induction proof (`prove`, depth 8) over `rv32i_core` data interface stability, single outstanding request ordering, reset postconditions, and counter monotonicity under unconstrained stalls and errors.
* [`wb_xbar.sby`](wb_xbar.sby) / [`wb_xbar_formal.sv`](wb_xbar_formal.sv): k-induction proof (`prove`, depth 10) over 4-master (`m0` CPU, `m1` Micro-DMA, `m2` external host, `m3` Tensor-DMA) x 14-slave Wishbone B4 arbitration exclusivity, one-hot slave selection, and bounded per-master fairness (`wait_cnt <= 8`).
* [`neural_accel.sby`](neural_accel.sby) / [`neural_accel_formal.sv`](neural_accel_formal.sv): k-induction proof (`prove`, depth 4) over single-cycle `irq` pulses, `busy` completion, Tensor-DMA idle quiescence and full-word write strobes, CSR status (`0x00[11]` = `tdma_busy`), and INT8 clamp bounds (`[-128, 127]`).
* [`secure_boot.sby`](secure_boot.sby) / [`secure_boot_formal.sv`](secure_boot_formal.sv): bounded check (`bmc`, depth 24) over `boot_release`/`fail` mutual exclusion, SRAM source gating, and irreversible `efuse_lock`.
* [`interface_sva.sv`](interface_sva.sv) / [`orx1_bind.sv`](orx1_bind.sv): concurrent SystemVerilog Assertions bind module over `orx1_soc` for tools with native SVA support.

The assertions verify bus protocol, arbitration, accelerator, and control safety contracts; they do not constitute a full-SoC timing, power, or cryptographic side-channel proof.
