# SPSS 外部基准夹具（tests/fixtures/spss）

## 现状说明

本目录当前**没有任何 SPSS 原始输出夹具**。仓库维护者本机未安装 SPSS，无法在这里生成真实的 SPSS 输出，也**不应伪造**任何"看起来像 SPSS"的假数据。

在没有真实夹具的情况下，`tests/test_numeric.R` 第 5 节的 "SPSS alignment" 断言使用**闭式/教科书精确值**作为外部基准（这些值不依赖被测代码）：

- Brown-Forsythe 稳健均值检验：`c(1,4,2,5,3,6)` 三组各 2 例的构造数据，F = 4/9 = 0.4444444444（精确分数）；
- Friedman 重复测量秩：`A=(1,1,3,3), B=(2,2,1,1), C=(3,3,2,2)` 的被试内平均秩 = (2, 1.5, 2.5)（手算即可验证）；
- 因子设计简单效应：残差 df 必须保留全模型误差项 df（非均衡设计下拆分文件会改变分母 df，SPSS 的 EM 均值简单效应保留之）。

以上覆盖的是"实现方式与 SPSS 对齐"的可解析性质。若要覆盖"数值输出与 SPSS 一致"，需要贡献真实 SPSS 输出，流程见下。

## 贡献流程（用真实 SPSS 输出补充基准）

1. **取数据**：运行对应统计模块（如 `run_stats_analysis.ps1 -Silent -ConfigJson examples/silent_stats_demo.json`），从结果目录取 `NN_<方法>_data.csv`（UTF-8-BOM，SPSS 可直接打开）。
2. **在 SPSS 中导入并分析**：将 CSV 导入 SPSS 27+，按该模块报告里给出的【SPSS操作】菜单路径执行分析（各模块的 SPSS 菜单路径见 `scripts/stats_common.R` 中 `STATS_METHODS` 表，或结果目录下的 `00_方法选择决策指南.md`）。
3. **记录输出**：把 SPSS 输出查看器中的**数值表**（结果表本体，含表标题）复制/保存为纯文本，存为本目录下的 `<方法名>.txt`（例如 `independent_t.txt`）。文件开头请注明：SPSS 版本、数据文件名与生成它的 seed（演示数据 seed=20260904）、执行日期。
4. **在 `tests/test_numeric.R` 中加断言**：新增 `check(...)` 比对该表中的关键统计量（t/F/χ²/df/p 等），黄金值直接取自你保存的 SPSS 输出，容差建议 `1e-9`（SPSS 打印位数有限时按打印精度放宽，并注明）。
5. **跑回归**：执行 `tests/run_numeric_tests.ps1`，确认新断言通过且末行 `PASS_COUNT=N` 与实际条数一致。
6. **提交**：夹具 `<方法名>.txt` 与测试改动一并提交，PR 描述中注明 SPSS 版本与数据 seed。

## 当前最值得补 SPSS 基准的 5 个方法

1. `independent_t` — 独立样本 t 检验（合并方差/Welch 双行表 + Levene 行；黄金值 -2.0998063566 可双验）
2. `one_way_anova` — 单因素方差分析（ANOVA 表 + LSD/Tukey/Bonferroni 事后比较；F 黄金值 7.7874726888）
3. `paired_t` — 配对样本 t 检验（成对差值表；t 黄金值 -13.0362471079）
4. `chi_square_independence` — 卡方独立性检验（交叉表 + 期望频数；χ² 黄金值 36.7321787894，注意 SPSS 默认连续校正需勾选"无"）
5. `rm_anova` — 重复测量方差分析（被试内效应 + Mauchly/GG/HF；F 黄金值 14.5030640425，需勾选球形假设修正输出）
