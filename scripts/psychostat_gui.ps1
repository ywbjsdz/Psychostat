# Psychostat 图形化应用 · 分步向导版（Windows / PowerShell 自带 WinForms，零依赖）
# 设计原则：GUI 只负责“收集参数 → 生成配置 → 调用现有 R 管线 → 展示输出”，
#           不重复实现任何统计逻辑（scripts/ 下核心代码保持不变）。
# 交互：左侧切换分支与步骤，每步只显示当前要做的事，用“上一步 / 下一步”逐步推进。
#
# 用法：.\启动Psychostat界面.bat
#      powershell -STA -File scripts\psychostat_gui.ps1
#      powershell -STA -File scripts\psychostat_gui.ps1 -SelfTest   （构建界面但不显示，供自动检查）
param([switch]$SelfTest, [switch]$SelfTestAnalysis)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $root 'psychostat_env.ps1')     # Select-PsychostatFile / Select-HighestRVersion / Install-* 等
$ErrorActionPreference = 'Continue'

# locale 防护：若本进程从带 LANG/LC_* 的终端（如 Git Bash）启动，中文路径下的 R（如 D:\工具\R-4.5.2）
# 会启动失败（"compiler 命名空间不可用"、base 包找不到）。启动时统一清除，后台任务继承干净环境。
# （终端启动器经由 Initialize-PsychostatEnvironment 已有同样清理，此处补齐 GUI 入口。）
Remove-Item Env:LANG, Env:LC_ALL, Env:LC_CTYPE -ErrorAction SilentlyContinue

# ── 常量 ──────────────────────────────────────────────────────────────────────
$script:StatsMethods = [ordered]@{
  descriptives            = '描述统计（M/SD/偏度峰度/Z分数）'
  normality               = '正态性与方差齐性检验'
  one_sample_t            = '单样本t检验'
  independent_t           = '独立样本t检验'
  paired_t                = '配对样本t检验'
  one_way_anova           = '单因素方差分析'
  two_way_anova           = '两因素方差分析（主效应+交互+简单效应）'
  rm_anova                = '重复测量方差分析'
  mixed_anova             = '混合设计方差分析'
  ancova                  = '协方差分析（ANCOVA）'
  correlation             = '相关分析（含偏相关）'
  regression              = '多元线性回归'
  chi_square_gof          = '卡方适合度检验'
  chi_square_independence = '卡方独立性检验'
  mann_whitney            = 'Mann-Whitney U检验'
  wilcoxon_signed         = 'Wilcoxon符号秩检验'
  kruskal_wallis          = 'Kruskal-Wallis H检验'
  friedman                = 'Friedman检验'
  mediation               = '中介效应分析（Bootstrap）'
  moderation              = '调节效应分析（简单斜率）'
  power                   = '统计功效与样本量（不需数据）'
}
$script:FieldMeta = [ordered]@{
  dv             = @{ label = '因变量（结果变量）'; type = 'single' }
  group          = @{ label = '分组变量'; type = 'single' }
  dv1            = @{ label = '前测列'; type = 'single' }
  dv2            = @{ label = '后测列'; type = 'single' }
  factor_a       = @{ label = '自变量 A'; type = 'single' }
  factor_b       = @{ label = '自变量 B'; type = 'single' }
  between        = @{ label = '被试间因子'; type = 'single' }
  id             = @{ label = '被试编号列（可留空）'; type = 'single' }
  covariate      = @{ label = '协变量'; type = 'single' }
  category       = @{ label = '分类变量'; type = 'single' }
  row_var        = @{ label = '行变量'; type = 'single' }
  col_var        = @{ label = '列变量'; type = 'single' }
  x              = @{ label = '自变量 X'; type = 'single' }
  m              = @{ label = '中介变量 M'; type = 'single' }
  y              = @{ label = '因变量 Y'; type = 'single' }
  interaction_x  = @{ label = '自变量 X'; type = 'single' }
  interaction_z  = @{ label = '调节变量 Z'; type = 'single' }
  interaction_dv = @{ label = '因变量 Y'; type = 'single' }
  columns        = @{ label = '要分析的数值列'; type = 'multi' }
  within         = @{ label = '重复测量各时间点列（按时间顺序勾选）'; type = 'multi' }
  predictors     = @{ label = '自变量列'; type = 'multi' }
  mu             = @{ label = '检验值 μ（与哪个总体常模比较；留空=50）'; type = 'value' }
}
$script:MethodFields = @{
  descriptives=@('columns'); normality=@('dv','group'); one_sample_t=@('dv','mu'); independent_t=@('dv','group')
  paired_t=@('dv1','dv2'); one_way_anova=@('dv','group'); two_way_anova=@('dv','factor_a','factor_b')
  rm_anova=@('within','id'); mixed_anova=@('within','between','id'); ancova=@('dv','group','covariate')
  correlation=@('columns'); regression=@('dv','predictors'); chi_square_gof=@('category')
  chi_square_independence=@('row_var','col_var'); mann_whitney=@('dv','group'); wilcoxon_signed=@('dv1','dv2')
  kruskal_wallis=@('dv','group'); friedman=@('within'); mediation=@('x','m','y')
  moderation=@('interaction_x','interaction_z','interaction_dv'); power=@()
}
$script:StatsPkgs = 'yaml jsonlite car emmeans nortest onewaytests pwr ggplot2 readxl haven MASS'
$script:CttPkgs   = 'yaml jsonlite psych lavaan GPArotation ggplot2 readxl haven MASS'
$script:IrtPkgs   = 'yaml jsonlite mirt psych ggplot2 readxl haven'

# 方法中文名与一句话理由（与终端 run_stats_analysis.ps1 的 MethodCatalog 同口径）
$script:MethodCatalog = [ordered]@{
  descriptives            = @{ zh = '描述统计';              tip = '给数据画像（M/SD/偏度峰度/Z分数）——任何分析的第一步' }
  normality               = @{ zh = '正态性与方差齐性检验';  tip = '检验 t/ANOVA 的前提：Shapiro-Wilk、K-S、Levene' }
  one_sample_t            = @{ zh = '单样本t检验';           tip = '样本均值 vs 已知总体值（常模）' }
  independent_t           = @{ zh = '独立样本t检验';         tip = '两组不同的人比较均值（男 vs 女）' }
  paired_t                = @{ zh = '配对样本t检验';         tip = '同一批人前后测比较' }
  one_way_anova           = @{ zh = '单因素方差分析';        tip = '一个自变量、≥3组（含LSD/Tukey/Bonferroni事后）' }
  two_way_anova           = @{ zh = '两因素方差分析';        tip = '两个自变量：主效应+交互+简单效应（三步闭环）' }
  rm_anova                = @{ zh = '重复测量方差分析';      tip = '同一批人测≥3次（Mauchly球形+GG/HF校正）' }
  mixed_anova             = @{ zh = '混合设计方差分析';      tip = '一组被试间×一组被试内（干预/对照 × 前中后测）' }
  ancova                  = @{ zh = '协方差分析';            tip = '控制前测/智商等连续变量后比较组间' }
  correlation             = @{ zh = '相关分析（含偏相关）';  tip = '两个连续变量的关联；控制第三变量用偏相关' }
  regression              = @{ zh = '多元线性回归';          tip = '多个自变量预测连续因变量（含交互与简单斜率）' }
  chi_square_gof          = @{ zh = '卡方适合度检验';        tip = '单个分类变量的分布 vs 理论比例' }
  chi_square_independence = @{ zh = '卡方独立性检验';        tip = '两个分类变量是否关联（性别×择业偏好）' }
  mann_whitney            = @{ zh = 'Mann-Whitney U检验';   tip = '两组独立但数据偏态/等级（t的替代）' }
  wilcoxon_signed         = @{ zh = 'Wilcoxon符号秩检验';    tip = '前后测但差值偏态/等级（配对t的替代）' }
  kruskal_wallis          = @{ zh = 'Kruskal-Wallis H检验'; tip = '≥3组独立但偏态/等级（ANOVA的替代）' }
  friedman                = @{ zh = 'Friedman检验';         tip = '≥3次重复测量但偏态/等级（重复测量ANOVA的替代）' }
  mediation               = @{ zh = '中介效应分析';          tip = 'X如何通过M影响Y（PROCESS Model 4，Bootstrap 5000）' }
  moderation              = @{ zh = '调节效应分析';          tip = 'X的效应何时/对谁更强（PROCESS Model 1，简单斜率+交互图）' }
  power                   = @{ zh = '统计功效与样本量';      tip = '开题算样本量（对应G*Power），不需要数据' }
}

# 方法选择向导的决策树（与终端 Invoke-DecisionWizard 同口径）：Next=下一问题键，Rec=直接推荐
$script:GuideTree = @{
  q1        = @{ Text = '问题 1：你的因变量（要解释的结果变量）是什么类型？'; Options = @(
      @{ T = '连续数据（考试分数、焦虑总分等，取值精细）';           Next = 'q2c' }
      @{ T = '分类数据（及格/不及格、A/B/C/D 偏好等，数个数）';       Next = 'q2a' }
      @{ T = '等级数据或严重偏态（排名、1-7满意度且分布很偏）';       Next = 'q2b' } ) }
  q2a       = @{ Text = '问题 2：分类变量涉及几个？'; Options = @(
      @{ T = '1 个：想知道它的分布是否符合理论比例';                  Rec = 'chi_square_gof' }
      @{ T = '2 个：想知道它们是否相互关联';                          Rec = 'chi_square_independence' } ) }
  q2b       = @{ Text = '问题 2：比较几组 / 几次测量？'; Options = @(
      @{ T = '2 组，两组是不同的人（独立）';                          Rec = 'mann_whitney' }
      @{ T = '2 次，同一批人前后测（配对）';                          Rec = 'wilcoxon_signed' }
      @{ T = '≥3 组，各组是不同的人（独立）';                         Rec = 'kruskal_wallis' }
      @{ T = '≥3 次，同一批人重复测量';                               Rec = 'friedman' } ) }
  q2c       = @{ Text = '问题 2：你的研究目的是？'; Options = @(
      @{ T = '比较差异：不同组/不同条件的均值是否不同';               Next = 'q3diff' }
      @{ T = '看关系：变量之间是否相关，或用 X 预测 Y';               Next = 'q3rel' }
      @{ T = '先检查数据前提：正态性 / 方差齐性（推荐先做）';         Rec = 'normality' } ) }
  q3rel     = @{ Text = '问题 3：想描述关联还是要做预测模型？'; Options = @(
      @{ T = '描述变量的关联强度（相关；控制第三变量选偏相关）';      Rec = 'correlation' }
      @{ T = '用一个或多个 X 预测 Y，看各自独特贡献（回归）';         Rec = 'regression' } ) }
  q3diff    = @{ Text = '问题 3：自变量有几个？各几个水平？'; Options = @(
      @{ T = '1 个自变量，2 个水平（两组）';                          Next = 'q4paired' }
      @{ T = '1 个自变量，≥3 个水平';                                 Rec = 'one_way_anova' }
      @{ T = '2 个自变量（如 教学法×动机），关注主效应和交互';        Rec = 'two_way_anova' }
      @{ T = '只有"时间"一个被试内变量（同一批人测 ≥3 次）';          Rec = 'rm_anova' }
      @{ T = '一个被试间 + 一个被试内（如 组别×前中后测）';           Rec = 'mixed_anova' }
      @{ T = '想控制一个连续协变量后比组间（ANCOVA）';                Rec = 'ancova' } ) }
  q4paired  = @{ Text = '问题 4：两组是不同的人，还是同一批人测两次？'; Options = @(
      @{ T = '不同的人（独立）';                                      Rec = 'independent_t' }
      @{ T = '同一批人（配对）';                                      Rec = 'paired_t' } ) }
}
$script:GuideState = @{ Path = @(); Rec = $null }

# ── 视觉主题（集中定义；全文件颜色字面量只允许出现在这里）────────────────────
# 为什么集中：此前约 40 处 FromArgb 散落各函数里，改一个色要全局搜且易出现
# 「同义不同值」（如三种近似绿）；统一入口后换主题只改这一张表。
# 文字对比度按 WCAG AA 选值：深色字（primary/textBody/textMuted）配浅底；
# warning 只用于图形件（圆点/进度段，AA 图形件要求 3:1），正文用更深的 warningText。
$script:Theme = [ordered]@{
    primary        = '#1C3C6C'   # 主色·深蓝：顶栏 / 主操作按钮 / 强调文字（白底上 ≈ 11:1）
    accent         = '#2D6CB5'   # 强调蓝：当前进度段 / 次要按钮描边与文字（白底上 ≈ 5.3:1）
    success        = '#1E783C'   # 成功绿：就绪 / 已完成段 / 成功状态文字（白底上 ≈ 5.5:1）
    warning        = '#C77C0A'   # 警示橙：黄灯圆点（仅图形，≥3:1）
    warningText    = '#9A5F06'   # 警示文字用更深的橙（白底上 ≈ 5.2:1，满足 AA 正文）
    danger         = '#AA3C28'   # 错误红：红灯 / 失败状态 / 危险操作文字（白底上 ≈ 6.2:1）
    bg             = '#F8F9FC'   # 窗体与内容区底色（卡片之外的留白）
    card           = '#FFFFFF'   # 卡片白：步骤内容卡 / 按钮白底
    border         = '#D9DEE8'   # 卡片浅灰描边（当前以 FixedSingle 系统描边呈现同层级观感）
    navBg          = '#F0F3F8'   # 左导航底
    bottomBg       = '#F4F6FA'   # 底部状态栏底
    navActive      = '#D6E8FA'   # 左导航当前项高亮
    accentSoft     = '#DCECFA'   # 主色浅底：卡片上的进入按钮 / 完成脉冲高亮档
    successSoft    = '#D6ECD8'   # 成功浅底（保留旧版「开始分析」按钮的语义色系备用）
    onPrimaryMuted = '#D2DEF0'   # 深蓝底上的次级文字（≈ 8:1）
    textBody       = '#3C465A'   # 正文深灰蓝（白底上 > 7:1）
    textMuted      = '#6E7482'   # 说明性灰字（白底上 ≈ 4.7:1，满足 AA）
    logBg          = '#FCFCFE'   # 日志区微灰白（与卡片白区分）
    btnBorder      = '#C8D2E1'   # 普通按钮描边
    separator      = '#C4CAD6'   # 分隔线灰
    segPending     = '#3D5578'   # 顶栏三段进度「未到」段（深蓝底上的暗一格）
}
function Get-ThemeColor([string]$Name) {
    # 唯一取色入口：名字写错时抛错而非默默给黑色，让自检能暴露拼写问题
    $hex = $script:Theme[$Name]
    if (-not $hex) { throw "主题色未定义：$Name" }
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}
function New-ThemeBrush([string]$Name) {
    # 供将来 GDI+ 自绘场景的小工具；当前主题全部用控件属性表达，暂无调用方
    return (New-Object System.Drawing.SolidBrush((Get-ThemeColor $Name)))
}

# ── 全局状态 ──────────────────────────────────────────────────────────────────
$script:Task = $null; $script:TaskTimer = $null; $script:HeartbeatTimer = $null
$script:LogBox = $null; $script:StatusLabel = $null; $script:RunButtons = @()
$script:OpenResultBtn = $null; $script:OpenReportBtn = $null; $script:CancelBtns = @(); $script:HomeBtn = $null
$script:LastResultDir = $null; $script:TaskStarted = $null; $script:TaskTick = 0
$script:CachedR = $null; $script:CachedPy = $null
$script:TaskSegment = 0; $script:SegPanels = @(); $script:SegCaptions = @()   # 三段进度状态与控件
$script:SegLabel = $null; $script:HeaderPanel = $null                         # 三段进度所在顶栏与引导标签（供 Resize 布局）
$script:PulseTimer = $null                                                    # 完成脉冲定时器（防 GC 必须挂 script 级）
$script:EnvState = $null                                                      # 顶部 R/Python 状态灯控件组
$script:LastTaskBranch = 'stats'                                              # 本次任务所属分支（决定打开哪个 HTML 报告）
$script:AppPages = @{}; $script:PageHost = $null; $script:StepButtons = @{}; $script:BranchButtons = @{}
$script:CurrentBranch = 'home'; $script:CurrentStep = 1
$script:Wizard = @{ home = @(); stats = @(); ctt = @(); irt = @() }
$script:CenterBand = 740     # 步骤内容带固定宽度；窗体更宽时左右留白使其水平居中
$script:StepsLabel = $null   # 左侧“步骤”标签（首页视图下隐藏）
$script:StatsDataColumns = @(); $script:StatsFile = ''; $script:CttFile = ''; $script:CttMap = ''; $script:IrtFile = ''; $script:IrtMap = ''

# ── 环境探测（结果缓存，避免每次点击都扫盘）──────────────────────────────────
function Get-RscriptPath {
    if ($script:CachedR -and (Test-Path -LiteralPath $script:CachedR)) { return $script:CachedR }
    $rs = $null
    try {
        if (Test-Path -LiteralPath 'D:\') {
            $rs = Select-HighestRVersion @(Get-ChildItem -Path 'D:\R-*\bin\Rscript.exe','D:\*\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
        if (-not $rs) { $c = Get-Command Rscript.exe -ErrorAction SilentlyContinue; if ($c) { $rs = $c.Source } }
        if (-not $rs) {
            foreach ($hive in 'HKLM:\SOFTWARE\R-core\R','HKCU:\SOFTWARE\R-core\R') {
                $reg = Get-ItemProperty $hive -ErrorAction SilentlyContinue
                if ($reg -and $reg.InstallPath) { $cand = Join-Path $reg.InstallPath 'bin\Rscript.exe'; if (Test-Path -LiteralPath $cand) { $rs = $cand; break } }
            }
        }
        if (-not $rs) { $rs = Select-HighestRVersion @(Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe','C:\R\*\bin\Rscript.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) }
    } catch { }
    $script:CachedR = $rs
    return $rs
}
function Get-PythonPath {
    # 仅用于界面状态显示（"Python：已就绪/未安装"）。**实际运行 结果报告一律走
    # Initialize-PsychostatPythonEnvironment**（见 New-AnalysisScript 生成的任务脚本）：
    # 只有那套逻辑会校验 pandas/python-docx、缺依赖时自动安装（清华源→官方源回退），
    # 并设置 PYTHONUSERBASE —— 依赖可能被装进随解释器走的 <python>\Psychostat-Python-User 目录，
    # 缺少该环境变量的进程在 sys.path 上看不到它们，会报 ModuleNotFoundError: No module named 'pandas'。
    if ($script:CachedPy -and (Test-Path -LiteralPath $script:CachedPy)) { return $script:CachedPy }
    $py = $null
    foreach ($n in @('python.exe','py.exe')) { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { $py = $c.Source; break } }
    if (-not $py -and (Test-Path -LiteralPath 'D:\')) {
        $py = Get-ChildItem -Path 'D:\Python*\python.exe','D:\*\Python*\python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
    # 命中 py 启动器时解析成真正的解释器路径：py.exe 只是转发器，其默认解释器可能随环境变化，
    # 显示（以及历史上作为运行命令）一个转发器路径既不准也容易选错解释器。
    if ($py -and (Split-Path -Leaf $py) -ieq 'py.exe') {
        $resolved = & $py -c 'import sys;print(sys.executable)' 2>$null | Select-Object -Last 1
        if ($resolved -and (Test-Path -LiteralPath $resolved.Trim())) { $py = $resolved.Trim() }
    }
    $script:CachedPy = $py
    return $py
}

# ── 日志与任务执行 ────────────────────────────────────────────────────────────
function Write-LogLine($s) {
    # 任务运行期间锁定到任务启动时的日志控件，避免用户切换步骤后日志丢失
    $target = if ($script:Task -and $script:Task.LogBox) { $script:Task.LogBox } else { $script:LogBox }
    if (-not $target) { return }
    try {
        $target.AppendText($s)
        $target.SelectionStart = $target.TextLength
        $target.ScrollToCaret()
    } catch { }
}
function Get-BranchHtmlName([string]$Branch) {
    # 结果目录 HTML 文件名契约（与 scripts/generate_html_report.py 及任务脚本约定一致，勿改）：
    # stats→stats_report_zh.html；CTT→ctt_report_zh.html；IRT→irt_report_zh.html
    switch ($Branch) { 'ctt' { return 'ctt_report_zh.html' } 'irt' { return 'irt_report_zh.html' } default { return 'stats_report_zh.html' } }
}
function Set-TaskSegment([int]$Segment, [switch]$Completed) {
    # 三段进度指示（装 R 包 → 跑分析 → 出报告）：未到=暗一格 / 当前=强调蓝 / 已完成=绿；
    # $Completed 表示任务成功收尾（三段全绿）。静态填充，不做动画。
    if (-not $script:SegPanels -or $script:SegPanels.Count -lt 3) { return }
    for ($i = 0; $i -lt 3; $i++) {
        $n = $i + 1
        $fillName = 'segPending'
        if ($Completed -or $n -lt $Segment) { $fillName = 'success' } elseif ($n -eq $Segment) { $fillName = 'accent' }
        $script:SegPanels[$i].BackColor = Get-ThemeColor $fillName
        $script:SegCaptions[$i].ForeColor = Get-ThemeColor ($(if ($Completed -or $n -le $Segment) { 'card' } else { 'onPrimaryMuted' }))
    }
    $script:TaskSegment = $Segment
}
function Update-TaskSegmentFromLog {
    # 心跳回调：从任务日志关键词推断当前段，只前进不后退（避免 R 输出里的偶发词把进度拉回去）。
    # 关键词取自 New-AnalysisScript 生成的固定提示行；环境检查等交互任务无日志流，段保持 0（全灰）。
    if (-not $script:Task) { return }
    $lb = if ($script:Task.LogBox) { $script:Task.LogBox } else { $script:LogBox }
    $text = if ($lb) { $lb.Text } else { '' }
    if (-not $text) { return }
    $seg = $script:TaskSegment
    if ($text -match 'Word|HTML|结果报告') { $seg = 3 }
    elseif ($text -match '开始分析') { $seg = 2 }
    elseif ($text -match 'R 包') { $seg = 1 }
    if ($seg -gt $script:TaskSegment) {
        $names = @{ 1 = '准备 R 环境（安装缺失的 R 包）'; 2 = '运行统计分析'; 3 = '生成中文报告' }
        Set-TaskSegment $seg
        Write-LogLine "── 进度：第 $seg/3 段 · $($names[$seg]) ──`r`n"
    }
}
function Start-ButtonPulse($btn) {
    # 温和完成动效：按钮 BackColor 在 白/主色浅底 两档间交替，500ms×4（约 2 次脉冲）后停止并复位。
    # 用 Timer 而非动画 API（WinForms 无原生过渡），档位差小、无闪烁感；定时器挂 script 级防 GC。
    # 状态经局部 hashtable 传递：GetNewClosure 闭包内看不到主脚本 $script: 变量，只有被捕获的局部可靠。
    if (-not $btn) { return }
    if ($script:PulseTimer) { try { $script:PulseTimer.Stop(); $script:PulseTimer.Dispose() } catch { }; $script:PulseTimer = $null }
    $state = @{ Count = 0; Timer = $null }
    $base = Get-ThemeColor 'card'; $hi = Get-ThemeColor 'accentSoft'
    $btn.BackColor = $base
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $state.Timer = $timer
    $timer.Add_Tick({
        if ($state.Count -ge 4) { $state.Timer.Stop(); $state.Timer.Dispose(); $btn.BackColor = $base; return }
        $state.Count++
        $btn.BackColor = $(if ($state.Count % 2 -eq 1) { $hi } else { $base })
    }.GetNewClosure())
    $script:PulseTimer = $timer
    $timer.Start()
}
function Update-EnvStatusLights([bool]$RReady, [bool]$PyReady) {
    # 状态灯颜色语义：绿=就绪 / 黄=可用但有缺 / 红=缺失。
    # R 找到即绿（分析核心）；Python 找到只给黄——pandas/python-docx 等报告依赖要到任务里
    # 由 Initialize-PsychostatPythonEnvironment 校验并按需补装，界面无法廉价预判，故属「可用但有缺」。
    # 文字统一用主题灰（保证对比度），颜色语义只由圆点承担。
    if (-not $script:EnvState) { return }
    $script:EnvState.RDot.ForeColor = Get-ThemeColor ($(if ($RReady) { 'success' } else { 'danger' }))
    $script:EnvState.RText.Text = $(if ($RReady) { 'R：就绪' } else { 'R：缺失' })
    $script:EnvState.PyDot.ForeColor = Get-ThemeColor ($(if ($PyReady) { 'warning' } else { 'danger' }))
    $script:EnvState.PyText.Text = $(if ($PyReady) { 'Python：可用' } else { 'Python：缺失' })
}
function Set-RunButtonsEnabled([bool]$enabled) {
    foreach ($b in $script:RunButtons) { if ($b) { $b.Enabled = $enabled } }
    foreach ($b in $script:CancelBtns) { if ($b) { $b.Enabled = -not $enabled } }
}
function Stop-GuiTask {
    # 取消任务（stats/CTT/IRT 三个“取消任务”按钮共用）：杀整棵进程树再清状态。
    # 后台 PowerShell 里还会派生 Rscript/python，仅 Kill() 只杀直接子进程，孙进程会残留继续写 outputs。
    if ($script:Task -and -not $script:Task.Process.HasExited) {
        try {
            Start-Process taskkill.exe -ArgumentList @('/PID', $script:Task.Process.Id, '/T', '/F') -WindowStyle Hidden -Wait | Out-Null
        } catch { }
        if (-not $script:Task.Process.HasExited) { try { $script:Task.Process.Kill() } catch { } }
        # 轮询等待进程真正退出（最多 5 秒），再解锁按钮/清状态，避免残留输出继续写入
        try {
            $deadline = (Get-Date).AddSeconds(5)
            while (-not $script:Task.Process.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
        } catch { }
        Write-LogLine "`r`n[已取消] 任务被用户终止。`r`n"
    }
    $script:TaskTimer.Stop(); $script:Task = $null; Set-RunButtonsEnabled $true
    Set-TaskSegment 0   # 取消后三段进度复位为全灰，避免下次任务显示残留状态
    if ($script:HomeBtn) { $script:HomeBtn.Enabled = $true }
    $script:StatusLabel.Text = '任务已取消。'
    $script:StatusLabel.ForeColor = Get-ThemeColor 'danger'
}
function Start-GuiTask {
    param([string]$Title, [string]$ScriptBody, [switch]$Interactive)
    try {
        if ($script:Task -and -not $script:Task.Process.HasExited) {
            [System.Windows.Forms.MessageBox]::Show('已有任务在运行，请等待完成或点“取消任务”。','Psychostat') | Out-Null; return
        }
        $tmpDir = Join-Path $env:TEMP ('psychostat_gui_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $ps1 = Join-Path $tmpDir 'task.ps1'
        $out = Join-Path $tmpDir 'out.txt'
        $err = Join-Path $tmpDir 'err.txt'
        # 统一任务输出为 UTF-8：后台 PowerShell 的中文提示（使用 R / 结果目录 等）才不会在日志区乱码
        $prologue = '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8' + "`r`n"
        [IO.File]::WriteAllText($ps1, $prologue + $ScriptBody, (New-Object System.Text.UTF8Encoding($true)))
        if ($Interactive) {
            # 交互式任务（如"检查环境/自动安装"）：脚本内部有 Read-Host 提问。
            # 若仍用 -WindowStyle Hidden + 重定向，提示写进重定向文件、用户既看不到也无法回答，
            # 任务会永久停在 Read-Host。故改为弹出**可见**控制台窗口，让用户能直接作答。
            $proc = Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File', $ps1) -PassThru
            $script:Task = [pscustomobject]@{ Title=$Title; Process=$proc; Out=$null; Err=$null; PosOut=0; PosErr=0; LogBox=$script:LogBox; Interactive=$true }
            Write-LogLine "=== $Title ===`r`n（已打开独立控制台窗口：请在**那个窗口**里查看进度并回答提问；本界面在此期间不显示实时日志）`r`n`r`n"
        } else {
            $proc = Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File', $ps1) `
                -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
            $script:Task = [pscustomobject]@{ Title=$Title; Process=$proc; Out=$out; Err=$err; PosOut=0; PosErr=0; LogBox=$script:LogBox; Interactive=$false }
            Write-LogLine "=== $Title ===`r`n（任务在后台运行，日志会自动刷新；无响应可点“取消任务”）`r`n`r`n"
        }
        # 清理上一轮的结果标记文件，确保结束处理读取到的是本次运行的结果目录
        $marker = Join-Path $root 'outputs\.last_result_dir.txt'
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        $script:TaskStarted = Get-Date; $script:TaskTick = 0
        Set-TaskSegment 0   # 新任务开始：三段进度复位为全灰
        if ($script:LogBox) { $script:LogBox.Clear() }
        Set-RunButtonsEnabled $false
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = "正在执行：$Title ..."
            $script:StatusLabel.ForeColor = Get-ThemeColor 'warningText'
        }
        $script:TaskTimer.Start()
    } catch {
        Write-LogLine "`r`n[错误] 启动任务失败：$($_.Exception.Message)`r`n"
        Set-RunButtonsEnabled $true
    }
}
function Update-GuiTask {
    try {
        if (-not $script:Task) { $script:TaskTimer.Stop(); return }
        foreach ($k in @('Out','Err')) {
            $path = $script:Task.$k
            $posName = if ($k -eq 'Out') { 'PosOut' } else { 'PosErr' }
            if (-not (Test-Path -LiteralPath $path)) { continue }
            try {
                $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                if ($fs.Length -gt $script:Task.$posName) {
                    $fs.Position = $script:Task.$posName
                    $sr = New-Object IO.StreamReader($fs)
                    $chunk = $sr.ReadToEnd()
                    $script:Task.$posName = $fs.Position
                    $sr.Close()
                    if ($chunk) { Write-LogLine $chunk }
                }
                $fs.Close()
            } catch { }
        }
        if ($script:Task.Process.HasExited) {
            $script:TaskTimer.Stop()
            # 先同步等待，确保 ExitCode 已固化（Start-Process -PassThru 下直接读可能拿到空值）
            try { $script:Task.Process.WaitForExit() } catch { }
            $code = $script:Task.Process.ExitCode
            if ($null -eq $code) { $code = 0 }
            # 结果目录：优先读后台脚本写入的标记文件（可靠）；否则退回从日志文本解析 hex
            $resultDir = $null
            $marker = Join-Path $root 'outputs\.last_result_dir.txt'
            if (Test-Path -LiteralPath $marker) {
                try {
                    $candidate = (Get-Content -LiteralPath $marker -Encoding UTF8 -ErrorAction Stop | Select-Object -First 1)
                    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $resultDir = $candidate.Trim() }
                } catch { }
            }
            if (-not $resultDir) {
                $lb = if ($script:Task.LogBox) { $script:Task.LogBox } else { $script:LogBox }
                $text = if ($lb) { $lb.Text } else { '' }
                $m = [regex]::Match($text, 'RESULT_DIR_UTF8_HEX=([0-9A-Fa-f]+)')
                if ($m.Success) {
                    $bytes = for ($i = 0; $i -lt $m.Groups[1].Value.Length; $i += 2) { [Convert]::ToByte($m.Groups[1].Value.Substring($i,2),16) }
                    $resultDir = [Text.Encoding]::UTF8.GetString($bytes)
                }
            }
            $script:LastResultDir = $resultDir
            Set-RunButtonsEnabled $true
            $script:OpenResultBtn.Enabled = [bool]$resultDir
            $script:OpenReportBtn.Enabled = [bool]$resultDir
            # 分析结束（无论成败）后出现“回到首页”快捷按钮
            $script:HomeBtn.Enabled = $true
            if ($code -eq 0) {
                if ($resultDir) {
                    $script:StatusLabel.Text = "完成，结果已生成：$resultDir"
                    Write-LogLine "`r`n=== 任务结束（退出码 0）===`r`n结果目录：$resultDir`r`n可点底部“打开结果文件夹”查看全部输出，或点“打开中文报告”。`r`n"
                    # 任务成功后自动打开中文 HTML 报告（默认浏览器）；文件名按任务分支映射。
                    # HTML 不存在（如生成器未就位/生成失败）则回退原行为：打开结果文件夹，绝不静默失败。
                    $htmlName = Get-BranchHtmlName $script:LastTaskBranch
                    $htmlPath = Join-Path $resultDir $htmlName
                    if (Test-Path -LiteralPath $htmlPath) {
                        Write-LogLine "正在打开中文报告：$htmlName`r`n"
                        try { Start-Process -FilePath $htmlPath } catch {
                            Write-LogLine "[提示] 自动打开报告失败：$($_.Exception.Message)（可点底部「打开中文报告」手动打开）`r`n"
                        }
                    } else {
                        Write-LogLine "[提示] 结果目录没有 $htmlName，改为打开结果文件夹。`r`n"
                        try { Start-Process explorer.exe -ArgumentList $resultDir } catch { }
                    }
                } else {
                    $script:StatusLabel.Text = '完成，但未识别到结果目录（请查看日志末尾）。'
                    Write-LogLine "`r`n=== 任务结束（退出码 0），但未识别到结果目录 ===`r`n"
                }
                # 完成动效（温和）：状态栏转成功色 + 三段进度全绿 + 「打开中文报告」按钮短脉冲
                $script:StatusLabel.ForeColor = Get-ThemeColor 'success'
                Set-TaskSegment 3 -Completed
                if ($script:OpenReportBtn -and $script:OpenReportBtn.Enabled) { Start-ButtonPulse $script:OpenReportBtn }
            } else {
                $script:StatusLabel.Text = "任务结束（退出码 $code）—— 请查看日志末尾提示。"
                $script:StatusLabel.ForeColor = Get-ThemeColor 'danger'
                Write-LogLine "`r`n=== 任务结束（退出码 $code）===`r`n"
            }
            $script:Task = $null
        } else {
            # 心跳：每 5 秒（12 次 tick）在状态栏显示已运行时长，确认没有卡死
            $script:TaskTick++
            if ($script:TaskTick % 12 -eq 0) {
                $秒 = [int]((Get-Date) - $script:TaskStarted).TotalSeconds
                $script:StatusLabel.Text = "正在执行：$($script:Task.Title)（已运行 $秒 秒）"
            }
            # 同一心跳里按日志关键词推进顶栏三段进度（装 R 包 → 跑分析 → 出报告）
            Update-TaskSegmentFromLog
        }
    } catch {
        Write-LogLine "`r`n[界面提示] 刷新日志时出现问题（已忽略）：$($_.Exception.Message)`r`n"
    }
}

# ── 列名读取 ──────────────────────────────────────────────────────────────────
function Get-DataColumns([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return @() }
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq '.csv') {
        try {
            $first = Get-Content -LiteralPath $path -TotalCount 1 -Encoding UTF8
            if ($first) { return @($first -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }
        } catch { }
        return @()
    }
    $rs = Get-RscriptPath
    if (-not $rs) { return @() }
    $safe = $path -replace '\\','/'
    $rCode = if ($ext -in '.xlsx','.xls') {
        "suppressMessages(suppressWarnings(library(readxl))); z <- read_excel('$safe', n_max = 0); cat(paste(names(z), collapse='|'))"
    } else {
        "suppressMessages(suppressWarnings(library(haven))); z <- read_sav('$safe'); cat(paste(names(z), collapse='|'))"
    }
    try {
        $out = & $rs --vanilla -e $rCode 2>$null
        if ($out) { return @(($out -join '') -split '\|' | Where-Object { $_ }) }
    } catch { }
    return @()
}

# ── 配置与后台脚本 ────────────────────────────────────────────────────────────
# 读取界面上"第 0 步 数据准备"的两个选择，转成配置里的 datacheck 段。
# 两个都选"不处理"时返回 $null（配置里不写 datacheck = 只报告、不改动数据）。
function Get-GuiDataCheckPolicy {
    if (-not $script:StatsControls -or -not $script:StatsControls.dcMissing) { return $null }
    $ma = if ($script:StatsControls.dcMissing.SelectedIndex -eq 1) { 'mean_impute' } else { 'report' }
    $oa = if ($script:StatsControls.dcOutlier.SelectedIndex -eq 1) { 'remove_by_z' } else { 'report' }
    if ($ma -eq 'report' -and $oa -eq 'report') { return $null }
    [ordered]@{ missing_action = $ma; outlier_action = $oa; z_cutoff = 3 }
}
function New-StatsConfig {
    param([string]$Mode, [string[]]$Methods, [string]$DataPath, [hashtable]$Vars, $DataCheck)
    $varsObj = [ordered]@{}
    if ($Vars) { foreach ($k in $Vars.Keys) { $varsObj[$k] = $Vars[$k] } }
    $obj = [ordered]@{
        method     = $Methods
        input      = [ordered]@{ mode = $Mode; path = $(if ($DataPath) { $DataPath } else { $null }) }
        variables  = $varsObj
        analysis   = [ordered]@{ alpha = 0.05; posthoc = @('lsd','tukey','bonferroni'); correlation_method = 'both' }
        simulation = [ordered]@{ seed = 20260904; n_per_group = 30 }
        output     = [ordered]@{ directory = (Join-Path $root 'outputs'); project_label = 'gui_stats'; report_language = 'zh' }
    }
    # 数据准备策略：只有用户真的选了"处理"才写进配置；默认不写 = 只报告不改数据
    if ($DataCheck) { $obj['datacheck'] = $DataCheck }
    $obj
}
function New-CttConfig {
    param([string]$Mode, [string]$DataPath, [string]$Goal, [string]$Mapping)
    [ordered]@{
        input    = [ordered]@{ mode = $Mode; path = $(if ($DataPath) { $DataPath } else { $null }); id_column = $null; item_columns = 'auto' }
        cleaning = [ordered]@{ scale_maximum = 5; reverse_items = @(); missing_5_to_20 = 'median_impute'; attention_item = $null; attention_correct_value = $null; response_time_column = $null; minimum_response_seconds = $null; straightline_action = 'flag'; extreme_action = 'flag' }
        analysis = [ordered]@{ goal = $Goal; n_factors = 'auto'; max_efa_iterations = 10; rotation = 'promax'; cfa_source = $(if ($Goal -eq 'cfa') { 'file' } else { 'skip' }); cfa_mapping = $(if ($Mapping) { $Mapping } else { '' }); criterion_column = $null; criterion_direction = 'positive'; known_group_column = $null }
        output   = [ordered]@{ directory = (Join-Path $root 'outputs'); project_label = 'gui_ctt'; report_language = 'zh' }
    }
}
function New-IrtConfig {
    param([string]$Mode, [string]$DataPath, [string]$Model, [string]$MirtMode, [string]$MirtItemModel = 'auto', [string]$LoadingMatrix)
    [ordered]@{
        input    = [ordered]@{ mode = $Mode; path = $(if ($DataPath) { $DataPath } else { $null }); id_column = $null; item_columns = 'auto'; missing = 'none' }
        analysis = [ordered]@{
            model = $Model; compare_models = @($Model); dimension_count = 'auto'; dimension_range = 'auto'
            mirt_mode = $MirtMode; mirt_item_model = $MirtItemModel; loading_matrix = $(if ($LoadingMatrix) { $LoadingMatrix } else { $null })
            max_auto_dimensions = 6; estimator = 'EM'; max_iterations = 500; theta_min = -3; theta_max = 3; theta_points = 121
            selection_criterion = 'BIC'; allow_3pl = $false; compute_m2 = $true
        }
        output   = [ordered]@{ directory = (Join-Path $root 'outputs'); project_label = 'gui_irt'; report_languages = @('zh','en'); save_model_object = $true }
    }
}
function Save-Config($obj, [string]$name) {
    $dir = Join-Path $root 'outputs'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir $name
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}
# ── 环境清理（界面按钮用）─────────────────────────────────────────────────────
# 复用 scripts\uninstall_psychostat.ps1：
#   ① 先用 -PreviewOnly 取预览文本（该模式绝不询问、绝不删除，适合被隐藏进程调用）；
#   ② 由界面弹出可滚动对话框让用户决定（关闭＝什么都不做）；
#   ③ 用户确认后才以 -Execute -Force 执行（确认动作就是那个对话框）。
# 安全边界由脚本自身保证：只删本工具专属目录、白名单校验、不动已有 R/Python 本体与用户数据。
function Invoke-PsychostatCleanupPreview {
    $scriptPath = Join-Path $root 'scripts\uninstall_psychostat.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw '未找到 scripts\uninstall_psychostat.ps1' }
    $out = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scriptPath -PreviewOnly 2>&1
    return (@($out) -join [Environment]::NewLine)
}
function Invoke-PsychostatCleanupExecute {
    $scriptPath = Join-Path $root 'scripts\uninstall_psychostat.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw '未找到 scripts\uninstall_psychostat.ps1' }
    $out = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Execute -Force 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($out) -join [Environment]::NewLine) }
}
function Show-PsychostatCleanupDialog {
    param([string]$PreviewText)
    # 只读多行预览（可滚动）+ 两个明确按钮；返回 $true 表示用户选择清理
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '清理已安装环境（先看清楚，再决定）'
    $dlg.ClientSize = New-Object System.Drawing.Size(740, 560)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $tip = New-Label '下面列出的是 Psychostat 自己安装的东西。你已有的 R / Python、共享库、分析结果（outputs）与数据（data）都不会被删除。' 12 10 716 34 $false 9
    $dlg.Controls.Add($tip)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(12, 50)
    $tb.Size = New-Object System.Drawing.Size(716, 446)
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Both'; $tb.WordWrap = $false
    $tb.BackColor = Get-ThemeColor 'card'
    $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $tb.Text = $PreviewText
    $dlg.Controls.Add($tb)
    $ok = New-Button '清理上面这些目录' 420 508 150 34
    $cancel = New-Button '什么都不做（关闭）' 578 508 150 34
    $ok.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $cancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel })
    $dlg.Controls.AddRange(@($ok, $cancel))
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $cancel
    $r = $dlg.ShowDialog()
    $dlg.Dispose()
    return ($r -eq [System.Windows.Forms.DialogResult]::OK)
}

function New-AnalysisScript {
    param([string]$Branch, [string]$Pkgs, [string]$ConfigPath, [string]$PythonReport)
    $pipeline = switch ($Branch) { 'stats' { 'stats_pipeline.R' } 'ctt' { 'ctt_pipeline.R' } 'irt' { 'irt_generic_pipeline.R' } }
    # 单引号安全化：下列变量会插值进生成脚本是单引号字符串，路径里的 ' 必须翻倍为 ''，
    # 否则含撇号的路径（如 O'Brien 用户目录）会提前闭合字符串、破坏任务脚本语法。
    $rootQ = $root.Replace("'", "''"); $pipelineQ = $pipeline.Replace("'", "''"); $configQ = $ConfigPath.Replace("'", "''")
    $reportQ = $PythonReport.Replace("'", "''")
    $htmlName = Get-BranchHtmlName $Branch   # HTML 报告文件名契约（stats/ctt/irt → *_report_zh.html，与 GUI 完成分支同源）
    @"
`$ErrorActionPreference = 'Continue'
# 环境预检走共享 psychostat_env.ps1（D 盘优先 / TEMP 非 ASCII 重定向 / R 写盘自检均生效）；
# 不带 -AllowAutoInstall：后台任务缺失环境时提示回界面安装，而不是无人值守自动装。
. '$rootQ\psychostat_env.ps1'
try { `$rs = Initialize-PsychostatEnvironment } catch { Write-Host '未找到 R。请回到界面点击“检查环境/自动安装”。'; exit 1 }
Write-Host ('使用 R：' + `$rs)
`$pkgs = '$Pkgs' -split ' '
Write-Host '检查 R 包（只装缺的，已装自动跳过；国内镜像优先，失败自动换源；下面会逐个包显示进度）...'
`$pkgScript = Get-PsychostatPackageInstallScript -Packages `$pkgs
& `$rs --vanilla `$pkgScript
if (`$LASTEXITCODE -ne 0) { Write-Host 'R 包安装失败：请检查网络后重试。'; exit 1 }
Write-Host '开始分析...'
`$started = Get-Date
& `$rs --vanilla '$rootQ\scripts\$pipelineQ' --config '$configQ'
`$code = `$LASTEXITCODE
# 结果目录：取本次运行后新生成的结果目录（比解析日志文本更可靠），写入文件供界面读取
`$latest = Get-ChildItem (Join-Path '$rootQ' 'outputs') -Directory -ErrorAction SilentlyContinue |
    Where-Object { `$_.LastWriteTime -ge `$started.AddSeconds(-2) } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (`$latest) {
    Write-Host ''
    Write-Host ('结果目录：' + `$latest.FullName)
    Set-Content -LiteralPath (Join-Path '$rootQ' 'outputs\.last_result_dir.txt') -Value `$latest.FullName -Encoding UTF8
    `$files = Get-ChildItem `$latest.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name
    Write-Host ('共生成 ' + `$files.Count + ' 个文件，其中：')
    `$files | Select-Object -First 15 | ForEach-Object { Write-Host ('  · ' + `$_.Name) }
    if (`$files.Count -gt 15) { Write-Host ('  … 其余 ' + (`$files.Count - 15) + ' 个文件请在结果目录中查看') }
} else {
    Write-Host '未找到本次运行生成的结果目录：请检查上方日志中的错误信息。'
}
if (`$code -eq 0 -and '$reportQ' -ne '' -and `$latest) {
    # Python 与 结果报告依赖：用与环境检查按钮、命令行启动器**完全相同**的解析逻辑。
    # 之前这里用的是 GUI 侧预解析的 `$py（Get-PythonPath），它既不校验 pandas/python-docx，
    # 也不会设置 PYTHONUSERBASE —— 依赖常被 pip --user 装进随解释器走的
    # <python>\Psychostat-Python-User 目录，缺少该环境变量的进程看不到它们，于是报
    # ModuleNotFoundError: No module named 'pandas'（"检查环境/自动安装"显示就绪也没用，
    # 因为它装到的可能是另一个 Python）。这里 -Silent 不弹窗，但缺依赖时仍会自动安装（镜像回退）。
    Write-Host '检查 Python 与 结果报告依赖（pandas / python-docx）...'
    `$pe = `$null
    try { `$pe = Initialize-PsychostatPythonEnvironment -ProjectRoot '$rootQ' -Silent } catch { `$pe = `$null }
    `$py = if (`$pe) { `$pe.Path } else { `$null }
    if (-not `$py -or -not (Test-Path -LiteralPath `$py)) {
        `$why = if (`$pe -and `$pe.Note) { `$pe.Note } else { '未找到可用的 Python' }
        Write-Host ('Word 结果报告跳过：' + `$why + '（CSV/图/Markdown 报告不受影响）')
    } else {
        Write-Host ('正在生成 Word 结果报告（Python：' + `$py + '）...')
        `$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$latest.FullName))
        & `$py -X utf8 '$rootQ\scripts\$reportQ' --result-dir-utf8-base64 `$b64
        if (`$LASTEXITCODE -eq 0) { Write-Host 'Word 报告已生成。' } else { Write-Host 'Word 报告生成失败（分析结果不受影响）；可回到界面点“检查环境/自动安装”后重试。' }
    }
    # 中文 HTML 报告（交付物 C）：与 Word 报告共用同一个 Python 解释器与初始化（`$py/`$pe）。
    # 失败只打一行提示、绝不影响退出码；成功时生成器 stdout 会打印 HTML_REPORT_OK（契约标记），
    # 任务脚本随即自行打开报告——后台任务的打开动作放在最靠近产物的一端最可靠。
    `$htmlGen = '$rootQ\scripts\generate_html_report.py'
    if (-not `$py -or -not (Test-Path -LiteralPath `$py)) {
        Write-Host 'HTML 报告跳过：未找到可用的 Python（分析结果不受影响）。'
    } elseif (-not (Test-Path -LiteralPath `$htmlGen)) {
        Write-Host 'HTML 报告跳过：未找到 scripts/generate_html_report.py（分析结果与 Word 报告不受影响）。'
    } else {
        Write-Host '正在生成中文 HTML 报告...'
        & `$py -X utf8 `$htmlGen --result-dir-utf8-base64 `$b64
        if (`$LASTEXITCODE -eq 0) {
            `$htmlOut = Join-Path `$latest.FullName '$htmlName'
            if (Test-Path -LiteralPath `$htmlOut) {
                Write-Host ('HTML 报告已生成：' + `$htmlOut)
                try { Start-Process -FilePath `$htmlOut } catch { Write-Host '（自动打开 HTML 报告失败，请到结果目录手动打开。）' }
            } else {
                Write-Host 'HTML 生成器退出码为 0 但未找到报告文件（请查看上方输出）。'
            }
        } else {
            Write-Host 'HTML 报告生成失败（分析结果与 Word 报告不受影响）。'
        }
    }
}
exit `$code
"@
}

# ── 控件工具 ──────────────────────────────────────────────────────────────────
function New-Label($text, $x, $y, $w = 480, $h = 22, $bold = $false, $size = 10) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $size, $(if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    return $l
}
function New-Button($text, $x, $y, $w, $h, [string]$Level = 'normal') {
    # 层级化按钮样式（表现层约定，不改任何行为）：
    #   primary   主操作（开始分析类）：实心主色白字
    #   secondary 次要（下一步/上一步/打开类）：白底主色描边与文字
    #   danger    危险（清理已安装环境）：弱化为文字按钮（Flat 无边框暗红字）
    #   normal    既有中性样式（导航/工具类按钮），默认
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    switch ($Level) {
        'primary' {
            $b.BackColor = Get-ThemeColor 'primary'; $b.ForeColor = [System.Drawing.Color]::White
            $b.FlatAppearance.BorderColor = Get-ThemeColor 'primary'; $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = Get-ThemeColor 'accent'   # 悬停微亮，仍是深底白字
        }
        'secondary' {
            $b.BackColor = Get-ThemeColor 'card'; $b.ForeColor = Get-ThemeColor 'accent'
            $b.FlatAppearance.BorderColor = Get-ThemeColor 'accent'
            $b.FlatAppearance.MouseOverBackColor = Get-ThemeColor 'accentSoft'
        }
        'danger' {
            $b.BackColor = Get-ThemeColor 'navBg'; $b.ForeColor = Get-ThemeColor 'danger'
            $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = Get-ThemeColor 'accentSoft'
        }
        default {
            $b.BackColor = Get-ThemeColor 'card'
            $b.FlatAppearance.BorderColor = Get-ThemeColor 'btnBorder'
        }
    }
    return $b
}
function New-LogBox($x, $y, $w, $h) {
    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Location = New-Object System.Drawing.Point($x, $y); $log.Size = New-Object System.Drawing.Size($w, $h)
    $log.ReadOnly = $true; $log.WordWrap = $false
    $log.BackColor = Get-ThemeColor 'logBg'
    $log.Font = New-Object System.Drawing.Font('Consolas', 9)
    return $log
}
function New-StepPanel {
    # 卡片式步骤容器：白底卡片浮在 #F8F9FC 内容区底色上（PageHost 的 Padding 形成四周留白），
    # 描边沿用 WinForms 原生 FixedSingle（与既有内嵌白色子面板同一描边语言），不自绘圆角、不引第三方。
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'; $p.BackColor = Get-ThemeColor 'card'; $p.Visible = $false
    $p.BorderStyle = 'FixedSingle'
    $p.AutoScroll = $true
    return $p
}

# ── 方法选择向导（界面交互）与变量收集辅助 ────────────────────────────────────
function Update-GuidePanel {
    $g = $script:GuideState; $gp = $script:StatsStep2.guidePanel
    if (-not $gp) { return }
    $gp.Controls.Clear()
    $y = 10
    $nextKey = 'q1'
    foreach ($step in @($g.Path)) {
        $q = $script:GuideTree[$step.Q]; $opt = $q.Options[$step.A]
        $gp.Controls.Add((New-Label $q.Text 12 $y 650 22 $false 9.5))
        $a = New-Label ('　答：' + $opt.T) 12 ($y + 24) 650 22 $false 9.5
        $a.ForeColor = Get-ThemeColor 'primary'
        $gp.Controls.Add($a); $y += 52
        $nextKey = if ($opt.Rec) { $null } else { $opt.Next }
    }
    if ($g.Rec) {
        $rec = $g.Rec; $cat = $script:MethodCatalog[$rec]
        $r1 = New-Label "✦ 推荐方法：$($cat.zh)（$rec）" 12 $y 650 26 $true 11.5
        $r1.ForeColor = Get-ThemeColor 'success'
        $gp.Controls.Add($r1)
        $r2 = New-Label "适用：$($cat.tip)" 12 ($y + 30) 650 22 $false 9.5
        $r2.ForeColor = Get-ThemeColor 'success'
        $gp.Controls.Add($r2)
        $r3 = New-Label '下一步：已选数据文件 → 设置变量后分析你的数据；未选文件 → 用内置模拟数据演示该方法。' 12 ($y + 56) 650 24 $false 9.5
        $r3.ForeColor = Get-ThemeColor 'textMuted'
        $gp.Controls.Add($r3)
        $again = New-Button '← 重新回答' 12 ($y + 86) 110 28
        $again.Add_Click({ Reset-Guide })
        $gp.Controls.Add($again)
    } elseif ($nextKey) {
        $q = $script:GuideTree[$nextKey]
        $gp.Controls.Add((New-Label $q.Text 12 $y 650 24 $true 10.5))
        $y += 30
        for ($i = 0; $i -lt $q.Options.Count; $i++) {
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = $q.Options[$i].T
            $rb.Location = New-Object System.Drawing.Point(28, $y); $rb.Size = New-Object System.Drawing.Size(640, 26)
            $rb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
            $key = $nextKey; $idx = $i
            $rb.Add_Click({ Select-GuideOption $key $idx }.GetNewClosure())
            $gp.Controls.Add($rb); $y += 30
        }
    }
}
function Reset-Guide {
    $script:GuideState.Path = @(); $script:GuideState.Rec = $null
    Update-GuidePanel; Sync-StatsStepViews
}
function Select-GuideOption([string]$qKey, [int]$idx) {
    $q = $script:GuideTree[$qKey]
    if (-not $q -or $idx -ge $q.Options.Count) { return }
    $opt = $q.Options[$idx]
    $script:GuideState.Path = @($script:GuideState.Path + @{ Q = $qKey; A = $idx })
    if ($opt.Rec) { $script:GuideState.Rec = $opt.Rec }
    Update-GuidePanel; Sync-StatsStepViews
}
function Get-SelectedFileMethods {
    # 当前“我的数据/向导”模式要跑的方法列表（多选）
    $m = @()
    $c = $script:StatsControls; $s2 = $script:StatsStep2
    if (-not $c -or -not $s2) { return $m }
    if ($c.rbGuide.Checked) { if ($script:GuideState.Rec) { $m += $script:GuideState.Rec }; return $m }
    if (-not $s2.fileMethods) { return $m }
    foreach ($i in $s2.fileMethods.CheckedItems) { $m += (("$i") -split ' — ')[0] }
    return $m
}
function Get-StatsVarsFromPanel {
    $vars = @{}
    if ($script:StatsStep3) {
        # 展开子面板（偏相关/分层回归的追加区域）里的控件，统一遍历
        $all = @($script:StatsStep3.varPanel.Controls)
        foreach ($ctl in $all) { if ($ctl -is [System.Windows.Forms.Panel]) { $all += @($ctl.Controls) } }
        $partialOn = $false; $blocksOn = $false
        foreach ($ctl in $all) {
            if ($ctl -is [System.Windows.Forms.CheckBox] -and $ctl.Tag -eq 'partial_enable') { $partialOn = $ctl.Checked; continue }
            if ($ctl -is [System.Windows.Forms.CheckBox] -and $ctl.Tag -eq 'blocks_enable') { $blocksOn = $ctl.Checked; continue }
            if ($ctl.Tag -and "$($ctl.Tag)" -like 'partial_*' -and -not $partialOn) { continue }
            if ($ctl.Tag -and "$($ctl.Tag)" -eq 'blocks_str' -and -not $blocksOn) { continue }
            if ($ctl -is [System.Windows.Forms.ComboBox] -and $ctl.Tag -and $ctl.SelectedItem) { $vars["$($ctl.Tag)"] = "$($ctl.SelectedItem)" }
            elseif ($ctl -is [System.Windows.Forms.CheckedListBox] -and $ctl.Tag) {
                $chosen = @(); foreach ($i in $ctl.CheckedItems) { $chosen += "$i" }
                if ($chosen.Count) { $vars["$($ctl.Tag)"] = $chosen }
            }
            elseif ($ctl -is [System.Windows.Forms.TextBox] -and $ctl.Tag -eq 'mu') {
                # 数值输入（检验值 μ）：非空且能解析为数字才写入；空则跳过（R 侧默认 50）
                $t = "$($ctl.Text)".Trim(); $num = 0.0
                if ($t -and [double]::TryParse($t, [ref]$num)) { $vars['mu'] = [double]$num }
            }
            elseif ($ctl -is [System.Windows.Forms.TextBox] -and $ctl.Tag -eq 'blocks_str') {
                # 分层回归：把 "层1变量,变量 | 层2变量" 解析成嵌套数组（JSON 里 R 读为 list）
                $t = "$($ctl.Text)".Trim()
                if ($t) {
                    $layers = @(); foreach ($part in ($t -split '\|')) {
                        $vs = @($part -split '[,，;；、]' | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
                        if ($vs.Count) { $layers += , @($vs) }
                    }
                    if ($layers.Count -ge 2) { $vars['blocks'] = $layers }
                }
            }
        }
    }
    return $vars
}
function Get-MissingSingleFields([string[]]$Methods, [hashtable]$Vars) {
    $missing = @()
    foreach ($m in $Methods) {
        foreach ($f in $script:MethodFields[$m]) {
            if ($script:FieldMeta[$f].type -eq 'single' -and $f -ne 'id' -and -not $Vars.ContainsKey($f)) {
                $item = "$($script:MethodCatalog[$m].zh)·$($script:FieldMeta[$f].label)"
                if ($missing -notcontains $item) { $missing += $item }
            }
        }
    }
    return $missing
}

# ── 向导：步骤切换 ────────────────────────────────────────────────────────────
function Show-Step([string]$branch, [int]$step) {
    $script:CurrentBranch = $branch; $script:CurrentStep = $step
    $panels = $script:Wizard[$branch]
    if (-not $panels -or $panels.Count -lt $step) { return }
    # 先把所有步骤面板隐藏，再显示目标面板（关键：面板创建时 Visible=$false，必须显式打开）
    foreach ($br in $script:Wizard.Keys) { foreach ($pnl in $script:Wizard[$br]) { $pnl.Visible = $false } }
    $panel = $panels[$step - 1]
    $panel.Dock = 'Fill'
    $panel.Visible = $true
    if ($script:PageHost) {
        $script:PageHost.Controls.Clear()
        $script:PageHost.Controls.Add($panel)
        $panel.BringToFront()
    }
    # 日志区随步骤切换（第 4 步 / 最后一步 才有日志）
    $script:LogBox = $panel.Controls | Where-Object { $_ -is [System.Windows.Forms.RichTextBox] } | Select-Object -First 1
    # 高亮左侧按钮
    foreach ($k in $script:BranchButtons.Keys) {
        $script:BranchButtons[$k].BackColor = if ($k -eq $branch) { Get-ThemeColor 'navActive' } else { Get-ThemeColor 'card' }
    }
    # 首页没有分步，隐藏“步骤”标签
    if ($script:StepsLabel) { $script:StepsLabel.Visible = ($branch -ne 'home') }
    foreach ($k in $script:StepButtons.Keys) {
        $btn = $script:StepButtons[$k]
        $parts = $k -split ':'
        if ($parts[0] -ne $branch) { $btn.Visible = $false; continue }
        $btn.Visible = $true
        $idx = [int]$parts[1]
        $btn.BackColor = if ($idx -eq $step) { Get-ThemeColor 'navActive' } else { Get-ThemeColor 'card' }
        $btn.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, $(if ($idx -eq $step) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    }
}
function Refresh-StepNav {
    Show-Step $script:CurrentBranch $script:CurrentStep
}
function Go-Next {
    $b = $script:CurrentBranch; $s = $script:CurrentStep
    if (-not (Test-StepReady $b $s)) { return }
    $max = $script:Wizard[$b].Count
    if ($s -lt $max) { Show-Step $b ($s + 1) }
}
function Go-Prev {
    $b = $script:CurrentBranch; $s = $script:CurrentStep
    if ($s -gt 1) { Show-Step $b ($s - 1) }
}
function Test-StepReady([string]$branch, [int]$step) {
    if ($branch -ne 'stats') { return $true }
    if ($step -eq 1 -and $script:StatsControls.rbFile.Checked -and -not $script:StatsFile) {
        [System.Windows.Forms.MessageBox]::Show('请先点“选择数据文件…”选择你的数据文件。','Psychostat') | Out-Null; return $false
    }
    if ($step -eq 2 -and $script:StatsControls.rbPick.Checked) {
        $picked = @(); foreach ($i in $script:StatsStep2.methodList.CheckedItems) { $picked += ($i -split ' — ')[0] }
        if (-not $picked.Count) { [System.Windows.Forms.MessageBox]::Show('请勾选至少一个方法。','Psychostat') | Out-Null; return $false }
    }
    if ($step -eq 2 -and $script:StatsControls.rbFile.Checked) {
        $picked = @(); foreach ($i in $script:StatsStep2.fileMethods.CheckedItems) { $picked += ($i -split ' — ')[0] }
        if (-not $picked.Count) { [System.Windows.Forms.MessageBox]::Show('请勾选至少一个方法（可多选）。','Psychostat') | Out-Null; return $false }
    }
    if ($step -eq 2 -and $script:StatsControls.rbGuide.Checked -and -not $script:GuideState.Rec) {
        [System.Windows.Forms.MessageBox]::Show('请先完成向导问题，得到推荐方法。','Psychostat') | Out-Null; return $false
    }
    return $true
}

# ── 首页：欢迎与三大功能模块总览（点卡片进入对应模块）────────────────────────
function New-HomePage {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '欢迎使用 Psychostat 心理测量与统计分析工具箱' 10 8 720 32 $true 14))
    $sub = New-Label '左侧选择功能与步骤。三个功能模块都内置模拟演示：第一次使用建议先跑一遍演示，看看结果长什么样，再分析自己的数据。' 10 44 720 24 $false 9.5
    $sub.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($sub)

    $cards = @(
        @{ K = 'stats'; T = '① 心理统计（SPSS 对照教学）'; D = '描述统计 / t 检验 / 方差分析 / 相关回归 / 卡方 / 非参数 / 中介调节 / 功效——21 个方法模块，每个都附 SPSS 菜单路径、结果解读与 结果写法。' }
        @{ K = 'ctt';   T = '② 经典测量理论 CTT'; D = '经典测量框架，适用于量表与测验的质量分析：数据清洗 → 项目分析 → 信度效度 → EFA / CFA 三条路线，输出三线表、300dpi 图、CFA 路径图与 结果报告初稿。' }
        @{ K = 'irt';   T = '③ 项目反应理论 IRT'; D = '现代测量框架，同样适用于量表与测验：Rasch / 2PL / 3PL / GRM / 多维 MIRT（探索+验证），缺失值审计、ICC / IIF / TIF 图、能力估计与中英文 Word 结果报告。' }
    )
    $y = 82
    foreach ($cd in $cards) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(10, $y); $card.Size = New-Object System.Drawing.Size(720, 92)
        $card.BackColor = Get-ThemeColor 'card'; $card.BorderStyle = 'FixedSingle'
        $key = $cd.K
        $card.Controls.Add((New-Label $cd.T 14 10 560 24 $true 11))
        $desc = New-Label $cd.D 14 38 560 46 $false 8.5
        $desc.ForeColor = Get-ThemeColor 'textMuted'
        $card.Controls.Add($desc)
        $enter = New-Button '进入 →' 588 28 116 36
        $enter.Anchor = 'Top,Right'
        $enter.BackColor = Get-ThemeColor 'accentSoft'
        $enter.Add_Click({ Show-Step $key 1 }.GetNewClosure())
        $card.Controls.Add($enter)
        $p.Controls.Add($card)
        $y += 102
    }

    $tips = New-Label '提示：缺 R / Python 时点左侧“检查环境/自动安装”；分析完成后用底部“打开结果文件夹 / 打开中文报告”查看输出；所有分析在后台运行，可随时取消。' 10 ($y + 6) 720 36 $false 9
    $tips.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($tips)
    return $p
}

# ── 心理统计：4 个步骤面板 ────────────────────────────────────────────────────
function New-StatsStep1 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 1 步：选择数据来源（或用向导帮你选方法）' 16 12 660 30 $true 13))
    $p.Controls.Add((New-Label '四种方式任选一种，选好后点右下角“下一步”。' 16 44 700 24))

    $rbSim = New-Object System.Windows.Forms.RadioButton
    $rbSim.Text = '内置模拟演示 —— 21 个方法全部跑一遍（推荐第一次使用）'
    $rbSim.Location = New-Object System.Drawing.Point(20, 76); $rbSim.Size = New-Object System.Drawing.Size(720, 26); $rbSim.Checked = $true
    $p.Controls.Add($rbSim)
    $p.Controls.Add((New-Label '讲解每个方法的 SPSS 操作路径、结果解读与 结果写法；无需准备数据。' 46 102 620 22))

    $rbPick = New-Object System.Windows.Forms.RadioButton
    $rbPick.Text = '选择方法体验 —— 用内置模拟数据只跑你关心的那几个方法'
    $rbPick.Location = New-Object System.Drawing.Point(20, 130); $rbPick.Size = New-Object System.Drawing.Size(720, 26)
    $p.Controls.Add($rbPick)
    $p.Controls.Add((New-Label '下一步勾选方法（可多选）。' 46 156 620 22))

    $rbFile = New-Object System.Windows.Forms.RadioButton
    $rbFile.Text = '分析我自己的数据 —— CSV / Excel / SPSS 文件（方法可多选）'
    $rbFile.Location = New-Object System.Drawing.Point(20, 184); $rbFile.Size = New-Object System.Drawing.Size(720, 26)
    $p.Controls.Add($rbFile)

    $fileBox = New-Object System.Windows.Forms.TextBox
    $fileBox.Location = New-Object System.Drawing.Point(46, 214); $fileBox.Size = New-Object System.Drawing.Size(480, 28); $fileBox.ReadOnly = $true
    $btnFile = New-Button '选择数据文件…' 536 212 130 30
    $p.Controls.AddRange(@($fileBox, $btnFile))
    $colHint = New-Label '（点“选择数据文件…”后会弹出选择框，并自动读取列名）' 46 246 620 22
    $colHint.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($colHint)

    $rbGuide = New-Object System.Windows.Forms.RadioButton
    $rbGuide.Text = '方法选择向导 —— 不知道用哪种统计方法？回答 3~4 个问题帮你选'
    $rbGuide.Location = New-Object System.Drawing.Point(20, 278); $rbGuide.Size = New-Object System.Drawing.Size(720, 26)
    $p.Controls.Add($rbGuide)
    $guideHint = New-Label '得到推荐方法后可直接用内置模拟数据演示，也可先在上面选好数据文件分析自己的数据。' 46 304 660 22
    $guideHint.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($guideHint)

    # ── 第 0 步：数据准备（每次分析前自动运行；这里决定"要不要处理"）──
    $dcTitle = New-Label '第 0 步：数据准备（每次分析前自动运行，先报告再按你的选择处理）' 20 330 720 22 $true 9
    $dcTitle.ForeColor = Get-ThemeColor 'textBody'
    $p.Controls.Add($dcTitle)

    $p.Controls.Add((New-Label '缺失值：' 20 356 76 24))
    $dcMissing = New-Object System.Windows.Forms.ComboBox
    $dcMissing.DropDownStyle = 'DropDownList'
    $dcMissing.Location = New-Object System.Drawing.Point(96, 353); $dcMissing.Size = New-Object System.Drawing.Size(300, 26)
    [void]$dcMissing.Items.AddRange(@('不处理（保持原样，只报告）', '均值插补（SPSS 常用口径）'))
    $dcMissing.SelectedIndex = 0
    $p.Controls.Add($dcMissing)

    $p.Controls.Add((New-Label '异常值：' 410 356 76 24))
    $dcOutlier = New-Object System.Windows.Forms.ComboBox
    $dcOutlier.DropDownStyle = 'DropDownList'
    $dcOutlier.Location = New-Object System.Drawing.Point(486, 353); $dcOutlier.Size = New-Object System.Drawing.Size(254, 26)
    [void]$dcOutlier.Items.AddRange(@('不删除（保留并在报告中标注）', '删除（按 |Z| > 3 判定）'))
    $dcOutlier.SelectedIndex = 0
    $p.Controls.Add($dcOutlier)

    $next = New-Button '下一步 →' 580 398 130 40 'secondary'
    $p.Controls.Add($next)
    $next.Add_Click({ Go-Next })

    $script:StatsControls = @{ rbSim=$rbSim; rbPick=$rbPick; rbFile=$rbFile; rbGuide=$rbGuide; fileBox=$fileBox; btnFile=$btnFile; colHint=$colHint; dcMissing=$dcMissing; dcOutlier=$dcOutlier }
    # 读取当前面板上的数据准备选择（供生成配置时调用；定义在函数外的普通函数里）
    $btnFile.Add_Click({
        $f = Select-PsychostatFile -Title '选择数据文件（CSV / Excel / SPSS）'
        if (-not $f) { return }
        $script:StatsFile = $f
        $script:StatsControls.fileBox.Text = $f
        $script:StatsDataColumns = Get-DataColumns $f
        if ($script:StatsDataColumns.Count) {
            $script:StatsControls.colHint.Text = "已读取 $($script:StatsDataColumns.Count) 个列名：$($script:StatsDataColumns -join '、')"
        } else {
            $script:StatsControls.colHint.Text = '未能自动读取列名（Excel/SPSS 需先有 R）；可先另存为 CSV 再试。'
        }
    })
    return $p
}
function New-StatsStep2 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 2 步：选择要运行的方法 / 完成选择向导' 16 12 660 30 $true 13))
    $hint = New-Label '' 16 44 690 26
    $p.Controls.Add($hint)

    $methodList = New-Object System.Windows.Forms.CheckedListBox
    $methodList.Location = New-Object System.Drawing.Point(20, 78); $methodList.Size = New-Object System.Drawing.Size(500, 240)
    $methodList.CheckOnClick = $true
    foreach ($k in $script:StatsMethods.Keys) { [void]$methodList.Items.Add("$k — $($script:StatsMethods[$k])") }
    $p.Controls.Add($methodList)

    $fileMethods = New-Object System.Windows.Forms.CheckedListBox
    $fileMethods.Location = New-Object System.Drawing.Point(520, 78); $fileMethods.Size = New-Object System.Drawing.Size(200, 200)
    $fileMethods.CheckOnClick = $true; $fileMethods.Enabled = $false
    foreach ($k in $script:StatsMethods.Keys) { if ($k -ne 'power') { [void]$fileMethods.Items.Add("$k — $($script:StatsMethods[$k])") } }
    $p.Controls.Add($fileMethods)
    $fileHint = New-Label '勾选要跑的方法（可多选，一次跑完）；同名变量下一步只设一次。' 520 282 200 44 $false 9
    $fileHint.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($fileHint)

    $guidePanel = New-Object System.Windows.Forms.Panel
    $guidePanel.Location = New-Object System.Drawing.Point(20, 78); $guidePanel.Size = New-Object System.Drawing.Size(700, 240)
    $guidePanel.AutoScroll = $true; $guidePanel.BackColor = Get-ThemeColor 'bg'; $guidePanel.BorderStyle = 'FixedSingle'
    $guidePanel.Visible = $false
    $p.Controls.Add($guidePanel)

    $prev = New-Button '← 上一步' 450 330 120 40 'secondary'
    $next = New-Button '下一步 →' 580 330 130 40 'secondary'
    $p.Controls.AddRange(@($prev, $next))
    $prev.Add_Click({ Go-Prev }); $next.Add_Click({ Go-Next })
    # 防遮挡：导航按钮置顶，确保任何提示标签都盖不住、点得到
    $prev.BringToFront(); $next.BringToFront()

    $script:StatsStep2 = @{ hint=$hint; methodList=$methodList; fileMethods=$fileMethods; fileHint=$fileHint; guidePanel=$guidePanel }
    return $p
}
function New-StatsStep3 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 3 步：设置变量（把数据列对应到分析角色）' 16 12 700 30 $true 13))
    $hint = New-Label '' 16 44 690 26
    $p.Controls.Add($hint)

    $varPanel = New-Object System.Windows.Forms.Panel
    $varPanel.Location = New-Object System.Drawing.Point(20, 78); $varPanel.Size = New-Object System.Drawing.Size(700, 240)
    $varPanel.AutoScroll = $true; $varPanel.BackColor = Get-ThemeColor 'bg'; $varPanel.BorderStyle = 'FixedSingle'
    $p.Controls.Add($varPanel)

    $prev = New-Button '← 上一步' 450 330 120 40 'secondary'
    $next = New-Button '下一步 →' 580 330 130 40 'secondary'
    $p.Controls.AddRange(@($prev, $next))
    $prev.Add_Click({ Go-Prev }); $next.Add_Click({ Go-Next })

    $script:StatsStep3 = @{ hint=$hint; varPanel=$varPanel }
    return $p
}
function New-StatsStep4 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 4 步：运行分析并查看结果' 16 12 700 30 $true 13))
    $summary = New-Label '' 16 44 690 26
    $p.Controls.Add($summary)

    $run = New-Button '开始分析' 20 78 160 40 'primary'
    $cancel = New-Button '取消任务' 190 78 110 40
    $cancel.Enabled = $false
    $prev = New-Button '← 上一步' 580 78 130 40 'secondary'
    $p.Controls.AddRange(@($run, $cancel, $prev))
    $prev.Add_Click({ Go-Prev })
    $script:CancelBtns += $cancel
    $cancel.Add_Click({ Stop-GuiTask })

    $log = New-LogBox 20 128 700 300
    $p.Controls.Add($log)

    $script:StatsStep4 = @{ summary=$summary; run=$run; log=$log }
    $script:RunButtons += $run
    $run.Add_Click({ Start-StatsAnalysis })
    return $p
}

# ── CTT：3 个步骤面板 ─────────────────────────────────────────────────────────
function New-CttStep1 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 1 步：选择数据与路线（经典测量理论 CTT）' 16 12 700 30 $true 13))

    $rbSim = New-Object System.Windows.Forms.RadioButton
    $rbSim.Text = '内置模拟量表演示（480 人 × 15 题：清洗 + 项目分析 + 信度 + EFA）'
    $rbSim.Location = New-Object System.Drawing.Point(20, 60); $rbSim.Size = New-Object System.Drawing.Size(720, 26); $rbSim.Checked = $true
    $rbFile = New-Object System.Windows.Forms.RadioButton
    $rbFile.Text = '分析我自己的量表数据（一行一被试、一列一题）'
    $rbFile.Location = New-Object System.Drawing.Point(20, 92); $rbFile.Size = New-Object System.Drawing.Size(720, 26)
    $p.Controls.AddRange(@($rbSim, $rbFile))

    $fileBox = New-Object System.Windows.Forms.TextBox
    $fileBox.Location = New-Object System.Drawing.Point(20, 126); $fileBox.Size = New-Object System.Drawing.Size(500, 28); $fileBox.ReadOnly = $true
    $btnFile = New-Button '选择数据文件…' 530 124 130 30
    $p.Controls.AddRange(@($fileBox, $btnFile))

    $p.Controls.Add((New-Label '分析路线：' 20 172 120 24))
    $goal = New-Object System.Windows.Forms.ComboBox
    $goal.DropDownStyle = 'DropDownList'
    $goal.Location = New-Object System.Drawing.Point(20, 196); $goal.Size = New-Object System.Drawing.Size(430, 28)
    [void]$goal.Items.Add('quality — 量表质量检查（不做因子分析）')
    [void]$goal.Items.Add('efa — 质量检查 + 探索性因子分析')
    [void]$goal.Items.Add('cfa — 质量检查 + 验证性因子分析（需对照表）')
    $goal.SelectedIndex = 1
    $p.Controls.Add($goal)

    $mapBox = New-Object System.Windows.Forms.TextBox
    $mapBox.Location = New-Object System.Drawing.Point(460, 196); $mapBox.Size = New-Object System.Drawing.Size(210, 28); $mapBox.ReadOnly = $true
    $btnMap = New-Button '选择题目-维度对照表…' 460 228 200 30
    $p.Controls.AddRange(@($mapBox, $btnMap))
    $mapHint = New-Label '仅 cfa（验证性因子分析）路线需要题目-维度对照表：选中 cfa 后右侧才会出现选择框；quality / efa 路线无需对照表。' 20 232 430 48 $false 9
    $mapHint.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($mapHint)

    $next = New-Button '下一步 →' 580 330 130 40 'secondary'
    $p.Controls.Add($next)
    $next.Add_Click({ Go-Next })

    $script:CttControls = @{ rbSim=$rbSim; rbFile=$rbFile; fileBox=$fileBox; btnFile=$btnFile; goal=$goal; mapBox=$mapBox; btnMap=$btnMap }
    $rbSim.Add_CheckedChanged({ $script:CttControls.fileBox.Enabled=$false; $script:CttControls.btnFile.Enabled=$false; $script:CttControls.goal.Enabled=$false; $script:CttControls.mapBox.Enabled=$false; $script:CttControls.btnMap.Enabled=$false })
    $rbFile.Add_CheckedChanged({ $script:CttControls.fileBox.Enabled=$true; $script:CttControls.btnFile.Enabled=$true; $script:CttControls.goal.Enabled=$true; $script:CttControls.mapBox.Enabled=$true; $script:CttControls.btnMap.Enabled=$true })
    $btnFile.Add_Click({ $f = Select-PsychostatFile -Title '选择量表数据文件'; if ($f) { $script:CttFile = $f; $script:CttControls.fileBox.Text = $f } })
    $btnMap.Add_Click({ $f = Select-PsychostatFile -Title '选择题目-维度对照表（含 item,dimension 两列）' -Filter '对照表|*.csv;*.xlsx;*.xls|所有文件|*.*'; if ($f) { $script:CttMap = $f; $script:CttControls.mapBox.Text = $f } })
    return $p
}
function New-CttStep2 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 2 步：确认并运行' 16 12 600 30 $true 13))
    $summary = New-Label '' 16 50 700 120
    $p.Controls.Add($summary)

    $run = New-Button '开始分析' 20 190 160 40 'primary'
    $cancel = New-Button '取消任务' 190 190 110 40
    $cancel.Enabled = $false
    $prev = New-Button '← 上一步' 580 190 130 40 'secondary'
    $p.Controls.AddRange(@($run, $cancel, $prev))
    $prev.Add_Click({ Go-Prev })
    $cancel.Add_Click({ Stop-GuiTask })

    $log = New-LogBox 20 240 700 190
    $p.Controls.Add($log)

    $script:CttStep2 = @{ summary=$summary; log=$log }
    $script:RunButtons += $run
    $script:CancelBtns += $cancel
    $run.Add_Click({ Start-CttAnalysis })
    return $p
}

# ── IRT：3 个步骤面板 ─────────────────────────────────────────────────────────
# ── IRT 模型选择向导：与 run_irt_analysis.ps1 的 Invoke-IrtModelWizard 同口径 ──────────
# 推荐口径：de Ayala《The Theory and Practice of IRT》(2022) 与 Dai & Chang (2021, Frontiers in Education)：
# Rasch/1PL 百级样本即可稳定；2PL 每题多估区分度、约 250-500 起；3PL 猜测参数公认需 N≥1000；
# 多级 GRM/GPCM 参数更多、建议 N≥250-500（样本够时双模型 BIC 比较更稳）。
# 作用域约定：本向导所有事件处理一律用普通脚本块 + $script: 状态——GetNewClosure 的模块作用域
# 看不到主脚本的 $script: 变量（会报"无法对 Null 数组进行索引"，New-MainForm 里同款说明）。
$script:IrtWizQuestions = @(
    @{ key = 'scoring'; text = '问题 1/4：题目是什么计分？';    opts = @('二分：0/1、对/错、是/否','有序多级：Likert 1-5、0-4 等','不清楚（先按多级选，数据体检会按实际纠正）') },
    @{ key = 'dim';      text = '问题 2/4：测量结构是？';        opts = @('单维：一个总分/一个构念','多维，或不确定（让数据说话）') },
    @{ key = 'n';        text = '问题 3/4：有效样本量大约？';    opts = @('少于 100','100–250','250–500','500–1000','1000 及以上') }
)
$script:IrtWizChoice = $null     # 用户采用后的选择：fill/zh/reason/mirtMode/mirtItemModel

function Get-IrtWizCurrentQuestion {
    # 按进度返回当前问题；第 4 题按 计分/维度 分支（多级→作答方式、二分→特殊情况、多维→模式；多维再问家族）
    $st = $script:IrtWizDlg.state
    switch ($st.q) {
        1 { $script:IrtWizQuestions[0] }
        2 { $script:IrtWizQuestions[1] }
        3 { $script:IrtWizQuestions[2] }
        4 {
            if ($st.ans['dim'] -eq 2) { @{ key = 'mirtmode'; text = '问题 4/5：多维分析用哪种模式？'; opts = @('探索性 MIRT（EIFA，推荐：BIC 与平行分析定维度）','验证性 MIRT（CIFA，需要题目-维度归属表）') } }
            elseif ($st.ans['scoring'] -eq 1) { @{ key = 'spec'; text = '问题 4/4：有以下情况吗？'; opts = @('标准化选择题考试，低能力者可能猜对（3PL 线索）','想要 Rasch 优良性质：题难可加、适合小样本与题库建设','都没有') } }
            else { @{ key = 'resp'; text = '问题 4/4：多级题目的作答方式更接近？'; opts = @('Likert 同意度/频率量表（累积跨越类别）','部分计分/逐步作答，如 0/1/2 步骤得分','不确定（样本够时两个都用 BIC 比较）') } }
        }
        5 {
            if ($st.ans['dim'] -eq 2) { @{ key = 'family'; text = '问题 5/5：多维项目反应模型家族？'; opts = @('自动匹配（推荐：二分=多维 2PL/M2PL；多级=多维 GRM）','M2PL：多维 2PL（仅二分）','MGRM：多维 GRM（多级·累积 logit）','MGPCM：多维 GPCM（多级·相邻 logit）','M3PL：多维 3PL（仅二分·需 N≥1000）') } } else { $null }
        }
        default { $null }
    }
}
function Get-IrtWizardRecommendation {
    param([hashtable]$a)   # scoring/dim/n 与（按分支）resp、spec、mirtmode、family，均为 1 起始选项序号
    if ($a.dim -eq 2) {
        # 多维：模式与家族由第 4/5 问直接给出（M2PL/MGRM/MGPCM/M3PL 显式可选）
        $mode = if ($a.mirtmode -eq 2) { 'cifa' } else { 'eifa' }
        $im = 'auto'; $zh = if ($a.scoring -eq 1) { 'MIRT（多维 2PL / M2PL）' } else { 'MIRT（多维 GRM）' }
        if ($a.family -eq 2) { $im = '2pl'; $zh = 'MIRT（多维 2PL / M2PL）' }
        elseif ($a.family -eq 3) { $im = 'grm'; $zh = 'MIRT（多维 GRM / MGRM）' }
        elseif ($a.family -eq 4) { $im = 'gpcm'; $zh = 'MIRT（多维 GPCM / MGPCM）' }
        elseif ($a.family -eq 5) { $im = '3pl'; $zh = 'MIRT（多维 3PL / M3PL）' }
        $modeTxt = if ($mode -eq 'cifa') { '验证性 CIFA（下一步会要求选择题目-维度归属表）' } else { '探索性 EIFA（BIC 与平行分析定维度）' }
        return @{ fill = 'mirt'; zh = $zh; mirtMode = $mode; mirtItemModel = $im; reason = "多维结构 → MIRT，$modeTxt" }
    }
    if ($a.scoring -ne 1) {   # 多级（含"不清楚"，先按多级处理、体检会纠正）
        if ($a.resp -eq 2)  { return @{ fill = 'gpcm'; zh = 'GPCM'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = '部分计分/逐步作答 → GPCM（Muraki 1992 相邻类别 logit）' } }
        if ($a.n -le 2)     { return @{ fill = 'grm';  zh = 'GRM';  mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = '多级×单维×N≤250 → GRM（Samejima 1969 累积 logit，Likert 量表常用）。提示：多级模型参数较多，de Ayala 建议 N≥250-500，样本偏小时解读需谨慎' } }
        return @{ fill = 'auto'; zh = '自动推荐（GRM 与 GPCM 用 BIC 选优）'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = 'Likert 或作答方式不确定、且 N≥250 → GRM 与 GPCM 都拟合、BIC 选优（自动推荐在多级数据 N≥500 时会比较两者；Dai & Chang 2021 建议双模型比较）' }
    }
    # 二分
    if ($a.spec -eq 2 -or $a.n -le 2) {
        $why = if ($a.spec -eq 2) { '追求可加性/题库 → Rasch（每题只估难度，最省样本，百级即可稳定）' } else { 'N<250 → Rasch 最稳妥（2PL 每题多估区分度参数，小样本不稳）' }
        return @{ fill = 'rasch'; zh = 'Rasch/1PL'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = $why }
    }
    if ($a.spec -eq 1 -and $a.n -ge 5) { return @{ fill = '2pl'; zh = '2PL'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = '有猜测可能且 N≥1000 → 建议同时拟合 2PL 与 3PL 用 BIC 选优（3PL 猜测参数需大样本；终端向导会自动双拟合，本界面先按 2PL 填入）' } }
    if ($a.spec -eq 1) { return @{ fill = '2pl'; zh = '2PL'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = '有猜测可能但 N<1000 → 先用 2PL（3PL 的猜测参数在小样本估不稳，de Ayala 2022）' } }
    return @{ fill = 'auto'; zh = '自动推荐（Rasch 与 2PL 用 BIC 选优）'; mirtMode = 'eifa'; mirtItemModel = 'auto'; reason = 'N≥250 且无特殊要求 → Rasch 与 2PL 都拟合、BIC 选优（既检验 1PL 等区分度假设，又允许区分度差异）' }
}
function Update-IrtWizDialog {
    # 重绘向导对话框：有题目→画问题；Get-IrtWizCurrentQuestion 返回空→画推荐结果屏
    $d = $script:IrtWizDlg; if (-not $d) { return }
    $d.optHost.Controls.Clear()
    $qq = Get-IrtWizCurrentQuestion
    if ($null -ne $qq) {
        $d.qLabel.Text = $qq.text
        $y = 4; $idx = 1
        foreach ($o in $qq.opts) {
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = $o; $rb.Location = New-Object System.Drawing.Point(8, $y); $rb.Size = New-Object System.Drawing.Size(570, 30)
            $rb.Tag = $qq.key
            if ($d.state.ans[$qq.key] -eq $idx) { $rb.Checked = $true }
            $d.optHost.Controls.Add($rb); $y += 34; $idx++
        }
        $d.back.Enabled = ($d.state.q -gt 1); $d.next.Visible = $true
        $d.next.Text = if ($d.state.q -eq 4 -and $d.state.ans['dim'] -eq 2) { '下一步 →' } elseif ($d.state.q -ge 4) { '给出推荐 →' } else { '下一步 →' }
        return
    }
    # 推荐结果屏
    $rec = Get-IrtWizardRecommendation $d.state.ans
    $d.qLabel.Text = '向导推荐'
    $t1 = New-Label ("推荐模型：$($rec.zh)") 8 10 580 28 $true 12
    $t1.ForeColor = Get-ThemeColor 'accent'
    $t2 = New-Label ("理由：$($rec.reason)") 8 44 580 120 $false 9.5
    $t3 = New-Label '点「采用推荐」会记录选择并回到第 1 步（卡片同步显示）；之后点「下一步 →」继续。' 8 170 580 40 $false 9
    $t3.ForeColor = Get-ThemeColor 'textMuted'
    $adopt = New-Button '采用推荐' 180 210 240 34 'primary'
    $adopt.Add_Click({
        $rec2 = Get-IrtWizardRecommendation $script:IrtWizDlg.state.ans
        $script:IrtWizChoice = $rec2
        if ($script:IrtControls -and $script:IrtControls.wizCard) {
            $script:IrtControls.wizCard.Text = "模型：$($rec2.zh) —— $($rec2.reason)"
            $script:IrtControls.wizCard.ForeColor = Get-ThemeColor 'accent'
        }
        Sync-IrtStepViews
        $script:IrtWizDlg.form.Close()
    })
    $d.optHost.Controls.AddRange(@($t1, $t2, $t3, $adopt))
    $d.back.Enabled = $true; $d.next.Visible = $false
}
function Show-IrtModelWizardDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'IRT 模型选择向导'
    $dlg.ClientSize = New-Object System.Drawing.Size(640, 420)
    $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $qLabel = New-Label '' 16 14 600 26 $true 11
    $optHost = New-Object System.Windows.Forms.Panel
    $optHost.Location = New-Object System.Drawing.Point(16, 52); $optHost.Size = New-Object System.Drawing.Size(600, 250)
    $hint = New-Label '推荐口径：de Ayala《The Theory and Practice of IRT》(2022)；Dai & Chang (2021, Frontiers in Education)。' 16 360 600 40 $false 8.5
    $hint.ForeColor = Get-ThemeColor 'textMuted'
    $back = New-Button '← 上一步' 16 320 110 32 'secondary'
    $next = New-Button '下一步 →' 500 320 120 36 'primary'
    $script:IrtWizDlg = @{ form = $dlg; qLabel = $qLabel; optHost = $optHost; back = $back; next = $next; state = @{ q = 1; ans = @{} } }
    $next.Add_Click({
        $sel = @($script:IrtWizDlg.optHost.Controls | Where-Object { $_ -is [System.Windows.Forms.RadioButton] -and $_.Checked })
        if (-not $sel.Count) { [System.Windows.Forms.MessageBox]::Show('请先选择一个选项。', 'IRT 模型向导') | Out-Null; return }
        $key = "$($sel[0].Tag)"; $idx = 1
        foreach ($c in $script:IrtWizDlg.optHost.Controls) { if ($c -is [System.Windows.Forms.RadioButton]) { if ($c.Checked) { break }; $idx++ } }
        $script:IrtWizDlg.state.ans[$key] = $idx
        $script:IrtWizDlg.state.q++
        Update-IrtWizDialog
    })
    $back.Add_Click({ if ($script:IrtWizDlg.state.q -gt 1) { $script:IrtWizDlg.state.q--; Update-IrtWizDialog } })
    $dlg.Controls.AddRange(@($qLabel, $optHost, $hint, $back, $next))
    $dlg.Add_Shown({ Update-IrtWizDialog })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    $script:IrtWizDlg = $null
}

function New-IrtStep1 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 1 步：选择数据与模型' 16 12 600 30 $true 13))

    $rbSim = New-Object System.Windows.Forms.RadioButton
    $rbSim.Text = '内置模拟演示（单维 GRM）'
    $rbSim.Location = New-Object System.Drawing.Point(20, 56); $rbSim.Size = New-Object System.Drawing.Size(400, 26); $rbSim.Checked = $true
    $rbSim2 = New-Object System.Windows.Forms.RadioButton
    $rbSim2.Text = '内置模拟演示（多维 MIRT 探索性 EIFA）'
    $rbSim2.Location = New-Object System.Drawing.Point(20, 86); $rbSim2.Size = New-Object System.Drawing.Size(400, 26)
    $rbFile = New-Object System.Windows.Forms.RadioButton
    $rbFile.Text = '分析我自己的数据（整数计分）'
    $rbFile.Location = New-Object System.Drawing.Point(20, 116); $rbFile.Size = New-Object System.Drawing.Size(400, 26)
    $p.Controls.AddRange(@($rbSim, $rbSim2, $rbFile))

    $fileBox = New-Object System.Windows.Forms.TextBox
    $fileBox.Location = New-Object System.Drawing.Point(20, 150); $fileBox.Size = New-Object System.Drawing.Size(500, 28); $fileBox.ReadOnly = $true
    $btnFile = New-Button '选择数据文件…' 530 148 130 30
    $p.Controls.AddRange(@($fileBox, $btnFile))

    # 模型一律通过向导选择（不再暴露手动下拉）；向导按 计分→维度→样本量→作答方式/模式/家族 给推荐
    $wizBtn = New-Button '选择模型（向导推荐）' 20 190 220 40 'primary'
    $p.Controls.Add($wizBtn)
    $wizCard = New-Label '模型：尚未选择 —— 点「选择模型（向导推荐）」，回答 3-5 个问题即可获得带文献依据的推荐（Rasch/2PL/3PL/GRM/GPCM/MIRT·M2PL）。' 250 190 480 40 $false 9
    $wizCard.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($wizCard)
    $wizBtn.Add_Click({ Show-IrtModelWizardDialog })

    $mapBox = New-Object System.Windows.Forms.TextBox
    $mapBox.Location = New-Object System.Drawing.Point(20, 232); $mapBox.Size = New-Object System.Drawing.Size(430, 28); $mapBox.ReadOnly = $true
    $btnMap = New-Button '选择题目的维度归属表…' 460 230 200 30
    $p.Controls.AddRange(@($mapBox, $btnMap))
    $mapHint = New-Label '仅"验证性 MIRT（CIFA）"需要归属表：向导选到该模式时上面才会出现选择框。' 20 266 600 22 $false 9
    $mapHint.ForeColor = Get-ThemeColor 'textMuted'
    $p.Controls.Add($mapHint)

    $next = New-Button '下一步 →' 580 330 130 40 'secondary'
    $p.Controls.Add($next)
    $next.Add_Click({ Go-Next })

    $script:IrtControls = @{ rbSim=$rbSim; rbSim2=$rbSim2; rbFile=$rbFile; fileBox=$fileBox; btnFile=$btnFile; wizBtn=$wizBtn; wizCard=$wizCard; mapBox=$mapBox; btnMap=$btnMap }
    $disable = { $script:IrtControls.fileBox.Enabled=$false; $script:IrtControls.btnFile.Enabled=$false; $script:IrtControls.wizBtn.Enabled=$false; $script:IrtControls.mapBox.Enabled=$false; $script:IrtControls.btnMap.Enabled=$false }
    $rbSim.Add_CheckedChanged($disable); $rbSim2.Add_CheckedChanged($disable)
    $rbFile.Add_CheckedChanged({ $script:IrtControls.fileBox.Enabled=$true; $script:IrtControls.btnFile.Enabled=$true; $script:IrtControls.wizBtn.Enabled=$true; $script:IrtControls.mapBox.Enabled=$true; $script:IrtControls.btnMap.Enabled=$true })
    $btnFile.Add_Click({ $f = Select-PsychostatFile -Title '选择 IRT 数据文件'; if ($f) { $script:IrtFile = $f; $script:IrtControls.fileBox.Text = $f } })
    $btnMap.Add_Click({ $f = Select-PsychostatFile -Title '选择题目-维度归属表（列名 item,dimension）' -Filter '归属表|*.csv;*.xlsx;*.xls|所有文件|*.*'; if ($f) { $script:IrtMap = $f; $script:IrtControls.mapBox.Text = $f } })
    return $p
}
function New-IrtStep2 {
    $p = New-StepPanel
    $p.Controls.Add((New-Label '第 2 步：确认并运行' 16 12 600 30 $true 13))
    $summary = New-Label '' 16 50 700 120
    $p.Controls.Add($summary)

    $run = New-Button '开始分析' 20 190 160 40 'primary'
    $cancel = New-Button '取消任务' 190 190 110 40
    $cancel.Enabled = $false
    $prev = New-Button '← 上一步' 580 190 130 40 'secondary'
    $p.Controls.AddRange(@($run, $cancel, $prev))
    $prev.Add_Click({ Go-Prev })
    $cancel.Add_Click({ Stop-GuiTask })

    $log = New-LogBox 20 240 700 190
    $p.Controls.Add($log)

    $script:IrtStep2 = @{ summary=$summary; log=$log }
    $script:RunButtons += $run
    $script:CancelBtns += $cancel
    $run.Add_Click({ Start-IrtAnalysis })
    return $p
}

# ── 变量映射面板（脚本级：事件回调需在脚本作用域访问控件）──────────────────────
function Update-StatsVarPanel {
    $c = $script:StatsControls; $s3 = $script:StatsStep3
    if (-not $c -or -not $s3 -or -not $script:StatsStep2) { return }
    $s3.varPanel.Controls.Clear()
    if (-not ($c.rbFile.Checked -or $c.rbGuide.Checked)) { return }
    $methods = @(Get-SelectedFileMethods)
    if (-not $methods.Count) {
        $ph = if ($c.rbGuide.Checked) { '（先回到第 2 步完成向导问题，这里会显示推荐方法的变量设置）' } else { '（先回到第 2 步勾选方法，这里会显示变量设置）' }
        $l = New-Label $ph 12 12 620 24 $false 9.5
        $l.ForeColor = Get-ThemeColor 'textMuted'
        $s3.varPanel.Controls.Add($l); return
    }
    # 多方法字段合并：同一字段只出现一次，并标注被哪些方法共用
    $usage = @{}; $order = @()
    foreach ($m in $methods) {
        foreach ($f in $script:MethodFields[$m]) {
            if (-not $usage.ContainsKey($f)) { $usage[$f] = @(); $order += $f }
            $usage[$f] = @($usage[$f] + $m)
        }
    }
    $y = 10
    foreach ($f in $order) {
        $meta = $script:FieldMeta[$f]
        $shared = $usage[$f].Count -gt 1
        $labelText = $meta.label
        if ($shared) {
            $names = @($usage[$f] | ForEach-Object { $script:MethodCatalog[$_].zh })
            $labelText = "$($meta.label)（用于：$($names -join '、')，共用）"
        }
        $s3.varPanel.Controls.Add((New-Label $labelText 12 $y 250 $(if ($shared) { 40 } else { 24 }) $false 9.5))
        if ($meta.type -eq 'multi') {
            $clb = New-Object System.Windows.Forms.CheckedListBox
            $clb.Location = New-Object System.Drawing.Point(268, $y); $clb.Size = New-Object System.Drawing.Size(440, 140)
            $clb.CheckOnClick = $true; $clb.Tag = $f
            foreach ($col in $script:StatsDataColumns) { [void]$clb.Items.Add($col) }
            $s3.varPanel.Controls.Add($clb)
            $y += 148
        } elseif ($meta.type -eq 'value') {
            # 数值输入（如单样本 t 的检验值 μ）：普通文本框，留空 = 用 R 侧默认值
            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Location = New-Object System.Drawing.Point(268, $y); $tb.Size = New-Object System.Drawing.Size(200, 28)
            $tb.Tag = 'mu'
            $s3.varPanel.Controls.Add($tb)
            $y += 36 + $(if ($shared) { 8 } else { 0 })
        } else {
            $cb = New-Object System.Windows.Forms.ComboBox
            $cb.Location = New-Object System.Drawing.Point(268, $y); $cb.Size = New-Object System.Drawing.Size(440, 28)
            $cb.DropDownStyle = 'DropDownList'; $cb.Tag = $f
            foreach ($col in $script:StatsDataColumns) { [void]$cb.Items.Add($col) }
            $s3.varPanel.Controls.Add($cb)
            $y += 36 + $(if ($shared) { 8 } else { 0 })
        }
    }
    if ($order.Count -eq 0) { $s3.varPanel.Controls.Add((New-Label '所选方法不需要指定变量列（自动分析全部数值列）。' 12 12 560 24)) }
    # ── 方法专属追加询问：相关→是否偏相关；回归→是否分层（都是 SPSS 里独立的分析路径，多问一步避免做错）──
    if ($methods -contains 'correlation') {
        $y += 10
        $s3.varPanel.Controls.Add((New-Label '偏相关（可选）：控制第三变量后的独特关联，与普通相关结果不同（SPSS 两个不同菜单）' 12 $y 560 22 $true 9.5))
        $y += 26
        $ckP = New-Object System.Windows.Forms.CheckBox
        $ckP.Text = '本次要做偏相关（选 X、Y 与控制变量）'
        $yTop = $y - 3
        $ckP.Location = New-Object System.Drawing.Point(268, $yTop); $ckP.AutoSize = $true; $ckP.Tag = 'partial_enable'
        $s3.varPanel.Controls.Add($ckP)
        $pPanel = New-Object System.Windows.Forms.Panel
        $ySub = $y + 26
        $pPanel.Location = New-Object System.Drawing.Point(268, $ySub); $pPanel.Size = New-Object System.Drawing.Size(460, 150); $pPanel.Visible = $false
        $pPanel.Controls.Add((New-Label 'X（变量1）' 0 4 100 20 $false 9))
        $cbX = New-Object System.Windows.Forms.ComboBox
        $cbX.Location = New-Object System.Drawing.Point(120, 0); $cbX.Size = New-Object System.Drawing.Size(220, 28)
        $cbX.DropDownStyle = 'DropDownList'; $cbX.Tag = 'partial_x'
        foreach ($col in $script:StatsDataColumns) { [void]$cbX.Items.Add($col) }
        $pPanel.Controls.Add($cbX)
        $pPanel.Controls.Add((New-Label 'Y（变量2）' 0 36 100 20 $false 9))
        $cbY = New-Object System.Windows.Forms.ComboBox
        $cbY.Location = New-Object System.Drawing.Point(120, 32); $cbY.Size = New-Object System.Drawing.Size(220, 28)
        $cbY.DropDownStyle = 'DropDownList'; $cbY.Tag = 'partial_y'
        foreach ($col in $script:StatsDataColumns) { [void]$cbY.Items.Add($col) }
        $pPanel.Controls.Add($cbY)
        $pPanel.Controls.Add((New-Label '控制变量（可多选）' 0 68 110 20 $false 9))
        $clbC = New-Object System.Windows.Forms.CheckedListBox
        $clbC.Location = New-Object System.Drawing.Point(120, 64); $clbC.Size = New-Object System.Drawing.Size(220, 84)
        $clbC.CheckOnClick = $true; $clbC.Tag = 'partial_control'
        foreach ($col in $script:StatsDataColumns) { [void]$clbC.Items.Add($col) }
        $pPanel.Controls.Add($clbC)
        $s3.varPanel.Controls.Add($pPanel)
        $ckP.Add_CheckedChanged({ $pPanel.Visible = $this.Checked }.GetNewClosure())
        $y += 184
    }
    if ($methods -contains 'regression') {
        $y += 10
        $s3.varPanel.Controls.Add((New-Label '分层回归（可选）：SPSS 里分多个"块"依次进入，每块报告 ΔR² 与 F 变更' 12 $y 560 22 $true 9.5))
        $y += 26
        $ckB = New-Object System.Windows.Forms.CheckBox
        $ckB.Text = '本次要做分层回归（在下面填写每层变量）'
        $yTop = $y - 3
        $ckB.Location = New-Object System.Drawing.Point(268, $yTop); $ckB.AutoSize = $true; $ckB.Tag = 'blocks_enable'
        $s3.varPanel.Controls.Add($ckB)
        $bPanel = New-Object System.Windows.Forms.Panel
        $ySub = $y + 26
        $bPanel.Location = New-Object System.Drawing.Point(268, $ySub); $bPanel.Size = New-Object System.Drawing.Size(460, 78); $bPanel.Visible = $false
        $tbB = New-Object System.Windows.Forms.TextBox
        $tbB.Location = New-Object System.Drawing.Point(0, 0); $tbB.Size = New-Object System.Drawing.Size(440, 28)
        $tbB.Tag = 'blocks_str'
        $bPanel.Controls.Add($tbB)
        $bPanel.Controls.Add((New-Label '每层内变量用逗号分隔，层与层用竖线 | 分隔。例：性别,年龄 | 焦虑,压力 | 社会支持' 0 34 460 40 $false 9))
        $s3.varPanel.Controls.Add($bPanel)
        $ckB.Add_CheckedChanged({ $bPanel.Visible = $this.Checked }.GetNewClosure())
        $y += 112
    }
}
function Sync-StatsStepViews {
    # 第 2/3/4 步内容随第 1 步选择变化
    $c = $script:StatsControls; if (-not $c) { return }
    $mode = if ($c.rbSim.Checked) { 'sim' } elseif ($c.rbPick.Checked) { 'pick' } elseif ($c.rbGuide.Checked) { 'guide' } else { 'file' }
    if ($script:StatsStep2) {
        $s2 = $script:StatsStep2
        $s2.methodList.Enabled = ($mode -eq 'pick')
        $s2.methodList.Visible = ($mode -ne 'guide')
        $s2.fileMethods.Enabled = ($mode -eq 'file')
        $s2.fileMethods.Visible = ($mode -eq 'file')
        $s2.fileHint.Visible = ($mode -eq 'file')
        $s2.guidePanel.Visible = ($mode -eq 'guide')
        $s2.hint.Text = switch ($mode) {
            'sim'   { '将运行全部 21 个方法（无需选择）。' }
            'pick'  { '勾选要运行的方法（可多选）。' }
            'file'  { '在右侧勾选要运行的方法（可多选，一次跑完），然后“下一步”设置变量。' }
            'guide' { '回答下面的问题，向导会一步步推荐统计方法。' }
        }
    }
    if ($script:StatsStep3) {
        $script:StatsStep3.hint.Text = switch ($mode) {
            'sim'   { '演示模式无需设置变量，直接下一步。' }
            'pick'  { '演示模式无需设置变量，直接下一步。' }
            'file'  { '把数据列对应到下面的分析角色（下拉/勾选点选；多个方法共用同名变量时只设一次）。' }
            'guide' { if ($script:StatsFile) { '把数据列对应到推荐方法的分析角色。' } else { '未选择数据文件：第 4 步将用内置模拟数据演示推荐方法。' } }
        }
        Update-StatsVarPanel
    }
    if ($script:StatsStep4) {
        $script:StatsStep4.summary.Text = switch ($mode) {
            'sim'   { '将运行：全部 21 个方法（内置模拟数据，含 SPSS 对照讲解）。' }
            'pick'  { '将运行：所选方法（内置模拟数据）。' }
            'file'  {
                $ms = @(Get-SelectedFileMethods)
                $zh = @($ms | ForEach-Object { $script:MethodCatalog[$_].zh })
                "将分析：$($script:StatsFile)`r`n方法（$($ms.Count) 个）：" + ($zh -join '、')
            }
            'guide' {
                $rec = $script:GuideState.Rec
                if (-not $rec) { '先回到第 2 步完成向导问题，得到推荐方法。' }
                elseif ($script:StatsFile) { "向导推荐：$($script:MethodCatalog[$rec].zh)（$rec）`r`n将分析你的数据：$($script:StatsFile)" }
                else { "向导推荐：$($script:MethodCatalog[$rec].zh)（$rec）`r`n将用内置模拟数据演示该方法。" }
            }
        }
    }
}
function Sync-CttStepViews {
    $c = $script:CttControls; if (-not $c -or -not $script:CttStep2) { return }
    # 对照表可见性：仅 cfa（验证性）路线需要 mapBox/btnMap；其他路线隐藏。
    # 可见性独立于 Enabled（sim 模式整体禁用的逻辑保持不变）。
    $needMap = (("$($c.goal.SelectedItem)" -split ' — ')[0]) -eq 'cfa'
    $c.mapBox.Visible = $needMap; $c.btnMap.Visible = $needMap
    if ($c.rbSim.Checked) { $script:CttStep2.summary.Text = '将运行：内置模拟量表演示（清洗 + 项目分析 + 信度 + EFA）。' }
    else { $script:CttStep2.summary.Text = "将分析：$($script:CttFile)`r`n路线：" + ("$($c.goal.SelectedItem)" -split ' — ')[0] + $(if ($script:CttMap) { "`r`n对照表：$($script:CttMap)" } else { '' }) }
}
function Sync-IrtStepViews {
    $c = $script:IrtControls; if (-not $c -or -not $script:IrtStep2) { return }
    # 归属表可见性：仅向导选择了 mirt + cifa（验证性）时需要；模型来自向导（$script:IrtWizChoice）。
    $wiz = $script:IrtWizChoice
    $needMap = ($wiz -and $wiz.fill -eq 'mirt' -and $wiz.mirtMode -eq 'cifa')
    $c.mapBox.Visible = $needMap; $c.btnMap.Visible = $needMap
    if ($c.rbSim.Checked) { $script:IrtStep2.summary.Text = '将运行：内置模拟演示（单维 GRM）。' }
    elseif ($c.rbSim2.Checked) { $script:IrtStep2.summary.Text = '将运行：内置模拟演示（多维 MIRT 探索性 EIFA）。' }
    elseif ($wiz) {
        $script:IrtStep2.summary.Text = "将分析：$($script:IrtFile)`r`n模型：$($wiz.zh)" +
            $(if ($wiz.fill -eq 'mirt') { "`r`nMIRT 模式：$($wiz.mirtMode)" } else { '' }) +
            $(if ($script:IrtMap) { "`r`n归属表：$($script:IrtMap)" } else { '' })
    } else {
        $script:IrtStep2.summary.Text = "将分析：$($script:IrtFile)`r`n模型：尚未选择 —— 回到第 1 步点「选择模型（向导推荐）」。"
    }
}

# ── 启动逻辑 ──────────────────────────────────────────────────────────────────
function Start-StatsAnalysis {
    $script:LastTaskBranch = 'stats'   # 供任务完成后按分支打开对应 HTML 报告
    $c = $script:StatsControls
    if ($c.rbSim.Checked) {
        Start-GuiTask -Title '心理统计 · 教学演示全流程（21 方法）' -ScriptBody (New-AnalysisScript 'stats' $script:StatsPkgs (Join-Path $root 'stats_config.yaml') 'generate_stats_report.py')
        return
    }
    if ($c.rbPick.Checked) {
        $picked = @(); foreach ($i in $script:StatsStep2.methodList.CheckedItems) { $picked += ($i -split ' — ')[0] }
        if (-not $picked.Count) { [System.Windows.Forms.MessageBox]::Show('请回到第 2 步勾选方法。','Psychostat') | Out-Null; return }
        $cfg = Save-Config (New-StatsConfig 'simulate' $picked $null @{} (Get-GuiDataCheckPolicy)) '.gui_stats.json'
        Start-GuiTask -Title ("心理统计 · 模拟（" + ($picked -join ', ') + "）") -ScriptBody (New-AnalysisScript 'stats' $script:StatsPkgs $cfg 'generate_stats_report.py')
        return
    }
    if ($c.rbGuide.Checked) {
        $rec = $script:GuideState.Rec
        if (-not $rec) { [System.Windows.Forms.MessageBox]::Show('请先在第 2 步完成向导问题，得到推荐方法。','Psychostat') | Out-Null; return }
        if ($script:StatsFile) {
            if (-not $script:StatsDataColumns.Count) {
                [System.Windows.Forms.MessageBox]::Show('已选择数据文件但未读取到列名，无法设置变量。请将文件另存为 CSV 后重新选择，或不选文件改用模拟演示。','Psychostat') | Out-Null; return
            }
            $vars = Get-StatsVarsFromPanel
            $missing = Get-MissingSingleFields @($rec) $vars
            if ($missing.Count) { [System.Windows.Forms.MessageBox]::Show(("请回到第 3 步为以下变量选择列：" + ($missing -join '、')),'Psychostat') | Out-Null; return }
            $cfg = Save-Config (New-StatsConfig 'file' @($rec) $script:StatsFile $vars (Get-GuiDataCheckPolicy)) '.gui_stats.json'
            Start-GuiTask -Title "心理统计 · 向导推荐（$rec · 我的数据）" -ScriptBody (New-AnalysisScript 'stats' $script:StatsPkgs $cfg 'generate_stats_report.py')
        } else {
            $cfg = Save-Config (New-StatsConfig 'simulate' @($rec) $null @{} (Get-GuiDataCheckPolicy)) '.gui_stats.json'
            Start-GuiTask -Title "心理统计 · 向导推荐（$rec · 模拟演示）" -ScriptBody (New-AnalysisScript 'stats' $script:StatsPkgs $cfg 'generate_stats_report.py')
        }
        return
    }
    # 我的数据（方法可多选）
    if (-not $script:StatsFile) { [System.Windows.Forms.MessageBox]::Show('请回到第 1 步选择数据文件。','Psychostat') | Out-Null; return }
    $methods = @(Get-SelectedFileMethods)
    if (-not $methods.Count) { [System.Windows.Forms.MessageBox]::Show('请回到第 2 步勾选分析方法（可多选）。','Psychostat') | Out-Null; return }
    $vars = Get-StatsVarsFromPanel
    $missing = Get-MissingSingleFields $methods $vars
    if ($missing.Count) { [System.Windows.Forms.MessageBox]::Show(("请回到第 3 步为以下变量选择列：" + ($missing -join '、')),'Psychostat') | Out-Null; return }
    # 多选列（数值列/自变量列等）允许留空 = 由 R 自动选用数据中的全部数值列
    $cfg = Save-Config (New-StatsConfig 'file' $methods $script:StatsFile $vars (Get-GuiDataCheckPolicy)) '.gui_stats.json'
    $label = if ($methods.Count -gt 1) { "$($methods.Count) 个方法：" + ((@($methods | ForEach-Object { $script:MethodCatalog[$_].zh })) -join '、') } else { $methods[0] }
    Start-GuiTask -Title "心理统计 · 我的数据（$label）" -ScriptBody (New-AnalysisScript 'stats' $script:StatsPkgs $cfg 'generate_stats_report.py')
}
function Start-CttAnalysis {
    $script:LastTaskBranch = 'ctt'     # 供任务完成后按分支打开对应 HTML 报告
    $c = $script:CttControls
    if ($c.rbSim.Checked) {
        Start-GuiTask -Title 'CTT · 模拟量表演示' -ScriptBody (New-AnalysisScript 'ctt' $script:CttPkgs (Join-Path $root 'ctt_config.yaml') 'generate_ctt_report.py')
        return
    }
    if (-not $script:CttFile) { [System.Windows.Forms.MessageBox]::Show('请回到第 1 步选择量表数据文件。','Psychostat') | Out-Null; return }
    $goal = ("$($c.goal.SelectedItem)" -split ' — ')[0]
    if ($goal -eq 'cfa' -and -not $script:CttMap) { [System.Windows.Forms.MessageBox]::Show('CFA 路线需要题目-维度对照表，请在第 1 步选择。','Psychostat') | Out-Null; return }
    $cfg = Save-Config (New-CttConfig 'file' $script:CttFile $goal $script:CttMap) '.gui_ctt.json'
    Start-GuiTask -Title "CTT · 我的数据（$goal）" -ScriptBody (New-AnalysisScript 'ctt' $script:CttPkgs $cfg 'generate_ctt_report.py')
}
function Start-IrtAnalysis {
    $script:LastTaskBranch = 'irt'     # 供任务完成后按分支打开对应 HTML 报告
    $c = $script:IrtControls
    if ($c.rbSim.Checked) {
        Start-GuiTask -Title 'IRT · 单维 GRM 模拟演示' -ScriptBody (New-AnalysisScript 'irt' $script:IrtPkgs (Join-Path $root 'config.yaml') 'generate_result_reports.py')
        return
    }
    if ($c.rbSim2.Checked) {
        Start-GuiTask -Title 'IRT · 多维 MIRT（EIFA）模拟演示' -ScriptBody (New-AnalysisScript 'irt' $script:IrtPkgs (Join-Path $root 'examples\mirt_simulation.yaml') 'generate_result_reports.py')
        return
    }
    if (-not $script:IrtFile) { [System.Windows.Forms.MessageBox]::Show('请回到第 1 步选择数据文件。','Psychostat') | Out-Null; return }
    $wiz = $script:IrtWizChoice
    $model = if ($wiz) { $wiz.fill } else { 'auto' }
    $mirtMode = if ($wiz -and $wiz.mirtMode) { $wiz.mirtMode } else { 'eifa' }
    $mirtItemModel = if ($wiz -and $wiz.mirtItemModel) { $wiz.mirtItemModel } else { 'auto' }
    $zhLabel = if ($wiz) { $wiz.zh } else { '自动推荐（BIC 选优）' }
    if ($model -eq 'mirt' -and $mirtMode -eq 'cifa' -and -not $script:IrtMap) { [System.Windows.Forms.MessageBox]::Show('验证性 MIRT 需要题目-维度归属表。','Psychostat') | Out-Null; return }
    $cfg = Save-Config (New-IrtConfig 'file' $script:IrtFile $model $mirtMode $mirtItemModel $script:IrtMap) '.gui_irt.json'
    Start-GuiTask -Title "IRT · 我的数据（$zhLabel）" -ScriptBody (New-AnalysisScript 'irt' $script:IrtPkgs $cfg 'generate_result_reports.py')
}

# ── 主窗体 ────────────────────────────────────────────────────────────────────
function New-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Psychostat · 心理统计工具箱'
    $form.Size = New-Object System.Drawing.Size(1010, 720)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = Get-ThemeColor 'bg'
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $form.MinimumSize = New-Object System.Drawing.Size(920, 660)

    # 顶栏加高一行以容纳三段进度指示（装 R 包 → 跑分析 → 出报告）；标题/副标题位置不变
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'; $header.Height = 86; $header.BackColor = Get-ThemeColor 'primary'
    $hTitle = New-Label 'Psychostat 心理测量与统计分析' 18 14 480 30 $true 14
    $hTitle.ForeColor = [System.Drawing.Color]::White
    $hSub = New-Label '心理统计（SPSS 对照） · 经典测量理论 CTT · 项目反应理论 IRT' 484 18 500 24
    $hSub.ForeColor = Get-ThemeColor 'onPrimaryMuted'; $hSub.TextAlign = 'MiddleRight'
    $hSub.Anchor = 'Top,Right'
    $header.Controls.AddRange(@($hTitle, $hSub))

    # 三段进度指示（静态填充，禁动画）：三个小 Panel 横排 + 小字说明。
    # 状态由 Set-TaskSegment 维护（心跳 Update-TaskSegmentFromLog 推进 / 任务开始复位 / 成功全绿）。
    $segLbl = New-Label '任务进度' 0 50 64 20 $false 9
    $segLbl.ForeColor = Get-ThemeColor 'onPrimaryMuted'; $segLbl.TextAlign = 'MiddleRight'
    $header.Controls.Add($segLbl)
    $segNames = @('① 装 R 包', '② 跑分析', '③ 出报告')
    $script:SegPanels = @(); $script:SegCaptions = @()
    for ($i = 0; $i -lt 3; $i++) {
        $sp = New-Object System.Windows.Forms.Panel
        $sp.Size = New-Object System.Drawing.Size(84, 8)
        $sc = New-Label $segNames[$i] 0 0 84 16 $false 8
        $sc.TextAlign = 'MiddleCenter'; $sc.ForeColor = Get-ThemeColor 'onPrimaryMuted'
        $header.Controls.AddRange(@($sp, $sc))
        $script:SegPanels += $sp; $script:SegCaptions += $sc
    }
    # 顶栏宽度随窗体变化：Resize 时按右缘重新摆放（先算好坐标再进 New-Object，避开逗号/减号优先级坑）。
    # 作用域说明：这里故意不用 GetNewClosure——闭包块看不到主脚本的 $script: 变量（模块作用域只回退全局），
    # 普通脚本块则保留原会话作用域，$script: 引用全部有效（与既有 $centerPad 同一模式）。
    $script:SegLabel = $segLbl; $script:HeaderPanel = $header
    $layoutSeg = {
        try {
            $w = $script:HeaderPanel.Width
            $lx = $w - 354
            $script:SegLabel.Location = New-Object System.Drawing.Point($lx, 50)
            for ($i = 0; $i -lt 3; $i++) {
                $x = $w - 102 - ((2 - $i) * 90)
                $script:SegPanels[$i].Location = New-Object System.Drawing.Point($x, 56)
                $script:SegCaptions[$i].Location = New-Object System.Drawing.Point($x, 67)
            }
        } catch { }
    }
    $header.Add_Resize($layoutSeg)
    & $layoutSeg
    Set-TaskSegment 0   # 初始全灰
    $form.Controls.Add($header)

    $nav = New-Object System.Windows.Forms.Panel
    $nav.Dock = 'Left'; $nav.Width = 196; $nav.BackColor = Get-ThemeColor 'navBg'
    $nav.AutoScroll = $true

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'; $bottom.Height = 52; $bottom.BackColor = Get-ThemeColor 'bottomBg'
    $script:StatusLabel = New-Label '就绪。' 14 15 540 22
    $script:StatusLabel.ForeColor = Get-ThemeColor 'textBody'
    $script:StatusLabel.Anchor = 'Top,Left,Right'
    $script:HomeBtn = New-Button '⟲ 回到首页' 560 9 116 34 'secondary'; $script:HomeBtn.Enabled = $false
    $script:HomeBtn.Anchor = 'Top,Right'
    $script:OpenResultBtn = New-Button '打开结果文件夹' 684 9 150 34 'secondary'; $script:OpenResultBtn.Enabled = $false
    $script:OpenResultBtn.Anchor = 'Top,Right'
    $script:OpenReportBtn = New-Button '打开中文报告' 840 9 140 34 'secondary'; $script:OpenReportBtn.Enabled = $false
    $script:OpenReportBtn.Anchor = 'Top,Right'
    $bottom.Controls.AddRange(@($script:StatusLabel, $script:HomeBtn, $script:OpenResultBtn, $script:OpenReportBtn))

    $pageHost = New-Object System.Windows.Forms.Panel
    $pageHost.Dock = 'Fill'; $pageHost.Padding = New-Object System.Windows.Forms.Padding(24, 20, 24, 16)
    $pageHost.BackColor = Get-ThemeColor 'bg'
    $script:PageHost = $pageHost

    # 关键：WinForms 按“后加入 Controls 的先停靠”布局。若把 Fill 面板最后加入，
    # 它会先占满整个窗体，再被顶栏/左导航/底栏盖在上面——右侧内容被遮住的根源。
    # 必须最先加入 pageHost（并 BringToFront 兜底），停靠顺序才正确：
    # 顶栏横贯顶部 → 底栏横贯底部 → 左导航 → 内容区填满剩余区域。
    $form.Controls.Add($pageHost)
    $form.Controls.Add($nav)
    $form.Controls.Add($bottom)
    $form.Controls.Add($header)
    $pageHost.BringToFront()

    # 内容居中：窗体比内容带更宽时，左右动态加留白，让步骤表单保持在可视区中间
    $centerPad = {
        try {
            if (-not $script:PageHost) { return }
            $pad = [int][Math]::Floor([Math]::Max(24, ($script:PageHost.Width - $script:CenterBand) / 2))
            $script:PageHost.Padding = New-Object System.Windows.Forms.Padding($pad, 20, $pad, 16)
        } catch { }
    }
    $form.Add_Resize($centerPad)
    $form.Add_Shown($centerPad)

    $script:TaskTimer = New-Object System.Windows.Forms.Timer
    $script:TaskTimer.Interval = 400
    $script:TaskTimer.Add_Tick({ Update-GuiTask })

    $script:HomeBtn.Add_Click({ Show-Step 'home' 1 })
    $script:OpenResultBtn.Add_Click({ if ($script:LastResultDir) { Start-Process explorer.exe -ArgumentList $script:LastResultDir } })
    $script:OpenReportBtn.Add_Click({
        if (-not $script:LastResultDir) { return }
        # 优先中文 HTML 报告（默认浏览器）：按本次任务分支映射文件名，找不到再兜底任意 *_report_zh.html
        $html = Join-Path $script:LastResultDir (Get-BranchHtmlName $script:LastTaskBranch)
        if (-not (Test-Path -LiteralPath $html)) {
            $anyHtml = Get-ChildItem -Path $script:LastResultDir -Filter '*report_zh.html' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($anyHtml) { $html = $anyHtml.FullName }
        }
        if (Test-Path -LiteralPath $html) { Start-Process -FilePath $html; return }
        # HTML 不存在（生成器未就位/生成失败）→ 维持旧行为：记事本打开中文 Markdown 报告
        $zh = Join-Path $script:LastResultDir 'stats_report_zh.md'
        if (-not (Test-Path -LiteralPath $zh)) { $zh = (Get-ChildItem -Path $script:LastResultDir -Filter '*report_zh.md' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
        if ($zh) { Start-Process notepad.exe -ArgumentList $zh } else { [System.Windows.Forms.MessageBox]::Show('该结果目录没有中文报告（或还未生成）。','Psychostat') | Out-Null }
    })
    return $form
}

# ── 装配 ──────────────────────────────────────────────────────────────────────
function New-PsychostatApp {
    $form = New-MainForm
    $nav = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Dock -eq 'Left' } | Select-Object -First 1

    # 分支按钮（首页 + 三大功能模块）
    $nav.Controls.Add((New-Label '功能' 16 6 160 16 $true 9))
    $y = 24
    foreach ($nb in @(@{K='home';T='首页 · 功能总览'}, @{K='stats';T='心理统计'}, @{K='ctt';T='经典测量理论 CTT'}, @{K='irt';T='项目反应理论 IRT'})) {
        $b = New-Button $nb.T 12 $y 172 32
        $b.TextAlign = 'MiddleLeft'
        $key = $nb.K
        $b.Add_Click({ Show-Step $key 1 }.GetNewClosure())
        $nav.Controls.Add($b)
        $script:BranchButtons[$key] = $b
        $y += 36
    }

    $stepsLbl = New-Label '步骤' 16 ($y + 2) 160 16 $true 9
    $nav.Controls.Add($stepsLbl)
    $script:StepsLabel = $stepsLbl
    $y += 22
    $stepNames = @{ stats = @('1. 数据来源','2. 选择方法','3. 设置变量','4. 运行与结果'); ctt = @('1. 数据与路线','2. 确认并运行'); irt = @('1. 数据与模型','2. 确认并运行') }
    foreach ($br in @('stats','ctt','irt')) {
        $i = 1
        foreach ($sn in $stepNames[$br]) {
            $b = New-Button $sn 20 $y 164 26
            $b.TextAlign = 'MiddleLeft'
            $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
            $key = $br + ':' + $i
            $brc = $br; $stepNum = $i
            $b.Add_Click({ Show-Step $brc $stepNum }.GetNewClosure())
            $b.Visible = $false
            $nav.Controls.Add($b)
            $script:StepButtons[$key] = $b
            $y += 30
            $i++
        }
    }
    $y += 4
    $sep = New-Label '──────────' 16 $y 160 14 $false 9
    $sep.ForeColor = Get-ThemeColor 'separator'
    $nav.Controls.Add($sep)
    $y += 20

    $btnAI = New-Button '用 AI 助手协助' 12 $y 172 28
    $btnAI.TextAlign = 'MiddleLeft'
    $btnAI.Add_Click({ Start-Process notepad.exe -ArgumentList (Join-Path $root 'AI智能体工作流.md') })
    $nav.Controls.Add($btnAI); $y += 34

    $btnCheck = New-Button '检查环境/自动安装' 12 $y 172 28
    $btnCheck.TextAlign = 'MiddleLeft'
    $btnCheck.Add_Click({
        $envScript = Join-Path $root 'psychostat_env.ps1'
        $body = @"
`$ErrorActionPreference = 'Continue'
. '$envScript'
Write-Host '正在准备运行环境（缺失的依赖会自动安装，可能需要几分钟）...'
`$r = Initialize-PsychostatEnvironment -AllowAutoInstall
Write-Host ('R：' + `$r)
`$py = Initialize-PsychostatPythonEnvironment -ProjectRoot '$root'
Write-Host ('Python：' + `$py.Note)
# 这里必须把三条分支的 R 包也装齐：原先本按钮只装 Python，用户点完它再点"开始分析"仍要下载 R 包，
# 于是按钮看起来没有用（职责与名称不一致）。现在装包清单取自 psychenv 的单一来源。
Write-Host ''
Write-Host '正在检查 R 包（只装缺的，已装自动跳过）...'
`$allPkgs = Get-PsychostatRequiredPackages -Branch all
`$pkgScript = Get-PsychostatPackageInstallScript -Packages `$allPkgs
`$prevEap = `$ErrorActionPreference; `$ErrorActionPreference = 'Continue'
& `$r --vanilla `$pkgScript 2>&1 | ForEach-Object { Write-Host "  `$_" -ForegroundColor DarkGray }
`$pkgExit = `$LASTEXITCODE
`$ErrorActionPreference = `$prevEap
Remove-Item -LiteralPath `$pkgScript -Force -ErrorAction SilentlyContinue
Write-Host ''
if (`$pkgExit -eq 0) {
    Write-Host '环境检查完成：R、R 包与 Python 均已就绪，后续分析无需再下载依赖。' -ForegroundColor Green
} else {
    Write-Host '环境检查基本完成，但部分 R 包未能安装（常见原因：网络慢或镜像缺包）。' -ForegroundColor Yellow
    Write-Host '可换网络后重试，或直接点开始分析——缺的包会在分析前自动重试安装。' -ForegroundColor Yellow
}
"@
        Start-GuiTask -Title '环境检查与自动安装' -ScriptBody $body -Interactive
    })
    $nav.Controls.Add($btnCheck); $y += 34

    $btnCleanup = New-Button '清理已安装环境' 12 $y 172 28 'danger'
    $btnCleanup.TextAlign = 'MiddleLeft'
    $btnCleanup.Add_Click({
        # ① 取预览（只读，不会删除任何东西）
        try {
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $preview = Invoke-PsychostatCleanupPreview
        } catch {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            [System.Windows.Forms.MessageBox]::Show("读取清理预览失败：$($_.Exception.Message)", 'Psychostat') | Out-Null
            return
        } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
        # ② 让用户在可滚动对话框里看清楚，再决定（关闭＝什么都不做）
        if (-not (Show-PsychostatCleanupDialog -PreviewText $preview)) { return }
        # ③ 执行清理并汇报结果
        try {
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $res = Invoke-PsychostatCleanupExecute
        } catch {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            [System.Windows.Forms.MessageBox]::Show("清理执行失败：$($_.Exception.Message)", 'Psychostat') | Out-Null
            return
        } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
        $lines = @($res.Text -split "`r?`n" | Where-Object { $_ -match '已删除|删除失败|清理完成|完成，但有' })
        $tail = ($lines | Select-Object -First 12) -join [Environment]::NewLine
        if ($res.ExitCode -eq 0) {
            $msg = '清理完成。' + [Environment]::NewLine + [Environment]::NewLine + $tail + [Environment]::NewLine + [Environment]::NewLine + '你已有的 R / Python 与你的数据、分析结果都未改动。'
            [System.Windows.Forms.MessageBox]::Show($msg, 'Psychostat 环境清理', 'OK', 'Information') | Out-Null
        } else {
            $msg = '有部分内容未能删除（常见原因：目录正被其它窗口占用）。' + [Environment]::NewLine + [Environment]::NewLine + $tail + [Environment]::NewLine + [Environment]::NewLine + '关闭其它 Psychostat 窗口 / R 会话后，可再点一次本按钮重试。'
            [System.Windows.Forms.MessageBox]::Show($msg, 'Psychostat 环境清理', 'OK', 'Warning') | Out-Null
        }
    })
    $nav.Controls.Add($btnCleanup); $y += 34

    $btnOpen = New-Button '打开结果文件夹' 12 $y 172 28
    $btnOpen.TextAlign = 'MiddleLeft'
    $btnOpen.Add_Click({
        $out = Join-Path $root 'outputs'
        if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out -Force | Out-Null }
        Start-Process explorer.exe -ArgumentList $out
    })
    $nav.Controls.Add($btnOpen); $y += 36

    # 环境状态灯（R / Python）：彩色圆点 + 文字，替代原先的纯文字两行标签。
    # 圆点用「●」文字 Label + ForeColor 实现（比对齐 12x12 色块简单，且与文字基线天然对齐）；
    # 颜色语义见 Update-EnvStatusLights：绿=就绪 / 黄=可用但有缺 / 红=缺失。
    $envLbl = New-Label '环境状态' 16 $y 160 16 $true 9
    $nav.Controls.Add($envLbl)
    $y2 = $y + 22
    $rDot = New-Label '●' 14 $y2 18 18 $false 10
    $rDot.ForeColor = Get-ThemeColor 'textMuted'; $rDot.TextAlign = 'MiddleLeft'
    $rText = New-Label 'R：检测中…' 34 ($y2 - 1) 156 20 $false 9
    $rText.ForeColor = Get-ThemeColor 'textBody'; $rText.TextAlign = 'MiddleLeft'
    $y3 = $y + 44
    $pyDot = New-Label '●' 14 $y3 18 18 $false 10
    $pyDot.ForeColor = Get-ThemeColor 'textMuted'; $pyDot.TextAlign = 'MiddleLeft'
    $pyText = New-Label 'Python：检测中…' 34 ($y3 - 1) 156 20 $false 9
    $pyText.ForeColor = Get-ThemeColor 'textBody'; $pyText.TextAlign = 'MiddleLeft'
    $y4 = $y + 68
    $envCap = New-Label '绿=就绪　黄=可用但有缺　红=缺失；Python 只影响报告生成。' 14 $y4 174 30 $false 8.5
    $envCap.ForeColor = Get-ThemeColor 'textMuted'
    $nav.Controls.AddRange(@($rDot, $rText, $pyDot, $pyText, $envCap))
    $script:EnvState = @{ RDot=$rDot; RText=$rText; PyDot=$pyDot; PyText=$pyText }

    # 步骤面板（首页 + 三大功能模块）
    $script:Wizard['home']  = @((New-HomePage))
    $script:Wizard['stats'] = @((New-StatsStep1), (New-StatsStep2), (New-StatsStep3), (New-StatsStep4))
    $script:Wizard['ctt']   = @((New-CttStep1), (New-CttStep2))
    $script:Wizard['irt']   = @((New-IrtStep1), (New-IrtStep2))

    # 第 1 步的单选项变化 → 同步后续步骤视图
    $script:StatsControls.rbSim.Add_CheckedChanged({ Sync-StatsStepViews })
    $script:StatsControls.rbPick.Add_CheckedChanged({ Sync-StatsStepViews })
    $script:StatsControls.rbFile.Add_CheckedChanged({ Sync-StatsStepViews })
    $script:StatsControls.rbGuide.Add_CheckedChanged({ Sync-StatsStepViews })
    $script:StatsStep2.fileMethods.Add_SelectedIndexChanged({ Sync-StatsStepViews })
    $script:CttControls.rbSim.Add_CheckedChanged({ Sync-CttStepViews })
    $script:CttControls.rbFile.Add_CheckedChanged({ Sync-CttStepViews })
    $script:CttControls.goal.Add_SelectedIndexChanged({ Sync-CttStepViews })
    $script:IrtControls.rbSim.Add_CheckedChanged({ Sync-IrtStepViews })
    $script:IrtControls.rbSim2.Add_CheckedChanged({ Sync-IrtStepViews })
    $script:IrtControls.rbFile.Add_CheckedChanged({ Sync-IrtStepViews })

    Update-GuidePanel
    Sync-StatsStepViews; Sync-CttStepViews; Sync-IrtStepViews
    Show-Step 'home' 1

    # 界面显示后再探测环境，避免启动瞬间卡顿；结果写入状态灯（颜色语义见 Update-EnvStatusLights）
    $form.Add_Shown({
        try {
            $rs = Get-RscriptPath; $py = Get-PythonPath
            Update-EnvStatusLights ([bool]$rs) ([bool]$py)
        } catch { }
    })
    return [pscustomobject]@{ Form = $form; Steps = $script:Wizard }
}

if ($SelfTestAnalysis) {
    # 端到端自检：用 GUI 的后台脚本模板真跑一次最小分析，验证“结果目录能被界面识别”
    $cfg = Save-Config (New-StatsConfig 'simulate' @('independent_t') $null @{}) '.gui_selftest.json'
    $marker = Join-Path $root 'outputs\.last_result_dir.txt'
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $body = New-AnalysisScript 'stats' $script:StatsPkgs $cfg ''
    $tmp = Join-Path $env:TEMP ('psychostat_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.ps1')
    [IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($true)))
    # 说明：此处用同进程调用（而非 Start-Process），以便在受限环境也能自检；
    #       界面运行时的进程启动方式（Start-Process + 重定向 + 隐藏窗口）保持不变。
    $log = (& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $hasMarker = Test-Path -LiteralPath $marker
    $markerValue = if ($hasMarker) { (Get-Content -LiteralPath $marker -Encoding UTF8 | Select-Object -First 1) } else { '' }
    $logHasDir = [bool]($log -match '结果目录：')
    $logHasFiles = [bool]($log -match '共生成')
    Write-Host ("分析自检：退出码=$code 结果标记存在=$hasMarker 日志含结果目录=$logHasDir 日志含文件清单=$logHasFiles")
    if ($markerValue) { Write-Host ("标记内容：$markerValue") }
    $ok = ($code -eq 0) -and $hasMarker -and $logHasDir -and $logHasFiles -and (Test-Path -LiteralPath $markerValue)
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if ($ok) { Write-Host 'ANALYSIS SELF-TEST OK（结果目录可被界面识别）' } else {
        Write-Host 'ANALYSIS SELF-TEST FAILED'
        ($log -split "`r?`n") | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    exit 0
}

if ($SelfTest) {
    $app = New-PsychostatApp
    $n = 0
    foreach ($br in $app.Steps.Keys) { foreach ($pnl in $app.Steps[$br]) { $n += $pnl.Controls.Count } }
    # 深度自检：遍历所有步骤切换与视图同步，捕获任何运行时错误（防“点击后卡住/报错”）
    $errors = @()
    foreach ($br in @('home','stats','ctt','irt')) {
        for ($i = 1; $i -le $script:Wizard[$br].Count; $i++) {
            try { Show-Step $br $i } catch { $errors += "Show-Step $br $i : $($_.Exception.Message)" }
        }
    }
    foreach ($fn in @('Sync-StatsStepViews','Sync-CttStepViews','Sync-IrtStepViews')) {
        try { & $fn } catch { $errors += "$fn : $($_.Exception.Message)" }
    }
    try { $script:StatsControls.rbFile.Checked = $true; Sync-StatsStepViews; $script:StatsControls.rbPick.Checked = $true; Sync-StatsStepViews } catch { $errors += "stats mode switch: $($_.Exception.Message)" }
    try {
        $script:StatsControls.rbGuide.Checked = $true; Sync-StatsStepViews
        # 第 0 步数据准备不在方法列表里（它总是自动运行），故 q1 不应再出现 datacheck 选项
        if ($script:MethodCatalog.Contains('datacheck') -or $script:StatsMethods.Contains('datacheck')) {
            $errors += "第0步数据准备不应出现在方法列表中（它是默认自动运行的）"
        }
        Reset-Guide; Select-GuideOption 'q1' 1; Select-GuideOption 'q2c' 1; Select-GuideOption 'q3rel' 0
        if ($script:GuideState.Rec -ne 'correlation') { $errors += "向导决策路径1：rec=$($script:GuideState.Rec)（应为 correlation）" }
        Reset-Guide; Select-GuideOption 'q1' 2; Select-GuideOption 'q2a' 1
        if ($script:GuideState.Rec -ne 'chi_square_independence') { $errors += "向导决策路径2：rec=$($script:GuideState.Rec)（应为 chi_square_independence）" }
        Reset-Guide; Select-GuideOption 'q1' 1; Select-GuideOption 'q2c' 0; Select-GuideOption 'q3diff' 0; Select-GuideOption 'q4paired' 1
        if ($script:GuideState.Rec -ne 'paired_t') { $errors += "向导决策路径3：rec=$($script:GuideState.Rec)（应为 paired_t）" }
        $script:StatsControls.rbPick.Checked = $true; Sync-StatsStepViews
    } catch { $errors += "guide wizard: $($_.Exception.Message)" }
    try { $script:CttControls.rbFile.Checked = $true; Sync-CttStepViews } catch { $errors += "ctt file sync: $($_.Exception.Message)" }
    try { $script:IrtControls.rbFile.Checked = $true; Sync-IrtStepViews } catch { $errors += "irt file sync: $($_.Exception.Message)" }
    try { $script:IrtWizChoice = @{ fill = 'mirt'; zh = 'MIRT'; mirtMode = 'cifa'; mirtItemModel = 'auto' }; Sync-IrtStepViews } catch { $errors += "irt model sync: $($_.Exception.Message)" }
    # G1 断言：stats/CTT/IRT 三个运行页各有一个“取消任务”按钮
    if (@($script:CancelBtns).Count -ne 3) { $errors += "取消按钮应有三处（stats/CTT/IRT），实际 $(@($script:CancelBtns).Count)" }
    # G2 断言：对照表/归属表可见性随下拉联动（CTT 仅 cfa；IRT 仅 mirt+cifa）。
    # 窗体未显示时 Control.Visible 恒 false，故用反射读 STATE_VISIBLE（同下方可见性检查）。
    try {
        $gs2 = [System.Windows.Forms.Control].GetMethod('GetState', [System.Reflection.BindingFlags]'NonPublic,Instance')
        $script:CttControls.goal.SelectedIndex = 2; Sync-CttStepViews
        if (-not ([bool]$gs2.Invoke($script:CttControls.mapBox, @(2)) -and [bool]$gs2.Invoke($script:CttControls.btnMap, @(2)))) { $errors += 'CTT cfa 路线下对照表控件应可见' }
        $script:CttControls.goal.SelectedIndex = 1; Sync-CttStepViews
        if ([bool]$gs2.Invoke($script:CttControls.mapBox, @(2)) -or [bool]$gs2.Invoke($script:CttControls.btnMap, @(2))) { $errors += 'CTT 非 cfa 路线下对照表控件应隐藏' }
        $script:IrtWizChoice = @{ fill = 'mirt'; zh = 'MIRT'; mirtMode = 'cifa'; mirtItemModel = 'auto' }; Sync-IrtStepViews
        if (-not ([bool]$gs2.Invoke($script:IrtControls.mapBox, @(2)) -and [bool]$gs2.Invoke($script:IrtControls.btnMap, @(2)))) { $errors += 'IRT mirt+cifa 下归属表控件应可见' }
        $script:IrtWizChoice = @{ fill = 'grm'; zh = 'GRM'; mirtMode = 'eifa' }; Sync-IrtStepViews
        if ([bool]$gs2.Invoke($script:IrtControls.mapBox, @(2)) -or [bool]$gs2.Invoke($script:IrtControls.btnMap, @(2))) { $errors += 'IRT 非 cifa（或非 mirt）下归属表控件应隐藏' }
        $script:IrtWizChoice = $null; Sync-IrtStepViews
    } catch { $errors += "map visibility sync: $($_.Exception.Message)" }
    # G4 断言：IRT 模型向导产出的 mirt_item_model 必须被 R 侧校验接受。
    # 白名单**直接从 scripts\irt_common.R 里读**，避免测试与实现各写一份而漂移——
    # 历史上正是这里漏掉了 gpcm：向导的「MGPCM」一被选中，就在读配置阶段报错退出。
    try {
        $irtCommonTxt = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\irt_common.R')
        $irtAllowRe = [regex]::Match($irtCommonTxt, 'mirt_item_model %in% c\(([^)]*)\)')
        if (-not $irtAllowRe.Success) {
            $errors += 'IRT 向导自检：未能从 irt_common.R 解析 mirt_item_model 的允许取值'
        } else {
            $irtAllowed = @([regex]::Matches($irtAllowRe.Groups[1].Value, '"([a-z0-9]+)"') | ForEach-Object { $_.Groups[1].Value })
            $irtProduced = New-Object System.Collections.Generic.HashSet[string]
            foreach ($wSc in 1, 2, 3) { foreach ($wDim in 1, 2) { foreach ($wN in 1, 2, 3, 4, 5) {
              foreach ($wResp in 1, 2, 3) { foreach ($wSpec in 1, 2, 3) { foreach ($wMm in 1, 2) { foreach ($wFam in 1, 2, 3, 4, 5) {
                $wRec = Get-IrtWizardRecommendation @{ scoring = $wSc; dim = $wDim; n = $wN; resp = $wResp; spec = $wSpec; mirtmode = $wMm; family = $wFam }
                if ($wRec -and $wRec.mirtItemModel) { [void]$irtProduced.Add("$($wRec.mirtItemModel)") }
              } } } } } } }
            $irtBad = @($irtProduced | Where-Object { $_ -notin $irtAllowed })
            if ($irtBad.Count) {
                $errors += "IRT 模型向导会产出 R 侧不接受的 mirt_item_model：$($irtBad -join '、')（允许：$($irtAllowed -join '/')）"
            }
        }
    } catch { $errors += "irt wizard mirt_item_model contract: $($_.Exception.Message)" }
    # G3 断言：任务脚本模板对含撇号路径（O'Brien 式用户目录）做单引号翻倍转义，产物须仍是合法 PowerShell
    $savedRoot = $root
    try {
        $root = "C:\tmp\r'o"
        $probe = New-AnalysisScript 'stats' $script:StatsPkgs "C:\tmp\it's\cfg.json" ''
    } finally { $root = $savedRoot }
    if ($probe -notlike "*C:\tmp\r''o\psychostat_env.ps1*") { $errors += '任务脚本模板：根路径撇号未翻倍转义' }
    if ($probe -notlike "*C:\tmp\it''s\cfg.json*") { $errors += '任务脚本模板：配置路径撇号未翻倍转义' }
    if ($probe -like "*C:\tmp\it's*") { $errors += '任务脚本模板：仍残留未转义的裸撇号路径' }
    try {
        $ptok = $null; $perr = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($probe, [ref]$ptok, [ref]$perr)
        if ($perr) { $errors += "任务脚本模板：含撇号路径的产物有语法错误（$($perr[0].Message)）" }
    } catch { $errors += "任务脚本模板语法解析：$($_.Exception.Message)" }
    # 关键断言：切到每一步后，页面容器里必须是该步骤面板，且其“自身可见位”为真
    # 说明：窗体未显示时 Control.Visible 返回有效可见性（恒 false），故用反射读控件状态位 STATE_VISIBLE。
    $getState = [System.Windows.Forms.Control].GetMethod('GetState', [System.Reflection.BindingFlags]'NonPublic,Instance')
    foreach ($br in @('home','stats','ctt','irt')) {
        for ($i = 1; $i -le $script:Wizard[$br].Count; $i++) {
            try {
                Show-Step $br $i
                $cnt = $script:PageHost.Controls.Count
                $first = if ($cnt -gt 0) { $script:PageHost.Controls[0] } else { $null }
                $ctlCount = if ($first) { $first.Controls.Count } else { 0 }
                $selfVis = if ($first -and $getState) { [bool]$getState.Invoke($first, @(2)) } else { $null }
                if ($first -ne $script:Wizard[$br][$i - 1]) { $errors += "步骤 $br/$i 显示的并非对应面板" }
                if ($selfVis -eq $false) { $errors += "步骤 $br/$i 面板自身可见位为假（Show-Step 未生效 → 右侧会空白）" }
                if ($ctlCount -lt 3) { $errors += "步骤 $br/$i 内容控件过少（$ctlCount 个），可能布局异常" }
                # 布局断言：控件右边界不得超过内容区可用宽度（窗口 1010 - 导航 196 - 内边距）
                $maxRight = 0
                foreach ($child in $first.Controls) { if ($child.Right -gt $maxRight) { $maxRight = $child.Right } }
                if ($maxRight -gt 740) { $errors += "步骤 $br/$i 有控件超出可用宽度（最右 $maxRight px > 740）" }
                # 防遮挡断言：任何标签不得与按钮重叠（否则按钮点不到，导航被卡死）
                $navBtns = @($first.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
                foreach ($lbl in @($first.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })) {
                    foreach ($bt in $navBtns) {
                        if ($lbl.Bounds.IntersectsWith($bt.Bounds)) {
                            $t = $lbl.Text; if ($t.Length -gt 12) { $t = $t.Substring(0, 12) + '…' }
                            $errors += ('步骤 ' + $br + '/' + $i + ' 标签「' + $t + '」遮挡按钮「' + $bt.Text + '」——按钮将无法点击')
                        }
                    }
                }
            } catch { $errors += "可见性检查 $br/$i : $($_.Exception.Message)" }
        }
    }
    # 布局断言：内容区不得被顶栏/左导航/底栏覆盖，顶栏必须横贯窗体
    # （历史 bug：Fill 面板后加入 Controls → 先停靠占满全窗 → 内容被导航盖住左上角）
    try {
        $app.Form.PerformLayout()
        $navPanel = $app.Form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Dock -eq 'Left' }   | Select-Object -First 1
        $hdrPanel = $app.Form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Dock -eq 'Top' }    | Select-Object -First 1
        $btmPanel = $app.Form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Dock -eq 'Bottom' } | Select-Object -First 1
        if ($script:PageHost.Left -lt ($navPanel.Width - 2))  { $errors += "内容区左缘 $($script:PageHost.Left) 落在左导航（宽 $($navPanel.Width)）下面——停靠顺序回归" }
        if ($script:PageHost.Top  -lt ($hdrPanel.Height - 2)) { $errors += "内容区顶缘 $($script:PageHost.Top) 落在顶栏（高 $($hdrPanel.Height)）下面——停靠顺序回归" }
        if ($btmPanel.Top -lt ($script:PageHost.Bottom - 2))   { $errors += "内容区底缘 $($script:PageHost.Bottom) 压到底栏（顶缘 $($btmPanel.Top)）——停靠顺序回归" }
        if ($hdrPanel.Width -lt ($app.Form.ClientSize.Width - 4)) { $errors += "顶栏宽 $($hdrPanel.Width) 未横贯窗体宽 $($app.Form.ClientSize.Width)——停靠顺序回归" }
    } catch { $errors += "布局断言 : $($_.Exception.Message)" }

    # 环境清理入口断言：左导航必须有「清理已安装环境」按钮，且相关函数齐全
    # （该流程只调用 uninstall_psychostat.ps1 的 -PreviewOnly / -Execute -Force；不在此处执行删除）
    try {
        if (-not ($navPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -like '*清理*' })) {
            $errors += '左导航缺少「清理已安装环境」按钮（环境清理入口丢失）'
        }
        foreach ($fn in @('Invoke-PsychostatCleanupPreview', 'Invoke-PsychostatCleanupExecute', 'Show-PsychostatCleanupDialog')) {
            if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { $errors += "缺少界面函数 $fn" }
        }
        $cleanupScript = Join-Path $root 'scripts\uninstall_psychostat.ps1'
        if (-not (Test-Path -LiteralPath $cleanupScript)) { $errors += '缺少 scripts\uninstall_psychostat.ps1（清理按钮将无法工作）' }
    } catch { $errors += "清理入口断言 : $($_.Exception.Message)" }

    $app.Form.Dispose()
    if ($errors.Count) {
        Write-Host 'GUI SELF-TEST FAILED:'
        $errors | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host "GUI SELF-TEST OK（步骤切换与视图同步均正常；步骤面板控件合计：$n）"
    exit 0
}

$app = New-PsychostatApp
[void]$app.Form.ShowDialog()
