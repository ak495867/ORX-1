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
  localparam logic [31:0] SRAM_BASE = 32'h0001_0000;
  localparam logic [31:0] SRAM_LAST = 32'h0001_0fff;
  localparam logic [31:0] SENSOR_BASE = 32'h4000_0000;
  localparam logic [31:0] ACCEL_BASE = 32'h4000_1000;
  localparam logic [31:0] BOOTCTRL_BASE = 32'h4000_2000;
  localparam logic [31:0] UART_BASE = 32'h4000_3000;
  localparam logic [31:0] ENERGY_BASE = 32'h4000_4000;
  function automatic logic in_range(input logic [31:0] address, input logic [31:0] base, input logic [31:0] last);
    in_range = (address >= base) && (address <= last);
  endfunction

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic d_valid;
  logic d_write;
  logic [31:0] d_addr;
  logic [31:0] d_wdata;
  logic [3:0] d_wstrb;
  logic [31:0] d_rdata;
  logic d_ready;

  logic [31:0] sram [0:1023];
  logic [31:0] sensor_csr_rdata;
  logic [31:0] accel_csr_rdata;
  logic [31:0] boot_csr_rdata;
  logic [31:0] energy_csr_rdata;
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
  wire rom_select = d_valid && d_addr < 32'h0000_0400;
  wire sram_select = d_valid && in_range(d_addr, SRAM_BASE, SRAM_LAST);
  wire sensor_select = d_valid && in_range(d_addr, SENSOR_BASE, SENSOR_BASE + 32'h0000_00ff);
  wire accel_select = d_valid && in_range(d_addr, ACCEL_BASE, ACCEL_BASE + 32'h0000_00ff);
  wire boot_select = d_valid && in_range(d_addr, BOOTCTRL_BASE, BOOTCTRL_BASE + 32'h0000_00ff);
  wire uart_select = d_valid && in_range(d_addr, UART_BASE, UART_BASE + 32'h0000_00ff);
  wire energy_select = d_valid && in_range(d_addr, ENERGY_BASE, ENERGY_BASE + 32'h0000_00ff);

  assign imem_rdata = {30'd0, imem_addr[1:0]};
  assign sram_index = d_addr[11:2];
  assign accel_csr_valid = accel_select;
  assign boot_csr_valid = boot_select;
  assign energy_csr_valid = energy_select;
  assign accel_csr_addr = d_addr[7:0];
  assign boot_csr_addr = d_addr[7:0];
  assign energy_csr_addr = d_addr[7:0];
  assign boot_word = 32'd0;
  assign sensor_bus_valid = sensor_valid | (sensor_select && d_write && d_addr[7:0] == 8'h08);
  assign sensor_bus_data = sensor_valid ? sensor_data : d_wdata[15:0];

  always_comb begin
    d_ready = d_valid;
    d_rdata = 32'd0;
    if (rom_select) d_rdata = 32'd0;
    else if (sram_select) d_rdata = sram[sram_index];
    else if (sensor_select) d_rdata = sensor_csr_rdata;
    else if (accel_select) d_rdata = accel_csr_rdata;
    else if (boot_select) d_rdata = boot_csr_rdata;
    else if (energy_select) d_rdata = energy_csr_rdata;
    else if (uart_select) d_rdata = 32'd0;
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sensor_enable <= 1'b0;
      sensor_clear <= 1'b0;
    end else begin
      sensor_clear <= 1'b0;
      if (sensor_select && d_write) begin
        case (d_addr[7:0])
          8'h00: sensor_enable <= d_wdata[0];
          8'h04: sensor_clear <= d_wdata[0];
          default: begin end
        endcase
      end
      if (sram_select && d_write) begin
        if (d_wstrb[0]) sram[sram_index][7:0] <= d_wdata[7:0];
        if (d_wstrb[1]) sram[sram_index][15:8] <= d_wdata[15:8];
        if (d_wstrb[2]) sram[sram_index][23:16] <= d_wdata[23:16];
        if (d_wstrb[3]) sram[sram_index][31:24] <= d_wdata[31:24];
      end
    end
  end

  always_comb begin
    sensor_csr_rdata = 32'd0;
    case (d_addr[7:0])
      8'h00: sensor_csr_rdata = {31'd0, sensor_enable};
      8'h04: sensor_csr_rdata = {31'd0, sensor_irq};
      8'h08: sensor_csr_rdata = {16'd0, sensor_result};
      8'h0c: sensor_csr_rdata = {31'd0, sensor_result_valid};
      default: sensor_csr_rdata = 32'd0;
    endcase
  end

  rv32i_core core (
    .clk(clk),
    .reset(reset),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .d_valid(d_valid),
    .d_write(d_write),
    .d_addr(d_addr),
    .d_wdata(d_wdata),
    .d_wstrb(d_wstrb),
    .d_rdata(d_rdata),
    .d_ready(d_ready),
    .trap(core_trap)
  );

  sensor_pipeline sensor (
    .clk(clk),
    .reset(reset),
    .sample_valid(sensor_bus_valid),
    .sample_data(sensor_bus_data),
    .cfg_enable(sensor_enable),
    .cfg_clear(sensor_clear),
    .result_valid(sensor_result_valid),
    .result_data(sensor_result),
    .irq(sensor_irq)
  );

  neural_accel accelerator (
    .clk(clk),
    .reset(reset),
    .csr_valid(accel_csr_valid),
    .csr_write(d_write),
    .csr_addr(accel_csr_addr),
    .csr_wdata(d_wdata),
    .csr_rdata(accel_csr_rdata),
    .irq(accelerator_irq)
  );

  secure_boot boot_controller (
    .clk(clk),
    .reset(reset),
    .csr_valid(boot_csr_valid),
    .csr_write(d_write),
    .csr_addr(boot_csr_addr),
    .csr_wdata(d_wdata),
    .csr_rdata(boot_csr_rdata),
    .boot_release(boot_release),
    .fail(boot_fail),
    .boot_word(boot_word)
  );

  energy_monitor activity_monitor (
    .clk(clk),
    .reset(reset),
    .csr_valid(energy_csr_valid),
    .csr_write(d_write),
    .csr_addr(energy_csr_addr),
    .csr_wdata(d_wdata),
    .csr_rdata(energy_csr_rdata),
    .sensor_event(sensor_result_valid),
    .accelerator_event(accelerator_irq),
    .memory_event(d_valid)
  );
endmodule
