module sha256_engine (
  input logic clk,
  input logic reset,
  input logic init,
  input logic start,
  input logic [31:0] block_word [0:15],
  output logic done,
  output logic [255:0] digest
);
  logic [5:0] round_cnt;
  logic busy;
  logic [31:0] a, b, c, d, e, f, g, h;
  logic [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
  logic [31:0] w [0:15];
  logic [31:0] cur_w;
  logic [31:0] k_val;
  logic [31:0] t1, t2;
  integer i;

  function automatic logic [31:0] rotr(input logic [31:0] val, input logic [4:0] amt);
    rotr = (val >> amt) | (val << (6'd32 - {1'b0, amt}));
  endfunction

  function automatic logic [31:0] sigma0(input logic [31:0] x);
    sigma0 = rotr(x, 5'd7) ^ rotr(x, 5'd18) ^ (x >> 3);
  endfunction

  function automatic logic [31:0] sigma1(input logic [31:0] x);
    sigma1 = rotr(x, 5'd17) ^ rotr(x, 5'd19) ^ (x >> 10);
  endfunction

  function automatic logic [31:0] sum0(input logic [31:0] x);
    sum0 = rotr(x, 5'd2) ^ rotr(x, 5'd13) ^ rotr(x, 5'd22);
  endfunction

  function automatic logic [31:0] sum1(input logic [31:0] x);
    sum1 = rotr(x, 5'd6) ^ rotr(x, 5'd11) ^ rotr(x, 5'd25);
  endfunction

  function automatic logic [31:0] get_k(input logic [5:0] r);
    case (r)
      6'd0: get_k = 32'h428a2f98; 6'd1: get_k = 32'h71374491; 6'd2: get_k = 32'hb5c0fbcf; 6'd3: get_k = 32'he9b5dba5;
      6'd4: get_k = 32'h3956c25b; 6'd5: get_k = 32'h59f111f1; 6'd6: get_k = 32'h923f82a4; 6'd7: get_k = 32'hab1c5ed5;
      6'd8: get_k = 32'hd807aa98; 6'd9: get_k = 32'h12835b01; 6'd10: get_k = 32'h243185be; 6'd11: get_k = 32'h550c7dc3;
      6'd12: get_k = 32'h72be5d74; 6'd13: get_k = 32'h80deb1fe; 6'd14: get_k = 32'h9bdc06a7; 6'd15: get_k = 32'hc19bf174;
      6'd16: get_k = 32'he49b69c1; 6'd17: get_k = 32'hefbe4786; 6'd18: get_k = 32'h0fc19dc6; 6'd19: get_k = 32'h240ca1cc;
      6'd20: get_k = 32'h2de92c6f; 6'd21: get_k = 32'h4a7484aa; 6'd22: get_k = 32'h5cb0a9dc; 6'd23: get_k = 32'h76f988da;
      6'd24: get_k = 32'h983e5152; 6'd25: get_k = 32'ha831c66d; 6'd26: get_k = 32'hb00327c8; 6'd27: get_k = 32'hbf597fc7;
      6'd28: get_k = 32'hc6e00bf3; 6'd29: get_k = 32'hd5a79147; 6'd30: get_k = 32'h06ca6351; 6'd31: get_k = 32'h14292967;
      6'd32: get_k = 32'h27b70a85; 6'd33: get_k = 32'h2e1b2138; 6'd34: get_k = 32'h4d2c6dfc; 6'd35: get_k = 32'h53380d13;
      6'd36: get_k = 32'h650a7354; 6'd37: get_k = 32'h766a0abb; 6'd38: get_k = 32'h81c2c92e; 6'd39: get_k = 32'h92722c85;
      6'd40: get_k = 32'ha2bfe8a1; 6'd41: get_k = 32'ha81a664b; 6'd42: get_k = 32'hc24b8b70; 6'd43: get_k = 32'hc76c51a3;
      6'd44: get_k = 32'hd192e819; 6'd45: get_k = 32'hd6990624; 6'd46: get_k = 32'hf40e3585; 6'd47: get_k = 32'h106aa070;
      6'd48: get_k = 32'h19a4c116; 6'd49: get_k = 32'h1e376c08; 6'd50: get_k = 32'h2748774c; 6'd51: get_k = 32'h34b0bcb5;
      6'd52: get_k = 32'h391c0cb3; 6'd53: get_k = 32'h4ed8aa4a; 6'd54: get_k = 32'h5b9cca4f; 6'd55: get_k = 32'h682e6ff3;
      6'd56: get_k = 32'h748f82ee; 6'd57: get_k = 32'h78a5636f; 6'd58: get_k = 32'h84c87814; 6'd59: get_k = 32'h8cc70208;
      6'd60: get_k = 32'h90befffa; 6'd61: get_k = 32'ha4506ceb; 6'd62: get_k = 32'hbef9a3f7; 6'd63: get_k = 32'hc67178f2;
      default: get_k = 32'd0;
    endcase
  endfunction

  assign k_val = get_k(round_cnt);
  assign cur_w = (round_cnt < 6'd16) ? w[round_cnt[3:0]] : (sigma1(w[14]) + w[9] + sigma0(w[1]) + w[0]);
  assign t1 = h + sum1(e) + ((e & f) ^ (~e & g)) + k_val + cur_w;
  assign t2 = sum0(a) + ((a & b) ^ (a & c) ^ (b & c));
  assign digest = {h0, h1, h2, h3, h4, h5, h6, h7};

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      round_cnt <= 6'd0;
      busy <= 1'b0;
      done <= 1'b0;
      h0 <= 32'h6a09e667;
      h1 <= 32'hbb67ae85;
      h2 <= 32'h3c6ef372;
      h3 <= 32'ha54ff53a;
      h4 <= 32'h510e527f;
      h5 <= 32'h9b05688c;
      h6 <= 32'h1f83d9ab;
      h7 <= 32'h5be0cd19;
      a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0;
      e <= 32'd0; f <= 32'd0; g <= 32'd0; h <= 32'd0;
      for (i = 0; i < 16; i = i + 1) w[i] <= 32'd0;
    end else begin
      done <= 1'b0;
      if (init) begin
        h0 <= 32'h6a09e667;
        h1 <= 32'hbb67ae85;
        h2 <= 32'h3c6ef372;
        h3 <= 32'ha54ff53a;
        h4 <= 32'h510e527f;
        h5 <= 32'h9b05688c;
        h6 <= 32'h1f83d9ab;
        h7 <= 32'h5be0cd19;
      end
      if (start && !busy) begin
        busy <= 1'b1;
        round_cnt <= 6'd0;
        a <= h0; b <= h1; c <= h2; d <= h3;
        e <= h4; f <= h5; g <= h6; h <= h7;
        for (i = 0; i < 16; i = i + 1) w[i] <= block_word[i];
      end else if (busy) begin
        a <= t1 + t2;
        b <= a;
        c <= b;
        d <= c;
        e <= d + t1;
        f <= e;
        g <= f;
        h <= g;
        if (round_cnt >= 6'd16) begin
          for (i = 0; i < 15; i = i + 1) w[i] <= w[i+1];
          w[15] <= cur_w;
        end
        if (round_cnt == 6'd63) begin
          busy <= 1'b0;
          done <= 1'b1;
          h0 <= h0 + (t1 + t2);
          h1 <= h1 + a;
          h2 <= h2 + b;
          h3 <= h3 + c;
          h4 <= h4 + (d + t1);
          h5 <= h5 + e;
          h6 <= h6 + f;
          h7 <= h7 + g;
        end else begin
          round_cnt <= round_cnt + 6'd1;
        end
      end
    end
  end
endmodule
