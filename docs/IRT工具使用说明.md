# IRT 工具使用说明

适用于首次使用者｜R mirt 驱动的 Rasch、2PL、3PL、GRM 与 MIRT 自动化分析

本说明对应 Psychostat 的 IRT 分支（项目根目录下的 run_irt_analysis.ps1 与 scripts/irt_*.R）。工具支持交互式向导、快捷命令与静默 JSON 调用；每一次分析都会输出带时间戳的结果目录、参数表、图形和中英文 Word 结果报告。

## 目录

- 0. 工具介绍、适用范围与局限
-   局限与不适用情形
-   0.1 版本信息与更新计划
- 1. 开始前准备
- 2. 安装 R 与依赖包
- 3. 三种运行方式
-   3.1 交互式向导
-   3.2 快捷命令
-   3.3 静默模式（AI 或批处理）
- 4. 支持的数据与模型
-   4.1 几条实测经验（拿本仓库的模拟数据跑出来的）
- 5. 数据体检与错误提示
- 6. 输出结果说明
-   6.1 透明性与可追溯性说明
-   6.2 结果阅读：各参数怎么理解
-     6.2.1 先看模型拟合与比较
-     6.2.2 再看项目参数
-     6.2.3 MIRT 的载荷和维度关系
-     6.2.4 项目拟合、θ 与标准误
-     6.2.5 图形如何使用
- 7. 完整示例：从 Excel 到报告
-   7.1 验证性 MIRT（CIFA）示例
-   7.2 示例数据：二维二分类 MIRT-2PL
- 8. 常见问题与解决方法
-   8.1 常见问题补充
- 9. 算法、可靠性与参考文献
- 10. AI工具使用说明

## 0. 工具介绍、适用范围与局限

本工具是一个面向心理学研究的、以 R 语言 mirt 包为计算后端的 IRT 自动分析工作流。它把数据读取、数据体检、模型拟合、项目诊断、能力估计、图形输出与中英文 Word 结果报告连接为同一流程；它不是替代研究者判断的“自动选题”或“自动得结论”系统。

适用场景：二分题或有序多级题的量表开发与修订、教育/心理测验项目分析、比较 Rasch/1PL、2PL、3PL、GRM，以及有明确或待探索维度结构时的 MIRT（EIFA/CIFA）分析。推荐的数据结构为“每行一名被试、每列一个题目”。

主要依赖：R 包 yaml、jsonlite、mirt、psych、ggplot2、readxl、haven；Word 报告还使用 Python 的 pandas 与 python-docx。启动器会自动检测并安装缺失的 R 包；Python 不可用时仍会保留 CSV、PNG、Markdown 与模型对象。

主要输出：数据体检与缺失摘要、模型比较（含 AIC/BIC/SABIC、M2、RMSEA、SRMSR、TLI、CFI）、项目参数与项目拟合、MIRT 载荷/相关、MAP θ 与标准误、ICC/IIF/TIF（300 dpi PNG）、配置快照、运行清单、RDS 模型对象以及中英文 Word 报告。

### 局限与不适用情形

本工具不适用于连续反应、无序名义多分类、复杂多层/纵向/增长模型、计算机自适应测验的在线施测、testlet 或明显局部依赖结构、复杂抽样权重与非随机缺失机制的自动化推断。样本很小、维度很多、类别极度稀疏、模型不收敛或理论结构尚不清楚时，不能将自动推荐或单一拟合指标作为最终结论；应由具备心理测量知识的研究者复核。

### 0.1 版本信息与更新计划

当前版本：v0.1.0（公开预览版）｜最后更新：2026-09-17。

本版新增或确认了：**模型选择向导（3–5 问；选"多维"时会追问 EIFA/CIFA 模式与 M2PL / MGRM / MGPCM / M3PL 家族）**、
快捷命令、静默 JSON 调用、前置数据体检、中文错误提示、自动选模的 BIC 理由、EIFA/CIFA 区分、
GRM 与 **GPCM**、多维 GRM/GPCM 与多维二分类 2PL/3PL 支持，以及可复核的中英文结果报告。

> 本说明书自本版起改为 **Markdown 源文件**（`docs/IRT工具使用说明.md`）纳入版本管理，
> Word 版在打包时由 `scripts/merge_manuals.py` 生成。

后续计划：提供可配置积分与估计设置、局部依赖与 DIF 诊断、等值性/跨组比较、更多报告模板，以及更细化的收敛与敏感性诊断。更新计划不代表这些功能已在本版实现。

## 1. 开始前准备

请准备一个 CSV、Excel 或 SPSS 数据文件。推荐的数据结构为“每行一名被试、每列一个题目”。题目必须是整数计分，例如二分题的 0/1，或 Likert 题的 1–5。建议在分析版数据中仅保留被试编号列和题目列（如Participant_ID、Q1–Q20），不要将姓名、文本回答、总分、年龄、性别、分组变量、小数分、日期等内容作为 IRT 项目

## 2. 安装 R 与依赖包

先安装 R（Windows 用户可从 CRAN 的 Windows 页面下载）。安装完成后，重新打开 PowerShell。工具会自动检查并安装 yaml、jsonlite、mirt、psych、ggplot2、readxl 和 haven。通常不需要手动安装 R 包。

静默安装说明：运行工具时，启动器会调用 R 的 install.packages() 安装缺失包。请保持网络畅通，并允许 R 写入个人 R 包目录。若单位网络限制 CRAN，可先配置代理或在可联网环境完成一次安装。

```powershell
.\run_irt_analysis.ps1
```

如果 PowerShell 阻止脚本执行，仅在当前窗口运行以下命令后再启动工具：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## 3. 三种运行方式

### 3.1 交互式向导

在工具文件夹打开 PowerShell，直接运行。系统会打开数据文件选择框，随后依次询问计分方式、维度、模型与缺失策略。输入提示中的数字并按回车即可。

若不确定选哪个模型，在"怎么选模型？"一问里选**向导推荐**（图形界面第 1 步的「模型选择向导」是同一个逻辑）：
依次回答 计分类型 → 维度 → 样本量，多级数据再回答"作答方式"、二分数据再回答"特殊情况"；
**若第 2 问选了"多维/不确定"，会额外追问两问**——① EIFA（探索）还是 CIFA（验证）；
② 多维模型家族选 `auto` / M2PL（二分）/ M3PL（二分）/ MGRM（多级）/ MGPCM（多级）。
答完给出带文献依据的推荐，图形界面还会自动回填模型下拉框与 `mirt_item_model`。

```powershell
cd "C:\Users\你的用户名\Desktop\IRT-Analysis"
.\run_irt_analysis.ps1
```

模型拟合前会显示数据体检报告。若没有严重问题，输入“2”继续；输入“1”取消。

### 3.2 快捷命令

已知道数据路径与模型时，可跳过大部分问答。

```powershell
.\run_irt_analysis.ps1 -Data ".\responses.xlsx" -m grm
.\run_irt_analysis.ps1 -Data ".\responses.xlsx" -Auto
```

-m 可取 rasch、2pl、3pl、grm 或 mirt。

-Auto 会根据数据计分特征和维度建议拟合候选模型，并输出 BIC 排序理由。

-Verbose 可在排错时显示原始 R/Python 诊断；普通模式仅显示中文提示。

### 3.3 静默模式（AI 或批处理）

复制 examples/silent_config_example.json，填写数据路径与题目列后运行。静默模式不弹出问答框，只输出一行一个 JSON 事件。

```powershell
.\run_irt_analysis.ps1 -Silent -ConfigJson .\examples\silent_config_example.json
```

## 4. 支持的数据与模型

| 类别 | 支持内容 | 适用情形 |
|---|---|---|
| 数据格式 | CSV、.xlsx、.xls、.sav | 一行一名被试，一列一个题目 |
| Rasch / 1PL | 二分数据 | 所有题目区分度相等的理论假设 |
| 2PL | 二分数据 | 题目区分度可不同 |
| 3PL | 二分数据 | 有充分理论依据时考虑猜测参数 |
| GRM | 有序多级数据 | Likert 等等级反应（Samejima 1969 累积 logit） |
| GPCM | 有序多级数据 | 部分计分/逐步作答（Muraki 1992 相邻类别 logit）。Likert 数据建议与 GRM 一起拟合、按 BIC 选（`compare_models: [grm, gpcm]`） |
| 探索性 MIRT（EIFA） | 二分或有序多级数据 | 未预设结构时，比较维度范围并报告 oblimin 旋转载荷、特征值与维度相关。家族由 `mirt_item_model` 指定：`auto`（按计分类型自动匹配）｜`2pl`（M2PL，仅二分）｜`3pl`（M3PL，仅二分）｜`grm`（MGRM，仅多级）｜`gpcm`（MGPCM，仅多级） |
| 验证性 MIRT（CIFA） | 二分或有序多级数据 | 已有题目-维度理论结构；提供 item,dimension CSV，固定未指定交叉载荷为零。家族同上 |

### 4.1 几条实测经验（拿本仓库的模拟数据跑出来的）

| 情形 | 数据 | 结果 |
|---|---|---|
| 忽略猜测按 2PL 拟合 | 真值是 3PL（1500 × 20，c ∈ [0.08, 0.25]） | 题目难度被**系统性低估约 0.285 logit**；而逐题 c 无法恢复（*r* = −.41） |
| BIC 选模型 | 同上 | 并列比较表里 2PL 的 BIC **更低**（33561 vs 33642）。配置里显式写 `model: 3pl` 时工具仍按 3PL 出结果；交给 `model: auto` 就会被判成 2PL——3PL 的额外参数惩罚很重，这正是"3PL 需要更大样本"的实测依据 |
| EIFA 的 θ 能逐因子比吗 | 三维 GPCM（900 × 24） | **不能**。EIFA 的因子经斜交旋转，逐因子 θ 恢复只有 *r* ≈ .41/.49/.40；同一份数据的 CIFA 是 .94/.93/.94。要得到可跨样本比较的维度分数，请用 CIFA + 题目-维度对照表 |
| 题目参数恢复 | 三维 GPCM | 台阶 b 恢复 *r* = .995（RMSE ≈ .12），与 EIFA/CIFA 无关，两者都好 |

### 4.2 独立验证状态（2026-09-18）

本分支输出经过三层复核（闭式复算 / 真值恢复 / 独立实现对照）与两轮外部模型实跑复核，**未发现已证实的数值错误**：MDISC、b↔d 换算（含 GPCM 台阶口径）、ICC（Samejima/Muraki/Birnbaum 闭式逐点）、IIF、TIF、缺失勾稽、BH 校正、题名口径均可独立复算。独立实现对照的结果：单维 2PL/GRM 的 a、b 与阈值和 `ltm` 的 **r = 1.0000**；单维 GPCM 的 a 和 `TAM` 的 **r = .999996**；二维 GPCM 的 a **r = .9977**、台阶 **r ≥ .9997**（量尺对齐后 b_d4 平均差 .0513，略高于 .05 的建议线，属边界值）；单维 2PL 的 SRMSR 在两引擎间相差 **5.0e-05**。

**两项已知缺口**：
1. **三维及以上多维 GPCM 尚无独立实现对照**：可用的第二引擎 TAM 在 3 维 × 24 题规模下不收敛（n=150 时 380 秒未返回；2 维子模型秒级完成）。故三维 MGPCM 的参数目前只有闭式自洽与真值恢复证据；补齐需安装 `sirt` 等可收敛的第二引擎。
2. **`M2*` 及其 df、`TLI`、`CFI` 尚无第二实现对照**：TAM 不输出这些量，只有 SRMSR 可作数值对照；SRMR 在两引擎的定义不同，不可逐位比。

## 5. 数据体检与错误提示

每次耗时拟合前，工具都会检查样本量、题目数、类别数、总体缺失率、每题缺失率、零方差题项与极少使用的反应类别。以下问题会阻止拟合：找不到数据或题目列、少于 3 个题目、非整数计分、全缺失题项、零方差题项，以及模型与计分方式不兼容。

缺失策略可选 none（默认，交给 mirt 的观测反应处理）、listwise（仅保留完整个案）和 pairwise（用于维度建议的可用个案相关）。所有缺失数量和比例会写入报告与 CSV。

## 6. 输出结果说明

结果保存于 outputs/项目名_模型_时间戳/，不会覆盖旧结果。

| 文件类型 | 用途 |
|---|---|
| report_zh.docx / report_en.docx | 中英文 结果报告风格完整报告 |
| model_comparison.csv | AIC、BIC、SABIC、M2、RMSEA、SRMSR、TLI、CFI 等 |
| model_recommendation.csv | 自动选模时的 BIC 排序与被选模型 |
| item_parameters.csv | 区分度、阈值/难度、猜测参数等 |
| item_fit.csv | S-X² 与 BH 校正后的项目拟合诊断 |
| ability_estimates.csv | 每名被试的 MAP θ 与标准误 |
| missingness_summary.csv | 缺失策略、数量与比例 |
| ICC/IIF/TIF/theta_distribution PNG | 300 dpi 项目与测验图形 |

### 6.1 透明性与可追溯性说明

自动完成的步骤：读取 CSV/Excel/SAV、识别候选题目与计分类型、统计样本量/缺失/零方差/稀疏类别、按配置拟合模型、计算拟合指标与项目/能力结果、生成 300 dpi 图形和中英文报告、保存结果。自动选模仅以预设候选模型与 BIC 排序为依据。

必须由用户设置或确认的步骤：要纳入哪些题目与 ID 列、缺失策略、模型类型与维度数、MIRT 选择 EIFA 还是 CIFA、CIFA 的 item-dimension 归属、迭代上限，以及是否接受统计结果作为理论上合理的模型。模型接受、题目删除和实质性解释均不自动完成。

每次运行均保留 config_snapshot、run_manifest、模型比较 CSV、数据体检结果、带时间戳的输出目录和（默认）RDS 模型对象；这些文件可与论文方法、补充材料或审稿回复一并提供，以追溯分析设置。

### 6.2 结果阅读：各参数怎么理解

本节用于帮助初次使用者从“模型是否合适—题目是否工作—分数是否可靠”三个层次阅读结果。以下阈值只是常用经验参照，不是机械的通过/不通过规则；应优先比较同一数据上的候选模型，并结合量表理论、样本特征和题目内容判断。

#### 6.2.1 先看模型拟合与比较

- -2LL：同一数据、同一估计框架下越小通常表示拟合更好；它本身不提供“好不好”的绝对标准。

- AIC、BIC、SABIC：用于比较候选模型，数值越小越优；BIC 对模型复杂度惩罚更强，是本工具自动选模的默认排序依据。不要把不同数据集的 BIC 直接相互比较。

- M2、df、p：M2 检验模型与数据是否存在整体偏离。p 值较大表示没有足够证据拒绝模型；但样本量较大时，即使偏离很小也可能得到显著 p 值，故必须同时看近似拟合指标。

- RMSEA 与 SRMSR：越小越好。RMSEA 约 < .05 常被视为接近拟合，.05–.08 为可接受范围；SRMSR 约 < .08 常作参考。它们是经验界限，不替代理论判断。

- CFI 与 TLI：越接近 1 越好；约 ≥ .95 通常表示较好拟合，.90–.95 可作为进一步检查的区间。CIFA 应优先与其单维基线比较 ΔCFI、ΔRMSEA、ΔAIC、ΔBIC：CFI 上升、RMSEA/AIC/BIC 下降通常支持多维结构。

#### 6.2.2 再看项目参数

- Rasch/1PL：主要解释难度/位置参数 b；b 越大，代表需要更高潜在特质才更可能作答正确或选择较高类别。

- 2PL：a 为区分度，b 为难度。a 越大，题目越能区分相近能力者；在常用量尺上，约 .65–1.35 可视为中等、> 1.35 较高、< .65 较低，但这只是描述性参照。

- 3PL：除 a、b 外，c 为低能力者答对的下限/猜测参数。c 偏高可能提示猜测、线索或模型不稳，应有选择题猜测的理论依据后再采用 3PL。

- GRM/MIRT：a（或因子载荷）表示题目与某维度的关联强度；d 是软件内部截距，通常不直接解释。报告中的 b_d1、b_d2… 是换算后的类别阈值/位置：它们应随类别递增；阈值很极端、顺序异常、NA 或类别频数很少时，应回查计分与类别使用。MDISC 是多维项目的综合区分度。

- GPCM / MGPCM：**b 的口径与 GRM 不同，别按同一套读**。GRM 的内部截距 d_k 本身就是阈值
  （`b_k = -d_k / MDISC`）；GPCM 的 d_k 是**类别截距**（参考类别 d₀ ≡ 0），标准台阶难度是
  **相邻截距之差** `b_k = -(d_k - d_{k-1}) / MDISC`。工具输出的 `b_d1…b_d_{K−1}` 用的是台阶口径，
  因此**不会出现 b_d0**。（已实测：单维 GPCM 下工具的 b 与 mirt 自己的 `coef(fit, IRTpars = TRUE)`
  逐题相同，最大绝对差 5×10⁻¹⁵。多维 GPCM 时 mirt 的 `IRTpars` 返回 NA，只能与生成真值核对。）

- 3PL 的 c 是**弱识别参数**：实测（N=1500、20 题）c 的均值几乎无偏，但逐题恢复相关只有 −.41，
  即"哪道题更容易被猜对"基本排不出来。报告里写逐题 c 时务必说明这一点。

#### 6.2.3 MIRT 的载荷和维度关系

探索性 MIRT（EIFA）先看旋转后载荷：一个题应在理论目标维度上较高、在其他维度上较低；交叉载荷较大说明题目可能不是简单结构。特征值和 BIC 用于共同判断维度数，不能仅凭其中一个指标决定。

验证性 MIRT（CIFA）中，loading_matrix 指定的主载荷被估计，未指定的交叉载荷固定为 0。载荷的 SE、z、p 反映该主载荷是否稳定地偏离 0；p 显著不等于载荷在实质上足够大。dimension_correlations.csv 中的相关越接近 1，说明维度越难区分；接近 0 表示相对独立，但不等于量表具备外部效度。

#### 6.2.4 项目拟合、θ 与标准误

item_fit.csv 的 S-X²、p.S_X2 与 BH_p 用于定位可能失配题。先看 BH_p：校正后很小的 p 值提示该题的观测反应与模型预测存在差异，应检查反向计分、题意、局部依赖和类别稀疏；不要自动删除。RMSEA.S_X2 较小通常是较好的辅助信号。

ability_estimates.csv 中的 F1、F2… 是 MAP 能力估计（θ），0 约为样本潜变量量尺中心，正值/负值表示相对高/低，而不是百分制分数。相应的 SE_F1、SE_F2… 是测量误差，越小越精确；处在量表两端或信息较低的区域，SE 往往更大。比较个体前应先确认模型和量尺在研究对象中适用。

#### 6.2.5 图形如何使用

ICC 显示不同 θ 下各反应类别的概率，理想情况下类别曲线随 θ 有序转换；IIF 显示单题在哪个 θ 区间最有信息；TIF 是题目信息的合计，峰值越高表示该区间测量越精确。MIRT 图均为条件切片：非目标维度固定为 0，因此它们描述的是特定条件下的精度，而不是所有维度组合下的平均精度。

建议的阅读顺序：先核对数据体检与类别频数 → 比较模型拟合 → 检查项目载荷/参数与项目拟合 → 看 θ 的 SE 与信息函数 → 最后结合理论、内容效度、局部依赖、DIF 和独立样本复现决定是否保留模型或题目。

## 7. 完整示例：从 Excel 到报告

情境：你有一份 300 名被试、12 个 1–5 分 Likert 题目的 Excel 文件 responses.xlsx，并假设量表为单维。

1. 将 Excel 整理为 Participant_ID、Q1–Q12；删除总分和文本列。

2. 进入工具目录并运行 .\run_irt_analysis.ps1。

3. 在文件选择框中选择 responses.xlsx。

4. 依次选择：有序多级（3）→ 单维（2）→ GRM（5）→ 不预处理缺失（1）。

5. 阅读数据体检；若项目数、缺失率和零方差检查无误，选择继续运行（2）。

6. 完成后打开 outputs/interactive_irt_grm_时间戳/ 下的 report_zh.docx。

7. 查看 model_comparison.csv、item_parameters.csv 与 ability_estimates.csv，结合理论和题目内容解释结果。

### 7.1 验证性 MIRT（CIFA）示例

情境：你有 20 个 1–5 分题目，并已依据理论将 Item01–Item10 归入 F1、Item11–Item20 归入 F2。先创建 UTF-8 编码的 loading_matrix.csv；文件只有两列，列名必须精确为 item,dimension。

item,dimension
Item01,F1
…
Item10,F1
Item11,F2
…
Item20,F2

在工具目录运行：

```powershell
.\run_irt_analysis.ps1 -Data ".\responses.xlsx" -m mirt -cifa -loading_matrix ".\loading_matrix.csv"
```

工具会先核查 CSV 是否覆盖每一个项目、每个项目是否只出现一次、每个维度是否至少包含两个项目；通过体检后，输出约束载荷、载荷的标准误与双侧 Wald 近似 p 值、维度相关，以及 CIFA 相对于单维模型的 ΔCFI、ΔRMSEA、ΔAIC 与 ΔBIC。

探索性 MIRT 的快捷命令为：

```powershell
.\run_irt_analysis.ps1 -Data ".\responses.xlsx" -m mirt -eifa -dim_range "1-3"
```

### 7.2 示例数据：二维二分类 MIRT-2PL

examples 文件夹提供 simulated_mirt_2pl_binary.csv（400 名被试、12 个 0/1 题）、simulated_mirt_2pl_binary_loading_matrix.csv（每个维度各 6 题）、simulated_mirt_2pl_binary_truth.csv（生成参数）以及 simulated_mirt_2pl_binary_expected_output.md（核对值）。该数据由 mirt::simdata() 以固定种子 20260815 生成。

在工具文件夹运行： .\run_irt_analysis.ps1 -Data ".\examples\simulated_mirt_2pl_binary.csv" -m mirt -cifa -loading_matrix ".\examples\simulated_mirt_2pl_binary_loading_matrix.csv"

已验证的预期模式是二维 CIFA-2PL 优于单维 2PL：BIC 约为 5656.681 对 5808.759，CFI 约为 1.000 对 0.746，RMSEA 约为 0.000 对 0.095，ΔBIC 约为 -152.078。不同 R/mirt 小版本下末位小数可略有变化；成功标志是运行清单显示 mirt_mode: cifa、mirt_item_model: 2PL、dimension_count: 2，并生成中英文 Word 报告。

若只想测试系统而不关心外部数据，可运行 examples/silent_mirt_2pl_cifa_simulation.json： .\run_irt_analysis.ps1 -Silent -ConfigJson .\examples\silent_mirt_2pl_cifa_simulation.json。它会在后台现生成相同规格的模拟数据并输出结构化 JSON 日志。

## 8. 常见问题与解决方法

| 提示 | 常见原因 | 建议 |
|---|---|---|
| 找不到数据文件 | 路径、文件名或扩展名不正确 | 重新使用文件选择框；确认文件未移动 |
| 题目不是整数计分 | 把文本、总分、小数或人口学变量当成题目 | 仅保留整数题目列 |
| 零方差题项 | 所有人选择同一选项 | 删除或修订该题后重试 |
| 模型未收敛 | 模型过复杂、样本不足或类别稀疏 | 减少维度、选择更简单模型、增加样本或提高 max_iterations |
| 多级数据不能拟合 2PL/3PL | 计分与模型不匹配 | 选择 GRM 或 MIRT |
| Word 报告未生成 | Python 依赖或权限问题 | 保留 CSV/Markdown；使用 -Verbose 查看诊断 |

### 8.1 常见问题补充

Q：文件格式或列名报错怎么办？ A：仅支持 CSV、.xlsx/.xls、.sav；每题必须是整数反应。请确认首行是唯一列名、每行是一名被试，并排除总分、文本与人口学变量。若扩展名写成 .csv 但文件实际是 Excel，请改正扩展名，或重新另存为真正 UTF-8 CSV/Excel。

Q：中文路径或带空格的路径能用吗？ A：可以。请始终用引号包住路径，例如 -Data "C:\Users\你的用户名\Desktop\研究数据.xlsx"；不要手动把反斜杠替换成乱码。

Q：R 或依赖包安装失败怎么办？ A：先确认命令行能找到 Rscript.exe，保持网络可访问 CRAN，并允许 R 写入个人包目录。单位网络受限时先配置代理或在可联网电脑完成一次包安装；随后重新启动 PowerShell。

Q：模型不收敛怎么办？ A：先检查稀疏类别、零方差题与反向计分；再考虑减少维度、使用更简单的 1PL/2PL/GRM、增加样本量或提高 max_iterations。不要仅靠提高迭代次数掩盖错误的模型结构。

Q：CIFA 的归属文件为什么不通过？ A：文件必须含小写列名 item,dimension；每个纳入题目恰好出现一次、题目名与数据列名完全一致，每个维度至少有两个题。多级数据应让 MIRT 使用 GRM；2PL/3PL 只适用于二分数据。

## 9. 算法、可靠性与参考文献

本工具所有 IRT 模型参数估计均调用 R 语言 mirt 包完成。mirt 是经同行评议的软件包，支持边际极大似然估计、EM、MHRM 等 IRT 经典估计流程，以及多维模型、项目拟合和能力估计。工具会保存配置快照、模型对象、输入体检与时间戳结果，因此分析可复现。

可靠性边界：软件实现不能替代研究设计与心理测量判断。研究者仍应依据量表理论选择维度结构，检查反向计分、局部独立性、DIF、类别稀疏性及跨样本稳定性；报告中的模型推荐是统计辅助，不是自动的理论结论。

验证性 MIRT 算法说明：工具把 item,dimension CSV 转换为 mirt.model() 语法，为每个维度声明允许载荷的题目，并在简单结构下将未声明的交叉载荷固定为零，同时估计维度协方差。CIFA 适用于有先验理论或量表结构证据的情形；它检验的是指定模型与数据的相容性，不能单独证明理论正确。EIFA 则在用户给定范围内比较无约束维度解，并将 BIC、特征值与旋转载荷作为共同的判断依据。

核心参考文献：

Chalmers, R. P. (2012). mirt: A multidimensional item response theory package for the R environment. Journal of Statistical Software, 48(6), 1–29. https://doi.org/10.18637/jss.v048.i06

Bock, R. D., & Aitkin, M. (1981). Marginal maximum likelihood estimation of item parameters: Application of an EM algorithm. Psychometrika, 46, 443–459. https://doi.org/10.1007/BF02293801

## 10. AI工具使用说明

作者目前仅是一名大三心理系本科生，工程能力尚在成长中，因此本工具的代码实现部分借助了 Codex (OpenAI) 作为AI agent完成，底层模型为GPT 5.6-Terra，本人负责提供方向想法与结果验证。

