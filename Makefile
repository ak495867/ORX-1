SHELL := /bin/bash
RTL := rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/secure_boot.sv rtl/energy_monitor.sv rtl/orx1_soc.sv
TB := tb/tb_orx1.sv
BUILD := build

.PHONY: all sim lint synth clean

all: sim lint synth

$(BUILD):
	mkdir -p $(BUILD)

sim: $(BUILD)
	iverilog -g2012 -s tb_orx1 -o $(BUILD)/tb_orx1 $(RTL) $(TB)
	vvp $(BUILD)/tb_orx1
	iverilog -g2012 -s tb_secure_boot -o $(BUILD)/tb_secure_boot $(RTL) tb/tb_secure_boot.sv
	vvp $(BUILD)/tb_secure_boot

lint: $(BUILD)
	verilator --lint-only -Wall -Wno-fatal --top-module orx1_soc $(RTL)

synth: $(BUILD)
	yosys -q -p "read_verilog -sv $(RTL); hierarchy -top orx1_soc; proc; opt; check; stat"

clean:
	rm -rf $(BUILD) yosys.log
