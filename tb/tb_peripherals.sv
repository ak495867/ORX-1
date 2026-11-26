`timescale 1ns/1ps
module tb_peripherals;
  logic clk = 1'b0;
  logic reset = 1'b1;
  integer failures = 0;
  integer cycles = 0;

  always #5 clk = ~clk;

  logic [31:0] cpu_imem_addr, cpu_imem_rdata;
  logic cpu_req_valid, cpu_req_write, cpu_rsp_valid, cpu_trap, cpu_sleep;
  logic [31:0] cpu_req_addr, cpu_req_wdata, cpu_rsp_rdata;
  logic [3:0] cpu_req_wstrb;
  logic [31:0] cpu_ram [0:15];
  logic [31:0] cpu_rom [0:31];

  assign cpu_imem_rdata = cpu_rom[cpu_imem_addr[6:2]];
  assign cpu_rsp_valid = cpu_req_valid;
  assign cpu_rsp_rdata = cpu_ram[cpu_req_addr[5:2]];

  always_ff @(posedge clk) begin
    if (cpu_req_valid && cpu_req_write) begin
      cpu_ram[cpu_req_addr[5:2]] <= cpu_req_wdata;
    end
  end

  rv32i_core u_cpu (
    .clk(clk), .reset(reset), .imem_addr(cpu_imem_addr), .imem_rdata(cpu_imem_rdata),
    .req_valid(cpu_req_valid), .req_ready(1'b1), .req_write(cpu_req_write),
    .req_addr(cpu_req_addr), .req_wdata(cpu_req_wdata), .req_wstrb(cpu_req_wstrb),
    .rsp_valid(cpu_rsp_valid), .rsp_rdata(cpu_rsp_rdata), .rsp_err(1'b0),
    .trap(cpu_trap), .core_sleep(cpu_sleep),
    .perf_cycles(), .perf_instructions(), .perf_loads(), .perf_stores(),
    .perf_branches(), .perf_bus_requests(), .perf_wait_cycles(),
    .irq_external(1'b0), .irq_timer(1'b0)
  );

  logic uart_valid, uart_write, uart_line, uart_irq;
  logic [7:0] uart_addr;
  logic [31:0] uart_wdata, uart_rdata;

  uart_core u_uart (
    .clk(clk), .reset(reset), .csr_valid(uart_valid), .csr_write(uart_write),
    .csr_addr(uart_addr), .csr_wdata(uart_wdata), .csr_rdata(uart_rdata),
    .rx(uart_line), .tx(uart_line), .uart_irq(uart_irq)
  );

  logic soc_sensor_valid = 1'b0;
  logic [15:0] soc_sensor_data = 16'd0;
  logic soc_sensor_result_valid, soc_accel_irq, soc_boot_release, soc_boot_fail;
  logic soc_trap, soc_sleep, soc_alert, soc_uart_tx;
  logic [15:0] soc_gpio_in, soc_gpio_out, soc_gpio_oe;
  logic soc_spi_sck, soc_spi_mosi, soc_spi_miso, soc_spi_cs_n;
  logic wb_cyc = 1'b0, wb_stb = 1'b0, wb_we = 1'b0;
  logic [3:0] wb_sel = 4'b0000;
  logic [31:0] wb_adr = 32'd0, wb_dat_i = 32'd0, wb_dat_o;
  logic wb_ack;

  assign soc_gpio_in = {soc_gpio_out[7:0], 8'd0};
  assign soc_spi_miso = soc_spi_mosi;

  orx1_soc u_soc (
    .clk(clk), .reset(reset), .sensor_valid(soc_sensor_valid), .sensor_data(soc_sensor_data),
    .sensor_result_valid(soc_sensor_result_valid), .sensor_result(),
    .accelerator_irq(soc_accel_irq), .boot_release(soc_boot_release), .boot_fail(soc_boot_fail),
    .core_trap(soc_trap), .core_sleep(soc_sleep), .sensor_alert(soc_alert),
    .uart_rx(1'b1), .uart_tx(soc_uart_tx),
    .gpio_in(soc_gpio_in), .gpio_out(soc_gpio_out), .gpio_oe(soc_gpio_oe),
    .spi_sck(soc_spi_sck), .spi_mosi(soc_spi_mosi), .spi_miso(soc_spi_miso), .spi_cs_n(soc_spi_cs_n),
    .wb_host_cyc_i(wb_cyc), .wb_host_stb_i(wb_stb), .wb_host_we_i(wb_we),
    .wb_host_sel_i(wb_sel), .wb_host_adr_i(wb_adr), .wb_host_dat_i(wb_dat_i),
    .wb_host_ack_o(wb_ack), .wb_host_dat_o(wb_dat_o)
  );

  function automatic [31:0] enc_u(input integer imm20, input integer rd, input integer opcode);
    enc_u = {imm20[19:0], rd[4:0], opcode[6:0]};
  endfunction
  function automatic [31:0] enc_i(input integer imm12, input integer rs1, input integer funct3, input integer rd, input integer opcode);
    enc_i = {imm12[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
  endfunction
  function automatic [31:0] enc_r(input integer funct7, input integer rs2, input integer rs1, input integer funct3, input integer rd);
    enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], 7'b0110011};
  endfunction
  function automatic [31:0] enc_s(input integer imm12, input integer rs2, input integer rs1, input integer funct3);
    enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm12[4:0], 7'b0100011};
  endfunction
  function automatic [31:0] enc_b(input integer imm13, input integer rs2, input integer rs1, input integer funct3);
    enc_b = {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], funct3[2:0], imm13[4:1], imm13[11], 7'b1100011};
  endfunction

  task automatic uart_wr(input logic [7:0] a, input logic [31:0] d);
    begin
      @(negedge clk);
      uart_addr = a; uart_wdata = d; uart_write = 1'b1; uart_valid = 1'b1;
      @(negedge clk);
      uart_valid = 1'b0; uart_write = 1'b0;
    end
  endtask

  task automatic uart_rd(input logic [7:0] a, output logic [31:0] d);
    begin
      @(negedge clk);
      uart_addr = a; uart_write = 1'b0; uart_valid = 1'b1;
      #1;
      d = uart_rdata;
      @(negedge clk);
      uart_valid = 1'b0;
    end
  endtask

  task automatic wb_write(input logic [31:0] a, input logic [31:0] d);
    begin
      @(negedge clk);
      wb_adr = a; wb_dat_i = d; wb_we = 1'b1; wb_sel = 4'b1111; wb_cyc = 1'b1; wb_stb = 1'b1;
      @(posedge clk); #1;
      while (!wb_ack) begin @(posedge clk); #1; end
      @(negedge clk);
      wb_cyc = 1'b0; wb_stb = 1'b0; wb_we = 1'b0;
    end
  endtask

  task automatic wb_read(input logic [31:0] a, output logic [31:0] d);
    begin
      @(negedge clk);
      wb_adr = a; wb_we = 1'b0; wb_sel = 4'b1111; wb_cyc = 1'b1; wb_stb = 1'b1;
      @(posedge clk); #1;
      while (!wb_ack) begin @(posedge clk); #1; end
      d = wb_dat_o;
      @(negedge clk);
      wb_cyc = 1'b0; wb_stb = 1'b0;
    end
  endtask

  integer i;
  logic [31:0] val;
  logic [31:0] fnv_exp;

  initial begin
    uart_valid = 1'b0; uart_write = 1'b0; uart_addr = 8'd0; uart_wdata = 32'd0;
    for (i = 0; i < 16; i = i + 1) cpu_ram[i] = 32'd0;
    for (i = 0; i < 32; i = i + 1) cpu_rom[i] = 32'h0000_0013;

    cpu_rom[0]  = enc_i(-7, 0, 3'b000, 1, 7'b0010011);
    cpu_rom[1]  = enc_i(3, 0, 3'b000, 2, 7'b0010011);
    cpu_rom[2]  = enc_r(7'b0000001, 2, 1, 3'b100, 3);
    cpu_rom[3]  = enc_s(0, 3, 0, 3'b010);
    cpu_rom[4]  = enc_r(7'b0000001, 2, 1, 3'b110, 4);
    cpu_rom[5]  = enc_s(4, 4, 0, 3'b010);
    cpu_rom[6]  = enc_u(32'h80000, 5, 7'b0110111);
    cpu_rom[7]  = enc_i(2, 0, 3'b000, 6, 7'b0010011);
    cpu_rom[8]  = enc_r(7'b0000001, 6, 5, 3'b101, 7);
    cpu_rom[9]  = enc_s(8, 7, 0, 3'b010);
    cpu_rom[10] = enc_i(-1, 0, 3'b000, 8, 7'b0010011);
    cpu_rom[11] = enc_r(7'b0000001, 8, 5, 3'b100, 9);
    cpu_rom[12] = enc_s(12, 9, 0, 3'b010);
    cpu_rom[13] = enc_r(7'b0000001, 8, 5, 3'b110, 10);
    cpu_rom[14] = enc_s(16, 10, 0, 3'b010);
    cpu_rom[15] = enc_r(7'b0000001, 0, 1, 3'b100, 11);
    cpu_rom[16] = enc_s(20, 11, 0, 3'b010);
    cpu_rom[17] = enc_r(7'b0000001, 2, 5, 3'b010, 12);
    cpu_rom[18] = enc_s(24, 12, 0, 3'b010);
    cpu_rom[19] = enc_r(7'b0000001, 6, 5, 3'b011, 13);
    cpu_rom[20] = enc_s(28, 13, 0, 3'b010);
    cpu_rom[21] = 32'h1050_0073;

    @(negedge clk);
    u_soc.boot_rom[0]  = enc_u(32'h00010, 1, 7'b0110111);
    u_soc.boot_rom[1]  = enc_u(32'h40009, 2, 7'b0110111);
    u_soc.boot_rom[2]  = enc_u(32'h4000a, 3, 7'b0110111);
    u_soc.boot_rom[3]  = enc_u(32'h40006, 4, 7'b0110111);
    u_soc.boot_rom[4]  = enc_u(32'h4000b, 5, 7'b0110111);

    u_soc.boot_rom[5]  = enc_i(255, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[6]  = enc_s(8, 7, 2, 3'b010);
    u_soc.boot_rom[7]  = enc_u(32'h0000f, 7, 7'b0110111);
    u_soc.boot_rom[8]  = enc_i(-256, 7, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[9]  = enc_s(12, 7, 2, 3'b010);
    u_soc.boot_rom[10] = enc_i(165, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[11] = enc_s(4, 7, 2, 3'b010);
    u_soc.boot_rom[12] = 32'h0000_0013;
    u_soc.boot_rom[13] = 32'h0000_0013;
    u_soc.boot_rom[14] = 32'h0000_0013;
    u_soc.boot_rom[15] = enc_i(0, 2, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[16] = enc_s(40, 7, 1, 3'b010);
    u_soc.boot_rom[17] = enc_i(16, 2, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[18] = enc_s(44, 7, 1, 3'b010);

    u_soc.boot_rom[19] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[20] = enc_s(12, 7, 3, 3'b010);
    u_soc.boot_rom[21] = enc_i(195, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[22] = enc_s(4, 7, 3, 3'b010);
    u_soc.boot_rom[23] = enc_i(9, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[24] = enc_s(0, 7, 3, 3'b010);
    u_soc.boot_rom[25] = enc_i(0, 3, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[26] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    u_soc.boot_rom[27] = enc_b(-8, 0, 7, 3'b001);
    u_soc.boot_rom[28] = enc_i(8, 3, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[29] = enc_s(48, 7, 1, 3'b010);

    u_soc.boot_rom[30] = enc_u(32'h12345, 7, 7'b0110111);
    u_soc.boot_rom[31] = enc_i(1656, 7, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[32] = enc_s(4, 7, 3, 3'b010);
    u_soc.boot_rom[33] = enc_i(73, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[34] = enc_s(0, 7, 3, 3'b010);
    u_soc.boot_rom[35] = enc_i(0, 3, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[36] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    u_soc.boot_rom[37] = enc_b(-8, 0, 7, 3'b001);
    u_soc.boot_rom[38] = enc_i(8, 3, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[39] = enc_s(52, 7, 1, 3'b010);

    u_soc.boot_rom[40] = enc_i(77, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[41] = enc_s(0, 7, 1, 3'b010);
    u_soc.boot_rom[42] = enc_i(88, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[43] = enc_s(16, 7, 1, 3'b010);
    u_soc.boot_rom[44] = enc_i(99, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[45] = enc_s(20, 7, 1, 3'b010);

    u_soc.boot_rom[46] = enc_s(0, 1, 4, 3'b010);
    u_soc.boot_rom[47] = enc_i(256, 1, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[48] = enc_s(4, 7, 4, 3'b010);
    u_soc.boot_rom[49] = enc_i(3, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[50] = enc_s(8, 7, 4, 3'b010);

    u_soc.boot_rom[51] = enc_i(16, 1, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[52] = enc_s(16, 7, 4, 3'b010);
    u_soc.boot_rom[53] = enc_i(512, 1, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[54] = enc_s(20, 7, 4, 3'b010);
    u_soc.boot_rom[55] = enc_i(2, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[56] = enc_s(24, 7, 4, 3'b010);

    u_soc.boot_rom[57] = enc_i(17, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[58] = enc_s(12, 7, 4, 3'b010);
    u_soc.boot_rom[59] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[60] = enc_s(28, 7, 4, 3'b010);

    u_soc.boot_rom[61] = enc_i(12, 4, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[62] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    u_soc.boot_rom[63] = enc_b(-8, 0, 7, 3'b001);
    u_soc.boot_rom[64] = enc_i(28, 4, 3'b010, 7, 7'b0000011);
    u_soc.boot_rom[65] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    u_soc.boot_rom[66] = enc_b(-8, 0, 7, 3'b001);

    u_soc.boot_rom[67] = enc_u(32'h12345, 7, 7'b0110111);
    u_soc.boot_rom[68] = enc_i(1656, 7, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[69] = enc_s(252, 7, 1, 3'b010);

    u_soc.boot_rom[70] = enc_i(120, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[71] = enc_s(4, 7, 5, 3'b010);
    u_soc.boot_rom[72] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    u_soc.boot_rom[73] = enc_s(8, 7, 5, 3'b010);
    u_soc.boot_rom[74] = 32'h1050_0073;
    u_soc.boot_rom[75] = 32'hffdff06f;

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (!cpu_sleep && !cpu_trap && cycles < 500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (cpu_trap || !cpu_sleep) failures = failures + 1;
    if ($signed(cpu_ram[0]) != -32'sd2) failures = failures + 1;
    if ($signed(cpu_ram[1]) != -32'sd1) failures = failures + 1;
    if (cpu_ram[2] != 32'h4000_0000) failures = failures + 1;
    if (cpu_ram[3] != 32'h8000_0000) failures = failures + 1;
    if (cpu_ram[4] != 32'd0) failures = failures + 1;
    if ($signed(cpu_ram[5]) != -32'sd1) failures = failures + 1;
    if ($signed(cpu_ram[6]) != -32'sd2) failures = failures + 1;
    if (cpu_ram[7] != 32'd1) failures = failures + 1;

    uart_wr(8'h08, 32'd2);
    uart_wr(8'h00, 32'h4f);
    uart_wr(8'h00, 32'h52);
    uart_wr(8'h00, 32'h58);
    uart_wr(8'h00, 32'h31);
    repeat (200) @(posedge clk);
    uart_rd(8'h00, val); if (val != 32'h4f) failures = failures + 1;
    uart_rd(8'h00, val); if (val != 32'h52) failures = failures + 1;
    uart_rd(8'h00, val); if (val != 32'h58) failures = failures + 1;
    uart_rd(8'h00, val); if (val != 32'h31) failures = failures + 1;

    cycles = 0;
    while (u_soc.u_sram.mem[63] != 32'h1234_5678 && !soc_trap && cycles < 2500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (soc_trap || u_soc.u_sram.mem[63] != 32'h1234_5678) failures = failures + 1;
    if (u_soc.u_sram.mem[10] != 32'h0000_a500) failures = failures + 1;
    if (u_soc.u_sram.mem[11] != 32'h0000_a500) failures = failures + 1;
    if (u_soc.u_sram.mem[12] != 32'h0000_00c3) failures = failures + 1;
    if (u_soc.u_sram.mem[13] != 32'h1234_5678) failures = failures + 1;
    if (u_soc.u_sram.mem[64] != 32'd77 || u_soc.u_sram.mem[65] != 32'd77 || u_soc.u_sram.mem[66] != 32'd77) failures = failures + 1;
    if (u_soc.u_sram.mem[128] != 32'd88 || u_soc.u_sram.mem[129] != 32'd99) failures = failures + 1;

    repeat (20) @(posedge clk);
    wb_read(32'h4000_4038, val);
    if (val == 32'd0) failures = failures + 1;

    repeat (150) @(posedge clk);
    wb_read(32'h4000_b000, val);
    if (!val[2]) failures = failures + 1;

    wb_write(32'h4000_b000, 32'h07);
    fnv_exp = 32'h811c_9dc5;
    for (i = 0; i < 4; i = i + 1) begin
      fnv_exp = (fnv_exp ^ u_soc.boot_rom[i]) * 32'h0100_0193;
    end
    wb_write(32'h4000_2008, fnv_exp);
    wb_write(32'h4000_2000, 32'h01);
    repeat (8) @(posedge clk);
    wb_write(32'h4000_b000, 32'h02);
    if (!soc_boot_release) failures = failures + 1;

    if (failures == 0) $display("PERIPHERALS_TEST_PASS cycles=%0d", cycles);
    else $display("PERIPHERALS_TEST_FAIL %0d cycles=%0d", failures, cycles);
    $finish;
  end
endmodule
