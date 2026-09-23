param(
    [Alias('c')][string]$Config,
    [Alias('d')][string]$Data,
    [ValidateSet('quality','efa','cfa')][string]$Goal,
    [Alias('m')][string]$Mapping,
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
$script:PsychostatStagePrefix = '[Psychostat CTT] '
$script:PsychostatRFailureTable = @(
  @('CFA 路线需要|mapping|item,dimension|CFA requires', 'CFA 的题目-维度对照表无效或缺省：需要含 item,dimension 两列的 CSV/Excel，每题只归属一个维度且不遗漏。'),
  @('5%.*20%|5%%.*20%%', '存在每人 5%–20% 的缺失。请先检查缺失机制，然后在配置中将 cleaning.missing_5_to_20 设为 listwise 或 median_impute。'),
  @('KMO|Bartlett', 'EFA 前提不满足：KMO 必须大于 .60 且 Bartlett 检验 p < .05。请检查样本量、题目相关性和无效题项。'),
  @('fewer than three items|at least three items', '可用题目不足或每个因子少于3题。请核对 item_columns、反向题列名和对照表。'),
  @('did not converge|not converge', 'CFA 未收敛。请检查每因子题数、极端相关（≥.85）、样本量和模型设定；必要时改用独立样本。')
)
$script:PsychostatRFailureFallback = 'R 分析未完成。请检查数据列名、量表计分和配置；可使用 -Verbose 查看原始诊断。'
$script:PsychostatDataFileTitle = '选择 CTT 量表数据文件'

function Resolve-CfaMapping($Path,[switch]$Prompt){
  while($true){
    if(-not $Path -and $Prompt){$Path=Select-PsychostatFile -Title '选择题目-维度对照表（含 item,dimension 两列）' -Filter '对照表 CSV/Excel|*.csv;*.xlsx;*.xls|所有文件|*.*'; if(-not $Path){$Path=Read-Host '（也可直接粘贴路径）题目-维度对照表路径（CSV/Excel，两列：item,dimension；模板见 examples\ctt_cfa_mapping_template.csv）'}}
    if(-not $Path){Stop-Friendly 'CFA 路线需要题目-维度对照表（含 item,dimension 两列的 CSV/Excel）。'}
    $p=Resolve-ExistingPath $Path '题目-维度对照表'
    if([IO.Path]::GetExtension($p).ToLowerInvariant() -in '.csv','.xlsx','.xls'){return $p}
    if(-not $Prompt){Stop-Friendly '题目-维度对照表必须为 CSV 或 Excel 文件。'}
    Write-Host '请选择 CSV、XLSX 或 XLS 文件。' -ForegroundColor Yellow; $Path=$null
  }
}
function New-InteractiveConfig($ExistingData,$RequestedGoal,$RequestedMapping){
  $mode=if($ExistingData){'file'}else{(Read-MenuChoice '选择数据来源' @('使用内置模拟量表数据（480人×15题，推荐体验流程）','使用我的数据文件（打开文件选择框）') 1)}
  $dataPath=$null; $sim=$false
  if($ExistingData){$dataPath=Resolve-ExistingPath $ExistingData '数据文件'}
  elseif($mode -eq 2){$dataPath=Select-DataFile}
  else{$sim=$true}
  $goal=$RequestedGoal
  if(-not $goal){
    Write-Host "`n同一份数据不建议既做EFA又做CFA：EFA找到的结构再拿同一批人做CFA只是\"内部验证\"。" -ForegroundColor DarkYellow
    Write-Host "真正的验证性证据应来自独立样本或预先指定的理论结构。" -ForegroundColor DarkYellow
    $goal=@('quality','efa','cfa')[(Read-MenuChoice '选择分析路线（与IRT的探索/验证选择一致）' @(
      '量表质量检查：清洗+项目分析+信度+校标/已知组效度（不做因子分析）',
      '质量 + EFA 探索性因子分析：数据驱动地找出结构（适合还没有预设结构时）',
      '质量 + CFA 验证性因子分析：验证你预先指定的结构（需要题目-维度对照表）') 2)-1]
  }
  $mapping=$null
  if($goal -eq 'cfa'){
    if($sim){Write-Host "`n模拟演示的 CFA 将自动使用模拟数据的真实结构（每5题一个维度）作为对照表。" -ForegroundColor DarkCyan}
    else{$mapping=$RequestedMapping; if(-not $mapping){$mapping=Resolve-CfaMapping $null -Prompt}else{$mapping=Resolve-CfaMapping $mapping}}
  }
  $k=5;while($true){$x=Read-Host '量表最高分 k（Likert 5级输入 5；回车默认 5）';if([string]::IsNullOrWhiteSpace($x)){break};$n=0;if([int]::TryParse($x,[ref]$n)-and$n -ge 2-and$n -le20){$k=$n;break};Write-Host '请输入 2–20 的整数。' -ForegroundColor Yellow}
  $rev=Read-Host '反向题列名，用逗号分隔（没有则直接回车）';$criterion=Read-Host '校标列名（没有则直接回车）';$group=Read-Host '已知组分组列名（没有则直接回车）'
  $itemCols='auto';if(-not $sim){$x=Read-Host '题目列名，用逗号分隔（直接回车=自动识别；自动识别会先做安全检查，若发现疑似 年龄/性别/ID/总分 等非题目列将要求你显式指定）';if(-not[string]::IsNullOrWhiteSpace($x)){$itemCols=@($x.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_})}}
  $obj=[ordered]@{input=[ordered]@{mode=if($sim){'simulate'}else{'file'};path=$(if($dataPath){$dataPath}else{$null});id_column=$null;item_columns=$itemCols};cleaning=[ordered]@{scale_maximum=$k;reverse_items=$(if($rev){@($rev.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_})}else{@()});missing_5_to_20='stop';attention_item=$(if($sim){'attention_check'}else{$null});attention_correct_value=$(if($sim){3}else{$null});response_time_column=$(if($sim){'response_time_sec'}else{$null});minimum_response_seconds=$(if($sim){45}else{$null});straightline_action='flag';extreme_action='flag'};analysis=[ordered]@{goal=$goal;n_factors='auto';max_efa_iterations=10;rotation='promax';cfa_source=$(if($goal -eq 'cfa'){'file'}else{'skip'});cfa_mapping=$(if($mapping){$mapping}else{''});criterion_column=$(if($criterion){$criterion}else{$null});criterion_direction='positive';known_group_column=$(if($group){$group}else{$null})};output=[ordered]@{directory=(Join-Path $root 'outputs');project_label='interactive_ctt';report_language='zh'}}
  if($goal -eq 'efa'){$obj.analysis.rotation=@('promax','varimax')[(Read-MenuChoice 'EFA 旋转方法' @('Promax（允许因子相关，推荐）','Varimax（正交旋转）') 1)-1]}
  $file=Join-Path $env:TEMP ('psychostat_ctt_{0}.json'-f(Get-Date -Format 'yyyyMMdd_HHmmss'));[IO.File]::WriteAllText($file,($obj|ConvertTo-Json -Depth 10),$utf8);$file
}
function New-QuickConfig($DataPath,$GoalValue,$MappingPath){
  # 快捷命令（类似IRT的 -m 快捷方式）：带参数时不再逐项提问，未指定项用稳妥默认值。
  $sim = -not $DataPath
  if($GoalValue -eq 'cfa' -and -not $sim -and -not $MappingPath){Stop-Friendly 'CFA 快捷命令需要 -Mapping 题目-维度对照表。'}
  $resolvedMapping = $null
  if($GoalValue -eq 'cfa' -and $MappingPath){$resolvedMapping = Resolve-CfaMapping $MappingPath}
  $obj=[ordered]@{input=[ordered]@{mode=if($sim){'simulate'}else{'file'};path=$(if($DataPath){$DataPath}else{$null});id_column=$null;item_columns='auto'};cleaning=[ordered]@{scale_maximum=5;reverse_items=@();missing_5_to_20='median_impute';attention_item=$(if($sim){'attention_check'}else{$null});attention_correct_value=$(if($sim){3}else{$null});response_time_column=$(if($sim){'response_time_sec'}else{$null});minimum_response_seconds=$(if($sim){45}else{$null});straightline_action='flag';extreme_action='flag'};analysis=[ordered]@{goal=$GoalValue;n_factors='auto';max_efa_iterations=10;rotation='promax';cfa_source=$(if($GoalValue -eq 'cfa'){'file'}else{'skip'});cfa_mapping=$(if($resolvedMapping){$resolvedMapping}else{''});criterion_column=$(if($sim){'criterion'}else{$null});criterion_direction='positive';known_group_column=$(if($sim){'known_group'}else{$null})};output=[ordered]@{directory=(Join-Path $root 'outputs');project_label="quick_ctt_$GoalValue";report_language='zh'}}
  $file=Join-Path $env:TEMP ('psychostat_ctt_{0}.json'-f(Get-Date -Format 'yyyyMMdd_HHmmss'));[IO.File]::WriteAllText($file,($obj|ConvertTo-Json -Depth 10),$utf8);$file
}
if($Silent -and -not $ConfigJson -and -not $Config){Stop-Friendly '静默模式必须提供 JSON 配置：-Silent -ConfigJson .\my_ctt_config.json'}
if($Silent -and $ConfigJson){$Config=$ConfigJson}
if($Goal -eq 'cfa' -and $Data -and -not $Mapping){Stop-Friendly '用 -Goal cfa 分析自己的数据时必须同时提供 -Mapping 题目-维度对照表（CSV/Excel，两列 item,dimension）。'}
if($Simulate){if($Config -or $Data -or $Goal){Stop-Friendly '-Simulate 不可与 -Config、-Data 或 -Goal 同时使用。'};$effective=Join-Path $root 'ctt_config.yaml'}
elseif($Config){$effective=Resolve-ExistingPath $Config '配置文件'}
elseif($Goal -and $Data){$p=Resolve-ExistingPath $Data '数据文件';$effective=New-QuickConfig $p $Goal $Mapping; Write-Stage "本次配置：$effective" 'DarkCyan'}
elseif($Goal){$effective=New-QuickConfig $null $Goal $Mapping; Write-Stage "本次配置：$effective" 'DarkCyan'}
elseif($Silent){Stop-Friendly '静默模式需要 JSON 配置。'}
else{$effective=New-InteractiveConfig $Data $null $Mapping; Write-Stage "本次配置：$effective" 'DarkCyan'}
if($Silent -and([IO.Path]::GetExtension($effective).ToLowerInvariant() -ne '.json')){Stop-Friendly '静默模式仅接受 JSON 配置。'}
try { $rscript = if ($Silent) { Initialize-PsychostatEnvironment } else { Initialize-PsychostatEnvironment -AllowAutoInstall } } catch { Stop-Friendly $_.Exception.Message }
$packages=Get-PsychostatRequiredPackages -Branch 'ctt';$packageScript=Get-PsychostatPackageInstallScript -Packages $packages;Write-Stage '检查并安装 CTT 所需 R 包（只装缺的，已装自动跳过；国内镜像优先，失败自动换源；psych=项目分析/信度/EFA，lavaan=CFA）...';$previousEap=$ErrorActionPreference;$ErrorActionPreference='Continue';$packageLog=& $rscript --vanilla $packageScript 2>&1;$packageExit=$LASTEXITCODE;$ErrorActionPreference=$previousEap;Remove-Item -LiteralPath $packageScript -Force -ErrorAction SilentlyContinue;if($packageExit -ne 0){Stop-Friendly (Translate-RFailure (($packageLog|Out-String).Trim())) (($packageLog|Out-String).Trim())}
if(-not $Silent){$confirm=Read-MenuChoice '即将开始分析（清洗→项目分析→信度→按所选路线出结果）。是否继续？' @('取消','继续运行') 2;if($confirm -ne 2){Write-Host '已取消。' -ForegroundColor Yellow; exit 0}}
Write-Stage '运行数据清洗、项目分析、信效度与所选路线（EFA 或 CFA）...';$old=$ErrorActionPreference;$ErrorActionPreference='Continue';$log=& $rscript --vanilla (Join-Path $root 'scripts\ctt_pipeline.R') --config-utf8-hex (ConvertTo-Utf8Hex $effective) 2>&1;$exit=$LASTEXITCODE;$ErrorActionPreference=$old;if($exit -ne 0){Stop-Friendly (Translate-RFailure (($log|Out-String).Trim())) (($log|Out-String).Trim())}
# 把 R 端的关键诊断显示出来（只增加显示，不改任何计算；-Silent 模式完全不变）。
# 起因：**零方差题会被自动识别静默排除**（10 题变 9 题），而 R 的那句"注意：以下列零方差…已排除"
# 此前只存在于被丢弃的 $log 里——屏幕上、run_log.txt 里、报告里都看不到，
# 用户会在不知情的情况下少分析一道题。"纳入哪些题"同理，属于必须可见的预处理信息。
if(-not $Silent){
  $diag = @($log | ForEach-Object { "$_" } | Where-Object { $_ -match '^(注意|题目列自动识别|数值列自动识别|平行分析|分析路线|统计核心包|CFA 估计口径|列名说明)' })
  if($diag.Count){ Write-Host ''; $diag | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkCyan } }
}
$line=$log|ForEach-Object{"$_"}|Where-Object{$_ -match '^RESULT_DIR_UTF8_HEX='}|Select-Object -Last 1;if(-not $line){Stop-Friendly '分析没有返回结果目录。' (($log|Out-String).Trim())};$hex=($line -replace '^RESULT_DIR_UTF8_HEX=','').Trim();[byte[]]$bytes=@(for($i=0;$i-lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)});$result=$utf8.GetString($bytes)
$pythonEnv=Initialize-PsychostatPythonEnvironment -ProjectRoot $root -Silent:$Silent;$reportNote=$null;if($pythonEnv.Ready){$reportNote='Word 结果报告：ctt_report_zh.docx 已生成。';Write-Stage '生成 Word 结果报告...';$oldPy=$ErrorActionPreference;$ErrorActionPreference='Continue';$reportLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_ctt_report.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($result))) 2>&1;$pyExit=$LASTEXITCODE;$ErrorActionPreference=$oldPy;if($pyExit -ne 0){Stop-Friendly '分析结果已生成，但 Word 报告生成失败。' (($reportLog|Out-String).Trim())}}elseif(-not $Silent){Write-Stage $pythonEnv.Note 'Yellow'; if([Environment]::UserInteractive){Read-Host '  （按回车键关闭窗口；Word 报告未生成，但分析与 CSV/图/Markdown 报告不受影响）'}}
# HTML 网页版报告（新增产物）：与 Word 报告解耦——Word 失败会 Stop，HTML 失败只黄字提示、不改变整体退出码；Python 缺席时沿用上方提示分支，不重复生成
$htmlName='ctt_report_zh.html';$htmlFile=Join-Path $result $htmlName;$htmlOk=$false
if($pythonEnv.Ready){$oldPy2=$ErrorActionPreference;$ErrorActionPreference='Continue';$htmlLog=& $pythonEnv.Path -X utf8 (Join-Path $root 'scripts\generate_html_report.py') --result-dir-utf8-base64 ([Convert]::ToBase64String($utf8.GetBytes($result))) 2>&1;$htmlExit=$LASTEXITCODE;$ErrorActionPreference=$oldPy2;if($htmlExit -eq 0 -and (($htmlLog|Out-String) -match 'HTML_REPORT_OK') -and (Test-Path -LiteralPath $htmlFile)){$htmlOk=$true;if(-not $Silent){Start-Process -FilePath $htmlFile}}elseif(-not $Silent){Write-Host "  网页版报告 $htmlName 未生成，其余产物（CSV/图/Word/Markdown）不受影响。" -ForegroundColor Yellow}}   # 静默模式供 AI/批处理调用，绝不开窗口：仅在交互模式用默认浏览器打开
if($Silent){Write-JsonLog 'complete' @{result_dir=$result;config=$effective;report_note=$reportNote;html_report=$(if($htmlOk){$htmlName}else{$null})}}else{Write-Stage "完成。结果目录：$result" 'Green'; if($htmlOk){Write-Host "  → 网页版报告 $htmlName（已在浏览器打开）。" -ForegroundColor DarkCyan}}
