# Psychostat 共享环境预检：三条分支（stats/CTT/IRT）统一调用。
# 用法：在启动器开头执行  . (Join-Path $PSScriptRoot 'psychostat_env.ps1')
#       $rscript = Initialize-PsychostatEnvironment    # 返回 Rscript.exe 完整路径
# 职责：清理 POSIX locale 变量（中文 R 安装路径下会导致 R 启动失败）；
#       优先从 D 盘定位 Rscript；将新增 R 包优先安装到 D 盘；必要时将 TEMP 重定向到 ASCII 安全目录；做一次 R 启动+临时文件写入自检。
#       另提供 Select-PsychostatFile：图形化"点选文件"对话框（不想手打路径的用户）。

# 通用文件选择弹窗：返回所选文件完整路径；用户取消或弹窗不可用时返回 $null（调用方回退到文本输入）。
function Select-PsychostatFile {
    param(
        [string]$Title = '选择文件',
        [string]$Filter = '支持的数据文件|*.csv;*.xlsx;*.xls;*.sav|CSV 文件|*.csv|Excel 文件|*.xlsx;*.xls|SPSS 文件|*.sav|所有文件|*.*'
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = $Title
        $dlg.Filter = $Filter
        $dlg.CheckFileExists = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    } catch { }
    return $null
}

function Get-PsychostatWritableDirectory {
    param([Parameter(Mandatory=$true)][string]$DName, [Parameter(Mandatory=$true)][string]$CName, [string]$DAlternate)
    $candidates = @()
    if (Test-Path -LiteralPath 'D:\') { $candidates += (Join-Path 'D:\' $DName); if ($DAlternate) { $candidates += $DAlternate } }
    if (Test-Path -LiteralPath 'C:\') { $candidates += (Join-Path 'C:\' $CName) }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA (Join-Path 'Psychostat' $CName)) }
    foreach ($candidate in $candidates) {
        try {
            New-Item -ItemType Directory -Force -Path $candidate -ErrorAction Stop | Out-Null
            $probe = Join-Path $candidate '.psychostat_write_probe'
            [IO.File]::WriteAllText($probe, 'ok', [Text.Encoding]::ASCII)
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $candidate
        } catch {
            # 目录可能已建出来但探测写入失败（权限/杀软/受限环境）：留下空壳会让人困惑，顺手清掉
            try {
                if ((Test-Path -LiteralPath $candidate) -and -not (Get-ChildItem -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }
    return $null
}

# ── 安装清单（供 scripts\uninstall_psychostat.ps1 做精确、安全的清理）─────────────
# 记录"这台机器上 Psychostat 装了什么、装在哪"。清单写在 %LOCALAPPDATA%\Psychostat\
# install_manifest.json，**不放进项目目录**：项目文件夹常被整体拷给同学或换机，
# 清单跟着走会指向错误路径。
# 有了它，清理脚本才能只删除本工具专属的目录（Psychostat-R-Library /
# Psychostat-Python-User / TEMP 重定向目录），而不去碰用户已有的 R / Python 环境，
# 也不去碰共享的 R / Python 用户库。
function Get-PsychostatInstallManifestPath {
    # 状态目录：默认 %LOCALAPPDATA%\Psychostat；可用环境变量 PSYCHOSTAT_STATE_DIR 覆盖
    # （便于自动化测试、便携安装，或 LOCALAPPDATA 不可写的受限环境）。
    $base = if ($env:PSYCHOSTAT_STATE_DIR) { $env:PSYCHOSTAT_STATE_DIR }
            elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Psychostat' }
            else { Join-Path $env:USERPROFILE '.psychostat' }
    return (Join-Path $base 'install_manifest.json')
}

function Update-PsychostatInstallManifest {
    param([hashtable]$Section)   # 形如 @{ r = @{ path = '…'; installed_by_us = $true } }
    # 记录失败绝不能影响分析流程：本函数吞掉所有异常。
    try {
        $path = Get-PsychostatInstallManifestPath
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) -ErrorAction Stop | Out-Null
        $manifest = @{}
        if (Test-Path -LiteralPath $path) {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($raw) { foreach ($p in ($raw | ConvertFrom-Json).PSObject.Properties) { $manifest[$p.Name] = $p.Value } }
        }
        if (-not $manifest.ContainsKey('schema')) { $manifest['schema'] = 1 }
        if (-not $manifest.ContainsKey('first_recorded')) { $manifest['first_recorded'] = (Get-Date).ToString('s') }
        $manifest['last_updated'] = (Get-Date).ToString('s')
        $manifest['project_dir'] = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        foreach ($k in $Section.Keys) {
            $existing = $manifest[$k]
            if ($existing -is [System.Management.Automation.PSCustomObject] -and $Section[$k] -is [hashtable]) {
                $merged = @{}                       # 浅合并：保留该节已有字段，只覆盖本次提供的键
                foreach ($p in $existing.PSObject.Properties) { $merged[$p.Name] = $p.Value }
                foreach ($p in $Section[$k].Keys) { $merged[$p] = $Section[$k][$p] }
                $manifest[$k] = $merged
            } else {
                $manifest[$k] = $Section[$k]
            }
        }
        Set-Content -LiteralPath $path -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding UTF8
    } catch { }
}

# ── 带进度/超时/卡死保护的下载 ────────────────────────────────────────────────
# 背景：原来用 Start-BitsTransfer（低优先级后台传输，卡住时无任何提示也无超时）与
# WebClient（无进度、无 stall 保护），一旦镜像慢，用户看到的就是"卡了几十分钟还没好"。
# 这里统一改成：显式 TLS1.2 + 每次读取超时（即卡死判定）+ 每 2 秒打印进度 + 不完整即失败。
function Save-PsychostatFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int]$StallSeconds = 30,
        # 慢源保护：连续 $SlowWindowSeconds 秒平均速度低于 $MinMBps 就放弃该源、让调用方换下一个镜像。
        # 只在非最后一次尝试时生效（-FinalAttempt）：全网都慢时宁可慢慢下完也不报错。
        [double]$MinMBps = 0.1,
        [int]$SlowWindowSeconds = 45,
        [switch]$FinalAttempt,
        [switch]$Quiet
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $part = "$Destination.part"
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    $slowAbort = $false
    try {
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = 30000
    $req.ReadWriteTimeout = ([Math]::Max($StallSeconds, 30)) * 1000
    $req.UserAgent = 'Psychostat/1.0 (Windows)'
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($part)
    $buf = New-Object byte[] 65536
    $done = 0; $sw = [Diagnostics.Stopwatch]::StartNew(); $lastTick = 0.0
    $winStart = 0.0; $winDone = 0
    try {
        while ($true) {
            $n = $in.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $out.Write($buf, 0, $n); $done += $n; $winDone += $n
            $el = $sw.Elapsed.TotalSeconds
            if (-not $Quiet -and ($el - $lastTick) -ge 2) {
                $lastTick = $el
                $spd = if ($el -gt 0) { $done / $el / 1MB } else { 0 }
                if ($total -gt 0) {
                    $eta = if ($spd -gt 0) { [int](($total - $done) / 1MB / $spd) } else { 0 }
                    Write-Host ("    已下载 {0:N1}/{1:N1} MB（{2}%，{3:N2} MB/s，剩余约 {4} 秒）" -f ($done/1MB), ($total/1MB), [int](100*$done/$total), $spd, $eta) -ForegroundColor DarkGray
                } else {
                    Write-Host ("    已下载 {0:N1} MB（{1:N2} MB/s）" -f ($done/1MB), $spd) -ForegroundColor DarkGray
                }
            }
            if (-not $FinalAttempt -and ($el - $winStart) -ge $SlowWindowSeconds) {
                $winSpd = $winDone / ($el - $winStart) / 1MB
                if ($winSpd -lt $MinMBps) {
                    $slowAbort = $true
                    throw ("该源速度过慢（近 {0} 秒平均 {1:N2} MB/s，低于 {2:N2} MB/s），换下一个镜像" -f $SlowWindowSeconds, $winSpd, $MinMBps)
                }
                $winStart = $el; $winDone = 0
            }
        }
    } finally {
        $out.Dispose(); $in.Dispose(); $resp.Dispose()
    }
    if ($total -gt 0 -and $done -lt $total) {
        throw "下载不完整（$done/$total 字节），已放弃该源"
    }
    Move-Item -LiteralPath $part -Destination $Destination -Force
    return $done
    } catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        if ($slowAbort) { throw }
        # 兜底：个别环境（老旧代理、安全软件拦截长连接）下 HttpWebRequest 会失败，
        # 退回 WebClient 的默认实现再试一次（没有进度显示，但比直接失败强）。
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'Psychostat/1.0 (Windows)')
            $wc.DownloadFile($Url, $Destination)
            return (Get-Item -LiteralPath $Destination).Length
        } catch {
            throw "下载失败：$($_.Exception.Message)"
        }
    }
}

# 短超时取回一个 http 文本页（用于列目录/探测镜像是否可达）
function Get-PsychostatHttpString {
    param([Parameter(Mandatory=$true)][string]$Url, [int]$TimeoutSec = 15)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = 'Psychostat/1.0 (Windows)'
    $resp = $req.GetResponse()
    try {
        $sr = New-Object IO.StreamReader($resp.GetResponseStream())
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $resp.Dispose() }
}

# ── R 包安装（共享给三个启动器与图形界面）──────────────────────────────────────
# 背景：此前四处调用都写死 repos='https://cloud.r-project.org'（境外官方源）。
# 国内访问该源经常只有几十 KB/s，而 psych/lavaan/mirt 及其依赖合计数百 MB，
# 于是出现"下载 2000 多秒还没装完/最后失败"。这里改为：
#   1) 国内镜像优先（清华 → 中科大 → 阿里云 → 官方源），逐个尝试，失败自动换源；
#   2) options(timeout) 放宽到 1800 秒，避免大包下载到一半被判超时；
#   3) Windows 下显式 type='binary'，直接装二进制包（不编译，不需要 Rtools）；
#   4) 逐个包安装并打印进度与耗时，不再"静默等待"；
#   5) 已装的包自动跳过，所以中断后重跑会接着装，不会从头再来；
#   6) 失败时给出可操作的原因与手动命令，而不是一句 "R packages missing"。
function Get-PsychostatPackageInstallCode {
    param([Parameter(Mandatory=$true)][string[]]$Packages)
    $pkgR = (($Packages | Where-Object { $_ }) | ForEach-Object { "'" + $_ + "'" }) -join ','
    $code = @"
local({
  pkgs <- c($pkgR)
  repos <- c('https://mirrors.tuna.tsinghua.edu.cn/CRAN',
             'https://mirrors.ustc.edu.cn/CRAN',
             'https://mirrors.aliyun.com/CRAN',
             'https://cloud.r-project.org')
  old_to <- getOption('timeout'); options(timeout = max(1800, old_to))
  if (.Platform`$OS.type == 'windows') options(pkgType = 'binary')
  t0 <- Sys.time()
  usecs <- function() as.numeric(difftime(Sys.time(), t0, units = 'secs'))
  need <- function() setdiff(pkgs, rownames(installed.packages()))
  miss <- need()
  if (!length(miss)) {
    cat('[R包] 所需 R 包均已安装，跳过下载（', paste(pkgs, collapse = ' '), '）\n', sep = '')
  } else {
    cat('[R包] 需要安装 ', length(miss), ' 个：', paste(miss, collapse = ' '), '\n', sep = '')
    # 镜像测速：慢但在走的源（如几十 KB/s）不会触发 install.packages 失败，却能把整次安装拖成
    # 20–30 分钟。先用各镜像都有、大小稳定的 PACKAGES.gz（约 1MB）实测速度，快的源优先、
    # 不通的排最后；实测结果打印出来，便于排错。
    options(timeout = min(60, getOption('timeout')))
    probe <- vapply(repos, function(rp) {
      tf <- tempfile(); sz <- 0; el <- 0
      try({
        tt <- system.time(suppressWarnings(download.file(file.path(rp, 'src', 'contrib', 'PACKAGES.gz'), tf, quiet = TRUE, mode = 'wb')))
        el <- tt[['elapsed']]; sz <- if (file.exists(tf)) file.size(tf) else 0
      }, silent = TRUE)
      unlink(tf)
      if (!is.finite(el) || el <= 0 || sz < 100e3) return(NA_real_)
      as.numeric(sz) / 1e6 / el
    }, numeric(1))
    options(timeout = max(1800, old_to))
    for (rp in names(probe)) {
      lbl <- sub('^https?://', '', rp); lbl <- sub('/CRAN$', '', lbl)
      cat(sprintf('[R包] 镜像测速 %s：%s\n', lbl, if (is.na(probe[[rp]])) '不可达，排到最后' else sprintf('%.2f MB/s', probe[[rp]])))
    }
    okm <- names(probe)[!is.na(probe)]
    repos <- c(okm[order(unlist(probe[okm]), decreasing = TRUE)], setdiff(repos, okm))
    cat('[R包] 按测速结果从快到慢依次使用镜像；单个包在一个源失败会自动换下一个源\n')
    failed <- character(0)
    for (i in seq_along(miss)) {
      p <- miss[i]
      cat(sprintf('[R包 %d/%d] %s …（已用 %d 秒）\n', i, length(miss), p, round(usecs())))
      ok <- FALSE
      for (rp in repos) {
        lbl <- sub('^https?://', '', rp); lbl <- sub('/CRAN$', '', lbl)
        cat('    源 ', lbl, ' …\n', sep = '')
        ts <- Sys.time()
        # dependencies = NA：只装 Depends/Imports/LinkingTo（运行必需）。TRUE 会把 Suggests
        # 全家桶也拖进来（psych 一个包就带出上百个），慢网络下时间是数倍，且我们用不到它们。
        try(install.packages(p, repos = rp, dependencies = NA, quiet = FALSE), silent = TRUE)
        if (requireNamespace(p, quietly = TRUE)) {
          cat(sprintf('    完成（本包用时 %d 秒）\n', round(as.numeric(difftime(Sys.time(), ts, units = 'secs')))))
          ok <- TRUE; break
        }
        cat('    该源未成功（网络慢或该源缺包），换下一个镜像\n')
      }
      if (!ok) failed <- c(failed, p)
    }
    still <- need()
    if (length(still)) {
      cat('\n[R包] 仍未安装：', paste(still, collapse = ' '), '\n', sep = '')
      cat('可能的原因与处理办法：\n')
      cat('  1) 网速慢或镜像临时不可达 → 换网络（如手机热点）后重新运行本工具；已装好的包不会重复下载。\n')
      cat('  2) 提示 “is not available (for R version …)” → 该 R 版本暂时没有 Windows 二进制包（常见于刚发布的新版本），建议改装 R 4.4.x / 4.5.x。\n')
      cat('  3) 手动安装（在 PowerShell 里执行，把 <包名> 换成上面的包名）：\n')
      cat('     Rscript -e install.packages(\'<包名>\',repos=\'https://mirrors.tuna.tsinghua.edu.cn/CRAN\')\n')
      stop('R packages missing: ', paste(still, collapse = ', '))
    }
    cat(sprintf('[R包] 全部就绪，用时 %d 秒\n', round(usecs())))
  }
})
"@
    return $code
}

# 把上面的 R 代码写到临时脚本文件，返回文件路径。
# 为什么不继续用 Rscript -e：多行代码经 PowerShell 传给原生程序时会被拆坏
# （实测报 "unexpected end of input"），而 R 包安装逻辑必须多行才好读、好排错。
# 文件编码为 UTF-8 无 BOM，与 scripts/ 下的管线脚本保持一致（R ≥ 4.2 原生即 UTF-8）。
function Get-PsychostatPackageInstallScript {
    param([Parameter(Mandatory=$true)][string[]]$Packages, [string]$Path)
    if (-not $Path) { $Path = Join-Path ([IO.Path]::GetTempPath()) 'psychostat_install_packages.R' }
    $code = Get-PsychostatPackageInstallCode -Packages $Packages
    [IO.File]::WriteAllText($Path, $code, (New-Object System.Text.UTF8Encoding($false)))
    return $Path
}

# ── Python 自动安装（仅交互模式、用户确认后执行）────────────────────────────────
# 从国内镜像（npmmirror/华为云）与 python.org 下载官方安装器，静默安装到
# D:\Python312（或 %LOCALAPPDATA%\Programs\Python\Python312），无需管理员权限。
# ── 安装包信任校验（安全）──────────────────────────────────────────────────
# 背景：R / Python 安装包被下载到 %TEMP% 后是**静默执行**的。原先缺少任何校验——
# 若某个镜像被投毒或劫持，就会在本机执行一个未经校验的安装程序。
# 官方安装包都带有效数字签名，因此"明确未签名 / 签名与内容不匹配"只可能是被替换过的文件 → 中止。
# 例外：UnknownError（如离线时无法构建完整信任链）**不中止**，只警告，
# 避免把网络受限的正常用户挡在自动安装之外。
function Assert-PsychostatInstallerTrusted([string]$Path, [string]$OfficialUrl) {
    $sig = $null
    try { $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop } catch { }
    if ($null -eq $sig -or -not $sig.Status) {
        Write-Host '  无法读取安装包签名信息，将继续安装（建议事后核对来源）。' -ForegroundColor DarkYellow
        return $true
    }
    switch ([string]$sig.Status) {
        'Valid' {
            $who = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '（未取到发布者）' }
            Write-Host ("  安装包签名校验通过：{0}" -f $who) -ForegroundColor DarkGreen
            return $true
        }
        'NotSigned' {
            Write-Host '  安装包**没有数字签名**——官方安装包应当有签名，可能已被替换。已中止安装。' -ForegroundColor Red
            Write-Host ("    请改为到官网手动下载安装：{0}" -f $OfficialUrl) -ForegroundColor Yellow
            return $false
        }
        'HashMismatch' {
            Write-Host '  安装包的数字签名与文件内容**不匹配**（文件可能被篡改）。已中止安装。' -ForegroundColor Red
            Write-Host ("    请改为到官网手动下载安装：{0}" -f $OfficialUrl) -ForegroundColor Yellow
            return $false
        }
        default {
            Write-Host ("  安装包签名状态：{0}（不中止；若安装失败请改用手动安装：{1}）" -f $sig.Status, $OfficialUrl) -ForegroundColor DarkYellow
            return $true
        }
    }
}

# 返回新安装的 python.exe 路径；失败返回 $null。
function Install-PsychostatPython {
    $version = '3.12.8'
    $urls = @(
        "https://registry.npmmirror.com/-/binary/python/$version/python-$version-amd64.exe",
        "https://mirrors.huaweicloud.com/python/$version/python-$version-amd64.exe",
        "https://www.python.org/ftp/python/$version/python-$version-amd64.exe")
    $installBase = $null
    foreach ($cand in @('D:\', (Join-Path $env:LOCALAPPDATA 'Programs\Python'))) {
        try {
            New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            $probe = Join-Path $cand '.psychostat_probe'
            [IO.File]::WriteAllText($probe, 'ok'); Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            $installBase = $cand; break
        } catch { }
    }
    if (-not $installBase) { Write-Host '找不到可写安装位置。请手动从 python.org 安装 Python。' -ForegroundColor Yellow; return $null }
    $targetDir = if ($installBase -eq 'D:\') { 'D:\Python312' } else { Join-Path $installBase 'Python312' }
    $dest = Join-Path $env:TEMP "python-$version-amd64.exe"
    $downloaded = $false
    for ($ui = 0; $ui -lt $urls.Count; $ui++) {
        $u = $urls[$ui]
        Write-Host "正在下载 Python $version（约 25 MB，来源：$($u -replace '^https?://','')）..." -ForegroundColor Cyan
        try {
            $bytes = Save-PsychostatFile -Url $u -Destination $dest -StallSeconds 30 -FinalAttempt:($ui -eq $urls.Count - 1)
            if ($bytes -lt 15MB) { throw "只下到 $([int]($bytes/1MB)) MB，不像是安装包（可能是镜像错误页）" }
            $downloaded = $true; break
        } catch {
            Write-Host "  该源不可用或过慢（$($_.Exception.Message)），尝试下一镜像..." -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $downloaded) { Write-Host 'Python 下载失败（网络问题）。请手动从 python.org 安装。' -ForegroundColor Red; return $null }
    if (-not (Assert-PsychostatInstallerTrusted -Path $dest -OfficialUrl 'https://www.python.org/downloads/windows/')) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return $null }
    Write-Host "正在静默安装 Python 到 $targetDir（约 1–2 分钟，请勿关闭窗口）..." -ForegroundColor Cyan
    try {
        $p = Start-Process -FilePath $dest -ArgumentList @('/quiet', 'InstallAllUsers=0', "TargetDir=$targetDir",
            'Include_launcher=0', 'Include_test=0', 'Include_doc=0', 'Include_tcltk=0', 'Shortcuts=0',
            'AssociateFiles=0', 'PrependPath=0', 'Include_pip=1') -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-Host "安装器退出码 $($p.ExitCode)（0 为成功）。" -ForegroundColor DarkYellow }
    } catch { Write-Host "安装进程启动失败：$($_.Exception.Message)" -ForegroundColor Red }
    $py = Join-Path $targetDir 'python.exe'
    if (Test-Path -LiteralPath $py) { Write-Host "Python 安装完成：$py" -ForegroundColor Green; return $py }
    Write-Host 'Python 安装未成功；请手动从 python.org 安装（安装时保持默认勾选 pip）。' -ForegroundColor Yellow
    return $null
}

function Initialize-PsychostatPythonEnvironment {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [switch]$Silent)
    # Python 仅用于 Word 结果报告；不自动下载安装 Python 本体。
    # 作用域级错误容忍：调用方可能是 $ErrorActionPreference='Stop'（启动器），
    # 原生工具（python/pip）的 stderr 不能让它整体崩溃；缺依赖应走自动安装或优雅降级。
    $ErrorActionPreference = 'Continue'
    # 本次会话是否由本工具安装了 Python（用于安装清单，供清理脚本提示卸载 Python 本体）
    $installedPyByUs = $false
    $pythonCandidates = @()
    if (Test-Path -LiteralPath 'D:\') {
        $dPython = Get-ChildItem -Path 'D:\Python*\python.exe','D:\*\Python*\python.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName
        $pythonCandidates += $dPython
    }
    $pycmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pycmd) { $pythonCandidates += $pycmd.Source }
    $pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        $pyPath = (& $pyLauncher.Source -c 'import sys;print(sys.executable)' 2>$null | Select-Object -Last 1)
        if ($pyPath) { $pythonCandidates += $pyPath.Trim() }
    }
    # 候选质检：只接受 ≥3.9 的独立 Python。捆绑/过老的解释器（如 SPSS 内置 Python 3.8）
    # 没有 pandas/python-docx 的 wheel，强行安装只会失败——此类候选应被剔除并改走自动安装。
    $python = $null; $skipped = @()
    foreach ($cand in ($pythonCandidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $cand)) { continue }
        $verOut = & $cand -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -ne 0) { $skipped += $cand; continue }
        $verText = (($verOut | Select-Object -Last 1) -as [string]).Trim()
        $v = $null; if ($verText -match '^(\d+)\.(\d+)$') { $v = [version]::new([int]$Matches[1], [int]$Matches[2]) }
        if ($v -and $v -ge [version]'3.9') { $python = $cand; break }
        $skipped += $cand
    }
    if (-not $python -and -not $Silent -and $skipped.Count -gt 0) {
        Write-Host "  已忽略不兼容的 Python：$($skipped -join '；')(版本过旧或不可用，无法安装 pandas/python-docx)。" -ForegroundColor DarkYellow
    }
    if (-not $python) {
        # 未找到合适 Python：交互模式询问后自动下载安装（仅 Word 结果报告需要；静默/AI 模式不自动装）。
        if (-not $Silent -and [Environment]::UserInteractive) {
            Write-Host "`n未检测到可用的 Python。Python 用于生成 Word 结果报告（推荐安装，以发挥全部功能）。" -ForegroundColor Yellow
            $yn = Read-Host '是否自动下载并安装独立的 Python 3.12（约 25 MB，来自国内镜像/python.org，无需管理员权限）？[Y/N，回车=N]'
            if ($yn -match '^[Yy]') {
                $auto = Install-PsychostatPython
                if ($auto -and (Test-Path -LiteralPath $auto)) {
                    $python = $auto; $installedPyByUs = $true
                    Write-Host "Python 就绪：$python（首次使用将自动安装 pandas/python-docx）..." -ForegroundColor Cyan
                }
            }
        }
        if (-not $python) {
            return [pscustomobject]@{ Available=$false; Ready=$false; Path=$null; Note='未找到可用的 Python；分析与 CSV/图/Markdown 报告仍可完成，Word 结果报告已跳过。如需 Word 报告：重新运行并输入 Y 自动安装独立 Python，或手动从 python.org 安装 3.12+。' }
        }
    }
    # 依赖探测/安装目录必须在**第一次探测之前**就定下来：
    # 若依赖由本工具装进专属目录（Psychostat-Python-User），而 PYTHONUSERBASE 只在安装分支里
    # 设置，那么每次新进程的首轮探测都看不到它们 → 每次都重跑一遍 pip，且离线时会因为
    # "安装失败" 而把其实完好的依赖判为未就绪、直接丢掉 Word 报告。
    $pythonFolder = Split-Path -Parent $python
    $userBase = Get-PsychostatWritableDirectory 'Psychostat-Python-User' 'Psychostat-Python-User' (Join-Path $pythonFolder 'Psychostat-Python-User')
    if ($userBase) { $env:PYTHONUSERBASE = $userBase }
    $probe = & $python -X utf8 -c "import pandas,docx;print('PSYCHOSTAT_REPORT_PYTHON_OK')" 2>$null
    if ($LASTEXITCODE -eq 0 -and "$probe" -match 'PSYCHOSTAT_REPORT_PYTHON_OK') {
        $ready = [pscustomobject]@{ Available=$true; Ready=$true; Path=$python; Note='Python 与 结果报告依赖已就绪。' }
        # 依赖已就绪：记录 Python 与依赖目录（PYTHONUSERBASE 未设时依赖在共享用户目录，清理脚本不会自动删）
        $pySection = @{ path = $python; ready = $true
                        user_base = $(if ($env:PYTHONUSERBASE) { $env:PYTHONUSERBASE } else { 'shared_user_site' }) }
        if ($installedPyByUs) { $pySection['installed_by_us'] = $true }
        Update-PsychostatInstallManifest @{ python = $pySection }
        return $ready
    }
    if (-not $Silent) { Write-Host '检测到 Python，但缺少 Word 结果报告依赖；正在安装 pandas 和 python-docx（约 1 分钟，请勿关闭窗口）...' -ForegroundColor Cyan }
    $requirements = Join-Path $ProjectRoot 'requirements.txt'
    # pip 走国内镜像优先（清华 PyPI），失败自动回退官方源；非静默时流式显示进度，避免"看似卡死"。
    $installExit = 1; $installLog = ''
    foreach ($mirror in @('https://pypi.tuna.tsinghua.edu.cn/simple', 'https://pypi.org/simple')) {
        $label = ($mirror -replace '^https?://', '' -replace '/simple$', '')
        if (-not $Silent) { Write-Host "  正在从 $label 安装（若网络慢请耐心等待）..." -ForegroundColor DarkCyan }
        if ($Silent) {
            $installLog = & $python -X utf8 -m pip --disable-pip-version-check install --user -r $requirements -i $mirror 2>&1
            $installExit = $LASTEXITCODE
        } else {
            & $python -X utf8 -m pip --disable-pip-version-check install --user -r $requirements -i $mirror 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            $installExit = $LASTEXITCODE
        }
        if ($installExit -eq 0) { break }
        if (-not $Silent) { Write-Host "  该源不可用，尝试官方源..." -ForegroundColor DarkYellow }
    }
    $probe = & $python -X utf8 -c "import pandas,docx;print('PSYCHOSTAT_REPORT_PYTHON_OK')" 2>$null
    if ($installExit -eq 0 -and $LASTEXITCODE -eq 0 -and "$probe" -match 'PSYCHOSTAT_REPORT_PYTHON_OK') {
        $where = if ($userBase) { "（依赖目录：$userBase）" } else { '' }
        # 记录：依赖由我们安装到哪个目录（若为专属 Psychostat-Python-User，清理脚本可直接删除）
        $pySection = @{ path = $python; ready = $true; deps_installed_by_us = $true
                        user_base = $(if ($userBase) { $userBase } else { 'shared_user_site' }) }
        if ($installedPyByUs) { $pySection['installed_by_us'] = $true }
        Update-PsychostatInstallManifest @{ python = $pySection }
        return [pscustomobject]@{ Available=$true; Ready=$true; Path=$python; Note="Python 结果报告依赖已安装$where。" }
    }
    Update-PsychostatInstallManifest @{ python = @{ path = $python; ready = $false; user_base = $(if ($userBase) { $userBase } else { 'shared_user_site' }) } }
    return [pscustomobject]@{ Available=$true; Ready=$false; Path=$python; Note=('Python 依赖安装失败；分析结果不受影响，Word 结果报告将跳过。' + [Environment]::NewLine + ($installLog | Out-String).Trim()) }
}
# Pick the newest R installation by numeric version (R-4.5.10 > R-4.5.9; string sort would pick 4.5.9).
# Empty candidate list is normal (no R on that drive): return $null instead of throwing.
function Select-HighestRVersion {
    param([string[]]$Candidates)
    if (-not $Candidates -or @($Candidates).Count -eq 0) { return $null }
    $parsed = foreach ($c in $Candidates) {
        $v = $null
        if ($c -match '\\R-([0-9]+(?:\.[0-9]+){1,2})\\bin\\Rscript\.exe$') {
            $parts = $Matches[1].Split('.')
            $v = [version]::new([int]$parts[0], [int]$parts[1], $(if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }))
        }
        [pscustomobject]@{ Path = $c; Ver = $v }
    }
    ($parsed | Where-Object { $_.Ver } | Sort-Object Ver -Descending | Select-Object -First 1).Path
}

# ── R 自动安装（仅交互模式、用户确认后执行）───────────────────────────────────────
# 从 CRAN 镜像（清华优先）下载官方 Windows 安装器并静默安装到用户可写目录，
# 无需管理员权限。返回新安装的 Rscript.exe 路径；失败返回 $null。
function Install-PsychostatR {
    # 国内镜像优先；列目录也用带超时的请求，避免某个镜像不通时干等
    $mirrors = @(
        'https://mirrors.tuna.tsinghua.edu.cn/CRAN',
        'https://mirrors.ustc.edu.cn/CRAN',
        'https://mirrors.aliyun.com/CRAN',
        'https://cloud.r-project.org')
    $version = $null
    foreach ($m in $mirrors) {
        try {
            $base = "$m/bin/windows/base/"
            $html = Get-PsychostatHttpString -Url $base -TimeoutSec 15
            $all = @([regex]::Matches($html, 'R-([0-9]+\.[0-9]+\.[0-9]+)-win\.exe') | ForEach-Object { $_.Groups[1].Value } |
                Sort-Object { [version]$_ } -Descending)
            if ($all.Count -gt 0) { $version = $all[0]; break }
        } catch { }
    }
    if (-not $version) {
        Write-Host '无法访问 CRAN 镜像（网络或 TLS 问题）。请手动从 https://cloud.r-project.org 下载安装 R。' -ForegroundColor Yellow
        return $null
    }
    $installRoot = $null
    foreach ($cand in @('D:\R', (Join-Path $env:LOCALAPPDATA 'Programs\R'))) {
        try {
            New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            $probe = Join-Path $cand '.psychostat_probe'
            [IO.File]::WriteAllText($probe, 'ok'); Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            $installRoot = $cand; break
        } catch { }
    }
    if (-not $installRoot) {
        Write-Host '找不到可写的安装位置（D:\R 与用户目录均不可写）。请手动安装 R。' -ForegroundColor Yellow
        return $null
    }
    $installDir = Join-Path $installRoot "R-$version"
    $dest = Join-Path $env:TEMP "R-$version-win.exe"
    Write-Host "正在下载 R $version（约 100 MB，视网速需 1–10 分钟；下面每 2 秒刷新一次进度）..." -ForegroundColor Cyan
    $downloaded = $false
    for ($mi = 0; $mi -lt $mirrors.Count; $mi++) {
        $m = $mirrors[$mi]
        $exeUrl = "$m/bin/windows/base/R-$version-win.exe"
        Write-Host "  来源：$($m -replace '^https?://','')" -ForegroundColor DarkCyan
        try {
            $bytes = Save-PsychostatFile -Url $exeUrl -Destination $dest -StallSeconds 30 -FinalAttempt:($mi -eq $mirrors.Count - 1)
            if ($bytes -lt 50MB) { throw "只下到 $([int]($bytes/1MB)) MB，不像是安装包（可能是镜像错误页）" }
            $downloaded = $true; break
        } catch {
            Write-Host "  该源不可用或过慢（$($_.Exception.Message)），换下一个镜像..." -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $downloaded) { Write-Host '所有镜像都下载失败，请检查网络后重试，或按提示手动安装 R。' -ForegroundColor Red; return $null }
    if (-not (Assert-PsychostatInstallerTrusted -Path $dest -OfficialUrl 'https://cloud.r-project.org/bin/windows/base/')) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return $null }
    Write-Host "正在静默安装到 $installDir（约 1–3 分钟，请勿关闭窗口）..." -ForegroundColor Cyan
    try {
        $p = Start-Process -FilePath $dest -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$installDir`"") -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-Host "安装器退出码 $($p.ExitCode)（0 为成功）。" -ForegroundColor DarkYellow }
    } catch { Write-Host "安装进程启动失败：$($_.Exception.Message)" -ForegroundColor Red }
    $rs = Join-Path $installDir 'bin\Rscript.exe'
    if (Test-Path -LiteralPath $rs) { Write-Host "R $version 安装完成：$rs" -ForegroundColor Green; return $rs }
    Write-Host 'R 未安装成功（个别环境需要管理员权限的安装器）；请手动安装后重试。' -ForegroundColor Yellow
    return $null
}

function Initialize-PsychostatEnvironment {
    param([switch]$AllowAutoInstall)
    # 作用域级错误容忍：调用方可能是 $ErrorActionPreference='Stop'（启动器）；
    # 本函数内所有原生工具调用（Rscript/python）的 stderr 不应导致整体崩溃。
    $ErrorActionPreference = 'Continue'
    # 本次会话是否由本工具安装了 R（用于安装清单，供清理脚本判断能否提示卸载 R 本体）
    $installedRByUs = $false
    # 1) locale：LANG/LC_* 泄漏进会话时，非 ASCII 安装路径的 R 会报 "compiler 命名空间不可用"
    Remove-Item Env:LANG, Env:LC_ALL, Env:LC_CTYPE -ErrorAction SilentlyContinue

    # 2) 定位 Rscript：先找免安装全家桶自带的 R，再找 D 盘（用户首选），
    #    然后 PATH/注册表，最后才找 C 盘。
    $rscript = $null
    # 免安装版把 R 放在 D:\Psychostat-R；该名字不含版本号，不会被下面的 R-* 通配匹配到，
    # 必须显式列出（否则解压即用的包会因为"找不到 R"而触发自动安装流程）。
    $bundleR = 'D:\Psychostat-R\bin\Rscript.exe'
    if (Test-Path -LiteralPath $bundleR) { $rscript = $bundleR }
    if (-not $rscript -and (Test-Path -LiteralPath 'D:\')) {
        $dCandidate = Select-HighestRVersion @(Get-ChildItem -Path 'D:\R-*\bin\Rscript.exe','D:\*\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        if ($dCandidate) { $rscript = $dCandidate }
    }
    if (-not $rscript) {
        $cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
        if ($cmd) { $rscript = $cmd.Source }
    }
    if (-not $rscript) {
        foreach ($hive in 'HKLM:\SOFTWARE\R-core\R', 'HKCU:\SOFTWARE\R-core\R') {
            $reg = Get-ItemProperty $hive -ErrorAction SilentlyContinue
            if ($reg -and $reg.InstallPath) {
                $cand = Join-Path $reg.InstallPath 'bin\Rscript.exe'
                if (Test-Path -LiteralPath $cand) { $rscript = $cand; break }
            }
        }
    }
    if (-not $rscript) {
        $cand = Select-HighestRVersion @(Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe','C:\R\*\bin\Rscript.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        if ($cand) { $rscript = $cand }
    }
    if (-not $rscript) {
        if ($AllowAutoInstall -and [Environment]::UserInteractive) {
            Write-Host "`n未检测到 R。Psychostat 的统计分析需要 R（开源免费）。" -ForegroundColor Yellow
            $yn = Read-Host '是否现在自动下载并安装 R（约 100 MB，来自清华/官方 CRAN 镜像，无需管理员权限）？[Y/N，回车=N]'
            if ($yn -match '^[Yy]') {
                $auto = Install-PsychostatR
                if ($auto -and (Test-Path -LiteralPath $auto)) { $rscript = $auto; $installedRByUs = $true }
            }
        }
    }
    if (-not $rscript) { throw '未找到 Rscript.exe。Psychostat 的分析需要 R：请从 https://cloud.r-project.org 安装，优先放在 D:\R\R-x.y.z；仅当 D 盘不可用时再安装到 C:\Program Files\R。安装后重新双击启动器。' }

    # 3) 缺失 R 包优先写入 D 盘，D 盘不可写时再退到 C 盘；不修改 R 的系统安装目录。
    $rBase = Split-Path (Split-Path (Split-Path $rscript -Parent) -Parent) -Parent
    $rLibrary = Get-PsychostatWritableDirectory 'Psychostat-R-Library' 'Psychostat-R-Library' (Join-Path $rBase 'Psychostat-R-Library')
    if ($rLibrary) { $env:R_LIBS_USER = $rLibrary }
    else { Write-Host '提示：未能创建 Psychostat 专属 R 包目录，本次新增的 R 包会装进共享的用户库（清理时无法自动区分，需手动处理）。' -ForegroundColor DarkYellow }
    # 4) TEMP 含非 ASCII（如中文用户名）时重定向到 ASCII 目录，避免个别 R 包安装/临时写入失败
    $tmp = [IO.Path]::GetTempPath()
    if ($tmp -match '[^\x00-\x7F]') {
        $alt = Join-Path $env:SystemDrive 'PsychostatTemp'
        try {
            New-Item -ItemType Directory -Force -Path $alt | Out-Null
            $probe = Join-Path $alt 'writable.txt'
            [IO.File]::WriteAllText($probe, 'ok'); Remove-Item $probe -ErrorAction SilentlyContinue
            $env:TEMP = $alt; $env:TMP = $alt
        } catch { }
    }

    # 5) R 自检：能启动、能写临时文件（在 R 自己的 tempdir 内完成，避免跨进程路径问题）
    $out = & $rscript --vanilla -e "cat('RSTART_OK'); cat(' VERSION=[', R.version.string, ']'); tf <- file.path(tempdir(),'psychostat_probe.txt'); writeLines('ok', tf, useBytes=TRUE); cat(' WRITE_OK=', file.exists(tf))" 2>&1
    if ($LASTEXITCODE -ne 0 -or "$out" -notmatch 'RSTART_OK') {
        throw "R 预检失败（Rscript 启动异常）：$($out | Out-String)"
    }
    if ("$out" -notmatch 'WRITE_OK=\s*TRUE') { throw "R 预检失败：无法写入临时文件（检查 TEMP 目录权限）：$($out | Out-String)" }
    # 6) 记录安装清单：清理脚本据此只删除本工具专属目录（见 scripts\uninstall_psychostat.ps1）
    $rVersion = if ("$out" -match 'VERSION=\[([^\]]*)\]') { $Matches[1].Trim() } else { $null }
    $rSection = @{
        path                          = $rscript
        version                       = $rVersion
        package_library               = $(if ($rLibrary) { $rLibrary } else { 'shared_user_library' })
        package_library_is_dedicated  = [bool]($rLibrary -and ($rLibrary -match 'Psychostat-R-Library$'))
    }
    # 仅在"本次确实由我们安装"时写入 installed_by_us = true；否则保持既有值/缺省（缺省视为不是我们装的，最安全）
    if ($installedRByUs) { $rSection['installed_by_us'] = $true }
    $tempRedirect = if ($env:TEMP -and ($env:TEMP -match 'PsychostatTemp$')) { $env:TEMP } else { $null }
    Update-PsychostatInstallManifest @{ r = $rSection; temp = @{ redirect_dir = $tempRedirect } }
    return $rscript
}

# ─────────────────────────────────────────────────────────────────────────────
# 启动器公共件（2026-09-19 由三个启动器合并而来；三个启动器都已 dot-source 本文件）
# 背景：这 7 个函数原先在 run_stats / run_ctt / run_irt 里各写一份（合计 18 处），已发生行为漂移——
#       最典型的是 Format-Fatal 只加在 IRT 里，于是 CTT 与心理统计分支的准确提示会被
#       Translate-RFailure 翻成"R 分析未完成…"这类没有信息量的套话。
# 现在的分工：**逻辑在这里（一份），分支专属的匹配模式与兜底文案留在各启动器里（作为数据）**。
# 因此控制台文案、静默 JSON 的事件名与字段结构均保持原样。
# ─────────────────────────────────────────────────────────────────────────────

# Write-Stage 的分支前缀：各启动器在 dot-source 之后覆盖（含原有的换行/括号写法，保证输出逐字不变）
$script:PsychostatStagePrefix = 'Psychostat '
function Write-Stage($Message,$Color='Cyan'){ if(-not $Silent){ Write-Host "$script:PsychostatStagePrefix$Message" -ForegroundColor $Color } }

function Write-JsonLog($Event,$Data=$null){if($Silent){Write-Output ([ordered]@{event=$Event;timestamp=(Get-Date).ToString('o');data=$Data}|ConvertTo-Json -Compress -Depth 10)}}

function Stop-Friendly($Message,$Raw=''){if($Silent){$x=[ordered]@{message=$Message};if($Verbose -and $Raw){$x.raw_error=$Raw};Write-JsonLog 'error' $x}else{Write-Host "`n[分析未完成] $Message" -ForegroundColor Red;if($Verbose -and $Raw){Write-Host "`n[原始诊断日志]`n$Raw" -ForegroundColor DarkGray}else{Write-Host '如需技术诊断，请在命令末尾加入 -Verbose。' -ForegroundColor DarkYellow}};exit 1}

# 自带编码器，不再依赖调用方的 $utf8（原先三个启动器各自持有该变量，是隐式耦合）
function ConvertTo-Utf8Hex($Text){$enc=New-Object System.Text.UTF8Encoding($false);(($enc.GetBytes([IO.Path]::GetFullPath($Text))|ForEach-Object{$_.ToString('X2')})-join'')}

function Resolve-ExistingPath($Path,$Name){if(-not $Path){return $null};$p=if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path (Get-Location).Path $Path};if(-not(Test-Path -LiteralPath $p)){Stop-Friendly "找不到$Name：$Path"};[IO.Path]::GetFullPath($p)}

# 中文原样透传、英文才翻译、译文是通用兜底时回退原文（原先只在 IRT 里，故只有 IRT 受益）
function Format-Fatal($Message){
  $m="$Message"
  if($m -match '[\u4e00-\u9fff]'){return $m}
  $t=Translate-RFailure $m
  if($t -like 'R 分析未完成*'){return $m}
  return $t
}

# 三分支共有的失败模式（原先在三份表里各写一遍，内容互有出入）
function Get-PsychostatCommonRFailure($Raw){
  if($Raw -match "package 'compiler' does not have a namespace"){return 'R 核心安装异常：compiler 命名空间不可用。请修复或重装 R 后再运行；这不是数据或模型错误。'}
  if($Raw -match 'loadNamespace|不存在叫.*程序包|package .* is not installed|there is no package called'){return '缺少 R 统计包：首次运行的自动安装可能未完成（需联网）。请联网后重新运行本启动器；若持续失败，手动执行 Rscript -e "install.packages(''onewaytests'')"（若提示其它包名则替换之）后重试。'}
  if($Raw -match 'Input file not found|input\.path'){return '找不到数据文件。请检查文件路径、名称和扩展名。'}
  return $null
}

# 从 R 的多行输出里挑出真正的错误行，供兜底文案附带——
# 否则用户只看到"R 分析未完成…"，而真正的原因（例如反向计分与编码范围不符）被埋在多行日志里。
function Get-PsychostatRFailureDetail($Raw){
  # 注意：PowerShell 会把原生命令的 stderr 包装成 "Rscript.exe : Error: …"，
  # 所以不能要求错误行以 Error 开头（早先写成 ^Error 便永远匹配不上）。
  foreach($line in @($Raw -split "`r?`n")){
    $t="$line".Trim()
    if($t -match 'Error(\s+in\s|[:：])'){
      $t = $t -replace '^[^:：]{1,40}[：:]\s*(?=Error)',''
      return $t
    }
  }
  return $null
}

# 每个启动器在 dot-source 之后设置：
#   $script:PsychostatRFailureTable   —— 分支专属模式表 @(@('正则','提示'), …)
#   $script:PsychostatRFailureFallback —— 分支专属兜底文案
$script:PsychostatRFailureTable = @()
$script:PsychostatRFailureFallback = 'R 分析未完成。请检查数据列名与配置；可使用 -Verbose 查看原始诊断。'
function Translate-RFailure($Raw){
  $m = Get-PsychostatCommonRFailure $Raw; if($m){ return $m }
  foreach($t in $script:PsychostatRFailureTable){ if($Raw -match $t[0]){ return $t[1] } }
  $fb = $script:PsychostatRFailureFallback
  $d = Get-PsychostatRFailureDetail $Raw
  if($d){ $fb = $fb + '（原始错误：' + $d + '）' }
  return $fb
}

# ── R 包清单的单一来源 ─────────────────────────────────────────────────────
# 原先同一份清单写在三个启动器、requirements.txt 注释与手册里（改一处漏三处）。
# 现在只在这里定义；启动器用 Get-PsychostatRequiredPackages -Branch <stats|ctt|irt> 取用。
$script:PsychostatPackages = [ordered]@{
    stats = @('yaml','jsonlite','car','emmeans','nortest','onewaytests','pwr','ggplot2','readxl','haven','MASS')
    ctt   = @('yaml','jsonlite','psych','lavaan','GPArotation','ggplot2','readxl','haven','MASS')
    irt   = @('yaml','jsonlite','mirt','psych','ggplot2','readxl','haven')
}
function Get-PsychostatRequiredPackages {
    param([string]$Branch='all')
    if ($Branch -eq 'all') { @($script:PsychostatPackages.Values | ForEach-Object { $_ } | Select-Object -Unique) }
    else { $script:PsychostatPackages[$Branch] }
}

# ── 交互式选择数据文件 / 菜单选择（原先在 CTT 与 IRT 启动器里各一份，仅标题不同）──
$script:PsychostatDataFileTitle = '选择数据文件'
function Select-DataFile{try{Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop;$d=New-Object System.Windows.Forms.OpenFileDialog;$d.Title=$script:PsychostatDataFileTitle;$d.Filter='支持的数据文件|*.csv;*.xlsx;*.xls;*.sav';if($d.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return $d.FileName}}catch{};while($true){$x=Read-Host '请输入数据文件完整路径';if((Test-Path -LiteralPath $x)-and([IO.Path]::GetExtension($x).ToLowerInvariant() -in '.csv','.xlsx','.xls','.sav')){return [IO.Path]::GetFullPath($x)};Write-Host '路径无效。请重新输入 CSV、Excel 或 SAV 文件。' -ForegroundColor Yellow}}
function Read-MenuChoice($Title,[string[]]$Options,[int]$Default){Write-Host "`n$Title" -ForegroundColor Cyan;for($i=0;$i -lt $Options.Count;$i++){Write-Host ('  {0}. {1}' -f($i+1),$Options[$i])};while($true){$x=Read-Host "请输入数字（直接回车默认 $Default）";if([string]::IsNullOrWhiteSpace($x)){return $Default};$n=0;if([int]::TryParse($x,[ref]$n)-and$n -ge 1-and$n -le $Options.Count){return $n};Write-Host '请输入列表中的数字。' -ForegroundColor Yellow}}
