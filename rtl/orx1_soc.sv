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
  output logic core_trap
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
  logic [31:0] energy_csr_rdata;
  logic [31:0] cpu_cycles;
  logic [31:0] cpu_instructions;
  logic [31:0] cpu_loads;
  logic [31:0] cpu_stores;
  logic [31:0] cpu_branches;
  logic [31:0] cpu_bus_requests;
  logic [31:0] cpu_wait_cycles;
  logic sensor_enable;
  logic sensor_clear;
  logic [15:0] sensor_bus_data;
  logic sensor_bus_valid;
  logic sensor_irq;
  logic accel_csr_valid;
  logic boot_csr_valid;
  logic energy_csr_valid;
  logic [7:0] accel_csr_addr;
  logic [7:0] boot_csr_addr;
  logic [7:0] energy_csr_addr;
  logic [31:0] boot_word;
  logic [9:0] sram_index;
  logic rom_select;
  logic sram_select;
  logic sensor_select;
  logic accel_select;
  logic boot_select;
  logic uart_select;
  logic energy_select;
  logic d_valid;
  logic d_ready;
  logic d_write;
  logic [31:0] d_addr;

  assign d_valid = req_valid;
  assign d_ready = req_ready;
  assign d_write = req_write;
  assign d_addr = req_addr;
  assign imem_rdata = 32'd0;
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
  assign rsp_err = req_valid && !(rom_select || sram_select || sensor_select || accel_select || boot_select || uart_select || energy_select);
  assign sensor_bus_valid = sensor_valid | (sensor_select && req_write && req_addr[7:0] == 8'h08);
  assign sensor_bus_data = sensor_valid ? sensor_data : req_wdata[15:0];
  assign accel_csr_valid = accel_select;
  assign boot_csr_valid = boot_select;
  assign energy_csr_valid = energy_select;
  assign accel_csr_addr = req_addr[7:0];
  assign boot_csr_addr = req_addr[7:0];
  assign energy_csr_addr = req_addr[7:0];
  assign boot_word = 32'd0;

  always_comb begin
    rsp_rdata = 32'd0;
    if (rom_select) rsp_rdata = 32'd0;
    else if (sram_select) rsp_rdata = sram[sram_index];
    else if (sensor_select) rsp_rdata = sensor_csr_rdata;
    else if (accel_select) rsp_rdata = accel_csr_rdata;
    else if (boot_select) rsp_rdata = boot_csr_rdata;
    else if (energy_select) rsp_rdata = energy_csr_rdata;
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sensor_enable <= 1'b0;
      sensor_clear <= 1'b0;
    end else begin
      sensor_clear <= 1'b0;
      if (sensor_select && req_write) begin
        case (req_addr[7:0])
          8'h00: sensor_enable <= req_wdata[0];
          8'h04: sensor_clear <= req_wdata[0];
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
      8'h00: sensor_csr_rdata = {31'd0, sensor_enable};
      8'h04: sensor_csr_rdata = {31'd0, sensor_irq};
      8'h08: sensor_csr_rdata = {16'd0, sensor_result};
      8'h0c: sensor_csr_rdata = {31'd0, sensor_result_valid};
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
    .perf_wait_cycles(cpu_wait_cycles)
  );

  sensor_pipeline sensor (
    .clk(clk), .reset(reset), .sample_valid(sensor_bus_valid), .sample_data(sensor_bus_data),
    .cfg_enable(sensor_enable), .cfg_clear(sensor_clear), .result_valid(sensor_result_valid),
    .result_data(sensor_result), .irq(sensor_irq)
  );

  neural_accel accelerator (
    .clk(clk), .reset(reset), .csr_valid(accel_csr_valid), .csr_write(req_write),
    .csr_addr(accel_csr_addr), .csr_wdata(req_wdata), .csr_rdata(accel_csr_rdata), .irq(accelerator_irq)
  );

  secure_boot boot_controller (
    .clk(clk), .reset(reset), .csr_valid(boot_csr_valid), .csr_write(req_write),
    .csr_addr(boot_csr_addr), .csr_wdata(req_wdata), .csr_rdata(boot_csr_rdata),
    .boot_release(boot_release), .fail(boot_fail), .boot_word(boot_word)
  );

  energy_monitor activity_monitor (
    .clk(clk), .reset(reset), .csr_valid(energy_csr_valid), .csr_write(req_write),
    .csr_addr(energy_csr_addr), .csr_wdata(req_wdata), .csr_rdata(energy_csr_rdata),
    .sensor_event(sensor_result_valid), .accelerator_event(accelerator_irq), .memory_event(req_valid),
    .cpu_cycles(cpu_cycles), .cpu_instructions(cpu_instructions), .cpu_loads(cpu_loads),
    .cpu_stores(cpu_stores), .cpu_branches(cpu_branches), .cpu_bus_requests(cpu_bus_requests),
    .cpu_wait_cycles(cpu_wait_cycles)
  );
endmodule
