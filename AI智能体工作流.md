# Psychostat AI 智能体工作流

此文件是给 ChatGPT、Codex、Claude Code 或学校已部署 AI 助手的交接模板；它不需要也不会保存 API Key。

**先判断你的智能体是哪一种，两种模式的数据流向和提示词完全不同：**

| 模式 | 你的智能体 | 数据是否离开本机 | 它能做什么 | 用哪份提示词 |
|---|---|---|---|---|
| **A 本地可执行** | Codex、Claude Code、能在你电脑上跑命令的助手 | **不出本机**（推荐） | 自己写配置 → 跑 Psychostat → 读产物 → 写出结果报告 | 提示词 A |
| **B 只能对话** | 网页版 ChatGPT / Claude / 校内问答助手 | 需上传（先按下方隐私底线脱敏） | 给配置和命令，你运行、把产物贴回去，它写报告 | 提示词 B |

## ⚠️ 先读：把数据交给外部 AI 之前的隐私底线

Psychostat 自身不联网、不调用任何大模型、不保存 API Key；但模式 B 会让你**把数据上传给外部 AI**，那一步数据就离开了你的电脑。模式 A 不需要上传任何数据。无论哪种模式都请：

1. **先删除直接标识列**：姓名、学号、身份证号、手机号、邮箱、住址、IP、时间戳中的定位信息等；
2. **能不用原始逐人数据就不用**：能给出汇总统计（N、均值、标准差、信度、检验统计量）就先给汇总；
3. 编号列若必须保留，请**替换为随机编号**（并另存一份对照表留在本地）；
4. 上传前自问一句：**这份文件如果被公开，被试会不会被认出来？**
5. 学校/单位有数据合规要求或伦理审批约束时，以那些要求为准。

> 一句话：**AI 可以帮你选方法、读输出、审文字，但别把能认出人的数据交给它。**

## 使用方法

**模式 A（本地可执行智能体，能做到"直接出结果报告"）**

1. 双击 `启动AI智能体工作流.bat` 打开本文件（或直接把本文件路径给智能体，让它自己读）。
2. 把数据文件路径和本文件一起交给它，复制下方的**提示词 A**（填好开头的三行）。
3. 它需要先跑一次 `第 1 步 确认设计` 等你点头，然后自己完成配置、运行、读产物、写报告。

**模式 B（只能对话的 AI）**

1. 按上面的隐私底线脱敏后，上传数据（或只上传变量字典与汇总统计）与本文件。
2. 复制下方的**提示词 B**，并告诉它你的研究问题。
3. 它给出配置与命令 → 你在 Psychostat 里运行 → 把指定文件内容贴回给它 → 它写报告。

## 智能体执行契约（模式 A 必读；所有字段照抄，别猜）

### 唯一入口（不要用 GUI、不要模拟点菜单）

```powershell
cd D:\Psychostat
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Psychostat\run_stats_analysis.ps1 -Silent -ConfigJson <你的配置文件.json>
```

- `-Silent` 必须配 `-ConfigJson <json 文件>`（或 `-Config <yaml 文件>`）；缺了会直接报错退出。
- 退出码 0 = 成功，非 0 = 失败。**每行输出一个 JSON 事件**，最后一行形如：

  ```json
  {"event":"complete","timestamp":"...","data":{"result_dir":"D:\\Psychostat\\outputs\\我的研究_stats_20260922_193811","config":"...","html_report":"stats_report_zh.html","report_note":"..."}}
  ```

  用 `data.result_dir` 定位结果目录，**不要靠猜目录名**。失败时是 `{"event":"error",...,"data":{"message":"..."}}`，把 `message` 原样报告，不要改成别的方法重试。
- **部分方法失败时整次运行仍可能报 `complete`**（样本能跑出结果目录与部分报告）。所以每次都要读结果目录里的 `run_log.txt`，核对 `Methods:` 与 `Failed methods:` 两行——**只要有方法没跑出来，就必须在报告里写明是哪个、为什么，不能当成跑成功。**
- 三分支入口同理：`run_ctt_analysis.ps1`、`run_irt_analysis.ps1`。本契约只覆盖心理统计分支。

### JSON 配置最小形状（照抄字段名；现成模板见 `examples\silent_stats_demo.json`）

```json
{
  "method": ["datacheck", "correlation"],
  "input": { "mode": "file", "path": "D:/我的研究/data.csv" },
  "variables": { "columns": ["焦虑总分", "睡眠质量", "前测分数"] },
  "datacheck": { "missing_action": "report", "outlier_action": "report", "z_cutoff": 3 },
  "analysis": { "alpha": 0.05, "posthoc": ["lsd","tukey","bonferroni"], "correlation_method": "both" },
  "output": { "directory": "outputs", "project_label": "my_study", "report_language": "zh" }
}
```

- `input.mode`：`file`（用我的数据）或 `simulate`（跑内置演示，不需要数据）。
- `datacheck` 默认只报告不改数据：`missing_action` = `report`/`mean_impute`/`listwise`，`outlier_action` = `report`/`remove_by_z`。**没我的明确要求就一律用 `report`。**
- 中文列名可以直接写，文件用 UTF-8 保存即可。

### 方法 id 与必填列键（`variables` 里必须显式填全，留空会退回演示数据的默认列名）

| 方法 id | 中文 | `variables` 必填键 | 备注 |
|---|---|---|---|
| `descriptives` | 描述统计 | `columns`（可空=全部数值列） | |
| `normality` | 正态性与方差齐性 | `columns` | |
| `one_sample_t` | 单样本 t | `dv` + `mu`（检验值，如常模 50） | |
| `independent_t` | 独立样本 t | `dv`, `group`（恰好 2 水平） | |
| `paired_t` | 配对样本 t | `dv1`, `dv2` | |
| `one_way_anova` | 单因素 ANOVA | `dv`, `group`（≥3 水平） | 事后比较默认 LSD/Tukey/Bonferroni |
| `two_way_anova` | 两因素 ANOVA | `dv`, `factor_a`, `factor_b` | 含交互与简单效应 |
| `rm_anova` | 重复测量 ANOVA | `within`（时间点列数组，**按时间顺序**） | |
| `mixed_anova` | 混合设计 ANOVA | `within`, `between`；`id` 可选 | |
| `ancova` | 协方差分析 | `dv`, `group`, `covariate` | |
| `correlation` | 相关（含偏相关） | `columns`（≥2 列） | 偏相关另见下方陷阱 |
| `regression` | 多元线性回归 | `dv`, `predictors` | 分层与增量见陷阱 |
| `chi_square_gof` | 卡方适合度 | `category`（+ `gof_expected_probs`） | |
| `chi_square_independence` | 卡方独立性 | `row_var`, `col_var` | |
| `mann_whitney` | Mann-Whitney U | `dv`, `group` | |
| `wilcoxon_signed` | Wilcoxon 符号秩 | `dv1`, `dv2` | |
| `kruskal_wallis` | Kruskal-Wallis H | `dv`, `group` | |
| `friedman` | Friedman | `within` | |
| `mediation` | 中介效应 | `x`, `m`, `y` | Bootstrap 5000 |
| `moderation` | 调节效应 | `interaction_x`, `interaction_z`, `interaction_dv` | **不是 `x`/`z`/`dv`** |
| `power` | 功效与样本量 | 不需要数据 | 开题算样本量 |

### 五个陷阱（踩了会得到看起来正常、其实错的输出）

1. **列键留空的静默回退**：`dv`/`group` 等键为空时，工具会去找演示数据的默认列名（`score`、`group`、`anxiety`、`pretest`…）；如果你的数据里恰好有同名列，会被**静默采用**。所以每个键都要显式写全。
2. **写错列名会被拒绝，不会静默丢列**：静默模式下只给一句友好提示（「变量列名配置有误…」）；**要看到工具列出的「可用列：…」全清单，需在命令末尾加 `-Verbose`**，原始报错在 JSON 的 `data.raw_error` 里。看到这个错就去核对表头（注意全半角与空格）。
3. **偏相关**：只有显式给出 `variables.partial_control`（控制变量数组，可配 `partial_x`/`partial_y` 指定要看哪两个变量的偏相关）时才会计算并输出 `*_partial_correlation.csv`；不给就跳过。**没有控制变量就不要写这个键。**
4. **分层回归的两个键是"二选一"，不要同时给**（实测：同时给时工具只走 blocks 那条路）：
   - 按 SPSS 的"块"分块进入、看每块的 ΔR² 与 F 变更 → `variables.blocks` = 数组的数组，按进入顺序，如 `[["前测"],["前测","正念得分"]]`，**块里的每个变量必须也写进 `predictors`**（否则报错）；产出 `*_hierarchical_blocks.csv`、`*_hierarchical_coefficients.csv`。
   - 按 `predictors` 的书写顺序逐个变量加入做增量检验 → `analysis.incremental = true`（`predictors` ≥ 2 个才有表）；产出 `*_hierarchical.csv`。
   - 两个都不给就只出常规回归表。**没明确要求就不要加。**
5. **`moderation` 的列键是 `interaction_*`**，`mediation` 的才是 `x`/`m`/`y`，两者不能混用。

### 产物清单（每次运行新建一个结果目录）

| 文件 | 是什么 |
|---|---|
| `00_prep_*.csv` / `00_prep_boxplots.png` | 第 0 步数据准备：缺失审计、逐例缺失、异常值、整例删除影响、箱线图 |
| `00_方法选择决策指南.md` | 本次方法选择与前提的说明 |
| `NN_<方法id>_<表名>.csv` | 每张统计表一个文件（NN 为执行顺序，如 `02_correlation_correlations.csv`） |
| `NN_<方法id>_data.csv` | 部分模块导出，供导入 SPSS 逐数值复现 |
| `stats_report_zh.md` | 教学报告：**每张表都写明「（SPSS: …）→ 对应 CSV 文件名」**，是 SPSS 对照的权威依据 |
| `stats_report_zh.html` / `stats_report_zh.docx` / `stats_report_en.docx` | 网页版 / 中文 Word / 英文 Word 报告 |
| `run_manifest.json` | R 与各 R 包版本、随机种子、输入路径（**含本机路径，不要抄进对外报告**） |
| `config_snapshot.json` / `run_log.txt` | 本次实际配置与运行日志 |

## 变量字典（建议与数据一起提供，可复制填写）

> 作用：让 AI 准确知道每一列的"角色"，避免臆测列名。请把下表复制进给 AI 的消息，按你的数据填写（列名必须与 CSV 表头**逐字一致**，注意全半角空格）。

| 列名（与 CSV 表头一致） | 类型 | 取值范围/示例 | 角色 | 备注 |
|---|---|---|---|---|
| 例如：anxiety_total | 连续 | 20–80 | 因变量 | 量表总分 |
| 例如：group | 分类 | 1=训练组, 2=对照组 | 自变量/组别 | 2 组独立 |
| 例如：pre_score | 连续 | 0–100 | 前测/协变量 | |
| 例如：gender | 分类 | 1=男, 2=女 | 描述用 | 不做分析列 |

填写要点：① 每个"角色"（因变量/自变量/协变量/被试编号）只能有一个主列，如有多个请在备注说明；② 非题目列（姓名、学号、时间戳）请明确标注"不分析"；③ 反向计分题请注明题号与最高分。

## 任务提示词 A：本地可执行智能体（直接出结果报告）

```text
【先把下面三行填好，其余交给它】
数据文件（完整路径）：D:\我的研究\data.csv
研究问题（一句话）：【例如：正念训练能否降低考试焦虑；控制前测后效应是否仍然成立】
我要的分析（按需删减）：【例如：描述统计 + 相关 + 层次回归（第一块：前测；第二块：正念得分）】

你是 Psychostat 的心理统计执行助理。你的任务不是给我建议，而是**直接跑出分析并写出一份结果报告**。
环境：Psychostat v0.1.0 免安装版在 D:\Psychostat（统计入口 run_stats_analysis.ps1，R 与 Python 运行时已随包，无需联网）。
入口命令、JSON 配置字段、方法 id 与列键、产物清单，见本文档「智能体执行契约」一节，字段名一律照抄。

硬约束（违反任意一条即视为任务失败）：
1. 不得修改、增删、重排我的数据文件（包括把缺失值改成均值或删除个案）——除非我明确要求，且必须在报告中写明改了什么、影响多少例。
2. 不得臆测列名：每个方法所需的列键都必须写成数据表头里的逐字列名；不确定就问我，宁可停下。
3. 不得编造或"顺推"任何数字：报告中每个统计量都必须来自结果目录里的 CSV 文件；CSV 里没有的量，写"该量本次工具未输出"。
4. 不得改动 Psychostat 的源码、算法与配置默认值；不得为了跑通而删方法、删变量、改阈值、换数据。
5. 不得用 GUI 或模拟点菜单：只用 run_stats_analysis.ps1 -Silent -ConfigJson 运行；不得直接调用其内部 R 脚本绕过流程。
6. 数据不离开本机：不要把我的数据、结果目录里的含逐人数据的文件（如 00_prep_missing_cases.csv）上传到任何在线服务。
7. 不要重复造轮子：`stats_report_zh.md` 里每张表都标了对应的 SPSS 操作与 CSV 文件名，SPSS 对照以它为准。

执行顺序：
第 1 步（先只做这一步，等我确认后再继续）用简明中文列出：研究问题、因变量、自变量、被试内/被试间设计、控制变量、
是否需要层次回归及其进入顺序、每个变量的数据结构（连续/分类/二分/等级/计数）与取值检查结果。
若数据缺少任一必需列、样本量对所选方法明显不足、或某前提无法检验，**停下来问我**，不要自己换方法、不要自己插补。

第 2 步 写配置：在 D:\Psychostat\ 下生成 agent_config_<日期>.json（字段见执行契约；不要写到 notes\ 之类的内部目录，那里不随包分发）；
variables 里每个必需键都填满，不留空；datacheck 用 report；output.directory 保持 outputs，
project_label 用能认出我这个研究的英文短名（如 mindfulness_anxiety）。

第 3 步 运行：
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Psychostat\run_stats_analysis.ps1 -Silent -ConfigJson <上一步的 json 路径>
解析最后一行 JSON 事件，取 data.result_dir 作为结果目录。若 event=error，把 message 原文贴给我并停止。

第 4 步 读产物：先读 run_log.txt 核对 Methods 与 Failed methods（有失败的方法要单独说明）；
再按产物清单逐个读结果目录下的 CSV（不要靠文件名猜内容），确认关键文件齐全；
先读 stats_report_zh.md 建立"表 ↔ CSV ↔ SPSS 操作"的对应关系。

第 5 步 写报告：在结果目录下新建 agent_report.md，必须包含这 9 节：
 ① 设计与变量：每个变量的列名、角色、结构、取值与 N；
 ② 方法与列映射：方法 id + 每个列键对应的列名 + 为什么选它（依据设计，不是依据结果好不好）；
 ③ 数据准备：N、缺失情况、异常值、整例删除影响——照抄 00_prep_*.csv 的实际数字；
 ④ 核心结果：每张表的数值从 CSV 逐字抄写（保留原始小数位与 p 值写法，如 p = 1.68e-11 写成 p < .001 并注明原始值）；
 ⑤ APA 结果句：每个统计量都给自由度、p、效应量（t/F/χ²/H/U/r/R²/η²p 等按各自规范）；
 ⑥ 前提检验结论：正态性、方差齐性、球形性、共线性等，依据工具产出的表（含工具给的警告句）；
 ⑦ SPSS 对照表：三列——统计量 | Psychostat 数值（来自哪个 CSV）| 对应 SPSS 操作与表格（取自 stats_report_zh.md）；
 ⑧ 工具给出的警告与我需要人工判断的地方（含未验证区域，见下）；
 ⑨ 复现信息：run_manifest.json 里的 R 版本与 R 包版本、随机种子、配置文件路径（**不要**把含我电脑用户名的 input_path 抄进去）。

第 6 步 收尾：告诉我 agent_report.md 的路径、结果目录里每个关键文件是干什么的、以及任何你没把握而需要我复核的点。

偏相关：只有我明确给出控制变量时才写 variables.partial_control（工具本身也只在显式给出时才计算，不给就跳过）。
层次回归（两个键二选一，都要我明确要求才加）：要按 SPSS 的"块"分块进入 → variables.blocks（数组的数组，按进入顺序，
块内变量必须也在 predictors 里）；要按 predictors 顺序逐个变量做增量检验 → analysis.incremental = true。
两个都不给就只出常规回归表；两个都给我也没要求时，不要自己决定用哪个。

已知边界（这些地方不许替工具打包票）：3 维以上 MGPCM、有序 CFA 的 L3、以及 M2*/df/TLI/CFI 三件套尚未独立验证；
3PL 的猜测参数 c 属弱识别，逐题排序不可解读；EIFA 的 θ 不可与 CFA 因子分直接比较；
分散缺失下 listwise 可能删掉大部分样本；工具仅支持 Windows，未签名，可能被智能应用控制/杀软拦截。
```

## 任务提示词 B：只能对话的 AI（我给配置、你运行、你贴回产物）

```text
【先填好】
研究问题（一句话）：【…】
我会上传：数据文件（已按隐私要求脱敏）+ 变量字典 + Psychostat 的《AI智能体工作流.md》
我能运行命令的方式：【例如：能打开 D:\Psychostat，能执行 PowerShell】

你是 Psychostat 的心理统计执行助理。你自己无法读我硬盘上的文件，也不能执行命令，所以按"你出方案 → 我运行 → 你写报告"闭环工作。

硬约束：
1. 不得臆测列名：所有列名只能用我提供的变量字典/表头里的逐字名称，缺哪个就问我。
2. 不得编造数字：报告里的每个统计量都必须来自我贴回的 CSV 内容；我没有贴的量，就写"我未提供该文件"。
3. 不得建议我改数据、删个案、改阈值或改 Psychostat 源码；我上传的数据不含直接标识列，你也不要让我补充姓名/学号。
4. 只用《AI智能体工作流.md》里的 run_stats_analysis.ps1 -Silent -ConfigJson 方式，不要教我点 GUI 菜单。

第 1 步（只做这一步，等我回答后再继续）用简明中文确认：研究问题、因变量、自变量、被试内/被试间、控制变量、
是否需要层次回归与进入顺序、每个变量的结构与取值。有缺失信息就问我，不要自己假设。
第 2 步 给出三样东西：
 ① 完整可保存的 JSON 配置（字段照抄《AI智能体工作流.md》的执行契约；variables 每个必需键填满，datacheck 用 report）；
 ② 我要运行的确切命令行（含 -Silent -ConfigJson 与文件路径）；
 ③ **我要贴回给你的文件清单**（逐条写明文件名与为什么需要它，例如 00_prep_missing_audit.csv、02_regression_coefficients.csv、stats_report_zh.md 里的表标题）。
   提醒我：贴回前请删掉 run_manifest.json 里的本机路径，缺失个案文件 00_prep_missing_cases.csv 不必贴。
第 3 步 等我贴回产物后写报告（用 Markdown 给我），必须含：设计与变量、方法与列映射及理由、数据准备（N/缺失/异常，照抄数字）、
每张表的数值（逐字抄我贴的内容）、APA 结果句（含 df、p、效应量）、前提检验结论、
SPSS 对照表（统计量 | Psychostat 数值 | 对应 SPSS 操作与表格）、工具警告与我需人工判断之处、以及你没把握的地方。
第 4 步 明确告诉我哪些结论需要我复核，以及下一步该补跑什么（如果有）。

偏相关：只有我明确给出控制变量时才用 variables.partial_control；层次回归两个键二选一（分块用 variables.blocks，
逐个增量用 analysis.incremental = true），只有我明确要求时才加，不要自己决定用哪个。
```
