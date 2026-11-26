`timescale 1ns/1ps
module tb_riscv_compliance;
  logic clk = 1'b0;
  logic reset = 1'b1;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic req_valid;
  logic req_ready;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic [31:0] rsp_rdata;
  logic rsp_err;
  logic trap;
  logic core_sleep;
  logic [31:0] perf_cycles;
  logic [31:0] perf_instructions;
  logic [31:0] perf_loads;
  logic [31:0] perf_stores;
  logic [31:0] perf_branches;
  logic [31:0] perf_bus_requests;
  logic [31:0] perf_wait_cycles;

  logic [31:0] ram [0:4095];
  integer cycles = 0;
  integer test_passed = 0;
  integer test_done = 0;
  integer has_ext_hex = 0;
  integer failures = 0;
  integer pc_w = 0;
  string test_hex_file;
  string test_sig_file;

  always #5 clk = ~clk;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign rsp_err = 1'b0;

  assign imem_rdata = ram[imem_addr[13:2]];
  assign rsp_rdata = ram[req_addr[13:2]];

  always_ff @(posedge clk) begin
    if (req_valid && req_ready && req_write) begin
      if (req_wstrb[0]) ram[req_addr[13:2]][7:0] <= req_wdata[7:0];
      if (req_wstrb[1]) ram[req_addr[13:2]][15:8] <= req_wdata[15:8];
      if (req_wstrb[2]) ram[req_addr[13:2]][23:16] <= req_wdata[23:16];
      if (req_wstrb[3]) ram[req_addr[13:2]][31:24] <= req_wdata[31:24];
    end
  end

  rv32i_core dut (
    .clk(clk),
    .reset(reset),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_write(req_write),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid),
    .rsp_rdata(rsp_rdata),
    .rsp_err(rsp_err),
    .trap(trap),
    .core_sleep(core_sleep),
    .perf_cycles(perf_cycles),
    .perf_instructions(perf_instructions),
    .perf_loads(perf_loads),
    .perf_stores(perf_stores),
    .perf_branches(perf_branches),
    .perf_bus_requests(perf_bus_requests),
    .perf_wait_cycles(perf_wait_cycles),
    .irq_external(1'b0),
    .irq_timer(1'b0)
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

  task automatic emit(input logic [31:0] inst);
    begin
      ram[pc_w] = inst;
      pc_w = pc_w + 1;
    end
  endtask

  task automatic check_slot(input integer idx, input logic [31:0] expected, input string label);
    begin
      if (ram[idx] !== expected) begin
        $display("COMPLIANCE_MISMATCH %s idx=%0d got=0x%08x exp=0x%08x", label, idx, ram[idx], expected);
        failures = failures + 1;
      end
    end
  endtask

  integer l_jal, l_jalr;

  initial begin
    integer fd;
    for (int i = 0; i < 4096; i = i + 1) ram[i] = 32'h0000_0013;

    if ($value$plusargs("HEX=%s", test_hex_file)) begin
      has_ext_hex = 1;
      $readmemh(test_hex_file, ram);
    end else begin
      pc_w = 512;
      emit(enc_csr(12'h342, 0, 3'b010, 28));
      emit(enc_i(2, 27, 3'b001, 29, 7'b0010011));
      emit(enc_r(7'b0000000, 29, 26, 3'b000, 29));
      emit(enc_s(0, 28, 29, 3'b010));
      emit(enc_i(1, 27, 3'b000, 27, 7'b0010011));
      emit(enc_csr(12'h341, 0, 3'b010, 29));
      emit(enc_i(4, 29, 3'b000, 29, 7'b0010011));
      emit(enc_csr(12'h341, 29, 3'b001, 0));
      emit(32'h3020_0073);

      pc_w = 0;
      emit(enc_i(32'h400, 0, 3'b000, 1, 7'b0010011));
      emit(enc_i(32'h600, 0, 3'b000, 2, 7'b0010011));
      emit(enc_i(32'h500, 0, 3'b000, 26, 7'b0010011));
      emit(enc_i(0, 0, 3'b000, 27, 7'b0010011));
      emit(enc_u(32'h00000, 3, 7'b0110111));
      emit(enc_i(32'h800, 0, 3'b000, 3, 7'b0010011));
      emit(enc_u(32'h00001, 3, 7'b0110111));
      emit(enc_i(-32'sd2048, 3, 3'b000, 3, 7'b0010011));
      emit(enc_csr(12'h305, 3, 3'b001, 0));

      emit(enc_u(32'h12345, 4, 7'b0110111));
      emit(enc_i(32'h678, 4, 3'b000, 4, 7'b0010011));
      emit(enc_s(0, 4, 1, 3'b010));
      emit(enc_u(32'h00000, 5, 7'b0010111));
      emit(enc_s(4, 5, 1, 3'b010));

      l_jal = pc_w;
      emit(enc_j(8, 6));
      emit(enc_i(99, 0, 3'b000, 6, 7'b0010011));
      emit(enc_r(7'b0000000, 6, 0, 3'b000, 7));
      emit(enc_i(21, 6, 3'b000, 8, 7'b0010011));
      l_jalr = pc_w;
      emit(enc_i(0, 8, 3'b000, 9, 7'b1100111));
      emit(enc_i(77, 0, 3'b000, 7, 7'b0010011));
      emit(enc_s(8, 7, 1, 3'b010));
      emit(enc_s(12, 9, 1, 3'b010));

      emit(enc_i(0, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(-5, 0, 3'b000, 11, 7'b0010011));
      emit(enc_i(3, 0, 3'b000, 12, 7'b0010011));
      emit(enc_b(8, 12, 12, 3'b000)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(1, 10, 3'b000, 10, 7'b0010011));
      emit(enc_b(8, 12, 11, 3'b001)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(2, 10, 3'b000, 10, 7'b0010011));
      emit(enc_b(8, 12, 11, 3'b100)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(4, 10, 3'b000, 10, 7'b0010011));
      emit(enc_b(8, 11, 12, 3'b101)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(8, 10, 3'b000, 10, 7'b0010011));
      emit(enc_b(8, 11, 12, 3'b110)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(16, 10, 3'b000, 10, 7'b0010011));
      emit(enc_b(8, 12, 11, 3'b111)); emit(enc_i(100, 0, 3'b000, 10, 7'b0010011));
      emit(enc_i(32, 10, 3'b000, 10, 7'b0010011));
      emit(enc_s(16, 10, 1, 3'b010));

      emit(enc_i(-1, 0, 3'b000, 11, 7'b0010011));
      emit(enc_i(0, 11, 3'b010, 12, 7'b0010011));
      emit(enc_i(0, 11, 3'b011, 13, 7'b0010011));
      emit(enc_r(7'b0000000, 11, 0, 3'b011, 14));
      emit(enc_r(7'b0000000, 0, 11, 3'b010, 15));
      emit(enc_u(32'h80000, 16, 7'b0110111));
      emit(enc_i(4, 16, 3'b000, 16, 7'b0010011));
      emit(enc_i({7'b0000000, 5'd1}, 16, 3'b101, 17, 7'b0010011));
      emit(enc_i({7'b0100000, 5'd1}, 16, 3'b101, 18, 7'b0010011));
      emit(enc_i(1, 0, 3'b000, 19, 7'b0010011));
      emit(enc_r(7'b0100000, 19, 16, 3'b101, 20));
      emit(enc_i(123, 0, 3'b000, 0, 7'b0010011));
      emit(enc_r(7'b0000000, 0, 0, 3'b000, 21));
      emit(enc_s(20, 12, 1, 3'b010));
      emit(enc_s(24, 13, 1, 3'b010));
      emit(enc_s(28, 14, 1, 3'b010));
      emit(enc_s(32, 15, 1, 3'b010));
      emit(enc_s(36, 17, 1, 3'b010));
      emit(enc_s(40, 18, 1, 3'b010));
      emit(enc_s(44, 20, 1, 3'b010));
      emit(enc_s(48, 21, 1, 3'b010));

      emit(enc_u(32'h89abd, 11, 7'b0110111));
      emit(enc_i(-32'sd529, 11, 3'b000, 11, 7'b0010011));
      emit(enc_s(0, 11, 2, 3'b010));
      emit(enc_i(1, 2, 3'b000, 12, 7'b0000011));
      emit(enc_i(1, 2, 3'b100, 13, 7'b0000011));
      emit(enc_i(2, 2, 3'b001, 14, 7'b0000011));
      emit(enc_i(2, 2, 3'b101, 15, 7'b0000011));
      emit(enc_i(32'h55, 0, 3'b000, 16, 7'b0010011));
      emit(enc_s(1, 16, 2, 3'b000));
      emit(enc_i(32'h123, 0, 3'b000, 16, 7'b0010011));
      emit(enc_s(2, 16, 2, 3'b001));
      emit(enc_i(0, 2, 3'b010, 17, 7'b0000011));
      emit(enc_s(52, 12, 1, 3'b010));
      emit(enc_s(56, 13, 1, 3'b010));
      emit(enc_s(60, 14, 1, 3'b010));
      emit(enc_s(64, 15, 1, 3'b010));
      emit(enc_s(68, 17, 1, 3'b010));

      emit(enc_i(-7, 0, 3'b000, 11, 7'b0010011));
      emit(enc_i(6, 0, 3'b000, 12, 7'b0010011));
      emit(enc_r(7'b0000001, 12, 11, 3'b000, 13));
      emit(enc_u(32'h80000, 14, 7'b0110111));
      emit(enc_i(-2, 0, 3'b000, 15, 7'b0010011));
      emit(enc_r(7'b0000001, 14, 15, 3'b001, 16));
      emit(enc_r(7'b0000001, 14, 15, 3'b010, 17));
      emit(enc_r(7'b0000001, 14, 14, 3'b011, 18));
      emit(enc_i(-45, 0, 3'b000, 19, 7'b0010011));
      emit(enc_i(7, 0, 3'b000, 20, 7'b0010011));
      emit(enc_r(7'b0000001, 20, 19, 3'b100, 21));
      emit(enc_r(7'b0000001, 20, 19, 3'b110, 22));
      emit(enc_r(7'b0000001, 20, 19, 3'b101, 23));
      emit(enc_r(7'b0000001, 20, 19, 3'b111, 24));
      emit(enc_i(-1, 0, 3'b000, 25, 7'b0010011));
      emit(enc_r(7'b0000001, 25, 14, 3'b100, 4));
      emit(enc_r(7'b0000001, 25, 14, 3'b110, 5));
      emit(enc_r(7'b0000001, 0, 19, 3'b100, 6));
      emit(enc_r(7'b0000001, 0, 19, 3'b110, 7));
      emit(enc_s(72, 13, 1, 3'b010));
      emit(enc_s(76, 16, 1, 3'b010));
      emit(enc_s(80, 17, 1, 3'b010));
      emit(enc_s(84, 18, 1, 3'b010));
      emit(enc_s(88, 21, 1, 3'b010));
      emit(enc_s(92, 22, 1, 3'b010));
      emit(enc_s(96, 23, 1, 3'b010));
      emit(enc_s(100, 24, 1, 3'b010));
      emit(enc_s(104, 4, 1, 3'b010));
      emit(enc_s(108, 5, 1, 3'b010));
      emit(enc_s(112, 6, 1, 3'b010));
      emit(enc_s(116, 7, 1, 3'b010));

      emit(32'h0ff0_000f);
      emit(enc_csr(12'h301, 0, 3'b010, 11));
      emit(enc_csr(12'hf14, 0, 3'b010, 12));
      emit(enc_csr(12'h342, 15, 3'b101, 0));
      emit(enc_csr(12'h342, 3, 3'b110, 0));
      emit(enc_csr(12'h342, 2, 3'b111, 13));
      emit(enc_csr(12'h342, 0, 3'b010, 14));
      emit(enc_csr(12'hb00, 0, 3'b010, 15));
      emit(enc_csr(12'hb02, 0, 3'b010, 16));
      emit(enc_s(120, 11, 1, 3'b010));
      emit(enc_s(124, 12, 1, 3'b010));
      emit(enc_s(128, 13, 1, 3'b010));
      emit(enc_s(132, 14, 1, 3'b010));
      emit(enc_s(136, 15, 1, 3'b010));
      emit(enc_s(140, 16, 1, 3'b010));

      emit(32'h0000_0073);
      emit(32'h0010_0073);
      emit(32'hffff_ffff);
      emit(enc_csr(12'hf14, 1, 3'b101, 0));
      emit(enc_i(1, 2, 3'b010, 11, 7'b0000011));
      emit(enc_s(2, 11, 2, 3'b010));
      emit(enc_s(144, 27, 1, 3'b010));

      emit(enc_i(1, 0, 3'b000, 11, 7'b0010011));
      emit(enc_u(32'h00011, 12, 7'b0110111));
      emit(enc_s(0, 11, 12, 3'b010));
      emit(enc_j(0, 0));
    end

    repeat (3) @(negedge clk);
    reset = 1'b0;

    while (cycles < 5000 && !trap && !test_done) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (req_valid && req_write && req_addr == 32'h0001_1000) begin
        test_done = 1;
        if (req_wdata == 32'd1) begin
          test_passed = 1;
        end else begin
          test_passed = 0;
        end
      end
    end

    if (!has_ext_hex) begin
      if (trap || !test_passed) failures = failures + 1;
      check_slot(256, 32'h1234_5678, "lui_addi");
      check_slot(257, 32'h0000_0030, "auipc");
      check_slot(258, (l_jal + 1) * 4, "jal_link");
      check_slot(259, (l_jalr + 1) * 4, "jalr_link");
      check_slot(260, 32'd63, "all_6_branches");
      check_slot(261, 32'd1, "slti_neg");
      check_slot(262, 32'd0, "sltiu_neg");
      check_slot(263, 32'd1, "sltu_u");
      check_slot(264, 32'd1, "slt_neg");
      check_slot(265, 32'h4000_0002, "srli");
      check_slot(266, 32'hc000_0002, "srai");
      check_slot(267, 32'hc000_0002, "sra");
      check_slot(268, 32'd0, "x0_zero");
      check_slot(269, 32'hffff_ffcd, "lb_neg");
      check_slot(270, 32'h0000_00cd, "lbu");
      check_slot(271, 32'hffff_89ab, "lh_off2");
      check_slot(272, 32'h0000_89ab, "lhu_off2");
      check_slot(273, 32'h0123_55ef, "sb_sh_lw");
      check_slot(274, -32'sd42, "mul");
      check_slot(275, 32'h0000_0001, "mulh_signed");
      check_slot(276, 32'hffff_ffff, "mulhsu");
      check_slot(277, 32'h4000_0000, "mulhu");
      check_slot(278, -32'sd6, "div_neg");
      check_slot(279, -32'sd3, "rem_neg");
      check_slot(280, 32'd613566750, "divu");
      check_slot(281, 32'd1, "remu");
      check_slot(282, 32'h8000_0000, "div_ovf");
      check_slot(283, 32'd0, "rem_ovf");
      check_slot(284, 32'hffff_ffff, "div_zero");
      check_slot(285, -32'sd45, "rem_zero");
      check_slot(286, 32'h4000_1100, "misa_rv32im");
      check_slot(287, 32'd0, "mhartid");
      check_slot(288, 32'd15, "csrrwi_csrrsi");
      check_slot(289, 32'd13, "csrrci");
      if (ram[290] == 32'd0 || ram[291] == 32'd0) failures = failures + 1;
      check_slot(292, 32'd6, "trap_count");
      check_slot(320, 32'd11, "mcause_ecall");
      check_slot(321, 32'd3, "mcause_ebreak");
      check_slot(322, 32'd2, "mcause_illegal");
      check_slot(323, 32'd2, "mcause_ro_csr");
      check_slot(324, 32'd4, "mcause_mis_lw");
      check_slot(325, 32'd6, "mcause_mis_sw");
      if (failures != 0) test_passed = 0;
    end

    if ($value$plusargs("SIG=%s", test_sig_file)) begin
      fd = $fopen(test_sig_file, "w");
      if (fd != 0) begin
        for (int i = 0; i < 64; i = i + 1) begin
          $fdisplay(fd, "%08x", ram[256 + i]);
        end
        $fclose(fd);
      end
    end

    if (test_passed && failures == 0) begin
      $display("RISCV_COMPLIANCE_PASS cycles=%0d checks=43", cycles);
    end else begin
      $display("RISCV_COMPLIANCE_FAIL cycles=%0d trap=%0d done=%0d fail=%0d", cycles, trap, test_done, failures);
    end
    $finish;
  end
endmodule
