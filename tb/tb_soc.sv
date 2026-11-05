`timescale 1ns/1ps
module tb_soc;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic sensor_valid = 1'b0;
  logic [15:0] sensor_data = 16'd0;
  logic sensor_result_valid;
  logic [15:0] sensor_result;
  logic accelerator_irq;
  logic boot_release;
  logic boot_fail;
  logic core_trap;
  integer failures = 0;

  always #5 clk = ~clk;

  orx1_soc dut (
    .clk(clk), .reset(reset), .sensor_valid(sensor_valid), .sensor_data(sensor_data),
    .sensor_result_valid(sensor_result_valid), .sensor_result(sensor_result),
    .accelerator_irq(accelerator_irq), .boot_release(boot_release), .boot_fail(boot_fail),
    .core_trap(core_trap)
  );

  task automatic sample(input logic [15:0] value);
    begin
      @(negedge clk);
      sensor_data = value;
      sensor_valid = 1'b1;
      @(negedge clk);
      sensor_valid = 1'b0;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    reset = 1'b0;
    force dut.sensor_enable = 1'b1;
    sample(16'd10);
    sample(16'd20);
    sample(16'd30);
    sample(16'd40);
    #1;
    if (!sensor_result_valid || sensor_result != 16'd25) failures = failures + 1;
    sample(16'd50);
    #1;
    if (!sensor_result_valid || sensor_result != 16'd35) failures = failures + 1;
    release dut.sensor_enable;
    if (boot_release || boot_fail) failures = failures + 1;
    if (failures == 0) $display("SOC_TEST_PASS");
    else $display("SOC_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
