`timescale 1ns/1ps
module tb_orx1;
  logic clk;
  logic reset;
  logic sample_valid;
  logic [15:0] sample_data;
  logic sensor_enable;
  logic sensor_clear;
  logic [1:0] sensor_depth;
  logic sensor_thresh_en;
  logic [15:0] sensor_thresh_low;
  logic [15:0] sensor_thresh_high;
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
    .cfg_depth(sensor_depth),
    .cfg_thresh_en(sensor_thresh_en),
    .cfg_thresh_low(sensor_thresh_low),
    .cfg_thresh_high(sensor_thresh_high),
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
    .auto_infer_sample(16'd0),
    .tdma_req_valid(),
    .tdma_req_ready(1'b0),
    .tdma_req_write(),
    .tdma_req_addr(),
    .tdma_req_wdata(),
    .tdma_req_wstrb(),
    .tdma_rsp_valid(1'b0),
    .tdma_rsp_rdata(32'd0)
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

  task automatic read_accel(input logic [7:0] address, output logic [31:0] value);
    begin
      @(negedge clk);
      accel_addr = address;
      accel_valid = 1'b1;
      accel_write = 1'b0;
      #1;
      value = accel_rdata;
      accel_valid = 1'b0;
    end
  endtask

  logic [31:0] rd_val;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    sample_valid = 1'b0;
    sample_data = 16'd0;
    sensor_enable = 1'b0;
    sensor_clear = 1'b0;
    sensor_depth = 2'b10;
    sensor_thresh_en = 1'b0;
    sensor_thresh_low = 16'd0;
    sensor_thresh_high = 16'hffff;
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

    @(negedge clk);
    sensor_clear = 1'b1;
    @(negedge clk);
    sensor_clear = 1'b0;
    sensor_depth = 2'b11;
    sensor_thresh_en = 1'b1;
    sensor_thresh_low = 16'd0;
    sensor_thresh_high = 16'd5;
    push_sample(16'd10);
    push_sample(16'd20);
    push_sample(16'd45);
    #1;
    if (!sensor_result_valid || sensor_result != 16'd15 || !sensor_alert) failures = failures + 1;

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
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd110) failures = failures + 1;

    write_accel(8'h30, 32'h0504_0302);
    write_accel(8'h34, 32'h0908_0706);
    write_accel(8'h08, 32'd10);
    write_accel(8'h00, 32'h11);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd120) failures = failures + 1;

    write_accel(8'h30, 32'h0504_0302);
    write_accel(8'h34, 32'h0001_0a05);
    write_accel(8'h08, 32'd0);
    write_accel(8'h0c, 32'd0);
    write_accel(8'h00, 32'h81);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd35) failures = failures + 1;

    write_accel(8'h30, 32'h0101_0101);
    write_accel(8'h34, 32'h0101_0101);
    write_accel(8'h38, 32'hffff_ffff);
    write_accel(8'h3c, 32'h0202_0202);
    write_accel(8'h40, 32'h0303_0303);
    write_accel(8'h08, 32'd4);
    write_accel(8'h60, 32'd1);
    write_accel(8'h64, 32'd8);
    write_accel(8'h68, 32'd4);
    write_accel(8'h0c, 32'd1);
    write_accel(8'h00, 32'h39);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd4) failures = failures + 1;
    read_accel(8'h44, rd_val);
    if (rd_val != 32'd0) failures = failures + 1;
    read_accel(8'h48, rd_val);
    if (rd_val != 32'd8) failures = failures + 1;
    read_accel(8'h4c, rd_val);
    if (rd_val != 32'd8) failures = failures + 1;

    write_accel(8'h50, 32'h0202_0202);
    write_accel(8'h54, 32'h0101_0101);
    write_accel(8'h0c, 32'd0);
    write_accel(8'h00, 32'h61);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd8) failures = failures + 1;
    read_accel(8'h44, rd_val);
    if (rd_val != 32'd4) failures = failures + 1;

    write_accel(8'h30, 32'h7f7f_7f7f);
    write_accel(8'h34, 32'h0202_0202);
    write_accel(8'h38, 32'hfefe_fefe);
    write_accel(8'h08, 32'd0);
    write_accel(8'h60, 32'd0);
    write_accel(8'h0c, 32'd0);
    write_accel(8'h6c, 32'sd500);
    write_accel(8'h00, 32'h321);
    @(posedge clk);
    #1;
    if (accel_irq) failures = failures + 1;
    read_accel(8'h04, rd_val);
    if (rd_val != 32'd127) failures = failures + 1;
    read_accel(8'h44, rd_val);
    if ($signed(rd_val) != -32'sd128) failures = failures + 1;

    write_accel(8'h6c, 32'sd100);
    write_accel(8'h00, 32'h321);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;

    read_accel(8'h70, rd_val);
    if (rd_val != 32'h0000_807f) failures = failures + 1;

    write_accel(8'h30, 32'h0101_0101);
    write_accel(8'h74, 32'h0101_0101);
    write_accel(8'h34, 32'h0202_0202);
    write_accel(8'h38, 32'h0202_0202);
    write_accel(8'h3c, 32'h0202_0202);
    write_accel(8'h40, 32'h0202_0202);
    write_accel(8'h78, 32'h0202_0202);
    write_accel(8'h7c, 32'h0202_0202);
    write_accel(8'h80, 32'h0202_0202);
    write_accel(8'h84, 32'h0202_0202);
    write_accel(8'h88, 32'h0202_0202);
    write_accel(8'h8c, 32'h0202_0202);
    write_accel(8'h90, 32'h0202_0202);
    write_accel(8'h94, 32'h0202_0202);
    write_accel(8'h98, 32'h0202_0202);
    write_accel(8'h9c, 32'h0202_0202);
    write_accel(8'ha0, 32'h0202_0202);
    write_accel(8'ha4, 32'h0202_0202);
    write_accel(8'h08, 32'sd4);
    write_accel(8'h60, -32'sd4);
    write_accel(8'h64, 32'sd10);
    write_accel(8'h68, 32'sd0);
    write_accel(8'ha8, 32'sd1);
    write_accel(8'hac, 32'sd2);
    write_accel(8'hb0, 32'sd3);
    write_accel(8'hb4, -32'sd100);
    write_accel(8'h0c, 32'd1);
    write_accel(8'h00, 32'h519);
    @(posedge clk);
    #1;
    if (!accel_irq) failures = failures + 1;
    read_accel(8'h70, rd_val);
    if (rd_val != 32'h080d_060a) failures = failures + 1;
    read_accel(8'hc8, rd_val);
    if (rd_val != 32'h0009_0908) failures = failures + 1;
    read_accel(8'hbc, rd_val);
    if (rd_val != 32'd9) failures = failures + 1;

    if (failures == 0) $display("ORX1_TEST_PASS");
    else $display("ORX1_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
