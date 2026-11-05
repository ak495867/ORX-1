`timescale 1ns/1ps
module tb_orx1;
  logic clk;
  logic reset;
  logic sample_valid;
  logic [15:0] sample_data;
  logic sensor_enable;
  logic sensor_clear;
  logic sensor_result_valid;
  logic [15:0] sensor_result;
  logic sensor_irq;
  logic accel_valid;
  logic accel_write;
  logic [7:0] accel_addr;
  logic [31:0] accel_wdata;
  logic [31:0] accel_rdata;
  logic accel_irq;
  integer failures;

  logic sensor_alert;

  sensor_pipeline sensor_dut (
    .clk(clk),
    .reset(reset),
    .sample_valid(sample_valid),
    .sample_data(sample_data),
    .cfg_enable(sensor_enable),
    .cfg_clear(sensor_clear),
    .cfg_depth(2'b10),
    .cfg_thresh_en(1'b0),
    .cfg_thresh_low(16'd0),
    .cfg_thresh_high(16'hffff),
    .result_valid(sensor_result_valid),
    .result_data(sensor_result),
    .alert(sensor_alert),
    .irq(sensor_irq)
  );

  neural_accel accel_dut (
    .clk(clk),
    .reset(reset),
    .csr_valid(accel_valid),
    .csr_write(accel_write),
    .csr_addr(accel_addr),
    .csr_wdata(accel_wdata),
    .csr_rdata(accel_rdata),
    .irq(accel_irq),
    .auto_infer_trigger(1'b0),
    .auto_infer_sample(16'd0)
  );

  always #5 clk = ~clk;

  task automatic push_sample(input logic [15:0] value);
    begin
      @(negedge clk);
      sample_data = value;
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
    end
  endtask

  task automatic write_accel(input logic [7:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      accel_addr = address;
      accel_wdata = value;
      accel_write = 1'b1;
      accel_valid = 1'b1;
      @(negedge clk);
      accel_valid = 1'b0;
      accel_write = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    sample_valid = 1'b0;
    sample_data = 16'd0;
    sensor_enable = 1'b0;
    sensor_clear = 1'b0;
    accel_valid = 1'b0;
    accel_write = 1'b0;
    accel_addr = 8'd0;
    accel_wdata = 32'd0;
    failures = 0;
    repeat (3) @(negedge clk);
    reset = 1'b0;
    sensor_enable = 1'b1;
    push_sample(16'd4);
    push_sample(16'd4);
    push_sample(16'd4);
    push_sample(16'd4);
    #1;
    if (!sensor_result_valid || sensor_result != 16'd4) failures = failures + 1;

    write_accel(8'h10, 32'd2);
    write_accel(8'h14, 32'd3);
    write_accel(8'h18, 32'd4);
    write_accel(8'h1c, 32'd5);
    write_accel(8'h20, 32'd6);
    write_accel(8'h24, 32'd7);
    write_accel(8'h28, 32'd8);
    write_accel(8'h2c, 32'd9);
    write_accel(8'h00, 32'd1);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    @(negedge clk);
    accel_addr = 8'h04;
    accel_valid = 1'b1;
    accel_write = 1'b0;
    #1;
    if (accel_rdata != 32'd110) failures = failures + 1;
    accel_valid = 1'b0;

    write_accel(8'h30, 32'h0504_0302);
    write_accel(8'h34, 32'h0908_0706);
    write_accel(8'h08, 32'd10);
    write_accel(8'h00, 32'h11);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    @(negedge clk);
    accel_addr = 8'h04;
    accel_valid = 1'b1;
    accel_write = 1'b0;
    #1;
    if (accel_rdata != 32'd120) failures = failures + 1;
    accel_valid = 1'b0;

    if (failures == 0) $display("ORX1_TEST_PASS");
    else $display("ORX1_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
