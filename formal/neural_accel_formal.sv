module neural_accel_formal (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  input logic auto_infer_trigger,
  input logic [15:0] auto_infer_sample
);
  logic [31:0] csr_rdata;
  logic irq;
  logic past_valid;

  neural_accel dut (
    .clk(clk), .reset(reset),
    .csr_valid(csr_valid), .csr_write(csr_write), .csr_addr(csr_addr), .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata), .irq(irq),
    .auto_infer_trigger(auto_infer_trigger), .auto_infer_sample(auto_infer_sample)
  );

  initial begin
    past_valid = 1'b0;
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    if (!past_valid) begin
      assume (reset);
    end

    if (past_valid && !reset && $past(!reset)) begin
      if ($past(irq)) begin
        assert (!irq);
      end
      if ($past(csr_addr == 8'h00 && csr_rdata[0]) && csr_addr == 8'h00) begin
        assert (!csr_rdata[0] && csr_rdata[1]);
      end
      if (past_valid && $past(past_valid) && $past(!reset, 2)) begin
        if ($past(csr_valid && csr_write && csr_addr == 8'h00 && csr_wdata[0] && csr_wdata[8], 2) &&
            $past(csr_addr == 8'h00 && !csr_rdata[0], 2) &&
            csr_addr == 8'h04) begin
          assert ($signed(csr_rdata) >= -32'sd128 && $signed(csr_rdata) <= 32'sd127);
        end
      end
    end
  end
endmodule
