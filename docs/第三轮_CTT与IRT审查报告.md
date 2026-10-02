# Psychostat CTT 与 IRT 第三方审查报告（第三次）

- 审查员：Codex（GPT-5）
- 审查模式：A 实跑；本报告对应提示词规定的“第二轮跨模型复核”范围
- 审查日期：2026-09-18
- 仓库：`C:/Users/<user>/Desktop/Psychostat`
- R 环境：R 4.5.2；`lavaan` 0.6-21、`mirt` 1.46.1、`TAM` 4.3-25；`sirt` 未安装
- 本轮新增材料：`tests/thirdparty/round2/review_round2.R`、`tests/thirdparty/round2/ctt_B_round2_config.yaml`、`tests/thirdparty/round2/results/`；本报告。

## 1. 范围、执行与可复现性

严格按 `docs/第三方AI复核提示词_第二轮_CTT与IRT.md` 的白名单进行。实际读取了限定的 6 个 R 源文件、CTT-B 与 IRT-G 模拟资料/配置、5 个指定输出目录中为 G1--G5 所需的 CSV/中英文报告、两份既有校对文档及 `tests/verify_*.R`；未读取其它 `outputs/` 目录、`notes/`、`.git/`、心理统计分支文档或 `.docx` 二进制。实际读取文件计数为 42（同一文件被重复读取时只计一次）。

核心复算脚本保留在：`tests/thirdparty/round2/review_round2.R`。最后一次默认运行命令（10.4 秒，退出码 0；仅有 lavaan 构建版本提示）如下：

```powershell
Remove-Item Env:LANG,Env:LC_ALL,Env:LC_CTYPE -ErrorAction SilentlyContinue
$env:TEMP='C:\PsychostatTemp'; $env:TMP='C:\PsychostatTemp'
& '<R-install-dir>\bin\Rscript.exe' --vanilla 'C:\Users\<user>\Desktop\Psychostat\tests\thirdparty\round2\review_round2.R'
```

G1 的 TAM 尝试需显式设置 `$env:RUN_TAM_G1='1'`。本轮未改动 `scripts/` 或任何既有 `.ps1`，也未改写原 `outputs/`。

## 2. 判定汇总

| 任务 | 判定 | 简要结论 |
|---|---|---|
| G1 多维 GPCM/MGPCM 独立 L3 | 未完成 | TAM 可用但拟合未返回可对照参数；sirt 不可用。 |
| G2 CFA 独立 L3 | 未完成 | 已严格复现 WLSMV + `std.lv=TRUE` 的结果，但未获得 OpenMx/semTools 的独立估计器对照。 |
| G3 拟合指标第二实现/文档核对 | 无法判定 | mirt 可加载，但 3 个指定 IRT 输出没有保存模型对象，不能重算 M2*/SRMSR。 |
| G4 报告层忠实性 | 一致 | 5 个目录各抽查 3 项，15/15 与 CSV 一致；无结论方向冲突。 |
| G5 `empirical_rxx` 口径 | 一致 | 工具值逐位符合 mirt 的正式定义；近似式差异正常。 |

## 3. 逐任务结果

| 任务 | 做法 | 复算值/证据 | 判定 |
|---|---|---|---|
| G1 | 检查 TAM/sirt 能力，并以 IRT-G 的 24 题、3 维 Q 矩阵尝试 `TAM::tam.mml.2pl(..., irtmodel='GPCM2')`。 | `G1_engine_capability.csv`：TAM=TRUE，sirt=FALSE；`G1_TAM_execution_marker.txt` 显示进入 TAM 调用，但没有产生可比较的参数或状态结果。 | 未完成。不能以“进入函数”替代参数对照。 |
| G2 | 用映射重建 CFA 语法；按管线口径对 Item07、Item15 反向计分，使用有序 WLSMV 与 `std.lv=TRUE`。另从审计专用管线输出的清洗后数据重拟合。 | 清洗：500 → 475（注意检验 15、过快 10）；20 个标准化载荷与工具表最大绝对差 `4.44e-16`，RMSE `2.85e-16`（`G2_same_estimator_metrics.csv`）。拟合：χ²=114.311, df=167, CFI=1.000, TLI=1.008, RMSEA=0, SRMR=.0357。 | 同估计器复现一致；但独立 L3 未完成。未经完整清洗时与生成真值的 r=.785、RMSE=.0432 不作为工具误差。 |
| G3 | 检查指定 IRT 目录是否保留 `*_selected_model.rds`，并在存在时调用 `mirt::M2(type='M2*')`。同时核对管线调用的定义路径。 | `G3_mirt_recalculation.csv` 为空：3 个目录均无保存模型对象。工具代码使用 `M2(fit, type='M2*', calcNull=TRUE, na.rm=TRUE)`；CIFA 输出中 M2 等为 NA，未伪造数值。 | 无法判定；不能把同一 mirt 路径重跑称为独立复算。 |
| G4 | 5 个指定结果目录逐一核对中文报告与 CSV，每目录抽查模型/样本量、信度和一个参数或拟合指标。另检查关键结论句方向。 | `G4_report_number_presence.csv` 自动命中 12/15；余下 3 项经精确文本核对均存在：`.745`（省略前导零）、`465`、`120`。因此为 15/15 一致。CIFA 报告选择 CIFA，且 BIC=12967.51 小于单维 13258.22；零方差 CTT 报告如实给出 α=-.141、KMO=.521、Bartlett p=.239，并提示谨慎解释。 | 一致。3 个初始未命中是审计 token 格式覆盖不足，不是报告错误。 |
| G5 | 直接反编译 `mirt::empirical_rxx()` 与 `mirt::marginal_rxx()`，再用能力估计/SE 表复算。 | `reported_empirical_rxx` 与定义式逐位相同（4 个维度/结果）：.7676944、.7182545、.8552893、.7483760。近似式分别低 .07030、.11052、.02448、.08460。 | 一致。正式输出应继续采用 `mirt::empirical_rxx()`。 |

## 4. G5 口径结论

`mirt::empirical_rxx()` 默认计算的是：

\[
r_{xx}^{emp}=\frac{\operatorname{Var}(\hat\theta)}{\operatorname{Var}(\hat\theta)+\overline{SE^2}}.
\]

第一轮所用的 `1-mean(SE²)/var(θ)` 是令 \(x=\overline{SE^2}/\operatorname{Var}(\hat\theta)\) 后，对 \(1/(1+x)\) 的一阶近似，因此系统性偏低；SE 相对能力方差不小的时候，.01--.11 的差距完全合理。建议维持当前正式报告的 `Empirical_rxx`，近似式只能作为说明性对照，不能作为一致性判据。

## 5. 发现的问题（按严重度）

### 中：IRT 输出未保留模型对象，导致拟合指标无法独立审计

- 分类：工具输出设计 / 可审计性缺口。
- 影响：无法基于实际已选模型独立重算 M2*、SRMSR、TLI/CFI 及其自由度口径；G3 因而不能被判为“已验证”。这不是已证实的数值错误。
- 最小复现：运行 `review_round2.R` 后，`tests/thirdparty/round2/results/G3_mirt_recalculation.csv` 为空；指定三个 IRT 输出目录均无 `*_selected_model.rds`。
- 最小建议（不在本轮执行）：在每个 IRT 结果目录中，以可选的审计开关保存已选 mirt 拟合对象及 mirt/R 版本信息；或导出足以重新计算 M2*/SRMSR 的充分信息。应明确提示对象可能较大及其版本兼容性。

未发现高严重度的数值错误、报告错列/漏行或中英文结论矛盾。G4 中的三个初始假阴性属于本轮审计脚本的格式匹配覆盖不足，归类为“我方审计脚本限制”，不计入项目缺陷。

## 6. 未能完成的部分

1. G1：需要能稳定结束并导出 TAM 参数的本地运行，或安装可用的 sirt，再按照 Muraki 台阶难度口径转换后比较 `a` 与 `b_d` 的相关和平均偏差。
2. G2：需要 OpenMx 或 semTools 的真正独立 CFA 实现，并明确处理有序 WLSMV 与 `std.lv=TRUE` 的等价识别；当前 lavaan 复现只能确认清洗、模型语法和估计口径。
3. G3：需要上述三份输出对应的 mirt 模型对象，或获准从相同输入重新拟合并把新拟合与原输出严格绑定。当前不能由表格反推 M2*。

## 7. 一致性指纹

```json
{
  "reviewer": "Codex (GPT-5)",
  "round": 2,
  "mode": "run",
  "files_read": 42,
  "stayed_in_whitelist": true,
  "G1_multidim_gpcm_l3": "not_done",
  "G2_cfa_l3": "partial",
  "G3_fit_indices": "not_done",
  "G4_report_fidelity": "done",
  "G5_empirical_rxx": "done",
  "new_findings": 1,
  "severity_max": "medium",
  "top_finding": "指定 IRT 结果目录未保留模型对象，M2*/SRMSR 无法独立复算。",
  "recompute_script_path": "tests/thirdparty/round2/review_round2.R"
}
```