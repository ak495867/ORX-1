#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
RTL="rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/cordic_engine.sv rtl/irq_ctrl.sv rtl/orx1_soc.sv"
iverilog -g2012 -s tb_orx1 -o build/tb_orx1 $RTL tb/tb_orx1.sv
vvp build/tb_orx1
iverilog -g2012 -s tb_secure_boot -o build/tb_secure_boot $RTL tb/tb_secure_boot.sv
vvp build/tb_secure_boot
iverilog -g2012 -s tb_soc -o build/tb_soc $RTL tb/tb_soc.sv
vvp build/tb_soc
iverilog -g2012 -s tb_firmware -o build/tb_firmware $RTL tb/tb_firmware.sv
vvp build/tb_firmware
iverilog -g2012 -s tb_interrupts -o build/tb_interrupts $RTL tb/tb_interrupts.sv
vvp build/tb_interrupts
iverilog -g2012 -s tb_cpu_benchmark -o build/tb_cpu_benchmark $RTL tb/tb_cpu_benchmark.sv
vvp build/tb_cpu_benchmark
iverilog -g2012 -s tb_riscv_compliance -o build/tb_riscv_compliance $RTL tb/tb_riscv_compliance.sv
vvp build/tb_riscv_compliance
