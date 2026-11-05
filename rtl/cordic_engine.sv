module cordic_engine (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic cordic_irq
);
  logic signed [31:0] x_reg;
  logic signed [31:0] y_reg;
  logic signed [31:0] z_reg;
  logic signed [31:0] x_shift;
  logic signed [31:0] y_shift;
  logic signed [31:0] angle_lut;
  logic d_dir;
  logic mode_rot;
  logic busy;
  logic done;
  logic [3:0] step_cnt;

  function automatic logic signed [31:0] get_atan_lut(input logic [3:0] step);
    case (step)
      4'd0:  get_atan_lut = 32'sd8192;
      4'd1:  get_atan_lut = 32'sd4836;
      4'd2:  get_atan_lut = 32'sd2555;
      4'd3:  get_atan_lut = 32'sd1297;
      4'd4:  get_atan_lut = 32'sd651;
      4'd5:  get_atan_lut = 32'sd326;
      4'd6:  get_atan_lut = 32'sd163;
      4'd7:  get_atan_lut = 32'sd81;
      4'd8:  get_atan_lut = 32'sd41;
      4'd9:  get_atan_lut = 32'sd20;
      4'd10: get_atan_lut = 32'sd10;
      4'd11: get_atan_lut = 32'sd5;
      4'd12: get_atan_lut = 32'sd3;
      4'd13: get_atan_lut = 32'sd1;
      4'd14: get_atan_lut = 32'sd1;
      default: get_atan_lut = 32'sd0;
    endcase
  endfunction

  assign cordic_irq = done;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {28'd0, cordic_irq, done, busy, mode_rot};
      8'h04: csr_rdata = x_reg;
      8'h08: csr_rdata = y_reg;
      8'h0c: csr_rdata = z_reg;
      8'h10: csr_rdata = (x_reg * 32'sd39797) >>> 16;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      x_reg <= 32'sd0;
      y_reg <= 32'sd0;
      z_reg <= 32'sd0;
      mode_rot <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      step_cnt <= 4'd0;
    end else begin
      done <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            mode_rot <= csr_wdata[0];
            if (csr_wdata[1]) done <= 1'b0;
            if (csr_wdata[2] && !busy) begin
              busy <= 1'b1;
              step_cnt <= 4'd0;
            end
          end
          8'h04: x_reg <= $signed(csr_wdata);
          8'h08: y_reg <= $signed(csr_wdata);
          8'h0c: z_reg <= $signed(csr_wdata);
          default: begin end
        endcase
      end else if (busy) begin
        x_shift = x_reg >>> step_cnt;
        y_shift = y_reg >>> step_cnt;
        angle_lut = get_atan_lut(step_cnt);

        if (mode_rot) begin
          d_dir = (z_reg >= 32'sd0) ? 1'b1 : 1'b0;
        end else begin
          d_dir = (y_reg < 32'sd0) ? 1'b1 : 1'b0;
        end

        if (d_dir) begin
          x_reg <= x_reg - y_shift;
          y_reg <= y_reg + x_shift;
          z_reg <= z_reg - angle_lut;
        end else begin
          x_reg <= x_reg + y_shift;
          y_reg <= y_reg - x_shift;
          z_reg <= z_reg + angle_lut;
        end

        if (step_cnt == 4'd15) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          step_cnt <= step_cnt + 4'd1;
        end
      end
    end
  end
endmodule
