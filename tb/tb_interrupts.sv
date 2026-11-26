`timescale 1ns/1ps
module tb_interrupts;
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
  logic uart_loopback;
  logic wb_host_ack_o;
  logic [31:0] wb_host_dat_o;
  integer failures = 0;
  integer cycles = 0;

  always #5 clk = ~clk;

  orx1_soc dut (
    .clk(clk), .reset(reset), .sensor_valid(sensor_valid), .sensor_data(sensor_data),
    .sensor_result_valid(sensor_result_valid), .sensor_result(sensor_result),
    .accelerator_irq(accelerator_irq), .boot_release(boot_release), .boot_fail(boot_fail),
    .core_trap(core_trap), .sensor_alert(sensor_alert), .uart_rx(uart_loopback), .uart_tx(uart_loopback),
    .wb_host_cyc_i(1'b0), .wb_host_stb_i(1'b0), .wb_host_we_i(1'b0),
    .wb_host_sel_i(4'b0000), .wb_host_adr_i(32'd0), .wb_host_dat_i(32'd0),
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

  function automatic [31:0] enc_csr(input integer csr12, input integer rs1, input integer funct3, input integer rd);
    enc_csr = {csr12[11:0], rs1[4:0], funct3[2:0], rd[4:0], 7'b1110011};
  endfunction

  initial begin
    @(negedge clk);
    dut.boot_rom[0]  = enc_u(32'h00010, 1, 7'b0110111);
    dut.boot_rom[1]  = enc_u(32'h40005, 2, 7'b0110111);
    dut.boot_rom[2]  = enc_u(32'h40003, 3, 7'b0110111);
    dut.boot_rom[3]  = enc_u(32'h40008, 4, 7'b0110111);
    dut.boot_rom[4]  = enc_u(32'h40000, 5, 7'b0110111);
    dut.boot_rom[5]  = enc_u(32'h40001, 6, 7'b0110111);
    dut.boot_rom[6]  = enc_i(256, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[7]  = enc_csr(12'h305, 7, 3'b001, 0);

    dut.boot_rom[8]  = 32'h0000_0073;

    dut.boot_rom[9]  = enc_s(12, 0, 2, 3'b010);
    dut.boot_rom[10] = enc_i(80, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[11] = enc_s(8, 7, 2, 3'b010);
    dut.boot_rom[12] = enc_i(128, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[13] = enc_csr(12'h304, 7, 3'b001, 0);
    dut.boot_rom[14] = enc_i(8, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[15] = enc_csr(12'h300, 7, 3'b001, 0);
    dut.boot_rom[16] = 32'h1050_0073;

    dut.boot_rom[17] = enc_i(4, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[18] = enc_s(8, 7, 3, 3'b010);
    dut.boot_rom[19] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[20] = enc_s(16, 7, 3, 3'b010);
    dut.boot_rom[21] = enc_i(8, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[22] = enc_s(4, 7, 4, 3'b010);
    dut.boot_rom[23] = enc_i(1, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[24] = enc_i(11, 7, 3'b001, 7, 7'b0010011);
    dut.boot_rom[25] = enc_csr(12'h304, 7, 3'b001, 0);
    dut.boot_rom[26] = enc_i(8, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[27] = enc_csr(12'h300, 7, 3'b001, 0);
    dut.boot_rom[28] = enc_i(90, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[29] = enc_s(0, 7, 3, 3'b010);
    dut.boot_rom[30] = 32'h1050_0073;

    dut.boot_rom[31] = enc_u(32'h01010, 7, 7'b0110111);
    dut.boot_rom[32] = enc_i(257, 7, 3'b000, 7, 7'b0010011);
    dut.boot_rom[33] = enc_s(52, 7, 6, 3'b010);
    dut.boot_rom[34] = enc_i(2, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[35] = enc_s(56, 7, 6, 3'b010);
    dut.boot_rom[36] = enc_i(32, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[37] = enc_s(0, 7, 6, 3'b010);
    dut.boot_rom[38] = enc_s(16, 0, 5, 3'b010);
    dut.boot_rom[39] = enc_i(5, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[40] = enc_s(0, 7, 5, 3'b010);
    dut.boot_rom[41] = enc_i(773, 0, 3'b000, 7, 7'b0010011);
    dut.boot_rom[42] = enc_s(8, 7, 5, 3'b010);
    dut.boot_rom[43] = enc_i(0, 6, 3'b010, 7, 7'b0000011);
    dut.boot_rom[44] = enc_i(1, 7, 3'b111, 7, 7'b0010011);
    dut.boot_rom[45] = enc_b(-8, 0, 7, 3'b001);
    dut.boot_rom[46] = enc_i(4, 6, 3'b010, 7, 7'b0000011);
    dut.boot_rom[47] = enc_s(16, 7, 1, 3'b010);
    dut.boot_rom[48] = enc_i(68, 6, 3'b010, 7, 7'b0000011);
    dut.boot_rom[49] = enc_s(20, 7, 1, 3'b010);
    dut.boot_rom[50] = enc_u(32'h12345, 7, 7'b0110111);
    dut.boot_rom[51] = enc_i(1656, 7, 3'b000, 7, 7'b0010011);
    dut.boot_rom[52] = enc_s(252, 7, 1, 3'b010);
    dut.boot_rom[53] = 32'h1050_0073;
    dut.boot_rom[54] = 32'hffdff06f;

    dut.boot_rom[64] = enc_csr(12'h342, 0, 3'b010, 28);
    dut.boot_rom[65] = enc_i(11, 0, 3'b000, 29, 7'b0010011);
    dut.boot_rom[66] = enc_b(28, 29, 28, 3'b000);
    dut.boot_rom[67] = enc_u(32'h80000, 29, 7'b0110111);
    dut.boot_rom[68] = enc_i(7, 29, 3'b000, 29, 7'b0010011);
    dut.boot_rom[69] = enc_b(40, 29, 28, 3'b000);
    dut.boot_rom[70] = enc_i(4, 29, 3'b000, 29, 7'b0010011);
    dut.boot_rom[71] = enc_b(52, 29, 28, 3'b000);
    dut.boot_rom[72] = 32'h3020_0073;

    dut.boot_rom[73] = enc_i(1, 0, 3'b000, 29, 7'b0010011);
    dut.boot_rom[74] = enc_s(0, 29, 1, 3'b010);
    dut.boot_rom[75] = enc_csr(12'h341, 0, 3'b010, 29);
    dut.boot_rom[76] = enc_i(4, 29, 3'b000, 29, 7'b0010011);
    dut.boot_rom[77] = enc_csr(12'h341, 29, 3'b001, 0);
    dut.boot_rom[78] = 32'h3020_0073;

    dut.boot_rom[79] = enc_i(1, 0, 3'b000, 29, 7'b0010011);
    dut.boot_rom[80] = enc_s(4, 29, 1, 3'b010);
    dut.boot_rom[81] = enc_i(-1, 0, 3'b000, 29, 7'b0010011);
    dut.boot_rom[82] = enc_s(8, 29, 2, 3'b010);
    dut.boot_rom[83] = 32'h3020_0073;

    dut.boot_rom[84] = enc_i(8, 4, 3'b010, 29, 7'b0000011);
    dut.boot_rom[85] = enc_s(8, 29, 1, 3'b010);
    dut.boot_rom[86] = enc_i(0, 3, 3'b010, 29, 7'b0000011);
    dut.boot_rom[87] = enc_s(12, 29, 1, 3'b010);
    dut.boot_rom[88] = enc_i(7, 0, 3'b000, 29, 7'b0010011);
    dut.boot_rom[89] = enc_s(12, 29, 3, 3'b010);
    dut.boot_rom[90] = enc_s(4, 0, 4, 3'b010);
    dut.boot_rom[91] = 32'h3020_0073;

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (dut.u_sram.mem[63] != 32'h1234_5678 && !core_trap && cycles < 1500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (core_trap) failures = failures + 1;
    if (dut.u_sram.mem[0] != 32'd1) failures = failures + 1;
    if (dut.u_sram.mem[1] != 32'd1) failures = failures + 1;
    if (dut.u_sram.mem[2] != 32'd8) failures = failures + 1;
    if (dut.u_sram.mem[3] != 32'd90) failures = failures + 1;
    if (dut.u_sram.mem[4] != 32'd8) failures = failures + 1;
    if (dut.u_sram.mem[5] != 32'd10) failures = failures + 1;
    if (dut.u_sram.mem[63] != 32'h1234_5678) failures = failures + 1;

    if (failures == 0) $display("INTERRUPT_TEST_PASS cycles=%0d", cycles);
    else $display("INTERRUPT_TEST_FAIL %0d cycles=%0d", failures, cycles);
    $finish;
  end
endmodule
