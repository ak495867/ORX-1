#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
iverilog -g2012 -s tb_orx1 -o build/tb_orx1 rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/secure_boot.sv rtl/uart_tx.sv rtl/energy_monitor.sv rtl/orx1_soc.sv tb/tb_orx1.sv
vvp build/tb_orx1
iverilog -g2012 -s tb_secure_boot -o build/tb_secure_boot rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/secure_boot.sv rtl/uart_tx.sv rtl/energy_monitor.sv rtl/orx1_soc.sv tb/tb_secure_boot.sv
vvp build/tb_secure_boot
