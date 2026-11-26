module gpio_ctrl (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  input logic [15:0] gpio_in,
  output logic [15:0] gpio_out,
  output logic [15:0] gpio_oe,
  output logic gpio_irq
);
  logic [15:0] in_sync_0;
  logic [15:0] in_sync_1;
  logic [15:0] in_prev;
  logic [15:0] irq_en;
  logic [15:0] irq_pending;
  logic [15:0] rising_edges;
  logic _unused_wdata;

  assign _unused_wdata = &{1'b0, csr_wdata[31:16]};
  assign rising_edges = in_sync_1 & ~in_prev;
  assign gpio_irq = |(irq_pending & irq_en);

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {16'd0, in_sync_1};
      8'h04: csr_rdata = {16'd0, gpio_out};
      8'h08: csr_rdata = {16'd0, gpio_oe};
      8'h0c: csr_rdata = {16'd0, irq_en};
      8'h10: csr_rdata = {16'd0, irq_pending};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      in_sync_0 <= 16'd0;
      in_sync_1 <= 16'd0;
      in_prev <= 16'd0;
      gpio_out <= 16'd0;
      gpio_oe <= 16'd0;
      irq_en <= 16'd0;
      irq_pending <= 16'd0;
    end else begin
      in_sync_0 <= gpio_in;
      in_sync_1 <= in_sync_0;
      in_prev <= in_sync_1;
      irq_pending <= (irq_pending & ~((csr_valid && csr_write && csr_addr == 8'h10) ? csr_wdata[15:0] : 16'd0)) | rising_edges;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h04: gpio_out <= csr_wdata[15:0];
          8'h08: gpio_oe <= csr_wdata[15:0];
          8'h0c: irq_en <= csr_wdata[15:0];
          default: begin end
        endcase
      end
    end
  end
endmodule
