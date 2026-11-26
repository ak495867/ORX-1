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
  logic signed [31:0] x_mid;
  logic signed [31:0] y_mid;
  logic signed [31:0] z_mid;
  logic signed [31:0] x_nxt;
  logic signed [31:0] y_nxt;
  logic signed [31:0] z_nxt;
  logic [3:0] step0;
  logic [3:0] step1;
  logic d_dir0;
  logic d_dir1;
  logic mode_rot;
  logic busy;
  logic done;
  logic [2:0] step_cnt;

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
  assign step0 = {step_cnt, 1'b0};
  assign step1 = {step_cnt, 1'b1};
  assign d_dir0 = mode_rot ? (z_reg >= 32'sd0) : (y_reg < 32'sd0);
  assign x_mid = d_dir0 ? (x_reg - (y_reg >>> step0)) : (x_reg + (y_reg >>> step0));
  assign y_mid = d_dir0 ? (y_reg + (x_reg >>> step0)) : (y_reg - (x_reg >>> step0));
  assign z_mid = d_dir0 ? (z_reg - get_atan_lut(step0)) : (z_reg + get_atan_lut(step0));

  assign d_dir1 = mode_rot ? (z_mid >= 32'sd0) : (y_mid < 32'sd0);
  assign x_nxt = d_dir1 ? (x_mid - (y_mid >>> step1)) : (x_mid + (y_mid >>> step1));
  assign y_nxt = d_dir1 ? (y_mid + (x_mid >>> step1)) : (y_mid - (x_mid >>> step1));
  assign z_nxt = d_dir1 ? (z_mid - get_atan_lut(step1)) : (z_mid + get_atan_lut(step1));

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
      step_cnt <= 3'd0;
    end else begin
      done <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            mode_rot <= csr_wdata[0];
            if (csr_wdata[1]) done <= 1'b0;
            if (csr_wdata[2] && !busy) begin
              busy <= 1'b1;
              step_cnt <= 3'd0;
            end
          end
          8'h04: x_reg <= $signed(csr_wdata);
          8'h08: y_reg <= $signed(csr_wdata);
          8'h0c: z_reg <= $signed(csr_wdata);
          default: begin end
        endcase
      end else if (busy) begin
        x_reg <= x_nxt;
        y_reg <= y_nxt;
        z_reg <= z_nxt;
        if (step_cnt == 3'd7) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          step_cnt <= step_cnt + 3'd1;
        end
      end
    end
  end
endmodule
