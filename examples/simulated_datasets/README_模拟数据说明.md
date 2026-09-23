# Psychostat 模拟数据集使用说明

> **这些数据是怎么来的**：全部由 `scripts/generate_simulated_datasets.R` 按显式参数生成（随机种子 20260912），
> 每个数据集都附带**生成真值**（题目参数、维度归属、被试真能力 θ）。你可以随时改种子重生成：
>
> ```powershell
> Rscript scripts\generate_simulated_datasets.R                  # 全部重生成（同种子结果完全一致）
> Rscript scripts\generate_simulated_datasets.R --seed 2027      # 换一组随机数
> Rscript scripts\generate_simulated_datasets.R --out D:\mydata   # 换输出目录
> ```
>
> **重要**：本目录下的所有 CSV 均为**模拟数据**，不含任何真实被试信息。
> 本目录位于 `examples/` 之下，因此不会被 `scripts\check_sensitive.ps1` 误判为真实数据。

**本文档中的"实测结果"都是用 Psychostat 真实跑出来的数字**，不是理论推测 —— 你可以照着重跑一遍核对。

---

## 0. 总览

| 数据集 | 文件 | 规模 | 结构 / 真值 | 用来试什么 |
|---|---|---|---|---|
| **CTT-A** | `ctt_A_clean_unidimensional_n600_items15.csv` | 600 × 15 | 单维，5 点计分，载荷 .55–.80，无缺失/无反向题 | CTT 入门：信度、EFA、项目分析 |
| **CTT-B** | `ctt_B_full_survey_n500_items20.csv` | 500 × 25 | 3 维（7/7/6 题），因子相关 .30–.40，2 道反向题、注意检验、反应时、效标、已知组、1.5% 缺失 | 完整量表流程 + CFA 验证 + 清洗规则 |
| **CTT-C** | `ctt_C_problem_items_n400_items16.csv` | 400 × 19 | 2 维 + 3 道问题题（无关题 / 双重载荷 / 低载荷），20 人直线作答、18 人注意检验失败、15 人过快、12 人中度缺失、5 人高缺失 | 清洗与"建议删题"机制 |
| **IRT-A** | `irt_A_binary_2pl_n800_items20.csv` | 800 × 20 | 二分（0/1），2PL，a∈[0.8,2.0]、b∈[−2,2] | IRT 入门：模型比较、题目参数、θ 估计 |
| **IRT-B** | `irt_B_polytomous_grm_n600_items15.csv` | 600 × 15 | 有序 1–5，GRM，a∈[0.9,1.9]，每题 4 个阈值 | 多级计分的 IRT（最像真实量表） |
| **IRT-C** | `irt_C_multidimensional_grm_n1000_items24.csv` | 1000 × 24 | 二维 GRM（每维 12 题），维度相关 .45，含小交叉载荷 | MIRT：EIFA 选维度 / CIFA 验证结构 |
| **IRT-D** | `irt_D_binary_missing5pct_n800_items20.csv` | 800 × 20 | 同 IRT-A 结构，随机 5% 单元格缺失 | 三种缺失策略的差异 |
| **IRT-E** | `irt_E_rasch_n500_items15.csv` | 500 × 15 | **真 Rasch**（所有题 a = 1） | 模型比较：BIC 能否认出真模型 |
| **IRT-F** | `irt_F_preflight_problems_n200_items12.csv` | 200 × 12 | 故意含 1 道零方差题（Item10）、1 道全缺失题（Item12）、1 道稀有类别题（Item11） | 数据体检（preflight）报错演示 |
| **CTT-D** | `ctt_D_three_factor_n700_items18.csv` | 700 × 18 | 三因子近似正交（因子相关 .12–.18，每维 6 题），载荷 .57–.78，无缺失/无反向题 | **varimax 正交旋转** + **手动指定因子数**（另两份 EFA 数据都是 promax + auto） |
| **CTT-E** | `ctt_E_dirty_remove_n800_items15.csv` | 800 × 20 | 15 题 5 点（α ≈ .56，**刻意做低**，见 2.5 节）、24 人整卷同选 3、10 人整卷 4/5 堆叠、25 人注意检验失败、20 人作答过快、2% 缺失、**负向效标** | **`straightline_action: remove` / `extreme_action: remove`**（真的删人）+ **`criterion_direction: negative`** |
| **IRT-G** | `irt_G_multidimensional_gpcm_n900_items24.csv` | 900 × 24 | 三维 GPCM（每维 8 题），1–5 计分，维度相关 .30–.40，含小交叉载荷 | **多维 GPCM（MGPCM）**：EIFA 选维 + CIFA 验证（此前没有任何 MGPCM 数据） |
| **IRT-H** | `irt_H_binary_3pl_n1500_items20.csv` | 1500 × 20 | 二分 3PL，a∈[0.8,2.0]、b∈[−2,2]、**猜测 c∈[0.08,0.25]** | **3PL 与猜测参数**：c 能否恢复；忽略 c 按 2PL 拟合会把 b 估偏多少 |
| **IRT-I** | `irt_I_multidimensional_binary_n800_items20.csv` | 800 × 20 | 二维二分（每维 10 题），维度相关 .45，含小交叉载荷 | **二分多维（M2PL）**：此前唯一的 MIRT 数据 IRT-C 是多级 GRM |

每个数据集旁边都有：
- `*_truth.csv`：生成真值（题目参数 / 维度归属 / 反向题标记）
- `*_true_theta.csv`：被试真实能力（IRT 才有）
- `*_config.yaml`：可直接运行的配置（CTT-B / IRT-C / IRT-G / IRT-I 还带对照表文件）

---

## 1. 三种跑法

### 1.1 图形界面（推荐新手）

1. 双击 `启动Psychostat界面.bat`
2. 左侧选 **经典测量理论 CTT** 或 **项目反应理论 IRT**
3. 第 1 步 → 数据来源选"我的数据" → 选择本目录里的 CSV（文件选择框）
4. 按提示选择路线（CTT：quality / efa / cfa）或模型（IRT：auto / rasch / 2pl / grm / mirt）
5. 第 2 步确认摘要 → 开始分析，日志会实时显示

> ⚠️ 用 GUI 跑 **CTT-B / CTT-C / IRT-F** 时，第 3 步（变量设置）请把辅助列的角色设对：
> `attention_check` → 注意检验题，`response_time_sec` → 反应时列，`participant_id` → 被试编号列。
> 否则注意检验题会被当成一道量表题目参与计算（见第 3 节"两个坑"）。

### 1.2 命令行 + 配置文件（推荐，一行就能跑）

```powershell
# CTT（三分支管线脚本直接跑配置）
Rscript scripts\ctt_pipeline.R --config examples\simulated_datasets\ctt_A_config.yaml
Rscript scripts\ctt_pipeline.R --config examples\simulated_datasets\ctt_B_config.yaml
Rscript scripts\ctt_pipeline.R --config examples\simulated_datasets\ctt_C_config.yaml

# IRT
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_A_config.yaml
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_B_config.yaml
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_C_config_eifa.yaml
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_C_config_cifa.yaml
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_D_config_missing_none.yaml
Rscript scripts\irt_generic_pipeline.R --config examples\simulated_datasets\irt_E_config.yaml

# IRT 数据体检（只体检、不拟合）
Rscript scripts\irt_preflight.R --config examples\simulated_datasets\irt_F_config.yaml
Rscript scripts\irt_preflight.R --config examples\simulated_datasets\irt_F_config_explicit_items.yaml
```

结果会写到 `outputs\<标签>_<分支>_<时间戳>\`（配置里已设为 `../../outputs`）。

### 1.3 启动器（带环境检查、自动装包、Word 结果报告）

```powershell
.\run_ctt_analysis.ps1 -Config .\examples\simulated_datasets\ctt_B_config.yaml
.\run_irt_analysis.ps1 -Config .\examples\simulated_datasets\irt_A_config.yaml
```

---

## 2. 逐个数据集：真值、跑法、实测结果

### 2.1 CTT-A：干净单维量表（入门首选）

- **数据**：`ctt_A_clean_unidimensional_n600_items15.csv`（600 人 × 15 题，1–5 计分，无缺失）
- **真值**：单因子；题目载荷从 .80 递减到 .55（见 `ctt_A_truth.csv`）
- **跑法**：`ctt_A_config.yaml`（`goal: efa`）

**实测结果（N = 600，清洗后 600/600 保留，无缺失、无删除）**

| 指标 | 实测值 | 说明 |
|---|---|---|
| Cronbach's α | **.9187**，95% CI [.9092, .9281] | 载荷 .55–.80 的直接结果 |
| McDonald's ω | **.9194** | 与 α 接近，说明基本满足 τ 等价 |
| 直线作答标记 | 3 人（未删除，只标记） | 极端低能力者可能整卷同选一项 |
| KMO / Bartlett | **.9716** / χ²(105) = 3765, *p* < .001 | 适切性极好 |
| EFA 因子数（平行分析） | **1**（MR1），解释 43.6% 方差 | 与真值一致 |
| CR（决断值）范围 | 15.97 – 31.74 | 全部远超 3.0 |
| CITC 范围 | .505 – .732 | 全部 > .30 |

> **观察点**：`04_efa_rotated_loadings.csv` 的 `primary_loading` 应与 `MR1` 完全一致、且逐题不同
> （极差 ≈ 0.24），`suggest_delete` 全为 `FALSE`，`04_efa_deletion_history.csv` 只有表头。
> 这正是"干净单维数据不应该有任何删题建议"的验收标准——它曾经因为一个只在单因子解发作的矩阵退化
> bug 而误报 Item01，现已修复（见第 3 节与 「内部问题清单」 P1-11）。

### 2.2 CTT-B：完整问卷（三维 + 反向题 + 效标 + 已知组）

- **数据**：`ctt_B_full_survey_n500_items20.csv`（500 人 × 20 题 + 5 个辅助列）
  - `Item01–Item20`：3 维（F1 = Item01–07，F2 = Item08–14，F3 = Item15–20），因子相关 .30–.40
  - **反向计分题：Item07 与 Item15**（配置里已声明 `reverse_items`）
  - 辅助列：`participant_id`、`attention_check`（3% 故意答错）、`response_time_sec`（2% 过快）、`criterion`（效标）、`known_group`（两组）
  - 1.5% 随机缺失
- **真值**：`ctt_B_truth.csv`（题目 → 维度、真载荷、是否反向题）
- **对照表**：`ctt_B_cfa_mapping.csv`
- **跑法**：`ctt_B_config.yaml`（`goal: cfa`；改成 `efa` 可探索结构）

**实测结果**

| 指标 | 实测值 |
|---|---|
| 清洗 | 500 → **475**（删除 25：注意检验失败 15 + 过快作答 10） |
| 反向计分 | 正确识别并反转 **Item07; Item15** |
| 总量表 α / ω | **.8493 / .8502**，CI [.8295, .8691] |
| F1 / F2 / F3 α | **.8351 / .7914 / .7574**（`source` 列标为 `CFA-mapping`） |
| CFA 拟合 | χ²(167) = **114.3**，χ²/df = **0.68**，CFI = **1.00**，TLI = **1.01**，RMSEA = **0**，SRMR = **.036** |
| 标准化载荷 | 最低 **.525**，全部 > .50 |
| CR（组合信度） | F1 **.860** / F2 **.822** / F3 **.788**（全部 > .70） |
| AVE | F1 **.469** / F2 **.400** / F3 **.385**（**全部 < .50**，工具已如实标 `FALSE`） |
| 判别效度（Fornell-Larcker） | 因子相关 .350–.491，√AVE > 相关 → 通过 |
| 效标关联效度 | *r* = **.579**，*p* < .001，方向符合预期 |
| 已知组效度 | Welch *t*(467.5) = **15.82**，*p* < .001，Cohen's *d* = **1.45** |
| 修正指数（`06_cfa_modification_indices.csv`） | 最大 MI ≈ **8.25**（F3 =~ Item02），提示可关注但幅度很小 |

> **观察点**：
> 1. **AVE < .50 但 CR > .70** 是这套数据的典型结果（载荷 .53–.75 时 AVE 自然偏低）。这正好用来讲清
>    "CR 看的是整体信度，AVE 看的是收敛效度"的差别，以及 AVE < .5 时 Fornell-Larcker 判定要谨慎。
> 2. WLSMV（有序分类变量估计）下 **χ² 的 p、AIC、BIC 显示为 NA**——这是估计方法本身不提供这些量，
>    不是工具漏算；报告时用 CFI/TLI/RMSEA/SRMR 即可。

### 2.3 CTT-C：问题数据（清洗 + 建议删题演示）

- **数据**：`ctt_C_problem_items_n400_items16.csv`（400 人 × 16 题 + 3 个辅助列）
  - 正常的 13 题 + **3 道问题题**：`Item07`（与所有题几乎无关）、`Item08`（同时载荷两个因子）、`Item16`（载荷偏低）
  - 脏作答：**20 人直线作答**（每题同一选项）、**18 人注意检验失败**、**15 人作答过快**、**12 人中度缺失（5–20%）**、**5 人高缺失（> 20%）**
- **真值**：`ctt_C_truth.csv`
- **跑法**：`ctt_C_config.yaml`（`goal: efa`）

**实测结果**

| 指标 | 实测值 |
|---|---|
| 清洗 | 400 → **364**（删除 36：注意检验失败 18 + 过快 15 + 高缺失 5，有少量重叠） |
| 只标记不删除 | 直线作答 **20** 人、极端值 **0** 人 |
| 建议删题清单 | `Item07`（主载荷 < .40、共同度 < .20）、`Item16`（主载荷 < .40、共同度 < .20）、`Item08`（**交叉载荷**） |
| 三道问题题的实际载荷 | Item07 主载荷 **.225** / 共同度 **.047**；Item08 主载荷 **.432**（交叉）；Item16 主载荷 **.214** / 共同度 **.114** |

> **观察点**：ES 里那 3 道坏题被**准确识别**，而且工具**只标注、不自动删题**，
> 全 16 题仍进入信度与 EFA 结果。请结合内容效度判断是否真的删——这是"用数据挑题会高估信度"的现实版本。

### 2.4 CTT-D：三因子近似正交（varimax + 手动指定因子数）

**一句话**：结构接近正交时该用 varimax；因子数由设计确定时直接写死，不必交给平行分析。

| 项 | 内容 |
|---|---|
| 文件 | `ctt_D_three_factor_n700_items18.csv`（700 × 18，5 点计分，无缺失、无反向题） |
| 真值 | `ctt_D_truth.csv`：每题的维度归属与生成载荷（.57–.78） |
| 结构 | 3 因子 × 6 题，因子间相关 **.12–.18**（近似正交） |
| 配置 | `ctt_D_config.yaml` → `goal: efa`、`rotation: varimax`、`n_factors: 3` |
| 跑法 | `Rscript scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_D_config.yaml` |

**实测结果**（种子 20260912）：

| 指标 | 实测值 | 说明 |
|---|---|---|
| Cronbach's α | **.7529**，95% CI [.7258, .7801] | 18 题总量表 |
| McDonald's ω | **.7574** | 与 α 接近 |
| KMO / Bartlett | **.8546** / χ²(153) = 3434.35, *p* < .001 | 适切性良好 |
| 提取因子数 | **3**（与配置一致） | 累积解释 41.6% 方差 |
| 分量表 α | MR1 **.832** / MR2 **.787** / MR3 **.794** | 三个因子各 6 题 |
| **结构恢复** | **18/18 题归属与真值完全一致** | MR1↔F1、MR2↔F2、MR3↔F3 |
| 建议删题 | **0 题** | 简单结构干净 |

**教学点**：把 `rotation` 改成 `promax`、`n_factors` 改成 `auto` 再跑一次，对比旋转方式与因子数决定方式
对结果的影响——这正是另外两份 EFA 数据（CTT-A / CTT-C）用的设置。

---

### 2.5 CTT-E：脏作答"真的删掉" + 负向效标

**一句话**：`flag`（只标记）与 `remove`（直接删人）的结果差异有多大；负向效标该怎么判方向。

| 项 | 内容 |
|---|---|
| 文件 | `ctt_E_dirty_remove_n800_items15.csv`（800 × 20） |
| 真值 | `ctt_E_truth.csv`：每题的载荷，并在 `injected_dirty` 列写明**注入的脏作答人数** |
| 配置 | `ctt_E_config.yaml` → `straightline_action: remove`、`extreme_action: remove`、`criterion_direction: negative` |
| 跑法 | `Rscript scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_E_config.yaml` |

**注入的脏作答**（两组刻意设计成互不干扰，便于分别核对删对了谁）：

- **直线作答 24 人**：整卷同选 3 → 总分落在均值附近，因此**只会**被直线作答规则命中
  （若整卷同选 1 或 5，会把总分 SD 从 ~9 抬到 ~13，反而让极端值规则失效——见下）
- **极端作答 10 人**：整卷 4/5 堆叠 → 被 `|z|>3` 与 `1.5×IQR` 命中
- 注意检验失败 25 人、作答过快 20 人、2% 随机单元格缺失

**实测结果**：

| 指标 | 实测值 | 说明 |
|---|---|---|
| 清洗 | 800 → **721**，删 79 人 | 直线作答 24、极端值 11、注意失败 25、过快 20（有重叠） |
| 全局缺失率 | 2.04%（中位数插补） | `missing_5_to_20: median_impute` |
| Cronbach's α | **.5579** | ⚠️ **刻意做低**，见下方说明 |
| 效标效度 | *r* = **−.385**, *p* < .001；`direction_matches` = **TRUE** | 负向效标：量表分越高、效标越低 |
| 已知组效度 | Welch *t*(717.5) = **16.08**, *p* < .001, Cohen's *d* = **1.20** | High vs Low |

**为什么这份数据的 α 只有 .56？**（这不是 bug，是刻意设计）

k 题 K 点量表上，总分 |z| 的理论上限约为 `2/√(2·r̄)`（r̄ = 题间平均相关）。
只要 α ≥ .70（r̄ ≳ .15），上限就只有 **~3.0**，而离群个案自己还会把 SD 抬高，
于是 **`|z|>3` 在 15 题 5 点量表上几乎不可能触发**；IQR 上界也会超过量表满分。

我们可以实测验证这一点：把载荷调回 .55–.78（与 CTT-A 同级）重新生成后跑本配置，得到

| 载荷 | 总分 SD | `|z|>3` 上界 | `1.5×IQR` 上界 | 满分 | 命中的极端值人数 |
|---|---|---|---|---|---|
| .55–.78（α ≈ .90） | 13.4 | **91.0** | **91.5** | 75 | **0**（两条规则都够不着） |
| .18–.48（α ≈ .56，本数据集） | ~9 | 74.7 | ~72 | 75 | **11** |

所以本数据集把载荷压到 .18–.48，只为让 `extreme_action: remove` 这条分支真的被执行到。
**这条经验对真实数据同样成立**：信度高的量表上，"按总分 |z|>3 找极端个案"基本是无效操作，
应改用 IQR 规则、分维度查看，或直接看箱线图。

---

### 2.6 IRT-A：二分 2PL（IRT 入门）

- **数据**：`irt_A_binary_2pl_n800_items20.csv`（800 人 × 20 题，0/1）
- **真值**：`irt_A_truth.csv`（每题 a、b）；`irt_A_true_theta.csv`（每人真 θ）
- **跑法**：`irt_A_config.yaml`（`model: auto`，按 BIC 在 rasch / 2pl 之间选）

**实测结果**

| 指标 | 实测值 | 真值 |
|---|---|---|
| 自动选择的模型 | **2PL** | 2PL ✓ |
| M2\* 绝对拟合 | **217.1**, df = 170, *p* = .0085, RMSEA = **.019**, CFI = **.992**, TLI = **.991** | 拟合良好 |
| 恢复的区分度 a | **0.884 – 2.226** | 0.8 – 2.0 |
| θ 估计（MAP） | N = 800，均值 **0.011**，SD **0.904** | 真值 SD 1.04 |
| **θ 参数恢复** | **r = .926**，回归斜率 **.799** | — |

> **观察点**：θ 估计的 SD（0.904）小于真值 SD（1.04）、回归斜率 < 1，这是 **MAP 估计的先验收缩**（正常现象）。
> 参数恢复 r = .93 说明"题目参数 + 能力估计"整体恢复了生成机制。

### 2.7 IRT-B：有序多级 GRM（最像真实量表）

- **数据**：`irt_B_polytomous_grm_n600_items15.csv`（600 × 15，1–5 计分）
- **真值**：`irt_B_truth.csv`（a 与 4 个阈值 b1–b4）；`irt_B_true_theta.csv`
- **跑法**：`irt_B_config.yaml`（`model: grm`）

**实测结果**

| 指标 | 实测值 | 真值 |
|---|---|---|
| M2\* 拟合 | **43.2**, df = 45, *p* = .548, RMSEA = 0, CFI = 1.00 | 极好 |
| 恢复的 a | **0.812 – 1.865** | 0.9 – 1.9 |
| 恢复的第一个阈值 b1 | **−2.146 – 0.735** | −2.2 – 2.2 |
| **θ 参数恢复** | **r = .918**，斜率 **.852** | — |

### 2.8 IRT-C：二维 GRM（EIFA 选维度 / CIFA 验证结构）

- **数据**：`irt_C_multidimensional_grm_n1000_items24.csv`（1000 × 24，每维 12 题，含小幅交叉载荷）
- **真值**：`irt_C_truth.csv`（a1、a2、主维度、4 个阈值）；`irt_C_true_theta.csv`（两维真 θ，相关 **.45**）
- **对照表**：`irt_C_loading_matrix.csv`

**跑法一（探索 EIFA）**：`irt_C_config_eifa.yaml`（`dimension_range: 1-3`）

| 模型 | BIC | CFI | RMSEA | 结论 |
|---|---|---|---|---|
| **2 维（EIFA_2D）** | **56679** | 1.000 | ≈ 0 | **被选中 ✓** |
| 3 维（EIFA_3D） | 56795 | 1.000 | ≈ 0 | 次优 |
| 1 维（EIFA_1D） | 57577 | 0.610 | .080 | 明显不拟合 |

估计的维度相关：**0.519**（真值 .45）；θ 分数相关：**0.621**。

**跑法二（验证 CIFA）**：`irt_C_config_cifa.yaml`（按载荷矩阵固定 2 维结构）

| 对比 | 结果 |
|---|---|
| ΔCFI（2 维 − 1 维） | **+0.385** |
| ΔRMSEA | **−0.070**（.0798 → .0098） |
| ΔAIC / ΔBIC | **−1015 / −1010**（都偏向 2 维） |
| 载荷显著性 | **24/24** 全部显著（*p* < .05） |
| 估计的因子相关 | **0.546**（真值 .45） |
| 两个维度与真值轴的最大 \|r\| | **.906 / .912** |

> **观察点**：EIFA 与 CIFA 给出**一致**的结论（2 维、维度间中等相关），这是最理想的教学示范——
> 探索与验证相互印证。注意 CIFA 的因子相关（.546）略高于真值（.45），属抽样波动范围。

### 2.9 IRT-D：缺失值三种策略（差异可能超出你的预期）

- **数据**：`irt_D_binary_missing5pct_n800_items20.csv`（在 IRT-A 结构上随机删掉 **5% 单元格**）
- **三份配置**：`irt_D_config_missing_none.yaml` / `_listwise.yaml` / `_pairwise.yaml`

**实测结果**

| 策略 | 进入估计的 N | 全缺失剔除 | listwise 删除 | θ 均值 |
|---|---|---|---|---|
| `none`（默认） | **800**（全部保留） | 0 | 0 | 0.0114 |
| `listwise` | **291** | 0 | **509（64%）** | 0.0091 |
| `pairwise` | **800** | 0 | 0 | 0.0114（与 none 完全相同） |

> **观察点（本数据包最有教学价值的一条）**：只有 5% 的单元格缺失，**listwise 却删掉了 64% 的被试**——
> 因为"20 道题里一道都没漏"的概率只有 0.95²⁰ ≈ 36%。这就是为什么现代 IRT 默认用观测反应似然（`none`），
> 而不是整例删除。同时请留意：`pairwise` 与 `none` 在计算结果上**完全等价**（工具文档已明确说明）。

### 2.10 IRT-E：真 Rasch（模型比较教学）

- **数据**：`irt_E_rasch_n500_items15.csv`（500 × 15，**所有题真 a = 1**）
- **真值**：`irt_E_truth.csv`；`irt_E_true_theta.csv`
- **跑法**：`irt_E_config.yaml`（`compare_models: [rasch, 2pl]`）

**实测结果**

| 模型 | logLik | AIC | BIC | 是否被选 |
|---|---|---|---|---|
| **rasch** | **−4174** | 8381 | **8448** | ✅ **选中** |
| 2pl | −4170 | 8399 | 8525 | ✗ |

θ 参数恢复：**r = .860**，斜率 **.689**。

> **观察点**：数据由真 Rasch 生成时，**BIC 正确选择了更简约的 Rasch 模型**（2PL 虽然 logLik 稍高，但多了 15 个自由度，
> 被 BIC 惩罚）。这就是"模型选择要惩罚复杂度"的直观演示。

### 2.11 IRT-F：数据体检（preflight）

同一份问题数据、两份配置，结果完全不同：

| 配置 | 结果 |
|---|---|
| `irt_F_config.yaml`（`item_columns: auto`） | **status = warning**，`fatal = []`；自动识别的题目只有 **10 列**——**Item10（零方差）与 Item12（全缺失）被静默排除**，只报了"Item11 存在极少使用的反应类别" |
| `irt_F_config_explicit_items.yaml`（显式列出 12 列） | 退出码 **2**，`status = fatal` |

> **这是本数据包暴露的第二个工具缺陷**：
> 1. **自动识别会静默丢弃**零方差列与全缺失列，导致 preflight 里那两条 fatal 检查**永远触发不了**（除非显式列出题目列）；
> 2. 显式列出时虽然拦住了，但**报错文案是错的**：会说"题目列中含非计分类型（因子/逻辑）：**NA**"——
>    真实原因是"整列全缺失"被 `read.csv` 读成了逻辑型，而且列名占位符打不出来（见 「内部问题清单」 P1-12）。
>
> 演示目的：让你看到"体检 → 报错 → 修正数据"的完整链路应该怎么走；现实里跑真实数据前**务必先看体检结果**。

---

### 2.12 IRT-G：三维 GPCM（MGPCM）

**一句话**：多级 Likert 数据的**多维**版本——此前的 IRT-C 是多维但用 GRM，本数据集专门覆盖多维 GPCM。

| 项 | 内容 |
|---|---|
| 文件 | `irt_G_multidimensional_gpcm_n900_items24.csv`（900 × 24，1–5 计分） |
| 真值 | `irt_G_truth.csv`：维度归属、主维度区分度 `a_primary`、四个台阶 `b1…b4`；`irt_G_true_theta.csv`：真能力 |
| 结构 | 3 维 × 8 题，维度相关 .30–.40，含小交叉载荷（0–.18） |
| 配置 | `irt_G_config_eifa.yaml`（3D EIFA）、`irt_G_config_cifa.yaml`（3D CIFA，配 `irt_G_loading_matrix.csv`） |

**实测结果**（种子 20260912）：

| 指标 | EIFA | CIFA |
|---|---|---|
| 选中模型 | **3D EIFA-GPCM** | **3D CIFA-GPCM** |
| 区分度 a 恢复（a_primary vs MDISC） | *r* = **.869** | *r* = **.850** |
| 台阶 b₁…b₄ 恢复（24 题 × 4 台阶 = 96 个值） | *r* = **.995**，RMSE = **.125** | *r* = **.995**，RMSE = **.119** |
| θ 恢复（F1 / F2 / F3） | *r* = .407 / .486 / .395 | *r* = **.943 / .933 / .941**（SE ≈ .31） |

> **θ 的那一行怎么读**：EIFA 是**探索性**的，因子会经过斜交旋转，其因子顺序/取向与生成时的 F1/F2/F3
> 并不一一对应，所以"逐因子比 r"没有意义（这份数据里它只有 .4 左右）；要逐因子核对 θ，
> 请看 **CIFA** 那一列（结构被对照表固定，r 都在 .93 以上）。题目参数的恢复（a 与台阶 b）两者都好。

**台阶 b 的口径提醒**：GPCM 的 mirt 参数是**类别截距** d_k，标准台阶难度是相邻截距之差
`b_k = -(d_k - d_{k-1})/MDISC`。工具输出的 `b_d1…b_d4` 就是这个台阶量，与真值可直接比对。
多维情形下 mirt 自己的 `coef(IRTpars=TRUE)` 对 GPCM 返回 `NA`，因此这里没有第三方参照，
只能拿生成真值核对——上表的 *r* = .995 就是这么来的。

---

### 2.13 IRT-H：二分 3PL（含猜测参数）

**一句话**：标准的"选择题考试"模型；顺便看清**猜测参数 c 到底有多难估**，以及忽略它会有什么后果。

| 项 | 内容 |
|---|---|
| 文件 | `irt_H_binary_3pl_n1500_items20.csv`（1500 × 20，0/1） |
| 真值 | `irt_H_truth.csv`：a∈[0.8,2.0]、b∈[−2,2]、**c∈[0.08,0.25]** |
| 配置 | `irt_H_config.yaml`（比较 2PL 与 3PL）、`irt_H_config_ignore_guess.yaml`（同一数据只按 2PL 拟合） |

**实测结果**：

| 指标 | 按 **3PL** 拟合 | 按 **2PL** 拟合（忽略猜测） |
|---|---|---|
| a 恢复 | *r* = **.770**，RMSE = .363 | *r* = .536，RMSE = .488 |
| b 恢复 | *r* = **.964**，RMSE = .349，**平均偏差 +.061** | *r* = .986，RMSE = .361，**平均偏差 −.285** |
| **c 恢复** | ***r* = −.406**，RMSE = .139 | —（模型没有 c） |
| c 均值 | 真值 **.168** vs 恢复 **.171**（均值很准） | — |
| θ 恢复 | *r* = **.874**，平均 SE = .457 | *r* = .874，平均 SE = .484 |
| BIC（并列比较表） | **33641.5** | **33561.2 ← 2PL 的 BIC 更低** |

**两个值得讲的教学点**：

1. **忽略猜测会把难度系统性低估**：2PL 下 b 的平均偏差是 **−0.285 logit**（3PL 只有 +.061）。
   也就是说，低能力者"猜对"被当成了"这题没那么难"。
2. **BIC 不一定会替你选出真模型**：这份数据**确实是按 3PL 生成的**，20 个额外的猜测参数带来的惩罚
   超过了 3PL 的拟合改善，因此**并列比较表里 BIC 更低的是 2PL**（33561.2 < 33641.5）。
   注意 `irt_H_config.yaml` 里写的是 `model: 3pl`（显式指定），所以工具仍按 3PL 出结果
   （日志 `Selected model: 3PL`；`*_model_recommendation.csv` 的 `Selected` 列也标在 3pl 上）；
   **如果你把 `model` 改成 `auto` 交给 BIC 决定，这份数据会被判成 2PL。**
   这正解释了文献里"3PL 需要 N≥1000 甚至更多"的说法——本数据 N=1500 仍不足以让 BIC 站到 3PL 这边。
   同时注意 **c 的个体恢复是失败的（r = −.406）**：均值无偏，但"哪道题更容易被猜对"排不出来。
   报告里若要写逐题的 c，请标明它是弱识别的参数。

---

### 2.14 IRT-I：二维二分（M2PL）

**一句话**：二分题目的多维情形——此前唯一的 MIRT 数据 IRT-C 是多级 GRM，二维二分一直没数据。

| 项 | 内容 |
|---|---|
| 文件 | `irt_I_multidimensional_binary_n800_items20.csv`（800 × 20，0/1） |
| 真值 | `irt_I_truth.csv`：维度归属、`b`、`a_primary`；`irt_I_true_theta.csv`：真能力 |
| 结构 | 2 维 × 10 题，维度相关 **.45**，含小交叉载荷（0–.20） |
| 配置 | `irt_I_config_eifa.yaml`（2D EIFA）、`irt_I_config_cifa.yaml`（2D CIFA + `irt_I_loading_matrix.csv`） |

**实测结果**：

| 指标 | EIFA | CIFA |
|---|---|---|
| 选中模型 | **2D EIFA-2PL（M2PL）** | **2D CIFA-2PL（M2PL）** |
| b 恢复 | *r* = **.995**，RMSE = .106 | *r* = **.994**，RMSE = .107 |
| θ 恢复（F1 / F2） | *r* = .605 / .612 | *r* = **.870 / .874**（SE ≈ .45） |

与 IRT-G 同一个规律：**题目参数两者都好，θ 要逐因子看就必须用 CIFA**。

---

## 3. 三个曾经踩到的坑（均已修复，保留说明作为背景）

### 坑 1（已修复）：注意检验题曾被当成一道量表题目

如果不声明 `attention_item`，`attention_check` 这种"取值 1–5 的整数列"曾会被自动识别为一道题目，
参与 α、EFA 等所有计算（实测：同一份模拟数据总量表 α 从 **.8086 掉到 .7453**，题目数 15 → 16）。

**现在的行为**：`check|attention|verify|careless|valid` 与中文 `注意|检验|甄别|作答` 已纳入自动识别的
守卫名单，未声明时**直接报错**并提示你显式指定题目列或声明 `attention_item`。
本目录的 CTT-B / CTT-C 配置都已写 `cleaning.attention_item: attention_check` + `attention_correct_value: 3`。

### 坑 2（已修复）：单因子解时 EFA 的"建议删题"曾不可信

单维量表（单因子解）下，`primary_loading` 列曾退化成常数，并出现**假阳性**的 `cross_loading`
建议删题（实测 CTT-A 的 Item01 被误标）；同时真正的低载荷题会因为判定失效而漏报。
根因是 `apply`/`vapply` 在"每行只返回 1 个值"时都会退化成向量。现已在 `ctt_pipeline.R` 改为显式分支处理。

### 坑 3（已修复）：零方差 / 全缺失列曾被静默丢弃

IRT 的题目自动识别只接受"非缺失唯一值 ≥ 2"的整数列，因此整列常量与整列全缺失的题会被**静默排除**，
数据体检里对应的两条 fatal 检查也就永远触发不了（IRT-F 正是为此准备的演示数据）。

**现在的行为**：这两类列会被显式打印出来，并写进 preflight JSON 的 `excluded_degenerate_columns`
字段；若你**显式列出**题目列，则会直接报"以下题目列整列全缺失：Item12"并给出正确列名。

---

*以上三条的详细复现与验收标准见 「内部问题清单」 的 P1-11 / P1-12 / P1-13。*

---

## 4. 建议的练习任务

1. **（入门）** 跑 CTT-A，把 `03_reliability.csv` 的 α 与 `ctt_A_truth.csv` 的载荷对比：为什么载荷越高 α 越大？
2. **（入门）** 跑 IRT-A，打开 `*_item_parameters.csv`：哪道题区分度最低？哪道题最难（b 最大）？与真值对比。
3. **（进阶）** 跑 CTT-B 的 `quality` / `efa` / `cfa` 三条路线，比较：三条路线各自能回答什么问题？为什么 EFA 与 CFA 不能在同一批数据上连做？
4. **（进阶）** 跑 IRT-D 的三种缺失策略，把 `*_missingness_summary.csv` 与 `*_ability_summary.csv` 的 N 抄下来，解释 listwise 为什么删了 64%。
5. **（进阶）** 跑 IRT-E，把 `model_comparison.csv` 的 BIC 抄下来，解释为什么 logLik 更高的 2PL 反而落选。
6. **（挑战）** 用 `--seed 2027` 重新生成数据，再跑一遍 IRT-C 的 EIFA：维度数还选得对吗？维度相关估计变成多少？（重复 5 个种子，感受抽样波动）
7. **（挑战）** 打开 `scripts/generate_simulated_datasets.R`，把 CTT-A 的载荷从 `.80–.55` 改成 `.45–.30`，重生成后看 α 掉到多少、EFA 还能不能得到单因子解。

---

## 5. 文件清单

```
examples\simulated_datasets\
├─ README_模拟数据说明.md                      ← 本文件
├─ ctt_A_clean_unidimensional_n600_items15.csv  + ctt_A_truth.csv + ctt_A_config.yaml
├─ ctt_B_full_survey_n500_items20.csv           + ctt_B_truth.csv + ctt_B_cfa_mapping.csv + ctt_B_config.yaml
├─ ctt_C_problem_items_n400_items16.csv         + ctt_C_truth.csv + ctt_C_config.yaml
├─ ctt_D_three_factor_n700_items18.csv          + ctt_D_truth.csv + ctt_D_config.yaml
├─ ctt_E_dirty_remove_n800_items15.csv          + ctt_E_truth.csv + ctt_E_config.yaml
├─ irt_A_binary_2pl_n800_items20.csv            + irt_A_truth.csv + irt_A_true_theta.csv + irt_A_config.yaml
├─ irt_B_polytomous_grm_n600_items15.csv        + irt_B_truth.csv + irt_B_true_theta.csv
│                                               + irt_B_config.yaml + irt_B_config_gpcm.yaml
├─ irt_C_multidimensional_grm_n1000_items24.csv + irt_C_truth.csv + irt_C_true_theta.csv
│                                               + irt_C_loading_matrix.csv
│                                               + irt_C_config_eifa.yaml + irt_C_config_cifa.yaml
├─ irt_D_binary_missing5pct_n800_items20.csv    + irt_D_truth.csv
│                                               + irt_D_config_missing_{none,listwise,pairwise}.yaml
├─ irt_E_rasch_n500_items15.csv                 + irt_E_truth.csv + irt_E_true_theta.csv + irt_E_config.yaml
├─ irt_F_preflight_problems_n200_items12.csv    + irt_F_config.yaml + irt_F_config_explicit_items.yaml
├─ irt_G_multidimensional_gpcm_n900_items24.csv + irt_G_truth.csv + irt_G_true_theta.csv
│                                               + irt_G_loading_matrix.csv
│                                               + irt_G_config_eifa.yaml + irt_G_config_cifa.yaml
├─ irt_H_binary_3pl_n1500_items20.csv           + irt_H_truth.csv + irt_H_true_theta.csv
│                                               + irt_H_config.yaml + irt_H_config_ignore_guess.yaml
└─ irt_I_multidimensional_binary_n800_items20.csv + irt_I_truth.csv + irt_I_true_theta.csv
                                                + irt_I_loading_matrix.csv
                                                + irt_I_config_eifa.yaml + irt_I_config_cifa.yaml
```

---

*生成脚本：`scripts/generate_simulated_datasets.R`（可重复运行；脚本已把 CSV 行尾统一成 LF，
同一平台上重新生成的产物与仓库里的**字节一致**）｜本文档中的实测结果对应 v0.1.0；
若你修改了代码或重新生成了数据，数字可能略有变化，请以你自己的运行结果为准。*
