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
  logic [7:0] boot_addr;
  logic [31:0] boot_word;
  integer failures;
  integer idx;
  integer wait_cnt;
  logic [31:0] expected_fnv;
  logic [255:0] nist_sha256_16z;
  logic [255:0] nist_sha256_64z;
  logic [255:0] nist_sha256_80z;

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
    .boot_addr(boot_addr),
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

  task automatic read_csr(input logic [7:0] address, output logic [31:0] value);
    begin
      @(negedge clk);
      csr_addr = address;
      csr_valid = 1'b1;
      csr_write = 1'b0;
      #1;
      value = csr_rdata;
      csr_valid = 1'b0;
    end
  endtask

  logic [31:0] status_val;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    csr_valid = 1'b0;
    csr_write = 1'b0;
    csr_addr = 8'd0;
    csr_wdata = 32'd0;
    boot_word = 32'd0;
    failures = 0;
    nist_sha256_16z = 256'h374708ff_f7719dd5_979ec875_d56cd228_6f6d3cf7_ec317a3b_25632aab_28ec37bb;
    nist_sha256_64z = 256'hf5a5fd42_d16a2030_2798ef6e_d309979b_43003d23_20d9f0e8_ea9831a9_2759fb4b;
    nist_sha256_80z = 256'h5b6fb58e_61fa4759_39767d68_a446f97f_1bff02c0_e5935a3e_a8bb51e6_515783d8;
    repeat (2) @(negedge clk);
    reset = 1'b0;

    write_csr(8'h08, 32'd0);
    write_csr(8'h00, 32'd1);
    repeat (6) @(posedge clk);
    #1;
    if (!fail || boot_release) failures = failures + 1;

    boot_word = 32'h1234_5678;
    expected_fnv = 32'h811c_9dc5;
    for (idx = 0; idx < 4; idx = idx + 1) begin
      expected_fnv = (expected_fnv ^ boot_word) * 32'h0100_0193;
    end
    write_csr(8'h08, expected_fnv);
    write_csr(8'h00, 32'd1);
    repeat (6) @(posedge clk);
    #1;
    if (!boot_release || fail) failures = failures + 1;

    boot_word = 32'd0;
    write_csr(8'h00, 32'h21);
    wait_cnt = 0;
    status_val = 32'd0;
    while (!status_val[1] && wait_cnt < 100) begin
      @(posedge clk);
      read_csr(8'h00, status_val);
      wait_cnt = wait_cnt + 1;
    end
    if (!status_val[1] || !fail || boot_release) failures = failures + 1;

    for (idx = 0; idx < 8; idx = idx + 1) begin
      write_csr(8'h0c, idx[31:0]);
      write_csr(8'h10, nist_sha256_16z[idx*32 +: 32]);
    end
    write_csr(8'h00, 32'h21);
    wait_cnt = 0;
    status_val = 32'd0;
    while (!status_val[1] && wait_cnt < 100) begin
      @(posedge clk);
      read_csr(8'h00, status_val);
      wait_cnt = wait_cnt + 1;
    end
    if (!status_val[1] || !boot_release || fail) failures = failures + 1;

    write_csr(8'h14, 32'd16);
    for (idx = 0; idx < 8; idx = idx + 1) begin
      write_csr(8'h0c, idx[31:0]);
      write_csr(8'h10, nist_sha256_64z[idx*32 +: 32]);
    end
    write_csr(8'h00, 32'h21);
    wait_cnt = 0;
    status_val = 32'd0;
    while (!status_val[1] && wait_cnt < 200) begin
      @(posedge clk);
      read_csr(8'h00, status_val);
      wait_cnt = wait_cnt + 1;
    end
    if (!status_val[1] || !boot_release || fail) failures = failures + 1;

    write_csr(8'h14, 32'd20);
    for (idx = 0; idx < 8; idx = idx + 1) begin
      write_csr(8'h0c, idx[31:0]);
      write_csr(8'h10, nist_sha256_80z[idx*32 +: 32]);
    end
    write_csr(8'h00, 32'h61);
    wait_cnt = 0;
    status_val = 32'd0;
    while (!status_val[1] && wait_cnt < 200) begin
      @(posedge clk);
      read_csr(8'h00, status_val);
      wait_cnt = wait_cnt + 1;
    end
    if (!status_val[1] || !boot_release || fail || !status_val[5]) failures = failures + 1;

    write_csr(8'h0c, 32'd0);
    write_csr(8'h10, 32'hDEAD_BEEF);
    read_csr(8'h10, status_val);
    if (status_val == 32'hDEAD_BEEF) failures = failures + 1;

    if (failures == 0) $display("SECURE_BOOT_TEST_PASS");
    else $display("SECURE_BOOT_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
