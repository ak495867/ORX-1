module orx1_soc #(
  parameter BOOT_HEX = ""
) (
  input logic clk,
  input logic reset,
  input logic sensor_valid,
  input logic [15:0] sensor_data,
  output logic sensor_result_valid,
  output logic [15:0] sensor_result,
  output logic accelerator_irq,
  output logic boot_release,
  output logic boot_fail,
  output logic core_trap,
  output logic sensor_alert,
  input logic uart_rx,
  output logic uart_tx,
  input logic wb_host_cyc_i,
  input logic wb_host_stb_i,
  input logic wb_host_we_i,
  input logic [3:0] wb_host_sel_i,
  input logic [31:0] wb_host_adr_i,
  input logic [31:0] wb_host_dat_i,
  output logic wb_host_ack_o,
  output logic [31:0] wb_host_dat_o
);
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic [31:0] sram_imem_rdata;
  logic req_valid;
  logic req_ready;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic [31:0] rsp_rdata;
  logic rsp_err;

  logic m0_ack, m0_err;
  logic [31:0] m0_rdata;
  logic m1_ack, m1_err;
  logic [31:0] m1_rdata;
  logic wb_host_err;

  logic [1:0] grant_master;
  logic [10:0] wb_s_cyc;
  logic [10:0] wb_s_stb;
  logic wb_s_we;
  logic [31:0] wb_s_adr;
  logic [31:0] wb_s_dat;
  logic [3:0] wb_s_sel;
  logic [10:0] wb_s_ack;
  logic [10:0] wb_s_err;

  logic [31:0] rom_rdata;
  logic [31:0] sram_rdata;
  logic sram_ack;
  logic [31:0] sensor_csr_rdata;
  logic [31:0] accel_csr_rdata;
  logic [31:0] boot_csr_rdata;
  logic [31:0] uart_csr_rdata;
  logic [31:0] energy_csr_rdata;
  logic [31:0] timer_csr_rdata;
  logic [31:0] dma_csr_rdata;
  logic [31:0] cordic_csr_rdata;
  logic [31:0] irq_csr_rdata;

  logic [31:0] cpu_cycles;
  logic [31:0] cpu_instructions;
  logic [31:0] cpu_loads;
  logic [31:0] cpu_stores;
  logic [31:0] cpu_branches;
  logic [31:0] cpu_bus_requests;
  logic [31:0] cpu_wait_cycles;

  logic sensor_enable;
  logic sensor_clear;
  logic sensor_thresh_en;
  logic [1:0] sensor_depth;
  logic [15:0] sensor_thresh_low;
  logic [15:0] sensor_thresh_high;
  logic sensor_auto_infer;
  logic auto_infer_trigger;
  logic [15:0] sensor_bus_data;
  logic sensor_bus_valid;
  logic sensor_irq;

  logic [31:0] boot_word;
  logic [2:0] boot_addr;
  logic [31:0] boot_rom [0:255];

  logic d_valid;
  logic d_ready;
  logic d_write;
  logic [31:0] d_addr;

  logic uart_irq;
  logic timer_irq;
  logic dma_irq;
  logic cordic_irq;
  logic core_irq;

  logic dma_req_valid;
  logic dma_req_ready;
  logic dma_req_write;
  logic [31:0] dma_req_addr;
  logic [31:0] dma_req_wdata;
  logic [3:0] dma_req_wstrb;
  logic dma_rsp_valid;
  logic [31:0] dma_rsp_rdata;

  integer rom_i;
  initial begin
    for (rom_i = 0; rom_i < 256; rom_i = rom_i + 1) boot_rom[rom_i] = 32'd0;
    if (BOOT_HEX != "") $readmemh(BOOT_HEX, boot_rom);
  end

  assign d_valid = req_valid;
  assign d_ready = req_ready;
  assign d_write = req_write;
  assign d_addr = req_addr;

  assign req_ready = m0_ack | m0_err;
  assign rsp_valid = m0_ack | m0_err;
  assign rsp_rdata = m0_rdata;
  assign rsp_err = m0_err;

  assign dma_req_ready = m1_ack | m1_err;
  assign dma_rsp_valid = m1_ack | m1_err;
  assign dma_rsp_rdata = m1_rdata;

  assign imem_rdata = (imem_addr >= `ORX1_SRAM_BASE && imem_addr <= `ORX1_SRAM_LAST) ? sram_imem_rdata :
                      ((imem_addr <= `ORX1_BOOT_LAST && boot_rom[imem_addr[9:2]] != 32'd0) ? boot_rom[imem_addr[9:2]] : 32'h0000_0013);

  assign rom_rdata = boot_rom[wb_s_adr[9:2]];
  assign wb_s_ack[0] = wb_s_cyc[0] && wb_s_stb[0] && (!wb_s_we || (grant_master == 2'd2));
  assign wb_s_err[0] = wb_s_cyc[0] && wb_s_stb[0] && wb_s_we && (grant_master != 2'd2);
  assign wb_s_ack[1] = sram_ack;
  assign wb_s_err[1] = 1'b0;
  assign wb_s_ack[10:2] = wb_s_cyc[10:2] & wb_s_stb[10:2];
  assign wb_s_err[10:2] = 9'd0;

  assign sensor_bus_valid = sensor_valid | (wb_s_cyc[2] && wb_s_stb[2] && wb_s_we && wb_s_adr[7:0] == 8'h08);
  assign sensor_bus_data = sensor_valid ? sensor_data : wb_s_dat[15:0];
  assign boot_word = boot_rom[boot_addr];
  assign auto_infer_trigger = sensor_auto_infer & sensor_result_valid;

  always_ff @(posedge clk) begin
    if (wb_s_cyc[0] && wb_s_stb[0] && wb_s_we && (grant_master == 2'd2)) begin
      if (wb_s_sel[0]) boot_rom[wb_s_adr[9:2]][7:0]   <= wb_s_dat[7:0];
      if (wb_s_sel[1]) boot_rom[wb_s_adr[9:2]][15:8]  <= wb_s_dat[15:8];
      if (wb_s_sel[2]) boot_rom[wb_s_adr[9:2]][23:16] <= wb_s_dat[23:16];
      if (wb_s_sel[3]) boot_rom[wb_s_adr[9:2]][31:24] <= wb_s_dat[31:24];
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sensor_enable <= 1'b0;
      sensor_clear <= 1'b0;
      sensor_thresh_en <= 1'b0;
      sensor_depth <= 2'b10;
      sensor_thresh_low <= 16'd0;
      sensor_thresh_high <= 16'hffff;
      sensor_auto_infer <= 1'b0;
    end else begin
      sensor_clear <= 1'b0;
      if (wb_s_cyc[2] && wb_s_stb[2] && wb_s_we) begin
        case (wb_s_adr[7:0])
          8'h00: begin
            sensor_enable <= wb_s_dat[0];
            sensor_thresh_en <= wb_s_dat[1];
            sensor_auto_infer <= wb_s_dat[2];
          end
          8'h04: sensor_clear <= wb_s_dat[0];
          8'h10: sensor_depth <= wb_s_dat[1:0];
          8'h14: sensor_thresh_low <= wb_s_dat[15:0];
          8'h18: sensor_thresh_high <= wb_s_dat[15:0];
          default: begin end
        endcase
      end
    end
  end

  always_comb begin
    sensor_csr_rdata = 32'd0;
    case (wb_s_adr[7:0])
      8'h00: sensor_csr_rdata = {29'd0, sensor_auto_infer, sensor_thresh_en, sensor_enable};
      8'h04: sensor_csr_rdata = {31'd0, sensor_irq};
      8'h08: sensor_csr_rdata = {16'd0, sensor_result};
      8'h0c: sensor_csr_rdata = {31'd0, sensor_result_valid};
      8'h10: sensor_csr_rdata = {30'd0, sensor_depth};
      8'h14: sensor_csr_rdata = {16'd0, sensor_thresh_low};
      8'h18: sensor_csr_rdata = {16'd0, sensor_thresh_high};
      8'h1c: sensor_csr_rdata = {31'd0, sensor_alert};
      default: sensor_csr_rdata = 32'd0;
    endcase
  end

  wb_interconnect u_wb_xbar (
    .clk(clk),
    .reset(reset),
    .m0_cyc_i(req_valid),
    .m0_stb_i(req_valid),
    .m0_we_i(req_write),
    .m0_adr_i(req_addr),
    .m0_dat_i(req_wdata),
    .m0_sel_i(req_wstrb),
    .m0_ack_o(m0_ack),
    .m0_dat_o(m0_rdata),
    .m0_err_o(m0_err),
    .m1_cyc_i(dma_req_valid),
    .m1_stb_i(dma_req_valid),
    .m1_we_i(dma_req_write),
    .m1_adr_i(dma_req_addr),
    .m1_dat_i(dma_req_wdata),
    .m1_sel_i(dma_req_wstrb),
    .m1_ack_o(m1_ack),
    .m1_dat_o(m1_rdata),
    .m1_err_o(m1_err),
    .m2_cyc_i(wb_host_cyc_i),
    .m2_stb_i(wb_host_stb_i),
    .m2_we_i(wb_host_we_i),
    .m2_adr_i(wb_host_adr_i),
    .m2_dat_i(wb_host_dat_i),
    .m2_sel_i(wb_host_sel_i),
    .m2_ack_o(wb_host_ack_o),
    .m2_dat_o(wb_host_dat_o),
    .m2_err_o(wb_host_err),
    .grant_master_o(grant_master),
    .s_cyc_o(wb_s_cyc),
    .s_stb_o(wb_s_stb),
    .s_we_o(wb_s_we),
    .s_adr_o(wb_s_adr),
    .s_dat_o(wb_s_dat),
    .s_sel_o(wb_s_sel),
    .s_ack_i(wb_s_ack),
    .s0_dat_i(rom_rdata),
    .s1_dat_i(sram_rdata),
    .s2_dat_i(sensor_csr_rdata),
    .s3_dat_i(accel_csr_rdata),
    .s4_dat_i(boot_csr_rdata),
    .s5_dat_i(uart_csr_rdata),
    .s6_dat_i(energy_csr_rdata),
    .s7_dat_i(timer_csr_rdata),
    .s8_dat_i(dma_csr_rdata),
    .s9_dat_i(cordic_csr_rdata),
    .s10_dat_i(irq_csr_rdata),
    .s_err_i(wb_s_err)
  );

  sram_sp #(
    .WORDS(1024),
    .ADDR_WIDTH(10)
  ) u_sram (
    .clk(clk),
    .reset(reset),
    .en(wb_s_cyc[1] && wb_s_stb[1]),
    .wen(wb_s_we ? wb_s_sel : 4'b0000),
    .addr(wb_s_adr[11:2]),
    .wdata(wb_s_dat),
    .rdata(sram_rdata),
    .ack(sram_ack),
    .imem_addr(imem_addr[11:2]),
    .imem_rdata(sram_imem_rdata)
  );

  rv32i_core core (
    .clk(clk), .reset(reset), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .req_valid(req_valid), .req_ready(req_ready), .req_write(req_write),
    .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err), .trap(core_trap),
    .perf_cycles(cpu_cycles), .perf_instructions(cpu_instructions), .perf_loads(cpu_loads),
    .perf_stores(cpu_stores), .perf_branches(cpu_branches), .perf_bus_requests(cpu_bus_requests),
    .perf_wait_cycles(cpu_wait_cycles), .irq_external(core_irq), .irq_timer(timer_irq)
  );

  sensor_pipeline sensor (
    .clk(clk), .reset(reset), .sample_valid(sensor_bus_valid), .sample_data(sensor_bus_data),
    .cfg_enable(sensor_enable), .cfg_clear(sensor_clear),
    .cfg_depth(sensor_depth), .cfg_thresh_en(sensor_thresh_en),
    .cfg_thresh_low(sensor_thresh_low), .cfg_thresh_high(sensor_thresh_high),
    .result_valid(sensor_result_valid), .result_data(sensor_result),
    .alert(sensor_alert), .irq(sensor_irq)
  );

  neural_accel accelerator (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[3] && wb_s_stb[3]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(accel_csr_rdata),
    .irq(accelerator_irq),
    .auto_infer_trigger(auto_infer_trigger),
    .auto_infer_sample(sensor_result)
  );

  secure_boot boot_controller (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[4] && wb_s_stb[4]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(boot_csr_rdata),
    .boot_release(boot_release), .fail(boot_fail), .boot_addr(boot_addr), .boot_word(boot_word)
  );

  uart_core serial_comm (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[5] && wb_s_stb[5]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(uart_csr_rdata),
    .rx(uart_rx), .tx(uart_tx), .uart_irq(uart_irq)
  );

  timer_mtime sys_timer (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[7] && wb_s_stb[7]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(timer_csr_rdata),
    .timer_irq(timer_irq)
  );

  dma_ctrl sys_dma (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[8] && wb_s_stb[8]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(dma_csr_rdata),
    .dma_req_valid(dma_req_valid), .dma_req_ready(dma_req_ready),
    .dma_req_write(dma_req_write), .dma_req_addr(dma_req_addr),
    .dma_req_wdata(dma_req_wdata), .dma_req_wstrb(dma_req_wstrb),
    .dma_rsp_valid(dma_rsp_valid), .dma_rsp_rdata(dma_rsp_rdata),
    .sensor_event(sensor_result_valid), .dma_irq(dma_irq)
  );

  energy_monitor activity_monitor (
    .clk(clk), .reset(reset), .csr_valid(wb_s_cyc[6] && wb_s_stb[6]), .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]), .csr_wdata(wb_s_dat), .csr_rdata(energy_csr_rdata),
    .sensor_event(sensor_result_valid), .accelerator_event(accelerator_irq),
    .memory_event(|wb_s_ack),
    .cpu_cycles(cpu_cycles), .cpu_instructions(cpu_instructions), .cpu_loads(cpu_loads),
    .cpu_stores(cpu_stores), .cpu_branches(cpu_branches), .cpu_bus_requests(cpu_bus_requests),
    .cpu_wait_cycles(cpu_wait_cycles)
  );

  cordic_engine coproc_cordic (
    .clk(clk),
    .reset(reset),
    .csr_valid(wb_s_cyc[9] && wb_s_stb[9]),
    .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]),
    .csr_wdata(wb_s_dat),
    .csr_rdata(cordic_csr_rdata),
    .cordic_irq(cordic_irq)
  );

  irq_ctrl u_irq_ctrl (
    .clk(clk),
    .reset(reset),
    .csr_valid(wb_s_cyc[10] && wb_s_stb[10]),
    .csr_write(wb_s_we),
    .csr_addr(wb_s_adr[7:0]),
    .csr_wdata(wb_s_dat),
    .csr_rdata(irq_csr_rdata),
    .irq_sources({cordic_irq, dma_irq, uart_irq, sensor_alert, accelerator_irq, sensor_irq}),
    .irq_out(core_irq)
  );
endmodule
