module sensor_pipeline #(
  parameter integer WIDTH = 16
) (
  input logic clk,
  input logic reset,
  input logic sample_valid,
  input logic [WIDTH-1:0] sample_data,
  input logic cfg_enable,
  input logic cfg_clear,
  input logic [1:0] cfg_depth,
  input logic cfg_thresh_en,
  input logic [WIDTH-1:0] cfg_thresh_low,
  input logic [WIDTH-1:0] cfg_thresh_high,
  output logic result_valid,
  output logic [WIDTH-1:0] result_data,
  output logic alert,
  output logic irq
);
  logic [WIDTH-1:0] samples [0:3];
  logic [WIDTH+1:0] next_sum;
  logic [WIDTH:0] next_sum_2;
  logic [WIDTH-1:0] computed_result;
  logic [1:0] count;
  logic [1:0] target_count;
  integer index;

  logic signed [WIDTH+1:0] pred_sample;
  logic signed [WIDTH+1:0] pred_delta;
  logic [WIDTH-1:0] abs_delta;

  assign pred_sample = ($signed({2'd0, samples[3]}) <<< 1) - $signed({2'd0, samples[2]});
  assign pred_delta = $signed({2'd0, sample_data}) - pred_sample;
  assign abs_delta = (pred_delta < 0) ? (-pred_delta[WIDTH-1:0]) : pred_delta[WIDTH-1:0];

  assign next_sum = {2'd0, samples[1]} + {2'd0, samples[2]} + {2'd0, samples[3]} + {2'd0, sample_data};
  assign next_sum_2 = {1'b0, samples[3]} + {1'b0, sample_data};

  always_comb begin
    case (cfg_depth)
      2'b00: begin
        target_count = 2'd0;
        computed_result = sample_data;
      end
      2'b01: begin
        target_count = 2'd1;
        computed_result = next_sum_2[WIDTH:1];
      end
      2'b10: begin
        target_count = 2'd3;
        computed_result = next_sum[WIDTH+1:2];
      end
      default: begin
        target_count = 2'd2;
        computed_result = abs_delta;
      end
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      count <= 2'd0;
      result_valid <= 1'b0;
      result_data <= '0;
      alert <= 1'b0;
      irq <= 1'b0;
      for (index = 0; index < 4; index = index + 1) samples[index] <= '0;
    end else begin
      result_valid <= 1'b0;
      irq <= 1'b0;
      if (cfg_clear) begin
        count <= 2'd0;
        alert <= 1'b0;
        for (index = 0; index < 4; index = index + 1) samples[index] <= '0;
      end else if (cfg_enable && sample_valid) begin
        samples[0] <= samples[1];
        samples[1] <= samples[2];
        samples[2] <= samples[3];
        samples[3] <= sample_data;
        if (count < target_count) begin
          count <= count + 2'd1;
        end else begin
          result_data <= computed_result;
          result_valid <= 1'b1;
          irq <= 1'b1;
          if (cfg_thresh_en && (computed_result < cfg_thresh_low || computed_result > cfg_thresh_high)) begin
            alert <= 1'b1;
          end else begin
            alert <= 1'b0;
          end
        end
      end
    end
  end
endmodule
