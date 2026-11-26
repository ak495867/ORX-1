#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
RTL="rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/cordic_engine.sv rtl/irq_ctrl.sv rtl/gpio_ctrl.sv rtl/spi_master.sv rtl/sys_ctrl.sv rtl/orx1_soc.sv"
verilator --lint-only -Wall --top-module orx1_soc $RTL
verilator --lint-only -Wall --top-module caravel_user_project_wrapper $RTL rtl/caravel_user_project_wrapper.sv
yosys -q -p "read_verilog -sv $RTL rtl/caravel_user_project_wrapper.sv; hierarchy -top caravel_user_project_wrapper; proc; opt; check; stat"
