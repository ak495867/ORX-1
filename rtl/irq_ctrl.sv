module irq_ctrl (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  input logic [5:0] irq_sources,
  output logic irq_out
);
  logic [5:0] irq_enable;
  logic [5:0] irq_status;

  assign irq_status = irq_sources & irq_enable;
  assign irq_out = |irq_status;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {26'd0, irq_sources};
      8'h04: csr_rdata = {26'd0, irq_enable};
      8'h08: csr_rdata = {26'd0, irq_status};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      irq_enable <= 6'd0;
    end else if (csr_valid && csr_write && csr_addr == 8'h04) begin
      irq_enable <= csr_wdata[5:0];
    end
  end
endmodule
