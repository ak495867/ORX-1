`timescale 1ns/1ps
module tb_secure_boot;
  logic clk;
  logic reset;
  logic csr_valid;
  logic csr_write;
  logic [7:0] csr_addr;
  logic [31:0] csr_wdata;
  logic [31:0] csr_rdata;
  logic boot_release;
  logic fail;
  logic [31:0] boot_word;
  integer failures;

  secure_boot dut (
    .clk(clk),
    .reset(reset),
    .csr_valid(csr_valid),
    .csr_write(csr_write),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .boot_release(boot_release),
    .fail(fail),
    .boot_word(boot_word)
  );

  always #5 clk = ~clk;

  task automatic write_csr(input logic [7:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      csr_addr = address;
      csr_wdata = value;
      csr_write = 1'b1;
      csr_valid = 1'b1;
      @(negedge clk);
      csr_valid = 1'b0;
      csr_write = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    csr_valid = 1'b0;
    csr_write = 1'b0;
    csr_addr = 8'd0;
    csr_wdata = 32'd0;
    boot_word = 32'd0;
    failures = 0;
    repeat (2) @(negedge clk);
    reset = 1'b0;
    write_csr(8'h08, 32'd0);
    write_csr(8'h00, 32'd1);
    repeat (6) @(posedge clk);
    #1;
    if (!fail || boot_release) failures = failures + 1;
    if (failures == 0) $display("SECURE_BOOT_TEST_PASS");
    else $display("SECURE_BOOT_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
