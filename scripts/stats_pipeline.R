# Psychostat undergraduate statistics pipeline: dispatches configured method modules, saves SPSS-style
# tables plus simulated data files for SPSS cross-checks, and assembles a Chinese teaching report.
script_arg <- commandArgs(FALSE)
script_arg <- sub("^--file=", "", script_arg[grep("^--file=", script_arg)][1])
source(file.path(dirname(normalizePath(script_arg)), "stats_common.R"))
source(file.path(dirname(normalizePath(script_arg)), "stats_modules.R"))
source(file.path(dirname(normalizePath(script_arg)), "stats_datacheck.R"))

make_result_dir <- function(cfg) {
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out <- file.path(cfg$output$directory, sprintf("%s_stats_%s", cfg$output$project_label, stamp))
  dir.create(out, recursive = TRUE, showWarnings = FALSE); out
}

banner <- function(idx, total, label, spss) {
  bar <- strrep("═", 66)
  guide("\n", bar)
  guide(sprintf("  %02d/%d  %s", idx, total, label))
  guide(sprintf("  对应SPSS：%s", spss))
  guide(bar)
}

start_report_section <- function(idx, method, meta) {
  stats_session$report <- c(stats_session$report,
                            sprintf("\n## %d. %s（%s）\n\n> SPSS路径：%s\n", idx, meta$label_zh, method, meta$spss))
}

write_method_guide <- function(out_dir) {
  txt <- paste0(
"# 心理统计方法选择决策指南（写给大二的你）\n\n",
"## 一、先问自己三个问题\n\n",
"1. **因变量是什么类型？** 连续（成绩、焦虑分）→ t/ANOVA/相关/回归；分类（及格与否、偏好）→ 卡方；等级或严重偏态 → 非参数检验。\n",
"2. **比较几组？组间独立还是重复测量？** 2组独立→独立t；2组配对→配对t；≥3组独立→单因素ANOVA；≥3次重复测量→重复测量ANOVA。\n",
"3. **数据满足前提吗？** 正态性（模块2：Shapiro-Wilk / K-S）、方差齐性（Levene）、球形性（Mauchly）——前提不满足时的退路见\"非参数对应表\"。\n\n",
"## 二、场景速查表（论文开题/考试答题前先看这里）\n\n",
"| 场景 | 用什么方法 | 本工具模块 |\n|---|---|---|\n",
"| 比较两组连续成绩（独立组） | 独立样本t检验 | independent_t |\n",
"| 比较前后测（同一批人） | 配对样本t检验 | paired_t |\n",
"| 比较三组及以上 | 单因素ANOVA+事后 | one_way_anova |\n",
"| 两个自变量共同影响（2×3设计） | 两因素ANOVA：先交互后主效应 | two_way_anova |\n",
"| 同一批人测3次以上 | 重复测量ANOVA（Mauchly/GG/HF） | rm_anova |\n",
"| 一组组间+一组组内 | 混合设计ANOVA | mixed_anova |\n",
"| 控制前测/智商后比组间 | 协方差分析ANCOVA | ancova |\n",
"| 两个连续变量的关系 | Pearson/Spearman相关 | correlation |\n",
"| 控制第三变量后的相关 | 偏相关 | correlation（partial） |\n",
"| 用多个X预测连续Y | 多元线性回归 | regression |\n",
"| 检验调节（交互） | 中心化乘积项+简单斜率 | moderation |\n",
"| 检验中介（X如何通过M影响Y） | PROCESS Model 4 + Bootstrap | mediation |\n",
"| 单个分类变量的分布 vs 理论比例 | 卡方适合度 | chi_square_gof |\n",
"| 两个分类变量是否关联 | 卡方独立性 | chi_square_independence |\n",
"| 两组偏态/等级数据 | Mann-Whitney U | mann_whitney |\n",
"| 前后测偏态/等级数据 | Wilcoxon符号秩 | wilcoxon_signed |\n",
"| ≥3组偏态/等级数据 | Kruskal-Wallis H | kruskal_wallis |\n",
"| ≥3次重复测量偏态/等级数据 | Friedman检验 | friedman |\n",
"| 事前算样本量/事后敏感性 | 功效分析（G*Power） | power |\n\n",
"## 三、方差分析三步决策闭环（必背）\n\n",
"1. 看主效应（每个自变量单独的影响）。\n",
"2. 看交互：**显著 → 主效应失去直接解释意义，必须做第3步**；不显著 → 回头解释主效应+事后比较。\n",
"3. 简单效应：固定一个变量的每个水平，检验另一个变量；简单效应显著后再看\"成对比较\"定位差异。\n\n",
"## 四、非参数检验对应表（前提不满足时的退路）\n\n",
"| 参数方法 | 非参数替代 | 前提检查 |\n|---|---|---|\n",
"| 独立样本t | Mann-Whitney U | 正态性（SW/K-S） |\n",
"| 配对样本t | Wilcoxon符号秩 | 差值正态性 |\n",
"| 单因素ANOVA | Kruskal-Wallis H | 正态性+方差齐性（Levene） |\n",
"| 重复测量ANOVA | Friedman | 正态性+球形性（Mauchly） |\n",
"| 单样本t | Wilcoxon符号秩（对总体中位数） | 正态性 |\n\n",
"## 五、效应量速查（显著≠重要，必须报告）\n\n",
"| 检验 | 效应量 | 小 | 中 | 大 |\n|---|---|---|---|---|\n",
"| t检验 | Cohen's d | .20 | .50 | .80 |\n",
"| ANOVA | η²p | .01 | .06 | .14 |\n",
"| 相关 | r | .10 | .30 | .50 |\n",
"| 卡方 | φ / Cramér's V | .10 | .30 | .50 |\n",
"| 非参数 | r = |Z|/√N | .10 | .30 | .50 |\n\n",
"## 六、相对思维导图的查漏补缺（本工具已补上）\n\n",
"- 前提检验独立成模块：正态性（Shapiro-Wilk、K-S-Lilliefors）与方差齐性（Levene）。\n",
"- 重复测量的球形性：Mauchly检验 + Greenhouse-Geisser / Huynh-Feldt 校正。\n",
"- Friedman检验：补齐非参数家族中\"重复测量≥3条件\"的空位。\n",
"- ANCOVA：从\"场景索引\"升格为正式模块（含斜率同质性前提与调整后均值）。\n",
"- 偏相关：控制第三变量后的相关。\n",
"- 回归诊断：多重共线性（VIF/容差）、Durbin-Watson、残差统计。\n",
"- 效应量与多重比较校正贯穿所有模块；中介效应（Model 4）、调节效应（Model 1）与功效分析（G*Power对应）分别作为第19、20、21个模块。\n"
  )
  writeLines(enc2utf8(txt), file.path(out_dir, "00_方法选择决策指南.md"), useBytes = TRUE)
}

sim_story <- function(m) {
  switch(m,
    datacheck = "120名学生的焦虑、学习时长与自尊得分；数据里**故意留了缺口**：学习时长缺 4%、自尊缺 3%，另有 3 个极端值与 1 个把缺失码 99 当分数的录入错误——正好用来演示第 0 步能查出什么。",
    descriptives = "90名大学生的考试焦虑得分与每周手机使用时长（后者右偏，用于对比偏度）。",
    normality = "60人的期末成绩：先整体检验正态性（对应SPSS探索只放因变量）。",
    one_sample_t = "某班30人考试焦虑分与全国常模 μ=50 比较。",
    independent_t = "男生32人、女生28人的空间推理测验成绩（独立两组）。",
    paired_t = "40名同学正念训练前后的焦虑得分（同一批人测两次）。",
    one_way_anova = "讲授/探究/翻转三种教学法各35人的期末成绩（单因素被试间）。",
    two_way_anova = "教学法(3)×学习动机(2)每格25人的成绩（2×3被试间设计，交互是主角）。",
    rm_anova = "30名同学在干预前、1月、3月、6月四个时间点的焦虑得分（重复测量）。",
    mixed_anova = "干预组30人、对照组30人，均在前测/后测/随访三个时间点测量焦虑（混合设计）。",
    ancova = "三种教学法各30人，以后测成绩为因变量、前测成绩为协变量。",
    correlation = "120名同学的学习时长、手机时长、考试焦虑与期末成绩（4个连续变量）。",
    regression = "150名同学：用学习时长、智商、焦虑预测期末成绩；另附动机×学习资源的调节示例。",
    chi_square_gof = "210人在四种学习风格选项上的选择分布 vs 均匀分布。",
    chi_square_independence = "240名学生的性别×择业偏好（2×3列联表）。",
    mann_whitney = "运动员28人 vs 游戏玩家32人的每周游戏时长（右偏分布）。",
    wilcoxon_signed = "26名同学对课程的前后满意度评分（1-7等级，偏态）。",
    kruskal_wallis = "心理/工科/艺术三个专业各30人的睡眠质量分（右偏）。",
    friedman = "22名同学对三个教学视频的满意度评分（1-7等级，相关样本）。",
    mediation = "180名同学：感知压力(X)→反刍思维(M)→抑郁(Y) 的三变量中介模型。",
    moderation = "150名同学：学习资源(Z)是否调节 学习动机(X) 对 投入得分(Y) 的影响。",
    power = "（本模块为计算器，无数据文件。）")
}

sim_truth <- function(m) {
  switch(m,
    datacheck = "变量真值：anxiety ≈ N(52,10)、study_hours ≈ N(8,3)、self_esteem ≈ N(30,5)；人工注入 9 个缺失、2 个极高值(95)、1 个极低值(2)、1 个越界码(99)",
    descriptives = "anxiety ≈ N(45,12)截断；phone_hours ~ Gamma(1.5,0.4)（右偏，均值3.75，理论偏度1.6）",
    normality = "traditional ≈ N(72,8)，cooperative ≈ N(75,8)，方差相等",
    one_sample_t = "样本 ~ N(56,9)，常模 μ=50 → 应检出显著高于常模（d≈0.67）",
    independent_t = "男 ~ N(103,13)，女 ~ N(94,13) → d≈0.69中偏大效应",
    paired_t = "前测 ~ N(52,10)，后测 ~ N(46,10)，r≈.65 → d≈0.74",
    one_way_anova = "讲授70/探究74/翻转78，σ=8 → F应显著",
    two_way_anova = "低动机70/74/78，高动机72/76/88，σ=8 → 交互显著（翻转在高动机多+10）",
    rm_anova = "时间均值52/47/44/43，σ=9，复合对称r=.55（球形成立）",
    mixed_anova = "干预组52/44/43，对照组52/51/50，σ=7，r=.6 → 交互显著",
    ancova = "posttest = 0.6×pretest + 讲授24/探究28/翻转31 + ε(6)",
    correlation = "给定相关矩阵：时长-成绩.65、时长-手机-.40、手机-焦虑.45、焦虑-成绩-.40",
    regression = "grade = 20 + 0.5×hours + 0.35×(IQ-100) - 0.25×(anx-50) + ε(6)",
    chi_square_gof = "选择概率 .40/.30/.20/.10 vs 均匀期望 .25×4",
    chi_square_independence = "男:学术20%/企业55%/临床25%；女:45%/25%/30% → 关联中等",
    mann_whitney = "athlete ~ Gamma(2,.7)（均值2.9），gamer ~ Gamma(2,.35)（均值5.7）",
    wilcoxon_signed = "post = pre - {0,1,1,2} + 扰动 → 后测显著更高（满意度提升）",
    kruskal_wallis = "心理6/工科9/艺术7 + Gamma(2,.8) → 工程最差",
    friedman = "B视频+0.8，C视频-0.3（共享被试基线）",
    mediation = "a=0.55，b=0.45，c'=0.15 → 间接效应≈0.25（显著），总效应≈0.40",
    moderation = "交互项系数1.6；Z低时X斜率≈2、Z高时≈5（调节显著）",
    power = "")
}

# 每个方法运行前的前置检查：先做描述统计；参数类方法顺带正态性检验（问题：让所有方法统一"第0步"）。
PARAMETRIC_METHODS <- c("one_sample_t", "independent_t", "paired_t", "one_way_anova", "two_way_anova",
                        "rm_anova", "mixed_anova", "ancova", "correlation", "regression", "mediation", "moderation")
# 提示口径按族区分（统计计算不变）：均值比较族（t检验/方差分析族）S-W 显著时提示"考虑非参数替代"；
# 回归/相关族的前提重点在残差正态性与影响点诊断，大样本下变量级 S-W 显著不构成更换方法的依据。
REGRESSION_FAMILY_METHODS <- c("correlation", "regression", "mediation", "moderation")

# 按输入模式取数据：file 读文件；simulate 取 simulate_<method>()（没有则退回 simulate_descriptives()）。
# 第 0 步数据准备与各方法都需要它，故抽成一处，避免两套逻辑走偏。
resolve_method_data <- function(cfg, m) {
  if (cfg$input$mode == "file") return(read_stats_data(cfg$input$path))
  sim_fun <- paste0("simulate_", m)
  if (exists(sim_fun)) return(get(sim_fun)(cfg))
  alt <- paste0("simulate_", cfg$method[cfg$method != "datacheck"][1])
  if (exists(alt)) return(get(alt)(cfg))
  get("simulate_descriptives")(cfg)
}

preflight_columns <- function(data, cfg, m) {
  v <- cfg$variables
  pick <- function(key, default) { x <- as.character(v[[key]] %||% ""); if (nzchar(x) && x %in% names(data)) x else if (length(default) == 1L && default %in% names(data)) default else NULL }
  pickv <- function(key, defaults) { x <- as_character_vector(v[[key]]); x <- x[x %in% names(data)]; if (length(x)) x else intersect(defaults, names(data)) }
  switch(m,
    "one_sample_t"    = list(num = pick("dv", "anxiety")),
    "independent_t"   = list(num = pick("dv", "spatial_score"), grp = pick("group", "gender")),
    "paired_t"        = list(num = c(pick("dv1", "pre"), pick("dv2", "post"))),
    "one_way_anova"   = list(num = pick("dv", "score"), grp = pick("group", "method")),
    "two_way_anova"   = {
      fa <- pick("factor_a", "method"); fb <- pick("factor_b", "motivation")
      list(num = pick("dv", "score"), grp = if (!is.null(fa) && !is.null(fb)) interaction(data[[fa]], data[[fb]], sep = "_") else NULL)
    },
    "rm_anova"        = list(num = pickv("within", c("time1_pre", "time2_1m", "time3_3m", "time4_6m"))),
    "mixed_anova"     = list(num = pickv("within", grep("^time", names(data), value = TRUE)), grp = pick("between", "group")),
    "ancova"          = list(num = c(pick("dv", "posttest"), pick("covariate", "pretest")), grp = pick("group", "method")),
    "correlation"     = list(num = { cc <- pickv("columns", character()); if (length(cc)) cc else names(data)[vapply(data, is.numeric, logical(1))] }),
    "regression"      = list(num = { dv0 <- pick("dv", "final_grade"); pp <- pickv("predictors", c("study_hours", "iq", "test_anxiety")); c(dv0, pp) }),
    "chi_square_gof"  = list(cat = pick("category", "preference")),
    "chi_square_independence" = list(cat = c(pick("row_var", "gender"), pick("col_var", "career_pref"))),
    "mann_whitney"    = list(num = pick("dv", "weekly_gaming_hours"), grp = pick("group", "group")),
    "wilcoxon_signed" = list(num = c(pick("dv1", "pre_satisfaction"), pick("dv2", "post_satisfaction"))),
    "kruskal_wallis"  = list(num = pick("dv", "sleep_quality_score"), grp = pick("group", "program")),
    "friedman"        = list(num = pickv("within", c("video_A", "video_B", "video_C"))),
    "mediation"       = list(num = c(pick("x", "stress"), pick("m", "rumination"), pick("y", "depression"))),
    "moderation"      = list(num = c(pick("interaction_dv", "engagement_score"), pick("interaction_x", "motivation"), pick("interaction_z", "learning_resources"))),
    list(num = NULL)
  )
}

run_preflight <- function(data, cfg, ctx, m) {
  spec <- preflight_columns(data, cfg, m)
  cols <- intersect(spec$num %||% character(), names(data))
  cols <- cols[vapply(data[cols], function(z) is.numeric(z), logical(1))]
  catv <- intersect(spec$cat %||% character(), names(data))
  if (!length(cols) && !length(catv)) return(invisible(NULL))
  guide("\n【第0步·前置检查】")
  if (length(cols)) {
    # 分组变量有两种来源，必须都支持：
    #   ① 字符串 = 数据里的列名（如 independent_t 的 group）→ 按列名取出实际列值。
    #      此前直接 as.factor(列名字符串) 只得到 1 个水平，导致按组描述统计与正态性检验从未真正分组。
    #   ② 已经是 factor（由 interaction() 现算出来，如 two_way_anova 的 A×B 单元格）→ 直接用。
    grp <- if (is.null(spec$grp)) NULL else {
      g <- if (is.character(spec$grp) && length(spec$grp) == 1L &&
               spec$grp %in% names(data)) data[[spec$grp]] else spec$grp
      droplevels(as.factor(g))
    }
    rows <- do.call(rbind, lapply(cols, function(cv) {
      x <- suppressWarnings(as.numeric(data[[cv]]))
      segs <- if (is.null(grp)) list(overall = x) else split(x, grp)
      do.call(rbind, lapply(names(segs), function(sn) {
        z <- segs[[sn]]; z <- z[is.finite(z)]
        sk <- spss_skewness(z); ku <- spss_kurtosis(z)
        data.frame(variable = cv, segment = sn, N = length(z), mean = mean(z), sd = stats::sd(z),
                   min = min(z), max = max(z), skewness = sk[["skewness"]], kurtosis = ku[["kurtosis"]])
      }))
    }))
    save_table(rows, ctx, "desc", "【表0】描述统计（前置：先看集中量数/离散量数/分布形态）")
    if (m %in% PARAMETRIC_METHODS) {
      ntab <- do.call(rbind, lapply(cols, function(cv) {
        x <- suppressWarnings(as.numeric(data[[cv]]))
        segs <- if (is.null(grp)) list(overall = x) else split(x, grp)
        do.call(rbind, lapply(names(segs), function(sn) sw_ks_rows(segs[[sn]], paste0(cv, " · ", sn))))
      }))
      save_table(ntab, ctx, "norm", "【表0b】正态性检验（前置：S-W首选；SPSS探索的K-S显著性显示上限为.200）")
      bad <- ntab[!is.na(ntab$sw_p) & ntab$sw_p < ctx$alpha, ]
      if (nrow(bad)) {
        if (m %in% REGRESSION_FAMILY_METHODS) {
          guide("  正态性：", sprintf("S-W p<.05 的变量·组段：%s → 回归/相关族重点看残差正态性与影响点诊断（本工具已输出 VIF/DW/残差诊断），大样本下变量级 S-W 显著不构成更换方法的依据。", paste(bad$segment, collapse = "、")))
        } else {
          guide("  正态性：", sprintf("S-W p<.05 的变量·组段：%s → 谨慎使用参数方法，考虑非参数替代或看分布图。", paste(bad$segment, collapse = "、")))
        }
      } else {
        okn <- normality_ok_note(ntab, ctx$alpha)
        if (!is.null(okn)) guide("  正态性：", okn, "参数方法前提可接受。")
      }
      un <- normality_untested_note(ntab)
      if (!is.null(un)) guide("  正态性：", un)
    }
    skw <- rows[!is.na(rows$skewness) & abs(rows$skewness) >= 1, ]
    if (nrow(skw)) guide("  偏度提示：", paste(sprintf("%s（|偏度|≥1）", skw$segment), collapse = "、"), " 分布明显偏态。")
  }
  for (cv in catv) {
    tab <- table(data[[cv]])
    save_table(data.frame(category = names(tab), frequency = as.integer(tab)), ctx,
               paste0("freq_", gsub("[^A-Za-z0-9_-]", "_", cv)), sprintf("【表0】分类变量频数（%s）", cv))
  }
  invisible(NULL)
}

# Machine-readable run manifest (run_manifest.json): timestamp/branch/R and package versions for reproducibility.
write_run_manifest <- function(out_dir, cfg, packages, methods_label, config_path = NULL, extra = NULL) {
  root <- normalizePath(file.path(dirname(normalizePath(script_arg, mustWork = FALSE)), ".."))
  branch <- tryCatch({ h <- readLines(file.path(root, ".git", "HEAD"), warn = FALSE); sub("^ref: refs/heads/", "", h[1]) }, error = function(e) NA_character_)
  version_of <- function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  m <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            branch = if (length(branch) && !is.na(branch)) branch else "unknown",
            r_version = R.version.string,
            os = paste0(R.version$platform, " / ", .Platform$OS.type),
            packages = stats::setNames(lapply(packages, version_of), packages),
            seed = cfg$simulation$seed %||% NULL,
            input_mode = cfg$input$mode,
            input_path = if (nzchar(cfg$input$path %||% "")) cfg$input$path else NULL,
            config_path = if (!is.null(config_path)) config_path else NULL,
            methods = methods_label)
  if (!is.null(extra)) m <- utils::modifyList(m, extra)
  jsonlite::write_json(m, file.path(out_dir, "run_manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
}

run_stats_pipeline <- function(config_path_args = commandArgs(trailingOnly = TRUE)) {
  loaded <- load_stats_config(config_path_args)
  cfg <- normalise_stats_config(loaded$config, loaded$base_dir)
  # 数据准备（第 0 步）**总是自动运行**（见下方第 0 步代码块），但**不占方法编号**：
  # 用户选的方法保持原有序号（01_、02_…），这样既有的脚本/对照习惯（如 01_independent_t_test.csv）不受影响。
  # 只有两种情况把 datacheck 作为独立章节列出：① 用户显式选了它；② 本次只跑数据准备。
  .needs_data <- any(cfg$method != "power")
  out_dir <- make_result_dir(cfg)
  file.copy(loaded$path, file.path(out_dir, paste0("config_snapshot.", tools::file_ext(loaded$path))), overwrite = TRUE)
  cat("Psychostat 心理统计模块运行中……\n")
  cat("方法：", paste(vapply(cfg$method, function(m) STATS_METHODS[[m]]$label_zh, character(1)), collapse = " → "), "\n")
  cat("结果目录：", out_dir, "\n\n")
  reset_report()
  stats_session$report <- c(
    sprintf("# Psychostat 心理统计教学报告\n\n生成时间：%s  \nR版本：%s  \n显著性水平 α = %s  \n",
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"), R.version.string, cfg$analysis$alpha),
    sprintf("数据来源：%s  \n\n", if (cfg$input$mode == "simulate") "内置模拟数据（结果目录中的 NN_方法_data.csv 可直接导入SPSS对照）" else cfg$input$path),
    "> **如何与SPSS对照**：把各模块的 `NN_方法_data.csv`（UTF-8-BOM编码）导入SPSS（文件>导入数据>CSV），按每个模块给出的\"SPSS操作路径\"点击运行，统计量应与各 `NN_方法_*.csv` 表格一致（t/F/χ²/H等在小数点后2-3位完全一致）。\n\n---\n"
  )
  write_method_guide(out_dir)
  total <- length(cfg$method)
  failed_methods <- character(0)

  # ── 第 0 步：数据准备（缺失值审计/处理、异常值筛查/处理、完整性检查）──────────
  # 只做一次，产物统一用 00_ 前缀；随后每个方法各自读取原始数据（保持互不影响的既有设计），
  # 由用户在 YAML 里指定 datacheck.missing_action / outlier_action 决定是否真正改动数据。
  if (.needs_data) {
    prep_ctx <- list(out_dir = out_dir, prefix = "00_prep", alpha = cfg$analysis$alpha, echo = TRUE)
    tryCatch({
      prep_data <- resolve_method_data(cfg, "datacheck")
      stats_session$report <- c(stats_session$report,
        "\n## 第 0 步 · 数据准备（缺失值与异常值）\n\n",
        "> 本节在任何统计分析之前运行，对应 SPSS 的【分析 > 描述统计 > 探索】与【分析 > 缺失值分析】。\n",
        "> 默认**只报告、不改动数据**；只有配置了 `datacheck.missing_action` / `datacheck.outlier_action` 才会处理。\n\n")
      run_datacheck(prep_data, cfg, prep_ctx)
      stats_session$report <- c(stats_session$report, "\n---\n")
    }, error = function(e) {
      msg <- conditionMessage(e)
      cat(sprintf("【数据准备失败】%s\n", msg))
      stats_session$report <- c(stats_session$report,
        sprintf("\n> ⚠ **数据准备未能完成**：%s  \n> 后续方法不受影响。\n\n---\n", msg))
    })
  }

  for (idx in seq_along(cfg$method)) {
    m <- cfg$method[idx]
    meta <- STATS_METHODS[[m]]
    banner(idx, total, meta$label_zh, meta$spss)
    start_report_section(idx, m, meta)
    ctx <- list(out_dir = out_dir, prefix = sprintf("%02d_%s", idx, m), alpha = cfg$analysis$alpha, echo = TRUE)
    # 单个方法失败不中止整次运行：记录原因并在报告该节标注，其余方法照常产出（全部失败才以非零退出）
    tryCatch({
      method_data <- NULL
      sim_fun <- paste0("simulate_", m)
      if (cfg$input$mode == "simulate" && exists(sim_fun)) {
        method_data <- get(sim_fun)(cfg)
        save_data(method_data, ctx)
        guide("【本例故事】", sim_story(m))
      } else if (cfg$input$mode == "file" && m != "power") {
        method_data <- read_stats_data(cfg$input$path)
      }
      if (m == "datacheck") {
        # 表格已在【第 0 步】以 00_data_* 前缀输出；此处只补配置说明，避免重复出表。
        guide("\n> **说明**：本模块的全部结果表已在上方【第 0 步 · 数据准备】一节输出（文件前缀 `00_prep_*`）。")
        guide("> 若要真正处理缺失值或异常值，请在配置里设置（不设置则一律只报告、不改动数据）：")
        guide(">   `datacheck.missing_action`: mean_impute | listwise | report")
        guide(">   `datacheck.outlier_action`: remove_by_z | report")
        guide(">   `datacheck.z_cutoff`: 3          # |Z| 阈值")
        guide(">   `datacheck.scale_range`: [1, 5]  # 可选：量表合法范围")
      }
      run_fun <- paste0("run_", m)
      run_preflight(method_data, cfg, ctx, m)
      get(run_fun)(method_data, cfg, ctx)
      .truth <- if (cfg$input$mode == "simulate") sim_truth(m) else NULL
      .truth <- if (is.null(.truth) || !length(.truth) || is.na(.truth[1])) "" else as.character(.truth[1])
      if (nzchar(.truth)) guide("\n【模拟真值】", .truth, "（数据由这些参数生成，检验结果应与之呼应）")
    }, error = function(e) {
      failed_methods <<- c(failed_methods, m)
      msg <- conditionMessage(e)
      cat(sprintf("【方法失败】%s：%s\n", meta$label_zh, msg))
      stats_session$report <- c(stats_session$report,
                                sprintf("\n> ⚠ **本方法未能完成**：%s  \n> 其余方法不受影响；请按提示调整变量设置后单独重跑本方法。\n\n---\n", msg))
    })
  }
  if (length(failed_methods)) {
    cat(sprintf("\n注意：%d/%d 个方法未能完成：%s（原因见上方各【方法失败】行；其余方法的结果与报告已正常生成）。\n",
                length(failed_methods), total, paste(failed_methods, collapse = ", ")))
    stats_session$report <- c(stats_session$report,
                              sprintf("\n---\n\n> ⚠ **运行提示**：本次 %d/%d 个方法未能完成（%s），原因见各节标注；其余方法结果不受影响。\n",
                                      length(failed_methods), total, paste(failed_methods, collapse = ", ")))
  }
  write_report(file.path(out_dir, "stats_report_zh.md"), header = "")
  writeLines(enc2utf8(c(
    "Psychostat 心理统计运行日志",
    paste("Run:", format(Sys.time(), "%FT%T%oz")),
    paste("R:", R.version.string),
    paste("Methods:", paste(cfg$method, collapse = ", ")),
    paste("Failed methods:", if (length(failed_methods)) paste(failed_methods, collapse = ", ") else "none"),
    paste("Input mode:", cfg$input$mode, if (cfg$input$mode == "file") cfg$input$path else ""),
    paste("Seed:", cfg$simulation$seed),
    "Note: 统计量与SPSS默认输出对齐（Type III SS、均值中心Levene、球形假定F、LSD/Tukey/Bonferroni、渐近Z含结点校正）；重复测量中若 Huynh-Feldt ε 估计 > 1 按 1 处理（SPSS 同样约定，不再打印警告）；模拟数据见各 NN_方法_data.csv。"
  )), file.path(out_dir, "run_log.txt"), useBytes = TRUE)
  write_run_manifest(out_dir, cfg, c("yaml", "jsonlite", "car", "emmeans", "nortest", "pwr", "ggplot2", "readxl", "haven", "MASS"),
                     paste(cfg$method, collapse = ", "), loaded$path)
  cat("\n完成。结果目录：", out_dir, "\n")
  cat("RESULT_DIR_UTF8_HEX=", paste(sprintf("%02X", as.integer(charToRaw(enc2utf8(normalizePath(out_dir))))), collapse = ""), "\n", sep = "")
  if (length(failed_methods) >= total) stopf("所有方法均失败（原因见上方各【方法失败】行）；请修正配置后重试。")
}

if (sys.nframe() == 0L) run_stats_pipeline()
