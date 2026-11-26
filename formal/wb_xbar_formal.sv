module wb_xbar_formal (
  input logic clk,
  input logic reset,

  input logic m0_cyc_i,
  input logic m0_stb_i,
  input logic m0_we_i,
  input logic [31:0] m0_adr_i,
  input logic [31:0] m0_dat_i,
  input logic [3:0] m0_sel_i,

  input logic m1_cyc_i,
  input logic m1_stb_i,
  input logic m1_we_i,
  input logic [31:0] m1_adr_i,
  input logic [31:0] m1_dat_i,
  input logic [3:0] m1_sel_i,

  input logic m2_cyc_i,
  input logic m2_stb_i,
  input logic m2_we_i,
  input logic [31:0] m2_adr_i,
  input logic [31:0] m2_dat_i,
  input logic [3:0] m2_sel_i,

  input logic [13:0] s_ack_raw,
  input logic [13:0] s_err_raw
);
  logic m0_ack_o, m0_err_o;
  logic [31:0] m0_dat_o;
  logic m1_ack_o, m1_err_o;
  logic [31:0] m1_dat_o;
  logic m2_ack_o, m2_err_o;
  logic [31:0] m2_dat_o;
  logic [1:0] grant_master_o;
  logic [13:0] s_cyc_o;
  logic [13:0] s_stb_o;
  logic s_we_o;
  logic [31:0] s_adr_o;
  logic [31:0] s_dat_o;
  logic [3:0] s_sel_o;
  logic [13:0] s_ack_i;
  logic [13:0] s_err_i;

  logic past_valid;
  logic [2:0] m0_wait_cnt;

  assign s_ack_i = s_ack_raw & s_cyc_o & s_stb_o;
  assign s_err_i = s_err_raw & s_cyc_o & s_stb_o & ~s_ack_i;

  wb_interconnect dut (
    .clk(clk), .reset(reset),
    .m0_cyc_i(m0_cyc_i), .m0_stb_i(m0_stb_i), .m0_we_i(m0_we_i), .m0_adr_i(m0_adr_i), .m0_dat_i(m0_dat_i), .m0_sel_i(m0_sel_i),
    .m0_ack_o(m0_ack_o), .m0_dat_o(m0_dat_o), .m0_err_o(m0_err_o),
    .m1_cyc_i(m1_cyc_i), .m1_stb_i(m1_stb_i), .m1_we_i(m1_we_i), .m1_adr_i(m1_adr_i), .m1_dat_i(m1_dat_i), .m1_sel_i(m1_sel_i),
    .m1_ack_o(m1_ack_o), .m1_dat_o(m1_dat_o), .m1_err_o(m1_err_o),
    .m2_cyc_i(m2_cyc_i), .m2_stb_i(m2_stb_i), .m2_we_i(m2_we_i), .m2_adr_i(m2_adr_i), .m2_dat_i(m2_dat_i), .m2_sel_i(m2_sel_i),
    .m2_ack_o(m2_ack_o), .m2_dat_o(m2_dat_o), .m2_err_o(m2_err_o),
    .grant_master_o(grant_master_o),
    .s_cyc_o(s_cyc_o), .s_stb_o(s_stb_o), .s_we_o(s_we_o), .s_adr_o(s_adr_o), .s_dat_o(s_dat_o), .s_sel_o(s_sel_o),
    .s_ack_i(s_ack_i),
    .s0_dat_i(32'd0), .s1_dat_i(32'd0), .s2_dat_i(32'd0), .s3_dat_i(32'd0),
    .s4_dat_i(32'd0), .s5_dat_i(32'd0), .s6_dat_i(32'd0), .s7_dat_i(32'd0),
    .s8_dat_i(32'd0), .s9_dat_i(32'd0), .s10_dat_i(32'd0), .s11_dat_i(32'd0),
    .s12_dat_i(32'd0), .s13_dat_i(32'd0),
    .s_err_i(s_err_i)
  );

  initial begin
    past_valid = 1'b0;
    m0_wait_cnt = 3'd0;
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    if (!past_valid) begin
      assume (reset);
      assume (m0_wait_cnt == 3'd0);
    end

    if (reset) begin
      m0_wait_cnt <= 3'd0;
    end else begin
      if (m0_cyc_i && m0_stb_i && !(m0_ack_o || m0_err_o)) begin
        if (m0_wait_cnt < 3'd7) m0_wait_cnt <= m0_wait_cnt + 3'd1;
      end else begin
        m0_wait_cnt <= 3'd0;
      end
    end

    if (past_valid && !reset && $past(!reset)) begin
      if ($past(m0_cyc_i && m0_stb_i && !(m0_ack_o || m0_err_o))) begin
        assume (m0_cyc_i && m0_stb_i);
        assume ($stable({m0_we_i, m0_adr_i, m0_dat_i, m0_sel_i}));
      end
      if ($past(m1_cyc_i && m1_stb_i && !(m1_ack_o || m1_err_o))) begin
        assume (m1_cyc_i && m1_stb_i);
        assume ($stable({m1_we_i, m1_adr_i, m1_dat_i, m1_sel_i}));
      end
      if ($past(m2_cyc_i && m2_stb_i && !(m2_ack_o || m2_err_o))) begin
        assume (m2_cyc_i && m2_stb_i);
        assume ($stable({m2_we_i, m2_adr_i, m2_dat_i, m2_sel_i}));
      end
      if ($past(|(s_cyc_o & s_stb_o & ~(s_ack_i | s_err_i)))) begin
        assume ((s_cyc_o & s_stb_o) == (s_ack_i | s_err_i));
      end

      assert ($onehot0({m2_ack_o, m1_ack_o, m0_ack_o}));
      assert ($onehot0({m2_err_o, m1_err_o, m0_err_o}));
      assert ($onehot0(s_cyc_o));
      assert ($onehot0(s_stb_o));
      assert (!(m0_ack_o || m0_err_o) || (m0_cyc_i && m0_stb_i));
      assert (!(m1_ack_o || m1_err_o) || (m1_cyc_i && m1_stb_i));
      assert (!(m2_ack_o || m2_err_o) || (m2_cyc_i && m2_stb_i));
      assert (m0_wait_cnt <= 3'd6);
    end
  end
endmodule
