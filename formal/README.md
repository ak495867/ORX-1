# ORX-1 Formal Checks

The formal directory contains `interface_sva.sv`, which defines temporal properties over the ORX-1 data request interface, accelerator completion pulse, and secure-boot status signals. `orx1_bind.sv` attaches the property module to `orx1_soc` without changing the synthesizable design hierarchy.

The properties cover four integration contracts. A valid data request must receive ready within four cycles. Address, write direction, and request validity must remain stable while a request is pending. Boot release and boot failure must never be asserted simultaneously. The accelerator completion interrupt must be a one-cycle pulse.

The repository does not ship a fixed formal engine command because support for SystemVerilog Assertions varies across open-source flows and simulator versions. A downstream project can compile the RTL, property module, and bind module with its selected formal tool, then add assumptions for reset sequencing, legal address traffic, and any environment-level fairness requirements.

The properties are not a complete security proof or instruction-set compliance proof. They are reusable interface contracts intended to serve as a starting point for a broader proof plan.
