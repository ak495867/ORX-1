module sys_ctrl (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  input logic host_grant,
  input logic boot_release,
  output logic cpu_reset_req,
  output logic wdt_reset_out
);
  logic cpu_hold_reset;
  logic boot_gate_en;
  logic wdt_reset_flag;
  logic wdt_enable;
  logic [31:0] wdt_load;
  logic [31:0] wdt_count;

  assign cpu_reset_req = cpu_hold_reset | (boot_gate_en & !boot_release) | wdt_reset_out;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {29'd0, wdt_reset_flag, boot_gate_en, cpu_hold_reset};
      8'h04: csr_rdata = wdt_load;
      8'h08: csr_rdata = {31'd0, wdt_enable};
      8'h0c: csr_rdata = wdt_count;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      cpu_hold_reset <= 1'b0;
      boot_gate_en <= 1'b0;
      wdt_reset_flag <= 1'b0;
      wdt_enable <= 1'b0;
      wdt_load <= 32'h0010_0000;
      wdt_count <= 32'h0010_0000;
      wdt_reset_out <= 1'b0;
    end else begin
      wdt_reset_out <= 1'b0;
      if (wdt_enable) begin
        if (wdt_count == 32'd0) begin
          wdt_reset_out <= 1'b1;
          wdt_reset_flag <= 1'b1;
          wdt_enable <= 1'b0;
          wdt_count <= wdt_load;
        end else begin
          wdt_count <= wdt_count - 32'd1;
        end
      end

      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (host_grant) begin
              cpu_hold_reset <= csr_wdata[0];
              boot_gate_en <= csr_wdata[1];
            end
            if (csr_wdata[2]) wdt_reset_flag <= 1'b0;
          end
          8'h04: begin
            wdt_load <= csr_wdata;
            if (!wdt_enable) wdt_count <= csr_wdata;
          end
          8'h08: begin
            wdt_enable <= csr_wdata[0];
            if (csr_wdata[1] || (csr_wdata[0] && !wdt_enable)) begin
              wdt_count <= wdt_load;
            end
          end
          default: begin end
        endcase
      end
    end
  end
endmodule
