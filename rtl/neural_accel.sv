module neural_accel (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic irq
);
  logic signed [7:0] activation [0:3];
  logic signed [7:0] weight [0:3];
  logic signed [31:0] result;
  logic busy;
  logic done;
  integer idx;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {30'd0, done, busy};
      8'h04: csr_rdata = result;
      8'h10: csr_rdata = {{24{activation[0][7]}}, activation[0]};
      8'h14: csr_rdata = {{24{activation[1][7]}}, activation[1]};
      8'h18: csr_rdata = {{24{activation[2][7]}}, activation[2]};
      8'h1c: csr_rdata = {{24{activation[3][7]}}, activation[3]};
      8'h20: csr_rdata = {{24{weight[0][7]}}, weight[0]};
      8'h24: csr_rdata = {{24{weight[1][7]}}, weight[1]};
      8'h28: csr_rdata = {{24{weight[2][7]}}, weight[2]};
      8'h2c: csr_rdata = {{24{weight[3][7]}}, weight[3]};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      result <= 32'sd0;
      busy <= 1'b0;
      done <= 1'b0;
      irq <= 1'b0;
      for (idx = 0; idx < 4; idx = idx + 1) begin
        activation[idx] <= 8'sd0;
        weight[idx] <= 8'sd0;
      end
    end else begin
      irq <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (csr_wdata[1]) done <= 1'b0;
            if (csr_wdata[0] && !busy) begin
              result <= $signed(activation[0]) * $signed(weight[0]) + $signed(activation[1]) * $signed(weight[1]) + $signed(activation[2]) * $signed(weight[2]) + $signed(activation[3]) * $signed(weight[3]);
              busy <= 1'b1;
            end
          end
          8'h10: activation[0] <= csr_wdata[7:0];
          8'h14: activation[1] <= csr_wdata[7:0];
          8'h18: activation[2] <= csr_wdata[7:0];
          8'h1c: activation[3] <= csr_wdata[7:0];
          8'h20: weight[0] <= csr_wdata[7:0];
          8'h24: weight[1] <= csr_wdata[7:0];
          8'h28: weight[2] <= csr_wdata[7:0];
          8'h2c: weight[3] <= csr_wdata[7:0];
          default: begin end
        endcase
      end
      if (busy) begin
        busy <= 1'b0;
        done <= 1'b1;
        irq <= 1'b1;
      end
    end
  end
endmodule
