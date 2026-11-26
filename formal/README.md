# ORX-1 Formal Checks

The `formal/` directory contains both SymbiYosys + Z3 verification harnesses and SVA interface bind files:

- `cpu_bus.sby` / `cpu_bus_formal.sv`: k-induction proof (`prove`, depth 8) over `rv32i_core` data interface stability, single outstanding request ordering, and counter monotonicity under unconstrained stalls and errors.
- `wb_xbar.sby` / `wb_xbar_formal.sv`: k-induction proof (`prove`, depth 10) over 3-master x 14-slave Wishbone B4 arbitration exclusivity, one-hot slave selection, and per-master fairness bounds.
- `neural_accel.sby` / `neural_accel_formal.sv`: k-induction proof (`prove`, depth 4) over single-cycle `irq` pulses, `busy` completion, CSR flag readback, and INT8 saturation bounds.
- `secure_boot.sby` / `secure_boot_formal.sv`: bounded check (`bmc`, depth 24) over `boot_release`/`fail` mutual exclusion, SRAM source gating, and irreversible `efuse_lock`.
- `interface_sva.sv` / `orx1_bind.sv`: concurrent SystemVerilog Assertions bind module over `orx1_soc` for tools with native SVA support.

The assertions verify bus protocol, arbitration, accelerator, and control safety contracts; they do not constitute a full-SoC timing, power, or cryptographic side-channel proof.
