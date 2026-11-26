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
  input logic [15:0] auto_infer_sample,
  output logic tdma_req_valid,
  input logic tdma_req_ready,
  output logic tdma_req_write,
  output logic [31:0] tdma_req_addr,
  output logic [31:0] tdma_req_wdata,
  output logic [3:0] tdma_req_wstrb,
  input logic tdma_rsp_valid,
  input logic [31:0] tdma_rsp_rdata
);
  logic signed [7:0] activation [0:7];
  logic signed [7:0] weight [0:7][0:7];
  logic signed [7:0] shadow_weight [0:3][0:3];
  logic signed [31:0] result [0:7];
  logic signed [31:0] bias [0:7];
  logic signed [31:0] anomaly_thresh;
  logic [4:0] shift_amt;
  logic cfg_accum;
  logic cfg_relu;
  logic cfg_bias;
  logic cfg_matrix;
  logic cfg_sparse;
  logic cfg_clamp;
  logic cfg_thresh_irq;
  logic cfg_8x8;
  logic busy;
  logic done;
  logic thresh_hit;

  typedef enum logic [2:0] {TDMA_IDLE, TDMA_RD_B, TDMA_RD_W, TDMA_RD_A, TDMA_EXEC, TDMA_WR} tdma_state_t;
  tdma_state_t tdma_state;
  logic [31:0] tdma_act_base;
  logic [31:0] tdma_w_base;
  logic [31:0] tdma_bias_base;
  logic [31:0] tdma_dst_base;
  logic [4:0] tdma_k_words;
  logic [2:0] tdma_out_tiles;
  logic [7:0] tdma_batch_cnt;
  logic tdma_ws;
  logic tdma_relu;
  logic tdma_bias_en;
  logic tdma_clamp;
  logic [4:0] tdma_shift;
  logic tdma_mode_8out;
  logic tdma_busy;
  logic tdma_done;
  logic [7:0] tdma_b_idx;
  logic [2:0] tdma_t_idx;
  logic [4:0] tdma_k_idx;
  logic [3:0] tdma_step_idx;
  logic [3:0] tdma_w_idx;
  logic [31:0] tdma_cur_w_ptr;
  logic [31:0] tdma_cur_b_ptr;
  logic [31:0] tdma_cur_a_ptr;
  logic [31:0] tdma_act_batch_ptr;
  logic [31:0] tdma_cur_d_ptr;
  logic tdma_exec_pulse;

  logic csr_go;
  logic auto_go;
  logic op_go;
  logic op_accum;
  logic op_relu;
  logic op_bias;
  logic op_matrix;
  logic op_sparse;
  logic op_clamp;
  logic op_wide;
  logic op_8out;
  logic [4:0] op_shift;
  logic op_use_shadow;

  logic signed [7:0] op_act [0:7];
  logic signed [7:0] op_w [0:7][0:7];
  logic signed [7:0] eff_act [0:7][0:7];
  logic signed [7:0] eff_w [0:7][0:7];
  logic signed [15:0] mac_prod [0:7][0:7];
  logic signed [31:0] mac_next_res [0:7];

  integer r, c;
  integer rc, cc;

  function automatic logic [7:0] sat_s8(input logic signed [31:0] val);
    begin
      if (val > 32'sd127) sat_s8 = 8'd127;
      else if (val < -32'sd128) sat_s8 = 8'h80;
      else sat_s8 = val[7:0];
    end
  endfunction

  assign tdma_req_wstrb = 4'b1111;
  assign csr_go = csr_valid && csr_write && (csr_addr == 8'h00) && csr_wdata[0] && !busy && !tdma_busy;
  assign auto_go = !(csr_valid && csr_write) && auto_infer_trigger && !busy && !tdma_busy;
  assign tdma_exec_pulse = tdma_busy && (tdma_state == TDMA_EXEC);
  assign op_go = csr_go || auto_go || tdma_exec_pulse;
  assign op_use_shadow = csr_go && csr_wdata[6];

  logic [4:0] tdma_k_rem;
  logic [1:0] tdma_k_chunk;
  logic tdma_is_last_k;
  logic [3:0] tdma_w_last;
  logic [2:0] tdma_w_row;
  logic tdma_w_hi;
  logic tdma_ws_fast;

  assign tdma_k_rem = tdma_k_words - tdma_k_idx;
  assign tdma_k_chunk = (tdma_k_rem >= 5'd2) ? 2'd2 : 2'd1;
  assign tdma_is_last_k = (tdma_k_idx + {3'd0, tdma_k_chunk}) >= tdma_k_words;
  assign tdma_w_row = tdma_mode_8out ? tdma_w_idx[2:0] : {1'b0, tdma_w_idx[1:0]};
  assign tdma_w_hi = tdma_mode_8out ? tdma_w_idx[3] : tdma_w_idx[2];
  assign tdma_ws_fast = tdma_ws && (tdma_k_words <= 5'd2) && (tdma_out_tiles == 3'd1);

  always_comb begin
    case ({tdma_mode_8out, (tdma_k_chunk == 2'd2)})
      2'b00: tdma_w_last = 4'd3;
      2'b01: tdma_w_last = 4'd7;
      2'b10: tdma_w_last = 4'd7;
      default: tdma_w_last = 4'd15;
    endcase
  end

  always_comb begin
    if (csr_go) begin
      op_accum = csr_wdata[2];
      op_relu = csr_wdata[3];
      op_bias = csr_wdata[4];
      op_matrix = csr_wdata[5] || csr_wdata[10];
      op_sparse = csr_wdata[7];
      op_clamp = csr_wdata[8];
      op_wide = csr_wdata[10];
      op_8out = csr_wdata[10];
      op_shift = shift_amt;
    end else if (auto_go) begin
      op_accum = cfg_accum;
      op_relu = cfg_relu;
      op_bias = cfg_bias;
      op_matrix = cfg_matrix || cfg_8x8;
      op_sparse = cfg_sparse;
      op_clamp = cfg_clamp;
      op_wide = cfg_8x8;
      op_8out = cfg_8x8;
      op_shift = shift_amt;
    end else begin
      op_accum = (tdma_k_idx != 5'd0);
      op_relu = tdma_is_last_k && tdma_relu;
      op_bias = (tdma_k_idx == 5'd0) && tdma_bias_en;
      op_matrix = 1'b1;
      op_sparse = 1'b0;
      op_clamp = tdma_is_last_k && tdma_clamp;
      op_wide = (tdma_k_chunk == 2'd2);
      op_8out = tdma_mode_8out;
      op_shift = tdma_is_last_k ? tdma_shift : 5'd0;
    end

    op_act[0] = auto_go ? $signed(auto_infer_sample[7:0]) : activation[0];
    op_act[1] = auto_go ? $signed(auto_infer_sample[15:8]) : activation[1];
    op_act[2] = activation[2];
    op_act[3] = activation[3];
    for (cc = 4; cc < 8; cc = cc + 1) begin
      op_act[cc] = op_wide ? activation[cc] : 8'sd0;
    end

    for (rc = 0; rc < 8; rc = rc + 1) begin
      for (cc = 0; cc < 8; cc = cc + 1) begin
        if (op_use_shadow && (rc < 4) && (cc < 4)) begin
          op_w[rc][cc] = shadow_weight[rc][cc];
        end else begin
          op_w[rc][cc] = weight[rc][cc];
        end
      end
    end

    for (rc = 0; rc < 8; rc = rc + 1) begin
      for (cc = 0; cc < 8; cc = cc + 1) begin
        eff_act[rc][cc] = 8'sd0;
        eff_w[rc][cc] = 8'sd0;
      end
      if (op_sparse) begin
        case (op_w[rc][2][1:0])
          2'd0: eff_act[rc][0] = op_act[0];
          2'd1: eff_act[rc][0] = op_act[1];
          2'd2: eff_act[rc][0] = op_act[2];
          default: eff_act[rc][0] = op_act[3];
        endcase
        case (op_w[rc][2][3:2])
          2'd0: eff_act[rc][1] = op_act[0];
          2'd1: eff_act[rc][1] = op_act[1];
          2'd2: eff_act[rc][1] = op_act[2];
          default: eff_act[rc][1] = op_act[3];
        endcase
        eff_w[rc][0] = op_w[rc][0];
        eff_w[rc][1] = op_w[rc][1];
        if (op_wide) begin
          case (op_w[rc][6][1:0])
            2'd0: eff_act[rc][4] = op_act[4];
            2'd1: eff_act[rc][4] = op_act[5];
            2'd2: eff_act[rc][4] = op_act[6];
            default: eff_act[rc][4] = op_act[7];
          endcase
          case (op_w[rc][6][3:2])
            2'd0: eff_act[rc][5] = op_act[4];
            2'd1: eff_act[rc][5] = op_act[5];
            2'd2: eff_act[rc][5] = op_act[6];
            default: eff_act[rc][5] = op_act[7];
          endcase
          eff_w[rc][4] = op_w[rc][4];
          eff_w[rc][5] = op_w[rc][5];
        end
      end else begin
        for (cc = 0; cc < 4; cc = cc + 1) begin
          eff_act[rc][cc] = op_act[cc];
          eff_w[rc][cc] = op_w[rc][cc];
        end
        if (op_wide) begin
          for (cc = 4; cc < 8; cc = cc + 1) begin
            eff_act[rc][cc] = op_act[cc];
            eff_w[rc][cc] = op_w[rc][cc];
          end
        end
      end
    end
  end

  genvar gr, gc;
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin : gen_mac_row
      logic signed [31:0] s01, s23, s45, s67, s03, s47, p_sum, a_sum, sh_sum, r_sum;
      for (gc = 0; gc < 8; gc = gc + 1) begin : gen_mac_col
        assign mac_prod[gr][gc] = $signed(eff_act[gr][gc]) * $signed(eff_w[gr][gc]);
      end
      assign s01 = $signed({{16{mac_prod[gr][0][15]}}, mac_prod[gr][0]}) +
                   $signed({{16{mac_prod[gr][1][15]}}, mac_prod[gr][1]});
      assign s23 = $signed({{16{mac_prod[gr][2][15]}}, mac_prod[gr][2]}) +
                   $signed({{16{mac_prod[gr][3][15]}}, mac_prod[gr][3]});
      assign s45 = $signed({{16{mac_prod[gr][4][15]}}, mac_prod[gr][4]}) +
                   $signed({{16{mac_prod[gr][5][15]}}, mac_prod[gr][5]});
      assign s67 = $signed({{16{mac_prod[gr][6][15]}}, mac_prod[gr][6]}) +
                   $signed({{16{mac_prod[gr][7][15]}}, mac_prod[gr][7]});
      assign s03 = s01 + s23;
      assign s47 = s45 + s67;
      assign p_sum = s03 + s47;
      assign a_sum = (op_accum ? result[gr] : 32'sd0) + p_sum + (op_bias ? bias[gr] : 32'sd0);
      assign sh_sum = a_sum >>> op_shift;
      assign r_sum = (op_relu && (sh_sum < 32'sd0)) ? 32'sd0 : sh_sum;
      assign mac_next_res[gr] = op_clamp ? ((r_sum > 32'sd127) ? 32'sd127 : ((r_sum < -32'sd128) ? -32'sd128 : r_sum)) : r_sum;
    end
  endgenerate

  assign thresh_hit = (result[0] >= anomaly_thresh) ||
                      (cfg_matrix && ((result[1] >= anomaly_thresh) ||
                                      (result[2] >= anomaly_thresh) ||
                                      (result[3] >= anomaly_thresh))) ||
                      (cfg_8x8 && ((result[4] >= anomaly_thresh) ||
                                   (result[5] >= anomaly_thresh) ||
                                   (result[6] >= anomaly_thresh) ||
                                   (result[7] >= anomaly_thresh)));

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {20'd0, tdma_busy, cfg_8x8, cfg_thresh_irq, cfg_clamp, cfg_sparse, 1'b0, cfg_matrix, cfg_bias, cfg_relu, cfg_accum, done, busy};
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
      8'h70: csr_rdata = {sat_s8(result[3]), sat_s8(result[2]), sat_s8(result[1]), sat_s8(result[0])};
      8'h74: csr_rdata = {activation[7], activation[6], activation[5], activation[4]};
      8'h78: csr_rdata = {weight[0][7], weight[0][6], weight[0][5], weight[0][4]};
      8'h7c: csr_rdata = {weight[1][7], weight[1][6], weight[1][5], weight[1][4]};
      8'h80: csr_rdata = {weight[2][7], weight[2][6], weight[2][5], weight[2][4]};
      8'h84: csr_rdata = {weight[3][7], weight[3][6], weight[3][5], weight[3][4]};
      8'h88: csr_rdata = {weight[4][3], weight[4][2], weight[4][1], weight[4][0]};
      8'h8c: csr_rdata = {weight[5][3], weight[5][2], weight[5][1], weight[5][0]};
      8'h90: csr_rdata = {weight[6][3], weight[6][2], weight[6][1], weight[6][0]};
      8'h94: csr_rdata = {weight[7][3], weight[7][2], weight[7][1], weight[7][0]};
      8'h98: csr_rdata = {weight[4][7], weight[4][6], weight[4][5], weight[4][4]};
      8'h9c: csr_rdata = {weight[5][7], weight[5][6], weight[5][5], weight[5][4]};
      8'ha0: csr_rdata = {weight[6][7], weight[6][6], weight[6][5], weight[6][4]};
      8'ha4: csr_rdata = {weight[7][7], weight[7][6], weight[7][5], weight[7][4]};
      8'ha8: csr_rdata = bias[4];
      8'hac: csr_rdata = bias[5];
      8'hb0: csr_rdata = bias[6];
      8'hb4: csr_rdata = bias[7];
      8'hb8: csr_rdata = result[4];
      8'hbc: csr_rdata = result[5];
      8'hc0: csr_rdata = result[6];
      8'hc4: csr_rdata = result[7];
      8'hc8: csr_rdata = {sat_s8(result[7]), sat_s8(result[6]), sat_s8(result[5]), sat_s8(result[4])};
      8'hcc: csr_rdata = tdma_act_base;
      8'hd0: csr_rdata = tdma_w_base;
      8'hd4: csr_rdata = tdma_bias_base;
      8'hd8: csr_rdata = tdma_dst_base;
      8'hdc: csr_rdata = {8'd0, tdma_batch_cnt, 5'd0, tdma_out_tiles, 3'd0, tdma_k_words};
      8'he0: csr_rdata = {20'd0, tdma_mode_8out, tdma_shift, tdma_clamp, tdma_bias_en, tdma_relu, tdma_ws, tdma_done, tdma_busy};
      default: csr_rdata = 32'd0;
    endcase
  end

  logic _unused_tdma_req;
  assign _unused_tdma_req = tdma_req_ready;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      for (r = 0; r < 8; r = r + 1) begin
        result[r] <= 32'sd0;
        bias[r] <= 32'sd0;
        activation[r] <= 8'sd0;
        for (c = 0; c < 8; c = c + 1) begin
          weight[r][c] <= 8'sd0;
        end
      end
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
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
      cfg_8x8 <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      irq <= 1'b0;
      tdma_state <= TDMA_IDLE;
      tdma_act_base <= 32'd0;
      tdma_w_base <= 32'd0;
      tdma_bias_base <= 32'd0;
      tdma_dst_base <= 32'd0;
      tdma_k_words <= 5'd1;
      tdma_out_tiles <= 3'd1;
      tdma_batch_cnt <= 8'd1;
      tdma_ws <= 1'b0;
      tdma_relu <= 1'b0;
      tdma_bias_en <= 1'b0;
      tdma_clamp <= 1'b0;
      tdma_shift <= 5'd0;
      tdma_mode_8out <= 1'b0;
      tdma_busy <= 1'b0;
      tdma_done <= 1'b0;
      tdma_b_idx <= 8'd0;
      tdma_t_idx <= 3'd0;
      tdma_k_idx <= 5'd0;
      tdma_step_idx <= 4'd0;
      tdma_w_idx <= 4'd0;
      tdma_cur_w_ptr <= 32'd0;
      tdma_cur_b_ptr <= 32'd0;
      tdma_cur_a_ptr <= 32'd0;
      tdma_act_batch_ptr <= 32'd0;
      tdma_cur_d_ptr <= 32'd0;
      tdma_req_valid <= 1'b0;
      tdma_req_write <= 1'b0;
      tdma_req_addr <= 32'd0;
      tdma_req_wdata <= 32'd0;
    end else begin
      irq <= 1'b0;
      if (op_go) begin
        result[0] <= mac_next_res[0];
        if (op_matrix) begin
          result[1] <= mac_next_res[1];
          result[2] <= mac_next_res[2];
          result[3] <= mac_next_res[3];
        end
        if (op_8out) begin
          result[4] <= mac_next_res[4];
          result[5] <= mac_next_res[5];
          result[6] <= mac_next_res[6];
          result[7] <= mac_next_res[7];
        end
      end

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
            cfg_8x8 <= csr_wdata[10];
            if (csr_wdata[6]) begin
              for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                  weight[r][c] <= shadow_weight[r][c];
                  shadow_weight[r][c] <= weight[r][c];
                end
              end
            end
            if (csr_wdata[0] && !busy && !tdma_busy) begin
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
          8'h34: begin weight[0][0] <= csr_wdata[7:0]; weight[0][1] <= csr_wdata[15:8]; weight[0][2] <= csr_wdata[23:16]; weight[0][3] <= csr_wdata[31:24]; end
          8'h38: begin weight[1][0] <= csr_wdata[7:0]; weight[1][1] <= csr_wdata[15:8]; weight[1][2] <= csr_wdata[23:16]; weight[1][3] <= csr_wdata[31:24]; end
          8'h3c: begin weight[2][0] <= csr_wdata[7:0]; weight[2][1] <= csr_wdata[15:8]; weight[2][2] <= csr_wdata[23:16]; weight[2][3] <= csr_wdata[31:24]; end
          8'h40: begin weight[3][0] <= csr_wdata[7:0]; weight[3][1] <= csr_wdata[15:8]; weight[3][2] <= csr_wdata[23:16]; weight[3][3] <= csr_wdata[31:24]; end
          8'h50: begin shadow_weight[0][0] <= csr_wdata[7:0]; shadow_weight[0][1] <= csr_wdata[15:8]; shadow_weight[0][2] <= csr_wdata[23:16]; shadow_weight[0][3] <= csr_wdata[31:24]; end
          8'h54: begin shadow_weight[1][0] <= csr_wdata[7:0]; shadow_weight[1][1] <= csr_wdata[15:8]; shadow_weight[1][2] <= csr_wdata[23:16]; shadow_weight[1][3] <= csr_wdata[31:24]; end
          8'h58: begin shadow_weight[2][0] <= csr_wdata[7:0]; shadow_weight[2][1] <= csr_wdata[15:8]; shadow_weight[2][2] <= csr_wdata[23:16]; shadow_weight[2][3] <= csr_wdata[31:24]; end
          8'h5c: begin shadow_weight[3][0] <= csr_wdata[7:0]; shadow_weight[3][1] <= csr_wdata[15:8]; shadow_weight[3][2] <= csr_wdata[23:16]; shadow_weight[3][3] <= csr_wdata[31:24]; end
          8'h60: bias[1] <= csr_wdata;
          8'h64: bias[2] <= csr_wdata;
          8'h68: bias[3] <= csr_wdata;
          8'h6c: anomaly_thresh <= $signed(csr_wdata);
          8'h74: begin activation[4] <= csr_wdata[7:0]; activation[5] <= csr_wdata[15:8]; activation[6] <= csr_wdata[23:16]; activation[7] <= csr_wdata[31:24]; end
          8'h78: begin weight[0][4] <= csr_wdata[7:0]; weight[0][5] <= csr_wdata[15:8]; weight[0][6] <= csr_wdata[23:16]; weight[0][7] <= csr_wdata[31:24]; end
          8'h7c: begin weight[1][4] <= csr_wdata[7:0]; weight[1][5] <= csr_wdata[15:8]; weight[1][6] <= csr_wdata[23:16]; weight[1][7] <= csr_wdata[31:24]; end
          8'h80: begin weight[2][4] <= csr_wdata[7:0]; weight[2][5] <= csr_wdata[15:8]; weight[2][6] <= csr_wdata[23:16]; weight[2][7] <= csr_wdata[31:24]; end
          8'h84: begin weight[3][4] <= csr_wdata[7:0]; weight[3][5] <= csr_wdata[15:8]; weight[3][6] <= csr_wdata[23:16]; weight[3][7] <= csr_wdata[31:24]; end
          8'h88: begin weight[4][0] <= csr_wdata[7:0]; weight[4][1] <= csr_wdata[15:8]; weight[4][2] <= csr_wdata[23:16]; weight[4][3] <= csr_wdata[31:24]; end
          8'h8c: begin weight[5][0] <= csr_wdata[7:0]; weight[5][1] <= csr_wdata[15:8]; weight[5][2] <= csr_wdata[23:16]; weight[5][3] <= csr_wdata[31:24]; end
          8'h90: begin weight[6][0] <= csr_wdata[7:0]; weight[6][1] <= csr_wdata[15:8]; weight[6][2] <= csr_wdata[23:16]; weight[6][3] <= csr_wdata[31:24]; end
          8'h94: begin weight[7][0] <= csr_wdata[7:0]; weight[7][1] <= csr_wdata[15:8]; weight[7][2] <= csr_wdata[23:16]; weight[7][3] <= csr_wdata[31:24]; end
          8'h98: begin weight[4][4] <= csr_wdata[7:0]; weight[4][5] <= csr_wdata[15:8]; weight[4][6] <= csr_wdata[23:16]; weight[4][7] <= csr_wdata[31:24]; end
          8'h9c: begin weight[5][4] <= csr_wdata[7:0]; weight[5][5] <= csr_wdata[15:8]; weight[5][6] <= csr_wdata[23:16]; weight[5][7] <= csr_wdata[31:24]; end
          8'ha0: begin weight[6][4] <= csr_wdata[7:0]; weight[6][5] <= csr_wdata[15:8]; weight[6][6] <= csr_wdata[23:16]; weight[6][7] <= csr_wdata[31:24]; end
          8'ha4: begin weight[7][4] <= csr_wdata[7:0]; weight[7][5] <= csr_wdata[15:8]; weight[7][6] <= csr_wdata[23:16]; weight[7][7] <= csr_wdata[31:24]; end
          8'ha8: bias[4] <= csr_wdata;
          8'hac: bias[5] <= csr_wdata;
          8'hb0: bias[6] <= csr_wdata;
          8'hb4: bias[7] <= csr_wdata;
          8'hcc: tdma_act_base <= csr_wdata;
          8'hd0: tdma_w_base <= csr_wdata;
          8'hd4: tdma_bias_base <= csr_wdata;
          8'hd8: tdma_dst_base <= csr_wdata;
          8'hdc: begin
            tdma_k_words <= (csr_wdata[4:0] == 5'd0) ? 5'd1 : csr_wdata[4:0];
            tdma_out_tiles <= (csr_wdata[10:8] == 3'd0) ? 3'd1 : csr_wdata[10:8];
            tdma_batch_cnt <= (csr_wdata[23:16] == 8'd0) ? 8'd1 : csr_wdata[23:16];
          end
          8'he0: begin
            if (csr_wdata[1]) tdma_done <= 1'b0;
            tdma_ws <= csr_wdata[2];
            tdma_relu <= csr_wdata[3];
            tdma_bias_en <= csr_wdata[4];
            tdma_clamp <= csr_wdata[5];
            tdma_shift <= csr_wdata[10:6];
            tdma_mode_8out <= csr_wdata[11];
            if (csr_wdata[0] && !tdma_busy && !busy) begin
              tdma_busy <= 1'b1;
              tdma_done <= 1'b0;
              tdma_b_idx <= 8'd0;
              tdma_t_idx <= 3'd0;
              tdma_k_idx <= 5'd0;
              tdma_step_idx <= 4'd0;
              tdma_w_idx <= 4'd0;
              tdma_act_batch_ptr <= tdma_act_base;
              tdma_cur_a_ptr <= tdma_act_base;
              tdma_cur_d_ptr <= tdma_dst_base;
              tdma_req_valid <= 1'b1;
              tdma_req_write <= 1'b0;
              if (csr_wdata[4]) begin
                tdma_req_addr <= tdma_bias_base;
                tdma_cur_b_ptr <= tdma_bias_base + 32'd4;
                tdma_cur_w_ptr <= tdma_w_base;
                tdma_state <= TDMA_RD_B;
              end else begin
                tdma_req_addr <= tdma_w_base;
                tdma_cur_w_ptr <= tdma_w_base + 32'd4;
                tdma_cur_b_ptr <= tdma_bias_base;
                tdma_state <= TDMA_RD_W;
              end
            end
          end
          default: begin end
        endcase
      end else if (auto_go) begin
        activation[0] <= auto_infer_sample[7:0];
        activation[1] <= auto_infer_sample[15:8];
        busy <= 1'b1;
      end

      if (busy) begin
        busy <= 1'b0;
        done <= 1'b1;
        irq <= !irq && (cfg_thresh_irq ? thresh_hit : 1'b1);
      end else if (tdma_busy) begin
        case (tdma_state)
          TDMA_RD_B: begin
            if (tdma_rsp_valid) begin
              bias[tdma_step_idx[2:0]] <= $signed(tdma_rsp_rdata);
              if (tdma_step_idx == (tdma_mode_8out ? 4'd7 : 4'd3)) begin
                tdma_step_idx <= 4'd0;
                tdma_w_idx <= 4'd0;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b0;
                tdma_req_addr <= tdma_cur_w_ptr;
                tdma_cur_w_ptr <= tdma_cur_w_ptr + 32'd4;
                tdma_state <= TDMA_RD_W;
              end else begin
                tdma_step_idx <= tdma_step_idx + 4'd1;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b0;
                tdma_req_addr <= tdma_cur_b_ptr;
                tdma_cur_b_ptr <= tdma_cur_b_ptr + 32'd4;
              end
            end
          end
          TDMA_RD_W: begin
            if (tdma_rsp_valid) begin
              if (!tdma_w_hi) begin
                weight[tdma_w_row][0] <= tdma_rsp_rdata[7:0];
                weight[tdma_w_row][1] <= tdma_rsp_rdata[15:8];
                weight[tdma_w_row][2] <= tdma_rsp_rdata[23:16];
                weight[tdma_w_row][3] <= tdma_rsp_rdata[31:24];
              end else begin
                weight[tdma_w_row][4] <= tdma_rsp_rdata[7:0];
                weight[tdma_w_row][5] <= tdma_rsp_rdata[15:8];
                weight[tdma_w_row][6] <= tdma_rsp_rdata[23:16];
                weight[tdma_w_row][7] <= tdma_rsp_rdata[31:24];
              end
              if (tdma_w_idx == tdma_w_last) begin
                tdma_step_idx <= 4'd0;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b0;
                tdma_req_addr <= tdma_cur_a_ptr;
                tdma_cur_a_ptr <= tdma_cur_a_ptr + 32'd4;
                tdma_state <= TDMA_RD_A;
              end else begin
                tdma_w_idx <= tdma_w_idx + 4'd1;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b0;
                tdma_req_addr <= tdma_cur_w_ptr;
                tdma_cur_w_ptr <= tdma_cur_w_ptr + 32'd4;
              end
            end
          end
          TDMA_RD_A: begin
            if (tdma_rsp_valid) begin
              if (!tdma_step_idx[0]) begin
                activation[0] <= tdma_rsp_rdata[7:0];
                activation[1] <= tdma_rsp_rdata[15:8];
                activation[2] <= tdma_rsp_rdata[23:16];
                activation[3] <= tdma_rsp_rdata[31:24];
              end else begin
                activation[4] <= tdma_rsp_rdata[7:0];
                activation[5] <= tdma_rsp_rdata[15:8];
                activation[6] <= tdma_rsp_rdata[23:16];
                activation[7] <= tdma_rsp_rdata[31:24];
              end
              if ({1'b0, tdma_step_idx[0]} + 2'd1 >= tdma_k_chunk) begin
                tdma_step_idx <= 4'd0;
                tdma_req_valid <= 1'b0;
                tdma_state <= TDMA_EXEC;
              end else begin
                tdma_step_idx <= 4'd1;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b0;
                tdma_req_addr <= tdma_cur_a_ptr;
                tdma_cur_a_ptr <= tdma_cur_a_ptr + 32'd4;
              end
            end
          end
          TDMA_EXEC: begin
            if (tdma_is_last_k) begin
              tdma_step_idx <= 4'd0;
              tdma_req_valid <= 1'b1;
              tdma_req_write <= 1'b1;
              tdma_req_addr <= tdma_cur_d_ptr;
              tdma_cur_d_ptr <= tdma_cur_d_ptr + 32'd4;
              tdma_req_wdata <= {sat_s8(mac_next_res[3]), sat_s8(mac_next_res[2]), sat_s8(mac_next_res[1]), sat_s8(mac_next_res[0])};
              tdma_state <= TDMA_WR;
            end else begin
              tdma_k_idx <= tdma_k_idx + {3'd0, tdma_k_chunk};
              tdma_w_idx <= 4'd0;
              tdma_req_valid <= 1'b1;
              tdma_req_write <= 1'b0;
              tdma_req_addr <= tdma_cur_w_ptr;
              tdma_cur_w_ptr <= tdma_cur_w_ptr + 32'd4;
              tdma_state <= TDMA_RD_W;
            end
          end
          TDMA_WR: begin
            if (tdma_rsp_valid) begin
              if (tdma_mode_8out && !tdma_step_idx[0]) begin
                tdma_step_idx <= 4'd1;
                tdma_req_valid <= 1'b1;
                tdma_req_write <= 1'b1;
                tdma_req_addr <= tdma_cur_d_ptr;
                tdma_cur_d_ptr <= tdma_cur_d_ptr + 32'd4;
                tdma_req_wdata <= {sat_s8(result[7]), sat_s8(result[6]), sat_s8(result[5]), sat_s8(result[4])};
              end else begin
                tdma_step_idx <= 4'd0;
                tdma_k_idx <= 5'd0;
                tdma_w_idx <= 4'd0;
                if (tdma_t_idx + 3'd1 < tdma_out_tiles) begin
                  tdma_t_idx <= tdma_t_idx + 3'd1;
                  tdma_cur_a_ptr <= tdma_act_batch_ptr;
                  tdma_req_valid <= 1'b1;
                  tdma_req_write <= 1'b0;
                  if (tdma_bias_en) begin
                    tdma_req_addr <= tdma_cur_b_ptr;
                    tdma_cur_b_ptr <= tdma_cur_b_ptr + 32'd4;
                    tdma_state <= TDMA_RD_B;
                  end else begin
                    tdma_req_addr <= tdma_cur_w_ptr;
                    tdma_cur_w_ptr <= tdma_cur_w_ptr + 32'd4;
                    tdma_state <= TDMA_RD_W;
                  end
                end else if (tdma_b_idx + 8'd1 < tdma_batch_cnt) begin
                  tdma_b_idx <= tdma_b_idx + 8'd1;
                  tdma_t_idx <= 3'd0;
                  tdma_act_batch_ptr <= tdma_cur_a_ptr;
                  tdma_req_valid <= 1'b1;
                  tdma_req_write <= 1'b0;
                  if (tdma_ws_fast) begin
                    tdma_req_addr <= tdma_cur_a_ptr;
                    tdma_cur_a_ptr <= tdma_cur_a_ptr + 32'd4;
                    tdma_state <= TDMA_RD_A;
                  end else if (tdma_bias_en) begin
                    tdma_req_addr <= tdma_bias_base;
                    tdma_cur_b_ptr <= tdma_bias_base + 32'd4;
                    tdma_cur_w_ptr <= tdma_w_base;
                    tdma_state <= TDMA_RD_B;
                  end else begin
                    tdma_req_addr <= tdma_w_base;
                    tdma_cur_w_ptr <= tdma_w_base + 32'd4;
                    tdma_cur_b_ptr <= tdma_bias_base;
                    tdma_state <= TDMA_RD_W;
                  end
                end else begin
                  tdma_busy <= 1'b0;
                  tdma_done <= 1'b1;
                  tdma_req_valid <= 1'b0;
                  tdma_req_write <= 1'b0;
                  irq <= !irq;
                  tdma_state <= TDMA_IDLE;
                end
              end
            end
          end
          default: begin
            tdma_busy <= 1'b0;
            tdma_req_valid <= 1'b0;
            tdma_req_write <= 1'b0;
            tdma_state <= TDMA_IDLE;
          end
        endcase
      end else if (!(csr_valid && csr_write && (csr_addr == 8'he0) && csr_wdata[0] && !busy)) begin
        tdma_req_valid <= 1'b0;
        tdma_req_write <= 1'b0;
        tdma_state <= TDMA_IDLE;
      end
    end
  end
endmodule
