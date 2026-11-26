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
  logic signed [7:0] weight [0:3][0:3];
  logic signed [7:0] shadow_weight [0:3][0:3];
  logic signed [7:0] active_weight [0:3][0:3];
  logic signed [31:0] result [0:3];
  logic signed [31:0] bias [0:3];
  logic signed [31:0] anomaly_thresh;
  logic [4:0] shift_amt;
  logic cfg_accum;
  logic cfg_relu;
  logic cfg_bias;
  logic cfg_matrix;
  logic cfg_sparse;
  logic cfg_clamp;
  logic cfg_thresh_irq;
  logic busy;
  logic done;
  logic thresh_hit;
  integer r, c;
  integer rc, cc;

  function automatic logic signed [31:0] compute_mac_row(
    input logic signed [7:0] a0, input logic signed [7:0] a1,
    input logic signed [7:0] a2, input logic signed [7:0] a3,
    input logic signed [7:0] w0, input logic signed [7:0] w1,
    input logic signed [7:0] w2, input logic signed [7:0] w3,
    input logic signed [31:0] prev,
    input logic signed [31:0] b,
    input logic [4:0] sh,
    input logic do_accum,
    input logic do_relu,
    input logic do_bias,
    input logic do_sparse,
    input logic do_clamp
  );
    logic signed [31:0] m0, m1, m2, m3;
    logic signed [31:0] p_sum;
    logic signed [31:0] a_sum;
    logic signed [31:0] s_sum;
    logic signed [31:0] r_sum;
    logic signed [7:0] sa0, sa1;
    begin
      if (do_sparse) begin
        case (w2[1:0])
          2'd0: sa0 = a0;
          2'd1: sa0 = a1;
          2'd2: sa0 = a2;
          default: sa0 = a3;
        endcase
        case (w2[3:2])
          2'd0: sa1 = a0;
          2'd1: sa1 = a1;
          2'd2: sa1 = a2;
          default: sa1 = a3;
        endcase
        m0 = (sa0 == 8'sd0) ? 32'sd0 : ($signed(sa0) * $signed(w0));
        m1 = (sa1 == 8'sd0) ? 32'sd0 : ($signed(sa1) * $signed(w1));
        p_sum = m0 + m1;
      end else begin
        m0 = (a0 == 8'sd0) ? 32'sd0 : ($signed(a0) * $signed(w0));
        m1 = (a1 == 8'sd0) ? 32'sd0 : ($signed(a1) * $signed(w1));
        m2 = (a2 == 8'sd0) ? 32'sd0 : ($signed(a2) * $signed(w2));
        m3 = (a3 == 8'sd0) ? 32'sd0 : ($signed(a3) * $signed(w3));
        p_sum = m0 + m1 + m2 + m3;
      end
      a_sum = (do_accum ? prev : 32'sd0) + p_sum + (do_bias ? b : 32'sd0);
      s_sum = a_sum >>> sh;
      if (do_relu && s_sum < 32'sd0) r_sum = 32'sd0;
      else r_sum = s_sum;
      if (do_clamp) begin
        if (r_sum > 32'sd127) compute_mac_row = 32'sd127;
        else if (r_sum < -32'sd128) compute_mac_row = -32'sd128;
        else compute_mac_row = r_sum;
      end else begin
        compute_mac_row = r_sum;
      end
    end
  endfunction

  assign thresh_hit = (result[0] >= anomaly_thresh) ||
                      (cfg_matrix && ((result[1] >= anomaly_thresh) ||
                                      (result[2] >= anomaly_thresh) ||
                                      (result[3] >= anomaly_thresh)));

  always_comb begin
    for (rc = 0; rc < 4; rc = rc + 1) begin
      for (cc = 0; cc < 4; cc = cc + 1) begin
        if (csr_valid && csr_write && csr_addr == 8'h00 && csr_wdata[6]) begin
          active_weight[rc][cc] = shadow_weight[rc][cc];
        end else begin
          active_weight[rc][cc] = weight[rc][cc];
        end
      end
    end

    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {22'd0, cfg_thresh_irq, cfg_clamp, cfg_sparse, cfg_matrix, cfg_bias, cfg_relu, cfg_accum, done, busy};
      8'h04: csr_rdata = result[0];
      8'h08: csr_rdata = bias[0];
      8'h0c: csr_rdata = {27'd0, shift_amt};
      8'h10: csr_rdata = {{24{activation[0][7]}}, activation[0]};
      8'h14: csr_rdata = {{24{activation[1][7]}}, activation[1]};
      8'h18: csr_rdata = {{24{activation[2][7]}}, activation[2]};
      8'h1c: csr_rdata = {{24{activation[3][7]}}, activation[3]};
      8'h20: csr_rdata = {{24{weight[0][0][7]}}, weight[0][0]};
      8'h24: csr_rdata = {{24{weight[0][1][7]}}, weight[0][1]};
      8'h28: csr_rdata = {{24{weight[0][2][7]}}, weight[0][2]};
      8'h2c: csr_rdata = {{24{weight[0][3][7]}}, weight[0][3]};
      8'h30: csr_rdata = {activation[3], activation[2], activation[1], activation[0]};
      8'h34: csr_rdata = {weight[0][3], weight[0][2], weight[0][1], weight[0][0]};
      8'h38: csr_rdata = {weight[1][3], weight[1][2], weight[1][1], weight[1][0]};
      8'h3c: csr_rdata = {weight[2][3], weight[2][2], weight[2][1], weight[2][0]};
      8'h40: csr_rdata = {weight[3][3], weight[3][2], weight[3][1], weight[3][0]};
      8'h44: csr_rdata = result[1];
      8'h48: csr_rdata = result[2];
      8'h4c: csr_rdata = result[3];
      8'h50: csr_rdata = {shadow_weight[0][3], shadow_weight[0][2], shadow_weight[0][1], shadow_weight[0][0]};
      8'h54: csr_rdata = {shadow_weight[1][3], shadow_weight[1][2], shadow_weight[1][1], shadow_weight[1][0]};
      8'h58: csr_rdata = {shadow_weight[2][3], shadow_weight[2][2], shadow_weight[2][1], shadow_weight[2][0]};
      8'h5c: csr_rdata = {shadow_weight[3][3], shadow_weight[3][2], shadow_weight[3][1], shadow_weight[3][0]};
      8'h60: csr_rdata = bias[1];
      8'h64: csr_rdata = bias[2];
      8'h68: csr_rdata = bias[3];
      8'h6c: csr_rdata = anomaly_thresh;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      for (r = 0; r < 4; r = r + 1) begin
        result[r] <= 32'sd0;
        bias[r] <= 32'sd0;
        activation[r] <= 8'sd0;
        for (c = 0; c < 4; c = c + 1) begin
          weight[r][c] <= 8'sd0;
          shadow_weight[r][c] <= 8'sd0;
        end
      end
      anomaly_thresh <= 32'sd0;
      shift_amt <= 5'd0;
      cfg_accum <= 1'b0;
      cfg_relu <= 1'b0;
      cfg_bias <= 1'b0;
      cfg_matrix <= 1'b0;
      cfg_sparse <= 1'b0;
      cfg_clamp <= 1'b0;
      cfg_thresh_irq <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      irq <= 1'b0;
    end else begin
      irq <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (csr_wdata[1]) done <= 1'b0;
            cfg_accum <= csr_wdata[2];
            cfg_relu <= csr_wdata[3];
            cfg_bias <= csr_wdata[4];
            cfg_matrix <= csr_wdata[5];
            cfg_sparse <= csr_wdata[7];
            cfg_clamp <= csr_wdata[8];
            cfg_thresh_irq <= csr_wdata[9];
            if (csr_wdata[6]) begin
              for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                  weight[r][c] <= shadow_weight[r][c];
                  shadow_weight[r][c] <= weight[r][c];
                end
              end
            end
            if (csr_wdata[0] && !busy) begin
              result[0] <= compute_mac_row(
                activation[0], activation[1], activation[2], activation[3],
                active_weight[0][0], active_weight[0][1], active_weight[0][2], active_weight[0][3],
                result[0], bias[0], shift_amt,
                csr_wdata[2], csr_wdata[3], csr_wdata[4], csr_wdata[7], csr_wdata[8]
              );
              if (csr_wdata[5]) begin
                result[1] <= compute_mac_row(
                  activation[0], activation[1], activation[2], activation[3],
                  active_weight[1][0], active_weight[1][1], active_weight[1][2], active_weight[1][3],
                  result[1], bias[1], shift_amt,
                  csr_wdata[2], csr_wdata[3], csr_wdata[4], csr_wdata[7], csr_wdata[8]
                );
                result[2] <= compute_mac_row(
                  activation[0], activation[1], activation[2], activation[3],
                  active_weight[2][0], active_weight[2][1], active_weight[2][2], active_weight[2][3],
                  result[2], bias[2], shift_amt,
                  csr_wdata[2], csr_wdata[3], csr_wdata[4], csr_wdata[7], csr_wdata[8]
                );
                result[3] <= compute_mac_row(
                  activation[0], activation[1], activation[2], activation[3],
                  active_weight[3][0], active_weight[3][1], active_weight[3][2], active_weight[3][3],
                  result[3], bias[3], shift_amt,
                  csr_wdata[2], csr_wdata[3], csr_wdata[4], csr_wdata[7], csr_wdata[8]
                );
              end
              busy <= 1'b1;
            end
          end
          8'h08: bias[0] <= csr_wdata;
          8'h0c: shift_amt <= csr_wdata[4:0];
          8'h10: activation[0] <= csr_wdata[7:0];
          8'h14: activation[1] <= csr_wdata[7:0];
          8'h18: activation[2] <= csr_wdata[7:0];
          8'h1c: activation[3] <= csr_wdata[7:0];
          8'h20: weight[0][0] <= csr_wdata[7:0];
          8'h24: weight[0][1] <= csr_wdata[7:0];
          8'h28: weight[0][2] <= csr_wdata[7:0];
          8'h2c: weight[0][3] <= csr_wdata[7:0];
          8'h30: begin
            activation[0] <= csr_wdata[7:0];
            activation[1] <= csr_wdata[15:8];
            activation[2] <= csr_wdata[23:16];
            activation[3] <= csr_wdata[31:24];
          end
          8'h34: begin
            weight[0][0] <= csr_wdata[7:0];
            weight[0][1] <= csr_wdata[15:8];
            weight[0][2] <= csr_wdata[23:16];
            weight[0][3] <= csr_wdata[31:24];
          end
          8'h38: begin
            weight[1][0] <= csr_wdata[7:0];
            weight[1][1] <= csr_wdata[15:8];
            weight[1][2] <= csr_wdata[23:16];
            weight[1][3] <= csr_wdata[31:24];
          end
          8'h3c: begin
            weight[2][0] <= csr_wdata[7:0];
            weight[2][1] <= csr_wdata[15:8];
            weight[2][2] <= csr_wdata[23:16];
            weight[2][3] <= csr_wdata[31:24];
          end
          8'h40: begin
            weight[3][0] <= csr_wdata[7:0];
            weight[3][1] <= csr_wdata[15:8];
            weight[3][2] <= csr_wdata[23:16];
            weight[3][3] <= csr_wdata[31:24];
          end
          8'h50: begin
            shadow_weight[0][0] <= csr_wdata[7:0];
            shadow_weight[0][1] <= csr_wdata[15:8];
            shadow_weight[0][2] <= csr_wdata[23:16];
            shadow_weight[0][3] <= csr_wdata[31:24];
          end
          8'h54: begin
            shadow_weight[1][0] <= csr_wdata[7:0];
            shadow_weight[1][1] <= csr_wdata[15:8];
            shadow_weight[1][2] <= csr_wdata[23:16];
            shadow_weight[1][3] <= csr_wdata[31:24];
          end
          8'h58: begin
            shadow_weight[2][0] <= csr_wdata[7:0];
            shadow_weight[2][1] <= csr_wdata[15:8];
            shadow_weight[2][2] <= csr_wdata[23:16];
            shadow_weight[2][3] <= csr_wdata[31:24];
          end
          8'h5c: begin
            shadow_weight[3][0] <= csr_wdata[7:0];
            shadow_weight[3][1] <= csr_wdata[15:8];
            shadow_weight[3][2] <= csr_wdata[23:16];
            shadow_weight[3][3] <= csr_wdata[31:24];
          end
          8'h60: bias[1] <= csr_wdata;
          8'h64: bias[2] <= csr_wdata;
          8'h68: bias[3] <= csr_wdata;
          8'h6c: anomaly_thresh <= $signed(csr_wdata);
          default: begin end
        endcase
      end else if (auto_infer_trigger && !busy) begin
        activation[0] <= auto_infer_sample[7:0];
        activation[1] <= auto_infer_sample[15:8];
        result[0] <= compute_mac_row(
          auto_infer_sample[7:0], auto_infer_sample[15:8], activation[2], activation[3],
          weight[0][0], weight[0][1], weight[0][2], weight[0][3],
          result[0], bias[0], shift_amt,
          cfg_accum, cfg_relu, cfg_bias, cfg_sparse, cfg_clamp
        );
        if (cfg_matrix) begin
          result[1] <= compute_mac_row(
            auto_infer_sample[7:0], auto_infer_sample[15:8], activation[2], activation[3],
            weight[1][0], weight[1][1], weight[1][2], weight[1][3],
            result[1], bias[1], shift_amt,
            cfg_accum, cfg_relu, cfg_bias, cfg_sparse, cfg_clamp
          );
          result[2] <= compute_mac_row(
            auto_infer_sample[7:0], auto_infer_sample[15:8], activation[2], activation[3],
            weight[2][0], weight[2][1], weight[2][2], weight[2][3],
            result[2], bias[2], shift_amt,
            cfg_accum, cfg_relu, cfg_bias, cfg_sparse, cfg_clamp
          );
          result[3] <= compute_mac_row(
            auto_infer_sample[7:0], auto_infer_sample[15:8], activation[2], activation[3],
            weight[3][0], weight[3][1], weight[3][2], weight[3][3],
            result[3], bias[3], shift_amt,
            cfg_accum, cfg_relu, cfg_bias, cfg_sparse, cfg_clamp
          );
        end
        busy <= 1'b1;
      end
      if (busy) begin
        busy <= 1'b0;
        done <= 1'b1;
        irq <= cfg_thresh_irq ? thresh_hit : 1'b1;
      end
    end
  end
endmodule
