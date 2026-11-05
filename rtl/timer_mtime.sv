module timer_mtime (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic timer_irq
);
  logic [63:0] mtime;
  logic [63:0] mtimecmp;

  assign timer_irq = (mtime >= mtimecmp);

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = mtime[31:0];
      8'h04: csr_rdata = mtime[63:32];
      8'h08: csr_rdata = mtimecmp[31:0];
      8'h0c: csr_rdata = mtimecmp[63:32];
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      mtime <= 64'd0;
      mtimecmp <= 64'hffff_ffff_ffff_ffff;
    end else begin
      mtime <= mtime + 64'd1;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: mtime[31:0] <= csr_wdata;
          8'h04: mtime[63:32] <= csr_wdata;
          8'h08: mtimecmp[31:0] <= csr_wdata;
          8'h0c: mtimecmp[63:32] <= csr_wdata;
          default: begin end
        endcase
      end
    end
  end
endmodule
