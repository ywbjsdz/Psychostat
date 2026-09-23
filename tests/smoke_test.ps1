# Psychostat 冒烟自检：验证三分支均可正常启动并完成一次最小模拟分析。
# 用法：
#   .\tests\smoke_test.ps1            # 快速：仅心理统计（2 个方法，约 10–30 秒）
#   .\tests\smoke_test.ps1 -Full      # 完整：stats + CTT + IRT 各跑一次模拟
# 任一检查失败则以非零退出码结束；全部通过输出 "ALL CHECKS PASSED"。
param([switch]$Full)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$fail = 0
function Check($Name, $ScriptBlock) {
    try { & $ScriptBlock; Write-Host "[PASS] $Name" -ForegroundColor Green }
    catch { $script:fail++; Write-Host "[FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red }
}
function Get-LastCompleteDir($JsonLog) {
    $line = $JsonLog | Select-String 'complete' | Select-Object -Last 1
    if (-not $line) { throw 'complete 事件缺失' }
    $evt = $line.Line | ConvertFrom-Json
    if (-not $evt.data.result_dir) { throw 'complete 事件缺少 result_dir' }
    $evt.data.result_dir
}

# R 定位复用产品自身的四级发现逻辑（D 盘 → PATH → 注册表 → C 盘），
# 而不是只查 PATH：否则"D 盘装了 R 但没进 PATH"这一产品明确支持的场景下，
# 冒烟测试会误报"环境：Rscript 可用"失败（与 run_numeric_tests.ps1 保持一致）。
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'psychostat_env.ps1')
# 该函数会向管道写诊断文字，只有最后一项是 Rscript 路径：
# 取 [-1] 可避免诊断文字混入后续 `$log` 的 JSON 逐行解析。
$rscript = @(Initialize-PsychostatEnvironment)[-1]
# IRT 用例依赖 mirt，而 mirt 的 Imports 含 vegan（带编译 DLL）。在启用了 Windows 应用控制策略
# （Smart App Control / WDAC）的机器上，未签名的 vegan.dll 可能被拦截，此时**所有 IRT 用例都跑不了**。
# 那属于环境故障、不是代码回归，所以先探测一次；不可用就明确 SKIP 并说明原因，避免误报成回归。
$skipCount = 0
$irtReason = $null
if ($Full) {
    $probe = & $rscript --vanilla -e "cat(if (requireNamespace('mirt', quietly=TRUE)) 'IRT_OK' else 'IRT_BLOCKED')" 2>&1
    if (($probe -join ' ') -notmatch 'IRT_OK') {
        $irtReason = 'mirt 无法加载（常见原因：Windows 应用控制策略拦截 vegan.dll）'
    }
}
function CheckIrt($Name, $ScriptBlock) {
    if ($script:irtReason) { $script:skipCount++; Write-Host "[SKIP] $Name -- $($script:irtReason)" -ForegroundColor Yellow; return }
    Check $Name $ScriptBlock
}

# ---- 0. 编码约定（不需要 R，快速与完整模式都跑）----
# 约定来自 .gitattributes：*.ps1 必须是 UTF-8 且带**恰好一个** BOM（PowerShell 5.1 靠它正确解析中文；
# 缺 BOM 时 5.1 会按本地代码页解码，中文脚本会出现语法错误或乱码）；*.bat 必须是纯 ASCII
# （任何代码页下双击都不乱码）；*.R / *.py 源码必须**不带** BOM。
# 这一条是真实教训：任何编辑器重写 .ps1 时若丢掉 BOM，工具在 5.1 下直接坏掉，而其它检查都发现不了。
Check '文件编码约定（ps1 单 BOM / bat 纯 ASCII / R-py 无 BOM）' {
    $bad = @()
    Get-ChildItem -Path $root -Recurse -File -Include '*.ps1','*.bat','*.R','*.py' |
        Where-Object { $_.FullName -notmatch '\\outputs\\|\\notes\\|\\\.git\\|\\.piptmp\\' } |
        ForEach-Object {
            $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
            $rel = $_.FullName.Substring($root.Length + 1)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $doubleBom = ($bytes.Length -ge 6 -and $bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF)
            if ($_.Extension -ieq '.ps1') {
                if (-not $hasBom) { $bad += "$rel 缺少 UTF-8 BOM" }
                if ($doubleBom) { $bad += "$rel 出现双 BOM" }
            } elseif ($_.Extension -ieq '.bat') {
                $nonAscii = @($bytes | Where-Object { $_ -gt 0x7F })
                if ($nonAscii.Count -gt 0) { $bad += "$rel 含 $($nonAscii.Count) 个非 ASCII 字节（BAT 必须纯 ASCII）" }
            } else {
                if ($hasBom) { $bad += "$rel 不应带 BOM（R/Python 源码）" }
            }
        }
    if ($bad.Count -gt 0) { throw ($bad -join '；') }
}

Check '环境：Rscript 可用' { if (-not $rscript) { throw '未找到 Rscript.exe' } }

# ---- 1. 心理统计：静默跑 2 个方法 ----
Check '心理统计：静默分析（independent_t + one_way_anova）' {
    $log = & (Join-Path $root 'run_stats_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'examples\silent_stats_demo.json') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
    $dir = Get-LastCompleteDir $log
    if (-not (Test-Path (Join-Path $dir 'stats_report_zh.md'))) { throw '未生成 stats_report_zh.md' }
    # 编号契约：第 0 步的数据准备用 00_data_* 前缀，**不占方法编号**，
    # 因此用户选的第 1 个方法始终是 01_（既有的对照/脚本习惯不受影响）。
    $tFile = Join-Path $dir '01_independent_t_test.csv'
    if (-not (Test-Path $tFile)) { throw '未生成 01_independent_t_test.csv（编号契约：第 0 步不占方法编号）' }
    # 统计量断言：合并方差 t 行的 t 值与固定黄金值一致（口径同 test_numeric.R 第3节：
    # 同一份演示数据 seed=20260904、n_per_group=30、var.equal=TRUE，黄金值取自实跑产物 -2.09980635657743）。
    $tCsv = Import-Csv -Encoding UTF8 $tFile
    $tRow = @($tCsv | Where-Object { $_.assumption -eq '假定方差相等(合并t)' })
    if ($tRow.Count -ne 1) { throw "01_independent_t_test.csv 应恰有 1 行合并方差 t（实际 $($tRow.Count) 行）" }
    $tVal = [double]$tRow[0].t
    if ([math]::Abs($tVal - (-2.0998063566)) -gt 5e-7) { throw "独立样本t = $tVal，与黄金值 -2.0998063566 偏差超过 5e-7（seed=20260904 演示数据）" }
}

# ---- 2. CTT：静默模拟（EFA 全流程）----
if ($Full) {
    Check 'CTT：静默模拟（清洗+项目分析+EFA+CFA）' {
        $log = & (Join-Path $root 'run_ctt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'examples\ctt_silent_simulation.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $dir = Get-LastCompleteDir $log
        if (-not (Test-Path (Join-Path $dir 'run_log.txt'))) { throw '未生成 run_log.txt' }
        # 统计量断言：Total 行的 Cronbach's α（按列名 alpha 匹配，不依赖列位置）。
        # 黄金值来源：examples/ctt_silent_simulation.json（seed=20260826、n=480）实跑测得 0.808614858970603，
        # 与 test_numeric.R 第4节（ctt_config.yaml）黄金值 0.8086148590 在 10 位小数下一致。
        $relPath = Join-Path $dir '03_reliability.csv'
        if (-not (Test-Path $relPath)) { throw '未生成 03_reliability.csv' }
        $relRows = @(Import-Csv -Encoding UTF8 $relPath)
        $totalRow = @($relRows | Where-Object { $_.scale -eq 'Total' })
        if ($totalRow.Count -ne 1) { throw "03_reliability.csv 应恰有 1 行 Total（实际 $($totalRow.Count) 行）" }
        if (-not ($totalRow[0].PSObject.Properties.Name -contains 'alpha')) { throw "03_reliability.csv 缺少 alpha 列（按列名匹配；实际列：$($totalRow[0].PSObject.Properties.Name -join ',')" }
        $alphaVal = [double]$totalRow[0].alpha
        if ([math]::Abs($alphaVal - 0.8086148590) -gt 1e-8) { throw "总量表 alpha = $alphaVal，与黄金值 0.8086148590 偏差超过 1e-8（silent 配置 seed=20260826 实测值 0.808614858970603）" }
    }
}

# ---- 3. IRT：静默模拟（2PL + CIFA）----
if ($Full) {
    CheckIrt 'IRT：静默模拟（MIRT 2PL + CIFA）' {
        $log = & (Join-Path $root 'run_irt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'examples\silent_mirt_2pl_cifa_simulation.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $dir = Get-LastCompleteDir $log
        if (-not (Get-ChildItem -Path $dir -Filter '*config_snapshot*' -File)) { throw '结果目录缺少 config_snapshot*' }
        if (-not (Get-ChildItem -Path $dir -Filter '*report_zh.md' -File)) { throw '结果目录缺少报告 md' }
    }
}

# ---- 3b. 单维 GPCM 的题目参数表自洽（仅 -Full）----
# 为什么单独守这一条：GPCM 在 mirt 的 coef() 里除 a1..aD 外还会带回**类别乘子列 ak0..ak4**
# （取值 0,1,2,3,4）。早先流水线用 grep("^a") 取判别力列，把 ak* 也算了进去，于是
# MDISC = sqrt(Σaⱼ² + Σak_k²)（单维 GPCM 实测 5.536，而该题 a 只有 0.805），
# 连带 b_d* 被同一因子整体压错、Primary_dimension 还会输出 "ak4" 这种不存在的维度。
# 这里用「MDISC 必须等于 sqrt(Σaⱼ²)」这一表内恒等式兜住整类错误。
if ($Full) {
    CheckIrt 'IRT：单维 GPCM 参数表（MDISC = sqrt(Σa²)，ak* 不得混入）' {
        $log = & (Join-Path $root 'run_irt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'tests\e2e_gpcm.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $dir = Get-LastCompleteDir $log
        $f = Get-ChildItem -Path $dir -Filter '*item_parameters.csv' -File | Select-Object -First 1
        if (-not $f) { throw '结果目录缺少 item_parameters.csv' }
        $pars = @(Import-Csv -Encoding UTF8 $f.FullName)
        if (-not $pars.Count) { throw 'item_parameters.csv 没有数据行' }
        $cols = @($pars[0].PSObject.Properties.Name)
        $aCols = @($cols | Where-Object { $_ -match '^a[0-9]+$' })
        $bCols = @($cols | Where-Object { $_ -match '^b_d[0-9]+$' })
        if ($aCols.Count -ne 1) { throw "单维 GPCM 的判别力列应恰为 1 个（a1），实际：$($aCols -join ',')" }
        if ($aCols[0] -ne 'a1') { throw "判别力列应为 a1，实际 $($aCols[0])" }
        if ($bCols.Count -ne 4) { throw "1–5 计分应有 4 个台阶列 b_d1..b_d4，实际：$($bCols -join ',')" }
        if ($cols -contains 'b_d0') { throw '不应出现 b_d0（参考类别不产生台阶难度）' }
        foreach ($r in $pars) {
            $ss = 0.0; foreach ($c in $aCols) { $ss += [double]$r.$c * [double]$r.$c }
            $want = [math]::Sqrt($ss)
            if ([math]::Abs([double]$r.MDISC - $want) -gt 1e-8 * [math]::Max(1.0, $want)) {
                throw "题目 $($r.Item) 的 MDISC = $($r.MDISC)，但 sqrt(Σa²) = $want —— GPCM 的类别乘子列 ak* 疑似又混进了判别力列"
            }
            foreach ($c in $bCols) {
                # 注意：PowerShell 5.1 跑在 .NET Framework 上，[double] 没有 IsFinite（那是 .NET Core 2.1+ 才有的），
                # 只有 IsNaN / IsInfinity —— 早先写成 IsFinite 会让这条自检自己抛方法调用异常。
                $bv = [double]$r.$c
                if ([double]::IsNaN($bv) -or [double]::IsInfinity($bv)) { throw "题目 $($r.Item) 的 $c 不是有限值（$($r.$c)）" }
            }
        }
    }
}

# ---- 4. 数值回归测试（仅 -Full；条数以 PASS_COUNT 输出为准）----
if ($Full) {
    Check '数值回归测试（test_numeric.R）' {
        & (Join-Path $root 'tests\run_numeric_tests.ps1')
        if ($LASTEXITCODE -ne 0) { throw "数值回归测试退出码 $LASTEXITCODE" }
    }
}

# ---- 5. 2D CIFA-MGRM 端到端（真实外部 CSV + 题目-维度文件；仅 -Full）----
if ($Full) {
    CheckIrt 'IRT 端到端：2D CIFA-MGRM（外部 CSV + 维度对照表）' {
        $log = & (Join-Path $root 'run_irt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'tests\e2e_cifa_mgrm.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $dir = Get-LastCompleteDir $log
        $loadFile = Get-ChildItem -Path $dir -Filter '*cifa_loading_matrix.csv' -File | Select-Object -First 1
        if (-not $loadFile) { throw '结果目录缺少 cifa_loading_matrix.csv' }
        # 统计量断言：载荷矩阵行数 = 题目数（tests/e2e_cifa_mgrm.json → tests/data/e2e_mgrm_responses.csv 共 12 题）；
        # 且每行在指定维度（tests/data/e2e_mgrm_loading.csv）上的载荷绝对值为该行最大。
        $loadRows = @(Import-Csv -Encoding UTF8 $loadFile.FullName)
        if ($loadRows.Count -ne 12) { throw "cifa_loading_matrix 行数（题目数）= $($loadRows.Count)，应为 12（e2e_cifa_mgrm 配置 12 题）" }
        $dimMap = @{}
        Import-Csv -Encoding UTF8 (Join-Path $root 'tests\data\e2e_mgrm_loading.csv') | ForEach-Object { $dimMap[$_.item] = $_.dimension }
        $dimCols = @($dimMap.Values | Select-Object -Unique)
        foreach ($r in $loadRows) {
            $assigned = $dimMap[$r.Item]
            if (-not $assigned) { throw "载荷矩阵中的题目 $($r.Item) 不在 e2e_mgrm_loading.csv 页中" }
            $maxAbs = ($dimCols | ForEach-Object { [math]::Abs([double]$r.$_) } | Measure-Object -Maximum).Maximum
            $assignedAbs = [math]::Abs([double]$r.$assigned)
            if ($assignedAbs -lt $maxAbs - 1e-12) { throw "题目 $($r.Item) 的指定维度（$assigned）载荷绝对值 $assignedAbs 不是该行最大（$maxAbs）" }
        }
    }
}


# ---- 6. 边界与回归夹具（仅 -Full）----
# 这一节把带回归性质的边界夹具固化成自检：每条都对应一个真实修过的缺陷，
# 断言"修好之后可观察的行为"，而不只是"没崩"。
#   6a 零方差题：必须显式告知并排除该列，而不是静默产出 NA 载荷；
#   6b 反向计分编码不符：必须报错拦住（R2），不得按 k+1-x 静默算出全错的反向分；
#   6c 中位数插补范围（R4）：插补值只能用"会被保留下来"的个案来算；
#   6d 小样本 IRT（R3）：n<50 必须给出"参数估计极不稳定"的警告。
if ($Full) {
    Check 'CTT：零方差题必须显式排除并告知' {
        $cfg = Join-Path $root 'tests\e2e_ctt_zero_variance.json'
        $log = & (Join-Path $root 'run_ctt_analysis.ps1') -Silent -ConfigJson $cfg 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        # "告知"这一半只能在 R 层核：静默模式的产品约定是只输出 JSON 事件，不转发 R 的诊断文字
        # （非静默模式会把这类"注意：…"打到控制台）。直调管线即可看到它。
        # 原生程序的 stderr 在 $ErrorActionPreference='Stop' + 2>&1 下会被当成终止错误抛出
        # （R 输出 "Warning: KMO=..." 这类正常警告就会让整条检查失败）。调用的这段时间放宽 EAP，
        # 与 run_irt_analysis.ps1 / run_ctt_analysis.ps1 里调用 R / Python 的做法一致。
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $rlog = & $rscript --vanilla (Join-Path $root 'scripts\ctt_pipeline.R') --config $cfg 2>&1
        $ErrorActionPreference = $prevEap
        $rtxt = ($rlog | Out-String)
        if ($rtxt -notmatch '零方差') { throw 'R 层没有任何「零方差」提示：退化列被静默丢弃了' }
        if ($rtxt -notmatch 'Item10') { throw 'R 层的零方差提示里没有点名被排除的列（Item10）' }
        $dir = Get-LastCompleteDir $log
        $cleaned = Get-ChildItem -Path $dir -Filter '*_cleaned_items.csv' -File | Select-Object -First 1
        if (-not $cleaned) { throw '结果目录缺少 *_cleaned_items.csv' }
        $cols = @((Import-Csv -Encoding UTF8 $cleaned.FullName | Select-Object -First 1).PSObject.Properties.Name)
        # 夹具数据共 10 题（Item01..Item10），其中 Item10 恒为 3 → 清洗后应只剩 9 题
        if ($cols -contains 'Item10') { throw "零方差的 Item10 未被排除（清洗后列：$($cols -join ',')）" }
        $itemCols = @($cols | Where-Object { $_ -match '^Item\d+$' })
        if ($itemCols.Count -ne 9) { throw "清洗后应剩 9 题，实际 $($itemCols.Count) 题：$($itemCols -join ',')" }
    }
}

if ($Full) {
    Check 'CTT：反向计分与观测范围不符时必须报错（R2）' {
        $log = & (Join-Path $root 'run_ctt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'tests\e2e_ctt_wrong_coding.json') -Verbose 2>&1
        if ($LASTEXITCODE -eq 0) { throw '0–4 编码却声明 scale_maximum=5，本应报错拦住，实际却跑完了' }
        $raw = ($log | Out-String)
        if ($raw -notmatch 'Reverse scoring assumes') { throw "原始诊断里没有 R2 的说明（应提示反向计分假设 1..scale_maximum）；实际输出：$($raw.Substring(0, [Math]::Min(400, $raw.Length)))" }
    }
}

if ($Full) {
    Check 'CTT：中位数插补只能用保留个案计算（R4）' {
        $log = & (Join-Path $root 'run_ctt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'tests\e2e_ctt_median_scope.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $dir = Get-LastCompleteDir $log
        $cleaned = Get-ChildItem -Path $dir -Filter '*_cleaned_items.csv' -File | Select-Object -First 1
        if (-not $cleaned) { throw '结果目录缺少 *_cleaned_items.csv' }
        $rows = @(Import-Csv -Encoding UTF8 $cleaned.FullName)
        # 夹具：40 名高缺失个案（Item06 全为 1，终将被删）+ 60 名完整个案（Item06 为 3/4/5）。
        # 保留者（60 人）中 Item06 的中位数是 4，全样本（100 人）的中位数是 3。
        if ($rows.Count -ne 60) { throw "应保留 60 名个案，实际 $($rows.Count)" }
        $p041 = @($rows | Where-Object { $_.participant_id -eq 'P041' })
        if ($p041.Count -ne 1) { throw '保留个案里找不到 P041（该个案 Item06 缺失、应被插补）' }
        if ([double]$p041[0].Item06 -ne 4) { throw "P041 的 Item06 插补为 $($p041[0].Item06)，应为 4（保留者中位数）；若为 3 说明用了全样本中位数" }
    }
}

if ($Full) {
    CheckIrt 'IRT：小样本（n=40）必须给出参数不稳警告（R3）' {
        $log = & (Join-Path $root 'run_irt_analysis.ps1') -Silent -ConfigJson (Join-Path $root 'tests\e2e_irt_small_n.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "启动器退出码 $LASTEXITCODE：$($log | Out-String)" }
        $line = $log | Select-String '"event":"preflight"' | Select-Object -Last 1
        if (-not $line) { throw '静默日志缺少 preflight 事件' }
        $pf = $line.Line | ConvertFrom-Json
        $warn = ($pf.data.warnings | Out-String)
        if ($warn -notmatch '样本量仅 40') { throw "体检未给出小样本警告（n=40）；实际 warnings：$warn" }
    }
}

Write-Host ''
if ($skipCount -gt 0) { Write-Host "[注意] 跳过 $skipCount 项 IRT 检查：$irtReason" -ForegroundColor Yellow }
if ($fail -gt 0) { Write-Host "[结果] $fail 项检查失败" -ForegroundColor Red; exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
