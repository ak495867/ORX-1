#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
verilator --lint-only -Wall -Wno-fatal --top-module orx1_soc rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/orx1_soc.sv
yosys -q -p "read_verilog -sv rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/orx1_soc.sv; hierarchy -top orx1_soc; proc; opt; check; stat"
