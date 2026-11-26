`timescale 1ns/1ps
module tb_model_bench;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic sensor_valid = 1'b0;
  logic [15:0] sensor_data = 16'd0;
  logic sensor_result_valid;
  logic [15:0] sensor_result;
  logic accelerator_irq;
  logic boot_release;
  logic boot_fail;
  logic core_trap;
  logic core_sleep;
  logic sensor_alert;
  logic uart_tx;
  logic [15:0] gpio_out, gpio_oe;
  logic spi_sck, spi_mosi, spi_cs_n;
  logic wb_ack;
  logic [31:0] wb_dat_o;

  integer failures = 0;
  integer cycles = 0;
  integer emit_pc = 0;
  integer emit_to_sram = 0;
  integer wake_err = 0;

  always #5 clk = ~clk;

  orx1_soc u_soc (
    .clk(clk), .reset(reset), .sensor_valid(sensor_valid), .sensor_data(sensor_data),
    .sensor_result_valid(sensor_result_valid), .sensor_result(sensor_result),
    .accelerator_irq(accelerator_irq), .boot_release(boot_release), .boot_fail(boot_fail),
    .core_trap(core_trap), .core_sleep(core_sleep), .sensor_alert(sensor_alert),
    .uart_rx(1'b1), .uart_tx(uart_tx),
    .gpio_in(16'd0), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(1'b0), .spi_cs_n(spi_cs_n),
    .wb_host_cyc_i(1'b0), .wb_host_stb_i(1'b0), .wb_host_we_i(1'b0),
    .wb_host_sel_i(4'b0000), .wb_host_adr_i(32'd0), .wb_host_dat_i(32'd0),
    .wb_host_ack_o(wb_ack), .wb_host_dat_o(wb_dat_o)
  );

  function automatic [31:0] enc_u(input integer imm20, input integer rd, input integer op);
    enc_u = {imm20[19:0], rd[4:0], op[6:0]};
  endfunction
  function automatic [31:0] enc_i(input integer imm12, input integer rs1, input integer f3, input integer rd, input integer op);
    enc_i = {imm12[11:0], rs1[4:0], f3[2:0], rd[4:0], op[6:0]};
  endfunction
  function automatic [31:0] enc_r(input integer f7, input integer rs2, input integer rs1, input integer f3, input integer rd);
    enc_r = {f7[6:0], rs2[4:0], rs1[4:0], f3[2:0], rd[4:0], 7'b0110011};
  endfunction
  function automatic [31:0] enc_s(input integer imm12, input integer rs2, input integer rs1, input integer f3);
    enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm12[4:0], 7'b0100011};
  endfunction
  function automatic [31:0] enc_b(input integer imm13, input integer rs2, input integer rs1, input integer f3);
    enc_b = {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], f3[2:0], imm13[4:1], imm13[11], 7'b1100011};
  endfunction
  function automatic [31:0] enc_j(input integer imm21, input integer rd);
    enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd[4:0], 7'b1101111};
  endfunction
  function automatic [31:0] enc_csr(input integer csr12, input integer rs1, input integer f3, input integer rd);
    enc_csr = {csr12[11:0], rs1[4:0], f3[2:0], rd[4:0], 7'b1110011};
  endfunction
  function automatic [31:0] enc_addi(input integer rd, input integer rs1, input integer imm12);
    enc_addi = enc_i(imm12, rs1, 3'b000, rd, 7'b0010011);
  endfunction
  function automatic [31:0] enc_slli(input integer rd, input integer rs1, input integer shamt);
    enc_slli = {7'b0000000, shamt[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0010011};
  endfunction
  function automatic [31:0] enc_srai(input integer rd, input integer rs1, input integer shamt);
    enc_srai = {7'b0100000, shamt[4:0], rs1[4:0], 3'b101, rd[4:0], 7'b0010011};
  endfunction
  function automatic [31:0] enc_add(input integer rd, input integer rs1, input integer rs2);
    enc_add = enc_r(7'b0000000, rs2, rs1, 3'b000, rd);
  endfunction
  function automatic [31:0] enc_or(input integer rd, input integer rs1, input integer rs2);
    enc_or = enc_r(7'b0000000, rs2, rs1, 3'b110, rd);
  endfunction
  function automatic [31:0] enc_lw(input integer rd, input integer rs1, input integer imm12);
    enc_lw = enc_i(imm12, rs1, 3'b010, rd, 7'b0000011);
  endfunction
  function automatic [31:0] enc_lb(input integer rd, input integer rs1, input integer imm12);
    enc_lb = enc_i(imm12, rs1, 3'b000, rd, 7'b0000011);
  endfunction
  function automatic [31:0] enc_sw(input integer rs2, input integer rs1, input integer imm12);
    enc_sw = enc_s(imm12, rs2, rs1, 3'b010);
  endfunction
  function automatic [31:0] enc_jalr(input integer rd, input integer rs1, input integer imm12);
    enc_jalr = enc_i(imm12, rs1, 3'b000, rd, 7'b1100111);
  endfunction

  task automatic emit(input logic [31:0] inst);
    begin
      if (emit_to_sram != 0) u_soc.u_sram.mem[emit_pc] = inst;
      else u_soc.boot_rom[emit_pc] = inst;
      emit_pc = emit_pc + 1;
    end
  endtask

  task automatic emit_snap(input integer snap_idx);
    begin
      emit(enc_i(16'h200 + (snap_idx * 20), 1, 3'b000, 11, 7'b0010011));
      emit(enc_jalr(10, 26, 0));
    end
  endtask

  function automatic [31:0] pack4(input integer b0, input integer b1, input integer b2, input integer b3);
    pack4 = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
  endfunction

  function automatic integer s8(input integer x);
    logic signed [7:0] t;
    begin
      t = x[7:0];
      s8 = t;
    end
  endfunction

  function automatic integer ref_clamp_relu(input integer acc, input integer shift, input integer do_relu);
    integer v;
    begin
      v = acc >>> shift;
      if (do_relu && v < 0) v = 0;
      if (v > 127) v = 127;
      if (v < -128) v = -128;
      ref_clamp_relu = v;
    end
  endfunction

  integer snap_fn_pc;
  integer l_cpu_row, l_cpu_col, p_cpu_relu, p_cpu_hi, p_cpu_lo;
  integer l_npu_poll1, l_mlp_sample, l_mlp_t0, l_mlp_t1, l_mlp_l2;
  integer l_sp_poll, l_dma_poll, l_cordic_poll;

  integer w1_t0 [0:15];
  integer w1_t1 [0:15];
  integer b1_v [0:3];
  integer w2_v [0:15];
  integer b2_v [0:3];
  integer mlp_in [0:31];
  integer mlp_gold [0:15];
  integer h_vec [0:3];
  integer s_i, r_i, c_i, acc_v;

  task automatic set4(output integer arr_idx_val, input integer v);
    arr_idx_val = v;
  endtask

  task automatic push_sensor(input logic [15:0] val);
    begin
      @(negedge clk);
      sensor_data = val;
      sensor_valid = 1'b1;
      @(negedge clk);
      sensor_valid = 1'b0;
    end
  endtask

  task automatic report_bench(input string name, input integer idx_start, input integer idx_end, input integer macs, input integer wakeups);
    integer dc, di, de, ds, da;
    real cpi, lat_us, mops, mac_cyc, ips;
    begin
      dc = u_soc.u_sram.mem[128 + idx_end*5 + 0] - u_soc.u_sram.mem[128 + idx_start*5 + 0];
      di = u_soc.u_sram.mem[128 + idx_end*5 + 1] - u_soc.u_sram.mem[128 + idx_start*5 + 1];
      de = u_soc.u_sram.mem[128 + idx_end*5 + 2] - u_soc.u_sram.mem[128 + idx_start*5 + 2];
      ds = u_soc.u_sram.mem[128 + idx_end*5 + 3] - u_soc.u_sram.mem[128 + idx_start*5 + 3];
      da = u_soc.u_sram.mem[128 + idx_end*5 + 4] - u_soc.u_sram.mem[128 + idx_start*5 + 4];
      cpi = (di > 0) ? ($itor(dc) / $itor(di)) : 0.0;
      lat_us = $itor(dc) * 0.02;
      ips = (dc > 0) ? (50000000.0 / $itor(dc)) : 0.0;
      mac_cyc = (dc > 0 && macs > 0) ? ($itor(macs) / $itor(dc)) : 0.0;
      mops = (dc > 0 && macs > 0) ? (($itor(macs) * 2.0 * 50.0) / $itor(dc)) : 0.0;
      $display("BENCH %-18s | cyc=%4d | instr=%4d | cpi=%0.2f | lat=%5.2fus | inf/s=%9.0f | MAC/cyc=%0.2f | MOPS@50M=%6.1f | accel=%2d | sleep=%3d | wake=%1d | energy=%4d",
               name, dc, di, cpi, lat_us, ips, mac_cyc, mops, da, ds, wakeups, de);
    end
  endtask

  task automatic write_csv_row(input integer fd, input string name, input integer idx_start, input integer idx_end, input integer macs, input integer wakeups);
    integer dc, di, de, ds, da;
    real cpi, lat_us, mops;
    begin
      dc = u_soc.u_sram.mem[128 + idx_end*5 + 0] - u_soc.u_sram.mem[128 + idx_start*5 + 0];
      di = u_soc.u_sram.mem[128 + idx_end*5 + 1] - u_soc.u_sram.mem[128 + idx_start*5 + 1];
      de = u_soc.u_sram.mem[128 + idx_end*5 + 2] - u_soc.u_sram.mem[128 + idx_start*5 + 2];
      ds = u_soc.u_sram.mem[128 + idx_end*5 + 3] - u_soc.u_sram.mem[128 + idx_start*5 + 3];
      da = u_soc.u_sram.mem[128 + idx_end*5 + 4] - u_soc.u_sram.mem[128 + idx_start*5 + 4];
      cpi = (di > 0) ? ($itor(dc) / $itor(di)) : 0.0;
      lat_us = $itor(dc) * 0.02;
      mops = (dc > 0 && macs > 0) ? (($itor(macs) * 2.0 * 50.0) / $itor(dc)) : 0.0;
      $fdisplay(fd, "%s,%0d,%0d,%0.2f,%0.2f,%0d,%0.1f,%0d,%0d,%0d,%0d",
                name, dc, di, cpi, lat_us, macs, mops, de, ds, da, wakeups);
    end
  endtask

  integer fd_csv;

  initial begin
    @(negedge clk);

    u_soc.u_sram.mem[0] = pack4(12, 45, -20, 30);
    u_soc.u_sram.mem[1] = pack4(10, -5, 2, 8);
    u_soc.u_sram.mem[2] = pack4(-3, 12, -4, 1);
    u_soc.u_sram.mem[3] = pack4(7, 0, 11, -6);
    u_soc.u_sram.mem[4] = pack4(-8, 9, 4, 15);
    u_soc.u_sram.mem[5] = 32'sd16;
    u_soc.u_sram.mem[6] = -32'sd8;
    u_soc.u_sram.mem[7] = 32'sd4;
    u_soc.u_sram.mem[8] = 32'sd32;

    w1_t0[0]=3;  w1_t0[1]=-2; w1_t0[2]=4;  w1_t0[3]=1;
    w1_t0[4]=-5; w1_t0[5]=6;  w1_t0[6]=-3; w1_t0[7]=2;
    w1_t0[8]=8;  w1_t0[9]=-1; w1_t0[10]=5; w1_t0[11]=-4;
    w1_t0[12]=-2; w1_t0[13]=7; w1_t0[14]=-6; w1_t0[15]=3;

    w1_t1[0]=-4; w1_t1[1]=2;  w1_t1[2]=1;  w1_t1[3]=-3;
    w1_t1[4]=3;  w1_t1[5]=-2; w1_t1[6]=7;  w1_t1[7]=1;
    w1_t1[8]=-3; w1_t1[9]=4;  w1_t1[10]=-2; w1_t1[11]=6;
    w1_t1[12]=5; w1_t1[13]=-1; w1_t1[14]=2; w1_t1[15]=-4;

    b1_v[0]=8; b1_v[1]=-4; b1_v[2]=12; b1_v[3]=0;

    w2_v[0]=5;  w2_v[1]=-3; w2_v[2]=2;  w2_v[3]=4;
    w2_v[4]=-2; w2_v[5]=6;  w2_v[6]=1;  w2_v[7]=-3;
    w2_v[8]=4;  w2_v[9]=2;  w2_v[10]=-5; w2_v[11]=3;
    w2_v[12]=-1; w2_v[13]=3; w2_v[14]=6; w2_v[15]=-2;

    b2_v[0]=4; b2_v[1]=10; b2_v[2]=-6; b2_v[3]=8;

    mlp_in[0]=10;  mlp_in[1]=-5;  mlp_in[2]=8;   mlp_in[3]=4;   mlp_in[4]=-6;  mlp_in[5]=3;   mlp_in[6]=12;  mlp_in[7]=-2;
    mlp_in[8]=-12; mlp_in[9]=9;   mlp_in[10]=-3; mlp_in[11]=7;  mlp_in[12]=4;  mlp_in[13]=-8; mlp_in[14]=2;  mlp_in[15]=11;
    mlp_in[16]=25; mlp_in[17]=18; mlp_in[18]=-10; mlp_in[19]=14; mlp_in[20]=-9; mlp_in[21]=20; mlp_in[22]=15; mlp_in[23]=-5;
    mlp_in[24]=-4; mlp_in[25]=-15; mlp_in[26]=22; mlp_in[27]=-8; mlp_in[28]=16; mlp_in[29]=12; mlp_in[30]=-7; mlp_in[31]=9;

    for (r_i = 0; r_i < 4; r_i = r_i + 1) begin
      u_soc.u_sram.mem[20 + r_i] = pack4(w1_t0[r_i*4+0], w1_t0[r_i*4+1], w1_t0[r_i*4+2], w1_t0[r_i*4+3]);
      u_soc.u_sram.mem[24 + r_i] = pack4(w1_t1[r_i*4+0], w1_t1[r_i*4+1], w1_t1[r_i*4+2], w1_t1[r_i*4+3]);
      u_soc.u_sram.mem[28 + r_i] = b1_v[r_i];
      u_soc.u_sram.mem[32 + r_i] = pack4(w2_v[r_i*4+0], w2_v[r_i*4+1], w2_v[r_i*4+2], w2_v[r_i*4+3]);
      u_soc.u_sram.mem[36 + r_i] = b2_v[r_i];
    end

    for (s_i = 0; s_i < 4; s_i = s_i + 1) begin
      u_soc.u_sram.mem[40 + s_i*2 + 0] = pack4(mlp_in[s_i*8+0], mlp_in[s_i*8+1], mlp_in[s_i*8+2], mlp_in[s_i*8+3]);
      u_soc.u_sram.mem[40 + s_i*2 + 1] = pack4(mlp_in[s_i*8+4], mlp_in[s_i*8+5], mlp_in[s_i*8+6], mlp_in[s_i*8+7]);
      for (r_i = 0; r_i < 4; r_i = r_i + 1) begin
        acc_v = b1_v[r_i];
        for (c_i = 0; c_i < 4; c_i = c_i + 1) acc_v = acc_v + s8(mlp_in[s_i*8+c_i]) * s8(w1_t0[r_i*4+c_i]);
        for (c_i = 0; c_i < 4; c_i = c_i + 1) acc_v = acc_v + s8(mlp_in[s_i*8+4+c_i]) * s8(w1_t1[r_i*4+c_i]);
        h_vec[r_i] = ref_clamp_relu(acc_v, 2, 1);
      end
      for (r_i = 0; r_i < 4; r_i = r_i + 1) begin
        acc_v = b2_v[r_i];
        for (c_i = 0; c_i < 4; c_i = c_i + 1) acc_v = acc_v + h_vec[c_i] * s8(w2_v[r_i*4+c_i]);
        mlp_gold[s_i*4 + r_i] = ref_clamp_relu(acc_v, 3, 1);
      end
    end

    u_soc.u_sram.mem[64] = pack4(2, 3, 4, 5);
    u_soc.u_sram.mem[65] = pack4(5, 10, 4, 0);
    u_soc.u_sram.mem[66] = pack4(-2, 4, 14, 0);
    u_soc.u_sram.mem[67] = pack4(3, -1, 9, 0);
    u_soc.u_sram.mem[68] = pack4(7, 2, 12, 0);
    u_soc.u_sram.mem[69] = 32'sd0;
    u_soc.u_sram.mem[70] = 32'sd20;
    u_soc.u_sram.mem[71] = 32'sd0;
    u_soc.u_sram.mem[72] = -32'sd5;

    for (s_i = 0; s_i < 16; s_i = s_i + 1) begin
      u_soc.u_sram.mem[80 + s_i] = 32'h1000 + s_i;
    end

    snap_fn_pc = 220;
    emit_pc = snap_fn_pc;
    emit(enc_lw(12, 3, 32'h00));
    emit(enc_sw(12, 11, 0));
    emit(enc_lw(12, 3, 32'h1c));
    emit(enc_sw(12, 11, 4));
    emit(enc_lw(12, 3, 32'h10));
    emit(enc_sw(12, 11, 8));
    emit(enc_lw(12, 3, 32'h38));
    emit(enc_sw(12, 11, 12));
    emit(enc_lw(12, 3, 32'h08));
    emit(enc_sw(12, 11, 16));
    emit(enc_jalr(0, 10, 0));

    emit_pc = 240;
    emit(enc_addi(27, 27, 1));
    emit(enc_sw(0, 7, 4));
    emit(enc_addi(29, 0, 2));
    emit(enc_sw(29, 2, 0));
    emit(32'h3020_0073);

    emit_to_sram = 0;
    emit_pc = 0;
    emit(enc_u(32'h00011, 12, 7'b0110111));
    emit(enc_jalr(0, 12, 0));

    emit_to_sram = 1;
    emit_pc = 1024;
    emit(enc_addi(26, 0, snap_fn_pc * 4));
    emit(enc_u(32'h00010, 1, 7'b0110111));
    emit(enc_u(32'h40001, 2, 7'b0110111));
    emit(enc_u(32'h40004, 3, 7'b0110111));
    emit(enc_u(32'h40000, 4, 7'b0110111));
    emit(enc_u(32'h40006, 5, 7'b0110111));
    emit(enc_u(32'h40007, 6, 7'b0110111));
    emit(enc_u(32'h40008, 7, 7'b0110111));
    emit(enc_addi(27, 0, 0));
    emit(enc_addi(12, 0, 32'h3c0));
    emit(enc_csr(12'h305, 12, 3'b001, 0));

    emit_snap(0);
    emit(enc_addi(13, 0, 0));
    l_cpu_row = emit_pc;
    emit(enc_slli(14, 13, 2));
    emit(enc_add(15, 1, 14));
    emit(enc_lw(16, 15, 20));
    emit(enc_addi(17, 0, 0));
    l_cpu_col = emit_pc;
    emit(enc_add(18, 1, 17));
    emit(enc_lb(19, 18, 0));
    emit(enc_add(20, 15, 17));
    emit(enc_lb(21, 20, 4));
    emit(enc_r(7'b0000001, 21, 19, 3'b000, 22));
    emit(enc_add(16, 16, 22));
    emit(enc_addi(17, 17, 1));
    emit(enc_addi(22, 0, 4));
    emit(enc_b((l_cpu_col - emit_pc) * 4, 22, 17, 3'b001));
    emit(enc_srai(16, 16, 3));
    p_cpu_relu = emit_pc; emit(32'd0);
    emit(enc_addi(16, 0, 0));
    u_soc.u_sram.mem[p_cpu_relu] = enc_b((emit_pc - p_cpu_relu) * 4, 0, 16, 3'b101);
    emit(enc_addi(22, 0, 127));
    p_cpu_hi = emit_pc; emit(32'd0);
    emit(enc_addi(16, 0, 127));
    u_soc.u_sram.mem[p_cpu_hi] = enc_b((emit_pc - p_cpu_hi) * 4, 16, 22, 3'b101);
    emit(enc_sw(16, 15, 48));
    emit(enc_addi(13, 13, 1));
    emit(enc_addi(22, 0, 4));
    emit(enc_b((l_cpu_row - emit_pc) * 4, 22, 13, 3'b001));
    emit_snap(1);

    emit_snap(2);
    emit(enc_lw(12, 1, 0));    emit(enc_sw(12, 2, 16'h30));
    emit(enc_lw(12, 1, 4));    emit(enc_sw(12, 2, 16'h34));
    emit(enc_lw(12, 1, 8));    emit(enc_sw(12, 2, 16'h38));
    emit(enc_lw(12, 1, 12));   emit(enc_sw(12, 2, 16'h3c));
    emit(enc_lw(12, 1, 16));   emit(enc_sw(12, 2, 16'h40));
    emit(enc_lw(12, 1, 20));   emit(enc_sw(12, 2, 16'h08));
    emit(enc_lw(12, 1, 24));   emit(enc_sw(12, 2, 16'h60));
    emit(enc_lw(12, 1, 28));   emit(enc_sw(12, 2, 16'h64));
    emit(enc_lw(12, 1, 32));   emit(enc_sw(12, 2, 16'h68));
    emit(enc_addi(12, 0, 3));  emit(enc_sw(12, 2, 16'h0c));
    emit(enc_addi(12, 0, 16'h139)); emit(enc_sw(12, 2, 16'h00));
    l_npu_poll1 = emit_pc;
    emit(enc_lw(12, 2, 0));
    emit(enc_i(1, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_npu_poll1 - emit_pc) * 4, 0, 12, 3'b001));
    emit(enc_lw(12, 2, 16'h04)); emit(enc_sw(12, 1, 64));
    emit(enc_lw(12, 2, 16'h44)); emit(enc_sw(12, 1, 68));
    emit(enc_lw(12, 2, 16'h48)); emit(enc_sw(12, 1, 72));
    emit(enc_lw(12, 2, 16'h4c)); emit(enc_sw(12, 1, 76));
    emit_snap(3);

    emit_snap(4);
    emit(enc_addi(13, 0, 0));
    l_mlp_sample = emit_pc;
    emit(enc_slli(14, 13, 3));
    emit(enc_add(15, 1, 14));
    emit(enc_lw(12, 15, 16'h0a0)); emit(enc_sw(12, 2, 16'h30));
    emit(enc_lw(12, 1, 16'h050));  emit(enc_sw(12, 2, 16'h34));
    emit(enc_lw(12, 1, 16'h054));  emit(enc_sw(12, 2, 16'h38));
    emit(enc_lw(12, 1, 16'h058));  emit(enc_sw(12, 2, 16'h3c));
    emit(enc_lw(12, 1, 16'h05c));  emit(enc_sw(12, 2, 16'h40));
    emit(enc_lw(12, 1, 16'h070));  emit(enc_sw(12, 2, 16'h08));
    emit(enc_lw(12, 1, 16'h074));  emit(enc_sw(12, 2, 16'h60));
    emit(enc_lw(12, 1, 16'h078));  emit(enc_sw(12, 2, 16'h64));
    emit(enc_lw(12, 1, 16'h07c));  emit(enc_sw(12, 2, 16'h68));
    emit(enc_sw(0, 2, 16'h0c));
    emit(enc_addi(12, 0, 16'h031)); emit(enc_sw(12, 2, 16'h00));
    l_mlp_t0 = emit_pc;
    emit(enc_lw(12, 2, 0)); emit(enc_i(1, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_mlp_t0 - emit_pc) * 4, 0, 12, 3'b001));

    emit(enc_lw(12, 15, 16'h0a4)); emit(enc_sw(12, 2, 16'h30));
    emit(enc_lw(12, 1, 16'h060));  emit(enc_sw(12, 2, 16'h34));
    emit(enc_lw(12, 1, 16'h064));  emit(enc_sw(12, 2, 16'h38));
    emit(enc_lw(12, 1, 16'h068));  emit(enc_sw(12, 2, 16'h3c));
    emit(enc_lw(12, 1, 16'h06c));  emit(enc_sw(12, 2, 16'h40));
    emit(enc_addi(12, 0, 2));       emit(enc_sw(12, 2, 16'h0c));
    emit(enc_addi(12, 0, 16'h12d)); emit(enc_sw(12, 2, 16'h00));
    l_mlp_t1 = emit_pc;
    emit(enc_lw(12, 2, 0)); emit(enc_i(1, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_mlp_t1 - emit_pc) * 4, 0, 12, 3'b001));

    emit(enc_lw(16, 2, 16'h04));
    emit(enc_i(255, 16, 3'b111, 16, 7'b0010011));
    emit(enc_lw(17, 2, 16'h44));
    emit(enc_i(255, 17, 3'b111, 17, 7'b0010011));
    emit(enc_slli(17, 17, 8));
    emit(enc_or(16, 16, 17));
    emit(enc_lw(17, 2, 16'h48));
    emit(enc_i(255, 17, 3'b111, 17, 7'b0010011));
    emit(enc_slli(17, 17, 16));
    emit(enc_or(16, 16, 17));
    emit(enc_lw(17, 2, 16'h4c));
    emit(enc_i(255, 17, 3'b111, 17, 7'b0010011));
    emit(enc_slli(17, 17, 24));
    emit(enc_or(16, 16, 17));

    emit(enc_sw(16, 2, 16'h30));
    emit(enc_lw(12, 1, 16'h080));  emit(enc_sw(12, 2, 16'h34));
    emit(enc_lw(12, 1, 16'h084));  emit(enc_sw(12, 2, 16'h38));
    emit(enc_lw(12, 1, 16'h088));  emit(enc_sw(12, 2, 16'h3c));
    emit(enc_lw(12, 1, 16'h08c));  emit(enc_sw(12, 2, 16'h40));
    emit(enc_lw(12, 1, 16'h090));  emit(enc_sw(12, 2, 16'h08));
    emit(enc_lw(12, 1, 16'h094));  emit(enc_sw(12, 2, 16'h60));
    emit(enc_lw(12, 1, 16'h098));  emit(enc_sw(12, 2, 16'h64));
    emit(enc_lw(12, 1, 16'h09c));  emit(enc_sw(12, 2, 16'h68));
    emit(enc_addi(12, 0, 3));       emit(enc_sw(12, 2, 16'h0c));
    emit(enc_addi(12, 0, 16'h139)); emit(enc_sw(12, 2, 16'h00));
    l_mlp_l2 = emit_pc;
    emit(enc_lw(12, 2, 0)); emit(enc_i(1, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_mlp_l2 - emit_pc) * 4, 0, 12, 3'b001));

    emit(enc_slli(14, 13, 4));
    emit(enc_add(15, 1, 14));
    emit(enc_lw(12, 2, 16'h04)); emit(enc_sw(12, 15, 16'h0c0));
    emit(enc_lw(12, 2, 16'h44)); emit(enc_sw(12, 15, 16'h0c4));
    emit(enc_lw(12, 2, 16'h48)); emit(enc_sw(12, 15, 16'h0c8));
    emit(enc_lw(12, 2, 16'h4c)); emit(enc_sw(12, 15, 16'h0cc));

    emit(enc_addi(13, 13, 1));
    emit(enc_addi(12, 0, 4));
    emit(enc_b((l_mlp_sample - emit_pc) * 4, 12, 13, 3'b001));
    emit_snap(5);

    emit_snap(6);
    emit(enc_lw(12, 1, 16'h100)); emit(enc_sw(12, 2, 16'h30));
    emit(enc_lw(12, 1, 16'h104)); emit(enc_sw(12, 2, 16'h34));
    emit(enc_lw(12, 1, 16'h108)); emit(enc_sw(12, 2, 16'h38));
    emit(enc_lw(12, 1, 16'h10c)); emit(enc_sw(12, 2, 16'h3c));
    emit(enc_lw(12, 1, 16'h110)); emit(enc_sw(12, 2, 16'h40));
    emit(enc_lw(12, 1, 16'h114)); emit(enc_sw(12, 2, 16'h08));
    emit(enc_lw(12, 1, 16'h118)); emit(enc_sw(12, 2, 16'h60));
    emit(enc_lw(12, 1, 16'h11c)); emit(enc_sw(12, 2, 16'h64));
    emit(enc_lw(12, 1, 16'h120)); emit(enc_sw(12, 2, 16'h68));
    emit(enc_sw(0, 2, 16'h0c));
    emit(enc_addi(12, 0, 16'h0b9)); emit(enc_sw(12, 2, 16'h00));
    l_sp_poll = emit_pc;
    emit(enc_lw(12, 2, 0)); emit(enc_i(1, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_sp_poll - emit_pc) * 4, 0, 12, 3'b001));
    emit(enc_lw(12, 2, 16'h04)); emit(enc_sw(12, 1, 16'h124));
    emit(enc_lw(12, 2, 16'h44)); emit(enc_sw(12, 1, 16'h128));
    emit(enc_lw(12, 2, 16'h48)); emit(enc_sw(12, 1, 16'h12c));
    emit(enc_lw(12, 2, 16'h4c)); emit(enc_sw(12, 1, 16'h130));
    emit_snap(7);

    emit_snap(8);
    emit(enc_addi(12, 1, 16'h140)); emit(enc_sw(12, 5, 16'h00));
    emit(enc_addi(12, 1, 16'h180)); emit(enc_sw(12, 5, 16'h04));
    emit(enc_addi(12, 0, 16));       emit(enc_sw(12, 5, 16'h08));
    emit(enc_addi(12, 0, 1));        emit(enc_sw(12, 5, 16'h0c));
    l_dma_poll = emit_pc;
    emit(enc_lw(12, 5, 16'h0c)); emit(enc_i(2, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_dma_poll - emit_pc) * 4, 0, 12, 3'b001));
    emit_snap(9);

    emit_snap(10);
    emit(enc_addi(12, 0, 300)); emit(enc_sw(12, 6, 4));
    emit(enc_addi(12, 0, 400)); emit(enc_sw(12, 6, 8));
    emit(enc_sw(0, 6, 12));
    emit(enc_addi(12, 0, 4));   emit(enc_sw(12, 6, 0));
    l_cordic_poll = emit_pc;
    emit(enc_lw(12, 6, 0)); emit(enc_i(2, 12, 3'b111, 12, 7'b0010011));
    emit(enc_b((l_cordic_poll - emit_pc) * 4, 0, 12, 3'b001));
    emit(enc_lw(12, 6, 16)); emit(enc_sw(12, 1, 16'h1c0));
    emit_snap(11);

    emit_snap(12);
    emit(enc_sw(0, 2, 16'h30));
    emit(enc_u(32'h01010, 12, 7'b0110111));
    emit(enc_addi(12, 12, 257));
    emit(enc_sw(12, 2, 16'h34));
    emit(enc_sw(0, 2, 16'h0c));
    emit(enc_sw(0, 2, 16'h08));
    emit(enc_addi(12, 0, 100)); emit(enc_sw(12, 2, 16'h6c));
    emit(enc_addi(12, 0, 16'h202)); emit(enc_sw(12, 2, 16'h00));
    emit(enc_sw(0, 4, 16'h10));
    emit(enc_addi(12, 0, 5)); emit(enc_sw(12, 4, 16'h00));
    emit(enc_addi(12, 0, 2)); emit(enc_sw(12, 7, 16'h04));
    emit(enc_addi(12, 0, 1)); emit(enc_i(11, 12, 3'b001, 12, 7'b0010011));
    emit(enc_csr(12'h304, 12, 3'b001, 0));
    emit(enc_addi(12, 0, 8)); emit(enc_csr(12'h300, 12, 3'b001, 0));
    emit(enc_u(32'ha0000, 12, 7'b0110111));
    emit(enc_addi(12, 12, 1));
    emit(enc_sw(12, 1, 16'h3fc));
    emit(32'h1050_0073);

    emit_snap(13);
    emit(enc_sw(27, 1, 16'h3f8));
    emit(enc_u(32'h12345, 12, 7'b0110111));
    emit(enc_addi(12, 12, 1656));
    emit(enc_sw(12, 1, 16'h3f4));
    emit(32'h1050_0073);
    emit(32'hffdff06f);

    if (emit_pc > 2048) begin
      $display("SRAM_OVERFLOW emit_pc=%0d", emit_pc);
      $finish;
    end

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (u_soc.u_sram.mem[255] != 32'ha000_0001 && !core_trap && cycles < 4000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    while (!core_sleep && !core_trap && cycles < 4000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    for (s_i = 0; s_i < 16; s_i = s_i + 1) begin
      push_sensor(16'h0505);
      repeat (6) begin
        @(posedge clk);
        cycles = cycles + 1;
        if (!core_sleep) wake_err = wake_err + 1;
      end
    end

    push_sensor(16'h5050);

    while (u_soc.u_sram.mem[253] != 32'h1234_5678 && !core_trap && cycles < 5000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (core_trap) failures = failures + 1;
    if (wake_err != 0) failures = failures + 1;
    if (u_soc.u_sram.mem[12] != 32'd13 || u_soc.u_sram.mem[13] != 32'd75 || u_soc.u_sram.mem[14] != 32'd0 || u_soc.u_sram.mem[15] != 32'd88) failures = failures + 1;
    if (u_soc.u_sram.mem[16] != 32'd13 || u_soc.u_sram.mem[17] != 32'd75 || u_soc.u_sram.mem[18] != 32'd0 || u_soc.u_sram.mem[19] != 32'd88) failures = failures + 1;

    for (s_i = 0; s_i < 4; s_i = s_i + 1) begin
      for (r_i = 0; r_i < 4; r_i = r_i + 1) begin
        if ($signed(u_soc.u_sram.mem[48 + s_i*4 + r_i]) != mlp_gold[s_i*4 + r_i]) begin
          $display("MLP_MISMATCH s=%0d r=%0d got=%0d exp=%0d", s_i, r_i, $signed(u_soc.u_sram.mem[48 + s_i*4 + r_i]), mlp_gold[s_i*4 + r_i]);
          failures = failures + 1;
        end
      end
    end

    if (u_soc.u_sram.mem[73] != 32'd40 || u_soc.u_sram.mem[74] != 32'd32 || u_soc.u_sram.mem[75] != 32'd5 || u_soc.u_sram.mem[76] != 32'd19) failures = failures + 1;
    for (s_i = 0; s_i < 16; s_i = s_i + 1) begin
      if (u_soc.u_sram.mem[96 + s_i] != (32'h1000 + s_i)) failures = failures + 1;
    end
    if (u_soc.u_sram.mem[112] < 32'd495 || u_soc.u_sram.mem[112] > 32'd505) failures = failures + 1;
    if (u_soc.u_sram.mem[254] != 32'd1) failures = failures + 1;

    $display("---------------------------------------------------------------------------------------------------------------------------------------------------");
    $display("ORX-1 Hardware Model & Speed Benchmark @ 50 MHz (code_words=%0d/1024 SRAM)", emit_pc - 1024);
    $display("---------------------------------------------------------------------------------------------------------------------------------------------------");
    report_bench("cpu_mlp_4x4",      0,  1,  16, 0);
    report_bench("npu_mlp_4x4",      2,  3,  16, 0);
    report_bench("npu_mlp_8x4x4_x4", 4,  5, 192, 0);
    report_bench("npu_sparse_2_4",   6,  7,   8, 0);
    report_bench("dma_burst_16w",    8,  9,   0, 0);
    report_bench("cordic_vec_mag",  10, 11,   0, 0);
    report_bench("auto_stream_wfi", 12, 13,  68, u_soc.u_sram.mem[254]);
    $display("---------------------------------------------------------------------------------------------------------------------------------------------------");
    $display("SPEEDUP_4X4_NPU_VS_CPU=%0.2fx",
             $itor(u_soc.u_sram.mem[128 + 1*5 + 0] - u_soc.u_sram.mem[128 + 0*5 + 0]) /
             $itor(u_soc.u_sram.mem[128 + 3*5 + 0] - u_soc.u_sram.mem[128 + 2*5 + 0]));
    $display("ENERGY_RATIO_4X4_CPU_TO_NPU=%0.2fx",
             $itor(u_soc.u_sram.mem[128 + 1*5 + 2] - u_soc.u_sram.mem[128 + 0*5 + 2]) /
             $itor(u_soc.u_sram.mem[128 + 3*5 + 2] - u_soc.u_sram.mem[128 + 2*5 + 2]));

    fd_csv = $fopen("build/model_benchmark.csv", "w");
    if (fd_csv != 0) begin
      $fdisplay(fd_csv, "workload,cycles,instructions,cpi,lat_us,macs,mops_50m,weighted_energy,sleep_cycles,accel_events,wakeups");
      write_csv_row(fd_csv, "cpu_mlp_4x4",      0,  1,  16, 0);
      write_csv_row(fd_csv, "npu_mlp_4x4",      2,  3,  16, 0);
      write_csv_row(fd_csv, "npu_mlp_8x4x4_x4", 4,  5, 192, 0);
      write_csv_row(fd_csv, "npu_sparse_2_4",   6,  7,   8, 0);
      write_csv_row(fd_csv, "dma_burst_16w",    8,  9,   0, 0);
      write_csv_row(fd_csv, "cordic_vec_mag",  10, 11,   0, 0);
      write_csv_row(fd_csv, "auto_stream_wfi", 12, 13,  68, u_soc.u_sram.mem[254]);
      $fclose(fd_csv);
    end

    if (failures == 0) $display("MODEL_BENCH_PASS total_cycles=%0d", cycles);
    else $display("MODEL_BENCH_FAIL %0d total_cycles=%0d", failures, cycles);
    $finish;
  end
endmodule
