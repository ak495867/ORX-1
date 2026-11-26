$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (Test-Path "C:\Users\Ak\tools\oss-cad-suite\bin") {
  $env:PATH = "C:\Users\Ak\tools\oss-cad-suite\bin;C:\Users\Ak\tools\oss-cad-suite\lib;" + $env:PATH
  if (-not $env:VERILATOR_ROOT -and (Test-Path "C:\Users\Ak\tools\oss-cad-suite\share\verilator")) {
    $env:VERILATOR_ROOT = "C:\Users\Ak\tools\oss-cad-suite\share\verilator"
  }
}

function Invoke-Tool {
  param([string]$FilePath, [string[]]$ToolArgs, [string]$LogPath = "")
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & $FilePath @ToolArgs 2>&1 | ForEach-Object { $_.ToString() }
  $rc = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($LogPath -ne "") { $out | Set-Content $LogPath }
  if ($rc -ne 0) {
    $out | Write-Host
    throw "Command failed ($rc): $FilePath $($ToolArgs -join ' ')"
  }
  return $out
}

New-Item -ItemType Directory -Force build | Out-Null

$codeFiles = Get-ChildItem -Recurse rtl,tb,formal,sw -Include *.sv,*.c,*.h
$comments = $codeFiles | Select-String -Pattern '(//|/\*|\*/)'
if ($comments) {
  Write-Host "COMMENT_CHECK_FAIL"
  $comments | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)" }
  exit 1
}
Write-Host "COMMENT_CHECK_PASS count=$($codeFiles.Count)"

Invoke-Tool "gcc" @('-Wall','-Wextra','-Werror','-DORX1_HOST_TEST','-Isw/include','-Isw/tinyml','sw/tinyml/tinyml.c','sw/tests/test_tinyml.c','-o','build/test_tinyml.exe') | Out-Null
$swOut = Invoke-Tool ".\build\test_tinyml.exe" @() "build/test_sw.log"
if (-not (Select-String -Quiet -Pattern 'SW_TINYML_TEST_PASS' build/test_sw.log)) { exit 1 }
Write-Host "test_tinyml: SW_TINYML_TEST_PASS"

Invoke-Tool "gcc" @('-O2','-Wall','-Wextra','-Werror','-DORX1_HOST_TEST','-Isw/include','-Isw/tinyml','sw/tinyml/tinyml.c','sw/tests/bench_models.c','-o','build/bench_models.exe') | Out-Null
$bmOut = Invoke-Tool ".\build\bench_models.exe" @() "build/c_model_benchmark.log"
if (-not (Select-String -Quiet -Pattern 'BENCH_MODELS_PASS' build/c_model_benchmark.log)) { exit 1 }
$bmOut | Write-Host

Invoke-Tool "gcc" @('-O2','-Wall','-Wextra','-Werror','-DORX1_HOST_TEST','-Isw/include','-c','sw/boot/bootloader.c','-o','build/bootloader.o') | Out-Null
Write-Host "BOOTLOADER_C_PASS"

$rtl = @(
  'rtl/orx1_pkg.sv','rtl/rv32i_core.sv','rtl/sensor_pipeline.sv','rtl/neural_accel.sv',
  'rtl/sha256_engine.sv','rtl/secure_boot.sv','rtl/uart_core.sv','rtl/timer_mtime.sv',
  'rtl/sram_sp.sv','rtl/dma_ctrl.sv','rtl/energy_monitor.sv','rtl/wb_interconnect.sv',
  'rtl/cordic_engine.sv','rtl/irq_ctrl.sv','rtl/gpio_ctrl.sv','rtl/spi_master.sv',
  'rtl/sys_ctrl.sv','rtl/orx1_soc.sv'
)

$verilatorCmd = if (Get-Command verilator_bin.exe -ErrorAction SilentlyContinue) { 'verilator_bin.exe' } else { 'verilator' }
Invoke-Tool $verilatorCmd (@('--lint-only','-Wall','--top-module','orx1_soc') + $rtl) "build/verilator.log" | Out-Null
Invoke-Tool $verilatorCmd (@('--lint-only','-Wall','--top-module','caravel_user_project_wrapper') + $rtl + @('rtl/caravel_user_project_wrapper.sv')) "build/verilator_caravel.log" | Out-Null
Write-Host "VERILATOR_STRICT_PASS"

$tbs = @(
  @{top='tb_orx1'; src='tb/tb_orx1.sv'; expect='ORX1_TEST_PASS'; log='build/sim_leaf.log'},
  @{top='tb_secure_boot'; src='tb/tb_secure_boot.sv'; expect='SECURE_BOOT_TEST_PASS'; log='build/sim_boot.log'},
  @{top='tb_soc'; src='tb/tb_soc.sv'; expect='SOC_TEST_PASS'; log='build/sim_soc.log'},
  @{top='tb_firmware'; src='tb/tb_firmware.sv'; expect='FIRMWARE_TEST_PASS'; log='build/sim_fw.log'},
  @{top='tb_interrupts'; src='tb/tb_interrupts.sv'; expect='INTERRUPT_TEST_PASS'; log='build/sim_irq.log'},
  @{top='tb_peripherals'; src='tb/tb_peripherals.sv'; expect='PERIPHERALS_TEST_PASS'; log='build/sim_periph.log'},
  @{top='tb_boot_flash'; src='tb/tb_boot_flash.sv'; expect='BOOT_FLASH_TEST_PASS'; log='build/sim_boot_flash.log'},
  @{top='tb_cpu_benchmark'; src='tb/tb_cpu_benchmark.sv'; expect='BENCHMARK_TEST_PASS'; log='build/benchmark.log'},
  @{top='tb_model_bench'; src='tb/tb_model_bench.sv'; expect='MODEL_BENCH_PASS'; log='build/model_benchmark.log'},
  @{top='tb_riscv_compliance'; src='tb/tb_riscv_compliance.sv'; expect='RISCV_COMPLIANCE_PASS'; log='build/compliance.log'}
)
foreach ($t in $tbs) {
  $vvp = "build/$($t.top).vvp"
  Invoke-Tool "iverilog" (@('-g2012','-Wall','-s',$t.top,'-o',$vvp) + $rtl + @($t.src)) | Out-Null
  Invoke-Tool "vvp" @($vvp) $t.log | Out-Null
  $hit = Select-String -Pattern $t.expect $t.log
  if (-not $hit) {
    Write-Host "SIM_FAIL $($t.top)"
    Get-Content $t.log | Write-Host
    exit 1
  }
  Write-Host "$($t.top): $($hit.Line.Trim())"
}

$yosysCmd = "read_verilog -sv $($rtl -join ' ') rtl/caravel_user_project_wrapper.sv; hierarchy -top caravel_user_project_wrapper; proc; opt; check; stat"
Invoke-Tool "yosys" @('-q','-p',$yosysCmd) "build/yosys.log" | Out-Null
Write-Host "YOSYS_SYNTH_CHECK_PASS"

foreach ($sbyJob in @('formal/wb_xbar.sby','formal/neural_accel.sby','formal/secure_boot.sby','formal/cpu_bus.sby')) {
  $sbyLog = "build/$(([IO.Path]::GetFileNameWithoutExtension($sbyJob))).sby.log"
  Invoke-Tool "sby" @('-f',$sbyJob) $sbyLog | Out-Null
  Write-Host "FORMAL_PASS $sbyJob"
}

Write-Host "ALL_ORX1_VERIFICATION_PASS"
