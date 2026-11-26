`timescale 1ns/1ps
module tb_firmware;
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
  logic sensor_alert;
  logic uart_tx;
  logic wb_host_cyc_i = 1'b0;
  logic wb_host_stb_i = 1'b0;
  logic wb_host_we_i = 1'b0;
  logic [3:0] wb_host_sel_i = 4'b0000;
  logic [31:0] wb_host_adr_i = 32'd0;
  logic [31:0] wb_host_dat_i = 32'd0;
  logic wb_host_ack_o;
  logic [31:0] wb_host_dat_o;
  integer failures = 0;
  integer cycles = 0;

  always #5 clk = ~clk;

  orx1_soc dut (
    .clk(clk), .reset(reset), .sensor_valid(sensor_valid), .sensor_data(sensor_data),
    .sensor_result_valid(sensor_result_valid), .sensor_result(sensor_result),
    .accelerator_irq(accelerator_irq), .boot_release(boot_release), .boot_fail(boot_fail),
    .core_trap(core_trap), .sensor_alert(sensor_alert), .uart_rx(1'b1), .uart_tx(uart_tx),
    .wb_host_cyc_i(wb_host_cyc_i), .wb_host_stb_i(wb_host_stb_i),
    .wb_host_we_i(wb_host_we_i), .wb_host_sel_i(wb_host_sel_i),
    .wb_host_adr_i(wb_host_adr_i), .wb_host_dat_i(wb_host_dat_i),
    .wb_host_ack_o(wb_host_ack_o), .wb_host_dat_o(wb_host_dat_o)
  );

  function automatic [31:0] enc_u(input integer imm20, input integer rd, input integer opcode);
    enc_u = {imm20[19:0], rd[4:0], opcode[6:0]};
  endfunction

  function automatic [31:0] enc_i(input integer imm12, input integer rs1, input integer funct3, input integer rd, input integer opcode);
    enc_i = {imm12[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
  endfunction

  function automatic [31:0] enc_s(input integer imm12, input integer rs2, input integer rs1, input integer funct3);
    enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm12[4:0], 7'b0100011};
  endfunction

  function automatic [31:0] enc_b(input integer imm13, input integer rs2, input integer rs1, input integer funct3);
    enc_b = {imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], funct3[2:0], imm13[4:1], imm13[11], 7'b1100011};
  endfunction

  task automatic wb_read(input logic [31:0] addr, output logic [31:0] rdata);
    begin
      @(negedge clk);
      wb_host_adr_i = addr;
      wb_host_we_i = 1'b0;
      wb_host_sel_i = 4'b1111;
      wb_host_cyc_i = 1'b1;
      wb_host_stb_i = 1'b1;
      @(posedge clk);
      #1;
      while (!wb_host_ack_o) begin
        @(posedge clk);
        #1;
      end
      rdata = wb_host_dat_o;
      @(negedge clk);
      wb_host_cyc_i = 1'b0;
      wb_host_stb_i = 1'b0;
    end
  endtask

  logic [31:0] host_val;

  initial begin
    dut.boot_rom[0]  = enc_u(32'h00010, 1, 7'b0110111);
    dut.boot_rom[1]  = enc_u(32'h40006, 2, 7'b0110111);
    dut.boot_rom[2]  = enc_u(32'h40001, 3, 7'b0110111);
    dut.boot_rom[3]  = enc_u(32'h40007, 4, 7'b0110111);
    dut.boot_rom[4]  = enc_u(32'h40003, 5, 7'b0110111);
    dut.boot_rom[5]  = enc_u(32'h40004, 6, 7'b0110111);

    dut.boot_rom[6]  = enc_i(111, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[7]  = enc_s(0, 7, 1, 3'b010);
    dut.boot_rom[8]  = enc_i(222, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[9]  = enc_s(4, 7, 1, 3'b010);

    dut.boot_rom[10] = enc_s(0, 1, 2, 3'b010);
    dut.boot_rom[11] = enc_i(64, 1, 3'b000, 7, 7'b0010011);
    dut.boot_rom[12] = enc_s(4, 7, 2, 3'b010);
    dut.boot_rom[13] = enc_i(2, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[14] = enc_s(8, 7, 2, 3'b010);
    dut.boot_rom[15] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[16] = enc_s(12, 7, 2, 3'b010);
    dut.boot_rom[17] = enc_i(12, 2, 3'b010, 7, 7'b0000011);
    dut.boot_rom[18] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    dut.boot_rom[19] = enc_b(-8, 0, 7, 3'b001);

    dut.boot_rom[20] = enc_u(32'h04030, 7, 7'b0110111);
    dut.boot_rom[21] = enc_i(513, 7, 3'b000, 7, 7'b0010011);
    dut.boot_rom[22] = enc_s(48, 7, 3, 3'b010);
    dut.boot_rom[23] = enc_u(32'h01010, 7, 7'b0110111);
    dut.boot_rom[24] = enc_i(257, 7, 3'b000, 7, 7'b0010011);
    dut.boot_rom[25] = enc_s(52, 7, 3, 3'b010);
    dut.boot_rom[26] = enc_i(-1, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[27] = enc_s(56, 7, 3, 3'b010);
    dut.boot_rom[28] = enc_i(5, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[29] = enc_s(8, 7, 3, 3'b010);
    dut.boot_rom[30] = enc_i(2, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[31] = enc_s(96, 7, 3, 3'b010);
    dut.boot_rom[32] = enc_s(12, 0, 3, 3'b010);
    dut.boot_rom[33] = enc_i(57, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[34] = enc_s(0, 7, 3, 3'b010);
    dut.boot_rom[35] = enc_i(0, 3, 3'b010, 7, 7'b0000011);
    dut.boot_rom[36] = enc_i(1, 7, 3'b111, 7, 7'b0010011);
    dut.boot_rom[37] = enc_b(-8, 0, 7, 3'b001);
    dut.boot_rom[38] = enc_i(4, 3, 3'b010, 7, 7'b0000011);
    dut.boot_rom[39] = enc_s(128, 7, 1, 3'b010);
    dut.boot_rom[40] = enc_i(68, 3, 3'b010, 7, 7'b0000011);
    dut.boot_rom[41] = enc_s(132, 7, 1, 3'b010);

    dut.boot_rom[42] = enc_i(300, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[43] = enc_s(4, 7, 4, 3'b010);
    dut.boot_rom[44] = enc_i(400, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[45] = enc_s(8, 7, 4, 3'b010);
    dut.boot_rom[46] = enc_s(12, 0, 4, 3'b010);
    dut.boot_rom[47] = enc_i(4, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[48] = enc_s(0, 7, 4, 3'b010);
    dut.boot_rom[49] = enc_i(0, 4, 3'b010, 7, 7'b0000011);
    dut.boot_rom[50] = enc_i(2, 7, 3'b111, 7, 7'b0010011);
    dut.boot_rom[51] = enc_b(-8, 0, 7, 3'b001);
    dut.boot_rom[52] = enc_i(16, 4, 3'b010, 7, 7'b0000011);
    dut.boot_rom[53] = enc_s(136, 7, 1, 3'b010);

    dut.boot_rom[54] = enc_i(79, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[55] = enc_s(0, 7, 5, 3'b010);

    dut.boot_rom[56] = enc_i(16, 6, 3'b010, 7, 7'b0000011);
    dut.boot_rom[57] = enc_s(140, 7, 1, 3'b010);

    dut.boot_rom[58] = enc_u(32'h12345, 7, 7'b0110111);
    dut.boot_rom[59] = enc_i(1656, 7, 3'b000, 7, 7'b0010011);
    dut.boot_rom[60] = enc_s(252, 7, 1, 3'b010);
    dut.boot_rom[61] = 32'h1050_0073;
    dut.boot_rom[62] = 32'hffdff06f;

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (dut.u_sram.mem[63] != 32'h1234_5678 && !core_trap && cycles < 1000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (core_trap) failures = failures + 1;
    if (dut.u_sram.mem[16] != 32'd111) failures = failures + 1;
    if (dut.u_sram.mem[17] != 32'd222) failures = failures + 1;
    if (dut.u_sram.mem[32] != 32'd15) failures = failures + 1;
    if (dut.u_sram.mem[33] != 32'd0) failures = failures + 1;
    if (dut.u_sram.mem[34] < 32'd495 || dut.u_sram.mem[34] > 32'd505) failures = failures + 1;
    if (dut.u_sram.mem[35] == 32'd0) failures = failures + 1;

    wb_read(32'h0001_00fc, host_val);
    if (host_val != 32'h1234_5678) failures = failures + 1;

    if (failures == 0) $display("FIRMWARE_TEST_PASS cycles=%0d", cycles);
    else $display("FIRMWARE_TEST_FAIL %0d cycles=%0d", failures, cycles);
    $finish;
  end
endmodule
