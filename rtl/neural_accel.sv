module neural_accel (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic irq,
  input logic auto_infer_trigger,
  input logic [15:0] auto_infer_sample
);
  logic signed [7:0] activation [0:3];
  logic signed [7:0] weight [0:3];
  logic signed [31:0] result;
  logic signed [31:0] bias;
  logic [4:0] shift_amt;
  logic cfg_accum;
  logic cfg_relu;
  logic cfg_bias;
  logic busy;
  logic done;
  integer idx;

  function automatic logic signed [31:0] compute_step(
    input logic signed [7:0] a0, input logic signed [7:0] a1,
    input logic signed [7:0] a2, input logic signed [7:0] a3,
    input logic signed [7:0] w0, input logic signed [7:0] w1,
    input logic signed [7:0] w2, input logic signed [7:0] w3,
    input logic signed [31:0] prev,
    input logic signed [31:0] b,
    input logic [4:0] sh,
    input logic do_accum,
    input logic do_relu,
    input logic do_bias
  );
    logic signed [31:0] p_sum;
    logic signed [31:0] a_sum;
    logic signed [31:0] s_sum;
    begin
      p_sum = $signed(a0) * $signed(w0) + $signed(a1) * $signed(w1) + $signed(a2) * $signed(w2) + $signed(a3) * $signed(w3);
      a_sum = (do_accum ? prev : 32'sd0) + p_sum + (do_bias ? b : 32'sd0);
      s_sum = a_sum >>> sh;
      if (do_relu && s_sum < 32'sd0) compute_step = 32'sd0;
      else compute_step = s_sum;
    end
  endfunction

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {27'd0, cfg_bias, cfg_relu, cfg_accum, done, busy};
      8'h04: csr_rdata = result;
      8'h08: csr_rdata = bias;
      8'h0c: csr_rdata = {27'd0, shift_amt};
      8'h10: csr_rdata = {{24{activation[0][7]}}, activation[0]};
      8'h14: csr_rdata = {{24{activation[1][7]}}, activation[1]};
      8'h18: csr_rdata = {{24{activation[2][7]}}, activation[2]};
      8'h1c: csr_rdata = {{24{activation[3][7]}}, activation[3]};
      8'h20: csr_rdata = {{24{weight[0][7]}}, weight[0]};
      8'h24: csr_rdata = {{24{weight[1][7]}}, weight[1]};
      8'h28: csr_rdata = {{24{weight[2][7]}}, weight[2]};
      8'h2c: csr_rdata = {{24{weight[3][7]}}, weight[3]};
      8'h30: csr_rdata = {activation[3], activation[2], activation[1], activation[0]};
      8'h34: csr_rdata = {weight[3], weight[2], weight[1], weight[0]};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      result <= 32'sd0;
      bias <= 32'sd0;
      shift_amt <= 5'd0;
      cfg_accum <= 1'b0;
      cfg_relu <= 1'b0;
      cfg_bias <= 1'b0;
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
            if (csr_wdata[2]) cfg_accum <= 1'b1;
            else cfg_accum <= 1'b0;
            if (csr_wdata[3]) cfg_relu <= 1'b1;
            else cfg_relu <= 1'b0;
            if (csr_wdata[4]) cfg_bias <= 1'b1;
            else cfg_bias <= 1'b0;
            if (csr_wdata[0] && !busy) begin
              result <= compute_step(
                activation[0], activation[1], activation[2], activation[3],
                weight[0], weight[1], weight[2], weight[3],
                result, bias, shift_amt,
                csr_wdata[2], csr_wdata[3], csr_wdata[4]
              );
              busy <= 1'b1;
            end
          end
          8'h08: bias <= csr_wdata;
          8'h0c: shift_amt <= csr_wdata[4:0];
          8'h10: activation[0] <= csr_wdata[7:0];
          8'h14: activation[1] <= csr_wdata[7:0];
          8'h18: activation[2] <= csr_wdata[7:0];
          8'h1c: activation[3] <= csr_wdata[7:0];
          8'h20: weight[0] <= csr_wdata[7:0];
          8'h24: weight[1] <= csr_wdata[7:0];
          8'h28: weight[2] <= csr_wdata[7:0];
          8'h2c: weight[3] <= csr_wdata[7:0];
          8'h30: begin
            activation[0] <= csr_wdata[7:0];
            activation[1] <= csr_wdata[15:8];
            activation[2] <= csr_wdata[23:16];
            activation[3] <= csr_wdata[31:24];
          end
          8'h34: begin
            weight[0] <= csr_wdata[7:0];
            weight[1] <= csr_wdata[15:8];
            weight[2] <= csr_wdata[23:16];
            weight[3] <= csr_wdata[31:24];
          end
          default: begin end
        endcase
      end else if (auto_infer_trigger && !busy) begin
        activation[0] <= auto_infer_sample[7:0];
        activation[1] <= auto_infer_sample[15:8];
        result <= compute_step(
          auto_infer_sample[7:0], auto_infer_sample[15:8], activation[2], activation[3],
          weight[0], weight[1], weight[2], weight[3],
          result, bias, shift_amt,
          cfg_accum, cfg_relu, cfg_bias
        );
        busy <= 1'b1;
      end
      if (busy) begin
        busy <= 1'b0;
        done <= 1'b1;
        irq <= 1'b1;
      end
    end
  end
endmodule
