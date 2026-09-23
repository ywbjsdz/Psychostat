param(
    [Alias('c')][string]$Config,
    [Alias('d')][string]$Data,
    [Alias('m')][string]$Method,
    [switch]$Simulate,
    [switch]$Silent,
    [string]$ConfigJson,
    [switch]$Verbose
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8; [Console]::OutputEncoding = $utf8; $OutputEncoding = $utf8
$root = $PSScriptRoot
. (Join-Path $root 'psychostat_env.ps1')

# ── 分支专属的环境数据（函数逻辑已下沉到 psychostat_env.ps1）──
$script:PsychostatStagePrefix = "`n[Psychostat 统计] "
$script:PsychostatRFailureTable = @(
  @('variables\.|不在数据列中|缺少 variables', '变量列名配置有误：请核对 variables 中每个列名都存在于数据第一行。'),
  @('恰好2个水平|需要≥3个水平|至少两', '分组变量的水平数不符合所选方法要求（2组用t/U，≥3组用ANOVA/H）。'),
  @('at least two|Anova\.mlm|未收敛|converge', '模型无法拟合：请检查重复测量列是否按时间顺序、被试编号是否正确。')
)
$script:PsychostatRFailureFallback = 'R 分析未完成。请检查数据列名与配置；可使用 -Verbose 查看原始诊断。'

function Get-DataFile { $p=Select-PsychostatFile -Title '选择数据文件（CSV / Excel / SPSS）'; if($p){return [IO.Path]::GetFullPath($p)}; while($true){$p=Read-Host '（也可直接粘贴路径）CSV、Excel 或 SPSS (.sav) 数据文件';if((Test-Path -LiteralPath $p)-and([IO.Path]::GetExtension($p).ToLowerInvariant() -in '.csv','.xlsx','.xls','.sav')){return [IO.Path]::GetFullPath($p)};Write-Host '文件无效，请重新输入。' -ForegroundColor Yellow} }
function Read-Choice($Title,[string[]]$Options,[int]$Default){Write-Host "`n$Title" -ForegroundColor Cyan;for($i=0;$i -lt $Options.Count;$i++){Write-Host ('  {0}. {1}' -f($i+1),$Options[$i])};while($true){$x=Read-Host "输入数字（回车默认 $Default）";if([string]::IsNullOrWhiteSpace($x)){return $Default};$n=0;if([int]::TryParse($x,[ref]$n)-and$n -ge 1-and$n -le $Options.Count){return $n};Write-Host '请输入列表中的数字。' -ForegroundColor Yellow}}
function Read-Text($Prompt){$x=Read-Host $Prompt; if([string]::IsNullOrWhiteSpace($x)){$null}else{$x.Trim()}}

# 方法目录：编号、id、中文名、一句话适用场景（交互引导的核心）
$script:MethodCatalog = [ordered]@{
  'descriptives'            = @{zh='描述统计';              tip='给数据画像（M/SD/偏度峰度/Z分数）——任何分析的第一步'}
  'normality'               = @{zh='正态性与方差齐性检验';  tip='检验 t/ANOVA 的前提：Shapiro-Wilk、K-S、Levene'}
  'one_sample_t'            = @{zh='单样本t检验';           tip='样本均值 vs 已知总体值（常模）'}
  'independent_t'           = @{zh='独立样本t检验';         tip='两组不同的人比较均值（男 vs 女）'}
  'paired_t'                = @{zh='配对样本t检验';         tip='同一批人前后测比较'}
  'one_way_anova'           = @{zh='单因素方差分析';        tip='一个自变量、≥3组（含LSD/Tukey/Bonferroni事后）'}
  'two_way_anova'           = @{zh='两因素方差分析';        tip='两个自变量：主效应+交互+简单效应（三步闭环）'}
  'rm_anova'                = @{zh='重复测量方差分析';      tip='同一批人测≥3次（Mauchly球形+GG/HF校正）'}
  'mixed_anova'             = @{zh='混合设计方差分析';      tip='一组被试间×一组被试内（干预/对照 × 前中后测）'}
  'ancova'                  = @{zh='协方差分析';            tip='控制前测/智商等连续变量后比较组间'}
  'correlation'             = @{zh='相关分析（含偏相关）';  tip='两个连续变量的关联；控制第三变量用偏相关'}
  'regression'              = @{zh='多元线性回归';          tip='多个自变量预测连续因变量（含交互与简单斜率）'}
  'chi_square_gof'          = @{zh='卡方适合度检验';        tip='单个分类变量的分布 vs 理论比例'}
  'chi_square_independence' = @{zh='卡方独立性检验';        tip='两个分类变量是否关联（性别×择业偏好）'}
  'mann_whitney'            = @{zh='Mann-Whitney U检验';   tip='两组独立但数据偏态/等级（t的替代）'}
  'wilcoxon_signed'         = @{zh='Wilcoxon符号秩检验';    tip='前后测但差值偏态/等级（配对t的替代）'}
  'kruskal_wallis'          = @{zh='Kruskal-Wallis H检验'; tip='≥3组独立但偏态/等级（ANOVA的替代）'}
  'friedman'                = @{zh='Friedman检验';         tip='≥3次重复测量但偏态/等级（重复测量ANOVA的替代）'}
  'mediation'               = @{zh='中介效应分析';          tip='X如何通过M影响Y（PROCESS Model 4，Bootstrap 5000）'}
  'moderation'              = @{zh='调节效应分析';          tip='X的效应何时/对谁更强（PROCESS Model 1，简单斜率+交互图）'}
  'power'                   = @{zh='统计功效与样本量';      tip='开题算样本量（对应G*Power），不需要数据'}
}
# 数据准备策略询问：先问缺失值管不管、再问异常值管不管。
# 默认（直接回车）= 都不处理，只报告。返回 [ordered] 配置；无选择时返回 $null。
function Get-DataCheckPolicy {
  Write-Host "`n—— 第 0 步：数据准备（缺失值 / 异常值）——" -ForegroundColor Magenta
  Write-Host "  工具会先报告数据里有哪些问题；下面决定要不要处理（不做也能继续，只是报告里会标注）。" -ForegroundColor DarkGray

  $miss = Read-Choice '发现缺失值时怎么办？' @(
      '不处理（保持原样，后续分析按各方法自身口径，多数为整例删除）',
      '均值插补（SPSS 常用口径：用该变量的均值替换缺失值）') 1
  $out = Read-Choice '发现异常值（|Z| > 3）时怎么办？' @(
      '不删除（保留并在报告中标注，异常值是否剔除应结合专业判断）',
      '删除（按 |Z| > 3 判定，并在报告中写明删除人数）') 1

  if($miss -eq 1 -and $out -eq 1){ return $null }   # 都不处理：不必写进配置

  $zc = $null
  if($out -eq 2){
    $t = Read-Text '  |Z| 阈值（回车默认 3）'
    if($t){ $n = 0.0; if([double]::TryParse($t,[ref]$n) -and $n -gt 0){ $zc = $n } else { Write-Host '  （输入无效，按默认 3 处理）' -ForegroundColor Yellow } }
  }
  $sr = $null
  $t2 = Read-Text '  量表取值范围（可选，如 1-5；用于检查越界值。直接回车跳过）'
  if($t2 -and $t2 -match '^\s*(-?\d+(?:\.\d+)?)\s*[-~至]\s*(-?\d+(?:\.\d+)?)\s*$'){
    $sr = @([double]$Matches[1], [double]$Matches[2])
    if($sr[0] -gt $sr[1]){ $sr = @($sr[1], $sr[0]) }
  }

  $dc = [ordered]@{}
  $dc['missing_action'] = if($miss -eq 2){ 'mean_impute' } else { 'report' }
  $dc['outlier_action'] = if($out -eq 2){ 'remove_by_z' } else { 'report' }
  if($zc){ $dc['z_cutoff'] = $zc }
  if($sr){ $dc['scale_range'] = $sr }
  $dc
}

function Show-MethodMenu($Title){
  Write-Host "`n$Title" -ForegroundColor Cyan
  $ids = @($script:MethodCatalog.Keys)
  for($i=0;$i -lt $ids.Count;$i++){ Write-Host ('  {0,2}. {1,-14} {2}' -f ($i+1), $script:MethodCatalog[$ids[$i]].zh, $script:MethodCatalog[$ids[$i]].tip) }
  while($true){
    $x = Read-Host '输入编号（多个用逗号分隔，回车=全部演示）'
    if([string]::IsNullOrWhiteSpace($x)){ return $ids }
    $picked = @(); $ok = $true
    foreach($part in ($x -split '[，,]') | Where-Object {$_ -match '\S'}){
      $n = 0
      if([int]::TryParse($part.Trim(),[ref]$n) -and $n -ge 1 -and $n -le $ids.Count){ $picked += $ids[$n-1] }
      elseif($script:MethodCatalog.Contains($part.Trim())){ $picked += $part.Trim() }
      else { Write-Host "无效编号：$part" -ForegroundColor Yellow; $ok=$false; break }
    }
    if($ok -and $picked.Count){ return $picked }
  }
}

# 方法选择决策向导：通过3-4个问题推荐方法（帮助大二学生建立选择思路）
function Invoke-DecisionWizard {
  Write-Host "`n══════════ 方法选择向导：回答几个问题，帮你选统计方法 ══════════" -ForegroundColor Cyan
  $dvType = Read-Choice '问题1/4：你的因变量（要解释的结果变量）是什么类型？' @(
    '连续数据（考试分数、焦虑总分等，取值精细）',
    '分类数据（及格/不及格、A/B/C/D偏好等，数个数）',
    '等级数据或严重偏态（排名、1-7满意度且分布很偏）') 1
  if($dvType -eq 2){
    $one = Read-Choice '问题2/4：分类变量涉及几个？' @('1个：想知道它的分布是否符合理论比例','2个：想知道它们是否相互关联') 1
    return if($one -eq 1){'chi_square_gof'}else{'chi_square_independence'}
  }
  if($dvType -eq 3){
    $groups = Read-Choice '问题2/4：比较几组/几次测量？' @(
      '2组，两组是不同的人（独立）',
      '2次，同一批人前后测（配对）',
      '≥3组，各组是不同的人（独立）',
      '≥3次，同一批人重复测量') 3
    return $(switch($groups){ 1 {'mann_whitney'} 2 {'wilcoxon_signed'} 3 {'kruskal_wallis'} 4 {'friedman'} })
  }
  # 连续数据
  $aim = Read-Choice '问题2/4：你的研究目的是？' @(
    '比较差异：不同组/不同条件的均值是否不同',
    '看关系：变量之间是否相关，或用X预测Y',
    '先检查数据前提：正态性/方差齐性（推荐先做）') 1
  if($aim -eq 3){ return 'normality' }
  if($aim -eq 2){
    $pred = Read-Choice '问题3/4：想描述关联还是要做预测模型？' @(
      '描述两个变量的关联强度（相关；控制第三变量选偏相关）',
      '用一个或多个X预测Y，看各自独特贡献（回归）') 1
    return if($pred -eq 1){'correlation'}else{'regression'}
  }
  $groups = Read-Choice '问题3/4：自变量有几个？各几个水平？' @(
    '1个自变量，2个水平（两组）',
    '1个自变量，≥3个水平',
    '2个自变量（如 教学法×动机），关注主效应和交互',
    '只有"时间"一个被试内变量（同一批人测≥3次）',
    '一个被试间 + 一个被试内（如 组别×前中后测）',
    '想控制一个连续协变量后比组间（ANCOVA）') 2
  switch($groups){
    1 {
      $paired = Read-Choice '问题4/4：两组是不同的人，还是同一批人测两次？' @('不同的人（独立）','同一批人（配对）') 1
      return if($paired -eq 1){'independent_t'}else{'paired_t'}
    }
    2 { return 'one_way_anova' }
    3 { return 'two_way_anova' }
    4 { return 'rm_anova' }
    5 { return 'mixed_anova' }
    6 { return 'ancova' }
  }
}

# 按方法询问数据中的列名（file模式），生成 variables 对象
function New-VariablesFor($Method){
  $v = [ordered]@{}
  function Ask-Col($Key,$Prompt){ $x = Read-Text $Prompt; if($x){ $v[$Key] = $x } }
  switch($Method){
    'descriptives'  { $c=Read-Text '要描述的数值列（逗号分隔，回车=自动选全部数值列）'; if($c){$v.columns=@($c -split '[，,]'|ForEach-Object{$_.Trim()})} }
    'normality'     { Ask-Col 'dv' '因变量列名（连续）'; Ask-Col 'group' '分组列名（可选，回车跳过Levene）' }
    'one_sample_t'  { Ask-Col 'dv' '因变量列名'; $mu=Read-Text '检验值（总体常模μ，回车默认50）'; $v.mu = if($mu){[double]$mu}else{50} }
    'independent_t' { Ask-Col 'dv' '因变量列名（连续）'; Ask-Col 'group' '分组列名（恰好2个水平）' }
    'paired_t'      { Ask-Col 'dv1' '前测列名'; Ask-Col 'dv2' '后测列名' }
    'one_way_anova' { Ask-Col 'dv' '因变量列名'; Ask-Col 'group' '分组列名（≥3个水平）' }
    'two_way_anova' { Ask-Col 'dv' '因变量列名'; Ask-Col 'factor_a' '自变量A列名'; Ask-Col 'factor_b' '自变量B列名' }
    'rm_anova'      { $w=Read-Text '组内变量列名，按时间顺序逗号分隔（如 pre,post,followup）'; if($w){$v.within=@($w -split '[，,]'|ForEach-Object{$_.Trim()})}; Ask-Col 'id' '被试编号列（可选）' }
    'mixed_anova'   { $w=Read-Text '组内变量列名，按时间顺序逗号分隔'; if($w){$v.within=@($w -split '[，,]'|ForEach-Object{$_.Trim()})}; Ask-Col 'between' '被试间因子列名（如组别）'; Ask-Col 'id' '被试编号列（可选）' }
    'ancova'        { Ask-Col 'dv' '因变量列名（如后测）'; Ask-Col 'group' '分组列名'; Ask-Col 'covariate' '协变量列名（如前测）' }
    'correlation'   { $c=Read-Text '要分析相关的数值列（逗号分隔，回车=全部数值列）'; if($c){$v.columns=@($c -split '[，,]'|ForEach-Object{$_.Trim()})} }
    'regression'    { Ask-Col 'dv' '因变量列名'; $p=Read-Text '自变量列名（逗号分隔，分类变量请先做0/1哑变量）'; if($p){$v.predictors=@($p -split '[，,]'|ForEach-Object{$_.Trim()})} }
    'chi_square_gof'{ Ask-Col 'category' '分类变量列名' }
    'chi_square_independence' { Ask-Col 'row_var' '行变量列名'; Ask-Col 'col_var' '列变量列名' }
    'mann_whitney'  { Ask-Col 'dv' '因变量列名（偏态/等级）'; Ask-Col 'group' '分组列名（2个水平）' }
    'wilcoxon_signed'{ Ask-Col 'dv1' '前测列名'; Ask-Col 'dv2' '后测列名' }
    'kruskal_wallis'{ Ask-Col 'dv' '因变量列名'; Ask-Col 'group' '分组列名（≥3水平）' }
    'friedman'      { $w=Read-Text '各条件列名（逗号分隔，同一批被试在每个条件下都有一列）'; if($w){$v.within=@($w -split '[，,]'|ForEach-Object{$_.Trim()})} }
    'mediation'     { Ask-Col 'x' '自变量X列名'; Ask-Col 'm' '中介变量M列名'; Ask-Col 'y' '因变量Y列名' }
    'moderation'    { Ask-Col 'interaction_x' '自变量X列名'; Ask-Col 'interaction_z' '调节变量Z列名'; Ask-Col 'interaction_dv' '因变量Y列名' }
    'power'         { Write-Host '功效分析不需要数据文件，直接计算。' -ForegroundColor DarkCyan }
  }
  $v
}

function New-InteractiveConfig {
  $mode = Read-Choice '选择运行方式' @(
    '教学演示全流程（推荐首次使用）：21种方法全部用内置模拟数据跑一遍，每个结果都给出SPSS操作路径与结果解读',
    '选择方法分析（内置模拟数据，体验该方法）',
    '分析我自己的数据文件（CSV/Excel/SPSS）',
    '方法选择向导：回答几个问题，帮你决定用哪种统计方法') 1
  if($mode -eq 4){
    $rec = Invoke-DecisionWizard
    Write-Host "`n→ 向导推荐方法：$($script:MethodCatalog[$rec].zh)（$rec）" -ForegroundColor Green
    Write-Host "  适用：$($script:MethodCatalog[$rec].tip)"
    $confirm = Read-Choice '用推荐方法继续吗？' @('继续（用我的数据）','继续（用内置模拟演示）','返回重新选') 1
    if($confirm -eq 3){ return New-InteractiveConfig }
    $methods = @($rec)
    if($confirm -eq 1){
      $path = Get-DataFile
      $vars = New-VariablesFor $rec
      return (New-ConfigJson 'file' $path $methods $vars (Get-DataCheckPolicy))
    }
    return (New-ConfigJson 'simulate' $null $methods $null (Get-DataCheckPolicy))
  }
  if($mode -eq 1){ return (Join-Path $root 'stats_config.yaml') }
  $methods = Show-MethodMenu '选择要运行的方法（可多选）'
  if($mode -eq 2){ return (New-ConfigJson 'simulate' $null $methods $null (Get-DataCheckPolicy)) }
  $path = Get-DataFile
  $varsList = @{}
  foreach($m in $methods){
    Write-Host "`n—— 为 [$($script:MethodCatalog[$m].zh)] 指定变量 ——" -ForegroundColor Magenta
    $varsList[$m] = New-VariablesFor $m
    # 方法专属追加询问：普通相关 vs 偏相关、整体进入 vs 分层回归——都是 SPSS 里不同的分析路径，多问一步避免做错
    if($m -eq 'correlation'){
      $pc = Read-Choice '  需要偏相关吗？（偏相关=控制第三变量后的独特关联，SPSS: 分析>相关>偏相关，与普通相关结果不同）' @('不需要，只做普通相关','需要偏相关（接下来指定 X、Y 与控制变量）') 1
      if($pc -eq 2){
        $px = Read-Text '  偏相关 X 列名（回车=第1个分析列）'; if($px){ $varsList[$m]['partial_x'] = $px }
        $py = Read-Text '  偏相关 Y 列名（回车=第2个分析列）'; if($py){ $varsList[$m]['partial_y'] = $py }
        $ctrl = Read-Text '  控制变量列名（多个用逗号分隔）'
        if($ctrl){ $varsList[$m]['partial_control'] = @($ctrl -split '[,，;；、]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
      }
    }
    if($m -eq 'regression'){
      $hr = Read-Choice '  需要分层回归吗？（SPSS: 线性回归把自变量分多个"块"依次进入，每块输出 ΔR²/F变更）' @('不需要，全部一次进入（Enter，默认）','需要分层回归（接下来逐层输入自变量）') 1
      if($hr -eq 2){
        $layers = @(); $ln = 1
        while($true){
          $v = Read-Text "  第 $ln 层自变量（逗号分隔；直接回车=结束，至少需要 2 层）"
          if(-not $v){ break }
          $layers += , @($v -split '[,，;；、]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
          $ln++
        }
        if($layers.Count -ge 2){ $varsList[$m]['blocks'] = $layers }
        else { Write-Host '  （不足 2 层，本次按整体进入处理；想分层请重跑并输入至少两层）' -ForegroundColor Yellow }
      }
    }
  }
  # 多方法时共用同一套变量（取并集提示）；单方法用其专属变量
  $vars = [ordered]@{}
  foreach($m in $methods){ foreach($k in $varsList[$m].Keys){ $vars[$k] = $varsList[$m][$k] } }
  (New-ConfigJson 'file' $path $methods $vars (Get-DataCheckPolicy))
}

function New-ConfigJson($Mode,$Path,$Methods,$Vars,$DataCheck){
  $obj=[ordered]@{
    method = $Methods
    input = [ordered]@{ mode=$Mode; path=$(if($Path){$Path}else{$null}) }
    variables = if($Vars){$Vars}else{[ordered]@{}}
    analysis = [ordered]@{ alpha=0.05; posthoc=@('lsd','tukey','bonferroni'); correlation_method='both' }
    simulation = [ordered]@{ seed=20260904; n_per_group=30 }
    output = [ordered]@{ directory=(Join-Path $root 'outputs'); project_label='interactive_stats'; report_language='zh' }
  }
  if($DataCheck){ $obj['datacheck'] = $DataCheck }
  $file=Join-Path $env:TEMP ('psychostat_stats_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  [IO.File]::WriteAllText($file, ($obj|ConvertTo-Json -Depth 10), $utf8); $file
}


if($Silent -and -not $ConfigJson -and -not $Config){Stop-Friendly '静默模式必须提供 JSON 配置：-Silent -ConfigJson .\my_stats_config.json'}
if($Silent -and $ConfigJson){$Config=$ConfigJson}
if($Simulate){if($Config -or $Data){Stop-Friendly '-Simulate 不可与 -Config 或 -Data 同时使用。'};$effective=Join-Path $root 'stats_config.yaml'}
elseif($Config){$effective=Resolve-ExistingPath $Config '配置文件'}
elseif($Method -and -not $Data){$effective=New-ConfigJson 'simulate' $null @($Method.Split(',')) $null; Write-Stage "本次配置：$effective" 'DarkCyan'}
elseif($Method -and $Data){$p=Resolve-ExistingPath $Data '数据文件';$effective=New-ConfigJson 'file' $p @($Method.Split(',')) $null; Write-Stage "本次配置：$effective" 'DarkCyan'}
elseif($Silent){Stop-Friendly '静默模式需要 JSON 配置。'}
else{$effective=New-InteractiveConfig; if(-not $Silent){Write-Stage "本次配置：$effective" 'DarkCyan'}}
if($Silent -and([IO.Path]::GetExtension($effective).ToLowerInvariant() -ne '.json')){Stop-Friendly '静默模式仅接受 JSON 配置。'}
try { $rscript = if ($Silent) { Initialize-PsychostatEnvironment } else { Initialize-PsychostatEnvironment -AllowAutoInstall } } catch { Stop-Friendly $_.Exception.Message }
$packages=Get-PsychostatRequiredPackages -Branch 'stats';$packageScript=Get-PsychostatPackageInstallScript -Packages $packages
if(-not $Silent){Write-Stage '检查并安装心理统计所需 R 包（只装缺的，已装自动跳过；国内镜像优先，失败自动换源）...'}
$previousEap=$ErrorActionPreference;$ErrorActionPreference='Continue';$packageLog=& $rscript --vanilla $packageScript 2>&1;$packageExit=$LASTEXITCODE;$ErrorActionPreference=$previousEap;Remove-Item -LiteralPath $packageScript -Force -ErrorAction SilentlyContinue
if($packageExit -ne 0){Stop-Friendly (Translate-RFailure (($packageLog|Out-String).Trim())) (($packageLog|Out-String).Trim())}
if(-not $Silent){Write-Stage '运行统计分析（控制台会逐步给出SPSS对照与结果解读）...'}
# Tee the R output: guidance text streams live to the console while being captured for error handling.
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
if($Silent){ $log=& $rscript --vanilla (Join-Path $root 'scripts\stats_pipeline.R') --config-utf8-hex (ConvertTo-Utf8Hex $effective) 2>&1 }
else{ $log=& $rscript --vanilla (Join-Path $root 'scripts\stats_pipeline.R') --config-utf8-hex (ConvertTo-Utf8Hex $effective) 2>&1 | ForEach-Object { Write-Host "$_"; "$_" } }
$exit=$LASTEXITCODE;$ErrorActionPreference=$old
if($exit -ne 0){Stop-Friendly (Translate-RFailure (($log|Out-String).Trim())) (($log|Out-String).Trim())}
$line=$log|ForEach-Object{"$_"}|Where-Object{$_ -match '^RESULT_DIR_UTF8_HEX='}|Select-Object -Last 1
if(-not $line){Stop-Friendly '分析没有返回结果目录。' (($log|Out-String).Trim())}
$hex=($line -replace '^RESULT_DIR_UTF8_HEX=','').Trim();[byte[]]$bytes=@(for($i=0;$i -lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)});$result=$utf8.GetString($bytes)
# 中英文 Word 结果报告（Python 与 pandas/python-docx 缺失时自动安装依赖；未安装 Python 时跳过并提示）
$pythonEnv=Initialize-PsychostatPythonEnvironment -ProjectRoot $root -Silent:$Silent
$reportNote=$pythonEnv.Note
# HTML 网页版报告（新增产物）：与 Word 报告解耦，失败只提示、绝不阻塞既有产物；$htmlOk 需在 Ready 块外初始化，供末尾 JSON/文案统一取值
$htmlName='stats_report_zh.html';$htmlFile=Join-Path $result $htmlName;$htmlOk=$false
if($pythonEnv.Ready){
  if(-not $Silent){Write-Stage '生成中英文 Word 结果报告...'}
  $old2=$ErrorActionPreference;$ErrorActionPreference='Continue'
  $reportLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_stats_report.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($result))) 2>&1
  $ErrorActionPreference=$old2
  if($LASTEXITCODE -ne 0){ if(-not $Silent){Write-Host '  结果报告生成失败（分析结果不受影响）：' -ForegroundColor DarkYellow; Write-Host (($reportLog|Out-String).Trim()) -ForegroundColor DarkGray; if([Environment]::UserInteractive){Read-Host '  （按回车键关闭窗口）'}} }
  else{ $reportNote='结果报告：stats_report_zh.docx / stats_report_en.docx 已生成。' }
  # 网页版报告为可选增强：成功=退出码0+stdout含HTML_REPORT_OK+文件落地；缺生成器/失败只黄字提示，不影响整体退出码
  $old3=$ErrorActionPreference;$ErrorActionPreference='Continue'
  $htmlLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_html_report.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($result))) 2>&1
  $ErrorActionPreference=$old3
  if($LASTEXITCODE -eq 0 -and (($htmlLog|Out-String) -match 'HTML_REPORT_OK') -and (Test-Path -LiteralPath $htmlFile)){
    $htmlOk=$true
    if(-not $Silent){Start-Process -FilePath $htmlFile}   # 静默模式供 AI/批处理调用，绝不开窗口；仅交互模式用默认浏览器打开
  }
  elseif(-not $Silent){Write-Host "  网页版报告 $htmlName 未生成，其余产物（CSV/图/Word/Markdown）不受影响。" -ForegroundColor Yellow}
}
elseif(-not $Silent){Write-Stage $pythonEnv.Note 'Yellow'; if([Environment]::UserInteractive){Read-Host '  （按回车键关闭窗口；Word 报告未生成，但分析与 CSV/图/Markdown 报告不受影响）'}}
if($Silent){Write-JsonLog 'complete' @{result_dir=$result;config=$effective;report_note=$reportNote;html_report=$(if($htmlOk){$htmlName}else{$null})}}else{Write-Stage "完成。结果目录：$result" 'Green'; Write-Host "  → 结果报告（中/英）：stats_report_zh.docx、stats_report_en.docx；" -ForegroundColor DarkCyan; Write-Host "  → 教学报告 stats_report_zh.md 与 00_方法选择决策指南.md；" -ForegroundColor DarkCyan; if($htmlOk){Write-Host "  → 网页版报告 $htmlName（已在浏览器打开）；" -ForegroundColor DarkCyan}; Write-Host "  → 把 NN_方法_data.csv 导入SPSS复现，对照各 NN_方法_*.csv 核验数值。" -ForegroundColor DarkCyan}
