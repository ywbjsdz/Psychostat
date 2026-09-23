# 参与贡献（Contributing）

感谢你愿意改进 Psychostat。本文件说明**这个项目实际使用的工作方式**，请先读一遍再动手。

---

## 一、这个项目最看重什么

按优先级排序：

1. **统计口径正确**。心理统计分支按 IBM SPSS 27 默认口径实现（合并方差 t、Type III 平方和、均值中心 Levene、Mauchly+GG/HF、LSD/Tukey/Bonferroni 等）。改动统计逻辑时，必须说明依据，并尽量补上可独立复算的断言。
2. **不破坏别人的机器**。用户多在 Windows 10/11 + PowerShell 5.1、中文用户名、可能没有管理员权限、网络在国内。任何"在我机器上能跑"的改动都要考虑这三条。
3. **对新手诚实**。报错要给可操作的中文原因；做不到的要明说做不到，不要静默降级或输出看似正常的错误数值。

---

## 二、环境准备

| 依赖 | 版本 | 说明 |
|---|---|---|
| Windows | 10/11 | 项目只支持 Windows（`.bat` 入口、WinForms 界面） |
| PowerShell | 5.1+ | **CI 跑的是 pwsh 7，但你必须在 5.1 上验一遍**（见下） |
| R | 4.2+ | 建议 `D:\R\R-x.y.z`；启动器也会去 D 盘、注册表找 |
| Python | 3.9+ | 可选，仅生成 Word 结果报告；需要 `pandas`、`python-docx` |

```powershell
git clone <repo> ; cd Psychostat
pip install -r requirements.txt          # 普通开发
pip install -r requirements-lock.txt     # 与 CI 一致的精确版本
```

---

## 三、改完必须跑的检查

```powershell
# 1) 分层自检（必跑）：文件编码约定 + 三分支冒烟 + 数值回归
.\tests\smoke_test.ps1 -Full        # 输出 ALL CHECKS PASSED 才算过；约 5–8 分钟
.\tests\smoke_test.ps1              # 快速版（仅心理统计两个方法）

# 2) 只跑数值回归（改统计逻辑时的高频循环）
.\tests\run_numeric_tests.ps1       # 末行给出 PASS_COUNT / FAIL_COUNT

# 3) 提交前自查：确认没有真实研究数据混进来
.\scripts\check_sensitive.ps1

# 4) 改了 R 源码时，先用最便宜的方式确认能解析（比跑全量冒烟快得多）
Rscript --vanilla -e "invisible(parse('scripts/stats_common.R')); invisible(parse('scripts/stats_modules.R')); cat('PARSE OK\n')"
```

### ⚠️ PowerShell 5.1 专项

CI 的 shell 是 `pwsh`（7.x），**很多 5.1 专有坑它抓不到**。已踩过的两个真实例子：

- **原生程序的 stderr**：`& $exe ... 2>&1` 在 `$ErrorActionPreference='Stop'` 下会把 stderr 升级为**终止性错误**（7.x 已改为当字符串）。调用 `Rscript`/`python` 时务必用
  ```powershell
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $exe ... 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  ```
- **BOM**：`.ps1` 必须带**恰好一个** UTF-8 BOM，否则 5.1 按本地代码页解码中文 → 语法错误或乱码；`.bat` 必须**纯 ASCII**（任何代码页下双击都不乱码）。冒烟测试的第 0 项会做字节级断言，改动后别跳过它。

---

## 四、文件与编码约定

由 `.gitattributes` 声明，并被 `tests/smoke_test.ps1` 自动把关：

| 类型 | 约定 |
|---|---|
| `*.ps1` | UTF-8，**恰好一个 BOM** |
| `*.bat` | **纯 ASCII**，无 BOM |
| `*.R` / `*.py` | UTF-8，**无 BOM** |
| `*.md` / `*.json` / `*.yaml` / `*.R` / `*.py` | LF 行尾 |
| `*.ps1` / `*.bat` | CRLF 行尾 |

> **用编辑器改 `.ps1` 后请检查 BOM 是否还在**——这是本项目最容易被无意破坏、且后果最严重（PowerShell 5.1 直接报几百个语法错误）的一点。

数据保护：

- 真实研究数据只放 `data/`（或 `private/`、`local/`、`secrets/`），这些目录已被 `.gitignore` 忽略。
- `*.sav / *.xlsx / *.xls` 全局忽略（`examples/`、`tests/data/` 下的模板除外）。
- **不要把被试信息写进代码、注释、提交信息或文档**。文档里举例一律用 `<你的用户名>` 之类的占位符。

---

## 五、加一个新的统计方法

1. 在 `scripts/stats_common.R` 的 `STATS_METHODS` 注册表里加一项，**必须带 `spss` 菜单路径字段**（界面与报告都用它）。
2. 在 `scripts/stats_modules.R` 写 `simulate_<方法>()` 与 `run_<方法>()`：
   - `simulate_*` 用 `set.seed(cfg$simulation$seed + N)`，保证可复现；
   - `run_*` 开头用 `need_var()` 取变量、`num_col()`/`group_col()` 取数据；
   - 用 `guide()` 输出教学文字：**什么时候用 → SPSS 菜单路径 → 结果怎么读 → 结果怎么写 → 常见错误**；
   - 结果一律用 `save_table(..., ctx, "<后缀>", "<表题>")` 落盘，表题里写明对应的 SPSS 表名。
3. 结果句**不要写死方向/构念名/显著性**。用现有模板助手（`two_group_direction()`、`levels_shape_note()`、`pairwise_shape_note()`）从实际统计量生成；无法唯一确定方向时，明确提示读者自行核对。
4. 拼公式前先做**列名安全化**（`formula_name_mapping()` + `rename_for_formula()`）：用户表头常含空格、`-`、顿号、括号、前导数字，裸拼进 `as.formula()` 会让 `-` 变成运算符，导致模型静默变形。
5. 在 `tests/test_numeric.R` 补断言（见下节）。

---

## 六、测试怎么写（重要）

`tests/test_numeric.R` 里有两类断言，**请加对类型**：

| 类型 | 验什么 | 价值 |
|---|---|---|
| ❌ 生成器断言 | 对 `simulate_*` 造的数据用 base R / `car` 复算 | **低**——把 `run_*` 改错它照样通过 |
| ✅ 生产代码断言 | **直接调用** `run_*` 或生产助手函数（`levene_spss()`、`anova_table_spss()`、`posthoc_tables()`…） | 高 |

写生产代码断言时，黄金值优先取**可独立复算的来源**，按可信度排序：

1. **闭式精确值**（最佳）：如 Levene 的 `F = 150544/9727`、Brown-Forsythe 的 `F = 4/9`。
   构造数据使结果是有理数，用 `near(x, 150544/9727, tol = 1e-10)` 断言。
2. **真实 SPSS 输出**：见下节夹具流程。
3. **结构性质**：如 Welch df ≠ 合并方差 df、`GG ε ≤ HF ε`、非平衡数据下 Type III ≠ Type I。
   这类断言不锁具体数值，不会因包版本漂移而误报，但能抓住口径错误。
4. **本工具实测值**：最后才用，且必须注明来源（数据文件、种子、日期）。

判据：**如果只把 `run_*` 的实现改坏、不动 `simulate_*`，你的断言必须变红。** 做不到就说明断言投放在生成器上了。

---

## 七、补 SPSS 外部基准夹具（欢迎，且价值最高）

`tests/fixtures/spss/` 目前只有说明骨架，**没有任何真实 SPSS 输出**——这是本项目最缺的一块。

流程见 `tests/fixtures/spss/README.md`，摘要：

1. 跑对应模块，从结果目录取 `NN_<方法>_data.csv`（UTF-8-BOM，SPSS 可直接打开）。
2. 在 SPSS 27+ 里按报告给出的菜单路径分析，把**数值表**存为本目录下的 `<方法名>.txt`。
3. 文件开头注明：SPSS 版本、数据文件名与生成它的 seed、执行日期。
4. 在 `tests/test_numeric.R` 里加断言，黄金值取自该文件，容差按 SPSS 打印精度放宽并注明。
5. 跑 `run_numeric_tests.ps1` 确认通过、且末行 `PASS_COUNT` 与实际条数一致，然后提 PR。

**请勿伪造"看起来像 SPSS"的输出**——没有基准时宁可留空并说明。

---

## 八、提交与 PR

- 分支命名：`fix/<主题>`、`feat/<主题>`、`docs/<主题>`。
- 提交信息：一句话说清**改了什么 + 为什么**（例如 `Fix normality verdict when S-W is skipped (n > 5000)`）。
- **必须在 PR 描述里贴出 `smoke_test.ps1 -Full` 的输出**，并注明你验证用的 PowerShell 版本与 R 版本。
- 同步更新 `CHANGELOG.md`（Keep a Changelog 格式）；用户可见的改动请一并更新 `README.md` 与对应 `docs/*.md`。
- Word 说明书是**生成物**（`docs/*.md` 才是源）：改完 md 后跑
  ```powershell
  python scripts/generate_docs.py      # 完整说明书
  python scripts/merge_manuals.py      # 分支说明合并版
  ```

---

## 九、我们不会接受的改动

- 为了在单一数据集上对上 SPSS 而**反推/拟合常数**（必须用通用算法，换数据也要成立）。
- 删掉或弱化报错信息、静默吞掉失败、把"算不出"渲染成"无效应"。
- 未经说明改动 SPSS 口径（如需偏离，请在报告与文档里显式标注）。
- 提交真实研究数据、被试信息或个人路径（CI 与 `check_sensitive.ps1` 会拦，但请自觉）。

---

## 十、行为准则

请保持专业与尊重：讨论对事不对人，批评请给可复现的证据。本项目面向学生与新研究者，**提问没有"太基础"这一说**。
