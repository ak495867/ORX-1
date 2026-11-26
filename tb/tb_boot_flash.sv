`timescale 1ns/1ps
module spi_flash_model (
  input logic spi_sck,
  input logic spi_mosi,
  output logic spi_miso,
  input logic spi_cs_n,
  input logic [31:0] mem0, mem1, mem2, mem3, mem4, mem5, mem6, mem7,
  input logic [31:0] mem8, mem9, mem10, mem11, mem12, mem13, mem14, mem15,
  input logic [31:0] mem16, mem17, mem18, mem19, mem20, mem21, mem22, mem23,
  input logic [31:0] mem24, mem25, mem26, mem27, mem28, mem29, mem30, mem31
);
  logic [31:0] mem [0:31];
  logic [31:0] cmd_shift = 32'd0;
  logic [31:0] tx_shift = 32'd0;
  logic [4:0] bit_cnt = 5'd0;
  logic [4:0] word_idx = 5'd0;
  logic data_phase = 1'b0;
  logic miso_q = 1'b0;

  always @(*) begin
    mem[0]  = mem0;  mem[1]  = mem1;  mem[2]  = mem2;  mem[3]  = mem3;
    mem[4]  = mem4;  mem[5]  = mem5;  mem[6]  = mem6;  mem[7]  = mem7;
    mem[8]  = mem8;  mem[9]  = mem9;  mem[10] = mem10; mem[11] = mem11;
    mem[12] = mem12; mem[13] = mem13; mem[14] = mem14; mem[15] = mem15;
    mem[16] = mem16; mem[17] = mem17; mem[18] = mem18; mem[19] = mem19;
    mem[20] = mem20; mem[21] = mem21; mem[22] = mem22; mem[23] = mem23;
    mem[24] = mem24; mem[25] = mem25; mem[26] = mem26; mem[27] = mem27;
    mem[28] = mem28; mem[29] = mem29; mem[30] = mem30; mem[31] = mem31;
  end

  assign spi_miso = spi_cs_n ? 1'b0 : miso_q;

  always @(posedge spi_cs_n) begin
    bit_cnt <= 5'd0;
    data_phase <= 1'b0;
    miso_q <= 1'b0;
    cmd_shift <= 32'd0;
    tx_shift <= 32'd0;
    word_idx <= 5'd0;
  end

  always @(posedge spi_sck) begin
    if (!spi_cs_n) begin
      if (!data_phase) begin
        cmd_shift <= {cmd_shift[30:0], spi_mosi};
        if (bit_cnt == 5'd31) begin
          data_phase <= 1'b1;
          word_idx <= cmd_shift[5:1];
          tx_shift <= mem[cmd_shift[5:1]];
          bit_cnt <= 5'd0;
        end else begin
          bit_cnt <= bit_cnt + 5'd1;
        end
      end else begin
        if (bit_cnt == 5'd31) begin
          word_idx <= word_idx + 5'd1;
          tx_shift <= mem[word_idx + 5'd1];
          bit_cnt <= 5'd0;
        end else begin
          bit_cnt <= bit_cnt + 5'd1;
        end
      end
    end
  end

  always @(negedge spi_sck) begin
    if (!spi_cs_n && data_phase) begin
      miso_q <= tx_shift[31];
      tx_shift <= {tx_shift[30:0], 1'b0};
    end
  end
endmodule

module tb_boot_flash;
  logic clk = 1'b0;
  logic reset = 1'b1;
  always #5 clk = ~clk;

  logic [31:0] flash_ok [0:31];
  logic [31:0] flash_bad [0:31];

  logic ok_sck, ok_mosi, ok_miso, ok_cs_n;
  logic ok_boot_release, ok_boot_fail, ok_trap, ok_sleep, ok_uart_tx;
  logic ok_ack;
  logic [31:0] ok_dat_o;
  logic wb_cyc = 1'b0, wb_stb = 1'b0, wb_we = 1'b0;
  logic [3:0] wb_sel = 4'b1111;
  logic [31:0] wb_adr = 32'd0, wb_dat_i = 32'd0;

  logic bad_sck, bad_mosi, bad_miso, bad_cs_n;
  logic bad_boot_release, bad_boot_fail, bad_trap, bad_sleep, bad_uart_tx;
  logic bad_ack;
  logic [31:0] bad_dat_o;

  orx1_soc #(.BUILTIN_BOOTLOADER(1'b1)) u_soc_ok (
    .clk(clk), .reset(reset), .sensor_valid(1'b0), .sensor_data(16'd0),
    .sensor_result_valid(), .sensor_result(),
    .accelerator_irq(), .boot_release(ok_boot_release), .boot_fail(ok_boot_fail),
    .core_trap(ok_trap), .core_sleep(ok_sleep), .sensor_alert(),
    .uart_rx(1'b1), .uart_tx(ok_uart_tx),
    .gpio_in(16'd0), .gpio_out(), .gpio_oe(),
    .spi_sck(ok_sck), .spi_mosi(ok_mosi), .spi_miso(ok_miso), .spi_cs_n(ok_cs_n),
    .wb_host_cyc_i(wb_cyc), .wb_host_stb_i(wb_stb), .wb_host_we_i(wb_we),
    .wb_host_sel_i(wb_sel), .wb_host_adr_i(wb_adr), .wb_host_dat_i(wb_dat_i),
    .wb_host_ack_o(ok_ack), .wb_host_dat_o(ok_dat_o)
  );

  spi_flash_model u_flash_ok (
    .spi_sck(ok_sck), .spi_mosi(ok_mosi), .spi_miso(ok_miso), .spi_cs_n(ok_cs_n),
    .mem0(flash_ok[0]), .mem1(flash_ok[1]), .mem2(flash_ok[2]), .mem3(flash_ok[3]),
    .mem4(flash_ok[4]), .mem5(flash_ok[5]), .mem6(flash_ok[6]), .mem7(flash_ok[7]),
    .mem8(flash_ok[8]), .mem9(flash_ok[9]), .mem10(flash_ok[10]), .mem11(flash_ok[11]),
    .mem12(flash_ok[12]), .mem13(flash_ok[13]), .mem14(flash_ok[14]), .mem15(flash_ok[15]),
    .mem16(flash_ok[16]), .mem17(flash_ok[17]), .mem18(flash_ok[18]), .mem19(flash_ok[19]),
    .mem20(flash_ok[20]), .mem21(flash_ok[21]), .mem22(flash_ok[22]), .mem23(flash_ok[23]),
    .mem24(flash_ok[24]), .mem25(flash_ok[25]), .mem26(flash_ok[26]), .mem27(flash_ok[27]),
    .mem28(flash_ok[28]), .mem29(flash_ok[29]), .mem30(flash_ok[30]), .mem31(flash_ok[31])
  );

  orx1_soc #(.BUILTIN_BOOTLOADER(1'b1)) u_soc_bad (
    .clk(clk), .reset(reset), .sensor_valid(1'b0), .sensor_data(16'd0),
    .sensor_result_valid(), .sensor_result(),
    .accelerator_irq(), .boot_release(bad_boot_release), .boot_fail(bad_boot_fail),
    .core_trap(bad_trap), .core_sleep(bad_sleep), .sensor_alert(),
    .uart_rx(1'b1), .uart_tx(bad_uart_tx),
    .gpio_in(16'd0), .gpio_out(), .gpio_oe(),
    .spi_sck(bad_sck), .spi_mosi(bad_mosi), .spi_miso(bad_miso), .spi_cs_n(bad_cs_n),
    .wb_host_cyc_i(1'b0), .wb_host_stb_i(1'b0), .wb_host_we_i(1'b0),
    .wb_host_sel_i(4'b0000), .wb_host_adr_i(32'd0), .wb_host_dat_i(32'd0),
    .wb_host_ack_o(bad_ack), .wb_host_dat_o(bad_dat_o)
  );

  spi_flash_model u_flash_bad (
    .spi_sck(bad_sck), .spi_mosi(bad_mosi), .spi_miso(bad_miso), .spi_cs_n(bad_cs_n),
    .mem0(flash_bad[0]), .mem1(flash_bad[1]), .mem2(flash_bad[2]), .mem3(flash_bad[3]),
    .mem4(flash_bad[4]), .mem5(flash_bad[5]), .mem6(flash_bad[6]), .mem7(flash_bad[7]),
    .mem8(flash_bad[8]), .mem9(flash_bad[9]), .mem10(flash_bad[10]), .mem11(flash_bad[11]),
    .mem12(flash_bad[12]), .mem13(flash_bad[13]), .mem14(flash_bad[14]), .mem15(flash_bad[15]),
    .mem16(flash_bad[16]), .mem17(flash_bad[17]), .mem18(flash_bad[18]), .mem19(flash_bad[19]),
    .mem20(flash_bad[20]), .mem21(flash_bad[21]), .mem22(flash_bad[22]), .mem23(flash_bad[23]),
    .mem24(flash_bad[24]), .mem25(flash_bad[25]), .mem26(flash_bad[26]), .mem27(flash_bad[27]),
    .mem28(flash_bad[28]), .mem29(flash_bad[29]), .mem30(flash_bad[30]), .mem31(flash_bad[31])
  );

  function automatic [31:0] rotr32(input logic [31:0] x, input integer n);
    rotr32 = (x >> n) | (x << (32 - n));
  endfunction

  function automatic [255:0] sha256_single_block(input logic [511:0] blk);
    logic [31:0] k [0:63];
    logic [31:0] w [0:63];
    logic [31:0] a, b, c, d, e, f, g, h;
    logic [31:0] s0, s1, ch, maj, t1, t2;
    integer t;
    begin
      k[ 0]=32'h428a2f98; k[ 1]=32'h71374491; k[ 2]=32'hb5c0fbcf; k[ 3]=32'he9b5dba5;
      k[ 4]=32'h3956c25b; k[ 5]=32'h59f111f1; k[ 6]=32'h923f82a4; k[ 7]=32'hab1c5ed5;
      k[ 8]=32'hd807aa98; k[ 9]=32'h12835b01; k[10]=32'h243185be; k[11]=32'h550c7dc3;
      k[12]=32'h72be5d74; k[13]=32'h80deb1fe; k[14]=32'h9bdc06a7; k[15]=32'hc19bf174;
      k[16]=32'he49b69c1; k[17]=32'hefbe4786; k[18]=32'h0fc19dc6; k[19]=32'h240ca1cc;
      k[20]=32'h2de92c6f; k[21]=32'h4a7484aa; k[22]=32'h5cb0a9dc; k[23]=32'h76f988da;
      k[24]=32'h983e5152; k[25]=32'ha831c66d; k[26]=32'hb00327c8; k[27]=32'hbf597fc7;
      k[28]=32'hc6e00bf3; k[29]=32'hd5a79147; k[30]=32'h06ca6351; k[31]=32'h14292967;
      k[32]=32'h27b70a85; k[33]=32'h2e1b2138; k[34]=32'h4d2c6dfc; k[35]=32'h53380d13;
      k[36]=32'h650a7354; k[37]=32'h766a0abb; k[38]=32'h81c2c92e; k[39]=32'h92722c85;
      k[40]=32'ha2bfe8a1; k[41]=32'ha81a664b; k[42]=32'hc24b8b70; k[43]=32'hc76c51a3;
      k[44]=32'hd192e819; k[45]=32'hd6990624; k[46]=32'hf40e3585; k[47]=32'h106aa070;
      k[48]=32'h19a4c116; k[49]=32'h1e376c08; k[50]=32'h2748774c; k[51]=32'h34b0bcb5;
      k[52]=32'h391c0cb3; k[53]=32'h4ed8aa4a; k[54]=32'h5b9cca4f; k[55]=32'h682e6ff3;
      k[56]=32'h748f82ee; k[57]=32'h78a5636f; k[58]=32'h84c87814; k[59]=32'h8cc70208;
      k[60]=32'h90befffa; k[61]=32'ha4506ceb; k[62]=32'hbef9a3f7; k[63]=32'hc67178f2;
      for (t = 0; t < 16; t = t + 1) w[t] = blk[t*32 +: 32];
      for (t = 16; t < 64; t = t + 1) begin
        s0 = rotr32(w[t-15], 7) ^ rotr32(w[t-15], 18) ^ (w[t-15] >> 3);
        s1 = rotr32(w[t-2], 17) ^ rotr32(w[t-2], 19) ^ (w[t-2] >> 10);
        w[t] = w[t-16] + s0 + w[t-7] + s1;
      end
      a=32'h6a09e667; b=32'hbb67ae85; c=32'h3c6ef372; d=32'ha54ff53a;
      e=32'h510e527f; f=32'h9b05688c; g=32'h1f83d9ab; h=32'h5be0cd19;
      for (t = 0; t < 64; t = t + 1) begin
        s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
        ch = (e & f) ^ ((~e) & g);
        t1 = h + s1 + ch + k[t] + w[t];
        s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
        maj = (a & b) ^ (a & c) ^ (b & c);
        t2 = s0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
      end
      sha256_single_block = {
        32'h6a09e667 + a, 32'hbb67ae85 + b, 32'h3c6ef372 + c, 32'ha54ff53a + d,
        32'h510e527f + e, 32'h9b05688c + f, 32'h1f83d9ab + g, 32'h5be0cd19 + h
      };
    end
  endfunction

  task automatic wb_host_op(input logic we, input logic [31:0] a, input logic [31:0] d, output logic [31:0] q);
    integer w;
    begin
      @(negedge clk);
      wb_we = we; wb_adr = a; wb_dat_i = d; wb_sel = 4'b1111; wb_cyc = 1'b1; wb_stb = 1'b1;
      @(posedge clk); #1;
      w = 0;
      while (!ok_ack && w < 6) begin
        @(posedge clk); #1;
        w = w + 1;
      end
      q = ok_dat_o;
      @(negedge clk);
      wb_cyc = 1'b0; wb_stb = 1'b0; wb_we = 1'b0;
    end
  endtask

  integer i, cycles = 0, failures = 0;
  logic [511:0] blk;
  logic [255:0] digest;
  logic [31:0] payload [0:7];
  logic [31:0] tmp;

  initial begin
    payload[0] = 32'h000100b7;
    payload[1] = 32'hcafec637;
    payload[2] = 32'heef60613;
    payload[3] = 32'h40c0a023;
    payload[4] = 32'h600dc6b7;
    payload[5] = 32'h00768693;
    payload[6] = 32'h3ed0ae23;
    payload[7] = 32'h10500073;

    blk = 512'd0;
    for (i = 0; i < 8; i = i + 1) blk[i*32 +: 32] = payload[i];
    blk[8*32 +: 32] = 32'h8000_0000;
    blk[15*32 +: 32] = 32'd256;
    digest = sha256_single_block(blk);

    for (i = 0; i < 32; i = i + 1) begin
      flash_ok[i] = 32'd0;
      flash_bad[i] = 32'd0;
    end
    flash_ok[0] = 32'h4F52_5831;
    flash_ok[1] = 32'd8;
    for (i = 0; i < 8; i = i + 1) flash_ok[2 + i] = digest[i*32 +: 32];
    for (i = 0; i < 8; i = i + 1) flash_ok[10 + i] = payload[i];

    for (i = 0; i < 32; i = i + 1) flash_bad[i] = flash_ok[i];
    flash_bad[10] = payload[0] ^ 32'h0000_0001;

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while ((!(ok_boot_release && ok_sleep) || !(bad_boot_fail && bad_sleep)) && cycles < 50000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!ok_boot_release || ok_boot_fail || ok_trap || !ok_sleep) failures = failures + 1;
    if (u_soc_ok.u_sram.mem[256] != 32'hcafe_beef) failures = failures + 1;
    if (u_soc_ok.u_sram.mem[255] != 32'h600d_c007) failures = failures + 1;
    if (!bad_boot_fail || bad_boot_release || !bad_sleep) failures = failures + 1;
    if (u_soc_bad.u_sram.mem[256] != 32'd0 || u_soc_bad.u_sram.mem[255] != 32'd0) failures = failures + 1;

    wb_host_op(1'b0, 32'h4000_200c, 32'd0, tmp);
    wb_host_op(1'b1, 32'h4000_200c, 32'd0, tmp);
    wb_host_op(1'b0, 32'h4000_2018, 32'd0, tmp);
    if (tmp != digest[31:0]) failures = failures + 1;

    wb_host_op(1'b0, 32'h4000_F000, 32'd0, tmp);
    wb_host_op(1'b0, 32'h4000_b000, 32'd0, tmp);
    if (!tmp[3]) failures = failures + 1;
    wb_host_op(1'b1, 32'h4000_b000, 32'h08, tmp);
    wb_host_op(1'b0, 32'h4000_b000, 32'd0, tmp);
    if (tmp[3]) failures = failures + 1;

    if (failures == 0) $display("BOOT_FLASH_TEST_PASS cycles=%0d", cycles);
    else $display("BOOT_FLASH_TEST_FAIL %0d cyc=%0d ok_pc=0x%08x ok_rel=%0d ok_fail=%0d ok_sleep=%0d sram0=0x%08x bad_pc=0x%08x bad_fail=%0d", failures, cycles, u_soc_ok.core.pc, ok_boot_release, ok_boot_fail, ok_sleep, u_soc_ok.u_sram.mem[0], u_soc_bad.core.pc, bad_boot_fail);
    $finish;
  end
endmodule
