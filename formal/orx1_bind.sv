bind orx1_soc orx1_interface_sva interface_properties (
  .clk(clk),
  .reset(reset),
  .d_valid(d_valid),
  .d_ready(d_ready),
  .d_write(d_write),
  .d_addr(d_addr),
  .accelerator_irq(accelerator_irq),
  .boot_release(boot_release),
  .boot_fail(boot_fail)
);
