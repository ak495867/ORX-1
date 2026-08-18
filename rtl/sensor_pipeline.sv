module sensor_pipeline #(
  parameter integer WIDTH = 16
) (
  input logic clk,
  input logic reset,
  input logic sample_valid,
  input logic [WIDTH-1:0] sample_data,
  input logic cfg_enable,
  input logic cfg_clear,
  output logic result_valid,
  output logic [WIDTH-1:0] result_data,
  output logic irq
);
  logic [WIDTH-1:0] samples [0:3];
  logic [WIDTH+1:0] sum;
  logic [WIDTH+1:0] next_sum;
  logic [1:0] count;
  integer index;

  assign sum = {2'd0, samples[0]} + {2'd0, samples[1]} + {2'd0, samples[2]} + {2'd0, samples[3]};
  assign next_sum = sum + {2'd0, sample_data};

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      count <= 2'd0;
      result_valid <= 1'b0;
      result_data <= '0;
      irq <= 1'b0;
      for (index = 0; index < 4; index = index + 1) samples[index] <= '0;
    end else begin
      result_valid <= 1'b0;
      irq <= 1'b0;
      if (cfg_clear) begin
        count <= 2'd0;
        for (index = 0; index < 4; index = index + 1) samples[index] <= '0;
      end else if (cfg_enable && sample_valid) begin
        samples[0] <= samples[1];
        samples[1] <= samples[2];
        samples[2] <= samples[3];
        samples[3] <= sample_data;
        if (count != 2'd3) begin
          count <= count + 2'd1;
        end else begin
          result_data <= next_sum[WIDTH+1:2];
          result_valid <= 1'b1;
          irq <= 1'b1;
        end
      end
    end
  end
endmodule
