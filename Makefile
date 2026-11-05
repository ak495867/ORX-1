SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
BUILD := build
RTL := rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/cordic_engine.sv rtl/orx1_soc.sv
TB_LEAF := tb/tb_orx1.sv
TB_BOOT := tb/tb_secure_boot.sv
TB_SOC := tb/tb_soc.sv
TB_BENCH := tb/tb_cpu_benchmark.sv
TB_COMP := tb/tb_riscv_compliance.sv

.PHONY: all check sim bench compliance lint synth formal clean

all: check sim bench compliance lint synth formal

$(BUILD):
	mkdir -p $(BUILD)

check: $(BUILD)
	./scripts/check_source_policy.sh

sim: $(BUILD)
	iverilog -g2012 -Wall -s tb_orx1 -o $(BUILD)/tb_orx1 $(RTL) $(TB_LEAF) 2>&1 | tee $(BUILD)/sim_compile_leaf.log
	vvp $(BUILD)/tb_orx1 | tee $(BUILD)/sim_leaf.log
	iverilog -g2012 -Wall -s tb_secure_boot -o $(BUILD)/tb_secure_boot $(RTL) $(TB_BOOT) 2>&1 | tee $(BUILD)/sim_compile_boot.log
	vvp $(BUILD)/tb_secure_boot | tee $(BUILD)/sim_boot.log
	iverilog -g2012 -Wall -s tb_soc -o $(BUILD)/tb_soc $(RTL) $(TB_SOC) 2>&1 | tee $(BUILD)/sim_compile_soc.log
	vvp $(BUILD)/tb_soc | tee $(BUILD)/sim_soc.log

bench: $(BUILD)
	iverilog -g2012 -Wall -s tb_cpu_benchmark -o $(BUILD)/tb_cpu_benchmark $(RTL) $(TB_BENCH) 2>&1 | tee $(BUILD)/sim_compile_benchmark.log
	vvp $(BUILD)/tb_cpu_benchmark | tee $(BUILD)/benchmark.log
	grep -q BENCHMARK_TEST_PASS $(BUILD)/benchmark.log

compliance: $(BUILD)
	iverilog -g2012 -Wall -s tb_riscv_compliance -o $(BUILD)/tb_riscv_compliance $(RTL) $(TB_COMP) 2>&1 | tee $(BUILD)/sim_compile_compliance.log
	vvp $(BUILD)/tb_riscv_compliance | tee $(BUILD)/compliance.log
	grep -q RISCV_COMPLIANCE $(BUILD)/compliance.log

lint: $(BUILD)
	verilator --lint-only -Wall --Wno-fatal --top-module orx1_soc $(RTL) 2>&1 | tee $(BUILD)/verilator.log
	sed -n '/%Warning/p' $(BUILD)/verilator.log > $(BUILD)/verilator-warnings.log || true

synth: $(BUILD)
	yosys -p "read_verilog -sv $(RTL); hierarchy -top orx1_soc; proc; opt; check; stat" 2>&1 | tee $(BUILD)/yosys.log

formal: $(BUILD)
	command -v sby >/dev/null || (printf '%s\n' 'sby is required; install SymbiYosys and a solver before running make formal.'; exit 1)
	sby -f formal/cpu_bus.sby 2>&1 | tee $(BUILD)/formal.log

clean:
	rm -rf $(BUILD) yosys.log
