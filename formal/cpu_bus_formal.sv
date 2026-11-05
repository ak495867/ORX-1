module cpu_bus_formal;
  logic clk;
  logic reset;
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
  logic past_valid;

  always #1 clk = ~clk;
  always_comb begin
    case (imem_addr[3:2])
      2'b00: imem_rdata = 32'h0050_2023;
      2'b01: imem_rdata = 32'h0000_2083;
      default: imem_rdata = 32'h0000_0013;
    endcase
    rsp_valid = req_valid && req_ready;
    rsp_rdata = 32'd0;
    rsp_err = 1'b0;
  end

  rv32i_core dut (
    .clk(clk), .reset(reset), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .req_valid(req_valid), .req_ready(req_ready), .req_write(req_write),
    .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err), .trap(trap),
    .perf_cycles(perf_cycles), .perf_instructions(perf_instructions),
    .perf_loads(perf_loads), .perf_stores(perf_stores), .perf_branches(perf_branches),
    .perf_bus_requests(perf_bus_requests), .perf_wait_cycles(perf_wait_cycles)
  );

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    past_valid = 1'b0;
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    if (past_valid && !reset) begin
      assert (!rsp_valid || req_valid);
      if ($past(req_valid && !req_ready)) begin
        assert (req_valid);
        assert ($stable({req_write, req_addr, req_wdata, req_wstrb}));
      end
      assert (perf_cycles >= $past(perf_cycles));
      assert (perf_instructions >= $past(perf_instructions));
      assert (perf_bus_requests >= $past(perf_bus_requests));
    end
  end
endmodule
