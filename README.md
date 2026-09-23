# Psychostat：心理测量与统计分析一体化教学工具

> 一个入口，三个任务：**心理统计（SPSS 对照教学）· CTT 经典测量理论 · IRT 项目反应理论**。
> 面向心理学本/硕学生与研究者：内置教学模拟数据，既可手动交互使用（PowerShell），也可被 AI 智能体以静默模式调用（逐行 JSON 日志）。
> 本目录不含任何真实研究数据；分析结果统一保存至 `outputs\<任务>_<标签>_<时间戳>\`，不会覆盖历史运行。

---

## 📦 免安装版下载（推荐给学生与测试者）

**[Releases → Psychostat v0.1.0](https://github.com/ywbjsdz/Psychostat/releases/tag/v0.1.0)** —— 下载 `Psychostat-v0.1.0.zip`（约 442 MB，**已内置 R 与 Python 运行时，无需联网安装**）。

解压出三个文件夹**一起**放到 D 盘根目录（`D:\Psychostat` + `D:\Psychostat-R` + `D:\Psychostat-Python`），双击 `启动Psychostat界面.bat` 即可；
先跑一次 `运行离线自检.bat` 验证环境。**上手前请先读包内《先读我（必读）.txt》与《免责声明（必读）.txt》**（后者写明三块尚未独立验证的区域）。
包未签名，较新 Win11 的「智能应用控制」可能拦截 `vegan.dll`，表现为 IRT 分支报错。

> 只想用源码 / 自行配置 R 环境？看下文「二、环境要求」，按源码流程运行即可。

---

## 一、这是什么

Psychostat 把心理测量与统计最常见的任务封装成"**下载即用**"的 Windows PowerShell 工具。所有统计核心运行在 R 上（统计量按 IBM SPSS 27 默认口径实现：合并方差 t、Type III 平方和、Brown-Forsythe、Friedman 秩等关键口径均有闭式值回归测试锁定；用仓库内 `tests\fixtures\spss\README.md` 的流程可继续补充真实 SPSS 输出基准），中英文 Word 结果报告由 Python 生成。

| 分支 | 覆盖内容 | 统计核心 | 教学特色 |
|---|---|---|---|
| **1. 心理统计** | 21 个方法模块：描述统计→三种 t→四类方差分析→ANCOVA→相关/偏相关→回归→两类卡方→四个非参数检验→中介/调节/功效 | R（car/emmeans/nortest/pwr 等） | 每方法=模拟数据+SPSS 菜单路径+结果解读+结果写法+常见错误；方法选择向导 |
| **2. CTT** | 量表数据清洗→项目分析→信度（α 与 McDonald's ω、α 置信区间）与效度→EFA→CFA（质量/EFA/CFA 三路线互斥） | R（psych/lavaan） | 输出三线表、300dpi 图、CFA 路径图（需可选包 semPlot，缺失时会提示安装命令）与 结果报告初稿 |
| **3. IRT** | Rasch/2PL/3PL/GRM/MIRT（探索+验证），缺失值审计、ICC/IIF/TIF、能力估计 | R（mirt） | 交互向导/静默调用双入口，中英文 Word 结果报告 |

**为什么强调"教学"**：三个分支都内置可复现的模拟数据（含生成"真值"），学生可以先看"正确答案应该长什么样"，再把自己的数据代入同一流程。**这不是临床或高风险决策工具**，请用于教学与一般研究辅助。

---

## 二、环境要求（下载即用需满足）

| 依赖 | 要求 | 缺失时的影响 |
|---|---|---|
| Windows + PowerShell | 5.1+（Win10/11 自带） | 无法运行（本工具面向 Windows） |
| **R** | 已安装 R；启动器会优先寻找 D 盘中的 R，再寻找 PATH/注册表与 C 盘 | 完全无法分析 |
| **Python**（可选） | python.exe 或 py 启动器 | 仅跳过 Word 结果报告，CSV/图/Markdown 报告不受影响；找到 Python 后会自动安装 pandas、python-docx |
| 网络（仅首次） | 自动从 CRAN 安装缺失 R 包 | 首次运行需联网 |

安装 Python 依赖（可选，仅 Word 结果报告需要）：
```powershell
pip install -r requirements.txt          # 普通使用（仅下限约束）
pip install -r requirements-lock.txt     # 精确复现/发布验证（推荐 CI 与贡献者使用）
```
R 依赖在首次运行时自动安装，**每次运行的实际版本都记录在结果目录的 `run_manifest.json` 里**（这是版本追溯的权威来源）。`renv.lock` 仅作参考快照，CI 并不按它还原，因此**不构成「已验证的精确复现路径」**；如需按锁复现请自行 `Rscript -e "install.packages('renv'); renv::restore()"`（更新方式见 `tests/update_renv_lock.R`）。

安装位置：新装的 R 请优先放到 D 盘（如 D:\R\R-x.y.z）；启动器新增的 R 包也优先写入 D 盘。只有 D 盘不可写时才回退到 C 盘。同一目录存在多个 R 版本时，按**数值版本**选取最新（如 R-4.5.10 优先于 R-4.5.9）。Python 用于生成 Word 结果报告：若机器上没有可用的 Python（≥3.9），首次运行会**询问是否自动下载并安装**独立 Python 3.12（约 25 MB，装到 D:\Python 或用户目录，无需管理员权限）；选 N 则跳过 Word 报告，CSV/图/Markdown 报告不受影响。

---

## 三、快速开始

### Windows：推荐用图形界面（分步向导，全程在窗口内操作）

双击 **`启动Psychostat界面.bat`** → 打开向导式图形界面，左边选功能、跟着步骤一步一步往下走：

**左侧**：首页总览 + 功能（心理统计 / 经典测量理论 CTT / 项目反应理论 IRT）+ 当前功能的**步骤列表**（可点击回退/前进）+ 环境检查、打开结果、AI 助手。

**心理统计（4 步）**：① 选择数据来源（内置演示 / 选方法 / 我的数据 / **方法选择向导**——回答 3~4 个问题推荐方法）→ ② 选择要运行的方法（勾选框**可多选**，如 描述统计＋相关＋回归 一次跑完；同名变量下一步只设一次）→ ③ 设置变量（选文件后**自动读取列名**，全部用下拉框/勾选框点选）→ ④ 开始分析并实时查看日志（含 SPSS 对照讲解、结果表）。

**CTT / IRT（各 2 步）**：① 选择数据与路线/模型（数据文件、EFA/CFA 路线、IRT 模型与 MIRT 模式均为点选，CFA/验证性 MIRT 会弹出对照表选择框）→ ② 确认摘要 → 开始分析。

其他要点：
- 顶部/左侧即时显示 R、Python 是否就绪；"检查环境/自动安装"在窗口内完成 R 与 Python 依赖安装
- 分析在后台运行，日志**逐行刷新**并显示已运行时长；可随时点"取消任务"
- 完成后底部状态栏显示结果目录，"打开结果文件夹 / 打开中文报告 / 回到首页"一键查看（中英文 Word 结果报告自动生成）
- 所有文件都是**选择弹窗**，所有变量名都是**下拉/勾选框**；仅当弹窗不可用时才回退为手工输入

### Windows：也可直接双击 BAT（命令行/静默/AI 调用）

- `启动心理统计.bat`：心理统计
- `启动量表编制_CTT.bat`：量表编制（CTT）
- `启动项目反应理论_IRT.bat`：项目反应理论（IRT）
- `启动AI智能体工作流.bat`：打开给 AI 助手的交接说明（`AI智能体工作流.md`，无需 API Key）

> BAT 说明：所有 BAT 均为**纯 ASCII 脚本**（不含中文字面），在任何 Windows 语言/代码页下双击都不会乱码；中文提示由启动后的 PowerShell 界面提供。启动失败（如缺少 R）时窗口会暂停显示原因；分析成功后窗口停留 8 秒（按任意键可立即关闭）以便查看结果路径。**首次在未装 R 的电脑上运行**：选择运行方式后工具会询问"是否自动下载并安装 R"——输入 Y 即从清华/官方 CRAN 镜像下载约 100 MB 安装包并静默安装到 `D:\R`（或用户目录），通常无需管理员权限（个别受企业策略限制的环境可能需要），装好后自动继续分析。

> 文件选择：数据文件、题目-维度对照表等**一律提供图形选择框**；只有在弹窗不可用（极少数受限环境）时才回退为手工输入路径。

### 平台说明

Psychostat **仅支持 Windows**（Windows 10/11 + PowerShell 5.1+）。所有 `.bat` 入口都是 Windows 专用脚本，macOS / Linux 无法运行——在 Mac 上双击 `.bat` 会被系统交给"默认打开方式"里注册了该文件类型的程序（装了某些国内 App 后常被抢注），可能弹出完全无关的软件，请 Mac 用户换用 Windows 电脑。

也可以在 Psychostat 文件夹打开 PowerShell：

```powershell
.\run_psychostat.ps1
```

按提示输入 **1（心理统计）/ 2（CTT）/ 3（IRT）**，或直接调用对应启动器：

```powershell
.\run_stats_analysis.ps1     # 心理统计：四选一菜单（推荐先跑"教学演示全流程"）
.\run_ctt_analysis.ps1       # CTT：三选一路线（质量检查 / EFA / CFA）
.\run_irt_analysis.ps1       # IRT：交互向导（选文件→计分方式→模型）
```

首次运行会自动安装所需 R 包；**国内网络下这一步可能要几十分钟**（psych/lavaan/mirt 及其依赖合计数百 MB，本机实测 R 包库约 860 MB），工具会逐包显示进度并自动换源，中途可安全中断、下次接着装。

---

## 四、用法速查

### 4.1 心理统计分支（21 个可选方法模块 + 自动执行的第 0 步数据准备）

```powershell
# 一键跑全部 21 个方法的教学演示（推荐首次体验）
.\run_stats_analysis.ps1 -Simulate

# 只跑指定方法（多个用逗号分隔），内置模拟数据
.\run_stats_analysis.ps1 -Method two_way_anova
.\run_stats_analysis.ps1 -Method independent_t,one_way_anova

# 用自己的数据（CSV/Excel/SPSS .sav）跑指定方法：按提示填写列名
.\run_stats_analysis.ps1 -Method independent_t -Data .\my_data.csv

# 使用 YAML 配置（自定义列名/α/事后比较等）
.\run_stats_analysis.ps1 -Config .\stats_config.yaml
```

21 个方法：`descriptives` 描述统计 · `normality` 正态性/方差齐性 · `one_sample_t` 单样本 t · `independent_t` 独立样本 t · `paired_t` 配对 t · `one_way_anova` 单因素方差分析 · `two_way_anova` 两因素方差分析 · `rm_anova` 重复测量方差分析 · `mixed_anova` 混合设计方差分析 · `ancova` 协方差分析 · `correlation` 相关/偏相关 · `regression` 多元回归 · `chi_square_gof` 卡方适合度 · `chi_square_independence` 卡方独立性 · `mann_whitney` Mann-Whitney U · `wilcoxon_signed` Wilcoxon 符号秩 · `kruskal_wallis` Kruskal-Wallis H · `friedman` Friedman · `mediation` 中介效应（Model 4, Bootstrap 5000）· `moderation` 调节效应（Model 1）· `power` 功效与样本量。

每个方法运行前自动做"第 0 步"（**不必勾选，也没法勾选**）：数据准备与异常值筛查（缺失值审计与处理、异常值筛查 |Z|>3 与 1.5×IQR、完整性检查），随后输出所用变量的描述统计（参数类方法附正态性检验）；每个模块的控制台引导会说明：什么时候用 → SPSS 菜单路径 → 结果怎么读 → 结果怎么写 → 常见错误。完整教学文档见 **docs\心理统计使用说明.md**（合并版见 Psychostat使用说明.docx 第一部分，打包时生成）。

### 4.2 CTT 分支（量表质量/EFA/CFA）

```powershell
.\run_ctt_analysis.ps1 -Goal efa  -Data .\my_scale.csv                     # 质量检查 + 探索性因子分析
.\run_ctt_analysis.ps1 -Goal cfa  -Data .\my_scale.csv -Mapping .\map.csv  # 验证性因子分析（需题目-维度对照表）
.\run_ctt_analysis.ps1 -Goal quality -Data .\my_scale.csv                  # 仅清洗+项目分析+信度效度
.\run_ctt_analysis.ps1 -Config .\ctt_config.yaml
```

数据要求：一个被试一行、一个题目一列的量表数据（CSV/XLSX/SAV）。EFA 与 CFA 为互斥路线（同一批数据先 EFA 再 CFA 只构成"内部验证"，不推荐），交互运行时请按菜单选择。内置模拟示例见 `ctt_config.yaml`；真实数据模板见 `examples\ctt_empirical_template.yaml` 与 `examples\ctt_cfa_mapping_template.csv`。想直接试跑，`examples\simulated_datasets\` 里有 5 组 CTT 数据：CTT-A 干净单维（入门）、CTT-B 完整问卷（三维+反向题+效标+已知组）、CTT-C 问题数据（清洗与建议删题）、CTT-D 三因子近似正交（`rotation: varimax` + 手动 `n_factors`）、CTT-E 脏作答 `remove` 与**负向效标**。完整文档见 **docs\CTT使用说明.md**（合并版见 Psychostat使用说明.docx 第二部分，打包时生成）。

### 4.3 IRT 分支（Rasch/2PL/3PL/GRM/GPCM/MIRT）

```powershell
.\run_irt_analysis.ps1 -Config .\config.yaml            # YAML 配置（默认小型 GRM 模拟示例）
.\run_irt_analysis.ps1 -Data .\responses.xlsx -m grm    # 直接指定数据与模型
.\run_irt_analysis.ps1 -Data .\responses.xlsx -Auto     # 自动推荐模型
.\run_irt_analysis.ps1                                  # 交互向导（文件选择框）
```

- 数据：一行一名被试、一列一个题目；题目须为整数计分（不要把姓名/性别/总分等非题目列纳入 IRT 项目）。
- 模型：二分类题目用 `rasch`/`2pl`（有理论依据时 `3pl`）；有序多级题目用 `grm`（Likert 量表·累积 logit）或 `gpcm`（部分计分/逐步作答·相邻 logit，Muraki 1992），多级且 N≥500 时自动推荐会双模型 BIC 比较选优；多维结构用 `mirt`（探索 EIFA / 验证 CIFA，需 `dimension_count` 或载荷对照表），并用 `mirt_item_model` 指定多维家族：`auto`（默认）｜`2pl`（M2PL，仅二分）｜`3pl`（M3PL，仅二分）｜`grm`（MGRM，仅多级）｜`gpcm`（MGPCM，仅多级）。
- **不知道选哪个模型？** 界面第 1 步点「模型选择向导」、终端交互选「向导推荐」：回答 计分类型→维度→样本量→（多级）作答方式/（二分）特殊情况，**选“多维”时再多问两问**（EIFA/CIFA 模式 + M2PL/MGRM/MGPCM/M3PL 家族），共 3–5 问即可获得带文献依据的推荐（de Ayala 2022；Dai & Chang 2021：Rasch 百级样本可稳、2PL 约 250-500 起、3PL 需 N≥1000、多级建议 ≥250-500）。GUI 采用推荐后自动回填模型下拉框与 `mirt_item_model`。
- 缺失值：`none`（缺省，交由 mirt 观测反应似然）/ `listwise`（删人，报告删除比例）/ `pairwise`（与 `none` 等价：拟合同样基于观测反应模式，仅维度启发式中的相关用成对可用个案）。整行全缺失的被试会在拟合前剔除并在缺失值审计中单列计数。每次运行输出缺失值审计三张 CSV。
- 配置模板见 `examples\`（rasch/2pl/3pl/grm/mirt 模拟 + empirical 真实模板）。完整文档见 **docs\IRT工具使用说明.md**（合并版见 Psychostat使用说明.docx 第三部分，打包时生成）。
- **想直接试跑**：`examples\simulated_datasets\` 里有 9 组 IRT 数据，其中 IRT-G（三维 GPCM/MGPCM，N=900）与 IRT-H（二分 3PL，N=1500）分别覆盖多维 GPCM 与猜测参数这两条较冷门的路径，IRT-I（二维二分/M2PL）覆盖二分多维。每组都带生成真值，可直接做参数恢复。

---

## 五、AI 智能体 / 静默模式（脚本化调用）

三个启动器都支持 **静默模式**：不弹任何交互框，只向 stdout 输出逐行 JSON 事件日志（`event: error | complete`，附 result_dir / config 等字段；IRT 启动器另会在分析前发 `preflight` 事件）；严重问题返回非零退出码。适合 AI 智能体、批处理或需要程序化调用的场景。

```powershell
# 心理统计：方法+数据写进 JSON 配置
.\run_stats_analysis.ps1 -Silent -ConfigJson .\examples\silent_stats_demo.json

# CTT：模拟演示（静默）
.\run_ctt_analysis.ps1 -Silent -ConfigJson .\examples\ctt_silent_simulation.json

# IRT：2PL+CIFA 模拟（静默）
.\run_irt_analysis.ps1 -Silent -ConfigJson .\examples\silent_mirt_2pl_cifa_simulation.json

# 手动运行时加入 -Verbose 可查看 R/Python 原始诊断（排查问题用）
```

JSON 配置格式见 `examples\` 下各 `silent_*.json`；交互式运行会生成"本次配置快照"并随结果一起保存（`config_snapshot.*`），可复制为下次调用的配置。结果目录路径通过 `complete` 事件的 `result_dir` 字段返回（UTF-8 路径已做跨进程安全编码，智能体直接使用该路径即可）。

---

## 六、输出文件说明

每个结果目录（`outputs\...`）按需包含：

| 类别 | 文件 | 说明 |
|---|---|---|
| 模拟数据 | `NN_方法_data.csv` | 教学演示的原始数据（UTF-8-BOM，可直接导入 SPSS/Excel 复现） |
| 结果表 | `NN_方法_*.csv` | SPSS 式统计表（描述/检验/事后比较/信度/EFA/CFA/项目参数等） |
| 图形 | `*.png` | 300 dpi（箱线图/直方图/交互图/路径图/ICC/IIF/TIF/碎石图/载荷热图等） |
| 教学报告 | `stats_report_zh.md`、`00_方法选择决策指南.md` | 逐步教学引导：何时用→怎么点→怎么读→怎么写结果 |
| 结果报告 | `*_report_zh.docx` / `*_report_en.docx` | 中英文 结果报告初稿（三线表 + 结果句），可作论文结果部分底稿 |
| 记录 | `config_snapshot.*`、`run_log.txt`、`run_manifest.json` | 本次配置、运行日志与机器可读运行清单（时间戳/分支/R 与包版本/种子/输入），供复现审计 |

**与 SPSS 对照**（心理统计分支）：把结果目录中的 `NN_方法_data.csv` 导入 SPSS，按各模块给出的菜单路径操作，统计量应与 `NN_方法_*.csv` 一致（t/F/χ²/H 等多数可对到小数点后 2–3 位；这是代码级口径对齐，仓库内暂无 SPSS 输出夹具，混合设计尚有已知差异，正式发表前请手工抽查）。关键对齐约定：均值中心 Levene、Type III 平方和、Mauchly+GG/HF、LSD/Tukey/Bonferroni、渐近 Z 含结点校正。对照时若遇方向/显示差异（配对方向、K-S 的 .200 上限、t 符号），见 docs\心理统计使用说明.md"对照时容易疑惑的 6 个点"。

---

## 七、项目结构

```
Psychostat/
├─ run_psychostat.ps1        总入口（任务选择菜单）
├─ run_stats_analysis.ps1    心理统计启动器   ├─ run_ctt_analysis.ps1  CTT 启动器
├─ run_irt_analysis.ps1      IRT 启动器       ├─ *_config.yaml        默认演示配置
├─ scripts/                  R 统计核心 + Python 报告生成器 + 文档/数据工具
│   ├─ stats_common.R / stats_modules.R / stats_datacheck.R /
│   │  stats_pipeline.R                                       心理统计（21 方法 + 第 0 步数据准备）
│   ├─ ctt_common.R / ctt_pipeline.R                          CTT（psych/lavaan）
│   ├─ irt_common.R / irt_generic_pipeline.R / irt_preflight.R  IRT（mirt）
│   ├─ psychostat_gui.ps1                                     图形化主界面（WinForms，零依赖）
│   ├─ generate_stats_report.py / generate_ctt_report.py /
│   │  generate_result_reports.py / merge_manuals.py          Word 结果报告与说明文档生成
│   ├─ generate_docs.py                                       Markdown → Word（完整说明书）
│   ├─ generate_simulated_datasets.R                          模拟数据集与真值生成器（可换种子重生成）
│   ├─ uninstall_psychostat.ps1                               环境清理（默认只预览；只删本工具专属目录）
│   └─ check_sensitive.ps1                                    提交前敏感数据检查（已跟踪 + 待提交）
├─ psychostat_env.ps1        共享环境预检 + 文件选择弹窗（三分支共用）
├─ examples/                 配置模板与静默调用示例（yaml/json/csv）
│   └─ simulated_datasets/   14 个可直接试跑的模拟数据集（CTT ×5 / IRT ×9）+ 生成真值 + 配置 + 使用说明
├─ docs/                     项目文档（md + Word 版）
│   ├─ 心理统计使用说明.md / CTT使用说明.md                    分支使用说明（md 为源，Word 版由生成器产出）
│   ├─ IRT工具使用说明.md                                     IRT 分支使用说明（Markdown 源，Word 版打包时生成）
│   ├─ Psychostat_完整使用说明书.md                           完整说明书源文件（含 21 个方法的统计注释）
│   └─ 待修问题清单.md                                        已知问题与改进路线（开发用；使用者请读 README 第十章）
├─ Psychostat完整使用说明书.docx  完整说明书 Word 版（根目录，可直接双击）
├─ Psychostat使用说明.docx     分支说明合并版（**打包时**由 merge_manuals.py 生成，不随仓库保存）
├─ SPSS与Psychostat心理统计模块输出对应.docx  20 个模块的逐方法 SPSS 数值对照记录（开头列明范围与已知差异）
├─ outputs/                  运行结果（自动生成；已被 .gitignore 排除，可随时清理）
├─ tests/                    冒烟自检（smoke_test.ps1）与数值回归测试（test_numeric.R）、夹具（data/、fixtures/）
├─ notes/                    内部工作笔记（已被 .gitignore 忽略，不入库）
├─ 启动Psychostat界面.bat    图形化主界面入口（推荐；窗口内点按钮用各分支）
├─ 清理Psychostat环境.bat    不用了想删干净时的入口（双击→先预览→输入 Y 才清理）
├─ 启动*.bat                分支双击入口（纯 ASCII，转发到对应启动器；AI 入口打开 AI智能体工作流.md）
├─ AI智能体工作流.md          给 AI 助手的交接说明与任务提示词（含变量字典模板）
├─ 运行离线自检.bat           一键自检（用随包 R 跑 88 条断言；免安装版使用者用）
├─ 免安装版-测试方法.md        三档验收流程（自检 / 功能抽查 / 完整验收）
└─ requirements.txt / LICENSE / README.md / CHANGELOG.md / CITATION.cff /
   CONTRIBUTING.md（开发约定、PowerShell 5.1 专项坑、补 SPSS 夹具流程）/ renv.lock（参考快照）
```

---

## 八、数据处理边界（隐私与安全）

本工具处理的是问卷/测验数据——**其中可能包含真实个人信息**。请遵守以下约定：

1. **真实数据只放 `data/`（或 `private/`、`local/`、`secrets/`）**：这些目录已被 `.gitignore` 忽略，`git status` 不会显示，不会随仓库发布。
2. **`*.sav / *.xlsx / *.xls` 全局忽略**（仅 `examples/` 下的模板与模拟示例豁免），即使放在项目根目录也不会被提交。
3. **发布前自查**：在项目根目录运行 `.\scripts\check_sensitive.ps1`——它会扫描本次将被提交的 `.sav/.xlsx/.xls/.csv` 文件（`examples/` 与 `tests/data/` 除外），发现疑似真实数据即警告并返回退出码 1。
4. **提交信息不要包含被试信息**；分析输出（`outputs/`）同样不入库。仓库内所有 `.csv` 应仅为模拟数据或配置模板。

---

## 九、常见问题

1. **提示找不到 Rscript.exe / 我的电脑没有 R** → 双击启动器后按提示输入 **Y**，工具会自动从清华/官方 CRAN 镜像下载并静默安装 R（约 100 MB，装到 `D:\R` 或用户目录，无需管理员权限，装完自动继续）；选择 N 或自动安装失败时才需手动：安装 R（r-project.org），建议安装到 `D:\R\R-x.y.z` 或 D 盘任意文件夹下的 `R-x.y.z`，D 盘不可用时再装到 C 盘。无需手动配置 PATH。
2. **Word 结果报告未生成** → 找到 Python 时会自动安装 pandas/python-docx；若仍未生成，请检查网络和 Python 安装。未安装 Python 时其余输出不受影响。
3. **首次运行装 R 包很慢/失败** → 网络问题；可切换 CRAN 镜像（国内可设清华镜像）后重试，或手动按 requirements.txt 中的注释安装。
4. **控制台中文乱码** → 工具内部已按 UTF-8 处理文件读写并主动设置输出编码；如个别终端仍乱码，先执行 `chcp 65001` 再运行。
5. **结果目录越来越多** → 每个时间戳目录是一次运行产物，可定期删除 `outputs\` 旧目录（不影响工具）。
6. **自己的数据列名含中文/特殊字符** → 支持 UTF-8 CSV/XLSX/SAV；交互式输入列名时直接粘贴列名即可。
7. **改了代码/启动器后如何确认没改坏？** → 项目根目录运行 `.\tests\smoke_test.ps1 -Full`（约 5–8 分钟：三分支模拟 + 2D CIFA-MGRM 端到端 + 数值回归黄金值对照）。快速自检用 `.\tests\smoke_test.ps1`（仅心理统计两方法）。
8. **双击 BAT 后窗口一闪而过/提示失败** → BAT 在失败时会暂停显示原因；常见原因是未安装 R（见第 1 条）或首次运行需要联网装 R 包（见第 3 条）。
9. **不用了，怎么把工具装过的东西彻底删掉？** → 三种方式，都不需要记命令：**(最省事)** 双击 `启动Psychostat界面.bat` → 左侧点 **「清理已安装环境」** → 在可滚动窗口里看清楚后点「清理上面这些目录」（或点「什么都不做」关闭）；**或** 直接双击项目根目录的 `清理Psychostat环境.bat`（输入 `Y` 清理、直接回车不清理）。它只删除本工具**专属**的目录（`Psychostat-R-Library`、`Psychostat-Python-User`、`C:\PsychostatTemp`）与安装清单；**不会**删除你已有的 R / Python 本体（你可能还在用 RStudio），不会删除共享的 R/Python 用户库，也不会删除你的 `outputs\` 与 `data\`。最后把整个项目文件夹删掉即可。详见 `docs\Psychostat_完整使用说明书.md` 第 1.5 节。
10. **同学没有 R / 网络慢 / 想完全离线用怎么办？** → 用仓库里的打包脚本做一个**免安装集成包**（工具 + 精简后的 R 运行时）：
    ```powershell
    .\notes\make_portable_release.ps1
    ```
    产出的 zip 解压到 D 盘后得到 `D:\Psychostat`（工具）与 `D:\Psychostat-R`（随包 R），
    使用者**不需要装 R、不需要联网、不需要管理员权限**。脚本只复制依赖闭包内的 R 包（比整包小得多），
    并且**会在离线状态下用副本 R 真实跑完 88 条数值回归断言**来证明剪枝没剪坏东西。
    随包还带 `运行离线自检.bat`（使用者一键自检）与 `免安装版-测试方法.md`（三档验收流程）。

10. **发给 Mac 的同学后，她双击 `.bat` 却打开了别的 App（比如某个 AI 助手）？** → `.bat` 是 Windows 专用脚本，macOS 不能执行；系统会把它交给"默认打开方式"里注册了该类型的程序（装了某些国内 App 后常被抢注），于是弹出了无关的软件。本工具**仅支持 Windows**，请 Mac 用户换用 Windows 电脑后双击 `启动Psychostat界面.bat` 使用。

---

## 十、已知限制（用之前请读）

本工具适合**课程作业、毕业论文、小论文与教学演示**。以下边界请务必知悉，**不要把它当成"零复核即可投稿"的黑箱**：

1. **定位**：面向教学与一般科研辅助，不是临床、选拔或其他高风险决策工具；不做因果推断（中介/调节只是统计意义上的）。
2. **SPSS 对照已做过逐方法的人工校验**：根目录 `SPSS与Psychostat心理统计模块输出对应.docx` 记录了 20 个模块的 Psychostat↔SPSS 数值并排对照（含 16 处「结论：一致」），多数统计量可对到小数点后 2–3 位。**第二十节（调节效应）已做到与 SPSS PROCESS 完全对齐**——修复均值中心化后，4 个系数与 4 个标准误四位小数完全相同（`constant = 30.5128 / x = .3158 (SE .0671) / w = .5825 (SE .0845) / Int_1 = −.0018`，R² = .5085，F(3,116) = 40.0019）。但请以该文件开头的「校对范围与已知差异」为准：① 未覆盖第 21 个模块（功效分析），第四节的独立样本 t 检验缺 SPSS 侧输出；② 混合设计仍有 3 处未逐位对齐（EM 边际均值 SE、被试内配对比较的误差项、Huynh-Feldt ε），前两项需第二组真实 SPSS 输出才能锁定；③ 该文件不随 CI 运行，**不能防止后续改动引入回归**——正式发表前请对关键表格再做一次手工抽查。
3. **回归测试覆盖有限**：数值回归断言只有二十余条，且多数验的是数据生成器；Type III 平方和、事后比较、球形校正、非参数 Z 等口径尚无数值断言。详见 `docs/待修问题清单.md`。
4. **自动生成的结果示范句是模板**：句子里的方向、构念名由你自行核对（工具已改为数据驱动并标注"模板"），**不要不加核对直接粘贴进论文**。
5. **缺失值**：统计分支为整例删除（listwise），不报告删除比例，也不做多重插补或 FIML。
6. **不支持**：多层线性模型、结构方程全模型、潜变量增长模型、网络分析、DIF、测量不变性、CAT。这些请用 Mplus / lavaan / 专用工具。
7. **环境**：仅 Windows 10/11 + PowerShell 5.1+；首次运行需联网安装 R 包（国内可能几十分钟）。
8. **AI / 静默模式**：静默模式**不自动安装环境**；缺 Python 时仍会报告成功但不会产出 Word 报告（`complete` 事件会带 `report_note` 说明）。

---

## 十一、English Quick Start

Psychostat bundles three Windows PowerShell tools for psychological measurement & statistics teaching (stats with SPSS-comparable output · CTT · IRT). Requirements: R (Rscript in PATH); Python optional (Word result reports). Run `.\run_psychostat.ps1`, pick 1/2/3, or call a launcher directly, e.g. `.\run_stats_analysis.ps1 -Simulate` for a full 21-method teaching demo, `.\run_stats_analysis.ps1 -Method independent_t -Data .\my.csv` for your own data, and `-Silent -ConfigJson .\examples\silent_stats_demo.json` for machine/AI-agent use. Every run writes a timestamped folder under `outputs\` with SPSS-style tables, 300-dpi figures and bilingual Word result reports; simulated datasets are exported as UTF-8-BOM CSV so results can be cross-checked in SPSS. See `docs\` for branch manuals and `docs\待修问题清单.md` for known limitations.

---

## 十二、参与贡献

想改代码或补测试？请先读 **`CONTRIBUTING.md`**。三条最关键的信息先放这里：

- **改完必须跑** `.\tests\smoke_test.ps1 -Full`（预期 `ALL CHECKS PASSED`），并在 PR 里贴出输出与你的 PowerShell / R 版本。
- **CI 跑的是 pwsh 7，你在用的可能是 PowerShell 5.1** —— 原生程序 stderr、BOM 处理等坑 CI 抓不到，请自己在本机 5.1 上验一遍。
- **加断言请加"生产代码"断言**：直接调用 `run_*` 或生产助手函数，而不是对 `simulate_*` 造的数据复算（后者把 `run_*` 改错也照样通过）。

最有价值的贡献是**补 `tests/fixtures/spss/` 的真实 SPSS 输出基准**（目前仍是空骨架），流程见 CONTRIBUTING.md 第七节。

---

## 十三、许可证与声明

本项目以 **MIT License** 发布（见 LICENSE）。工具面向**教学与一般科研辅助**，内置数据均为模拟数据；使用前请自行核对统计口径与研究设计，作者不对分析结论承担担保责任。欢迎 fork 与改进。
