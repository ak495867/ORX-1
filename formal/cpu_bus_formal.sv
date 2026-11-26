module cpu_bus_formal (
  input logic clk,
  input logic reset,
  input logic [31:0] imem_rdata,
  input logic req_ready,
  input logic rsp_valid_in,
  input logic [31:0] rsp_rdata,
  input logic rsp_err_in,
  input logic irq_external,
  input logic irq_timer
);
  logic [31:0] imem_addr;
  logic req_valid;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic rsp_err;
  logic trap;
  logic core_sleep;
  logic [31:0] perf_cycles;
  logic [31:0] perf_instructions;
  logic [31:0] perf_loads;
  logic [31:0] perf_stores;
  logic [31:0] perf_branches;
  logic [31:0] perf_bus_requests;
  logic [31:0] perf_wait_cycles;
  logic past_valid;
  logic wait_pending;

  assign rsp_valid = rsp_valid_in && ((req_valid && req_ready) || wait_pending);
  assign rsp_err = rsp_err_in && rsp_valid;

  rv32i_core dut (
    .clk(clk), .reset(reset), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .req_valid(req_valid), .req_ready(req_ready), .req_write(req_write),
    .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err), .trap(trap),
    .core_sleep(core_sleep),
    .perf_cycles(perf_cycles), .perf_instructions(perf_instructions),
    .perf_loads(perf_loads), .perf_stores(perf_stores), .perf_branches(perf_branches),
    .perf_bus_requests(perf_bus_requests), .perf_wait_cycles(perf_wait_cycles),
    .irq_external(irq_external), .irq_timer(irq_timer)
  );

  initial begin
    past_valid = 1'b0;
    wait_pending = 1'b0;
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    if (!past_valid) begin
      assume (reset);
    end
    if (reset) begin
      wait_pending <= 1'b0;
    end else begin
      if (req_valid && req_ready && !rsp_valid) begin
        wait_pending <= 1'b1;
      end else if (rsp_valid) begin
        wait_pending <= 1'b0;
      end
    end

    if (past_valid && !reset && $past(reset)) begin
      assert (!trap && !req_valid && !core_sleep);
    end
    if (past_valid && !reset && $past(!reset)) begin
      assert (!rsp_valid || (req_valid && req_ready) || wait_pending);
      assert (!(req_valid && $past(req_valid && req_ready && !rsp_valid)));
      assert (!(trap && core_sleep));
      if ($past(req_valid && !req_ready)) begin
        assert (req_valid);
        assert ($stable({req_write, req_addr, req_wdata, req_wstrb}));
      end
      if ($past(trap)) begin
        assert (trap);
      end
      assert (perf_cycles == $past(perf_cycles) + 32'd1);
      assert (perf_instructions == $past(perf_instructions) || perf_instructions == $past(perf_instructions) + 32'd1);
      assert (perf_bus_requests == $past(perf_bus_requests) || perf_bus_requests == $past(perf_bus_requests) + 32'd1);
      assert (perf_wait_cycles == $past(perf_wait_cycles) || perf_wait_cycles == $past(perf_wait_cycles) + 32'd1);
      assert (perf_loads == $past(perf_loads) || perf_loads == $past(perf_loads) + 32'd1);
      assert (perf_stores == $past(perf_stores) || perf_stores == $past(perf_stores) + 32'd1);
    end
  end
endmodule
