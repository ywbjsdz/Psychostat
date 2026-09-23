# Psychostat：CTT 全流程使用说明

## 1. 工具是什么

Psychostat 在原有 IRT 功能之外新增了一个独立的经典测量理论（CTT）分支。它面向“一个被试一行、一个题目一列”的心理量表数据，依次执行数据清洗、项目分析、信度与外部效度、EFA、CFA，并输出 结果报告风格三线表、300 dpi 图和 Word 初稿。它是量表修订的可复现工作流，不替代研究者的理论判断或内容效度评估。

依赖 R：`psych`、`lavaan`、`CTT`、`GPArotation`、`ggplot2`、`readxl`、`haven`、`yaml`、`jsonlite`、`MASS`；CFA 路径图额外使用可选的 `semPlot`。首次运行会检查并安装缺失包。报告生成使用 Python 的 `pandas` 与 `python-docx`。

## 1b. 三条分析路线（与 IRT 的探索/验证选择一致）

同一份数据**不建议**既做 EFA 又做 CFA：用 EFA 找到的结构再拿同一批被试做 CFA 只是"内部验证"，不构成真正的验证性证据。因此工具把分析拆成三条互斥路线，交互式运行时会在菜单中让你选择（`analysis.goal`）：

| 路线 | 内容 | 什么时候用 |
|---|---|---|
| `quality` 量表质量检查 | 清洗 + 项目分析 + 信度（总量表 α、删题 α）+ 校标/已知组效度 | 只要评价量表质量，不做因子分析 |
| `efa` 质量 + EFA | 在质量检查基础上做探索性因子分析（KMO/Bartlett 前提、循环删题、旋转、方差解释） | 还没有预设结构，想数据驱动地找结构 |
| `cfa` 质量 + CFA | 在质量检查基础上验证你**预先指定**的结构（拟合指标、标准化载荷、CR/AVE、区分效度） | 已有理论结构或前人 EFA 结果（独立样本），需提供**题目-维度对照表** |

CFA 路线必须提供题目-维度对照表（`analysis.cfa_mapping`：含 `item,dimension` 两列的 CSV/Excel，每题只归属一个维度；模板 `examples\ctt_cfa_mapping_template.csv`）。题目集合以对照表为准，避免注意力题等混入。模拟演示模式下 CFA 自动使用模拟数据的真实结构。旧配置 `cfa_source: efa`（同数据 EFA→CFA 连跑）已废弃：会自动按 EFA 路线执行并在日志中说明。

统计核心包（权威发布版本）：`psych`（项目分析/信度/EFA）与 `lavaan`（CFA，有序题采用 WLSMV 估计）；版本号写入每次运行的 `run_log.txt`。

快捷命令（不再逐项提问，未指定项用默认值）：

```powershell
.un_ctt_analysis.ps1 -Goal efa  -Data .\my_scale.csv
.un_ctt_analysis.ps1 -Goal cfa -Data .\my_scale.csv -Mapping .\my_mapping.csv
.un_ctt_analysis.ps1 -Goal quality -Data .\my_scale.csv
```

## 2. 最快的模拟示例

在 `Psychostat` 文件夹空白处右键打开 PowerShell，运行：

```powershell
.\run_ctt_analysis.ps1 -Config .\ctt_config.yaml
```

该例子生成 480 名被试、15 个五级题、3 个相关因子的模拟问卷；包括反向题、少量缺失、注意力题、作答时间、校标与已知组。结果保存至 `outputs\ctt_simulation_ctt_时间戳\`。预期会看到：`01_cleaning_summary.csv`、`02_item_analysis.csv`、`03_reliability.csv`、`04_efa_rotated_loadings.csv`、`05_cfa_fit.csv`（未跳过 CFA 时）和 `ctt_report_zh.docx`。

也可直接运行：

```powershell
.\run_psychostat.ps1
```

然后输入 `2` 选择 CTT；选择模拟数据即可体验完整流程。输入 `1` 则仍是原有 IRT 工具。

## 3. 用自己的数据

支持 CSV、Excel（`.xlsx`/`.xls`）与 SPSS（`.sav`）。数据应为一行一个被试、一列一个题目；ID、性别、总分、校标、分组、作答时间和注意力题不应混入项目列。复制 `examples\ctt_empirical_template.yaml`，至少填写：

```yaml
input:
  mode: file
  path: "C:/Users/YourName/Desktop/my_questionnaire.xlsx"
  id_column: ID
  item_columns: auto
cleaning:
  scale_maximum: 5
  reverse_items: [Q3, Q8]
analysis:
  rotation: promax
  cfa_source: efa
```

再运行：

```powershell
.\run_ctt_analysis.ps1 -Config .\my_ctt.yaml
```

交互方式无需写 YAML：

```powershell
.\run_ctt_analysis.ps1
```

它会询问数据文件、最高分、反向题、校标、已知组和旋转方式。高级设置（注意力题、作答时间、缺失中间区间、CFA 映射）请使用配置文件。

## 4. 六阶段规则与可解释参数

| 阶段 | 工具规则 | 如何解释 |
|---|---|---|
| 数据清洗 | 个体缺失 `<5%` 中位数插补；`>20%` 剔除；5%–20% 必须配置 `stop/listwise/median_impute` | 先判断缺失机制；不要把工具默认当成缺失机制证据。 |
| 反向题 | `k + 1 − 原始值` | `scale_maximum` 是最高分 k，反向题列必须只填正式题目。 |
| 注意力/质量 | 陷阱题错误、低于最低作答时间者自动排除；直线作答和极端总分默认标记 | 标记不是自动作弊结论；需结合问卷情境复核。 |
| 项目分析 | 前/后 27% 极端组；`CR>3 且 p<.05`；`CITC>.30` | 仅当 CR 与 CITC 同时达标时给出“保留”建议。 |
| 信度 | 总量表及因子 α；`α>.70` 可接受；删题后 α 增加 `>.05` 提示删题 | α 受题目数与单维性影响，不能单独证明量表质量。 |
| EFA | `KMO>.60`、Bartlett `p<.05`；特征值>1+碎石图；累计方差>50% | 还要看理论可解释性，不只看特征值。 |
| EFA 删题 | 主载荷 `<.40`；跨载荷 `>.30` 且差值 `<.20`；共同度 `<.20`；因子少于 3 题 | 见 `04_efa_deletion_history.csv`；删除前须保留内容覆盖。 |
| CFA | χ²/df<5；CFI/TLI>.90；RMSEA/SRMR<.08 | 拟合是综合证据，不应只报告单一指标。 |
| 聚合/区分效度 | 载荷>.50、CR>.70、AVE>.50；因子相关<.85；√AVE>因子相关 | CFA 的 CR 与 AVE 不等同于 Cronbach’s α。 |

校标效度需要填写 `criterion_column` 和预期方向 `positive/negative`；已知组效度需要 `known_group_column`，两组用 Welch t 检验，三组及以上用单因素 ANOVA，同时报告 Cohen’s d 或 η²。

## 5. CFA 结构来源

`cfa_source: efa` 会以最终 EFA 的主载荷归属生成一个候选 CFA 简单结构。这样在同一样本中得到的 CFA **仅是探索性内部验证**；用于论文的严格验证应在独立样本、拆分样本，或基于预先指定的理论模型完成。

若已有理论结构，将 `cfa_source` 设为 `file`，并填 `cfa_mapping`：文件需有 `item,dimension` 两列；每题只能出现一次，且每个因子至少 3 题。模板见 `examples\ctt_cfa_mapping_template.csv`。

## 6. 结果文件

- `01_*`：清洗汇总、每名被试审计记录、清洗后的项目数据。
- `02_item_analysis.csv`：低/高组均值、CR(t)、df、p、CITC 和保留建议。
- `03_*`：α、删题后 α、校标关联、已知组效度。
- `04_*`：KMO/Bartlett、删题历史、旋转载荷、方差解释、题目-因子归属、碎石图和载荷热图。
- `05_*`：CFA 模型语法、拟合指标、载荷及 p 值、CR/AVE、Fornell–Larcker 表与区分效度。
- `ctt_report_zh.docx`：可编辑 结果报告初稿；表格为三线表，图均为 300 dpi PNG。
- `config_snapshot.*` 与 `run_log.txt`：可追溯性记录（配置、软件版本和图形生成状态）。

## 7. 常见问题

| 问题 | 原因与处理 |
|---|---|
| `compiler 命名空间不可用` | R 核心安装已损坏，和数据无关。重新安装 R 到官方默认位置，重开 PowerShell 后再运行。 |
| 找不到文件/中文路径失败 | 使用完整路径并用英文双引号包住；本工具以 UTF-8 传递路径。确认扩展名真实为 CSV/XLSX/XLS/SAV。 |
| 5%–20% 缺失停止 | 这是刻意的保护。检查缺失机制后在 `cleaning.missing_5_to_20` 明确选 `listwise` 或 `median_impute`。 |
| KMO/Bartlett 未通过 | 题目相关性不足、样本过小或含无效题。不要强行做 EFA；先检查题目和构念。 |
| CFA 未收敛 | 检查每因子至少 3 题、因子相关是否≥.85、样本量、异常数据和理论模型。可先简化模型。 |
| 没有路径图 | 可选包 `semPlot` 未安装；统计表与报告仍会生成。安装后重跑即可。 |

## 8. R 函数接口（供进阶用户）

`scripts/ctt_pipeline.R` 暴露以下函数：`clean_ctt_data()`、`run_item_analysis()`、`run_reliability_validity()`、`run_efa_iterative()`、`run_cfa()` 与 `run_ctt_pipeline()`；读取和模拟函数位于 `scripts/ctt_common.R`：`read_ctt_data()`、`prepare_ctt_items()`、`simulate_ctt_data()`。它们由启动器统一调用，初学者无需手动运行。

```r
source("scripts/ctt_common.R")
source("scripts/ctt_pipeline.R")
# 直接按 YAML/JSON 配置运行全流程
run_ctt_pipeline(c("--config", "ctt_config.yaml"))
```

## 9. 透明性与局限

工具自动执行预先写明的阈值、保存删题历史和配置快照；但题目列、反向题、最高分、注意力规则、缺失中间区间、因子旋转、CFA 来源、校标方向和已知组均由用户设定。自动建议不是最终删题决定。工具不适用于名义分类题、非量表型数据、极小样本、复杂多层数据、纵向测量不变性、DIF/IRT 或没有足够理论依据的确认性结论。

### 9.1 独立验证状态（2026-09-18）

本分支输出经过三层复核（闭式复算 / 真值恢复 / 独立实现对照）与两轮外部模型实跑复核，**未发现已证实的数值错误**：α、CITC、CR 决断值、KMO、Bartlett、EFA 表一致性、CFA 的 CR 与 AVE、ω、α 的 Feldt 精确区间均可由教科书公式复算；清洗链路（反向计分、注意检验、作答过快、直线作答、极端值、缺失处理）已逐行独立复现（5 个数据集、0 处不一致）；CFA 标准化载荷对生成真值的恢复 *r* = .872（RMSE = .032）。

**一项已知缺口**：**有序题的 CFA 目前没有独立实现对照**。lavaan 的 WLSMV 在本机没有等价的第二实现——`OpenMx` 的 `mxFitFunctionWLS` 只提供 `WLS/DWLS/ULS`（已核对函数签名），没有 WLSMV 的均值/方差修正；`semTools` 是 lavaan 的插件，不构成独立引擎。因此 CFA 的证据是"闭式复算 + 真值恢复"两类，不含第三类。若审稿人明确要求独立实现对照，请改走"两侧同为连续 ML"的口径（题目唯一取值 > 10 时工具即用 ML）。

明细见 `docs/CTT与IRT校对记录.md`。

