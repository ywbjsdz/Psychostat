# Psychostat 数值回归测试包装器（本地与 CI 共用）
# 用法：.\tests\run_numeric_tests.ps1
# 职责：清 locale → 定位 Rscript（复用 psychostat_env.ps1 三级发现）→ 运行 tests\test_numeric.R
#       → 统计输出中的 [PASS]/[FAIL] 行数并末行输出 PASS_COUNT=N / FAIL_COUNT=N（断言条数的单一事实来源）→ 透传退出码
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'psychostat_env.ps1')
$rscript = Initialize-PsychostatEnvironment
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "[run_numeric_tests] 使用 Rscript: $rscript"
$lines = @()
& $rscript --vanilla (Join-Path $root 'tests\test_numeric.R') |
    ForEach-Object { $line = "$_"; $script:lines += $line; Write-Host $line }
$code = $LASTEXITCODE
$passCount = @($lines | Where-Object { $_.Contains('[PASS]') }).Count
$failCount = @($lines | Where-Object { $_.Contains('[FAIL]') }).Count
Write-Host "PASS_COUNT=$passCount FAIL_COUNT=$failCount"
exit $code
