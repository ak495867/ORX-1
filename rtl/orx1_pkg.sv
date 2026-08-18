package orx1_pkg;
  parameter logic [31:0] BOOT_BASE = 32'h0000_0000;
  parameter logic [31:0] SRAM_BASE = 32'h0001_0000;
  parameter logic [31:0] SRAM_LAST = 32'h0001_0fff;
  parameter logic [31:0] SENSOR_BASE = 32'h4000_0000;
  parameter logic [31:0] ACCEL_BASE = 32'h4000_1000;
  parameter logic [31:0] BOOTCTRL_BASE = 32'h4000_2000;
  parameter logic [31:0] UART_BASE = 32'h4000_3000;
  parameter logic [31:0] ENERGY_BASE = 32'h4000_4000;
  function automatic logic in_range(input logic [31:0] address, input logic [31:0] base, input logic [31:0] last);
    in_range = (address >= base) && (address <= last);
  endfunction
endpackage
