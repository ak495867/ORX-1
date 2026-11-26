SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
BUILD := build
RTL := rtl/orx1_pkg.sv rtl/rv32i_core.sv rtl/sensor_pipeline.sv rtl/neural_accel.sv rtl/sha256_engine.sv rtl/secure_boot.sv rtl/uart_core.sv rtl/timer_mtime.sv rtl/sram_sp.sv rtl/dma_ctrl.sv rtl/energy_monitor.sv rtl/wb_interconnect.sv rtl/cordic_engine.sv rtl/irq_ctrl.sv rtl/gpio_ctrl.sv rtl/spi_master.sv rtl/sys_ctrl.sv rtl/orx1_soc.sv
OPENRAM_BB := rtl/sky130_sram_2kbyte_1rw1r_32x512_8.sv
TB_LEAF := tb/tb_orx1.sv
TB_BOOT := tb/tb_secure_boot.sv
TB_SOC := tb/tb_soc.sv
TB_FW := tb/tb_firmware.sv
TB_IRQ := tb/tb_interrupts.sv
TB_PERIPH := tb/tb_peripherals.sv
TB_FLASH := tb/tb_boot_flash.sv
TB_BENCH := tb/tb_cpu_benchmark.sv
TB_MODEL_BENCH := tb/tb_model_bench.sv
TB_COMP := tb/tb_riscv_compliance.sv

.PHONY: all sim bench model-bench compliance sw test-sw lint synth floorplan formal clean

all: test-sw sim bench model-bench compliance lint synth floorplan formal

$(BUILD):
	mkdir -p $(BUILD)

test-sw: $(BUILD)
	gcc -Wall -Wextra -Werror -DORX1_HOST_TEST -Isw/include -Isw/tinyml sw/tinyml/tinyml.c sw/tests/test_tinyml.c -o $(BUILD)/test_tinyml
	./$(BUILD)/test_tinyml | tee $(BUILD)/test_sw.log
	grep -q SW_TINYML_TEST_PASS $(BUILD)/test_sw.log
	gcc -O2 -Wall -Wextra -Werror -DORX1_HOST_TEST -Isw/include -Isw/tinyml sw/tinyml/tinyml.c sw/tests/bench_models.c -o $(BUILD)/bench_models
	./$(BUILD)/bench_models | tee $(BUILD)/c_model_benchmark.log
	grep -q BENCH_MODELS_PASS $(BUILD)/c_model_benchmark.log
	gcc -O2 -Wall -Wextra -Werror -DORX1_HOST_TEST -Isw/include -c sw/boot/bootloader.c -o $(BUILD)/bootloader.o

sim: $(BUILD)
	iverilog -g2012 -Wall -s tb_orx1 -o $(BUILD)/tb_orx1 $(RTL) $(TB_LEAF) 2>&1 | tee $(BUILD)/sim_compile_leaf.log
	vvp $(BUILD)/tb_orx1 | tee $(BUILD)/sim_leaf.log
	grep -q ORX1_TEST_PASS $(BUILD)/sim_leaf.log
	iverilog -g2012 -Wall -s tb_secure_boot -o $(BUILD)/tb_secure_boot $(RTL) $(TB_BOOT) 2>&1 | tee $(BUILD)/sim_compile_boot.log
	vvp $(BUILD)/tb_secure_boot | tee $(BUILD)/sim_boot.log
	grep -q SECURE_BOOT_TEST_PASS $(BUILD)/sim_boot.log
	iverilog -g2012 -Wall -s tb_soc -o $(BUILD)/tb_soc $(RTL) $(TB_SOC) 2>&1 | tee $(BUILD)/sim_compile_soc.log
	vvp $(BUILD)/tb_soc | tee $(BUILD)/sim_soc.log
	grep -q SOC_TEST_PASS $(BUILD)/sim_soc.log
	iverilog -g2012 -Wall -D USE_OPENRAM -s tb_soc -o $(BUILD)/tb_soc_openram $(RTL) $(OPENRAM_BB) $(TB_SOC) 2>&1 | tee $(BUILD)/sim_compile_soc_openram.log
	vvp $(BUILD)/tb_soc_openram | tee $(BUILD)/sim_soc_openram.log
	grep -q SOC_TEST_PASS $(BUILD)/sim_soc_openram.log
	iverilog -g2012 -Wall -s tb_firmware -o $(BUILD)/tb_firmware $(RTL) $(TB_FW) 2>&1 | tee $(BUILD)/sim_compile_fw.log
	vvp $(BUILD)/tb_firmware | tee $(BUILD)/sim_fw.log
	grep -q FIRMWARE_TEST_PASS $(BUILD)/sim_fw.log
	iverilog -g2012 -Wall -s tb_interrupts -o $(BUILD)/tb_interrupts $(RTL) $(TB_IRQ) 2>&1 | tee $(BUILD)/sim_compile_irq.log
	vvp $(BUILD)/tb_interrupts | tee $(BUILD)/sim_irq.log
	grep -q INTERRUPT_TEST_PASS $(BUILD)/sim_irq.log
	iverilog -g2012 -Wall -s tb_peripherals -o $(BUILD)/tb_peripherals $(RTL) $(TB_PERIPH) 2>&1 | tee $(BUILD)/sim_compile_periph.log
	vvp $(BUILD)/tb_peripherals | tee $(BUILD)/sim_periph.log
	grep -q PERIPHERALS_TEST_PASS $(BUILD)/sim_periph.log
	iverilog -g2012 -Wall -s tb_boot_flash -o $(BUILD)/tb_boot_flash $(RTL) $(TB_FLASH) 2>&1 | tee $(BUILD)/sim_compile_flash.log
	vvp $(BUILD)/tb_boot_flash | tee $(BUILD)/sim_boot_flash.log
	grep -q BOOT_FLASH_TEST_PASS $(BUILD)/sim_boot_flash.log
	iverilog -g2012 -Wall -D USE_OPENRAM -s tb_boot_flash -o $(BUILD)/tb_boot_flash_openram $(RTL) $(OPENRAM_BB) $(TB_FLASH) 2>&1 | tee $(BUILD)/sim_compile_flash_openram.log
	vvp $(BUILD)/tb_boot_flash_openram | tee $(BUILD)/sim_boot_flash_openram.log
	grep -q BOOT_FLASH_TEST_PASS $(BUILD)/sim_boot_flash_openram.log

bench: $(BUILD)
	iverilog -g2012 -Wall -s tb_cpu_benchmark -o $(BUILD)/tb_cpu_benchmark $(RTL) $(TB_BENCH) 2>&1 | tee $(BUILD)/sim_compile_benchmark.log
	vvp $(BUILD)/tb_cpu_benchmark | tee $(BUILD)/benchmark.log
	grep -q BENCHMARK_TEST_PASS $(BUILD)/benchmark.log

model-bench: $(BUILD)
	iverilog -g2012 -Wall -s tb_model_bench -o $(BUILD)/tb_model_bench $(RTL) $(TB_MODEL_BENCH) 2>&1 | tee $(BUILD)/sim_compile_model_bench.log
	vvp $(BUILD)/tb_model_bench | tee $(BUILD)/model_benchmark.log
	grep -q MODEL_BENCH_PASS $(BUILD)/model_benchmark.log
	gcc -O2 -Wall -Wextra -Werror -DORX1_HOST_TEST -Isw/include -Isw/tinyml sw/tinyml/tinyml.c sw/tests/bench_models.c -o $(BUILD)/bench_models
	./$(BUILD)/bench_models | tee $(BUILD)/c_model_benchmark.log
	grep -q BENCH_MODELS_PASS $(BUILD)/c_model_benchmark.log
	gcc -O2 -Wall -Wextra -Werror -DORX1_HOST_TEST -Isw/include -c sw/boot/bootloader.c -o $(BUILD)/bootloader.o

compliance: $(BUILD)
	iverilog -g2012 -Wall -s tb_riscv_compliance -o $(BUILD)/tb_riscv_compliance $(RTL) $(TB_COMP) 2>&1 | tee $(BUILD)/sim_compile_compliance.log
	vvp $(BUILD)/tb_riscv_compliance | tee $(BUILD)/compliance.log
	grep -q RISCV_COMPLIANCE_PASS $(BUILD)/compliance.log

sw: $(BUILD)
	command -v riscv64-unknown-elf-gcc >/dev/null || (printf '%s\n' 'riscv64-unknown-elf-gcc not found; skipping bare-metal SW build.'; exit 0)
	riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -nostdlib -T sw/lib/link.ld -Isw/include -Isw/tinyml sw/lib/crt0.s sw/tinyml/tinyml.c sw/examples/tinyml_anomaly_detector.c -o $(BUILD)/tinyml_anomaly_detector.elf
	riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 $(BUILD)/tinyml_anomaly_detector.elf $(BUILD)/tinyml_anomaly_detector.hex

lint: $(BUILD)
	verilator --lint-only -Wall --top-module orx1_soc $(RTL) 2>&1 | tee $(BUILD)/verilator.log
	verilator --lint-only -Wall -DUSE_OPENRAM --top-module orx1_soc $(RTL) $(OPENRAM_BB) 2>&1 | tee $(BUILD)/verilator_openram.log
	verilator --lint-only -Wall --top-module caravel_user_project_wrapper $(RTL) rtl/caravel_user_project_wrapper.sv 2>&1 | tee $(BUILD)/verilator_caravel.log

synth: $(BUILD)
	yosys -p "read_verilog -sv $(RTL) rtl/caravel_user_project_wrapper.sv; hierarchy -top caravel_user_project_wrapper; proc; opt; check; stat" 2>&1 | tee $(BUILD)/yosys.log
	yosys -p "read_verilog -sv -DUSE_OPENRAM -DSYNTHESIS $(RTL) $(OPENRAM_BB) rtl/caravel_user_project_wrapper.sv; hierarchy -top caravel_user_project_wrapper; proc; opt; check; stat" 2>&1 | tee $(BUILD)/yosys_openram.log

floorplan: $(BUILD)
	python3 scripts/floorplan_analyze.py --check-only 2>&1 | tee $(BUILD)/floorplan.log
	grep -q FLOORPLAN_CHECK_PASS $(BUILD)/floorplan.log

formal: $(BUILD)
	command -v sby >/dev/null || (printf '%s\n' 'sby is required; install SymbiYosys and a solver before running make formal.'; exit 1)
	sby -f formal/wb_xbar.sby 2>&1 | tee $(BUILD)/formal_xbar.log
	sby -f formal/neural_accel.sby 2>&1 | tee $(BUILD)/formal_npu.log
	sby -f formal/secure_boot.sby 2>&1 | tee $(BUILD)/formal_boot.log
	sby -f formal/cpu_bus.sby 2>&1 | tee $(BUILD)/formal.log

clean:
	rm -rf $(BUILD) yosys.log
