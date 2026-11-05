module orx1_soc (
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
  output logic uart_tx
);
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
  logic [31:0] sram [0:1023];
  logic [31:0] sensor_csr_rdata;
  logic [31:0] accel_csr_rdata;
  logic [31:0] boot_csr_rdata;
  logic [31:0] uart_csr_rdata;
  logic [31:0] energy_csr_rdata;
  logic [31:0] timer_csr_rdata;
  logic [31:0] dma_csr_rdata;
  logic [31:0] cordic_csr_rdata;
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
  logic accel_csr_valid;
  logic boot_csr_valid;
  logic uart_csr_valid;
  logic energy_csr_valid;
  logic timer_csr_valid;
  logic dma_csr_valid;
  logic [7:0] accel_csr_addr;
  logic [7:0] boot_csr_addr;
  logic [7:0] uart_csr_addr;
  logic [7:0] energy_csr_addr;
  logic [7:0] timer_csr_addr;
  logic [7:0] dma_csr_addr;
  logic [7:0] cordic_csr_addr;
  logic [31:0] boot_word;
  logic [2:0] boot_addr;
  logic [31:0] boot_rom [0:255];
  logic [9:0] sram_index;
  logic rom_select;
  logic sram_select;
  logic sensor_select;
  logic accel_select;
  logic boot_select;
  logic uart_select;
  logic energy_select;
  logic timer_select;
  logic dma_select;
  logic cordic_select;
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
  logic dma_req_write;
  logic [31:0] dma_req_addr;
  logic [31:0] dma_req_wdata;
  logic [3:0] dma_req_wstrb;

  assign d_valid = req_valid;
  assign d_ready = req_ready;
  assign d_write = req_write;
  assign d_addr = req_addr;
  assign imem_rdata = (imem_addr >= `ORX1_SRAM_BASE && imem_addr <= `ORX1_SRAM_LAST) ? sram[imem_addr[11:2]] : ((imem_addr <= `ORX1_BOOT_LAST && boot_rom[imem_addr[9:2]] != 32'd0) ? boot_rom[imem_addr[9:2]] : 32'h0000_0013);
  assign req_ready = req_valid;
  assign rsp_valid = req_valid && req_ready;
  assign sram_index = req_addr[11:2];
  assign rom_select = req_valid && req_addr >= `ORX1_BOOT_BASE && req_addr <= `ORX1_BOOT_LAST;
  assign sram_select = req_valid && req_addr >= `ORX1_SRAM_BASE && req_addr <= `ORX1_SRAM_LAST;
  assign sensor_select = req_valid && req_addr >= `ORX1_SENSOR_BASE && req_addr < `ORX1_SENSOR_BASE + `ORX1_REGION_SIZE;
  assign accel_select = req_valid && req_addr >= `ORX1_ACCEL_BASE && req_addr < `ORX1_ACCEL_BASE + `ORX1_REGION_SIZE;
  assign boot_select = req_valid && req_addr >= `ORX1_BOOTCTRL_BASE && req_addr < `ORX1_BOOTCTRL_BASE + `ORX1_REGION_SIZE;
  assign uart_select = req_valid && req_addr >= `ORX1_UART_BASE && req_addr < `ORX1_UART_BASE + `ORX1_REGION_SIZE;
  assign energy_select = req_valid && req_addr >= `ORX1_ENERGY_BASE && req_addr < `ORX1_ENERGY_BASE + `ORX1_REGION_SIZE;
  assign timer_select = req_valid && req_addr >= `ORX1_TIMER_BASE && req_addr < `ORX1_TIMER_BASE + `ORX1_REGION_SIZE;
  assign dma_select = req_valid && req_addr >= `ORX1_DMA_BASE && req_addr < `ORX1_DMA_BASE + `ORX1_REGION_SIZE;
  assign cordic_select = req_valid && req_addr >= `ORX1_CORDIC_BASE && req_addr < `ORX1_CORDIC_BASE + `ORX1_REGION_SIZE;
  assign rsp_err = req_valid && !(rom_select || sram_select || sensor_select || accel_select || boot_select || uart_select || energy_select || timer_select || dma_select || cordic_select);
  assign sensor_bus_valid = sensor_valid | (sensor_select && req_write && req_addr[7:0] == 8'h08);
  assign sensor_bus_data = sensor_valid ? sensor_data : req_wdata[15:0];
  assign accel_csr_valid = accel_select;
  assign boot_csr_valid = boot_select;
  assign uart_csr_valid = uart_select;
  assign energy_csr_valid = energy_select;
  assign timer_csr_valid = timer_select;
  assign dma_csr_valid = dma_select;
  assign cordic_csr_valid = cordic_select;
  assign accel_csr_addr = req_addr[7:0];
  assign boot_csr_addr = req_addr[7:0];
  assign uart_csr_addr = req_addr[7:0];
  assign energy_csr_addr = req_addr[7:0];
  assign timer_csr_addr = req_addr[7:0];
  assign dma_csr_addr = req_addr[7:0];
  assign cordic_csr_addr = req_addr[7:0];
  assign boot_word = boot_rom[boot_addr];
  assign auto_infer_trigger = sensor_auto_infer & sensor_result_valid;
  assign core_irq = sensor_irq | accelerator_irq | sensor_alert | uart_irq | dma_irq | cordic_irq;

  always_comb begin
    rsp_rdata = 32'd0;
    if (rom_select) rsp_rdata = boot_rom[req_addr[9:2]];
    else if (sram_select) rsp_rdata = sram[sram_index];
    else if (sensor_select) rsp_rdata = sensor_csr_rdata;
    else if (accel_select) rsp_rdata = accel_csr_rdata;
    else if (boot_select) rsp_rdata = boot_csr_rdata;
    else if (uart_select) rsp_rdata = uart_csr_rdata;
    else if (energy_select) rsp_rdata = energy_csr_rdata;
    else if (timer_select) rsp_rdata = timer_csr_rdata;
    else if (dma_select) rsp_rdata = dma_csr_rdata;
    else if (cordic_select) rsp_rdata = cordic_csr_rdata;
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
      if (sensor_select && req_write) begin
        case (req_addr[7:0])
          8'h00: begin
            sensor_enable <= req_wdata[0];
            sensor_thresh_en <= req_wdata[1];
            sensor_auto_infer <= req_wdata[2];
          end
          8'h04: sensor_clear <= req_wdata[0];
          8'h10: sensor_depth <= req_wdata[1:0];
          8'h14: sensor_thresh_low <= req_wdata[15:0];
          8'h18: sensor_thresh_high <= req_wdata[15:0];
          default: begin end
        endcase
      end
      if (sram_select && req_write) begin
        if (req_wstrb[0]) sram[sram_index][7:0] <= req_wdata[7:0];
        if (req_wstrb[1]) sram[sram_index][15:8] <= req_wdata[15:8];
        if (req_wstrb[2]) sram[sram_index][23:16] <= req_wdata[23:16];
        if (req_wstrb[3]) sram[sram_index][31:24] <= req_wdata[31:24];
      end
    end
  end

  always_comb begin
    sensor_csr_rdata = 32'd0;
    case (req_addr[7:0])
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
    .clk(clk), .reset(reset), .csr_valid(accel_csr_valid), .csr_write(req_write),
    .csr_addr(accel_csr_addr), .csr_wdata(req_wdata), .csr_rdata(accel_csr_rdata),
    .irq(accelerator_irq),
    .auto_infer_trigger(auto_infer_trigger),
    .auto_infer_sample(sensor_result)
  );

  secure_boot boot_controller (
    .clk(clk), .reset(reset), .csr_valid(boot_csr_valid), .csr_write(req_write),
    .csr_addr(boot_csr_addr), .csr_wdata(req_wdata), .csr_rdata(boot_csr_rdata),
    .boot_release(boot_release), .fail(boot_fail), .boot_addr(boot_addr), .boot_word(boot_word)
  );

  uart_core serial_comm (
    .clk(clk), .reset(reset), .csr_valid(uart_csr_valid), .csr_write(req_write),
    .csr_addr(uart_csr_addr), .csr_wdata(req_wdata), .csr_rdata(uart_csr_rdata),
    .rx(uart_rx), .tx(uart_tx), .uart_irq(uart_irq)
  );

  timer_mtime sys_timer (
    .clk(clk), .reset(reset), .csr_valid(timer_csr_valid), .csr_write(req_write),
    .csr_addr(timer_csr_addr), .csr_wdata(req_wdata), .csr_rdata(timer_csr_rdata),
    .timer_irq(timer_irq)
  );

  dma_ctrl sys_dma (
    .clk(clk), .reset(reset), .csr_valid(dma_csr_valid), .csr_write(req_write),
    .csr_addr(dma_csr_addr), .csr_wdata(req_wdata), .csr_rdata(dma_csr_rdata),
    .dma_req_valid(dma_req_valid), .dma_req_ready(1'b1),
    .dma_req_write(dma_req_write), .dma_req_addr(dma_req_addr),
    .dma_req_wdata(dma_req_wdata), .dma_req_wstrb(dma_req_wstrb),
    .dma_rsp_valid(dma_req_valid), .dma_rsp_rdata(32'd0),
    .sensor_event(sensor_result_valid), .dma_irq(dma_irq)
  );

  energy_monitor activity_monitor (
    .clk(clk), .reset(reset), .csr_valid(energy_csr_valid), .csr_write(req_write),
    .csr_addr(energy_csr_addr), .csr_wdata(req_wdata), .csr_rdata(energy_csr_rdata),
    .sensor_event(sensor_result_valid), .accelerator_event(accelerator_irq), .memory_event(req_valid),
    .cpu_cycles(cpu_cycles), .cpu_instructions(cpu_instructions), .cpu_loads(cpu_loads),
    .cpu_stores(cpu_stores), .cpu_branches(cpu_branches), .cpu_bus_requests(cpu_bus_requests),
    .cpu_wait_cycles(cpu_wait_cycles)
  );

  cordic_engine coproc_cordic (
    .clk(clk),
    .reset(reset),
    .csr_valid(cordic_csr_valid),
    .csr_write(req_write),
    .csr_addr(cordic_csr_addr),
    .csr_wdata(req_wdata),
    .csr_rdata(cordic_csr_rdata),
    .cordic_irq(cordic_irq)
  );
endmodule
