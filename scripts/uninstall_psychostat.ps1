<#
Psychostat 环境清理脚本（安全版）

作用：把本工具在你电脑上"装过的东西"干净地删掉——只删除**本工具专属**的目录：
  · Psychostat-R-Library     我们新增的 R 包（不碰 R 自带的与你自己装的包）
  · Psychostat-Python-User   我们新增的 Python 依赖（pandas / python-docx）
  · PsychostatTemp           临时路径含中文时用来重定向的 TEMP 目录
  · install_manifest.json    本次安装的记录文件本身

绝对不做的事（红线）：
  · 不删除已存在的 R / Python 本体（你可能在用 RStudio 或其它脚本依赖它们）
  · 不删除共享的 R / Python 用户库（那里面混着你自己装的包）
  · 不删除你的分析结果 outputs\ 与数据 data\（只在预览里列出体积，提醒你自行处理）

用法（在项目根目录执行，或双击本文件所在目录的 .bat）：
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\uninstall_psychostat.ps1            # 只预览（默认）
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\uninstall_psychostat.ps1 -Execute   # 真正删除（会二次确认）
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\uninstall_psychostat.ps1 -Execute -Force   # 跳过确认

参数：
  -Execute        真正执行删除（缺省为 dry-run 预览）
  -Force          执行时不询问确认
  -ManifestPath   指定安装清单路径（默认与 psychostat_env.ps1 使用同一套解析，可用 PSYCHOSTAT_STATE_DIR 覆盖）
#>
param([switch]$Execute, [switch]$Force, [switch]$PreviewOnly, [string]$ManifestPath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# 白名单：只允许删除"叶子名"符合下列模式的目录（防止清单被改成任意路径后误删）
$AllowedLeaf = @('Psychostat-R-Library', 'Psychostat-Python-User', 'PsychostatTemp')

function Get-DirSizeMB([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 0)
}

function Test-Deletable([string]$Path) {
    # 多重护栏：必须是白名单叶子名、不是盘根、不在项目目录内、长度合理
    if (-not $Path) { return @{ ok = $false; why = '路径为空' } }
    $full = $Path
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return @{ ok = $false; why = '路径非法' } }
    $leaf = Split-Path -Leaf ($full.TrimEnd('\'))
    if ($AllowedLeaf -notcontains $leaf) { return @{ ok = $false; why = "目录名不在白名单（$leaf）" } }
    if ($full.TrimEnd('\') -match '^[A-Za-z]:$') { return @{ ok = $false; why = '是盘根目录' } }
    if ($full.TrimEnd('\').Length -lt 12) { return @{ ok = $false; why = '路径过短' } }
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return @{ ok = $false; why = '位于项目目录内' } }
    return @{ ok = $true; why = '' }
}

# ── 1. 读安装清单（与 psychostat_env.ps1 使用同一套路径解析）────────────────────
if (-not $ManifestPath) {
    $envScript = Join-Path $root 'psychostat_env.ps1'
    if (Test-Path -LiteralPath $envScript) {
        . $envScript
        $ManifestPath = Get-PsychostatInstallManifestPath
    } else {
        $ManifestPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Psychostat') 'install_manifest.json'
    }
}
$manifest = $null
if (Test-Path -LiteralPath $ManifestPath) {
    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $manifest = $null }
}

# ── 2. 汇总"可删除项"（清单 + 已知候选位置探测，兼容本功能上线前安装的机器）──────
$targets = New-Object System.Collections.Generic.List[object]
function Add-Target([string]$Path, [string]$Kind) {
    if (-not $Path) { return }
    $dup = $targets | Where-Object { $_.Path -eq $Path }
    if ($dup) { return }
    $check = Test-Deletable $Path
    $exists = Test-Path -LiteralPath $Path
    $targets.Add([pscustomobject]@{
        Path = $Path; Kind = $Kind; Exists = $exists
        SizeMB = Get-DirSizeMB $Path
        Safe = $check.ok
        Deletable = ($check.ok -and $exists)
        Note = $(if (-not $check.ok) { $check.why } elseif (-not $exists) { '不存在（跳过）' } else { '' })
    })
}

# 2a. 清单里记录的专属目录
if ($manifest) {
    if ($manifest.r -and $manifest.r.package_library_is_dedicated) { Add-Target $manifest.r.package_library 'R 包（本工具专属库）' }
    if ($manifest.python -and $manifest.python.user_base -and $manifest.python.user_base -ne 'shared_user_site') { Add-Target $manifest.python.user_base 'Python 依赖（本工具专属）' }
    if ($manifest.temp -and $manifest.temp.redirect_dir) { Add-Target $manifest.temp.redirect_dir 'TEMP 重定向目录' }
}
# 2b. 候选位置探测（D 盘 → R/Python 安装目录旁 → C 盘 → LOCALAPPDATA）
$probe = @()
if (Test-Path -LiteralPath 'D:\') { $probe += 'D:\Psychostat-R-Library'; $probe += 'D:\Psychostat-Python-User' }
if (Test-Path -LiteralPath 'C:\') { $probe += 'C:\Psychostat-R-Library'; $probe += 'C:\Psychostat-Python-User'; $probe += 'C:\PsychostatTemp' }
if ($env:LOCALAPPDATA) {
    $probe += (Join-Path $env:LOCALAPPDATA 'Psychostat\Psychostat-R-Library')
    $probe += (Join-Path $env:LOCALAPPDATA 'Psychostat\Psychostat-Python-User')
}
$rscript = $null
$cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
if ($cmd) { $rscript = $cmd.Source }
if (-not $rscript -and $manifest -and $manifest.r) { $rscript = $manifest.r.path }
if ($rscript -and (Test-Path -LiteralPath $rscript)) {
    $rBase = Split-Path (Split-Path (Split-Path $rscript -Parent) -Parent) -Parent
    $probe += (Join-Path $rBase 'Psychostat-R-Library')
}
$python = $null
if ($manifest -and $manifest.python) { $python = $manifest.python.path }
if ($python -and (Test-Path -LiteralPath $python)) {
    $probe += (Join-Path (Split-Path -Parent $python) 'Psychostat-Python-User')
}
foreach ($p in $probe) { Add-Target $p '专属目录（探测到）' }

# ── 3. 打印报告 ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '══════════ Psychostat 环境清理 ' -NoNewline
Write-Host $(if ($Execute) { '（执行删除）' } else { '（预览模式，不会删除任何东西）' }) -ForegroundColor $(if ($Execute) { 'Yellow' } else { 'Cyan' })
Write-Host ('安装清单：' + $ManifestPath + $(if ($manifest) { '  ✓ 已读取' } else { '  （无，按候选位置探测）' }))
if ($manifest) { Write-Host ("清单记录时间：" + $manifest.last_updated + "；项目目录：" + $manifest.project_dir) }
Write-Host ''
Write-Host '【将删除：本工具专属目录】' -ForegroundColor Yellow
$doomed = @($targets | Where-Object { $_.Deletable })
if (-not $doomed.Count) { Write-Host '  （没有找到本工具专属目录——说明依赖装在共享库里，或已经清理过）' }
foreach ($t in $targets) {
    $mark = if ($t.Deletable) { '删除' } elseif (-not $t.Safe) { '拒绝' } elseif ($t.Exists) { '保留' } else { '—' }
    $size = if ($null -eq $t.SizeMB) { '' } else { "  $($t.SizeMB) MB" }
    Write-Host ("  [{0}] {1,-58}{2}{3}" -f $mark, $t.Path, $size, $(if ($t.Note) { "  （$($t.Note)）" } else { '' }))
}
$totalMB = ($doomed | Measure-Object -Property SizeMB -Sum).Sum
Write-Host ("  合计可释放约 " + [math]::Round($totalMB, 0) + " MB") -ForegroundColor Yellow
Write-Host ''
Write-Host '【不会删除（需要你自己决定）】' -ForegroundColor DarkCyan
if ($manifest -and $manifest.r -and $manifest.r.path) {
    $own = if ($manifest.r.installed_by_us) { '（记录显示：当初是 Psychostat 帮你装的）' } else { '（记录显示：安装 Psychostat 之前就存在）' }
    Write-Host ("  · R 本体：$($manifest.r.path) $own")
    # R 主目录 = <R_HOME>\bin\Rscript.exe 往上两级；Inno 安装器的卸载程序就在 R 主目录下
    $rHome = Split-Path (Split-Path $manifest.r.path -Parent) -Parent
    $unins = Join-Path $rHome 'unins000.exe'
    if (Test-Path -LiteralPath $unins) {
        Write-Host ("    如需卸载：运行 `"$unins`"，或 设置 → 应用 → R for Windows（注意：RStudio 等软件可能依赖它）")
    } else {
        Write-Host ("    如需卸载：设置 → 应用 → R for Windows，或删除 $rHome（注意：RStudio 等软件可能依赖它）")
    }
}
if ($manifest -and $manifest.python -and $manifest.python.path) {
    $own = if ($manifest.python.installed_by_us) { '（记录显示：当初是 Psychostat 帮你装的）' } else { '（记录显示：安装 Psychostat 之前就存在）' }
    Write-Host ("  · Python 本体：$($manifest.python.path) $own")
    Write-Host ("    如需卸载：设置 → 应用 → Python（注意：其它项目可能也在用它）")
}
if ($manifest -and $manifest.r -and -not $manifest.r.package_library_is_dedicated) {
    Write-Host ("  · R 包共享用户库：$($manifest.r.package_library)")
    Write-Host ('    里面有你自己装的包，本脚本不动它；要清请手动删该目录（或只删本工具用到的包）')
}
if ($manifest -and $manifest.r -and $manifest.r.path -and (Test-Path -LiteralPath $manifest.r.path)) {
    # R 自带包库（= <R主目录>\library）：本工具的 R 包若当初装进了这里（而不是专属目录），
    # 脚本不会自动删——里面同时有 R 自带的基础包，其它 R 项目也可能在用。如实报告体积供用户判断。
    $rHome2 = Split-Path (Split-Path $manifest.r.path -Parent) -Parent
    $sysLib = Join-Path $rHome2 'library'
    if (Test-Path -LiteralPath $sysLib) {
        $libMB = Get-DirSizeMB $sysLib
        Write-Host ("  · R 自带包库：$sysLib （约 $libMB MB）")
        Write-Host '    本工具用到的 R 包若装在这里，本脚本不会自动删（其中含 R 自带基础包，其它 R 项目也可能依赖）'
        Write-Host '    确定不再用 R 时，可手动删除该目录，或直接卸载 R 本体'
    }
}
if ($manifest -and $manifest.python -and $manifest.python.user_base -eq 'shared_user_site') {
    Write-Host '  · Python 依赖装在共享用户目录（pandas / python-docx）——本脚本不动它'
    Write-Host '    如需删除：<你的Python> -m pip uninstall pandas python-docx lxml'
}
foreach ($d in @('outputs', 'data')) {
    $p = Join-Path $root $d
    if (Test-Path -LiteralPath $p) {
        $mb = Get-DirSizeMB $p
        $what = if ($d -eq 'outputs') { '你的分析结果' } else { '你自己的数据' }
        Write-Host ("  · 项目内 $d\ （$what，约 $mb MB）——不自动删除")
    }
}
Write-Host ("  · 项目文件夹本身：" + $root)
Write-Host '    这个文件夹可以整体删除（里面没有任何系统级安装的东西）'
Write-Host ''

if (-not $doomed.Count) {
    Write-Host '没有需要删除的专属目录（可能依赖装在共享库里，或已经清理过）。' -ForegroundColor Green
    exit 0
}
# 交互确认：双击「清理Psychostat环境.bat」进来时，直接在这里问，用户不需要记任何参数
# 说明：$PreviewOnly（界面按钮调用）与非交互环境（管道/CI）都只输出预览、绝不询问、绝不删除。
if (-not $Execute -and ($PreviewOnly -or -not [Environment]::UserInteractive)) {
    if (-not $PreviewOnly) { Write-Host '以上为预览（当前为非交互环境）。确认无误后加 -Execute 执行。' -ForegroundColor Cyan }
    exit 0
}
if (-not $Execute) {
    Write-Host ''
    Write-Host ('是否现在清理上面这 ' + $doomed.Count + ' 个目录（约 ' + [math]::Round($totalMB, 0) + ' MB）？') -ForegroundColor Cyan
    Write-Host '  输入 Y 再回车 = 执行清理      直接回车 = 什么都不做（仅查看）' -ForegroundColor Cyan
    $yn = Read-Host '请选择'
    if ($yn -notmatch '^[Yy]') {
        Write-Host ''
        Write-Host '已取消：没有删除任何内容。' -ForegroundColor DarkYellow
        exit 0
    }
    $Execute = $true
    $Force = $true          # 上面的 Y 就是确认，不再二次追问
} elseif (-not $Force) {
    $yn = Read-Host ("确认删除上述 " + $doomed.Count + " 个目录（约 " + [math]::Round($totalMB, 0) + " MB）？输入 Y 继续")
    if ($yn -notmatch '^[Yy]') { Write-Host '已取消，未删除任何内容。' -ForegroundColor DarkYellow; exit 0 }
}

# ── 4. 执行删除 ──────────────────────────────────────────────────────────────
Write-Host ''
$failed = @()
foreach ($t in $doomed) {
    try {
        Remove-Item -LiteralPath $t.Path -Recurse -Force -ErrorAction Stop
        Write-Host ("  已删除 {0} （{1} MB）" -f $t.Path, $t.SizeMB) -ForegroundColor Green
    } catch {
        $failed += "$($t.Path)：$($_.Exception.Message)"
        Write-Host ("  删除失败 {0} → {1}" -f $t.Path, $_.Exception.Message) -ForegroundColor Red
    }
}
# 清单本身：全部删除成功后移除（便于用户确认"真的清完了"）
if (-not $failed.Count -and (Test-Path -LiteralPath $ManifestPath)) {
    try { Remove-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop; Write-Host ("  已删除安装清单：$ManifestPath") -ForegroundColor Green } catch { }
}
Write-Host ''
if ($failed.Count) {
    Write-Host ("完成，但有 " + $failed.Count + " 项失败：") -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  · $_" -ForegroundColor Red }
    Write-Host '（常见原因：目录里有程序正在占用；关掉其它 Psychostat 窗口/R 会话后重试）' -ForegroundColor DarkYellow
    exit 1
}
Write-Host '清理完成。R / Python 本体与你自己的数据都未改动。' -ForegroundColor Green
