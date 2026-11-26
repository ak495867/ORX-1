`timescale 1ns/1ps
module tb_riscv_compliance;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic req_valid;
  logic req_ready;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic [31:0] rsp_rdata;
  logic rsp_err;
  logic trap;
  logic [31:0] perf_cycles;
  logic [31:0] perf_instructions;
  logic [31:0] perf_loads;
  logic [31:0] perf_stores;
  logic [31:0] perf_branches;
  logic [31:0] perf_bus_requests;
  logic [31:0] perf_wait_cycles;

  logic [31:0] ram [0:4095];
  integer cycles = 0;
  integer test_passed = 0;
  integer test_done = 0;
  string test_hex_file;
  string test_sig_file;

  always #5 clk = ~clk;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign rsp_err = 1'b0;

  assign imem_rdata = ram[imem_addr[13:2]];
  assign rsp_rdata = ram[req_addr[13:2]];

  always_ff @(posedge clk) begin
    if (req_valid && req_ready && req_write) begin
      if (req_wstrb[0]) ram[req_addr[13:2]][7:0] <= req_wdata[7:0];
      if (req_wstrb[1]) ram[req_addr[13:2]][15:8] <= req_wdata[15:8];
      if (req_wstrb[2]) ram[req_addr[13:2]][23:16] <= req_wdata[23:16];
      if (req_wstrb[3]) ram[req_addr[13:2]][31:24] <= req_wdata[31:24];
    end
  end

  rv32i_core dut (
    .clk(clk),
    .reset(reset),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_write(req_write),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid),
    .rsp_rdata(rsp_rdata),
    .rsp_err(rsp_err),
    .trap(trap),
    .perf_cycles(perf_cycles),
    .perf_instructions(perf_instructions),
    .perf_loads(perf_loads),
    .perf_stores(perf_stores),
    .perf_branches(perf_branches),
    .perf_bus_requests(perf_bus_requests),
    .perf_wait_cycles(perf_wait_cycles),
    .irq_external(1'b0),
    .irq_timer(1'b0)
  );

  initial begin
    integer fd;
    for (int i = 0; i < 4096; i = i + 1) ram[i] = 32'h0000_0013;
    ram[0] = 32'h0010_0093;
    ram[1] = 32'h0001_1137;
    ram[2] = 32'h0011_2023;
    ram[3] = 32'h0000_006f;
    if ($value$plusargs("HEX=%s", test_hex_file)) begin
      $readmemh(test_hex_file, ram);
    end
    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (cycles < 5000 && !trap && !test_done) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (req_valid && req_write && req_addr == 32'h0001_1000) begin
        test_done = 1;
        if (req_wdata == 32'd1) begin
          test_passed = 1;
        end else begin
          test_passed = 0;
        end
      end
    end

    if ($value$plusargs("SIG=%s", test_sig_file)) begin
      fd = $fopen(test_sig_file, "w");
      if (fd != 0) begin
        for (int i = 0; i < 64; i = i + 1) begin
          $fdisplay(fd, "%08x", ram[i]);
        end
        $fclose(fd);
      end
    end

    if (test_passed) begin
      $display("RISCV_COMPLIANCE_PASS cycles=%0d", cycles);
    end else begin
      $display("RISCV_COMPLIANCE_FAIL cycles=%0d trap=%0d done=%0d", cycles, trap, test_done);
    end
    $finish;
  end
endmodule
