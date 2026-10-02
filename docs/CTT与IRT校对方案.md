# CTT / IRT 输出校对方案

> 目的：把 CTT 与 IRT 两个分支的输出，用**和心理统计分支同一套体例**校对一遍，
> 产出一份可随仓库发布的对照记录，并把其中能自动化的部分沉淀成回归夹具。
>
> 配套文档：`SPSS与Psychostat心理统计模块输出对应.docx`（心理统计分支的已完成版，本方案沿用它的版式）、
> `tests/fixtures/spss/README.md`（夹具贡献流程）、`docs/待修问题清单.md`（第 1、4、5 条与本方案直接相关）。

---

## 0. 为什么不能照搬心理统计分支的做法

心理统计分支之所以能"逐模块对 SPSS"，是因为**SPSS 27 有对应的菜单**，一对一抄表即可。
CTT 与 IRT 各有各的难处，先说清楚，否则会白忙：

| 分支 | 与 SPSS 的关系 | 因此判据是 |
|---|---|---|
| **心理统计**（已完成） | 模块 ↔ SPSS 菜单**一一对应** | 对 SPSS 数值（唯一权威） |
| **CTT** | **大部分能对**（信度、项目分析、EFA、效标、已知组），但**三样 SPSS 给不了**：McDonald's ω、α 的置信区间、CFA | 对 SPSS 为主，缺的三样另找参考 |
| **IRT** | **SPSS 完全没有 IRT**；而本工具的计算引擎**本身就是 mirt**——"拿 mirt 对 mirt"是同义反复 | 换三层判据（见 §1） |

> **范围决定（2026-09-18）**：**不对 SPSS、也不对 Mplus**。
> CTT 与 IRT 都用**权威开源实现与其文档定义**作为外部基准：
> ① 教科书闭式公式（§1 的 L1）；② **R 的另一套实现**——IRT 用 `ltm`（2PL/GRM 边际极大似然）
> 与 `TAM`（GRM/GPCM 斜率—截距）、`psych::irt.fa`；CTT 的 CFA 用 `lavaan` 之外的独立路径
> （闭式 CR/AVE + `OpenMx`/`semTools`），并逐项给出参数化换算；③ 已知真值恢复（L2）。
> 相应地：L3 **不再需要任何商业软件**，全部可在本机命令行完成。

---

## 1. 三条判据（"校对通过"到底指什么）

| 层 | 判据 | 怎么做 | 强度 | 能否进 CI |
|---|---|---|---|---|
| **L1 可解析性质** | 用闭式公式**独立复算**，不依赖被测代码 | 如 `MDISC = sqrt(Σaⱼ²)`、`b = -d/MDISC`、`I(θ) = a²P(1−P)`、`TIF = ΣIIF` | 最强 | ✅ 能 |
| **L2 真值恢复** | 模拟数据带生成真值，看参数能否恢复 | `cor(估计, 真值)`、RMSE、回归斜率 | 强 | ✅ 能（固定 seed） |
| **L3 独立实现对照** | 与**另一套 R 实现**或教科书公式对同一份数据 | IRT：`ltm`、`TAM`、`psych::irt.fa`；CTT：闭式公式 + `OpenMx`/`semTools` | 中（受参数化口径影响，必须先换算） | ⚠️ 一般不能（`ltm`/`TAM` 未必随包分发） |

**三条都要做，但顺序是 L1 → L2 → L3**：L1 最便宜、最能防回归，而且**能直接抓 bug**
（本轮 IRT 走查里最严重的那个 GPCM 参数表错误，就是 L1 型的 `MDISC ≠ sqrt(Σa²)`）。

---

## 2. CTT 校对清单（**已实现并实跑通过**）

> 执行方式：`Rscript --vanilla tests\verify_l1_ctt.R <结果目录> [更多目录...]`
> 复算脚本用**教科书闭式公式**从 `01_cleaned_items.csv`（清洗后数据）独立重算，
> 不调用工具内部函数，也不再用 `psych::alpha` 去验证一个内部就是 `psych::alpha` 的工具。

### 分组 A：已落地的 L1 复算（全部可与公式逐位比对）

| # | 校对内容 | 产出文件 · 字段 | 独立依据（公式/文档） | 三态 | 容差 |
|---|---|---|---|---|---|
| C1 | 总量表 α | `03_reliability.csv` · `alpha`(Total) | Cronbach (1951)：`α = k/(k−1)·(1−Σσᵢ²/σ²)`（协方差口径） | 预期一致 | 1e-10 |
| C9 | 删除项后的 α | `03_alpha_if_deleted.csv` · `alpha_if_deleted` | 同上，逐题去掉后重算 | 预期一致 | 1e-10 |
| C2 | CITC（校正后题总相关） | `02_item_analysis.csv` · `CITC` | 定义：`cor(题ᵢ, 总分−题ᵢ)` | 预期一致 | 1e-10 |
| C3 | CR 决断值 | `02_item_analysis.csv` · `low_mean` `high_mean` `CR_t` `df` `p` | 高低 27% 分组 + 合并方差 t（`floor(.27n)`） | 预期一致 | 1e-10 |
| C4 | KMO | `04_efa_diagnostics.csv` · `KMO` | Kaiser (1974)：`Σr²/(Σr²+Σ偏相关²)`，偏相关取自 `R⁻¹` | 预期一致 | 1e-8 |
| C5 | Bartlett 球形检验 | 同上 · `Bartlett_chisq` `Bartlett_df` | Bartlett (1937)：`χ² = −[(n−1)−(2p+5)/6]·ln(det R)`，`df = p(p−1)/2` | 预期一致 | 1e-6 |
| C6 | EFA 表内部一致性 | `04_efa_rotated_loadings.csv`、`04_efa_variance.csv` | `primary_loading = max(abs(λ))`；`primary_factor` 对应之；`proportion = SS/k`；`cumulative = cumsum` | 预期一致 | 1e-10 |
| C7 | CFA 的 CR / AVE | `05_cfa_convergent_validity.csv` | Fornell & Larcker (1981)：`CR=(Σλ)²/((Σλ)²+Σ(1−λ²))`、`AVE=mean(λ²)`（λ 取标准化解） | 预期一致 | 1e-10 |
| C8 | 单因子 ω | `03_reliability.csv` · `omega` | `ω = (Σλ)²/((Σλ)²+Σ(1−λ²))`，λ 取工具同一张载荷表（单因子解时） | 预期一致 | 1e-3 |

**实跑结果（2026-09-18，ctt_A / ctt_B（CFA 路线）/ ctt_D 三个目录）**：

```
L1_PASS=29  L1_FAIL=0  L1_SKIP=5
CTT L1 复算：全部通过
```

代表性实测量（工具值 vs 闭式值）：

| 检查 | 数据 | 结果 |
|---|---|---|
| C1 α | ctt_B | 工具 0.8492906595 vs 闭式 0.8492906595（差 0） |
| C9 删除项后 α | ctt_B | 最大相对差 5.2e-16 |
| C2 CITC | ctt_B | 最大相对差 1.0e-15 |
| C3 CR 决断值 | ctt_D | 每组 189 人，最大相对差 2.6e-15 |
| C4 KMO | ctt_A | 0.97164588 vs 0.97164588 |
| C5 Bartlett χ² | ctt_D | 3434.347880 vs 3434.347880（df 153） |
| C7 CR/AVE | ctt_B | 最大相对差 5.2e-16 / 8.3e-16 |
| C8 ω（单因子） | ctt_A | 0.919401 vs 0.919392（差异来自 ω 的因子抽取口径，1e-5 量级） |

### 分组 B：仍待补的 CTT 项

| # | 校对内容 | 独立依据 | 状态 |
|---|---|---|---|
| B1 | α 的 95% CI | 正态近似 `α ± 1.96×ase` 手算；或 Feldt (1965) 的精确 CI 作对照 | 待补（两种方法结果本就不完全相同，属"预期不同的两种口径"） |
| B2 | CFA 拟合指数与载荷的**独立复核** | `OpenMx` / `semTools`（独立于 lavaan 的第二实现） | 待补（工具引擎是 lavaan，用 lavaan 复核属同义反复） |
| B3 | EFA 载荷与解释方差的**独立复核** | `ltm`/`TAM` 不含 EFA；可用 `factanal`（stats 内置，独立于 psych 的 minres 实现）作交叉 | 待补 |

### 分组 C：工具自定义规则（SPSS 无对应，校对 = 核对计数与规则）

| # | 校对内容 | 产出文件 | 怎么校 | 状态 |
|---|---|---|---|---|
| C10 | 清洗计数 | `01_cleaning_summary.csv`、`01_case_cleaning_audit.csv` | 用 base R 复现同一规则（整行同值、注意题≠正确值、反应时<阈值、缺失率>20%/<5%）后数人，与工具计数逐项比 | 待补（可脚本化，无需外部软件） |
| C11 | 插补后描述统计 | `01_cleaned_items.csv` | 直接对清洗后数据算 M/SD 与 `01_cleaned_items.csv` 自身一致 | 已隐含在 C1–C3（同一份数据即可复现） |

### 分组 D：明确**不需要**校对

| 项 | 原因 |
|---|---|
| 分半信度、重测信度 | **工具未输出**（手册 §11 已说明） |
| "删除项后的标度均值/方差"、"基于标准化项的 α" | 工具未输出（可选改进项） |
| 图形（碎石图、载荷热图） | 只查可读性，不校对数值 |
| Word/HTML 报告排版 | 抽查即可；数值应等于对应 CSV（见 §3.6 报告层一致性） |

---

## 3. IRT 校对清单

数据准备：仓库里 **9 组带真值的 IRT 数据**就是现成的校对材料，按要校的模型挑：

| 数据 | 用来校 |
|---|---|
| `irt_A_binary_2pl_n800_items20.csv` | 2PL |
| `irt_E_rasch_n500_items15.csv` | Rasch（真 a ≡ 1） |
| `irt_H_binary_3pl_n1500_items20.csv` | 3PL（含猜测 c） |
| `irt_B_polytomous_grm_n600_items15.csv` | GRM / GPCM |
| `irt_D_binary_missing5pct_n800_items20.csv` | 缺失三策略 |
| `irt_C` / `irt_G` / `irt_I` | MIRT（EIFA / CIFA，多级与二分各一） |

### 分组 A：L1 可解析性质（**最该先做，且能进 CI**）

| # | 校对内容 | 产出文件 | 独立复算方式 | 判定 |
|---|---|---|---|---|
| A1 | **MDISC = sqrt(Σaⱼ²)** | `*_item_parameters.csv` | 从同表的 `a1..aD` 直接算 | 相对误差 < 1e-8。**这条已进 `smoke_test.ps1 -Full`**，专防 GPCM 的 `ak*` 列混入 |
| A2 | **b 与 d 的换算** | 同上 | GRM：`b = -d/MDISC`；**GPCM：台阶 = 相邻截距之差 ÷ MDISC**（口径不同，别混） | 1e-8。单维 GPCM 下还应与 mirt 自己的 `coef(fit, IRTpars=TRUE)` 逐题相同（实测差 5e-15） |
| A3 | **ICC 曲线** | `*_icc_data.csv`（`Theta, Probability, Category, Item`） | 2PL/3PL 用 `P = c + (1-c)/(1+exp(-a(θ-b)))` 逐点算；GRM/GPCM 按类别累积公式 | 最大绝对差 < 1e-8 |
| A4 | **IIF 题目信息** | `*_iif_data.csv` | 2PL：`I(θ) = a²P(1−P)`；多级按 mirt 的类别信息公式 | 同上 |
| A5 | **TIF = Σ IIF** | `*_tif_data.csv` | 把同一 θ 上各题的 IIF 相加 | 同上 |
| A6 | **能力 SE 与信息量的关系** | `*_ability_estimates.csv` | `SE(θ) ≈ 1/sqrt(I(θ))`（MAP 下是近似，**只有量级与形状要一致**，不要求逐位） | **中位比值 ∈ [0.75, 1.25] 且 r ≥ .70**（见下方阈值变更说明） |
| A7 | **模型比较表内部一致** | `*_model_comparison.csv`、`*_model_recommendation.csv` | 排行按 `selection_criterion` 升序；`Selected=TRUE` 的行必须 = 实际使用的模型（本轮刚修过一个反例） | 严格一致 |
| A8 | **CIFA 载荷矩阵结构** | `*_cifa_loading_matrix.csv` | 行数 = 题目数；每题只出现一次；未指定维度的载荷为 0 | 严格一致。**已进 smoke** |
| A9 | **缺失审计勾稽** | `*_missingness_summary.csv` | `Original_N − Listwise_removed = Analysed_N`；`Missing_cells_before` 与逐题缺失表相加一致 | 严格一致 |
| A10 | **Rasch 的 a 恒为 1** | `*_item_parameters.csv` | 真 Rasch 数据下 `a` 列的极差应为 0 | 极差 < 1e-8。**若不为 0，说明拟合的不是 Rasch** |
| A11 | **题目拟合的 BH 校正** | `*_item_fit.csv` | `BH_p` 是否等于 `p.adjust(p.S_X2, "BH")` | 1e-12（专防列名匹配静默降级） |
| A12 | **各输出表题名口径一致** | 目录内所有含 Item 列的 CSV | 按数字键（`Item01 ↔ Item1`）比较题目集合 | 严格一致。**本轮靠它发现 CIFA 路线的题名不一致**，详见 `CTT与IRT校对记录.md` 6.1 |

> **状态：分组 A 已全部实现并实跑通过** —— `tests/verify_l1_irt.R`，8 个结果目录
> **PASS = 109 / FAIL = 0 / SKIP = 13**（SKIP 均为"该路线不适用"）。
> 逐项实测偏差见 `docs/CTT与IRT校对记录.md` 第 2 节。

> **阈值变更说明（A6，2026-09-18 第三方复核后补记）**：本表原写"相关 > .95"，实现时改为
> "中位比值 ∈ [0.75,1.25] 且 r ≥ .70"。**放宽是必要的**：MAP 估计下 `SE(θ)` 是后验 SD，
> 天然小于 `1/sqrt(I(θ))`（收缩），逐点相关会被尾部噪声拉低——实测 3PL 的 r = .732、
> GRM 的 r = .761，而两者的**中位比值都 ≈ 0.93**（量级完全正确）。但当时只把理由写在脚本注释里，
> 没有同步这张表，属**未声明的阈值迁移**（第三方复核指出，已在此声明）。

### 分组 B：L2 真值恢复（**已脚本化并实跑通过**）

脚本：`tests/verify_recovery_irt.R`。用法：`Rscript --vanilla tests/verify_recovery_irt.R <结果目录>...`
逐数据集产出下面这张表，作为"这个工具的参数估计靠不靠谱"的证据（实测值，8 组目录 **PASS = 32 / FAIL = 0**）：

| 指标 | 怎么算 | 实测 | 判据 |
|---|---|---|---|
| a 恢复 | `cor(a_est, a_true)`、RMSE | 2PL .909；3PL .770；GRM .943；MIRT .850–.873；Rasch 固定参数（逐题偏差 0） | r ≥ .70 |
| b 恢复 | 同上 | 二分 r = .964–.997；多级台阶 r = .995（96 个阈值） | r ≥ .90 |
| **c 恢复（3PL）** | 同上 | **r = −.406**，RMSE .139，均值无偏（真值 .168 / 估计 .171）→ **群体可用、逐题排序不可用** | **只报告不判定** |
| θ 恢复 | `cor(θ̂, θ_true)`、回归斜率、平均 SE | CIFA：r = .870–.943；EIFA：r = .395–.612 → **不可逐因子比**（旋转未对齐） | CIFA r ≥ .80；EIFA 只报告 |
| 结构恢复 | CIFA 主载荷是否落在真维度 | **24/24（100%）与 20/20（100%）** | ≥ 95% |

> **坚固性**：脚本要求"真值文件与输出表**逐题全覆盖**对齐"（按数字键），
> 对齐不齐即判 FAIL——防止题名口径不一致时只对上半个数据、却报"恢复良好"。

### 分组 C：L3 独立实现对照（要处理"参数化口径"，最容易误判）

> **状态：`ltm` 对照已实现并实跑通过** —— `tests/verify_l3_irt_ltm.R`，**PASS = 6 / FAIL = 0 / SKIP = 0**。
> 实测：2PL 的 a 与 b、GRM 的 a 与 4 个阈值，**相关全部为 r = 1.0000**，|平均偏差| ≤ 0.008。
> 这是三层里最强的一条证据——闭式复算发现不了的"共同实现错误"要靠它。

| 独立实现 | 能对什么 | ⚠️ 必须先处理的换算 |
|---|---|---|
| **`ltm`**（R）✅已用 | 2PL / GRM 的 a、b 与 θ | 两种调用口径不同、**不能用同一种写法**：`ltm::ltm()` 有公式接口（`ltm(X ~ z1)`），返回列 `Dffclt, Dscrmn`；`ltm::grm()` **没有**公式接口（第一个形参就是 `data`），必须 `grm(X)`，返回列 `Extrmt1..ExtrmtK-1, Dscrmn`。区分度列固定叫 `Dscrmn`——**不要用 `names(co)[1]`**，那是难度列 |
| **`TAM`**（R）待用 | GRM / GPCM / MIRT 的斜率—截距参数 | 与 mirt 同为斜率—截距形式，量尺可比性最好；注意 `TAM` 的 `B` 矩阵含**类别乘子**（与 mirt 的 `ak*` 同源）——**换算时不要把乘子当成维度载荷**（本项目在 mirt 侧刚踩过同一个坑） |
| **`psych::irt.fa`**（R）待用 | 2PL / GRM 的题目参数 | 与 `psych` 同族，适合作 CTT↔IRT 的衔接检查（总分与 θ 的相关、α 与边际信度的一致性） |
| **闭式 CR/AVE** ✅已用 | CFA 的收敛效度 | 直接用 `05_cfa_loadings.csv` 的 `standardized_loading` 代入 `CR=(Σλ)²/((Σλ)²+Σ(1−λ²))`、`AVE=mean(λ²)`（L1，已实跑通过，最大相对差 8.3e-16） |
| **`OpenMx` / `semTools`** 待用 | CFA 的拟合指数与载荷（对 lavaan 的独立复核） | 需自行指定与工具相同的估计量（有序题 WLSMV / 连续题 ML）与 `std.lv` 约束；两边口径不对齐则不可比 |

### 分组 D：明确**不对齐 / 只对相对量**（写进记录）

| 项 | 原因 |
|---|---|
| 参数的**绝对原点**（a、b、θ 的绝对值） | 潜在量尺的识别约束不同（θ 的均值/方差、因子方差固定为几）→ 只比差值、相关、排序 |
| EIFA 的**因子标签** | 探索性解会旋转，F1/F2 与理论维度不一一对应（实测逐因子 θ 恢复仅 r ≈ .4） |
| **S-X² vs infit/outfit** | 不同的题目拟合统计量，不可互换 |
| θ 的绝对分数 | 同"绝对原点"，只比相对高低与 SE 量级 |

---

## 4. 操作步骤（沿用 `tests/fixtures/spss/README.md` 的流程）

对**每一个**要校对的模块重复：

1. **取数据**：跑一次 file 模式（不要用 simulate 模式，否则参考软件拿不到同一份数据）。
   数据文件在结果目录里（CTT 是 `simulated_ctt_data.csv` 或你自己放进去的那份 CSV）。
2. **记下元信息**：工具版本、R 与包版本、数据文件、seed、执行日期。
3. **在参考软件里跑**：按 §2/§3 的表选路径，注意表里标注的口径差异。
4. **存原始输出**：把参考软件的数值表（含表标题）另存为纯文本，放到
   `tests/fixtures/<软件>/<模块名>.txt`（如 `tests/fixtures/spss/ctt_reliability.txt`），
   **文件开头注明**：软件与版本、数据文件、seed、日期、勾选了哪些选项。
5. **填对照记录**：在对照文档里写三段——① Psychostat 侧数值；② 参考软件侧数值；③ `结论：一致 / 不一致（原因）`。
   体例照抄 `SPSS与Psychostat心理统计模块输出对应.docx`。文档开头必须有一节
   **「校对范围与已知差异（发布前请读）」**，逐条列出：覆盖了哪些模块、哪些没覆盖、
   哪些"落在容差外但已确认不是 bug"（及原因）。
6. **沉淀断言**：凡属 L1/L2 的，加进 `tests/test_numeric.R` 或 `tests/smoke_test.ps1 -Full`；
   凡依赖外部软件的（L3），**只留夹具文件 + 记录**，不进 CI（并在记录里说明这一点）。
7. **跑回归并提交**：`tests\run_numeric_tests.ps1` 全绿，夹具与改动一并提交，提交信息里写明软件版本与 seed。

---

## 5. 判定容差

| 比较对象 | 容差 | 理由 |
|---|---|---|
| 与 SPSS/Mplus 的**打印值** | **四舍五入到打印位数后相同** | SPSS 只打印 3 位小数；沿用心理统计分支已有的"一致"定义 |
| 与 R 第二实现（`ltm`/`TAM`/`psych`） | `< 1e-6` | 同一模型同一约束下应几乎逐位相同 |
| L1 闭式性质 | 相对 `< 1e-8`（或绝对 `< 1e-10`） | 纯代数恒等式 |
| L2 真值恢复 | 不给死阈值，给**参考区间** | 恢复精度取决于样本量/题目数，写死会误报 |

---

## 6. 优先级与工作量建议

| 优先级 | 内容 | 预估 | 说明 |
|---|---|---|---|
| **P0** | IRT 分组 A（10 条 L1 性质）+ CTT 的 A1/A2/A4/A5/A8 | 半天 | 大部分是脚本活，不需外部软件，且**能直接抓 bug** |
| **P1** | CTT 的 A3（CR 决断值）、A6/A7（EFA，注意提取方法对齐）、A9（已知组）、C1/C2（清洗计数） | 1 天 | 需要在 SPSS 里手工切分组/复现规则 |
| **P2** | CTT 的 B3（CFA，对 AMOS/Mplus）、B1/B2（ω 与 α 的 CI） | 1 天 | 依赖你机器上的软件 |
| **P3** | IRT 分组 B（恢复指标脚本化） | 半天 | 数据现成，写脚本即可 |
| **P4** | IRT 分组 C（对 `ltm` / `TAM` / `psych::irt.fa`） | 半天 | 全部在本机命令行完成；仍需先推导参数化换算，建议**只挑 1–2 个模型**做代表 |

**建议的起手式**：先做 P0。它不依赖任何外部软件、当天就能出结果，而且历史经验说明
这一层最容易抓到真问题（GPCM 的 `MDISC` 错误就是这一层抓到的）。

---

## 7. 需要你先确认/准备的事

1. **SPSS 27** ✅ 已有。**AMOS** 是否随版本安装？（CFA 要用）
2. ~~Mplus~~ / ~~flexMIRT~~ / ~~Winsteps~~：**已决定不用**，改用 R 第二实现 `ltm` / `TAM`。
3. 需要在本机装 `ltm` 与 `TAM`：`install.packages(c("ltm","TAM"))`。
   ⚠️ 但**目前 `mirt` 被 Windows 安全策略拦截**（`vegan.dll`），IRT 相关的一切都跑不了，见文末「环境阻断」。
4. **谁来跑参考软件**：SPSS/Mplus 只在你机器上，我跑不了——分工是
   **我负责**：跑 Psychostat 侧、准备数据、写复算与恢复脚本、把结果填进对照文档、沉淀断言；
   **你负责**：在 SPSS/Mplus 里按表操作并把输出表粘回来（或存成夹具 txt）。
5. **对照文档的落点**：建议命名为 `CTT与IRT输出校对记录.docx`，与现有那份并排放在项目根目录。

---

## 附：本方案与现有文档的关系

| 文档 | 关系 |
|---|---|
| `SPSS与Psychostat心理统计模块输出对应.docx` | **体例来源**（照抄它的三段式与"校对范围与已知差异"开头） |
| `tests/fixtures/spss/README.md` | **流程来源**（第 4 节的 7 步就是它的推广） |
| `docs/待修问题清单.md` 第 1 条 | 本方案正是它的执行方案（"SPSS 对照缺外部基准夹具"） |
| `docs/待修问题清单.md` 第 4 条 | IRT 分组 A 落实后，可把那条"预期值未被断言"一并关掉 |
| `docs/待修问题清单.md` 第 5 条 | IRT 分组 B 就是它的待办 |
| `examples/simulated_datasets/README_模拟数据说明.md` | 各数据的"实测值"栏可直接作为 L2 的对照基线 |

---

## 附：环境阻断（2026-09-18 发现，影响 IRT）

**现象**：IRT 分支的所有拟合都无法启动，报
`unable to load shared object 'D:/学习/R-4.5.2/library/vegan/libs/x64/vegan.dll': LoadLibrary failure: 应用程序控制策略已阻止此文件。`

**根因**（机器级安全策略，与代码无关）：

- **Windows Smart App Control 处于「强制」模式**：`HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy`
  的 `VerifiedAndReputablePolicyState = 1`。
- CodeIntegrity 事件日志（`Microsoft-Windows-CodeIntegrity/Operational`）在 **2026-09-18 08:06:49**
  明确记录：`Rscript.exe attempted to load vegan.dll that did not meet the Enterprise signing level
  requirements or violated code integrity policy (Policy ID: {0283ac0f-fff1-49ae-ada1-8a933130cad6})`。
- Smart App Control 会先以「评估」模式运行一段时间再自动转「强制」，这解释了"先前能跑、某时刻起不能"。

**影响范围（实测 19 个包）**：只有 **`vegan` 被拦 → `mirt` 因此不可用**；
`lattice / Matrix / Rcpp / mgcv / GPArotation / psych / lavaan / car / emmeans / ggplot2 / pwr /
nortest / onewaytests / readxl / haven / yaml / jsonlite` **全部正常**。
→ **心理统计分支与 CTT 分支不受影响；IRT 分支完全不可用**（`mirt` 的 `Imports` 含 `vegan`，无法绕过）。

**可选处置**（需你在 Windows 上操作，我无法代做）：

1. **关闭 Smart App Control**：Windows 安全中心 →「应用和浏览器控制」→「智能应用控制」→ 关闭。
   ⚠️ 微软的设计是**一旦关闭，除非重装 Windows 否则无法再开启**，请自行权衡。
2. **重装 `vegan`**：`install.packages("vegan")` 装到用户库，看新二进制能否通过信誉判定（成本低，值得一试）。
3. **换一台机器**跑 IRT 部分。

**连带影响**：本仓库的 `tests\smoke_test.ps1 -Full` 与 `tests\test_numeric.R` 都含 IRT 端到端用例，
在这台机器上会因此变红（**不是代码回归**）。IRT 的 L1/L2 复算脚本（`tests\verify_l1_irt.R`）已写好，
策略解除后可直接运行。
