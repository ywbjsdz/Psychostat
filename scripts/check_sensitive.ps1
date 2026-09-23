# Psychostat 敏感文件提交前检查
# 用法：.\scripts\check_sensitive.ps1      # 在 Psychostat 根目录执行
# 扫描范围：① git 已跟踪文件（git ls-files，CI 干净检出时也能发现误入库的历史文件）
#           ② git 将纳入提交的改动/新文件（git status --porcelain）。
# 规则：命中 .sav/.xlsx/.xls/.csv，且不在豁免目录（examples/、tests/data/、outputs/）下。
# 命中则按来源（已跟踪/未提交）列出并退出码 1（阻止发布）。
param()
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
if (-not (Test-Path (Join-Path $root '.git'))) {
    Write-Host '[check_sensitive] 未找到 .git（跳过；仓库初始化后此检查才有效）。' -ForegroundColor DarkYellow
    exit 0
}
function Test-SuspectPath([string]$p) {
    $p -match '\.(sav|xlsx|xls|csv)$' -and $p -notmatch '^(examples|tests/data)/' -and $p -notmatch '^outputs/'
}
$porcelain = & git -C $root status --porcelain 2>$null
$tracked   = & git -C $root -c core.quotepath=false ls-files 2>$null
$hitsTracked = @(); $hitsPending = @()
foreach ($f in $tracked) { if (Test-SuspectPath $f) { $hitsTracked += $f } }
foreach ($line in $porcelain) {
    $path = $line.Substring(3).Trim('"')
    # 已跟踪命中不再重复报（同一路径以“已跟踪”为准）
    if ((Test-SuspectPath $path) -and $hitsTracked -notcontains $path) { $hitsPending += $path }
}
if ($hitsTracked.Count -or $hitsPending.Count) {
    Write-Host '[check_sensitive] ⚠ 检测到疑似真实数据文件（请移入 data/ 目录或加入 .gitignore）：' -ForegroundColor Red
    $hitsTracked | ForEach-Object { Write-Host "  - [已跟踪] $_" -ForegroundColor Red }
    $hitsPending | ForEach-Object { Write-Host "  - [未提交] $_" -ForegroundColor Red }
    Write-Host '[check_sensitive] 已跟踪文件请用 git rm --cached 取消跟踪；未提交文件请不要 git add。' -ForegroundColor Yellow
    Write-Host '[check_sensitive] 确认是模拟/示例数据可在下面追加豁免。' -ForegroundColor Yellow
    exit 1
}
Write-Host '[check_sensitive] OK：已跟踪与待提交文件中均未发现疑似真实数据文件。' -ForegroundColor Green
exit 0
