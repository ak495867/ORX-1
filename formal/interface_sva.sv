module orx1_interface_sva (
  input logic clk,
  input logic reset,
  input logic d_valid,
  input logic d_ready,
  input logic d_write,
  input logic [31:0] d_addr,
  input logic accelerator_irq,
  input logic boot_release,
  input logic boot_fail
);
  default clocking cb @(posedge clk); endclocking
  property request_eventually_completes;
    disable iff (reset) d_valid |-> ##[1:4] d_ready;
  endproperty
  property request_fields_hold;
    disable iff (reset) d_valid && !d_ready |=> d_valid && $stable({d_write, d_addr});
  endproperty
  property boot_status_exclusive;
    !(boot_release && boot_fail);
  endproperty
  property accelerator_irq_pulses;
    accelerator_irq |=> !accelerator_irq;
  endproperty
  assert property (request_eventually_completes);
  assert property (request_fields_hold);
  assert property (boot_status_exclusive);
  assert property (accelerator_irq_pulses);
endmodule
