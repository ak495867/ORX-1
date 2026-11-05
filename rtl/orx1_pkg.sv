`ifndef ORX1_PKG_SV
`define ORX1_PKG_SV
`define ORX1_BOOT_BASE 32'h0000_0000
`define ORX1_BOOT_LAST 32'h0000_03ff
`define ORX1_SRAM_BASE 32'h0001_0000
`define ORX1_SRAM_LAST 32'h0001_0fff
`define ORX1_SENSOR_BASE 32'h4000_0000
`define ORX1_ACCEL_BASE 32'h4000_1000
`define ORX1_BOOTCTRL_BASE 32'h4000_2000
`define ORX1_UART_BASE 32'h4000_3000
`define ORX1_ENERGY_BASE 32'h4000_4000
`define ORX1_TIMER_BASE 32'h4000_5000
`define ORX1_DMA_BASE 32'h4000_6000
`define ORX1_REGION_SIZE 32'h0000_0100

package orx1_pkg;
  localparam logic [31:0] BOOT_BASE = `ORX1_BOOT_BASE;
  localparam logic [31:0] BOOT_LAST = `ORX1_BOOT_LAST;
  localparam logic [31:0] SRAM_BASE = `ORX1_SRAM_BASE;
  localparam logic [31:0] SRAM_LAST = `ORX1_SRAM_LAST;
  localparam logic [31:0] SENSOR_BASE = `ORX1_SENSOR_BASE;
  localparam logic [31:0] ACCEL_BASE = `ORX1_ACCEL_BASE;
  localparam logic [31:0] BOOTCTRL_BASE = `ORX1_BOOTCTRL_BASE;
  localparam logic [31:0] UART_BASE = `ORX1_UART_BASE;
  localparam logic [31:0] ENERGY_BASE = `ORX1_ENERGY_BASE;
  localparam logic [31:0] TIMER_BASE = `ORX1_TIMER_BASE;
  localparam logic [31:0] DMA_BASE = `ORX1_DMA_BASE;
  localparam logic [31:0] REGION_SIZE = `ORX1_REGION_SIZE;

  function automatic logic in_range(input logic [31:0] address, input logic [31:0] base, input logic [31:0] last);
    in_range = (address >= base) && (address <= last);
  endfunction
endpackage
`endif
