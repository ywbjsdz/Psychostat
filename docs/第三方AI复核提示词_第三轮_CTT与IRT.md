# 第三轮交接：我方对第二轮报告的复核结论 + 第三轮任务（G1–G3）

> **怎么发**：Codex 有文件访问，**直接让它读本文件**即可，不必粘贴：
> `docs/第三方AI复核提示词_第三轮_CTT与IRT.md`
>
> **轮次定义**（此前编号不一致，此处统一）：
> **第 1 轮** = ZCode／GLM-5.3（数值层，50 条主张全一致）；
> **第 2 轮** = Codex／GPT-5.6 Terra（换靶子 G1–G5）；
> **第 3 轮** = 本轮：Codex 补做 G1–G3，并回应第一部分我方的复核结论。
>
> **本轮性质**：这是**补作业轮**，不是新的对抗式复核。第 2 轮的 G4/G5 已被我方核验并采纳，
> 不必重做；本轮只收口 G1/G2/G3 三个洞。

---

## 第一部分　我方对第二轮报告的复核结论（**请先读，避免重复或推翻已确认的部分**）

### 1.1 已由我方独立核验：你报告的数字**全部属实**

| 你的报告 | 我方核验结果 |
|---|---|
| ctt_B 清洗 500 → 475（注意检验 15、过快 10） | ✓ `01_case_cleaning_audit.csv` 500 行、`01_cleaned_items.csv` 475 行 |
| G5：`Empirical_rxx` = .7676944 / .7182545 / .8552893 / .7483760 | ✓ 从 `*_reliability.csv` 与 `*_ability_estimates.csv` 逐位复算，**完全吻合** |
| G5：近似式分别低 +.07030 / +.11052 / +.02448 / +.08460 | ✓ 同上，四个差值逐位吻合 |
| G4：CIFA BIC 12967.51 < 单维 13258.22 | ✓ CSV 为 12967.5060557911 / 13258.2193592843 |
| G4：零方差 CTT 报告 α=−.141、KMO=.521、Bartlett p=.239 | ✓ CSV 为 −0.141408345 / 0.520840790 / 0.238952540 |
| G2：20 个载荷 max\|diff\|=4.44e-16、RMSE=2.85e-16 | ✓ 与你的 `G2_same_estimator_metrics.csv` 一致 |
| 未越出白名单、未改核心代码、未污染 `outputs/` | ✓ `git status` 与 `find outputs -newermt` 均确认 |

**G4 与 G5 已被我方采纳为本轮新增证据**，写入项目校对记录第 11 节。
你的**方法论纪律**（明确标"未完成/partial/无法判定"、拒绝"进入函数即完成"、拒绝"同引擎重跑即独立"、
留下脚本与 `sessionInfo`）比第 1 轮更规范，特此记录。

### 1.2 需要改判：那条"中等发现"**不是产品缺陷**

你报告："IRT 输出未保留模型对象，导致拟合指标无法独立审计"，归类为「工具输出设计 / 可审计性缺口」。
**该结论不成立**，请在本轮报告中**撤回**，理由三条：

1. **工具默认就保存模型对象。** `scripts/irt_generic_pipeline.R:270` 为
   `if(isTRUE(cfg$output$save_model_object %||% TRUE)) saveRDS(chosen$fit, fn("selected_model","rds"))`
   —— **默认 TRUE**。所有 `examples/simulated_datasets/irt_*_config.yaml` 都设 `true`，
   这些目录里确实存在 `*_selected_model.rds`（例：`irt_analysis_grm_20260918_091608`、
   `irt_analysis_mirt_cifa_20260918_091928`，均已核实）。
2. **你检查的三个目录没有 `.rds`，是因为那三份夹具显式设了 `"save_model_object": false`**
   （`tests/e2e_cifa_mgrm.json`、`tests/e2e_gpcm.json`、`tests/e2e_irt_small_n.json`）——
   它们是为冒烟测试刻意轻量化的夹具。而这三份夹具是**我方在第 2 轮提示词的白名单里
   为 G4（需要 docx/html 报告）挑选的**：挑 G4 的材料，把 G3 的材料挑没了。
   → **归因是我方材料清单的失误，不是工具设计问题。**
3. **你建议的补救无法达成独立性。** 在保存的 mirt 对象上再调 `mirt::M2` 是**同一引擎**，
   而你在同一份报告里已写明"不能把同一 mirt 路径重跑称为独立复算"——**两者自相矛盾**。
   要独立复算 `M2*`/`SRMSR` 必须在**第二引擎里重拟合**（TAM / sirt），保存 mirt 对象不能解决。

因此：**本项目至今没有任何已证实的缺陷**（两轮、三方复核合计）。
所有已发现问题都落在**我方的校对脚本/文档**（第 1 轮 5 处，已修）与**我方的材料清单**（第 2 轮 1 处，已归因）。

### 1.3 我方补充实测：TAM 多维 GPCM 的可行性（供你直接使用）

你第 2 轮在 G1 上只留下了 `G1_TAM_execution_marker.txt`。我方进一步测了规模边界
（`TAM::tam.mml.2pl(..., irtmodel="GPCM")`，`irt_G` 数据）：

| 规模 | 实测结果 |
|---|---|
| 1 维 × 8 题 | **0 秒**成功，返回 `B`、`AXsi` |
| 2 维 × 16 题（n=200） | **2 秒**成功，`B` 为 16×6×2 |
| 3 维 × 24 题（n=150） | **380 秒未完成**（进程被杀，日志停在该步） |

→ 多维 GPCM 在 TAM 里 **2 维可行、3 维不收敛**。这直接决定了本轮 G1 的两条路线（见 2.1）。

### 1.4 第二轮净结果

G4、G5 完成并被采纳；G1 未完成、G2 为"同估计器复现"（只能证明清洗、模型语法与估计口径的转写无误，
**不能**替代独立实现）、G3 无法判定。故本轮范围 = 这三项。

---

## 第二部分　第三轮任务（只做 G1/G2/G3）

### 2.0 三条明令（都来自第 2 轮的教训）

1. **"进入函数"不算完成。** 不得以 marker 文件、空 CSV 或"函数被调用"代替参数对照。
2. **"同一引擎重跑"不算独立复算。** 用 `mirt`/`lavaan` 再跑一遍，无论换多少参数，
   都不是独立实现。独立实现的清单：`TAM`、`sirt`、`OpenMx`、`semTools`、`ltm`、`stats::factanal`。
3. **不可行时给出"可行性测量"，而不是留空。** 格式照 1.3：规模 × 耗时 × 是否返回参数 × 卡在哪一步。
   "我试了但没成功"不算结论，"在 X 规模下 Y 秒内未返回、原因是 Z"才算。

### 2.1 G1（最高优先）多维 GPCM 的 L3 独立对照

**第 1 步：标定（必须做，秒级）——先把参数化换算钉死**

同一模型、两引擎，先证明你会读参数，再谈比对：

- 工具侧：`outputs/irt_analysis_gpcm_20260917_212101`（**单维 GPCM**，irt_B 数据，含 `a1`、`d1..d4`、`b_d1..b_d4`）
- 第二引擎：`TAM::tam.mml.2pl(resp=X, Q=单维Q, irtmodel="GPCM")`（1 维实测 0 秒）
- 交付：报告里写清**从 TAM 的 `B`/`AXsi` 导出 a 与台阶 b 的换算公式**，并给出这一步的 r 与平均偏差。
- **若标定步都对不上，不要进入第 2 步**，先报告差异与你的判断（是换算错、口径不同，还是真不一致）。

**第 2 步：真正的缺口**

- **路线 A（推荐，已实测可行）**：`irt_G` 的 F1+F2 子集（16 题、2 维），`Q` 由
  `examples/simulated_datasets/irt_G_loading_matrix.csv` 构造；n=200 实测 2 秒。
  给出 a 与 `b_d` 的 r / 平均偏差 / RMSE。
  **必须写明：这只覆盖 2 维 GPCM，3 维仍未验证**（不许把它说成"多维 GPCM 已验证"）。
- **路线 B（可选，真 3 维）**：允许 `install.packages("sirt")`（CRAN）。装上就用 `sirt` 做 3 维对照；
  装不上或跑不动，按 2.0 第 3 条给出可行性测量。

**已知陷阱（我方踩过，别重复）**
① `TAM` 的 `B` 是**题目 × 类别 × 维度**的数组，含类别维度——不要把类别乘子当成维度载荷
（我方曾在单维 GPCM 上把 MDISC 算成 5.536，而该题 a 只有 0.805，就是这个原因）；
② 工具的 `b_dk` 是**台阶难度** = 相邻类别截距之差 ÷ MDISC（Muraki 口径），不是 `−d_k/MDISC`；
③ `ltm::grm()` 与 `ltm::tpm()` **没有公式接口**（第一个形参就是 `data`）。

### 2.2 G2 CFA 的**真**独立 L3

- **用 `OpenMx`（优先，可手写模型）或 `semTools`——不是再用 `lavaan`。**
- 必须对齐口径：有序题 **WLSMV**、**`std.lv = TRUE`**（因子方差固定为 1）。你第 2 轮已复现这两点，
  本轮把它换成独立引擎即可，不必重新论证口径。
- 材料：`examples/simulated_datasets/ctt_B_full_survey_n500_items20.csv`、`ctt_B_cfa_mapping.csv`、
  `ctt_B_config.yaml`、`outputs/ctt_B_ctt_20260918_080516/05_cfa_loadings.csv`、同目录 `05_cfa_model_syntax.lav`
- 交付：20 个标准化载荷的 **r、RMSE、最大单题偏差**；并说明 OpenMx 的 WLSMV 实现与 lavaan 的差异
  是否影响可比性。若 `semTools` 只能做补充分析（如测量不变性）而不能给出独立估计，请说明并改走 OpenMx。

### 2.3 G3 拟合指标：先做"两引擎能拟合同一模型"的情形

- **关键前提**：只有两引擎拟合的是**同一个模型**，`M2*`/`SRMSR` 的对比才有意义。
  GRM（mirt）与 GPCM（TAM）是**不同模型**，不可比——不要混用。
- **推荐路线**：`irt_A`（**单维 2PL**，20 题）。TAM 的 `irtmodel="2PL"` 与 mirt 的 2PL 是同一个模型
  （TAM 单维实测 0 秒）。对照 `outputs/irt_analysis_2pl_20260918_091532/*_model_comparison.csv`
  里的 `M2*`/`SRMSR`/`TLI`/`CFI` 与 TAM 的 `tam.fit` / `tam.modelfit`，逐项给出：
  **定义是否相同、df 口径是否相同、数值差多少**。
- 若要再推进：`irt_B` 是单维 **GRM**，需另找能拟合 GRM 的第二引擎（TAM 的 GPCM 不是 GRM）。
- **预先授权一种合格结论**：`M2*` 是特定定义（Maydeu-Olivares 一族）的统计量，
  若两引擎的**定义或 df 口径不同，则"只能比量级与方向、不能逐位比"本身就是合格结论**。
  **不要为了给出数值而硬凑、换模型或放宽定义。**
- **明令**：不得用保存的 mirt 对象再调 `mirt::M2` 充当独立复算（理由见 1.2 第 3 条）。

### 2.4 读取白名单（第三轮）

**可以读**：

| 类别 | 路径 |
|---|---|
| 被测代码 | `scripts/irt_generic_pipeline.R`、`scripts/irt_common.R`、`scripts/ctt_pipeline.R`、`scripts/ctt_common.R` |
| 生成器（推导真值口径） | `scripts/generate_simulated_datasets.R` |
| 数据与配置 | `examples/simulated_datasets/{irt_A,irt_B,irt_G}_*`、`ctt_B_*`（含 `irt_B_config_gpcm.yaml`、`irt_G_loading_matrix.csv`、各 `*_truth.csv`） |
| 指定结果目录（只有这 6 个） | `outputs/irt_analysis_gpcm_20260917_212101`（单维 GPCM，G1 标定）、`outputs/irt_analysis_2pl_20260918_091532`（G3）、`outputs/irt_analysis_grm_20260918_091608`、`outputs/irt_analysis_mirt_cifa_20260918_091928`（irt_G CIFA）、`outputs/irt_analysis_mirt_eifa_20260918_092357`（irt_G EIFA）、`outputs/ctt_B_ctt_20260918_080516`（G2） |
| 我方结论与方法 | `docs/CTT与IRT校对记录.md`、`docs/CTT与IRT校对方案.md`、`docs/第三轮_CTT与IRT审查报告.md`（你自己的第 2 轮报告） |
| 你自己的脚手架 | `tests/thirdparty/round2/` |

**不要读**：`outputs/` 下的其它目录（共 286 个结果目录、7994 个文件、870MB）、`notes/`、`.git/`、
心理统计分支文档、任何 `.docx`/`.html` 二进制（要文本请用 `python-docx` 抽取）。

### 2.5 输出格式（沿用，便于三方并排比对）

1. **元信息**：模型与版本、模式、实际执行的命令、耗时、**实际读过的文件数**。
2. **撤回声明**：明确写出撤回第 2 轮那条"未保留模型对象"的结论（见 1.2）。
3. **逐任务表**：| 任务 | 做法 | 复算值 | 判定（一致/不一致/不可比/未完成）| 证据（命令 / 文件:行 / 脚本路径）|
4. **不可行项的可行性测量**（照 1.3 的表格形态）。
5. **发现的问题**（按严重度；每条给最小复现；归类为 工具缺陷／我方脚本缺陷／判据不合理／环境差异）。
6. **你未能完成的部分**：卡在哪、需要什么才能继续。**宁可写"未完成"，不要给没有证据的判定。**
7. **一致性指纹 v3**：

```json
{
  "reviewer": "<模型名与版本>",
  "round": 3,
  "mode": "run | static",
  "files_read": 0,
  "stayed_in_whitelist": true,
  "G1_route_used": "2dim_TAM | 3dim_sirt | calibration_only | none",
  "G1_calibration_agreement": "<r / mean diff，未做填 none>",
  "G2_independent_engine": "OpenMx | semTools | none",
  "G3_verdict_form": "definitional | numerical | not_comparable | not_done",
  "infeasibility_measured": true,
  "retracted_findings": ["round2: IRT 未保留模型对象"],
  "new_findings": 0,
  "severity_max": "high | medium | low | none",
  "top_finding": "<一句话，没有则填 none>",
  "recompute_script_path": "tests/thirdparty/round3/review_round3.R"
}
```

### 2.6 对仓库的禁止事项

- **不得改动 `scripts/` 与任何 `*.ps1`**（核心代码）。修复建议只出**最小 diff 建议**，由我方决定是否采纳。
- 不得重构、重命名、调整格式、顺手改注释。
- 不得删除或改写我方 `tests/verify_*.R`；如认为其中有错，请**新增**你的版本。
- 复算脚本请留在 `tests/thirdparty/round3/`（含 `results/` 与 `sessionInfo`），并在报告中给出路径与运行命令。
- 临时文件放 `notes/` 或你自己的 `thirdparty` 目录内，**结束时清理干净**（第 2 轮在 `%TEMP%` 留了 `fx.ps1`）。
- 不要动 `git` 历史、不要删除或改写 `outputs/` 下的任何目录（需要新结果就新建目录）。
- 若安装 R 包（如 `sirt`），请记录包名与版本到 `sessionInfo.txt`。

现在开始。若某任务缺文件，请先列出你需要什么，**不要自行扩大读取范围**。
