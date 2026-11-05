`timescale 1ns/1ps
module tb_cpu_benchmark;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic req_valid;
  logic req_ready = 1'b1;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid = 1'b0;
  logic [31:0] rsp_rdata = 32'd0;
  logic rsp_err = 1'b0;
  logic trap;
  logic [31:0] perf_cycles;
  logic [31:0] perf_instructions;
  logic [31:0] perf_loads;
  logic [31:0] perf_stores;
  logic [31:0] perf_branches;
  logic [31:0] perf_bus_requests;
  logic [31:0] perf_wait_cycles;
  integer failures = 0;
  integer cycles;

  always #5 clk = ~clk;

  function automatic [31:0] enc_i(input integer imm, input integer rs1, input integer funct3, input integer rd, input integer opcode);
    enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
  endfunction
  function automatic [31:0] enc_b(input integer imm, input integer rs1, input integer rs2, input integer funct3);
    enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], funct3[2:0], imm[4:1], imm[11], 7'b1100011};
  endfunction

  always_comb begin
    case (imem_addr)
      32'd0:  imem_rdata = enc_i(0, 0, 3'b000, 1, 7'b0010011);
      32'd4:  imem_rdata = enc_i(101, 0, 3'b000, 2, 7'b0010011);
      32'd8:  imem_rdata = enc_i(1, 1, 3'b000, 1, 7'b0010011);
      32'd12: imem_rdata = enc_i(-1, 2, 3'b000, 2, 7'b0010011);
      32'd16: imem_rdata = enc_b(-8, 2, 0, 3'b001);
      default: imem_rdata = 32'h0000_0073;
    endcase
  end

  rv32i_core dut (
    .clk(clk), .reset(reset), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .req_valid(req_valid), .req_ready(req_ready), .req_write(req_write),
    .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err), .trap(trap),
    .perf_cycles(perf_cycles), .perf_instructions(perf_instructions),
    .perf_loads(perf_loads), .perf_stores(perf_stores), .perf_branches(perf_branches),
    .perf_bus_requests(perf_bus_requests), .perf_wait_cycles(perf_wait_cycles),
    .irq_external(1'b0), .irq_timer(1'b0)
  );

  initial begin
    repeat (2) @(negedge clk);
    reset = 1'b0;
    cycles = 0;
    while (!trap && cycles < 1000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    @(posedge clk);
    #1;
    if (!trap) failures = failures + 1;
    if (perf_cycles == 0 || perf_instructions == 0 || perf_branches == 0) failures = failures + 1;
    if (perf_loads != 0 || perf_stores != 0) failures = failures + 1;
    $display("BENCHMARK cycles=%0d instructions=%0d branches=%0d loads=%0d stores=%0d waits=%0d", perf_cycles, perf_instructions, perf_branches, perf_loads, perf_stores, perf_wait_cycles);
    $display("benchmark_metric,cycles,instructions,branches,loads,stores,bus_requests,wait_cycles");
    $display("loop_100,%0d,%0d,%0d,%0d,%0d,%0d,%0d", perf_cycles, perf_instructions, perf_branches, perf_loads, perf_stores, perf_bus_requests, perf_wait_cycles);
    if (failures == 0) $display("BENCHMARK_TEST_PASS");
    else $display("BENCHMARK_TEST_FAIL %0d", failures);
    $finish;
  end
endmodule
