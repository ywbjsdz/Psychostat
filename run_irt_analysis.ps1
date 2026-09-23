param(
    [Alias('c')][string]$Config,
    [Alias('d')][string]$Data,
    [Alias('m')][ValidateSet('rasch','2pl','3pl','grm','gpcm','mirt')][string]$Model,
    [switch]$Auto,
    [switch]$Eifa,
    [switch]$Cifa,
    [Alias('dim_range')][string]$DimRange,
    [Alias('loading_matrix')][string]$LoadingMatrix,
    [switch]$Silent,
    [string]$ConfigJson,
    [switch]$Verbose
)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding=$utf8; [Console]::OutputEncoding=$utf8; $OutputEncoding=$utf8
$root=$PSScriptRoot
. (Join-Path $root 'psychostat_env.ps1')

# ── 分支专属的环境数据（函数逻辑已下沉到 psychostat_env.ps1）──
$script:PsychostatStagePrefix = '[General IRT] '
$script:PsychostatRFailureTable = @(
  @('Loading matrix|loading_matrix|CIFA requires|dimension_mapping', '验证性 MIRT 的题目-维度文件无效。请使用含 item,dimension 两列的 UTF-8 CSV，并确保每题只归属一个维度。'),
  @('mirt_item_model|ordered polytomous.*2PL|ordered polytomous.*3PL', '多级有序数据应使用多维 GRM；多维 2PL/3PL 仅适用于二分数据。请在向导中选择“自动匹配”或多维 GRM。'),
  @('not integer|integer-scored', '题目必须为整数计分。请排除文本、总分和人口学变量。'),
  @('Zero-variance', '存在零方差题项。请删除所有被试均选同一选项的题目。'),
  @('did not converge|max cycles|NCYCLES', '模型未收敛。可降低维度数、改用更简单模型、增加样本量或提高 max_iterations。')
)
$script:PsychostatRFailureFallback = 'R 分析未完成（数据体检已通过，问题出在模型拟合阶段）。请在命令末尾加 -Verbose 查看原始诊断日志。'
$script:PsychostatDataFileTitle = '选择 IRT 数据文件'

function Read-DimensionRange($Initial){$x=$Initial;while($true){if($null -eq $x){$x=Read-Host '请输入维度范围，例如 1-3（直接回车自动推荐）'};if([string]::IsNullOrWhiteSpace($x)-or$x.Trim().ToLowerInvariant() -eq 'auto'){return 'auto'};if($x -match '^\s*([1-6])\s*-\s*([1-6])\s*$' -and [int]$Matches[1]-le[int]$Matches[2]){return ('{0}-{1}' -f [int]$Matches[1],[int]$Matches[2])};Write-Host '范围应为 1-3，且最大为 6 维。' -ForegroundColor Yellow;$x=$null}}
function Resolve-LoadingMatrix($Path,[switch]$Prompt){
  while($true){
    if(-not $Path -and $Prompt){$Path=Select-PsychostatFile -Title '选择题目-维度归属表（列名 item,dimension）' -Filter '归属表 CSV/Excel|*.csv;*.xlsx;*.xls|所有文件|*.*'; if(-not $Path){$Path=Read-Host '（也可直接粘贴路径）题目-维度归属 CSV 或 Excel 路径（列名 item,dimension）'}}
    if(-not $Path){Stop-Friendly '验证性 MIRT 需要题目-维度归属 CSV 或 Excel 文件。'}
    $p=Resolve-ExistingPath $Path '题目-维度归属文件'
    if([IO.Path]::GetExtension($p).ToLowerInvariant() -in '.csv','.xlsx','.xls'){return $p}
    if(-not $Prompt){Stop-Friendly '验证性 MIRT 的归类文件必须为 CSV 或 Excel。'}
    Write-Host '请选择 CSV、XLSX 或 XLS 文件。' -ForegroundColor Yellow; $Path=$null
  }
}

function Invoke-IrtModelWizard{
  # IRT 模型选择向导：计分类型→维度→样本量→（多级）作答方式/（二分）特殊情况。
  # 推荐口径来自 de Ayala《The Theory and Practice of IRT》(2022) 与 Dai & Chang (2021, Frontiers in Education)
  # 的经验规则：Rasch/1PL 百级样本即可稳定；2PL 需 250-500 起；3PL 猜测参数公认 N≥1000；
  # 多级 GRM/GPCM 建议 N≥250-500（样本够时双模型 BIC 比较更稳）。
  $scoring=Read-MenuChoice '问题 1/4：题目是什么计分？' @('二分：0/1、对/错、是/否','有序多级：Likert 1-5、0-4 等','不清楚（先按多级选，数据体检会按实际纠正）') 1
  $dim=Read-MenuChoice '问题 2/4：测量结构是？' @('单维：一个总分/一个构念','多维，或不确定（让数据说话）') 1
  $n=Read-MenuChoice '问题 3/4：有效样本量大约？' @('少于 100','100–250','250–500','500–1000','1000 及以上') 1
  if($scoring -eq 2){
    $resp=Read-MenuChoice '问题 4/4：多级题目的作答方式更接近？' @('Likert 同意度/频率量表（累积跨越类别）','部分计分/逐步作答，如 0/1/2 步骤得分','不确定（样本够时两个都用 BIC 比较）') 1
    if($dim -eq 2){return @{model='mirt';compare=@('mirt');mirtItemModel='auto';reason='多维/不确定结构 → MIRT：EIFA 用 BIC 与平行分析定维度；多级数据自动用多维 GRM 家族'}}
    if($n -le 2 -and $resp -ne 2){return @{model='grm';compare=@('grm');mirtItemModel='auto';reason='多级×单维×N<500 → GRM（Samejima 1969 累积 logit，Likert 量表常用）。提示：多级模型参数较多，de Ayala 建议 N≥250-500，样本偏小时解读需谨慎'}}
    if($resp -eq 1){return @{model='grm';compare=@('grm','gpcm');mirtItemModel='auto';reason='Likert 量表 → GRM 首选；N≥500 时同时拟合 GPCM 用 BIC 选优（Dai & Chang 2021 建议双模型比较）'}}
    if($resp -eq 2){return @{model='gpcm';compare=@('gpcm');mirtItemModel='auto';reason='部分计分/逐步作答 → GPCM（Muraki 1992 相邻类别 logit）'}}
    return @{model='grm';compare=@('grm','gpcm');mirtItemModel='auto';reason='作答方式不确定且 N≥500 → GRM 与 GPCM 都拟合、BIC 选优'}
  }
  $spec=Read-MenuChoice '问题 4/4：有以下情况吗？' @('标准化选择题考试，低能力者可能猜对（3PL 线索）','想要 Rasch 优良性质：题难可加、适合小样本与题库建设','都没有') 1
  if($dim -eq 2){return @{model='mirt';compare=@('mirt');mirtItemModel='auto';reason='多维/不确定结构 → MIRT：EIFA 用 BIC 定维度；二分数据自动用多维 2PL'}}
  if($spec -eq 2 -or $n -le 2){
    $why=if($spec -eq 2){'追求可加性/题库 → Rasch（每题只估难度，最省样本，百级即可稳定）'}else{'N<250 → Rasch 最稳妥（2PL 每题多估区分度参数，小样本不稳）'}
    return @{model='rasch';compare=@('rasch');mirtItemModel='auto';reason=$why}
  }
  if($spec -eq 1 -and $n -ge 5){return @{model='2pl';compare=@('2pl','3pl');mirtItemModel='auto';reason='有猜测可能且 N≥1000 → 2PL 与 3PL 都拟合、BIC 选优（3PL 猜测参数需要大样本）'}}
  if($spec -eq 1){return @{model='2pl';compare=@('2pl');mirtItemModel='auto';reason='有猜测可能但 N<1000 → 先用 2PL（3PL 的猜测参数在小样本估不稳，de Ayala 2022）'}}
  return @{model='2pl';compare=@('rasch','2pl');mirtItemModel='auto';reason='N≥250 且无特殊要求 → Rasch 与 2PL 都拟合、BIC 选优（既检验 1PL 等区分度假设，又允许区分度差异）'}
}

function New-RunConfig($InputData,$RequestedModel,[switch]$Automatic,[switch]$Interactive,$RequestedMirtMode,$RequestedDimRange,$RequestedLoadingMatrix){
  $dataPath=$InputData;if(-not $dataPath){$dataPath=Select-DataFile};$scoring='auto';$dimensions='auto';$missing='none';$modelValue=$RequestedModel;$mirtMode=if($RequestedMirtMode){$RequestedMirtMode}else{'eifa'};$mirtItemModel='auto';$wizCompare=$null;$dimensionRange=if($RequestedDimRange){Read-DimensionRange $RequestedDimRange}else{'auto'};$loading=$RequestedLoadingMatrix;$itemCols='auto'
  if($Interactive){
    $scoring=@('auto','binary','ordinal')[(Read-MenuChoice '题目计分方式' @('自动检测（推荐）','二分计分：0/1、对/错','有序多级：Likert 等') 1)-1]
    $dimChoice=Read-MenuChoice '潜变量维度' @('自动建议（推荐）','单维','多维') 1
    if($dimChoice -eq 3){
      $modelValue='mirt';$dimensions='auto'
      $mirtItemModel=@('auto','grm','gpcm','2pl','3pl')[(Read-MenuChoice '多维项目反应模型' @('自动匹配（推荐：多级=多维 GRM；二分=多维 2PL）','多维 GRM（多级·累积 logit）','多维 GPCM（多级·相邻 logit）','多维 2PL（仅二分）','多维 3PL（仅二分；需有猜测参数理论依据）') 1)-1]
      $modeChoice=Read-MenuChoice 'MIRT 分析模式' @('探索性 MIRT（EIFA）','验证性 MIRT（CIFA）') 1
      if($modeChoice -eq 1){$mirtMode='eifa';$dimensionRange=Read-DimensionRange $null}else{$mirtMode='cifa';$loading=Resolve-LoadingMatrix $null -Prompt}
    }else{
      if($dimChoice -eq 2){$dimensions=1}
      $howToChoose=Read-MenuChoice '怎么选模型？' @('向导推荐：回答 3-4 个问题（推荐）','手动选择模型') 1
      if($howToChoose -eq 1){
        $wiz=Invoke-IrtModelWizard
        $zh=@{rasch='Rasch/1PL';'2pl'='2PL';'3pl'='3PL';grm='GRM';gpcm='GPCM';mirt='MIRT'}[$wiz.model]
        Write-Host "`n→ 向导推荐：$zh" -ForegroundColor Green;Write-Host "  理由：$($wiz.reason)" -ForegroundColor DarkCyan
        $modelValue=$wiz.model;$wizCompare=$wiz.compare;$mirtItemModel=$wiz.mirtItemModel
        if($modelValue -eq 'mirt'){$modeChoice=Read-MenuChoice 'MIRT 分析模式' @('探索性 MIRT（EIFA）','验证性 MIRT（CIFA）') 1;if($modeChoice -eq 1){$mirtMode='eifa';$dimensionRange=Read-DimensionRange $null}else{$mirtMode='cifa';$loading=Resolve-LoadingMatrix $null -Prompt}}
      }else{
      $modelValue=@('auto','rasch','2pl','3pl','grm','gpcm','mirt')[(Read-MenuChoice '拟合模型' @('自动推荐（推荐）','Rasch / 1PL','2PL','3PL','GRM（单维·Likert）','GPCM（单维·部分计分）','MIRT') 1)-1]
      if($modelValue -eq 'mirt'){$modeChoice=Read-MenuChoice 'MIRT 分析模式' @('探索性 MIRT（EIFA）','验证性 MIRT（CIFA）') 1;if($modeChoice -eq 1){$mirtMode='eifa';$dimensionRange=Read-DimensionRange $null}else{$mirtMode='cifa';$loading=Resolve-LoadingMatrix $null -Prompt}}
      }
    }
    $missing=@('none','listwise','pairwise')[(Read-MenuChoice '缺失值处理' @('不预处理，交给 mirt（推荐）','完整个案 listwise','pairwise 维度建议') 1)-1]
    $x=Read-Host '题目列名，用逗号分隔（直接回车=自动识别；自动识别会先做安全检查，若发现疑似 年龄/性别/ID/总分 等非题目列将要求你显式指定）';if(-not[string]::IsNullOrWhiteSpace($x)){$itemCols=@($x.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_})}
  }elseif($Automatic){$modelValue='auto'}
  if(-not $modelValue){$modelValue='auto'}
  if($modelValue -ne 'mirt' -and($RequestedMirtMode-or$RequestedDimRange-or$RequestedLoadingMatrix)){Stop-Friendly '-eifa、-cifa、-dim_range 和 -loading_matrix 仅能与 -m mirt 一起使用。'}
  if($modelValue -eq 'mirt'){if($mirtMode -eq 'cifa'){$loading=Resolve-LoadingMatrix $loading}else{$dimensionRange=Read-DimensionRange $dimensionRange}}
  $comparison=if($modelValue -eq 'auto'){'auto'}elseif($modelValue -eq 'mirt'){@('mirt')}else{@($modelValue)};if($wizCompare){$comparison=$wizCompare}
  $cfg=[ordered]@{input=[ordered]@{mode='file';path=[IO.Path]::GetFullPath($dataPath);id_column=$null;item_columns=$itemCols;missing=$missing};analysis=[ordered]@{model=$modelValue;compare_models=$comparison;response_format=$scoring;dimension_count=$dimensions;dimension_range=$dimensionRange;mirt_mode=$mirtMode;mirt_item_model=$mirtItemModel;loading_matrix=$loading;max_auto_dimensions=6;dimension_mapping=$null;estimator='EM';max_iterations=500;theta_min=-3;theta_max=3;theta_points=121;selection_criterion='BIC';allow_3pl=$false;compute_m2=$true};output=[ordered]@{directory=(Join-Path $root 'outputs');project_label='interactive_irt';report_languages=@('zh','en');save_model_object=$true}}
  $path=Join-Path $env:TEMP ('irt_generated_{0}.json' -f(Get-Date -Format 'yyyyMMdd_HHmmss'));[IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)));return $path
}
function Invoke-Preflight($ConfigPath,$RscriptPath){
  $profilePath=Join-Path $env:TEMP ('irt_preflight_{0}.json' -f([guid]::NewGuid().ToString('N')))
  $previousEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
  $raw=& $RscriptPath --vanilla (Join-Path $root 'scripts\irt_preflight.R') --config-utf8-hex (ConvertTo-Utf8Hex $ConfigPath) --output-utf8-hex (ConvertTo-Utf8Hex $profilePath) 2>&1
  $preflightExit=$LASTEXITCODE; $ErrorActionPreference=$previousEap; $rawText=($raw|Out-String).Trim()
  if(-not(Test-Path -LiteralPath $profilePath)){return [pscustomobject]@{status='fatal';fatal=@('数据体检程序没有返回有效结果。');warnings=@();raw=$rawText;exit_code=$preflightExit}}
  try{$z=[IO.File]::ReadAllText($profilePath,[Text.Encoding]::UTF8)|ConvertFrom-Json;$z|Add-Member raw $rawText -Force;$z|Add-Member exit_code $preflightExit -Force;Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue;return $z}catch{Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue;return [pscustomobject]@{status='fatal';fatal=@('无法解析数据体检结果。');warnings=@();raw=$rawText;exit_code=$preflightExit}}
}
function Show-Preflight($p){Write-Host "`n========== 数据体检报告 ==========" -ForegroundColor Cyan;Write-Host ("数据源：{0}`n样本量：{1}；题目数：{2}`n自动识别计分：{3}`n总体缺失率：{4}%" -f $p.source,$p.sample_size,$p.item_count,$p.scoring,$p.missing_pct);$zero=@($p.zero_variance|Where-Object{$_});if($zero.Count){Write-Host ('零方差题项：'+($zero-join'、')) -ForegroundColor Red}else{Write-Host '零方差题项：无' -ForegroundColor Green};@($p.warnings|Where-Object{$_})|ForEach-Object{Write-Host "提示：$_" -ForegroundColor Yellow};@($p.fatal|Where-Object{$_})|ForEach-Object{Write-Host "严重问题：$_" -ForegroundColor Red};Write-Host '==================================' -ForegroundColor Cyan}
if($Auto-and$Model){Stop-Friendly '-Auto 与 -m 不能同时使用。'};if($Eifa-and$Cifa){Stop-Friendly '-eifa 与 -cifa 不能同时使用。'};if(($Eifa-or$Cifa-or$DimRange-or$LoadingMatrix)-and$Model -ne 'mirt'){Stop-Friendly '-eifa、-cifa、-dim_range 和 -loading_matrix 仅能与 -m mirt 一起使用。'};if($Silent-and-not$ConfigJson-and-not$Config){Stop-Friendly '静默模式需要 JSON 配置：-Silent -ConfigJson .\config.json'};if($Silent-and$ConfigJson){$Config=$ConfigJson}
if($Config){$effectiveConfig=Resolve-ExistingPath $Config '配置文件'}elseif($Silent){Stop-Friendly '静默模式需要 JSON 配置。'}else{$interactive=(-not$Data-and-not$Model-and-not$Auto);$mode=if($Cifa){'cifa'}elseif($Eifa){'eifa'}else{$null};$effectiveConfig=New-RunConfig $Data $Model -Automatic:$Auto -Interactive:$interactive $mode $DimRange $LoadingMatrix;Write-Stage "已生成本次运行配置：$effectiveConfig" 'DarkCyan'}
if($Silent-and([IO.Path]::GetExtension($effectiveConfig).ToLowerInvariant() -ne '.json')){Stop-Friendly '静默模式只接受 JSON 配置。'}
try { $rscript = if ($Silent) { Initialize-PsychostatEnvironment } else { Initialize-PsychostatEnvironment -AllowAutoInstall } } catch { Stop-Friendly $_.Exception.Message }
$packages=Get-PsychostatRequiredPackages -Branch 'irt';$packageScript=Get-PsychostatPackageInstallScript -Packages $packages;Write-Stage '检查并安装 IRT 所需 R 包（只装缺的，已装自动跳过；国内镜像优先，失败自动换源）...';$previousEap=$ErrorActionPreference;$ErrorActionPreference='Continue';$packageLog=& $rscript --vanilla $packageScript 2>&1;$packageExit=$LASTEXITCODE;$ErrorActionPreference=$previousEap;Remove-Item -LiteralPath $packageScript -Force -ErrorAction SilentlyContinue;if($packageExit -ne 0){Stop-Friendly 'R 依赖包安装失败。请检查网络、R 权限和 CRAN 连接。' (($packageLog|Out-String).Trim())}
$profile=Invoke-Preflight $effectiveConfig $rscript;if($Silent){Write-JsonLog 'preflight' $profile}else{Show-Preflight $profile};$fatal=@($profile.fatal|Where-Object{$_});if($fatal.Count){Stop-Friendly ('数据体检发现严重问题：'+(($fatal|ForEach-Object{Format-Fatal "$_"})-join'；')) $profile.raw};if(-not$Silent){if((Read-MenuChoice '体检完成。是否开始模型拟合？' @('取消','继续运行') 2)-ne 2){Write-Host '已取消。' -ForegroundColor Yellow;exit 0}}
Write-Stage 'Running IRT analysis...'
$previousEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
$analysisLog=& $rscript --vanilla (Join-Path $root 'scripts\irt_generic_pipeline.R') --config-utf8-hex (ConvertTo-Utf8Hex $effectiveConfig) 2>&1
$analysisExit=$LASTEXITCODE; $ErrorActionPreference=$previousEap
if($analysisExit -ne 0){Stop-Friendly (Translate-RFailure (($analysisLog|Out-String).Trim())) (($analysisLog|Out-String).Trim())}
if(-not$Silent){$analysisLog|ForEach-Object{if("$_" -match '^(Detected |Fitting |Selected model:|Curve generation skipped:)'){Write-Host $_}}}
$autoLine=$analysisLog|ForEach-Object{"$_"}|Where-Object{$_ -match '^AUTO_BIC_RANKING='}|Select-Object -Last 1
$autoBicRanking=if($autoLine){($autoLine-replace'^AUTO_BIC_RANKING=','').Trim()}else{$null}
if($autoBicRanking-and-not$Silent){Write-Host "自动选模依据：候选模型按 BIC 排序（越低越好）为 $autoBicRanking；已选择 BIC 最低的模型。" -ForegroundColor Green}
$hexLine=$analysisLog|ForEach-Object{"$_"}|Where-Object{$_ -match '^RESULT_DIR_UTF8_HEX='}|Select-Object -Last 1;if(-not$hexLine){Stop-Friendly '分析完成但没有返回结果目录。'};$hex=($hexLine-replace'^RESULT_DIR_UTF8_HEX=','').Trim();[byte[]]$bytes=@(for($i=0;$i-lt$hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)});$resultDir=$utf8.GetString($bytes);if(-not(Test-Path -LiteralPath $resultDir)){Stop-Friendly '分析结果目录无法打开。'}
$pythonEnv=Initialize-PsychostatPythonEnvironment -ProjectRoot $root -Silent:$Silent;$reportNote=$null;if($pythonEnv.Ready){$reportNote='Word 结果报告：*_report_zh.docx / *_report_en.docx 已生成。';Write-Stage 'Creating bilingual results-style Word reports...';$oldPy=$ErrorActionPreference;$ErrorActionPreference='Continue';$reportLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_result_reports.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($resultDir))) 2>&1;$pyExit=$LASTEXITCODE;$ErrorActionPreference=$oldPy;if($pyExit -ne 0){Stop-Friendly '结果已生成，但 Word 报告生成失败。' (($reportLog|Out-String).Trim())};if(-not$Silent){$reportLog|ForEach-Object{if("$_"-match'^Created report:'){Write-Host $_}}}}elseif(-not$Silent){Write-Stage $pythonEnv.Note 'Yellow'; if([Environment]::UserInteractive){Read-Host '  （按回车键关闭窗口；Word 报告未生成，但分析与 CSV/图/Markdown 报告不受影响）'}}
# HTML 网页版报告（新增产物）：与 Word 报告解耦——Word 失败会 Stop，HTML 失败只黄字提示、不改变整体退出码；Python 缺席时沿用上方提示分支，不重复生成
$htmlName='irt_report_zh.html';$htmlFile=Join-Path $resultDir $htmlName;$htmlOk=$false
if($pythonEnv.Ready){$oldPy2=$ErrorActionPreference;$ErrorActionPreference='Continue';$htmlLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_html_report.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($resultDir))) 2>&1;$htmlExit=$LASTEXITCODE;$ErrorActionPreference=$oldPy2;if($htmlExit -eq 0 -and (($htmlLog|Out-String) -match 'HTML_REPORT_OK') -and (Test-Path -LiteralPath $htmlFile)){$htmlOk=$true;if(-not $Silent){Start-Process -FilePath $htmlFile}}elseif(-not $Silent){Write-Host "  网页版报告 $htmlName 未生成，其余产物（CSV/图/Word/Markdown）不受影响。" -ForegroundColor Yellow}}   # 静默模式供 AI/批处理调用，绝不开窗口：仅在交互模式用默认浏览器打开
if($Silent){Write-JsonLog 'complete' @{result_dir=$resultDir;config=$effectiveConfig;auto_bic_ranking=$autoBicRanking;report_note=$reportNote;html_report=$(if($htmlOk){$htmlName}else{$null})}}else{Write-Stage "Complete. Results: $resultDir" 'Green'; if($htmlOk){Write-Host "  → 网页版报告 $htmlName（已在浏览器打开）。" -ForegroundColor DarkCyan}}