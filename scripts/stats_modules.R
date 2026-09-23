# Psychostat undergraduate statistics modules.  Each module provides simulate_<id>() and run_<id>() so the
# same code path serves the built-in teaching demos and user data files.  Every test mirrors IBM SPSS
# defaults (mean-centred Levene, Type III SS, sphericity-assumed F with Mauchly/GG/HF, LSD/Tukey/Bonferroni
# post hoc, asymptotic tie-corrected Z for rank tests) so numbers can be cross-checked against SPSS output.

fmt1 <- function(x) formatC(x, format = "f", digits = 1)
fmt2 <- function(x) formatC(x, format = "f", digits = 2)
fmt3 <- function(x) formatC(x, format = "f", digits = 3)

# Columns whose names look like IDs/metadata are excluded from automatic numeric-column selection
# (descriptives/correlation), so id/age/total-like columns are not silently summarised.
auto_numeric_cols <- function(data) {
  nms <- names(data)[vapply(data, is.numeric, logical(1))]
  drop <- grep("^id$|_id$|编号$|^no$", nms, value = TRUE, ignore.case = TRUE)
  setdiff(nms, drop)
}
meta_dropped_hint <- function(data, cols) {
  meta <- setdiff(names(data)[vapply(data, is.numeric, logical(1))], cols)
  if (length(meta)) guide("【提示】自动数值列已排除疑似 ID/元数据列：", paste(meta, collapse = ", "),
                          "；如确需分析请在配置 variables.columns 中显式列出。")
  invisible(NULL)
}

rnd <- function(df, digits = 3) {
  df[] <- lapply(df, function(z) if (is.numeric(z)) round(z, digits) else z)
  df
}

save_table <- function(df, ctx, name, caption = NULL) {
  path <- file.path(ctx$out_dir, sprintf("%s_%s.csv", ctx$prefix, name))
  write_csv_utf8(df, path)
  if (ctx$echo) {
    if (!is.null(caption)) guide("\n", caption, "  →  ", basename(path))
    print(rnd(df))
  }
  invisible(path)
}

save_data <- function(df, ctx, suffix = "data") {
  path <- file.path(ctx$out_dir, sprintf("%s_%s.csv", ctx$prefix, suffix))
  write_csv_bom(df, path)
  guide("\n【模拟数据】已保存（UTF-8-BOM，可直接导入SPSS）：", basename(path), "  （N = ", nrow(df), " 行）")
  invisible(path)
}

get_var <- function(cfg, key) as.character(cfg$variables[[key]] %||% "")
get_var_vector <- function(cfg, key) as_character_vector(cfg$variables[[key]])

need_var <- function(data, cfg, key, default = NULL) {
  v <- get_var(cfg, key)
  if (!nzchar(v)) {
    if (!is.null(default) && default %in% names(data)) return(default)
    stopf("配置缺少 variables.%s（本方法需要在数据中指定该列名）。", key)
  }
  if (!v %in% names(data)) stopf("variables.%s = '%s' 不在数据列中。可用列：%s", key, v, paste(names(data), collapse = ", "))
  v
}

num_col <- function(data, v) suppressWarnings(as.numeric(data[[v]]))
group_col <- function(data, v) {
  g <- data[[v]]
  if (is.numeric(g)) factor(g) else droplevels(as.factor(g))
}

# ─── 1. 描述统计 ───────────────────────────────────────────────────────────────
simulate_descriptives <- function(cfg) {
  set.seed(cfg$simulation$seed + 1L); n <- max(60L, cfg$simulation$n_per_group * 3L)
  anxiety <- pmax(20, pmin(80, round(45 + 12 * stats::rt(n, df = 8))))
  phone_hours <- round(stats::rgamma(n, shape = 1.5, rate = 0.4), 1)
  data.frame(id = sprintf("S%03d", seq_len(n)), anxiety = anxiety, phone_hours = phone_hours)
}

run_descriptives <- function(data, cfg, ctx) {
  cv <- get_var_vector(cfg, "columns")
  cols <- if (length(cv) && nzchar(cv[1])) cv else { c0 <- auto_numeric_cols(data); meta_dropped_hint(data, c0); c0 }
  cols <- cols[vapply(data[cols], function(z) is.numeric(z), logical(1))]
  if (!length(cols)) stopf("描述统计需要至少一个数值列。")
  guide("\n【什么时候用】给数据\"画像\"：集中量数（M）、差异量数（SD）、分布形态（偏度/峰度），是所有后续分析的第一步。")
  guide("【SPSS操作】分析 > 描述统计 > 描述（求M/SD/最值）；分析 > 描述统计 > 探索（含直方图/Q-Q图/正态性检验/异常值）。")
  rows <- lapply(cols, function(v) {
    x <- num_col(data, v); x <- x[is.finite(x)]
    sk <- spss_skewness(x); ku <- spss_kurtosis(x)
    data.frame(variable = v, N = length(x), min = min(x), max = max(x), mean = mean(x), sd = stats::sd(x),
               variance = stats::var(x), skewness = sk[["skewness"]], skewness_se = sk[["se"]],
               kurtosis = ku[["kurtosis"]], kurtosis_se = ku[["se"]], cv_pct = stats::sd(x) / abs(mean(x)) * 100)
  })
  tab <- do.call(rbind, rows)
  save_table(tab, ctx, "stats", "【表1】描述统计（SPSS: 分析>描述统计>描述；偏度/峰度及标准误对应\"探索\"输出）")
  guide("\n【结果怎么读】")
  guide("  · 平均数（mean）代表典型水平，标准差（sd）代表离散程度；两者一起报告：M ± SD。")
  guide("  · 偏度|skewness| > 1 提示明显偏态；峰度|kurtosis| > 1 提示尖峰（尾部较厚），两者结合判断分布形态。")
  guide("    分布明显偏离正态时，后续参数检验（t/ANOVA/回归）要谨慎，可考虑非参数方法（见模块15-18）。")
  guide("  · 变异系数 cv_pct = SD/M×100，用于比较\"单位不同或均值悬殊\"变量的相对离散度。")
  guide("\n【本例解读】")
  for (i in seq_len(nrow(tab))) {
    guide(sprintf("  · %s：M = %.2f, SD = %.2f，偏度 = %.2f%s。", tab$variable[i], tab$mean[i], tab$sd[i], tab$skewness[i],
                  ifelse(abs(tab$skewness[i]) >= 1, " → 明显偏态（|偏度|≥1）", "（|偏度|<1 视为近似正态）")))
  }
  ztab <- data.frame(id = if ("id" %in% names(data)) as.character(data$id) else seq_len(nrow(data)))
  for (v in cols) ztab[[paste0(v, "_z")]] <- round(as.numeric(scale(num_col(data, v))), 3)
  save_table(ztab, ctx, "zscores", "【表2】标准化Z分数（SPSS: 描述>勾选\"将标准化值另存为变量\"）")
  guide("\n【Z分数怎么用】Z = (X - M)/SD，表示该被试高于/低于平均水平多少个标准差；|Z| > 3 常作为异常值线索。")
  first <- cols[1]
  x <- num_col(data, first); x <- x[is.finite(x)]
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_histogram.png")), function() {
    graphics::hist(x, breaks = "Sturges", freq = FALSE, col = "#8FB8DE", border = "white",
                   xlab = first, ylab = "Density", main = paste("Histogram of", first))
    graphics::curve(stats::dnorm(x, mean(x), stats::sd(x)), add = TRUE, lwd = 2, col = "#B2182B")
  })
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_boxplot.png")), function() {
    graphics::boxplot(lapply(data[cols], function(z) z[is.finite(as.numeric(z))]), col = "#8FB8DE",
                      border = "#2166AC", ylab = "Score", main = "Boxplots (1.5*IQR rule)")
  })
  stem_txt <- paste(utils::capture.output(graphics::stem(x, scale = 2)), collapse = "\n")
  guide("\n【茎叶图】对应SPSS探索输出，可直接看到每个观测的位置：\n```\n", stem_txt, "\n```")
  invisible(NULL)
}

# ─── 2. 正态性与方差齐性检验 ──────────────────────────────────────────────────
simulate_normality <- function(cfg) {
  set.seed(cfg$simulation$seed + 2L); n <- cfg$simulation$n_per_group
  data.frame(id = sprintf("S%03d", seq_len(2 * n)),
             group = rep(c("traditional", "cooperative"), each = n),
             score = c(round(72 + 8 * stats::rnorm(n)), round(75 + 8 * stats::rnorm(n))))
}

run_normality <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "score"); y <- num_col(data, dv)
  # 与SPSS探索的默认一致：只放因变量时输出整体的正态性检验；仅当显式配置 variables.group 时才分组检验
  # （对应SPSS探索把分组变量放入"因子列表"）。
  gv <- get_var(cfg, "group")
  guide("\n【什么时候用】检验 t/ANOVA/回归的前提——数据是否近似正态；也是\"选参数还是非参数\"的第一步。")
  guide("【SPSS操作】分析 > 描述统计 > 探索：只放因变量 → 输出整体正态性（本模块默认）；")
  guide("  若把分组变量放入\"因子列表\" → 按组输出（配置 variables.group 后本模块同样按组输出）。")
  rows <- sw_ks_rows(y, paste0(dv, " 整体"))
  if (nzchar(gv)) rows <- rbind(rows, do.call(rbind, lapply(levels(group_col(data, gv)), function(lv)
    sw_ks_rows(y[group_col(data, gv) == lv], paste0(gv, "=", lv)))))
  save_table(rows, ctx, "normality_tests", "【表1】正态性检验（SPSS: 探索>绘制>带检验的正态图；未配置分组时与SPSS只放因变量的输出一致）")
  guide("\n【结果怎么读】")
  guide("  · Shapiro-Wilk（首选，适合N ≤ 5000）：p > .05 → 不能拒绝正态假设（通过）；p ≤ .05 → 偏离正态。")
  guide("  · K-S（Lilliefors校正）大样本时也常用；注意大样本时两者过于灵敏，一点点偏态就显著，")
  guide("    【与SPSS对照】SPSS 的 K-S(Lilliefors) 显著性显示上限为 .200——凡 p ≥ .2 都只显示 \".200\"；本表给出精确渐近值（如 .878），两者结论一致（p ≥ .05 → 不能拒绝正态）。")
  guide("    因此务必同时看直方图/Q-Q图和偏度峰度（|偏度|、|峰度| < 1 通常可接受参数检验）。")
  guide("\n【本例解读】")
  vio <- normality_violation_note(rows, ctx$alpha)
  if (!is.null(vio)) guide("  ", vio, "；其余已检验的变量·组段未见显著偏离正态。")
  ok <- normality_ok_note(rows, ctx$alpha)
  if (!is.null(ok)) guide("  ", ok, "可使用参数检验（t/ANOVA）。")
  un <- normality_untested_note(rows)
  if (!is.null(un)) guide("  ", un)
  if (nzchar(gv)) {
    g <- group_col(data, gv)
    lv <- levene_spss(y, g)
    save_table(data.frame(test = "Levene (基于均值)", F = lv$F, df1 = lv$df1, df2 = lv$df2, p = lv$p, sig = lv$p < ctx$alpha),
               ctx, "levene", "【表2】方差齐性检验（SPSS: 独立样本T检验第2张表首行，或单因素ANOVA>选项>方差齐性检验）")
    guide("\n【方差齐性怎么读】Levene p > .05 → 各组方差相等（用合并方差t，即\"假定方差相等\"行）；p ≤ .05 → 方差不齐（改读 Welch 校正行）。")
  }
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_qqplot.png")), function() {
    stats::qqnorm(y[is.finite(y)]); stats::qqline(y[is.finite(y)], col = "#B2182B", lwd = 2)
    graphics::title(paste("Normal Q-Q Plot:", dv))
  })
  invisible(NULL)
}

sw_ks_rows <- function(x, segment) {
  x <- x[is.finite(x)]
  sw <- if (length(x) >= 3L && length(x) <= 5000L) stats::shapiro.test(x) else NULL
  ks <- if (length(x) >= 5L) nortest::lillie.test(x) else NULL
  data.frame(segment = segment, N = length(x),
             # sw_tested 显式区分"未检验"与"检验不显著"：n<3 或 n>5000 时 S-W 不计算，
             # 下游结论句必须据此外显式声明"无法给出 S-W 结论"。
             sw_tested = !is.null(sw),
             sw_statistic = if (!is.null(sw)) unname(sw$statistic) else NA_real_,
             sw_p = if (!is.null(sw)) sw$p.value else NA_real_,
             ks_lilliefors_statistic = if (!is.null(ks)) unname(ks$statistic) else NA_real_,
             ks_lilliefors_p = if (!is.null(ks)) ks$p.value else NA_real_)
}

# ─── 3. 单样本 t 检验 ─────────────────────────────────────────────────────────
simulate_one_sample_t <- function(cfg) {
  set.seed(cfg$simulation$seed + 3L); n <- cfg$simulation$n_per_group
  data.frame(id = sprintf("S%03d", seq_len(n)), anxiety = round(56 + 9 * stats::rnorm(n)))
}

run_one_sample_t <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "anxiety"); mu <- as.numeric(cfg$variables$mu %||% 50)
  x <- num_col(data, dv); x <- x[is.finite(x)]; n <- length(x)
  guide("\n【什么时候用】想知道\"这一个样本的均值\"是否不同于某个已知总体值（常模、全国均值、理论中点等）。")
  guide("【SPSS操作】分析 > 比较均值 > 单样本T检验：检验变量 = ", dv, "，检验值 = ", mu, "。")
  stat <- data.frame(variable = dv, N = n, mean = mean(x), sd = stats::sd(x), se = stats::sd(x) / sqrt(n))
  save_table(stat, ctx, "stats", "【表1】单样本统计（SPSS: 单样本统计）")
  tt <- stats::t.test(x, mu = mu)
  d <- (mean(x) - mu) / stats::sd(x)
  test <- data.frame(t = unname(tt$statistic), df = unname(tt$parameter), p = tt$p.value,
                     mean_difference = unname(tt$estimate) - mu,
                     ci_lower_mean_difference = tt$conf.int[1] - mu, ci_upper_mean_difference = tt$conf.int[2] - mu, cohens_d = d)
  save_table(test, ctx, "test", "【表2】单样本检验（SPSS: 单样本检验；95%CI为均值与检验值之差的置信区间）")
  guide("\n【结果怎么读】")
  guide(sprintf("  · t(%d) = %s，%s（双尾）；均值差 = %s，95%%CI[%s, %s]。", n - 1L, fmt2(tt$statistic), fmt_p_inline(tt$p.value), fmt2(mean(x) - mu), fmt2(tt$conf.int[1]), fmt2(tt$conf.int[2])))
  guide(sprintf("  · p %s .05 → %s；Cohen's d = %s（%s）。", ifelse(tt$p.value < ctx$alpha, "<", "≥"),
                ifelse(tt$p.value < ctx$alpha, sprintf("样本均值与检验值%s显著不同（差异不能仅用抽样误差解释）", mu), "无充分证据表明与总体值不同"), fmt2(d), interpret_d(d)))
  dir1 <- two_group_direction(mean(x), mu, sprintf("%s 的样本均值", dv), sprintf("检验值 %s", fmt2(mu)))
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", dv, " 的样本均值（M = ", fmt2(mean(x)), "）", dir1[["txt"]],
        "：t(", n - 1L, ") = ", fmt2(tt$statistic), ", ", fmt_p_inline(tt$p.value), ", Cohen's d = ", fmt2(d), "（", interpret_d(d), "）。",
        ifelse(tt$p.value >= ctx$alpha, "本例 p 未达显著，规范写法应为\"无充分证据表明与检验值不同\"。", ""))
  guide("\n【注意】若数据严重偏态或为等级数据 → 用 Wilcoxon 符号秩检验（模块16）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_histogram_mean_mu.png")), function() {
    print(ggplot2::ggplot(data.frame(y = x), ggplot2::aes(x = y)) +
            ggplot2::geom_histogram(bins = 30, fill = "#8FB8DE", color = "white") +
            ggplot2::geom_vline(xintercept = mu, color = "#B2182B", linetype = "dashed", linewidth = 1) +
            ggplot2::geom_vline(xintercept = mean(x), color = "#2166AC", linewidth = 1) +
            ggplot2::annotate("text", x = mu, y = Inf, vjust = 2, hjust = -.05, color = "#B2182B",
                              label = sprintf("Test value mu = %.2f", mu)) +
            ggplot2::annotate("text", x = mean(x), y = Inf, vjust = 4, hjust = -.05, color = "#2166AC",
                              label = sprintf("Sample mean = %.2f", mean(x))) +
            ggplot2::labs(title = "One-sample t: distribution vs test value", x = dv, y = "Frequency") +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("单样本t检验分布图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 4. 独立样本 t 检验 ───────────────────────────────────────────────────────
simulate_independent_t <- function(cfg) {
  set.seed(cfg$simulation$seed + 4L)
  n1 <- cfg$simulation$n_per_group + 2L; n2 <- cfg$simulation$n_per_group - 2L
  data.frame(id = sprintf("S%03d", seq_len(n1 + n2)), gender = rep(c("male", "female"), c(n1, n2)),
             spatial_score = round(c(103 + 13 * stats::rnorm(n1), 94 + 13 * stats::rnorm(n2))))
}

run_independent_t <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "spatial_score"); gv <- need_var(data, cfg, "group", "gender")
  y <- num_col(data, dv); g <- group_col(data, gv)
  ok <- is.finite(y) & !is.na(g); y <- y[ok]; g <- droplevels(g[ok])
  if (nlevels(g) != 2L) stopf("独立样本t检验要求分组变量恰好2个水平，当前：%s", paste(levels(g), collapse = ", "))
  lev <- levels(g)
  guide("\n【什么时候用】比较两组互不干扰的均值（如 男 vs 女、实验组 vs 控制组）；因变量为连续数据且近似正态。")
  guide("【SPSS操作】分析 > 比较均值 > 独立样本T检验：检验变量 = ", dv, "，分组变量 = ", gv, "（定义组1/组2）。")
  gs <- do.call(rbind, lapply(lev, function(l) {
    x <- y[g == l]; data.frame(group = l, N = length(x), mean = mean(x), sd = stats::sd(x), se = stats::sd(x) / sqrt(length(x)))
  }))
  save_table(gs, ctx, "group_stats", "【表1】组统计量（SPSS: 组统计）")
  lv <- levene_spss(y, g)
  save_table(data.frame(levene_F = lv$F, df1 = lv$df1, df2 = lv$df2, levene_p = lv$p), ctx, "levene", "【表2】方差齐性 Levene 检验（SPSS: 独立样本检验表上半部分，基于均值）")
  te <- stats::t.test(y ~ g, var.equal = TRUE); tw <- stats::t.test(y ~ g, var.equal = FALSE)
  es <- cohens_d_independent(y, g)
  test <- data.frame(assumption = c("假定方差相等(合并t)", "不假定方差相等(Welch)"),
                     t = c(unname(te$statistic), unname(tw$statistic)),
                     df = c(unname(te$parameter), unname(tw$parameter)),
                     p = c(te$p.value, tw$p.value),
                     mean_difference = c(unname(te$estimate[1]) - unname(te$estimate[2]), unname(tw$estimate[1]) - unname(tw$estimate[2])),
                     ci_lower = c(te$conf.int[1], tw$conf.int[1]), ci_upper = c(te$conf.int[2], tw$conf.int[2]),
                     cohens_d = c(es[["d"]], es[["d"]]), hedges_g = c(es[["hedges_g"]], es[["hedges_g"]]))
  save_table(test, ctx, "test", "【表3】独立样本检验（SPSS: 独立样本检验下半部分；效应量对应SPSS 27+\"独立样本效应大小\"）")
  use_row <- if (lv$p >= ctx$alpha) "假定方差相等(合并t)" else "不假定方差相等(Welch)"
  trow <- test[test$assumption == use_row, ]
  guide("\n【三步读表法】")
  guide(sprintf("  第1步 看Levene：F(%d,%d) = %s，%s → %s，读\"%s\"行。", lv$df1, lv$df2, fmt2(lv$F), fmt_p_inline(lv$p),
                ifelse(lv$p >= ctx$alpha, "方差齐性满足", "方差不齐"), use_row))
  guide(sprintf("  第2步 看t行：t(%s) = %s，%s → 两组%s显著差异。", format(trow$df, digits = 4), fmt2(trow$t), fmt_p_inline(trow$p), ifelse(trow$p < ctx$alpha, "存在", "无证据表明存在")))
  guide(sprintf("  第3步 看效应量与方向：均值差 = %s（%s: M = %s vs %s: M = %s），Cohen's d = %s（%s）。",
                fmt2(trow$mean_difference), lev[1], fmt2(gs$mean[1]), lev[2], fmt2(gs$mean[2]), fmt2(es[["d"]]), interpret_d(es[["d"]])))
  gs1 <- gs$mean[match(lev[1], gs$group)]; gs2 <- gs$mean[match(lev[2], gs$group)]
  dir2 <- two_group_direction(gs1, gs2, lev[1], lev[2])
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", dir2[["txt"]], "：t(", format(trow$df, digits = 4), ") = ", fmt2(trow$t), ", ",
        fmt_p_inline(trow$p), ", Cohen's d = ", fmt2(es[["d"]]), "（", interpret_d(es[["d"]]), "）。",
        ifelse(trow$p >= ctx$alpha, "本例 p 未达显著，规范写法应为\"两组差异无统计学意义\"。", ""))
  guide("\n【常见错误】① 只报告p不报告效应量和方向；② Levene显著仍读第一行；③ 两组是同一批人（前后测）却用独立t → 应该用配对t。")
  guide("【与SPSS对照】t与差值的正负号取决于组别顺序：本表按列名字母序（female−male）计算，SPSS按你定义的组1/组2；对照时|t|与p完全一致，方向自行统一。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_boxplot.png")), function() {
    print(ggplot2::ggplot(data.frame(y = y, g = g), ggplot2::aes(x = g, y = y)) +
            ggplot2::geom_boxplot(fill = "#8FB8DE", color = "#2166AC") +
            ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5, color = "#B2182B") +
            ggplot2::labs(title = "Independent-samples t: group distributions (diamond = mean)", x = gv, y = dv) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("独立样本t检验箱线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 5. 配对样本 t 检验 ───────────────────────────────────────────────────────
simulate_paired_t <- function(cfg) {
  set.seed(cfg$simulation$seed + 5L); n <- cfg$simulation$n_per_group + 10L
  sig <- matrix(c(10, 6.5, 6.5, 10), 2, 2)
  xy <- MASS::mvrnorm(n, mu = c(52, 46), Sigma = sig)
  data.frame(id = sprintf("S%03d", seq_len(n)), pre = round(xy[, 1]), post = round(xy[, 2]))
}

run_paired_t <- function(data, cfg, ctx) {
  v1 <- need_var(data, cfg, "dv1", "pre"); v2 <- need_var(data, cfg, "dv2", "post")
  x <- num_col(data, v1); z <- num_col(data, v2)
  ok <- is.finite(x) & is.finite(z); x <- x[ok]; z <- z[ok]
  # SPSS 成对差 = 对话框里选择的 Variable1 − Variable2；演示数据列按字母序点选时即 后−前。
  # 默认 dv2 − dv1（后−前），可用 analysis.paired_direction: dv1_minus_dv2 切换。
  d <- if (identical(cfg$analysis$paired_direction, "dv1_minus_dv2")) x - z else z - x
  dlab <- if (identical(cfg$analysis$paired_direction, "dv1_minus_dv2")) "前−后" else "后−前"
  n <- length(d)
  guide("\n【什么时候用】同一批人测两次（前测/后测）或严格匹配的成对被试；差值近似正态。")
  guide("【SPSS操作】分析 > 比较均值 > 配对样本T检验：成对变量 = (", v1, ", ", v2, ")；")
  guide("  SPSS的成对差 = 你点选的 Variable1 − Variable2（变量列表按字母排序，点选顺序决定正负号）。")
  stats_tab <- data.frame(variable = c(v1, v2, paste0("差值(", dlab, ")")), N = c(n, n, n),
                          mean = c(mean(x), mean(z), mean(d)), sd = c(stats::sd(x), stats::sd(z), stats::sd(d)),
                          se = c(stats::sd(x) / sqrt(n), stats::sd(z) / sqrt(n), stats::sd(d) / sqrt(n)))
  save_table(stats_tab, ctx, "stats", "【表1】配对样本统计（SPSS: 配对样本统计）")
  ct <- stats::cor.test(x, z)
  save_table(data.frame(pair = paste(v1, "&", v2), N = n, r = unname(ct$estimate), p = ct$p.value),
             ctx, "correlation", "【表2】配对样本相关（SPSS: 配对样本相关；前后测相关高说明测量稳定）")
  tt <- if (identical(cfg$analysis$paired_direction, "dv1_minus_dv2")) stats::t.test(x, z, paired = TRUE) else stats::t.test(z, x, paired = TRUE)
  es <- cohens_d_paired(d)
  test <- data.frame(difference_direction = dlab, mean_difference = mean(d), sd_difference = stats::sd(d), se_difference = stats::sd(d) / sqrt(n),
                     t = unname(tt$statistic), df = n - 1L, p = tt$p.value,
                     ci_lower = tt$conf.int[1], ci_upper = tt$conf.int[2], cohens_d = es[["d"]])
  save_table(test, ctx, "test", sprintf("【表3】配对样本检验（SPSS: 配对样本检验；差值 = %s，95%%CI为差值的置信区间）", dlab))
  guide("\n【结果怎么读】")
  guide(sprintf("  · 差值均值（%s）= %s（从 %s 到 %s 平均变化%s），t(%d) = %s，%s，d = %s（%s）。",
                dlab, fmt2(mean(d)), v1, v2, ifelse(mean(d) > 0, ifelse(identical(dlab, "后−前"), "上升", "下降"), ifelse(identical(dlab, "后−前"), "下降", "上升")),
                n - 1L, fmt2(tt$statistic), fmt_p_inline(tt$p.value), fmt2(es[["d"]]), interpret_d(es[["d"]])))
  guide("  · 方向由差值均值符号决定（请结合变量含义解读升降的好坏）；如需反向，在配置 analysis.paired_direction 设为 dv1_minus_dv2。")
  guide("  · 与SPSS对照：|t|与p完全一致；正负号取决于SPSS里你点选配对的先后顺序。")
  rise <- mean(d) > 0
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", dlab, " = ", fmt2(mean(d)), "（",
        ifelse(rise, sprintf("%s 的平均水平高于 %s", v1, v2), sprintf("%s 的平均水平高于 %s", v2, v1)),
        "）：t(", n - 1L, ") = ", fmt2(tt$statistic), ", ", fmt_p_inline(tt$p.value), ", Cohen's d = ", fmt2(es[["d"]]), "（", interpret_d(es[["d"]]), "）。",
        ifelse(tt$p.value >= ctx$alpha, "本例 p 未达显著，规范写法应为\"前后测差异无统计学意义\"。", "升降的好坏需结合变量含义判断，本模板不作好坏评价。"))
  guide("\n【注意】差值严重偏态 → Wilcoxon 符号秩检验（模块17）；两组是不同的人 → 独立样本t（模块4）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_pre_post_lines.png")), function() {
    pd <- data.frame(subject = rep(seq_len(n), 2L),
                     cond = factor(rep(c(v1, v2), each = n), levels = c(v1, v2)),
                     y = c(x, z))
    md <- data.frame(cond = factor(c(v1, v2), levels = c(v1, v2)), m = c(mean(x), mean(z)))
    print(ggplot2::ggplot(pd, ggplot2::aes(x = cond, y = y)) +
            ggplot2::geom_line(ggplot2::aes(group = subject), color = grDevices::adjustcolor("#2166AC", .3), linewidth = .4) +
            ggplot2::geom_point(color = grDevices::adjustcolor("#2166AC", .4), size = .8) +
            ggplot2::geom_line(data = md, ggplot2::aes(x = cond, y = m, group = 1), inherit.aes = FALSE,
                               color = "#B2182B", linewidth = 1.2) +
            ggplot2::geom_point(data = md, ggplot2::aes(x = cond, y = m), inherit.aes = FALSE,
                                color = "#B2182B", size = 3) +
            ggplot2::labs(title = "Paired t: pre-post trajectories (bold red = means)", x = NULL, y = "Score") +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("配对t检验前后测连线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 6. 单因素方差分析 ────────────────────────────────────────────────────────
simulate_one_way_anova <- function(cfg) {
  set.seed(cfg$simulation$seed + 6L); n <- cfg$simulation$n_per_group + 5L
  k <- 3L
  data.frame(id = sprintf("S%03d", seq_len(n * k)),
             method = factor(rep(c("lecture", "inquiry", "flipped"), each = n),
                             levels = c("lecture", "inquiry", "flipped")),
             score = round(c(70 + 8 * stats::rnorm(n), 74 + 8 * stats::rnorm(n), 78 + 8 * stats::rnorm(n))))
}

run_one_way_anova <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "score"); gv <- need_var(data, cfg, "group", "method")
  y <- num_col(data, dv); g <- group_col(data, gv)
  ok <- is.finite(y) & !is.na(g); y <- y[ok]; g <- droplevels(g[ok])
  if (nlevels(g) < 3L) stopf("单因素ANOVA需要≥3个水平（2水平请用独立样本t），当前：%s", paste(levels(g), collapse = ", "))
  use_spss_contrasts()
  guide("\n【什么时候用】1个被试间自变量、≥3个水平；因变量连续、近似正态、各组方差齐性。")
  guide("【SPSS操作】分析 > 比较均值 > 单因素ANOVA：因变量 = ", dv, "，因子 = ", gv,
        "；选项勾选\"描述统计\"\"方差齐性检验\"；事后比较选 LSD/Tukey/Bonferroni。")
  desc <- do.call(rbind, lapply(levels(g), function(l) {
    x <- y[g == l]; data.frame(independent_variable = gv, dependent_variable = dv, group = l, N = length(x), mean = mean(x), sd = stats::sd(x), se = stats::sd(x) / sqrt(length(x)),
                               min = min(x), max = max(x))
  }))
  save_table(desc, ctx, "descriptives", "【表1】各组描述统计（SPSS: 单因素ANOVA>选项>描述统计）")
  lv <- levene_spss(y, g)
  save_table(data.frame(levene_F = lv$F, df1 = lv$df1, df2 = lv$df2, levene_p = lv$p), ctx, "levene", "【表2】方差齐性检验（SPSS: 方差齐性检验，基于均值）")
  fit <- stats::aov(y ~ g)
  tab <- summary(fit)[[1]]
  aov_tab <- data.frame(source = c("组间(自变量)", "组内(误差)", "总计"),
                        SS = c(tab[1, "Sum Sq"], tab[2, "Sum Sq"], sum(tab[, "Sum Sq"])),
                        df = c(tab[1, "Df"], tab[2, "Df"], sum(tab[, "Df"])),
                        MS = c(tab[1, "Mean Sq"], tab[2, "Mean Sq"], NA),
                        F = c(tab[1, "F value"], NA, NA), p = c(tab[1, "Pr(>F)"], NA, NA),
                        partial_eta_sq = c(partial_eta_sq(tab[1, "Sum Sq"], tab[2, "Sum Sq"]), NA, NA))
  save_table(aov_tab, ctx, "anova", "【表3】方差分析表（SPSS: ANOVA表；单因素设计中 η²p = η²）")
  Fv <- tab[1, "F value"]; pF <- tab[1, "Pr(>F)"]; et <- aov_tab$partial_eta_sq[1]
  guide("\n【结果怎么读（两步）】")
  guide(sprintf("  第1步 看F：F(%d, %d) = %s，%s → %s。Levene %s（%s）。",
                tab[1, "Df"], tab[2, "Df"], fmt2(Fv), fmt_p_inline(pF),
                ifelse(pF < ctx$alpha, "至少有两组均值不同（F显著只说明\"有差异\"，不指明谁和谁不同）", "各组均值无显著差异，分析到此为止（不要做事后比较）"),
                fmt_p_inline(lv$p), ifelse(lv$p >= ctx$alpha, "方差齐性满足", "方差不齐 → 改看Welch行，或用Kruskal-Wallis（模块17）")))
  guide(sprintf("  第2步 看效应量：η²p = %s（%s），自变量解释了因变量方差的%s%%。", fmt3(et), interpret_eta2(et), fmt1(et * 100)))
  guide("\n【第2步之后】F显著 → 必须做事后多重比较定位差异（表4-6）；F不显著 → 停止，不要再报告\"事后某对显著\"。")
  ph <- posthoc_tables(y, g, alpha = ctx$alpha)
  if ("lsd" %in% cfg$analysis$posthoc) save_table(ph$lsd, ctx, "posthoc_lsd", "【表4】事后比较-LSD（SPSS: 多重比较，未校正；最灵敏但Ⅰ类错误膨胀）")
  if ("tukey" %in% cfg$analysis$posthoc && !is.null(ph$tukey)) save_table(ph$tukey, ctx, "posthoc_tukey", "【表5】事后比较-Tukey HSD（SPSS: 多重比较；控制族Ⅰ类错误，组数多时推荐）")
  if ("bonferroni" %in% cfg$analysis$posthoc) save_table(ph$bonferroni, ctx, "posthoc_bonferroni", "【表6】事后比较-Bonferroni（SPSS: 多重比较；最保守）")
  welch <- stats::oneway.test(y ~ g, var.equal = FALSE)
  bf <- brown_forsythe_spss(y, g)
  robust <- data.frame(test = c("Welch ANOVA", "Brown-Forsythe"),
                       F = c(unname(welch$statistic), bf$F),
                       df1 = c(unname(welch$parameter[1]), bf$df1),
                       df2 = c(unname(welch$parameter[2]), bf$df2),
                       p = c(welch$p.value, bf$p))
  save_table(robust, ctx, "robust_tests", "【表7】稳健检验（SPSS: 均值齐性的稳健检验，方差不齐时报告）")
  sig_pairs <- ph$bonferroni[ph$bonferroni$p_adjusted < ctx$alpha, ]
  guide("\n【事后怎么选】LSD＝不校正（适合事先计划的验证性比较）；Tukey＝探索性整体比较首选；Bonferroni＝比较次数少且要求严格时。")
  guide("【本例事后结论（以Bonferroni为准）】",
        if (nrow(sig_pairs)) paste(vapply(seq_len(nrow(sig_pairs)), function(i) sprintf("%s vs %s：差 = %s，p = %s", sig_pairs$pair1[i], sig_pairs$pair2[i], fmt2(sig_pairs$difference[i]), fmt_p_inline(sig_pairs$p_adjusted[i])), character(1)), collapse = "；") else "经Bonferroni校正后没有显著配对。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】")
  guide("  ", sprintf("%s 对 %s 的影响%s：F(%s, %s) = %s, %s, η²p = %s（%s）。",
                      gv, dv, ifelse(pF < ctx$alpha, "显著", "不显著（不应再报告事后比较）"),
                      tab[1, "Df"], tab[2, "Df"], fmt2(Fv), fmt_p_inline(pF), fmt3(et), interpret_eta2(et)))
  guide("  各组均值关系：", levels_shape_note(desc$group, desc$mean), "。")
  if (nrow(sig_pairs)) {
    guide("  事后比较（Bonferroni）显著的配对：", pairwise_shape_note(sig_pairs$pair1, sig_pairs$pair2, sig_pairs$difference), "。")
  } else {
    guide("  事后比较：经 Bonferroni 校正后各配对差异均不显著。")
  }
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_means.png")), function() {
    graphics::barplot(desc$mean, names.arg = desc$group, col = "#8FB8DE", border = "#2166AC",
                      ylim = c(0, max(desc$mean + desc$se) * 1.15), ylab = "Mean", main = "Group means with SE bars")
    graphics::arrows(seq_along(desc$mean) - .35, desc$mean - desc$se, seq_along(desc$mean) - .35, desc$mean + desc$se, angle = 90, code = 3, length = .08)
  })
  invisible(NULL)
}

posthoc_tables <- function(y, g, alpha = 0.05) {
  g <- droplevels(as.factor(g)); lev <- levels(g); k <- length(lev)
  fit <- stats::aov(y ~ g); tab <- summary(fit)[[1]]
  mse <- tab[2, "Mean Sq"]; dfe <- tab[2, "Df"]; sp <- sqrt(mse)
  m <- k * (k - 1L) / 2L
  base <- do.call(rbind, utils::combn(lev, 2L, simplify = FALSE))
  mk <- function(padj_type) {
    out <- data.frame()
    for (i in seq_len(nrow(base))) {
      a <- y[g == base[i, 1]]; b <- y[g == base[i, 2]]
      diff <- mean(a) - mean(b); se <- sp * sqrt(1 / length(a) + 1 / length(b))
      tstat <- diff / se
      # CI 临界值必须跟随用户设定的 alpha：否则 alpha=.10 时会出现
      # "p_adj 显著"与"95%CI 含 0"并存的矛盾（SPSS 里二者同一个置信区间设置）。
      if (padj_type == "none") { p <- 2 * stats::pt(-abs(tstat), dfe); crit <- stats::qt(1 - alpha / 2, dfe) }
      else { p <- min(1, 2 * stats::pt(-abs(tstat), dfe) * m); crit <- stats::qt(1 - alpha / (2 * m), dfe) }
      out <- rbind(out, data.frame(pair1 = base[i, 1], pair2 = base[i, 2], difference = diff, se = se,
                                   t = tstat, p_adjusted = p, ci_lower = diff - crit * se, ci_upper = diff + crit * se))
    }
    out
  }
  tk <- if (k > 2L) as.data.frame(TukeyHSD(fit, which = "g")$g) else NULL
  tukey <- NULL
  if (!is.null(tk)) {
    # TukeyHSD 的行名是 "水平a-水平b"（a、b 来自 levels(g)，实际按"后一水平-前一水平"排序）。组名本身
    # 含连字符时（如 pre-test-post-test）用正则按第一个/最后一个连字符拆分会拆错，pair1/pair2 匹配不到
    # 任何水平，se/t 全为 NA。改为与 factor levels 的所有两两组合精确配对（两个顺序都尝试，paste 后与
    # 行名完全相等才算命中，pair1/pair2 按行名实际顺序取以保证差值方向不变）；找不到时才回退正则并警告。
    lev_pairs <- utils::combn(lev, 2L, simplify = FALSE)
    pair1 <- character(nrow(tk)); pair2 <- character(nrow(tk))
    for (r in seq_len(nrow(tk))) {
      rn <- rownames(tk)[r]
      hit <- which(vapply(lev_pairs, function(pr)
        identical(paste(pr[1], pr[2], sep = "-"), rn) || identical(paste(pr[2], pr[1], sep = "-"), rn),
        logical(1)))
      if (length(hit)) {
        pr <- lev_pairs[[hit[1]]]
        forward <- identical(paste(pr[1], pr[2], sep = "-"), rn)
        pair1[r] <- if (forward) pr[1] else pr[2]
        pair2[r] <- if (forward) pr[2] else pr[1]
      } else {
        pair1[r] <- sub("-.*", "", rn); pair2[r] <- sub(".*-", "", rn)
        warning(sprintf("TukeyHSD 行名 '%s' 无法与 factor levels 精确配对，已回退到正则拆分，请核对事后比较表的组名。", rn))
      }
    }
    n_tab <- table(g)
    se <- sp * sqrt(1 / as.numeric(n_tab[pair1]) + 1 / as.numeric(n_tab[pair2]))
    tukey <- data.frame(pair1 = pair1, pair2 = pair2, difference = tk$diff, se = se,
                        t = tk$diff / se, p_adjusted = tk$`p adj`,
                        ci_lower = tk$lwr, ci_upper = tk$upr)
  }
  list(lsd = mk("none"), bonferroni = mk("bonferroni"), tukey = tukey)
}

# ─── 7. 两因素方差分析（交互与简单效应） ─────────────────────────────────────
simulate_two_way_anova <- function(cfg) {
  set.seed(cfg$simulation$seed + 7L); n <- max(20L, cfg$simulation$n_per_group - 5L)
  cell <- expand.grid(method = c("lecture", "inquiry", "flipped"), motivation = c("low", "high"))
  mu <- c(lecture = 70, inquiry = 74, flipped = 78)
  add <- ifelse(cell$motivation == "high", 2, 0)
  add[cell$method == "flipped" & cell$motivation == "high"] <- 10
  rows <- do.call(rbind, lapply(seq_len(nrow(cell)), function(i) {
    data.frame(id = sprintf("S%03d", (i - 1L) * n + seq_len(n)), method = cell$method[i], motivation = cell$motivation[i],
               score = round(mu[cell$method[i]] + add[i] + 8 * stats::rnorm(n)))
  }))
  rows$method <- factor(rows$method, levels = c("lecture", "inquiry", "flipped"))
  rows$motivation <- factor(rows$motivation, levels = c("low", "high"))
  rows
}

run_two_way_anova <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "score"); fa <- need_var(data, cfg, "factor_a", "method"); fb <- need_var(data, cfg, "factor_b", "motivation")
  y <- num_col(data, dv); A <- group_col(data, fa); B <- group_col(data, fb)
  ok <- is.finite(y) & !is.na(A) & !is.na(B)
  dd <- data.frame(y = y[ok], A = droplevels(A[ok]), B = droplevels(B[ok]))
  use_spss_contrasts()
  guide("\n【什么时候用】2个被试间自变量（如 教学法×动机），同时考察两个主效应与一个交互效应；因变量连续。")
  guide("【SPSS操作】分析 > 一般线性模型 > 单变量：因变量 = ", dv, "，固定因子 = ", fa, ", ", fb,
        "；绘制：水平轴 = ", fa, "，单图 = ", fb, "（交互图）；EM均值：两因子都选入并勾选\"比较\"（简单效应）。")
  desc <- do.call(rbind, lapply(split(dd, interaction(dd$A, dd$B, sep = "_")), function(z)
    data.frame(A = z$A[1], B = z$B[1], N = nrow(z), mean = mean(z$y), sd = stats::sd(z$y), se = stats::sd(z$y) / sqrt(nrow(z)))))
  save_table(desc, ctx, "cell_descriptives", "【表1】单元格描述统计（SPSS: 单变量统计量）")
  lv <- levene_spss(dd$y, interaction(dd$A, dd$B))
  save_table(data.frame(levene_F = lv$F, df1 = lv$df1, df2 = lv$df2, levene_p = lv$p), ctx, "levene", "【表2】误差方差齐性检验（SPSS: Levene，基于均值，对6个单元格）")
  fit <- stats::aov(y ~ A * B, data = dd)
  tab <- anova_table_spss(fit, terms = c("A", "B", "A:B", "Residuals"))
  tab$source <- c(paste0(fa, " 主效应"), paste0(fb, " 主效应"), paste0(fa, " × ", fb, " 交互"), "误差")
  save_table(tab, ctx, "anova", "【表3】主体间效应检验（SPSS: 主体间效应的检验，Type III 平方和）")
  Fint <- tab$F[3]; pint <- tab$p[3]
  guide("\n【方差分析三步决策闭环（考试/论文必用）】")
  guide("  第1步 逐个看主效应：每个自变量\"单独\"是否有影响（表3前两行）。")
  guide(sprintf("  第2步 看交互：A×B 的 F = %s，%s。", fmt2(Fint), fmt_p_inline(pint)))
  if (pint < ctx$alpha) {
    guide("    ⚠️ 交互显著（p < .05）→ 主效应失去直接解释意义（一个变量的效果随另一变量的水平而变），必须进入第3步简单效应！")
  } else {
    guide("    ✅ 交互不显著 → 回头解释主效应；主效应显著且该因子>2水平时做事后比较。")
  }
  guide("  第3步 简单效应（两个方向都给出，按研究问题选一个方向用）：")
  guide("    ① 先看 表4\"简单效应总检验\"——固定一个变量的每个水平，检验另一变量的简单效应，由 emmeans 从2×3全模型估计并保留原模型误差项（对应SPSS一般线性模型EM均值的简单效应，比拆分文件后单因素ANOVA更准确：非均衡设计下误差项不变）；")
  guide("    ② 总F显著的那个方向，再用 表5/表6 的成对比较（Bonferroni）定位具体哪两个水平不同。")
  se_a <- spss_simple_effect_omnibus(fit, "A", "B")
  se_b <- spss_simple_effect_omnibus(fit, "B", "A")
  se_omni <- rbind(
    data.frame(
      direction = paste0(fa, " at ", fb, "=", se_a$by_level), test = "Full-model simple-effect F (EMMEANS)",
      F = se_a$F, df1 = se_a$df1, df2 = se_a$df2, p = se_a$p,
      partial_eta_sq = NA_real_
    ),
    data.frame(
      direction = paste0(fb, " at ", fa, "=", se_b$by_level), test = "Full-model simple-effect F (EMMEANS)",
      F = se_b$F, df1 = se_b$df1, df2 = se_b$df2, p = se_b$p,
      partial_eta_sq = NA_real_
    )
  )
  names(se_omni)[names(se_omni) == "direction"] <- "\u65b9\u5411"
  names(se_omni)[names(se_omni) == "test"] <- "\u68c0\u9a8c"
  save_table(se_omni, ctx, "simple_effects_omnibus",
             "【表4】简单效应总检验（双向都列出，交互显著后按研究问题选一个方向解读；简单效应由 emmeans 从全模型估计并保留原模型误差项，对应SPSS一般线性模型的EM均值简单效应）")
  sig_omni <- se_omni[se_omni$p < ctx$alpha, ]
  guide("\n【本例简单效应总检验结论】",
        if (nrow(sig_omni)) paste(sprintf("%s：F(%s, %s) = %s，%s", sig_omni$方向, format(sig_omni$df1), format(sig_omni$df2), fmt2(sig_omni$F), fmt_p_inline(sig_omni$p)), collapse = "；") else "各方向的简单效应均不显著。")
  t1 <- as.data.frame(emmeans::contrast(emmeans::emmeans(fit, ~ A | B), method = "pairwise", adjust = "bonferroni"))
  t2 <- as.data.frame(emmeans::contrast(emmeans::emmeans(fit, ~ B | A), method = "pairwise", adjust = "bonferroni"))
  t1_out <- data.frame(简单效应 = paste0(fa, " 在 ", fb, "=", t1$B), 对比 = t1$contrast, 差值 = t1$estimate,
                       se = t1$SE, df = t1$df, t = t1$t.ratio, p_bonferroni = t1$p.value)
  t2_out <- data.frame(简单效应 = paste0(fb, " 在 ", fa, "=", t2$A), 对比 = t2$contrast, 差值 = t2$estimate,
                       se = t2$SE, df = t2$df, t = t2$t.ratio, p_bonferroni = t2$p.value)
  save_table(t1_out, ctx, "simple_effects_a_by_b", "【表5】成对比较：A在各B水平（SPSS: EM均值>成对比较，Bonferroni；用于表4显著的方向）")
  save_table(t2_out, ctx, "simple_effects_b_by_a", "【表6】成对比较：B在各A水平（SPSS: EM均值>成对比较，Bonferroni；用于表4显著的方向）")
  emm <- as.data.frame(emmeans::emmeans(fit, ~ A * B))
  save_table(data.frame(A = emm$A, B = emm$B, emmean = emm$emmean, se = emm$SE, df = emm$df,
                        ci_lower = emm$lower.CL, ci_upper = emm$upper.CL),
             ctx, "emmeans", "【表7】估算边际均值（SPSS: EM均值表）")
  pd <- expand.grid(A = levels(dd$A), B = levels(dd$B))
  pd$mean <- as.vector(tapply(dd$y, list(dd$A, dd$B), mean))
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_interaction.png")), function() {
    print(ggplot2::ggplot(pd, ggplot2::aes(x = A, y = mean, group = B, color = B, shape = B)) +
            ggplot2::geom_point(size = 3) + ggplot2::geom_line(linewidth = 1) +
            ggplot2::labs(title = "Interaction / profile plot", x = fa, y = paste("mean of", dv)) + ggplot2::theme_minimal())
  })
  guide("\n【交互图怎么看】两条线平行 → 无交互；明显交叉/张口 → 有交互。本例 interaction.png 中线条",
        if (pint < ctx$alpha) "不平行（翻转课堂在高动机组抬升更多），与显著的交互效应一致。" else "基本平行，与不显著的交互一致。")
  sigA <- t1_out[t1_out$p_bonferroni < ctx$alpha, ]; sigB <- t2_out[t2_out$p_bonferroni < ctx$alpha, ]
  guide("\n【本例成对比较结论（用于表4中显著的简单效应方向）】")
  if (nrow(sigA)) guide("  · ", paste(sprintf("%s：%s（p = %s）", sigA$简单效应, sigA$对比, fmt_p_inline(sigA$p_bonferroni)), collapse = "；"))
  if (nrow(sigB)) guide("  · ", paste(sprintf("%s：%s（p = %s）", sigB$简单效应, sigB$对比, fmt_p_inline(sigB$p_bonferroni)), collapse = "；"))
  if (!nrow(sigA) && !nrow(sigB)) guide("  · 经Bonferroni校正后没有显著的成对比较。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】")
  guide("  ", sprintf("%s 与 %s 的交互效应%s：F(%s, %s) = %s, %s, η²p = %s。",
                      fa, fb, ifelse(tab$p[3] < ctx$alpha, "显著", "不显著"),
                      format(tab$df[3]), format(tab$df[4]), fmt2(tab$F[3]), fmt_p_inline(tab$p[3]), fmt3(tab$partial_eta_sq[3])))
  guide("  简单效应（表4）：", if (nrow(sig_omni)) "部分方向的简单效应显著，具体谁高谁低请对照表4-6的均值与配对结果自行表述。" else "各方向简单效应均不显著。")
  guide("\n【常见错误】① 交互显著却只报告主效应；② 做了简单效应却不再看成对比较定位差异；③ 把两个因子分开做两次单因素ANOVA（丢失交互信息）。")
  invisible(NULL)
}

# ─── 8. 重复测量方差分析 ──────────────────────────────────────────────────────
simulate_rm_anova <- function(cfg) {
  set.seed(cfg$simulation$seed + 8L); n <- cfg$simulation$n_per_group
  k <- 4L; mu <- c(52, 47, 44, 43); s <- 9; rho <- 0.55
  Sigma <- matrix(rho * s * s, k, k); diag(Sigma) <- s * s
  y <- MASS::mvrnorm(n, mu, Sigma)
  d <- as.data.frame(round(y)); names(d) <- c("time1_pre", "time2_1m", "time3_3m", "time4_6m")
  d$id <- sprintf("S%03d", seq_len(n)); d
}

run_rm_anova <- function(data, cfg, ctx) {
  wcols <- get_var_vector(cfg, "within")
  if (!length(wcols) || !nzchar(wcols[1])) wcols <- names(data)[vapply(data, is.numeric, logical(1))][seq_len(min(4L, sum(vapply(data, is.numeric, logical(1)))))]
  miss <- setdiff(wcols, names(data)); if (length(miss)) stopf("variables.within 中的列不存在：%s", paste(miss, collapse = ", "))
  wide <- as.data.frame(lapply(data[wcols], function(z) suppressWarnings(as.numeric(z))))
  wide <- wide[stats::complete.cases(wide), , drop = FALSE]
  n <- nrow(wide); k <- ncol(wide); labels <- wcols
  guide("\n【什么时候用】同一批被试在≥3个条件/时间点重复测量（前后测+追踪、多轮实验条件）。")
  guide("【SPSS操作】分析 > 一般线性模型 > 重复测量：定义被试内因子（名称如 time，级别数 = ", k,
        "）→ 把 ", paste(wcols, collapse = ", "), " 依次填入\"组内变量\"；选项勾选\"描述统计\"与\"方差齐性检验\"；EM均值做事后比较。")
  desc <- data.frame(time = labels, N = n, mean = colMeans(wide), sd = apply(wide, 2, stats::sd), se = apply(wide, 2, stats::sd) / sqrt(n))
  save_table(desc, ctx, "descriptives", "【表1】各时间点描述统计（SPSS: 描述统计）")
  mlm <- stats::lm(as.matrix(wide) ~ 1)
  idata <- data.frame(time = factor(seq_len(k), levels = as.character(seq_len(k)), labels = labels))
  ma <- car::Anova(mlm, idata = idata, idesign = ~ time, type = 3)
  sm <- suppressWarnings(summary(ma, multivariate = FALSE))
  u <- rm_univariate(sm, "time")
  ss_time <- u$SS; df_time <- u$df1; ss_err <- u$SS_err; df_err <- u$df2; F_time <- u$F; p_time <- u$p
  mt <- mauchly_table(sm, n = n, q = k - 1L); eps <- gg_hf_epsilons(sm)
  gg <- if (nrow(eps)) eps$GG_eps[1] else NA_real_; hf <- if (nrow(eps)) eps$HF_eps[1] else NA_real_
  ggp <- if (nrow(eps)) eps$GG_p[1] else NA_real_; hfp <- if (nrow(eps)) eps$HF_p[1] else NA_real_
  mauchly_out <- if (nrow(mt)) data.frame(term = "time", Mauchly_W = mt$Mauchly_W[1], chisq = mt$chisq[1], df = mt$df[1], p = mt$p[1]) else data.frame(term = "time", Mauchly_W = NA_real_, chisq = NA_real_, df = NA_real_, p = NA_real_)
  save_table(mauchly_out, ctx, "mauchly", "【表2】Mauchly球形检验（SPSS: Mauchly检验；p > .05 → 球形满足）")
  uni <- data.frame(row = c("假定球形(Sphericity Assumed)", "Greenhouse-Geisser校正", "Huynh-Feldt校正"),
                    SS = rep(ss_time, 3), df1 = c(df_time, df_time * gg, df_time * hf),
                    df2 = c(df_err, df_err * gg, df_err * hf),
                    MS = c(ss_time / df_time, ss_time / (df_time * gg), ss_time / (df_time * hf)), F = rep(F_time, 3),
                    p = c(p_time, ggp, hfp),
                    partial_eta_sq = rep(partial_eta_sq(ss_time, ss_err), 3))
  save_table(uni, ctx, "within_tests", "【表3】被试内效应检验（SPSS: 主体内效应检验；校正只改变df与p，F值不变）")
  guide("\n【怎么读重复测量输出（三步走）】")
  if (nrow(mt) && !is.na(mt$p[1])) guide(sprintf("  第1步 Mauchly：W = %s，%s → %s", fmt3(mt$Mauchly_W[1]), fmt_p_inline(mt$p[1]),
                                                ifelse(mt$p[1] >= ctx$alpha, "球形满足，读\"假定球形\"行", sprintf("球形不满足 → 读Greenhouse-Geisser行（ε = %s；GG ε > .75 时可用Huynh-Feldt ε = %s）", fmt3(gg), fmt3(hf)))))
  guide(sprintf("  第2步 时间效应：F(%s, %s) = %s，%s，η²p = %s（%s）。", fmt2(df_time), fmt2(df_err), fmt2(F_time), fmt_p_inline(p_time), fmt3(partial_eta_sq(ss_time, ss_err)), interpret_eta2(partial_eta_sq(ss_time, ss_err))))
  guide("  第3步 时间效应显著 → 做配对事后比较（Bonferroni）定位哪些时间点不同（表4）。")
  ph <- paired_posthoc(wide, alpha = ctx$alpha)
  save_table(ph, ctx, "posthoc_paired", "【表4】时间点两两比较（SPSS: 成对比较，Bonferroni；差值 = 早时间点 − 晚时间点，与SPSS (I)−(J) 一致）")
  sigp <- ph[ph$p_adjusted < ctx$alpha, ]
  guide("\n【本例事后结论】", if (nrow(sigp)) paste(sprintf("%s vs %s：差 = %s，p_adj = %s", sigp$pair1, sigp$pair2, fmt2(sigp$difference), fmt_p_inline(sigp$p_adjusted)), collapse = "；") else "经Bonferroni校正后无显著配对。")
  spheric <- is.na(mt$p[1]) || mt$p[1] >= ctx$alpha
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】")
  guide("  ", sprintf("被试内因素 %s 的主效应%s：F(%s, %s) = %s, %s, η²p = %s。",
                      paste(wcols, collapse = "/"), ifelse(ifelse(spheric, p_time, ggp) < ctx$alpha, "显著", "不显著"),
                      ifelse(spheric, fmt2(df_time), fmt2(df_time * gg)), ifelse(spheric, fmt2(df_err), fmt2(df_err * gg)),
                      fmt2(F_time), fmt_p_inline(ifelse(spheric, p_time, ggp)), fmt3(partial_eta_sq(ss_time, ss_err))))
  if (nrow(sigp)) {
    guide("  Bonferroni 事后比较显著的配对：", pairwise_shape_note(as.character(sigp$pair1), as.character(sigp$pair2), sigp$difference), "（详见表4）。")
  } else {
    guide("  Bonferroni 事后比较：各配对差异均不显著。")
  }
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_profile.png")), function() {
    pd <- data.frame(time = factor(rep(labels, each = n), levels = labels), y = as.vector(as.matrix(wide)))
    print(ggplot2::ggplot(pd, ggplot2::aes(time, y)) + ggplot2::stat_summary(fun = mean, geom = "point", size = 3) +
            ggplot2::stat_summary(fun = mean, geom = "line", ggplot2::aes(group = 1)) +
            ggplot2::stat_summary(fun.data = ggplot2::mean_se, geom = "errorbar", width = .1) +
            ggplot2::labs(title = "Profile plot of repeated measures", x = "Time", y = "Mean") + ggplot2::theme_minimal())
  })
  guide("\n【注意】① 球形不满足且GG ε < .75 → 更稳健的选择是多元检验或多层模型（高年级拓展）；② 只有2个时间点 → 配对t；③ 不同的人在不同条件 → 被试间设计，用单因素ANOVA。")
  invisible(NULL)
}

paired_posthoc <- function(wide, alpha = 0.05) {
  k <- ncol(wide); n <- nrow(wide); m <- k * (k - 1L) / 2L
  # 与 posthoc_tables 同理：CI 临界值跟随用户设定的 alpha
  crit <- stats::qt(1 - alpha / (2 * m), n - 1L)
  out <- data.frame()
  for (i in seq_len(k - 1L)) for (j in (i + 1L):k) {
    d <- wide[, i] - wide[, j]; se <- stats::sd(d) / sqrt(n); t <- mean(d) / se
    out <- rbind(out, data.frame(pair1 = names(wide)[i], pair2 = names(wide)[j], difference = mean(d), se = se, df = n - 1L,
                                 t = t, p_adjusted = min(1, 2 * stats::pt(-abs(t), n - 1L) * m),
                                 ci_lower = mean(d) - crit * se, ci_upper = mean(d) + crit * se))
  }
  out
}

# ─── 9. 混合设计方差分析 ──────────────────────────────────────────────────────
simulate_mixed_anova <- function(cfg) {
  set.seed(cfg$simulation$seed + 9L); n <- max(20L, cfg$simulation$n_per_group)
  k <- 3L; rho <- 0.6; s <- 7
  Sigma <- matrix(rho * s * s, k, k); diag(Sigma) <- s * s
  a <- MASS::mvrnorm(n, mu = c(52, 44, 43), Sigma)
  b <- MASS::mvrnorm(n, mu = c(52, 51, 50), Sigma)
  d <- rbind(as.data.frame(round(a)), as.data.frame(round(b)))
  names(d) <- c("time1_pre", "time2_post", "time3_followup")
  d$id <- sprintf("S%03d", seq_len(2 * n)); d$group <- rep(c("intervention", "control"), each = n); d
}

run_mixed_anova <- function(data, cfg, ctx) {
  wcols <- get_var_vector(cfg, "within")
  if (!length(wcols) || !nzchar(wcols[1])) wcols <- grep("^time", names(data), value = TRUE)
  miss <- setdiff(wcols, names(data)); if (length(miss)) stopf("variables.within 中的列不存在：%s", paste(miss, collapse = ", "))
  bv <- need_var(data, cfg, "between", "group")
  idv <- get_var(cfg, "id")
  if (!nzchar(idv) || !idv %in% names(data)) { data$.id <- seq_len(nrow(data)); idv <- ".id" }
  complete <- stats::complete.cases(data[c(wcols, bv)])
  data <- data[complete, , drop = FALSE]
  wide <- as.data.frame(lapply(data[wcols], function(z) suppressWarnings(as.numeric(z))))
  n <- nrow(wide); k <- ncol(wide)
  grp <- droplevels(group_col(data, bv)); id <- data[[idv]]
  if (!all(table(grp) >= 2L)) stopf("混合设计需要每组至少2名被试。")
  guide("\n【什么时候用】既有被试间因子（两组不同的人）又有被试内因子（每人重复测量），如 干预组/对照组 × 前/后/随访。")
  guide("【SPSS操作】分析 > 一般线性模型 > 重复测量：定义被试内因子 time（级别数 = ", k, "）→ 填入 ", paste(wcols, collapse = ", "),
        " → 被试间因子填 ", bv, "；绘制：水平轴 = time，单图 = ", bv, "；EM均值做简单效应。")
  long <- do.call(rbind, lapply(seq_len(k), function(j)
    data.frame(id = as.factor(id), group = grp, time = factor(wcols[j], levels = wcols), y = wide[, j])))
  cell <- do.call(rbind, lapply(split(long, interaction(long$group, long$time, drop = TRUE)), function(z)
    data.frame(group = z$group[1], time = z$time[1], N = nrow(z), mean = mean(z$y), sd = stats::sd(z$y), se = stats::sd(z$y) / sqrt(nrow(z)))))
  save_table(cell, ctx, "cell_descriptives", "【表1】单元格描述统计（SPSS: 描述统计）")
  use_spss_contrasts()
  fit <- stats::aov(y ~ group * time + Error(id / time), data = long)
  s <- summary(fit)
  # summary.aovlist names strata like "Error: id" / "Error: id:time"; match either naming.
  strat <- function(pat) { i <- grep(pat, names(s)); if (length(i)) normalise_anova_tab(s[[i[1]]]) else NULL }
  st_id <- strat("^Error: id$|^id$"); st_it <- strat("^Error: id:time$|^id:time$")
  term_row <- function(tab, row) if (is.null(tab) || !row %in% rownames(tab)) NULL else tab[row, ]
  r_group <- term_row(st_id, "group"); r_time <- term_row(st_it, "time"); r_int <- term_row(st_it, "group:time")
  res_between <- if (!is.null(st_id)) st_id["Residuals", ] else list(`Sum Sq` = NA_real_, Df = NA_real_)
  res_within <- if (!is.null(st_it)) st_it["Residuals", ] else list(`Sum Sq` = NA_real_, Df = NA_real_)
  res_between <- as.list(res_between); res_within <- as.list(res_within)
  mk <- function(r, res, label) {
    if (is.null(r)) return(data.frame(source = label, SS = NA_real_, df = NA_real_, MS = NA_real_, F = NA_real_, p = NA_real_, partial_eta_sq = NA_real_))
    data.frame(source = label, SS = r[["Sum Sq"]], df = r[["Df"]], MS = r[["Sum Sq"]] / r[["Df"]], F = r[["F value"]], p = r[["Pr(>F)"]],
               partial_eta_sq = partial_eta_sq(r[["Sum Sq"]], res[["Sum Sq"]]))
  }
  tab <- rbind(mk(r_group, res_between, paste0(bv, " 组间主效应")),
               mk(r_time, res_within, "time 被试内主效应"),
               mk(r_int, res_within, paste0(bv, " × time 交互")))
  save_table(tab, ctx, "anova", "【表2】混合设计效应检验（SPSS: 主体间/主体内效应检验，假定球形，Type III）")
  rm_fit <- spss_repeated_glm(wide, grp, wcols)
  fit_mlm <- rm_fit$fit
  sm <- rm_fit$summary
  u_group <- rm_univariate(sm, "grp")
  u_time <- rm_univariate(sm, "time")
  u_int <- rm_univariate(sm, "grp:time")
  ms_error <- u_int$SS_err / u_int$df2
  cell_emm <- stats::aggregate(y ~ group + time, data = long, FUN = mean)
  group_n <- table(grp)
  cell_emm$N <- as.integer(group_n[as.character(cell_emm$group)])
  cell_emm$SE <- sqrt(ms_error / cell_emm$N)
  save_table(cell_emm, ctx, "estimated_marginal_means", "Estimated marginal means: pooled within-subject error term (SPSS GLM)")
  mk_rm <- function(u, label) data.frame(source = label, SS = u$SS, df = u$df1, MS = u$SS / u$df1, F = u$F, p = u$p, partial_eta_sq = partial_eta_sq(u$SS, u$SS_err))
  tab <- rbind(
    mk_rm(u_group, paste0(bv, " between-subject main effect")),
    mk_rm(u_time, "time within-subject main effect"),
    mk_rm(u_int, paste0(bv, " x time interaction"))
  )
  save_table(tab, ctx, "anova", "Mixed-design Type III effects (SPSS GLM repeated-measures model)")
  mt <- mauchly_table(sm, n = n, q = k - 1L); eps <- gg_hf_epsilons(sm)
  within_rows <- function(u, term) {
    e <- eps[eps$term == term, , drop = FALSE]
    gg <- if (nrow(e)) e$GG_eps[1] else NA_real_
    hf <- if (nrow(e)) e$HF_eps[1] else NA_real_
    gp <- if (nrow(e)) e$GG_p[1] else NA_real_
    hp <- if (nrow(e)) e$HF_p[1] else NA_real_
    data.frame(
      term = term, row = c("Sphericity Assumed", "Greenhouse-Geisser", "Huynh-Feldt"), SS = u$SS,
      df1 = c(u$df1, u$df1 * gg, u$df1 * hf),
      df2 = c(u$df2, u$df2 * gg, u$df2 * hf),
      F = u$F, p = c(u$p, gp, hp), partial_eta_sq = partial_eta_sq(u$SS, u$SS_err)
    )
  }
  within_tests <- rbind(
    within_rows(u_time, "time"),
    within_rows(u_int, "grp:time")
  )
  save_table(within_tests, ctx, "within_tests", "Within-subject effects with SPSS sphericity corrections")
  if (nrow(mt)) save_table(data.frame(term = mt$term, Mauchly_W = mt$Mauchly_W, chisq = mt$chisq, df = mt$df, p = mt$p,
                                      GG_eps = eps$GG_eps[match(mt$term, eps$term)], HF_eps = eps$HF_eps[match(mt$term, eps$term)]),
                           ctx, "mauchly", "【表3】Mauchly球形检验（SPSS: Mauchly检验；p > .05 → 用假定球形行）")
  Fint <- u_int$F
  pint <- u_int$p
  df_int <- u_int$df1
  df_within_err <- u_int$df2
  guide("\n【怎么读混合设计输出】")
  guide("  · 组间主效应：两组在所有时间点上的总体差异（交互显著时无直接解释意义）。")
  guide("  · 被试内主效应 time：所有被试合并后随时间的变化。")
  guide(sprintf("  · 交互（重点！）：F(%s, %s) = %s，%s。", format(df_int), format(df_within_err), fmt2(Fint), fmt_p_inline(pint)))
  if (!is.na(pint) && pint < ctx$alpha) {
    guide("    ⚠️ 交互显著 → 效果取决于\"组别×时间\"的组合，必须做简单效应（表4、5）：")
    guide("    ① 每组内的时间变化（干预组是否真的在下降）；② 每个时间点的组间差异（后测/随访时两组是否拉开）。")
  } else {
    guide("    交互不显著 → 分别解释两个主效应即可。")
  }
  # 简单效应① 的两种算法：SPSS EMMEANS 对被试内因子的简单效应默认输出"多变量检验"（Pillai，合并误差）；
  # 拆分文件+重复测量得到"单变量假定球形"版。两者都给出，数值分别与 SPSS 两张表对应。
  U <- stats::contr.poly(k)
  Z <- as.matrix(wide) %*% U; colnames(Z) <- paste0("c", seq_len(k - 1L))
  dz <- data.frame(Z, grp = grp)
  old_ctr <- options(contrasts = c("contr.treatment", "contr.poly"))
  fitz <- stats::lm(as.matrix(dz[paste0("c", seq_len(k - 1L))]) ~ grp, data = dz)
  options(old_ctr)
  # ── SPSS 多变量检验（Pillai/Wilks/Hotelling/Roy）：对正交对比矩阵做 manova，
  #    Intercept 行 = time 主效应、grp 行 = 组别×时间交互（SPSS 重复测量默认输出的表之一）
  mv_rows <- do.call(rbind, lapply(c("Pillai", "Wilks", "Hotelling-Lawley", "Roy"), function(tt) {
    ms <- tryCatch(summary(stats::manova(fitz), test = tt, intercept = TRUE)$stats, error = function(e) NULL)
    if (is.null(ms) || !"(Intercept)" %in% rownames(ms)) return(NULL)
    rn <- rownames(ms)
    rbind(
      data.frame(effect = "time（被试内主效应）", statistic = tt, value = ms["(Intercept)", tt],
                 F = ms["(Intercept)", "approx F"], df1 = ms["(Intercept)", "num Df"], df2 = ms["(Intercept)", "den Df"],
                 p = ms["(Intercept)", "Pr(>F)"]),
      data.frame(effect = paste0(bv, " × time（交互）"), statistic = tt, value = ms["grp", tt],
                 F = ms["grp", "approx F"], df1 = ms["grp", "num Df"], df2 = ms["grp", "den Df"],
                 p = ms["grp", "Pr(>F)"]))
  }))
  if (!is.null(mv_rows) && nrow(mv_rows)) save_table(mv_rows, ctx, "multivariate_tests",
    "【表3b】多变量检验（SPSS: 多变量检验表——Pillai/Wilks/Hotelling/Roy 四种统计量；与单变量表并列输出）")
  # ── SPSS 被试内对比（多项式趋势分解）：每个正交对比列做 y~grp，
  #    截距 t² = time 的该阶趋势 F；grp 系数 t² = 组别×该阶趋势交互 F（通用算法，非数据拟合）
  trend_name <- function(j) switch(min(j, 5L), "线性", "二次", "三次", "四次", sprintf("%d次", j))
  trend_rows <- do.call(rbind, lapply(seq_len(k - 1L), function(j) {
    y <- dz[[paste0("c", j)]]
    lj <- stats::lm(y ~ grp, data = dz); co <- summary(lj)$coefficients
    ss_err <- sum(lj$residuals^2); N3 <- length(y); m3 <- mean(y)
    ss_time <- N3 * m3^2
    ss_int <- sum((lj$fitted.values - m3)^2)
    rbind(data.frame(effect = paste0("time（", trend_name(j), "）"), SS = ss_time, df = 1, MS = ss_time,
                     F = co[1, "t value"]^2, p = co[1, "Pr(>|t|)"], partial_eta_sq = ss_time / (ss_time + ss_err)),
          data.frame(effect = paste0(bv, " × time（", trend_name(j), "）"), SS = ss_int, df = 1, MS = ss_int,
                     F = co[2, "t value"]^2, p = co[2, "Pr(>|t|)"], partial_eta_sq = ss_int / (ss_int + ss_err)))
  }))
  save_table(trend_rows, ctx, "within_contrasts",
             "【表3c】被试内对比（SPSS: 被试内对比——time 与交互的线性/二次…趋势分解，同一误差项）")
  glv <- levels(grp)
  coef2 <- rownames(stats::coef(fitz))[2]
  multivar_rows <- do.call(rbind, lapply(glv, function(gv2) {
    hyp <- if (gv2 == glv[1]) "(Intercept) = 0" else paste0("(Intercept) + ", coef2, " = 0")
    lh <- car::linearHypothesis(fitz, hyp)
    pl <- grep("^Pillai", utils::capture.output(print(lh)), value = TRUE)[1]
    tk <- scan(text = pl, what = character(), quiet = TRUE)
    data.frame(group = gv2, 检验 = "多变量Pillai（SPSS EM均值简单效应）", test_statistic = as.numeric(tk[3]),
               F = as.numeric(tk[4]), df1 = as.numeric(tk[5]), df2 = as.numeric(tk[6]), p = as.numeric(tk[7]))
  }))
  univar_rows <- do.call(rbind, lapply(glv, function(gv2) {
    sub <- long[long$group == gv2, ]
    f2 <- stats::aov(y ~ time + Error(id / time), data = sub)
    s2 <- summary(f2)
    t2 <- normalise_anova_tab(s2[[grep("^Error: id:time$|^id:time$", names(s2))[1]]])
    data.frame(group = gv2, 检验 = "单变量假定球形（拆分文件重复测量）", test_statistic = NA_real_,
               F = t2["time", "F value"], df1 = t2["time", "Df"], df2 = t2["Residuals", "Df"], p = t2["time", "Pr(>F)"])
  }))
  se_time_by_group <- multivar_rows
  save_table(se_time_by_group, ctx, "simple_time_by_group",
             "【表4】简单效应①：各组内的时间效应（上2行=SPSS多变量检验Pillai默认输出；下2行=拆分文件单变量）")
  se_group_by_time <- do.call(rbind, lapply(levels(long$time), function(tv) {
    sub <- long[long$time == tv, ]
    tt <- stats::t.test(y ~ group, data = sub, var.equal = TRUE)
    d <- cohens_d_independent(sub$y, sub$group)
    data.frame(time = as.character(tv), t = unname(tt$statistic), df = unname(tt$parameter), p = tt$p.value,
               p_bonferroni = min(1, tt$p.value * k), cohens_d = d[["d"]])
  }))
  save_table(se_group_by_time, ctx, "simple_group_by_time", "【表5】简单效应②：各时间点的组间差异（独立t + Bonferroni校正）")
  group_pairs <- as.data.frame(summary(emmeans::contrast(emmeans::emmeans(fit_mlm, ~ grp), method = "pairwise", adjust = "bonferroni"), infer = c(TRUE, TRUE)))
  group_posthoc <- data.frame(effect = "group", contrast = group_pairs$contrast, mean_difference = group_pairs$estimate,
                              se = group_pairs$SE, df = group_pairs$df, t = group_pairs$t.ratio,
                              p_bonferroni = group_pairs$p.value, ci_lower = group_pairs$lower.CL, ci_upper = group_pairs$upper.CL)
  time_pairs <- paired_posthoc(wide, alpha = ctx$alpha)
  time_posthoc <- data.frame(effect = "time", contrast = paste(time_pairs$pair1, time_pairs$pair2, sep = " - "),
                             mean_difference = time_pairs$difference, se = time_pairs$se, df = time_pairs$df,
                             t = time_pairs$t, p_bonferroni = time_pairs$p_adjusted,
                             ci_lower = time_pairs$ci_lower, ci_upper = time_pairs$ci_upper)
  main_posthoc <- rbind(group_posthoc, time_posthoc)
  save_table(main_posthoc, ctx, "main_effects_posthoc", "Main-effect pairwise comparisons (Bonferroni)")

  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】")
  guide("  ", sprintf("组别与时间的交互效应%s：F(%s, %s) = %s, %s, η²p = %s。",
                      ifelse(pint < ctx$alpha, "显著", "不显著"), format(df_int), format(df_within_err),
                      fmt2(Fint), fmt_p_inline(pint), fmt3(tab$partial_eta_sq[3])))
  guide("  交互是否显著只说明\"组间差异随时间变化\"；具体哪个组在哪一时点更高，请对照单元格均值与简单效应表自行表述，本模板不作方向断言。")
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_profile.png")), function() {
    print(ggplot2::ggplot(long, ggplot2::aes(time, y, color = group, group = group)) +
            ggplot2::stat_summary(fun = mean, geom = "point", size = 3) + ggplot2::stat_summary(fun = mean, geom = "line", linewidth = 1) +
            ggplot2::stat_summary(fun.data = ggplot2::mean_se, geom = "errorbar", width = .1) +
            ggplot2::labs(title = "Mixed design profile plot", x = "Time", y = "Mean") + ggplot2::theme_minimal())
  })
  guide("\n【注意】两线交叉/张开是交互的直观证据；SPSS对被试内因子的简单效应默认打印\"多变量检验\"表（Pillai等4行）——对应表4上2行；若在SPSS拆分文件后做重复测量，则对应表4下2行（单变量假定球形）。")
  invisible(NULL)
}

# ─── 10. 协方差分析 ANCOVA ────────────────────────────────────────────────────
simulate_ancova <- function(cfg) {
  set.seed(cfg$simulation$seed + 10L); n <- cfg$simulation$n_per_group
  k <- 3L; pre <- 60 + 10 * stats::rnorm(n * k)
  add <- rep(c(24, 28, 31), each = n)
  data.frame(id = sprintf("S%03d", seq_len(n * k)),
             method = factor(rep(c("lecture", "inquiry", "flipped"), each = n), levels = c("lecture", "inquiry", "flipped")),
             pretest = round(pre, 1), posttest = round(0.6 * pre + add + 6 * stats::rnorm(n * k)))
}

run_ancova <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "posttest"); gv <- need_var(data, cfg, "group", "method"); cv <- need_var(data, cfg, "covariate", "pretest")
  y <- num_col(data, dv); g <- group_col(data, gv); x <- num_col(data, cv)
  ok <- is.finite(y) & is.finite(x) & !is.na(g)
  dd <- data.frame(y = y[ok], g = droplevels(g[ok]), x = x[ok])
  use_spss_contrasts()
  guide("\n【什么时候用】比较各组后测差异，同时把一个连续协变量（前测成绩、智商等）的个体差异\"统计控制\"掉，使组间比较更精确。")
  guide("【SPSS操作】分析 > 一般线性模型 > 单变量：因变量 = ", dv, "，固定因子 = ", gv, "，协变量 = ", cv,
        "；先在\"模型\"中定制 ", gv, "*", cv, " 交互验证斜率同质性，再回到只含主效应的模型。")
  f_slope <- stats::aov(y ~ g * x, data = dd)
  st <- anova_table_spss(f_slope, terms = c("g:x", "Residuals"))
  save_table(data.frame(source = paste0(gv, " * ", cv, "（斜率同质性）"), F = st$F[1], df1 = st$df[1], df2 = st$df[2], p = st$p[1]),
             ctx, "slope_homogeneity", "【表1】回归斜率同质性检验（ANCOVA前提：交互应不显著。注意这不是Levene检验！SPSS输出中位置相近但内容不同）")
  guide("\n【前提检查】", sprintf("斜率同质性 F(%s, %s) = %s，%s → %s。", format(st$df[1]), format(st$df[2]), fmt2(st$F[1]), fmt_p_inline(st$p[1]),
                                  ifelse(st$p[1] >= ctx$alpha, "满足（各组中协变量与因变量的关系一致），可以做ANCOVA", "不满足！不能直接做ANCOVA，考虑分组回归或Johnson-Neyman技术")))
  # SPSS 单变量GLM 另会输出"Levene's 同质性变异数检验"：基于含协变量全模型的残差做均值中心 Levene。
  fit_levene_base <- stats::lm(y ~ x + g, data = dd)
  lvr <- levene_spss(stats::resid(fit_levene_base), dd$g)
  save_table(data.frame(test = "Levene(全模型残差, 基于均值)", F = lvr$F, df1 = lvr$df1, df2 = lvr$df2, p = lvr$p),
             ctx, "levene_errorvar", "【表1b】误差方差齐性 Levene 检验（对应SPSS: Levene's 同質性變異數檢定，含协变量时基于模型残差）")
  fit <- stats::aov(y ~ x + g, data = dd)
  tab <- anova_table_spss(fit, terms = c("x", "g", "Residuals"))
  tab$source <- c(paste0(cv, " 协变量"), paste0(gv, " 组间(调整后)"), "误差")
  save_table(tab, ctx, "ancova", "【表2】协方差分析（SPSS: 主体间效应检验，Type III；核心看组间行）")
  emm_fit <- emmeans::emmeans(fit, specs = ~ g, at = list(x = mean(dd$x)))
  emm <- as.data.frame(emm_fit)
  save_table(data.frame(group = emm$g, adjusted_mean = emm$emmean, se = emm$SE, df = emm$df, ci_lower = emm$lower.CL, ci_upper = emm$upper.CL),
             ctx, "adjusted_means", "【表3】调整后均值（SPSS: EM均值，协变量取样本均值时各组的期望值）")
  pr <- as.data.frame(emmeans::contrast(emm_fit, method = "pairwise", adjust = "bonferroni"))
  pw <- data.frame(contrast = pr$contrast, difference = pr$estimate, se = pr$SE, df = pr$df, t = pr$t.ratio, p_bonferroni = pr$p.value)
  save_table(pw, ctx, "posthoc_adjusted", "【表4】调整后组间比较（SPSS: EM均值>成对比较，Bonferroni）")
  Fg <- tab$F[2]; pg <- tab$p[2]; et <- tab$partial_eta_sq[2]
  sigp <- pw[pw$p_bonferroni < ctx$alpha, ]
  guide("\n【结果怎么读】")
  guide(sprintf("  · 协变量行：%s 本身显著预测 %s（F = %s，%s）——这正是ANCOVA要\"控制掉\"的部分。", cv, dv, fmt2(tab$F[1]), fmt_p_inline(tab$p[1])))
  guide(sprintf("  · 组间行（核心）：F(%s, %s) = %s，%s，η²p = %s（%s）→ 控制协变量后各组%s差异。",
                format(tab$df[2]), format(tab$df[3]), fmt2(Fg), fmt_p_inline(pg), fmt3(et), interpret_eta2(et), ifelse(pg < ctx$alpha, "仍有", "无")))
  guide("  · 报告\"调整后均值\"（表3）而非原始均值——它排除了协变量差异的影响，与普通ANOVA表最大的不同。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】控制协变量后，组别对因变量的效应", ifelse(pg < ctx$alpha, "显著", "不显著"), "：F(", format(tab$df[2]), ", ", format(tab$df[3]), ") = ", fmt2(Fg), ", ", fmt_p_inline(pg), ", η²p = ", fmt3(et), "；调整后均值比较显示：",
        if (nrow(sigp)) paste(sprintf("%s（p = %s）", sigp$contrast, fmt_p_inline(sigp$p_bonferroni)), collapse = "、") else "各组两两差异不显著。")
  guide("\n【注意】① 非随机分组（如按班级）时，ANCOVA\"控制前测\"不等于随机等价，因果解释要谨慎；② 协变量测量应在处理之前；③ 常被用于\"前测→后测\"设计：比\"前后测差值t检验\"统计效力更高。")
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_ancova.png")), function() {
    print(ggplot2::ggplot(dd, ggplot2::aes(x = x, y = y, color = g)) + ggplot2::geom_point(alpha = .6) +
            ggplot2::geom_smooth(method = "lm", se = FALSE, linewidth = 1) +
            ggplot2::labs(title = "ANCOVA: per-group regression lines", x = cv, y = dv) + ggplot2::theme_minimal())
  })
  invisible(NULL)
}

# ─── 11. 相关分析（含偏相关） ─────────────────────────────────────────────────
simulate_correlation <- function(cfg) {
  set.seed(cfg$simulation$seed + 11L); n <- cfg$simulation$n_per_group * 4L
  R <- matrix(c(1, -.40, -.35, .65, -.40, 1, .45, -.35, -.35, .45, 1, -.40, .65, -.35, -.40, 1), 4, 4)
  z <- MASS::mvrnorm(n, mu = rep(0, 4), Sigma = R)
  data.frame(id = sprintf("S%03d", seq_len(n)),
             study_hours = round(22 + 6 * z[, 1], 1),
             phone_hours = round(4 + 2 * z[, 2], 1),
             test_anxiety = round(50 + 10 * z[, 3]),
             final_grade = round(65 + 8 * z[, 4]))
}

run_correlation <- function(data, cfg, ctx) {
  cols <- get_var_vector(cfg, "columns")
  if (!length(cols) || !nzchar(cols[1])) { cols <- auto_numeric_cols(data); meta_dropped_hint(data, cols) }
  miss <- setdiff(cols, names(data)); if (length(miss)) stopf("variables.columns 中的列不存在：%s", paste(miss, collapse = ", "))
  # 偏相关控制列允许不在 columns 里（GUI/终端是单独选择的）：并入数据矩阵保证按同一套完整观测计算；
  # 两两相关表（表1与矩阵）仍只报告用户选定的 columns。
  pcs_req <- get_var_vector(cfg, "partial_control")
  extra_cols <- setdiff(pcs_req, cols)
  if (length(extra_cols)) {
    missx <- setdiff(extra_cols, names(data))
    if (length(missx)) stopf("variables.partial_control 中的列不存在：%s", paste(missx, collapse = ", "))
  }
  X <- as.data.frame(lapply(data[c(cols, extra_cols)], function(z) suppressWarnings(as.numeric(z))))
  complete <- stats::complete.cases(X); X <- X[complete, , drop = FALSE]; n <- nrow(X)
  guide("\n【什么时候用】考察两个连续变量的关联方向与强度。Pearson：双变量近似正态的连续数据；Spearman：等级或严重偏态；二分×连续 → 点二列相关（数值上=把0/1当连续做Pearson）。")
  guide("【SPSS操作】分析 > 相关 > 双变量：选入 ", paste(cols, collapse = ", "), "，勾选 Pearson/Spearman，双尾显著性。偏相关：分析 > 相关 > 偏相关（控制变量放入\"控制\"框）。")
  methods <- switch(cfg$analysis$correlation_method, pearson = "pearson", spearman = "spearman", both = c("pearson", "spearman"))
  long_rows <- list()
  for (mth in methods) {
    for (i in seq_along(cols)) for (j in (i + 1L):length(cols)) {
      if (j > length(cols)) break
      ct <- suppressWarnings(stats::cor.test(X[[i]], X[[j]], method = mth))
      r <- unname(ct$estimate)
      ci <- if (mth == "pearson") tanh(atanh(r) + c(-1, 1) * stats::qnorm(0.975) / sqrt(n - 3)) else c(NA_real_, NA_real_)
      long_rows[[length(long_rows) + 1L]] <- data.frame(method = mth, var1 = cols[i], var2 = cols[j], N = n,
                                                        r = r, p = ct$p.value, ci95_lower = ci[1], ci95_upper = ci[2])
    }
  }
  long_tab <- do.call(rbind, long_rows)
  save_table(long_tab, ctx, "correlations", "【表1】两两相关（SPSS: 相关性表；95%CI为Fisher变换补充，SPSS默认不输出）")
  for (mth in methods) {
    cm <- stats::cor(X[cols], method = mth)
    save_table(as.data.frame(cm), ctx, paste0("matrix_r_", mth), sprintf("【%s】相关系数矩阵r（SPSS: 相关性下三角，*p<.05）", mth))
    pm <- outer(cols, cols, Vectorize(function(a, b) suppressWarnings(stats::cor.test(X[[a]], X[[b]], method = mth)$p.value)))
    dimnames(pm) <- dimnames(cm)
    save_table(as.data.frame(pm), ctx, paste0("matrix_p_", mth), sprintf("【%s】显著性矩阵p（SPSS: 相关性表中的Sig.）", mth))
  }
  # 偏相关：默认取前两列为 x/y、第三列为控制变量；列不足3个或未配置时跳过（避免任意默认列导致的错误）。
  pcs <- get_var_vector(cfg, "partial_control")
  px <- get_var(cfg, "partial_x"); py <- get_var(cfg, "partial_y")
  if (!px %in% cols) px <- cols[1]
  if (!py %in% cols) py <- if (length(cols) >= 2L) cols[2] else cols[1]
  pcs <- intersect(pcs, setdiff(c(cols, extra_cols), c(px, py)))
  has_requested_control <- length(pcs) > 0L
  if (!length(pcs)) {
    rest <- setdiff(cols, c(px, py))
    if (length(rest) >= 1L) pcs <- rest[1]
  }
  if (!has_requested_control) pcs <- character()
  if (length(pcs) && !identical(px, py)) {
    pc <- tryCatch(partial_cor(X[[px]], X[[py]], X[pcs]), error = function(e) NULL)
    if (is.null(pc)) {
      guide("\n【偏相关】计算失败（控制变量可能是常数列或存在共线），已跳过；请检查 variables.partial_control 指定的列。")
    } else {
    save_table(data.frame(x = px, y = py, controlling = paste(pcs, collapse = "+"), r_partial = pc$r, df = pc$df, t = pc$t, p = pc$p),
               ctx, "partial_correlation", "【表2】偏相关（SPSS: 偏相关表；默认x/y取前两列、控制变量取第三列，可用 variables.partial_x/partial_y/partial_control 指定）")
    r0 <- stats::cor(X[[px]], X[[py]])
    guide(sprintf("\n【偏相关怎么读】%s 与 %s 的零阶 r = %s；控制 %s 后 r_partial = %s（%s）。控制后相关大幅下降 → 原相关部分由第三变量解释；控制后仍显著 → 存在独特关联。",
                  px, py, fmt2(r0), paste(pcs, collapse = "+"), fmt2(pc$r), fmt_p_inline(pc$p)))
    }
  } else {
    guide("\n【偏相关】需要至少3个数值列（默认 x/y 取前两列、控制变量取第三列）；当前列不足或已用于 x/y，故跳过。可用 variables.partial_x / partial_y / partial_control 指定。")
  }
  guide("\n【结果怎么读】")
  guide("  · r的符号 = 方向；|r| 大小 = 强度（.10小/.30中/.50大）；r² = 一个变量能解释另一个变量方差的比例。")
  guide("  · p < .05 只说明\"总体相关非零\"；大样本时 r = .15 也会显著——务必同时报告效应量 r。")
  guide("  · 相关 ≠ 因果：学习时间与成绩相关 ≠ 增加学习时间必然提高成绩（第三变量、反向因果都可能）。")
  guide("\n【本例解读】")
  for (mth in methods) {
    sub <- long_tab[long_tab$method == mth & long_tab$p < ctx$alpha, ]
    if (nrow(sub)) guide(sprintf("  · %s 显著相关：%s。", mth, paste(sprintf("%s–%s：r = %s（%s）", sub$var1, sub$var2, fmt2(sub$r), interpret_r(sub$r)), collapse = "；")))
  }
  # 该模板句只适用于内置模拟数据的固定列名（study_hours / final_grade）：必须整块受 if 保护。
  # 之前缺 `{`，if 只作用到第一行，其余行无条件执行 → 真实数据文件（列名不同）时 .v1/.v2 未定义，
  # 运行到这里抛 "object '.v1' not found"，整个 correlation 方法失败（R 非 0 退出 → 报告不再生成）。
  if (all(c("study_hours", "final_grade") %in% names(X))) {
    .v1 <- names(X)[1]; .v2 <- names(X)[2]
    .r <- suppressWarnings(stats::cor(X[[1]], X[[2]])); .p <- suppressWarnings(stats::cor.test(X[[1]], X[[2]])$p.value)
    .dir <- ifelse(!is.finite(.r), "（相关无法计算）", ifelse(.r > 0, "正相关", ifelse(.r < 0, "负相关", "无线性相关")))
    guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", .v1, " 与 ", .v2, " 呈", .dir, "（r = ", fmt2(.r), "，", fmt_p_inline(.p), "，r² = ",
          fmt2(.r^2), "，即解释 ", .v2, " 方差的 ", fmt1(.r^2 * 100), "%）。相关不等于因果，报告时避免因果表述。")
  }
  if (length(cols) >= 2L) save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_scatter.png")), function() {
    sdf <- X[1:2]; names(sdf) <- c("xvar", "yvar")
    print(ggplot2::ggplot(sdf, ggplot2::aes(x = xvar, y = yvar)) + ggplot2::geom_point(alpha = .6) +
            ggplot2::geom_smooth(method = "lm", se = TRUE) + ggplot2::labs(title = "Scatter with regression line", x = cols[1], y = cols[2]) + ggplot2::theme_minimal())
  })
  guide("\n【注意】① 有极端值/曲线关系时Pearson失真（先看散点图）；② 等级数据用Spearman；③ 报告显著相关时给出N与双尾/单尾。")
  invisible(NULL)
}

partial_cor <- function(x, y, z) {
  z <- as.data.frame(z); n <- length(x)
  rx <- stats::resid(stats::lm(x ~ as.matrix(z))); ry <- stats::resid(stats::lm(y ~ as.matrix(z)))
  r <- stats::cor(rx, ry); df <- n - ncol(z) - 2L
  t <- r * sqrt(df / (1 - r^2))
  list(r = r, df = df, t = t, p = 2 * stats::pt(-abs(t), df))
}

# ─── 12. 多元线性回归（含交互与简单斜率） ────────────────────────────────────
simulate_regression <- function(cfg) {
  set.seed(cfg$simulation$seed + 12L); n <- cfg$simulation$n_per_group * 5L
  hours <- 22 + 6 * stats::rnorm(n); iq <- 105 + 12 * stats::rnorm(n); anx <- 50 + 10 * stats::rnorm(n)
  grade <- 20 + 0.5 * hours + 0.35 * (iq - 100) - 0.25 * (anx - 50) + 6 * stats::rnorm(n)
  d <- data.frame(id = sprintf("S%03d", seq_len(n)), study_hours = round(hours, 1), iq = round(iq),
                  test_anxiety = round(anx), final_grade = round(grade))
  set.seed(cfg$simulation$seed + 120L)
  mot <- pmax(1, pmin(7, round(4 + 1.2 * stats::rnorm(n))))
  res <- pmax(1, pmin(7, round(4 + 1.2 * stats::rnorm(n))))
  g2 <- 40 + 3.5 * (mot - 4) + 3 * (res - 4) + 1.6 * (mot - 4) * (res - 4) + 5 * stats::rnorm(n)
  d$motivation <- mot; d$learning_resources <- res; d$engagement_score <- round(g2)
  d
}

run_regression <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "final_grade")
  preds <- get_var_vector(cfg, "predictors")
  if (!length(preds) || !nzchar(preds[1])) {
    demo_preds <- intersect(c("study_hours", "iq", "test_anxiety"), names(data))
    preds <- if (length(demo_preds) >= 2L) demo_preds else setdiff(names(data)[vapply(data, is.numeric, logical(1))], dv)
  }
  preds <- preds[preds %in% names(data)]
  num_ok <- preds[vapply(data[preds], is.numeric, logical(1))]
  if (length(setdiff(preds, num_ok))) stopf("回归自变量需为数值列（分类变量请先做0/1哑变量，与SPSS操作一致）。非数值列：%s", paste(setdiff(preds, num_ok), collapse = ", "))
  preds <- num_ok
  if (!length(preds)) stopf("回归需要至少一个数值型自变量（variables.predictors）。")
  dd <- data[c(dv, preds)]; dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  old_contrasts <- options(contrasts = c("contr.treatment", "contr.poly"))
  on.exit(options(old_contrasts), add = TRUE)
  guide("\n【什么时候用】用一个或多个自变量预测连续因变量；回答\"哪些变量有独特预测作用、方向如何、整体解释力多大\"。")
  guide("【SPSS操作】分析 > 回归 > 线性：因变量 = ", dv, "，自变量 = ", paste(preds, collapse = ", "), "，方法 = 输入(Enter，默认全部进入)；统计量里勾选\"估算值\"\"模型拟合\"\"共线性诊断\"\"Durbin-Watson\"。")
  # ── 列名安全化（仅供建模内部使用）────────────────────────────────────────────
  # 问卷表头常含空格、`-`、顿号、括号、前导数字。直接拼进 as.formula() 会被当成运算符
  # （列名 "T1-T3总分" 会被解析为 T1 减 T3）→ 模型静默变形或 object not found。
  # 因此把参与公式的列在本函数内部改名为 ASCII 安全名；所有输出表/文字按 `.orig()` 还原原名。
  dv0 <- dv; preds0 <- preds
  .m <- formula_name_mapping(c(dv0, preds0))
  dd <- rename_for_formula(dd, .m)
  dv <- unname(.m[dv0]); preds <- unname(.m[preds0])
  .orig <- function(x) { r <- names(.m)[match(x, unname(.m))]; ifelse(is.na(r), x, r) }
  .bad <- unsafe_formula_names(c(dv0, preds0))
  if (length(.bad)) guide("  列名说明：以下列名不是合法的 R 变量名（含空格/`-`/顿号/括号/前导数字等），已在模型内部改用安全名计算，表格仍按原列名显示：",
                          paste(.bad, collapse = "、"), "。注意形如 `A-B` 的列名在 R 公式中会被解释为运算，本工具已替你规避。")
  fit <- stats::lm(stats::as.formula(paste(dv, "~", paste(preds, collapse = " + "))), data = dd)
  s <- summary(fit); n <- nrow(dd); k <- length(preds)
  dw <- sum(diff(fit$residuals)^2) / sum(fit$residuals^2)
  model_summary <- data.frame(R = sqrt(s$r.squared), R_squared = s$r.squared, adjusted_R_squared = s$adj.r.squared,
                              SE_of_estimate = s$sigma, Durbin_Watson = dw)
  save_table(model_summary, ctx, "model_summary", "【表1】模型汇总（SPSS: 模型汇总；Durbin-Watson≈2表示残差独立）")
  # 整体模型检验：与SPSS"ANOVA表"一致（回归SS=模型SS，F来自summary的fstatistic；不要用anova()逐行拆解）。
  SSE <- sum(fit$residuals^2); SST <- sum((dd[[dv]] - mean(dd[[dv]]))^2); SSR <- SST - SSE
  fstat <- s$fstatistic
  anova_tab <- data.frame(model = c("回归(Regression)", "残差(Residual)", "总计(Total)"),
                          SS = c(SSR, SSE, SST),
                          df = c(fstat[["numdf"]], fstat[["dendf"]], fstat[["numdf"]] + fstat[["dendf"]]),
                          MS = c(SSR / fstat[["numdf"]], SSE / fstat[["dendf"]], NA),
                          F = c(unname(fstat[["value"]]), NA, NA), p = c(stats::pf(fstat[["value"]], fstat[["numdf"]], fstat[["dendf"]], lower.tail = FALSE), NA, NA))
  save_table(anova_tab, ctx, "anova", "【表2】回归方差分析（SPSS: ANOVA表——整体模型检验，对应summary的F值）")
  # 分层回归（SPSS「块」语义）：variables.blocks 指定每块自变量（GUI/终端会询问；配置可写
  # list(c("性别","年龄"), c("焦虑","压力")) 或字符串 "性别,年龄|焦虑,压力"）。严格对应 SPSS 线性回归
  # 对话框分多个"块"依次进入（方法=输入）：每个模型输出 R/R²/调整R²/ΔR²/F变更/Sig，以及各模型的系数表。
  raw_blocks <- cfg$variables$blocks
  blk <- NULL
  as_char_vec <- function(b) if (is.character(b)) trimws(b) else if (is.list(b)) trimws(as.character(unlist(b))) else character(0)
  if (!is.null(raw_blocks)) {
    if (is.character(raw_blocks)) {
      parts <- strsplit(paste(raw_blocks, collapse = "|"), "|", fixed = TRUE)[[1]]
      blk <- lapply(parts, function(s) trimws(strsplit(gsub("^[,;、\\s]+|[,;、\\s]+$", "", s), "[,;、]+")[[1]]))
    } else if (is.list(raw_blocks)) {
      blk <- lapply(raw_blocks, as_char_vec)   # JSON 走 simplifyVector=FALSE：每块是 list(scalars)
    }
    blk <- Filter(function(b) length(b) > 0L && all(nzchar(b)), blk)
    # 分层回归的块用的是原始列名，这里统一换成安全名（未列出的名字保持原样）
    if (!is.null(blk)) blk <- lapply(blk, function(b) ifelse(b %in% names(.m), unname(.m[b]), b))
  }
  if (!is.null(blk) && length(blk) >= 2L) {
    unknown <- setdiff(unique(unlist(blk)), preds)
    if (length(unknown)) stopf("variables.blocks 中的变量不在自变量列表内：%s（请检查分层设置）", paste(unknown, collapse = ", "))
    cum <- NULL; hier <- data.frame(); coef_blocks <- list()
    for (j in seq_along(blk)) {
      cum <- c(cum, blk[[j]])
      fj <- stats::lm(stats::as.formula(paste(dv, "~", paste(cum, collapse = " + "))), data = dd)
      sj <- summary(fj)
      r2_j <- sj$r.squared
      if (j == 1L) {
        df1c <- sj$fstatistic[["numdf"]]; df2c <- sj$fstatistic[["dendf"]]
        fc <- unname(sj$fstatistic[["value"]]); pc <- stats::pf(fc, df1c, df2c, lower.tail = FALSE)
      } else {
        fprev <- stats::lm(stats::as.formula(paste(dv, "~", paste(unlist(blk[seq_len(j - 1L)]), collapse = " + "))), data = dd)
        cmp <- stats::anova(fprev, fj)
        df1c <- cmp[2, "Df"]; df2c <- cmp[2, "Res.Df"]; fc <- cmp[2, "F"]; pc <- cmp[2, "Pr(>F)"]
      }
      hier <- rbind(hier, data.frame(model = j, block_predictors = paste(.orig(blk[[j]]), collapse = "+"),
                                     predictors_in_model = length(cum), R = sqrt(r2_j), R_squared = r2_j,
                                     adjusted_R_squared = sj$adj.r.squared, SE_of_estimate = sj$sigma,
                                     delta_R_squared = if (j == 1L) r2_j else r2_j - hier$R_squared[j - 1L],
                                     F_change = fc, df1 = df1c, df2 = df2c, p_change = pc))
      cj <- coef(summary(fj))
      sdy2 <- stats::sd(dd[[dv]])
      beta_j <- vapply(rownames(cj)[-1], function(v) cj[v, 1] * stats::sd(dd[[v]]) / sdy2, numeric(1))
      coef_blocks[[j]] <- data.frame(model = j, predictor = .orig(rownames(cj)), B = cj[, 1], SE = cj[, 2],
                                     Beta = c(NA_real_, beta_j), t = cj[, 3], p = cj[, 4], row.names = NULL)
    }
    save_table(hier, ctx, "hierarchical_blocks", "【表2b】分层回归模型汇总（SPSS: 模型汇总+变更统计量——每块进入后的 R² 与 ΔR²/F变更）")
    save_table(do.call(rbind, coef_blocks), ctx, "hierarchical_coefficients",
               "【表2c】分层回归各块系数（SPSS: 每个块模型一张系数表；本表合并并用\"模型\"列区分）")
    guide(sprintf("\n【分层回归怎么读】共 %d 个块依次进入（对应SPSS线性回归的 块1→块%d，方法=输入）：", length(blk), length(blk)))
    for (j in seq_len(nrow(hier))) guide(sprintf("  模型%d（+%s）：R² = %s，ΔR² = %s，F变更(%s, %s) = %s，%s%s。",
      j, hier$block_predictors[j], fmt3(hier$R_squared[j]), fmt3(hier$delta_R_squared[j]),
      fmt2(hier$df1[j]), fmt2(hier$df2[j]), fmt2(hier$F_change[j]), fmt_p_inline(hier$p_change[j]),
      ifelse(hier$p_change[j] < ctx$alpha, " → 该块有显著增量贡献", " → 该块无显著增量贡献")))
  } else {
  do_incremental <- isTRUE(cfg$analysis$incremental)
  if (do_incremental && k >= 2L) {
    hier_rows <- data.frame(); r2_prev <- 0
    for (j in seq_len(k)) {
      fml <- paste(dv, "~", paste(preds[seq_len(j)], collapse = " + "))
      fj <- stats::lm(stats::as.formula(fml), data = dd)
      r2_j <- summary(fj)$r.squared
      cmp <- if (j == 1L) NULL else stats::anova(stats::lm(stats::as.formula(paste(dv, "~", paste(preds[seq_len(j - 1L)], collapse = " + "))), data = dd), fj)
      hier_rows <- rbind(hier_rows, data.frame(
        step = j, added_predictor = .orig(preds[j]),
        R_squared = r2_j, delta_R_squared = r2_j - r2_prev,
        F_change = if (j == 1L) unname(summary(fj)$fstatistic[["value"]]) else cmp[2, "F"],
        df1 = if (j == 1L) 1L else cmp[2, "Df"], df2 = if (j == 1L) unname(summary(fj)$fstatistic[["dendf"]]) else cmp[2, "Res.Df"],
        p_change = if (j == 1L) stats::pf(summary(fj)$fstatistic[["value"]], 1, summary(fj)$fstatistic[["dendf"]], lower.tail = FALSE) else cmp[2, "Pr(>F)"]))
      r2_prev <- r2_j
    }
    save_table(hier_rows, ctx, "hierarchical",
               "【表2b】层次进入的增量检验（逐个加入自变量：ΔR²与嵌套模型F变更；对应SPSS在\"块\"中依次进入或 anova(模型1, 模型2)）")
    guide("【表2b怎么读】这是增量（分块）检验：每加入一个自变量，R²提高多少（ΔR²）、该增量是否显著（F变更）。")
    guide("  与表2的区别：表2检验\"整个模型\"是否显著；表2b回答\"每个变量额外贡献了多少解释力\"。SPSS对应：线性回归对话框里分多个\"块\"依次进入后输出的\"变更统计量\"。")
  }
  }
  ci <- stats::confint(fit)
  co <- s$coefficients
  sdy <- stats::sd(dd[[dv]])
  beta <- vapply(seq_along(preds), function(i) co[i + 1L, 1] * stats::sd(dd[[preds[i]]]) / sdy, numeric(1))
  vifs <- if (k >= 2L) tryCatch(car::vif(fit), error = function(e) rep(NA_real_, k)) else rep(NA_real_, k)
  coef_tab <- data.frame(predictor = .orig(rownames(co)), B = co[, 1], SE = co[, 2], Beta = c(NA, beta),
                         t = co[, 3], p = co[, 4], ci_lower = ci[, 1], ci_upper = ci[, 2],
                         tolerance = if (k >= 2L) c(NA, 1 / vifs) else NA_real_, VIF = c(NA, vifs))
  save_table(coef_tab, ctx, "coefficients", "【表3】回归系数（SPSS: 系数表，含标准化系数Beta与共线性统计量）")
  guide("\n【四张表怎么读（按SPSS输出顺序）】")
  guide(sprintf("  ① 模型汇总：R² = %s → 模型解释因变量方差的%s%%；调整R² = %s（惩罚自变量个数，报告更稳妥）；DW = %s（接近2为佳）。",
                fmt3(s$r.squared), fmt1(s$r.squared * 100), fmt3(s$adj.r.squared), fmt2(dw)))
  guide(sprintf("  ② ANOVA：F(%d, %d) = %s，%s → 模型整体%s。", fstat[["numdf"]], fstat[["dendf"]], fmt2(fstat[["value"]]), fmt_p_inline(stats::pf(fstat[["value"]], fstat[["numdf"]], fstat[["dendf"]], lower.tail = FALSE)),
                ifelse(stats::pf(fstat[["value"]], fstat[["numdf"]], fstat[["dendf"]], lower.tail = FALSE) < ctx$alpha, "显著（至少一个自变量回归系数非零）", "不显著")))
  for (i in seq_len(nrow(coef_tab))) {
    if (i == 1L) guide(sprintf("  ③ 系数表-截距：B = %s（自变量全为0时的预测值，通常不解释）。", fmt3(coef_tab$B[1])))
    else guide(sprintf("  ③ 系数表-%s：B = %s（其他变量不变时，%s每增1分，%s平均%s%s），t = %s，%s%s。",
                       coef_tab$predictor[i], fmt3(coef_tab$B[i]), coef_tab$predictor[i], dv,
                       ifelse(coef_tab$B[i] >= 0, "增加 ", "减少 "), fmt3(abs(coef_tab$B[i])), fmt2(coef_tab$t[i]), fmt_p_inline(coef_tab$p[i]),
                       ifelse(coef_tab$p[i] < ctx$alpha, "（独特预测作用显著）", "（无显著独特贡献）")))
  }
  if (k >= 2L) guide("  ④ 共线性：VIF < 5（严格<2.5）且容差>0.2 → 多重共线性可接受；否则自变量信息重叠，系数不稳定。")
  .pm <- stats::pf(fstat[["value"]], fstat[["numdf"]], fstat[["dendf"]], lower.tail = FALSE)
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】回归模型", ifelse(.pm < ctx$alpha, "显著", "不显著"), "：F(", fstat[["numdf"]], ", ", fstat[["dendf"]], ") = ", fmt2(fstat[["value"]]), ", ", fmt_p_inline(.pm), ", adj.R² = ", fmt3(s$adj.r.squared),
        ifelse(.pm < ctx$alpha, "；其中：", "（模型整体不显著，个别系数的显著性不宜单独解读）；其中："),
        paste(sprintf("%s（B = %s, β = %s, %s）", coef_tab$predictor[-1], fmt3(coef_tab$B[-1]), fmt2(beta), fmt_p_inline(coef_tab$p[-1])), collapse = "、"), "。")
  pred_v <- stats::predict(fit); res_v <- fit$residuals
  std_res <- res_v / s$sigma
  res_stats <- data.frame(statistic = c("预测值", "残差", "标准化预测值", "标准化残差"),
                          min = c(min(pred_v), min(res_v), min(scale(pred_v)), min(std_res)),
                          max = c(max(pred_v), max(res_v), max(scale(pred_v)), max(std_res)),
                          mean = c(mean(pred_v), mean(res_v), mean(scale(pred_v)), mean(std_res)),
                          sd = c(stats::sd(pred_v), stats::sd(res_v), stats::sd(scale(pred_v)), stats::sd(std_res)))
  save_table(res_stats, ctx, "residuals_stats", "【表4】残差统计（SPSS: 残差统计量；|标准化残差|>3为异常值线索）")
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_diagnostics.png")), function() {
    graphics::par(mfrow = c(1, 2))
    graphics::plot(pred_v, res_v, xlab = "Predicted", ylab = "Residual", main = "Residuals vs Predicted", pch = 19, col = grDevices::adjustcolor("#2166AC", .6))
    graphics::abline(h = 0, lty = 2, col = "#B2182B")
    stats::qqnorm(std_res, main = "Normal Q-Q of standardized residuals"); stats::qqline(std_res, col = "#B2182B", lwd = 2)
    graphics::par(mfrow = c(1, 1))
  })
  guide("\n【调节分析去哪了？】交互/调节（X的效应是否随Z变化）已独立为\"调节效应分析\"模块（method = moderation，第20个演示），")
  guide("  含中心化交互模型、简单斜率（±1SD）与交互图；本模块专注主效应回归。中介效应见 mediation 模块。")
  guide("\n【注意】① 预测≠因果；② 分类自变量要先做0/1哑变量（同SPSS）；③ R²高但系数全不显著 → 查VIF多重共线性；④ 报告B时写清测量单位。")
  invisible(NULL)
}

# ─── 13. 卡方适合度检验 ───────────────────────────────────────────────────────
simulate_chi_square_gof <- function(cfg) {
  set.seed(cfg$simulation$seed + 13L); n <- cfg$simulation$n_per_group * 7L
  data.frame(id = sprintf("S%03d", seq_len(n)),
             preference = factor(sample(c("A_visual", "B_auditory", "C_reading", "D_kinesthetic"), n, replace = TRUE,
                                        prob = c(.40, .30, .20, .10))))
}

run_chi_square_gof <- function(data, cfg, ctx) {
  cv <- need_var(data, cfg, "category", "preference")
  x <- data[[cv]]; x <- x[!is.na(x)]
  tab <- table(x); k <- length(tab); n <- sum(tab)
  eprops <- cfg$analysis$gof_expected_probs
  if (is.null(eprops) || !length(eprops)) eprops <- rep(1 / k, k)
  eprops <- as.numeric(eprops)
  if (length(eprops) != k) stopf("analysis.gof_expected_probs 需要 %d 个概率（与类别数一致，总和为1）。", k)
  expected <- n * eprops
  ch <- suppressWarnings(stats::chisq.test(tab, p = eprops))
  out <- data.frame(category = names(tab), observed = as.integer(tab), expected = expected,
                    residual = as.integer(tab) - expected)
  save_table(out, ctx, "frequencies", "【表1】观察频数与期望频数（SPSS: 频数表；残差 = 观察 - 期望）")
  test <- data.frame(chisq = unname(ch$statistic), df = k - 1L, p = ch$p.value, N = n)
  if (k == 2L) test$binomial_exact_p <- min(1, stats::pbinom(min(tab), n, min(eprops)) * 2)
  save_table(test, ctx, "test", "【表2】卡方适合度检验（SPSS: 检验统计量；二分类时附二项精确检验）")
  guide("\n【什么时候用】单个分类变量的分布是否符合理论比例（四选项是否被均匀选择；男女比是否1:1）。")
  guide("【SPSS操作】用原始个案数据：分析 > 非参数检验 > 旧对话框 > 卡方，把 ", cv, " 放入。")
  guide("  ⚠️ 若手里只有汇总频数（每类多少人），SPSS要先用 数据 > 个案加权（按频数变量加权）再操作。")
  guide("\n【结果怎么读】")
  guide(sprintf("  · χ²(%d, N = %d) = %s，%s → 观察分布与理论比例%s。",
                k - 1L, n, fmt2(ch$statistic), fmt_p_inline(ch$p.value),
                ifelse(ch$p.value < ctx$alpha, sprintf("显著不同；偏离最大的类别：%s（残差 = %s）", out$category[which.max(abs(out$residual))], fmt2(out$residual[which.max(abs(out$residual))])), "无显著差异")))
  guide("  · 每类期望频数最好 ≥ 5（本例期望 = ", fmt2(expected[1]), "）；若某类期望 < 5，考虑合并类别。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", cv, " 的分布",
        ifelse(ch$p.value < ctx$alpha, "显著偏离理论/均匀分布", "与理论/均匀分布无显著差异"),
        "：χ²(", k - 1L, ", N = ", n, ") = ", fmt2(ch$statistic), ", ", fmt_p_inline(ch$p.value), "。",
        ifelse(ch$p.value < ctx$alpha, sprintf("实际频数最高的是「%s」（%d 次，期望 %.2f）。", names(tab)[which.max(tab)], max(tab), expected[which.max(tab)]), ""))
  guide("\n【注意】适合度只涉及一个分类变量；两个分类变量的关系用独立性检验（模块14）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_obs_vs_expected.png")), function() {
    bd <- data.frame(category = rep(names(tab), 2L),
                     prop = c(as.numeric(tab) / n, eprops),
                     type = factor(rep(c("Observed", "Expected"), each = k), levels = c("Observed", "Expected")))
    print(ggplot2::ggplot(bd, ggplot2::aes(x = category, y = prop, fill = type)) +
            ggplot2::geom_col(position = ggplot2::position_dodge(.8), width = .7) +
            ggplot2::scale_fill_manual(values = c(Observed = "#8FB8DE", Expected = "#B2182B")) +
            ggplot2::labs(title = "Goodness-of-fit: observed vs expected proportions", x = cv, y = "Proportion", fill = NULL) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("卡方适合度检验条形图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 14. 卡方独立性检验 ───────────────────────────────────────────────────────
simulate_chi_square_independence <- function(cfg) {
  set.seed(cfg$simulation$seed + 14L); n <- cfg$simulation$n_per_group * 8L
  gender <- rep(c("male", "female"), n / 2L)
  pref <- character(n)
  pref[gender == "male"] <- sample(c("academic", "corporate", "clinical"), n / 2L, replace = TRUE, prob = c(.20, .55, .25))
  pref[gender == "female"] <- sample(c("academic", "corporate", "clinical"), n / 2L, replace = TRUE, prob = c(.45, .25, .30))
  data.frame(id = sprintf("S%03d", seq_len(n)), gender = factor(gender), career_pref = factor(pref))
}

run_chi_square_independence <- function(data, cfg, ctx) {
  rv <- need_var(data, cfg, "row_var", "gender"); cv <- need_var(data, cfg, "col_var", "career_pref")
  r <- droplevels(as.factor(data[[rv]])); c <- droplevels(as.factor(data[[cv]]))
  ok <- !is.na(r) & !is.na(c); r <- r[ok]; c <- c[ok]
  tab <- table(r, c); n <- sum(tab)
  ch <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
  lr <- 2 * sum(tab[tab > 0] * log(tab[tab > 0] / ch$expected[tab > 0]))
  expected_min <- min(ch$expected)
  cells_lt5 <- sum(ch$expected < 5) / length(ch$expected) * 100
  std_res <- (tab - ch$expected) / sqrt(ch$expected)
  adj_res <- (tab - ch$expected) / sqrt(ch$expected * outer(1 - rowSums(tab) / n, 1 - colSums(tab) / n))
  dimnames(std_res) <- dimnames(tab); dimnames(adj_res) <- dimnames(tab)
  obs <- as.data.frame(as.table(tab)); names(obs) <- c(rv, cv, "observed")
  obs$expected <- as.vector(ch$expected); obs$std_residual <- as.vector(std_res); obs$adj_std_residual <- as.vector(adj_res)
  save_table(obs, ctx, "crosstab", "【表1】交叉表（SPSS: 交叉表>单元格>期望计数与标准化残差）")
  is22 <- all(dim(tab) == c(2, 2))
  test <- data.frame(test = "Pearson卡方", chisq = unname(ch$statistic), df = unname(ch$parameter), p = ch$p.value, N = n, min_expected = expected_min, pct_cells_lt5 = cells_lt5)
  test <- rbind(test, data.frame(test = "似然比卡方", chisq = lr, df = unname(ch$parameter), p = stats::pchisq(lr, ch$parameter, lower.tail = FALSE), N = n, min_expected = expected_min, pct_cells_lt5 = cells_lt5))
  if (is22) {
    cy <- suppressWarnings(stats::chisq.test(tab, correct = TRUE))
    fs <- stats::fisher.test(tab)
    test <- rbind(test, data.frame(test = c("连续性校正(Yates)", "Fisher精确检验"),
                                   chisq = c(unname(cy$statistic), NA_real_), df = c(1L, NA_real_), p = c(cy$p.value, fs$p.value), N = n, min_expected = expected_min, pct_cells_lt5 = cells_lt5))
  }
  save_table(test, ctx, "tests", "【表2】卡方检验汇总（SPSS: 卡方检验表；2×2自动附连续性校正与Fisher精确检验）")
  dfr <- min(nrow(tab), ncol(tab)) - 1L
  eff <- if (is22) sqrt(unname(ch$statistic) / n) else sqrt(unname(ch$statistic) / n / dfr)
  save_table(data.frame(effect = if (is22) "phi" else "Cramers_V", value = eff, interpretation = interpret_cramers_v(eff, dfr + 1L)),
             ctx, "effect_size", "【表3】效应量（SPSS: 交叉表>统计量>Phi和Cramer V）")
  guide("\n【什么时候用】两个分类变量之间是否关联（性别与择业偏好；干预方式与是否复发）。")
  guide("【SPSS操作】分析 > 描述统计 > 交叉表：行 = ", rv, "，列 = ", cv,
        "；统计量勾选\"卡方\"和\"Phi和Cramer V\"；单元格勾选\"期望\"\"标准化残差\"。")
  guide("\n【结果怎么读（四步）】")
  guide(sprintf("  第1步 先看期望频数：最小期望 = %s，期望<5的格子占%s%%。%s", fmt2(expected_min), fmt1(cells_lt5),
                ifelse(expected_min >= 5, "满足卡方条件（全部期望≥5）。", ifelse(cells_lt5 < 20 && expected_min >= 1, "期望<5的格子<20%且均≥1 → 卡方仍可用；否则合并类别或用Fisher精确检验。", "建议合并类别或改用Fisher精确检验。"))))
  guide(sprintf("  第2步 看Pearson卡方：χ²(%d, N = %d) = %s，%s → 两变量%s。",
                unname(ch$parameter), n, fmt2(ch$statistic), fmt_p_inline(ch$p.value), ifelse(ch$p.value < ctx$alpha, "关联（不独立）", "无显著关联（独立）")))
  guide(sprintf("  第3步 看效应量：%s = %s（%s）——卡方显著后必须报告。", if (is22) "φ" else "Cramér's V", fmt3(eff), interpret_cramers_v(eff, dfr + 1L)))
  guide("  第4步 看调整标准化残差定位来源：|残差| > 2 的格子是\"驱动显著性\"的关键格子（结合行列百分比描述谁多谁少）。")
  big <- which(abs(adj_res) > 2, arr.ind = TRUE)
  if (nrow(big)) guide("  本例 |调整残差|>2 的格子：", paste(apply(big, 1L, function(ix) sprintf("%s × %s（残差 = %s）", rownames(tab)[ix[1]], colnames(tab)[ix[2]], fmt2(adj_res[ix[1], ix[2]]))), collapse = "；"))
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", rv, " 与 ", cv, " 之间",
        ifelse(ch$p.value < ctx$alpha, "存在显著关联", "无显著关联（独立）"),
        "：χ²(", unname(ch$parameter), ", N = ", n, ") = ", fmt2(ch$statistic), ", ", fmt_p_inline(ch$p.value), ", ",
        if (is22) "φ" else "Cramér's V", " = ", fmt3(eff), "（", interpret_cramers_v(eff, dfr + 1L), "）。关联方向请对照列联表的行/列百分比。")
  guide("\n【常见错误】① 用相关分析处理两个分类变量；② 只报χ²不报效应量；③ 期望频数太小仍硬报卡方（应Fisher）；④ 把\"显著关联\"说成因果。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_grouped_bars.png")), function() {
    bd <- obs[1:3]; names(bd) <- c("rowv", "colv", "n")
    bd$prop <- bd$n / as.numeric(stats::ave(bd$n, bd$rowv, FUN = sum))
    print(ggplot2::ggplot(bd, ggplot2::aes(x = colv, y = prop, fill = rowv)) +
            ggplot2::geom_col(position = ggplot2::position_dodge(.8), width = .7) +
            ggplot2::labs(title = "Chi-square independence: column distribution within each row level",
                          x = cv, y = "Proportion within row", fill = rv) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("卡方独立性检验条形图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 15. Mann-Whitney U ───────────────────────────────────────────────────────
simulate_mann_whitney <- function(cfg) {
  set.seed(cfg$simulation$seed + 15L)
  n1 <- cfg$simulation$n_per_group - 2L; n2 <- cfg$simulation$n_per_group + 2L
  data.frame(id = sprintf("S%03d", seq_len(n1 + n2)), group = rep(c("athlete", "gamer"), c(n1, n2)),
             weekly_gaming_hours = round(c(stats::rgamma(n1, shape = 2, rate = .7), stats::rgamma(n2, shape = 2, rate = .35)), 1))
}

run_mann_whitney <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "weekly_gaming_hours"); gv <- need_var(data, cfg, "group", "group")
  y <- num_col(data, dv); g <- group_col(data, gv)
  ok <- is.finite(y) & !is.na(g); y <- y[ok]; g <- droplevels(g[ok])
  if (nlevels(g) != 2L) stopf("Mann-Whitney U 要求恰好2组，当前：%s", paste(levels(g), collapse = ", "))
  lev <- levels(g); x1 <- y[g == lev[1]]; x2 <- y[g == lev[2]]
  n1_ <- length(x1); n2_ <- length(x2); N <- n1_ + n2_
  guide("\n【什么时候用】两组独立、因变量严重偏态或为等级数据（不满足t检验正态前提）时的\"救命稻草\"。")
  guide("【SPSS操作】分析 > 非参数检验 > 旧对话框 > 2个独立样本：检验变量 = ", dv, "，分组变量 = ", gv, "，勾选 Mann-Whitney U。")
  m <- mwu_spss(x1, x2)
  ranks <- data.frame(group = lev, N = c(n1_, n2_), mean_rank = c(m$r1 / n1_, m$r2 / n2_), rank_sum = c(m$r1, m$r2),
                      median = c(stats::median(x1), stats::median(x2)))
  save_table(ranks, ctx, "ranks", "【表1】秩统计（SPSS: 秩表——报告时用中位数+四分位距而非均值）")
  test <- data.frame(Mann_Whitney_U = m$U, Wilcoxon_W = if (m$U == m$U1) m$r1 else m$r2, Z = m$Z, p_asymptotic_2tailed = m$p,
                     effect_size_r = abs(m$Z) / sqrt(N))
  save_table(test, ctx, "test", "【表2】检验统计（SPSS: 检验统计表；Z为含结点校正的渐近正态，双尾）")
  guide("\n【结果怎么读】")
  guide(sprintf("  · U = %s，Z = %s，%s → 两组分布%s。效应量 r = |Z|/√N = %s（.10小/.30中/.50大）。",
                fmt2(m$U), fmt2(m$Z), fmt_p_inline(m$p), ifelse(m$p < ctx$alpha, "位置显著不同（中位数一大一小）", "无显著差异"), fmt2(abs(m$Z) / sqrt(N))))
  guide(sprintf("  · 描述统计请报中位数：%s组 Mdn = %s，%s组 Mdn = %s。", lev[1], fmt1(stats::median(x1)), lev[2], fmt1(stats::median(x2))))
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", dv, " 在两组间",
        ifelse(m$p < ctx$alpha, "差异显著", "无显著差异"),
        "：U = ", fmt2(m$U), ", Z = ", fmt2(m$Z), ", ", fmt_p_inline(m$p), ", r = ", fmt2(abs(m$Z) / sqrt(N)), "。",
        "方向请对照两组的平均秩（rank）或中位数自行表述；本表 Z 恒取负值（U = min(U1,U2) 口径），不含方向信息。")
  ttc <- suppressWarnings(stats::t.test(x1, x2))
  guide("\n【如果误用t会怎样】本例若强行用独立样本t：t = ", fmt2(ttc$statistic), "，", fmt_p_inline(ttc$p.value),
        "——结论方向一致；但偏态+小样本时t的p值不可靠，这正是选U的理由（教学对照，正式报告二选一即可）。")
  guide("\n【注意】① U检验比较的是分布位置（中位数），不是均值；② 同一批人测两次 → Wilcoxon符号秩（模块16）；③ ≥3组 → Kruskal-Wallis（模块17）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_boxplot.png")), function() {
    print(ggplot2::ggplot(data.frame(y = y, g = g), ggplot2::aes(x = g, y = y)) +
            ggplot2::geom_boxplot(fill = "#8FB8DE", color = "#2166AC") +
            ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5, color = "#B2182B") +
            ggplot2::labs(title = "Mann-Whitney U (nonparametric): group distributions (diamond = mean)", x = gv, y = dv) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("Mann-Whitney U箱线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 16. Wilcoxon 符号秩检验 ──────────────────────────────────────────────────
simulate_wilcoxon_signed <- function(cfg) {
  set.seed(cfg$simulation$seed + 16L); n <- cfg$simulation$n_per_group - 4L
  pre <- pmax(1, pmin(7, round(3 + 1.3 * stats::rnorm(n))))
  improve <- sample(c(0, 1, 1, 2), n, replace = TRUE)
  post <- pmax(1, pmin(7, pre - improve + sample(c(-1, 0, 0, 1), n, replace = TRUE)))
  data.frame(id = sprintf("S%03d", seq_len(n)), pre_satisfaction = pre, post_satisfaction = post)
}

run_wilcoxon_signed <- function(data, cfg, ctx) {
  v1 <- need_var(data, cfg, "dv1", "pre_satisfaction"); v2 <- need_var(data, cfg, "dv2", "post_satisfaction")
  x <- num_col(data, v1); z <- num_col(data, v2)
  ok <- is.finite(x) & is.finite(z); x <- x[ok]; z <- z[ok]
  # 与配对t一致：默认差值 = 后−前（dv2 − dv1），可用 analysis.paired_direction: dv1_minus_dv2 切换。
  d <- if (identical(cfg$analysis$paired_direction, "dv1_minus_dv2")) x - z else z - x
  dlab <- if (identical(cfg$analysis$paired_direction, "dv1_minus_dv2")) "前−后" else "后−前"
  guide("\n【什么时候用】同一批人前后两次测量，差值严重偏态或为等级数据（配对t的非参数替代）。")
  guide("【SPSS操作】分析 > 非参数检验 > 旧对话框 > 2个相关样本：成对变量 = (", v1, ", ", v2, ")，勾选 Wilcoxon。")
  w <- wsr_spss(d)
  save_table(data.frame(difference_direction = dlab, N_total = length(d), N_nonzero_pairs = w$n, W_positive = w$Wplus, W_negative = w$Wminus,
                        Wilcoxon_W = w$W, Z = w$Z, p_asymptotic_2tailed = w$p, effect_size_r = abs(w$Z) / sqrt(w$n)),
             ctx, "test", sprintf("【检验表】（SPSS: 检验统计表；差值 = %s，W = 较小的秩和，Z为渐近正态，双尾）", dlab))
  guide("\n【结果怎么读】")
  guide(sprintf("  · 有效差值对子 n = %d（剔除0差值后），W = %s，Z = %s，%s → 前后测%s。",
                w$n, fmt2(w$W), fmt2(w$Z), fmt_p_inline(w$p), ifelse(w$p < ctx$alpha, "显著不同", "无显著差异")))
  pos <- sum(d > 0); neg <- sum(d < 0)
  guide(sprintf("  · 方向：%d对后>前、%d对后<前（正秩和 = %s，负秩和 = %s，差值=%s）→ 多数被试%s。",
                pos, neg, fmt2(w$Wplus), fmt2(w$Wminus), dlab, ifelse(w$Wplus > w$Wminus, "后测更高", "前测更高")))
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", v1, " 与 ", v2, " 两次测量", ifelse(w$p < ctx$alpha, "差异显著", "无显著差异"),
        "：Z = ", fmt2(w$Z), ", ", fmt_p_inline(w$p), ", r = ", fmt2(abs(w$Z) / sqrt(w$n)), "。方向请对照正/负秩的个数与中位数自行表述（Z 取 min(W+,W−) 口径，不含方向）。")
  guide("\n【注意】① 报告中位数而非均值；② 差值若近似正态 → 直接用配对t（信息利用更充分）；③ ≥3个相关条件 → Friedman（模块19）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_pre_post_lines.png")), function() {
    np <- length(x)
    pd <- data.frame(subject = rep(seq_len(np), 2L),
                     cond = factor(rep(c(v1, v2), each = np), levels = c(v1, v2)),
                     y = c(x, z))
    md <- data.frame(cond = factor(c(v1, v2), levels = c(v1, v2)), m = c(mean(x), mean(z)))
    print(ggplot2::ggplot(pd, ggplot2::aes(x = cond, y = y)) +
            ggplot2::geom_line(ggplot2::aes(group = subject), color = grDevices::adjustcolor("#2166AC", .3), linewidth = .4) +
            ggplot2::geom_point(color = grDevices::adjustcolor("#2166AC", .4), size = .8) +
            ggplot2::geom_line(data = md, ggplot2::aes(x = cond, y = m, group = 1), inherit.aes = FALSE,
                               color = "#B2182B", linewidth = 1.2) +
            ggplot2::geom_point(data = md, ggplot2::aes(x = cond, y = m), inherit.aes = FALSE,
                                color = "#B2182B", size = 3) +
            ggplot2::labs(title = "Wilcoxon signed-rank (nonparametric): pre-post trajectories (bold red = means)",
                          x = NULL, y = "Score") +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("Wilcoxon符号秩检验前后测连线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

wsr_spss <- function(d) {
  d <- d[!is.na(d) & d != 0]; n <- length(d)
  rk <- rank(abs(d)); Wp <- sum(rk[d > 0]); Wm <- sum(rk[d < 0]); W <- min(Wp, Wm)
  ties <- table(abs(d))
  mu <- n * (n + 1) / 4; s2 <- n * (n + 1) * (2 * n + 1) / 24 - sum(ties^3 - ties) / 48
  Z <- (W - mu) / sqrt(s2)
  list(W = W, Wplus = Wp, Wminus = Wm, n = n, Z = Z, p = 2 * stats::pnorm(-abs(Z)))
}

# ─── 17. Kruskal-Wallis H ─────────────────────────────────────────────────────
simulate_kruskal_wallis <- function(cfg) {
  set.seed(cfg$simulation$seed + 17L); n <- cfg$simulation$n_per_group
  data.frame(id = sprintf("S%03d", seq_len(3 * n)),
             program = factor(rep(c("psychology", "engineering", "art"), each = n)),
             sleep_quality_score = round(c(6 + stats::rgamma(n, 2, .8), 9 + stats::rgamma(n, 2, .8), 7 + stats::rgamma(n, 2, .8)), 1))
}

run_kruskal_wallis <- function(data, cfg, ctx) {
  dv <- need_var(data, cfg, "dv", "sleep_quality_score"); gv <- need_var(data, cfg, "group", "program")
  y <- num_col(data, dv); g <- group_col(data, gv)
  ok <- is.finite(y) & !is.na(g); y <- y[ok]; g <- droplevels(g[ok])
  if (nlevels(g) < 3L) stopf("Kruskal-Wallis 需要≥3组，当前：%s", paste(levels(g), collapse = ", "))
  k <- nlevels(g); N <- length(y)
  guide("\n【什么时候用】≥3组独立、因变量偏态或等级（单因素方差分析的非参数替代）。")
  guide("【SPSS操作】分析 > 非参数检验 > 旧对话框 > K个独立样本：检验变量 = ", dv, "，因子 = ", gv, "，勾选 Kruskal-Wallis H。")
  rr <- rank(y)
  ranks <- do.call(rbind, lapply(levels(g), function(l) {
    x <- y[g == l]; data.frame(group = l, N = length(x), mean_rank = mean(rr[g == l]), median = stats::median(x))
  }))
  save_table(ranks, ctx, "ranks", "【表1】秩统计（SPSS: 秩表）")
  kw <- stats::kruskal.test(y ~ g)
  eps2 <- (unname(kw$statistic) - k + 1) / (N - k)
  save_table(data.frame(Kruskal_Wallis_H = unname(kw$statistic), df = unname(kw$parameter), p = kw$p.value,
                        epsilon_squared = eps2, N = N),
             ctx, "test", "【表2】检验统计（SPSS: 检验统计表；H即卡方值，含结点校正）")
  guide("\n【结果怎么读】")
  guide(sprintf("  · H(%d) = %s，%s → %s；效应量 ε² = %s（.01小/.06中/.14大）。",
                unname(kw$parameter), fmt2(kw$statistic), fmt_p_inline(kw$p.value),
                ifelse(kw$p.value < ctx$alpha, "至少两组分布位置不同（不指明哪两组）", "各组无显著差异"), fmt3(eps2)))
  pairs <- t(combn(levels(g), 2L))
  pw <- do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) {
    a <- y[g == pairs[i, 1]]; b <- y[g == pairs[i, 2]]
    mm <- mwu_spss(a, b)
    data.frame(pair = paste(pairs[i, 1], "vs", pairs[i, 2]), U = mm$U, Z = mm$Z, p = mm$p, p_bonferroni = min(1, mm$p * nrow(pairs)))
  }))
  save_table(pw, ctx, "posthoc_pairwise", "【表3】事后两两比较（Bonferroni校正）")
  guide("\n【SPSS27怎么找到事后】旧对话框（K个独立样本）没有成对比较；请用：分析 > 非参数检验 > 独立样本（新版界面）> 字段里放因变量和因子 > 设置 > 成对比较，默认即为 Bonferroni —— 输出\"成对比较\"表与本表3对应。")
  sigp <- pw[pw$p_bonferroni < ctx$alpha, ]
  guide("\n【事后结论】", if (nrow(sigp)) paste(sprintf("%s：p_adj = %s", sigp$pair, fmt_p_inline(sigp$p_bonferroni)), collapse = "；") else "经Bonferroni校正后无显著配对。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", dv, " 在各组间",
        ifelse(kw$p.value < ctx$alpha, "差异显著", "无显著差异"),
        "：H(", unname(kw$parameter), ") = ", fmt2(kw$statistic), ", ", fmt_p_inline(kw$p.value), ", ε² = ", fmt3(eps2), "。")
  guide("  事后比较（Bonferroni）：",
        if (nrow(sigp)) paste0("有 ", nrow(sigp), " 对差异显著（", paste(sigp$pair, collapse = "、"), "）；谁高谁低请对照各组平均秩/中位数表述。") else "各配对均不显著。")
  guide("\n【注意】① 描述统计用中位数；② H不显著时不要做事后；③ 重复测量（相关样本）≥3条件 → Friedman（模块18）。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_boxplot.png")), function() {
    print(ggplot2::ggplot(data.frame(y = y, g = g), ggplot2::aes(x = g, y = y)) +
            ggplot2::geom_boxplot(fill = "#8FB8DE", color = "#2166AC") +
            ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3.5, color = "#B2182B") +
            ggplot2::labs(title = "Kruskal-Wallis H (nonparametric): group distributions (diamond = mean)", x = gv, y = dv) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("Kruskal-Wallis箱线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

mwu_spss <- function(x1, x2) {
  n1_ <- length(x1); n2_ <- length(x2); N <- n1_ + n2_
  rk <- rank(c(x1, x2)); r1 <- sum(rk[seq_len(n1_)])
  U1 <- r1 - n1_ * (n1_ + 1) / 2; U2 <- n1_ * n2_ - U1; U <- min(U1, U2)
  ties <- table(c(x1, x2)); tiecor <- 1 - sum(ties^3 - ties) / (N^3 - N)
  muU <- n1_ * n2_ / 2; sdU <- sqrt(n1_ * n2_ * (N + 1) / 12 * tiecor)
  Z <- (U - muU) / sdU
  list(U = U, U1 = U1, U2 = U2, r1 = r1, r2 = sum(rk) - r1, Z = Z, p = 2 * stats::pnorm(-abs(Z)))
}

# ─── 18. Friedman 检验 ────────────────────────────────────────────────────────
simulate_friedman <- function(cfg) {
  set.seed(cfg$simulation$seed + 18L); n <- max(15L, cfg$simulation$n_per_group - 8L)
  base <- stats::rnorm(n)
  mk <- function(shift) pmax(1, pmin(7, round(4 + 0.8 * base + shift + stats::rnorm(n, 0, .9))))
  data.frame(id = sprintf("S%03d", seq_len(n)), video_A = mk(0), video_B = mk(0.8), video_C = mk(-0.3))
}

run_friedman <- function(data, cfg, ctx) {
  wcols <- get_var_vector(cfg, "within")
  if (!length(wcols) || !nzchar(wcols[1])) wcols <- names(data)[vapply(data, is.numeric, logical(1))][1:3]
  miss <- setdiff(wcols, names(data)); if (length(miss)) stopf("variables.within 中的列不存在：%s", paste(miss, collapse = ", "))
  wide <- as.data.frame(lapply(data[wcols], function(z) suppressWarnings(as.numeric(z))))
  wide <- wide[stats::complete.cases(wide), , drop = FALSE]
  n <- nrow(wide); k <- ncol(wide)
  guide("\n【什么时候用】同一批被试在≥3个相关条件/时间点上的等级或偏态数据（重复测量ANOVA的非参数替代）。")
  guide("【SPSS操作】分析 > 非参数检验 > 旧对话框 > K个相关样本：把 ", paste(wcols, collapse = ", "), " 放入检验变量，勾选 Friedman。")
  fr <- stats::friedman.test(as.matrix(wide))
  mean_ranks <- friedman_mean_ranks_spss(wide)
  ranks <- data.frame(
    condition = wcols,
    mean_rank = mean_ranks,
    median = vapply(wide, stats::median, numeric(1))
  )
  save_table(ranks, ctx, "ranks", "【表1】秩统计（SPSS: 秩表）")
  W <- unname(fr$statistic) / (n * (k - 1))
  save_table(data.frame(Friedman_chisq = unname(fr$statistic), df = unname(fr$parameter), p = fr$p.value,
                        N = n, kendalls_W = W),
             ctx, "test", "【表2】检验统计（SPSS: 检验统计表；Kendall's W 为一致性效应量）")
  guide("\n【结果怎么读】")
  guide(sprintf("  · χ²_Friedman(%d) = %s，%s → %s；Kendall's W = %s（.1小/.3中/.5大，表示条件间一致性）。",
                unname(fr$parameter), fmt2(fr$statistic), fmt_p_inline(fr$p.value),
                ifelse(fr$p.value < ctx$alpha, "至少两个条件的位置不同", "各条件无显著差异"), fmt2(W)))
  m <- k * (k - 1L) / 2L
  pw <- data.frame()
  for (i in seq_len(k - 1L)) for (j in (i + 1L):k) {
    w2 <- wsr_spss(wide[, i] - wide[, j])
    pw <- rbind(pw, data.frame(pair = paste(wcols[i], "vs", wcols[j]), W = w2$W, Z = w2$Z,
                               p = w2$p, p_bonferroni = min(1, w2$p * m)))
  }
  save_table(pw, ctx, "posthoc_pairwise", "【表3】事后两两比较（Wilcoxon符号秩 + Bonferroni）")
  guide("\n【SPSS27怎么找到事后】旧对话框（K个相关样本）没有成对比较；请用：分析 > 非参数检验 > 相关样本（新版界面）> 字段里放各条件 > 设置 > 成对比较，默认 Bonferroni —— 输出\"成对比较\"表与本表3对应。")
  sigp <- pw[pw$p_bonferroni < ctx$alpha, ]
  guide("\n【事后结论】", if (nrow(sigp)) paste(sprintf("%s：p_adj = %s", sigp$pair, fmt_p_inline(sigp$p_bonferroni)), collapse = "；") else "经Bonferroni校正后无显著配对。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】各次测量的评分",
        ifelse(fr$p.value < ctx$alpha, "差异显著", "无显著差异"),
        "：χ²(", unname(fr$parameter), ") = ", fmt2(fr$statistic), ", ", fmt_p_inline(fr$p.value), ", Kendall's W = ", fmt2(W), "。",
        "哪一次最高/最低请对照各次测量的平均秩（表1）自行表述。")
  guide("\n【注意】① 每个被试在各条件下都有一个值；② 数据近似正态且球形可接受 → 用重复测量ANOVA更灵敏。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_condition_boxplot.png")), function() {
    pd <- data.frame(subject = rep(seq_len(n), k),
                     cond = factor(rep(wcols, each = n), levels = wcols),
                     y = as.vector(as.matrix(wide)))
    print(ggplot2::ggplot(pd, ggplot2::aes(x = cond, y = y)) +
            ggplot2::geom_line(ggplot2::aes(group = subject), color = grDevices::adjustcolor("#2166AC", .25), linewidth = .4) +
            ggplot2::geom_boxplot(fill = "#8FB8DE", color = "#2166AC", alpha = .5) +
            ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "#B2182B") +
            ggplot2::labs(title = "Friedman (nonparametric): per-condition distributions with subject trajectories",
                          x = NULL, y = "Score") +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("Friedman各条件箱线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 19. 统计功效与样本量 ─────────────────────────────────────────────────────
run_power <- function(data, cfg, ctx) {
  guide("\n【什么时候用】开题/设计阶段回答两个问题：① 需要多大样本才能检测到预期效应（事前分析，推荐）；② 已有样本能检测到多大效应（敏感性分析）。")
  guide("【SPSS对照】SPSS 28+ 自带样本量计算（\"功效分析\"），心理学更常用 G*Power；本模块用R的 pwr 包，结果与G*Power一致。")
  a <- cfg$analysis$alpha
  grid <- expand.grid(d = c(0.2, 0.5, 0.8), power = c(0.80, 0.90))
  t_rows <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
    p <- pwr::pwr.t.test(d = grid$d[i], sig.level = a, power = grid$power[i], type = "two.sample")
    data.frame(design = "独立样本t（双尾）", effect = paste("d =", grid$d[i]), alpha = a, power = grid$power[i],
               N_total = ceiling(p$n) * 2L)
  }))
  pa <- pwr::pwr.anova.test(k = 3, f = 0.25, sig.level = a, power = 0.80)
  pr <- pwr::pwr.r.test(r = 0.3, sig.level = a, power = 0.80)
  pf2 <- pwr::pwr.f2.test(u = 3, v = NULL, f2 = 0.15, sig.level = a, power = 0.80)
  extra <- data.frame(
    design = c("单因素ANOVA（k=3）", "Pearson相关（双尾）", "多元回归（3个预测变量）"),
    effect = c("f = 0.25（中等）", "r = 0.30（中等）", "f² = 0.15（中等）"),
    alpha = a, power = 0.80,
    N_total = c(ceiling(pa$n) * 3L, ceiling(pr$n), ceiling(pf2$u + pf2$v + 1L))
  )
  tab <- rbind(t_rows, extra)
  save_table(tab, ctx, "sample_size_table", sprintf("【表1】常用设计所需样本量（α = %s，双尾；对应G*Power先验分析）", fmt2(a)))
  guide("\n【怎么读】")
  guide("  · 事前分析（推荐）：先根据文献/预实验确定效应量（d/f/r），再查所需N；Cohen标准：小.2/中.5/大.8（对应f: .10/.25/.40）。")
  .small_row <- tab[tab$design == "独立样本t（双尾）" & tab$effect == "d = 0.2" & tab$power == 0.8, ]
  .small_txt <- if (nrow(.small_row)) sprintf("每组约 %d 人（总约 %d 人，即表1独立样本t行）",
                                              .small_row$N_total[1] / 2L, .small_row$N_total[1]) else "（见表1独立样本t行）"
  guide("  · 小效应需要的样本量惊人（当前设置下 d = 0.2、power = .8 → ", .small_txt,
        "）；\"没显著\"很多时候只是\"样本不够\"（power不足），不等于\"无效应\"。")
  guide("  · power = 1 - β，β是Ⅱ类错误；.80是约定俗成的最低标准。")
  guide("  · 事后只宜报告\"敏感性分析\"（本样本能检测到的最小效应），不要报告observed power。")
  nper <- ceiling(pwr::pwr.t.test(d = .5, power = .8, sig.level = a, type = "two.sample")$n)
  guide("\n【结果写法】事前样本量分析：预期中等效应 d = 0.50，α = ", fmt2(a), "（双尾），power = .80，需每组 ", nper, " 人（pwr / G*Power 3.1）。")
  guide("\n【注意】① 效应量别拍脑袋：查meta分析或做预实验；② 组间样本不等会降低power；③ 卡方设计用 pwr.chisq.test(w, df, power) 计算。")
  tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_power_curves.png")), function() {
    n_grid <- seq(5, 500, by = 5)
    pd <- do.call(rbind, lapply(c(0.2, 0.5, 0.8), function(de) {
      pw <- vapply(n_grid, function(nn) pwr::pwr.t.test(n = nn, d = de, sig.level = a, type = "two.sample")$power, numeric(1))
      data.frame(n_per_group = n_grid, d = sprintf("d = %.1f", de), power = pw)
    }))
    pd$d <- factor(pd$d, levels = c("d = 0.2", "d = 0.5", "d = 0.8"))
    print(ggplot2::ggplot(pd, ggplot2::aes(x = n_per_group, y = power, color = d)) +
            ggplot2::geom_hline(yintercept = 0.80, linetype = "dashed", color = "#B2182B") +
            ggplot2::geom_line(linewidth = 1) +
            ggplot2::scale_color_manual(values = c("d = 0.2" = "#B2182B", "d = 0.5" = "#2166AC", "d = 0.8" = "#67A9CF")) +
            ggplot2::annotate("text", x = 500, y = 0.80, hjust = 1, vjust = -.5, color = "#B2182B", label = "power = .80") +
            ggplot2::labs(title = sprintf("Power curves: independent-samples t (two-sided, alpha = %s)", fmt2(a)),
                          x = "N per group", y = "Power", color = NULL) +
            ggplot2::theme_minimal())
  }), error = function(e) warning(sprintf("功效曲线图绘制失败，已跳过：%s", conditionMessage(e))))
  invisible(NULL)
}

# ─── 19. 中介效应分析（PROCESS Model 4） ───────────────────────────────────────
simulate_mediation <- function(cfg) {
  set.seed(cfg$simulation$seed + 19L); n <- cfg$simulation$n_per_group * 6L
  stress <- pmax(1, pmin(10, round(4 + 2 * stats::rnorm(n))))
  Xc <- stress - mean(stress)
  rumination <- pmax(1, pmin(10, round(2 + 0.55 * Xc + 1.3 * stats::rnorm(n), 1)))
  Mc <- rumination - mean(rumination)
  depression <- pmax(0, pmin(20, round(2.5 + 0.15 * Xc + 0.45 * Mc + 1.1 * stats::rnorm(n), 1)))
  data.frame(id = sprintf("S%03d", seq_len(n)), stress = stress, rumination = rumination, depression = depression)
}

run_mediation <- function(data, cfg, ctx) {
  xv <- need_var(data, cfg, "x", "stress"); mv <- need_var(data, cfg, "m", "rumination"); yv <- need_var(data, cfg, "y", "depression")
  X <- num_col(data, xv); M <- num_col(data, mv); Y <- num_col(data, yv)
  ok <- is.finite(X) & is.finite(M) & is.finite(Y)
  dd <- data.frame(X = X[ok], M = M[ok], Y = Y[ok]); n <- nrow(dd)
  # 可识别性预检：X 与 M 完全共线（两个角色选了同一列/中介是自变量的线性复制）时，M~X 完美拟合、
  # Y~X+M 秩亏，summary() 会整行剔除共线系数，cb["M", ] 便会下标越界。这里提前给出可操作的中文报错。
  if (n < 3L) stopf("中介分析至少需要 3 个完整观测（当前有效 n = %d，缺失剔除后所剩过少）。请检查数据或改用内置模拟演示。", n)
  uniq_n <- vapply(dd, function(z) length(unique(z)), integer(1))
  if (any(uniq_n < 2L)) stopf("中介分析的变量 %s 只有 1 种取值（常量），无法估计回归路径。请检查变量设置（X=%s，M=%s，Y=%s）。",
                              paste(c(xv, mv, yv)[uniq_n < 2L], collapse = "、"), xv, mv, yv)
  r_xm <- suppressWarnings(stats::cor(dd$X, dd$M))
  if (is.finite(r_xm) && abs(r_xm) > 0.9999)
    stopf("自变量 %s 与中介变量 %s 几乎完全共线（r = %.6f）。常见原因：两个角色选择了同一列，或中介变量只是自变量的线性复制（如总分=题目之和）。此时 a、b 两条路径在数学上无法区分，中介分析不适用——请更换中介变量，或改用回归/相关分析。", xv, mv, r_xm)
  guide("\n【什么时候用】回答\"X 如何通过 M 影响 Y\"（如何起作用）：例如 感知压力(X) → 反刍思维(M) → 抑郁(Y)。")
  guide("  区分：中介问\"怎么起作用\"（本模块）；调节问\"什么时候/对谁更强\"（模块20，独立的moderation方法）。")
  guide("【SPSS操作】安装 Hayes PROCESS 宏后：分析 > 回归 > PROCESS v4：Y = ", yv, "，X = ", xv, "，M = ", mv,
        "，Model number = 4，勾选 Bootstrap 5000（置信区间 Percentile）；无宏时可用分步回归对照（表1的三个模型）。")
  f_total <- stats::lm(Y ~ X, dd); c_r <- summary(f_total)$coefficients["X", ]
  f_a <- stats::lm(M ~ X, dd); a_r <- summary(f_a)$coefficients["X", ]
  f_b <- stats::lm(Y ~ X + M, dd); cb <- summary(f_b)$coefficients
  if (!"M" %in% rownames(cb) || !"X" %in% rownames(cb))
    stopf("中介模型（Y~X+M）出现完全共线，路径 b / c' 的系数行被剔除、无法估计。请检查 %s、%s、%s 之间是否存在重复列或线性复制关系。", yv, xv, mv)
  b_r <- cb["M", ]; cp_r <- cb["X", ]
  a <- a_r[["Estimate"]]; b <- b_r[["Estimate"]]; ab <- a * b
  paths <- data.frame(
    path = c(paste0("总效应 c (", yv, "~", xv, ")"), paste0("a (", mv, "~", xv, ")"),
             paste0("b (", yv, "~", mv, " 控制", xv, ")"), paste0("直接效应 c' (", yv, "~", xv, " 控制", mv, ")"),
             "间接效应 ab = a×b"),
    model = c("模型0", "模型1", "模型2", "模型2", "a×b"),
    B = c(c_r[["Estimate"]], a, b, cp_r[["Estimate"]], ab),
    SE = c(c_r[["Std. Error"]], a_r[["Std. Error"]], b_r[["Std. Error"]], cp_r[["Std. Error"]], NA),
    t = c(c_r[["t value"]], a_r[["t value"]], b_r[["t value"]], cp_r[["t value"]], NA),
    p = c(c_r[["Pr(>|t|)"]], a_r[["Pr(>|t|)"]], b_r[["Pr(>|t|)"]], cp_r[["Pr(>|t|)"]], NA),
    R_squared = c(summary(f_total)$r.squared, summary(f_a)$r.squared, NA, summary(f_b)$r.squared, NA))
  save_table(paths, ctx, "paths", "【表1】中介路径系数（PROCESS Model 4 输出的三个回归模型；模型2 = Y~X+M）")
  # Sobel 检验（补充参考；偏保守，主推Bootstrap CI）
  sobel_z <- ab / sqrt(b^2 * a_r[["Std. Error"]]^2 + a^2 * b_r[["Std. Error"]]^2)
  sobel_p <- 2 * stats::pnorm(-abs(sobel_z))
  # Bootstrap 5000 次百分位CI：闭式OLS斜率，速度远快于重复lm
  set.seed(cfg$simulation$seed + 1900L)
  B <- 5000L
  sXX <- var(dd$X); a0 <- stats::cov(dd$X, dd$M) / sXX
  ab_boot <- numeric(B)
  for (i in seq_len(B)) {
    j <- sample.int(n, n, replace = TRUE)
    Xj <- dd$X[j]; Mj <- dd$M[j]; Yj <- dd$Y[j]
    vX <- stats::var(Xj); cXY <- stats::cov(Xj, Yj); cXM <- stats::cov(Xj, Mj)
    a_j <- cXM / vX
    b_j <- (stats::cov(Mj, Yj) * vX - cXY * cXM) / (stats::var(Mj) * vX - cXM^2)
    ab_boot[i] <- a_j * b_j
  }
  ci <- stats::quantile(ab_boot, c(.025, .975), names = FALSE)
  sig_med <- ci[1] > 0 | ci[2] < 0
  indirect <- data.frame(effect = c("间接效应 ab", "Sobel检验(参考)", "Bootstrap 5000 95%CI下限", "Bootstrap 5000 95%CI上限", "中介占总效应比例 ab/c"),
                         value = c(ab, sobel_z, ci[1], ci[2], ab / c_r[["Estimate"]]),
                         note = c(sprintf("a×b"), sprintf("Z = %s，%s", fmt2(sobel_z), fmt_p_inline(sobel_p)),
                                  ifelse(sig_med, "CI不含0 → 中介显著", "CI含0 → 中介不显著"),
                                  "", ifelse(c_r[["Estimate"]] != 0, sprintf("%.1f%%", 100 * ab / c_r[["Estimate"]]), "")))
  save_table(indirect, ctx, "indirect", "【表2】间接效应与Bootstrap检验（对应PROCESS输出的 Indirect effect(s) 与 BootLLCI/BootULCI）")
  guide("\n【结果怎么读（三步）】")
  guide(sprintf("  第1步 看间接效应的Bootstrap 95%%CI：ab = %s，CI[%s, %s] → %s（现行标准：CI不含0即中介成立，比Sobel更稳健）。",
                fmt3(ab), fmt3(ci[1]), fmt3(ci[2]), ifelse(sig_med, "中介效应显著", "中介效应不显著")))
  guide(sprintf("  第2步 判断完全/部分中介：直接效应 c' = %s（%s）→ %s。",
                fmt3(cp_r[["Estimate"]]), fmt_p_inline(cp_r[["Pr(>|t|)"]]),
                ifelse(sig_med && cp_r[["Pr(>|t|)"]] < ctx$alpha, "部分中介（X对Y仍有直接作用）",
                       ifelse(sig_med, "完全中介（控制M后X不再直接影响Y；谨慎表述为\"接近完全中介\"）", "无中介证据"))))
  guide(sprintf("  第3步 报告路径与占比：a = %s（%s），b = %s（%s），中介占总效应 %s%%。",
                fmt3(a), fmt_p_inline(a_r[["Pr(>|t|)"]]), fmt3(b), fmt_p_inline(b_r[["Pr(>|t|)"]]), fmt1(100 * ab / c_r[["Estimate"]])))
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】", xv, " 通过 ", mv, " 影响 ", yv, " 的间接效应 ab = ", fmt3(ab), "，Boot 95%CI [", fmt3(ci[1]), ", ", fmt3(ci[2]), "]",
        ifelse(sig_med, "（不含0 → 间接效应显著）", "（含0 → 未见显著间接效应）"),
        "；直接效应 c' = ", fmt3(cp_r[["Estimate"]]), "，", fmt_p_inline(cp_r[["Pr(>|t|)"]]), "，占总效应 ", fmt1(100 * ab / c_r[["Estimate"]]), "%。")
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_path_diagram.png")), function() {
    graphics::par(mar = c(1, 1, 3, 1)); graphics::plot.new(); graphics::plot.window(c(0, 10), c(0, 10))
    box_txt <- function(cx, cy, lab) { graphics::rect(cx - 1.25, cy - .75, cx + 1.25, cy + .75); graphics::text(cx, cy, lab, cex = .9) }
    box_txt(2, 1.6, xv); box_txt(5, 8.4, mv); box_txt(8, 1.6, yv)
    graphics::arrows(2.6, 2.35, 4.4, 7.6, length = .12); graphics::text(2.9, 5.2, sprintf("a = %s%s", fmt3(a), p_star(a_r[["Pr(>|t|)"]])), pos = 4, cex = .85)
    graphics::arrows(5.6, 7.6, 7.4, 2.35, length = .12); graphics::text(7.15, 5.2, sprintf("b = %s%s", fmt3(b), p_star(b_r[["Pr(>|t|)"]])), pos = 2, cex = .85)
    graphics::arrows(3.3, 1.6, 6.7, 1.6, length = .12); graphics::text(5, .9, sprintf("c' = %s%s", fmt3(cp_r[["Estimate"]]), p_star(cp_r[["Pr(>|t|)"]])), cex = .85)
    graphics::title("Mediation model (PROCESS Model 4)")
  })
  guide("\n【注意】① 横断面数据的\"中介\"是统计中介，因果链需要理论/设计支撑；② 完全/部分中介的二分表述近年受批评，建议同时报告ab、CI与占比；③ Sobel假设正态偏保守，优先Bootstrap；④ 建议N ≥ 200（本演示N = ", n, "）。")
  invisible(NULL)
}

# ─── 20. 调节效应分析（PROCESS Model 1） ───────────────────────────────────────
simulate_moderation <- function(cfg) simulate_regression(cfg)

run_moderation <- function(data, cfg, ctx) {
  ix <- need_var(data, cfg, "interaction_x", "motivation")
  iz <- need_var(data, cfg, "interaction_z", "learning_resources")
  dv <- need_var(data, cfg, "interaction_dv", "engagement_score")
  if (!dv %in% names(data)) dv <- need_var(data, cfg, "dv", "engagement_score")
  idd <- data[c(dv, ix, iz)]; idd <- idd[stats::complete.cases(idd), , drop = FALSE]
  n <- nrow(idd)
  guide("\n【什么时候用】回答\"X的效应何时/对谁更强\"（调节）：例如 学习资源(Z) 是否调节 动机(X) 对 投入(Y) 的影响。")
  guide("  区分：调节问\"什么时候更强\"（本模块，乘积项显著）；中介问\"如何起作用\"（模块19）。")
  guide("【SPSS操作】安装 PROCESS 宏后：分析 > 回归 > PROCESS v4：Y = ", dv, "，X = ", ix, "，Z/moderator = ", iz,
        "，Model number = 1，勾选 Mean center、Simple slopes(J-N可视化可选)；无宏时按表1手动构造中心化乘积项。")
  # 均值中心化（SPSS PROCESS 的 "Mean center" 口径）：Xc = X - mean(X)，Zc = Z - mean(Z)。
  # 注意：必须显式做减法。scale(x, scale=FALSE) 的默认 center=TRUE 才能中心化；
  # 早期为防止变量遮蔽曾误写成 center=FALSE，等于完全不中心化，导致截距与主效应全部失真。
  Xc <- idd[[ix]] - mean(idd[[ix]], na.rm = TRUE)
  Zc <- idd[[iz]] - mean(idd[[iz]], na.rm = TRUE)
  sdx <- stats::sd(idd[[ix]]); sdz <- stats::sd(idd[[iz]])
  idd$Xc <- as.numeric(Xc); idd$Zc <- as.numeric(Zc)
  # ── 列名安全化（仅供建模内部使用）────────────────────────────────────────────
  # 与回归模块同理：列名含 `-`/空格/顿号时会被 as.formula() 当运算符解析。
  dv0 <- dv; ix0 <- ix; iz0 <- iz
  .m <- formula_name_mapping(c(dv0, ix0, iz0))
  idd <- rename_for_formula(idd, .m)
  dv <- unname(.m[dv0]); ix <- unname(.m[ix0]); iz <- unname(.m[iz0])
  # 对外显示一律用原始列名（dvL/ixL/izL），仅公式内部使用安全名
  dvL <- dv0; ixL <- ix0; izL <- iz0
  .badm <- unsafe_formula_names(c(dv0, ix0, iz0))
  if (length(.badm)) guide("  列名说明：", paste(.badm, collapse = "、"),
                           " 不是合法的 R 变量名，已在交互模型内部改用安全名计算，表格仍按原列名显示。")
  fint <- stats::lm(stats::as.formula(paste(dv, "~ Xc * Zc")), data = idd)
  cf <- summary(fint)$coefficients
  term_zh <- c("(Intercept)" = "截距", "Xc" = paste0(ix0, "（X，中心化）"), "Zc" = paste0(iz0, "（Z，中心化）"),
               "Xc:Zc" = paste0(ix0, " × ", iz0, "（交互项 Xc×Zc）"))
  save_table(data.frame(term = rownames(cf), term_label = unname(term_zh[rownames(cf)]),
                        B = cf[, 1], SE = cf[, 2], t = cf[, 3], p = cf[, 4]),
             ctx, "interaction_model", sprintf("【表1】调节（交互）模型：Y = %s；X/Z均先减去各自均值再构造乘积项（SPSS PROCESS Model 1）", dv))
  guide(sprintf("\n【表1变量说明】本模型预测 %s：X = %s（中心化后记 Xc），Z = %s（中心化后记 Zc），交互项 Xc:Zc = 两者乘积（检验\"Z是否调节X的效应\"）。",
                dvL, ixL, izL))
  zlevels <- c(-1, 0, 1)
  tr <- emmeans::emtrends(fint, specs = ~ Zc, var = "Xc", at = list(Zc = zlevels * sdz))
  ss <- as.data.frame(summary(tr, infer = TRUE))
  slopes <- data.frame(Z_level = c(paste0(izL, " 低(-1SD)"), paste0(izL, " 均值(M)"), paste0(izL, " 高(+1SD)")),
                       Z_value = zlevels * sdz,
                       simple_slope_of_X = ss$Xc.trend, se = ss$SE, t = ss$t.ratio, df = ss$df, p = ss$p.value)
  save_table(slopes, ctx, "simple_slopes", sprintf("【表2】%s 对 %s 的简单斜率（PROCESS\"条件效应\"：X的效应在Z = 低/中/高时的斜率）", ixL, dvL))
  b3 <- cf["Xc:Zc", 1]; p3 <- cf["Xc:Zc", 4]
  b1 <- cf["Xc", 1]; p1 <- cf["Xc", 4]
  save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_interaction.png")), function() {
    mz <- mean(idd[[iz]])
    pd <- data.frame(xv = rep(c(mz - sdz, mz, mz + sdz), each = 50))
    xr <- range(idd[[ix]])
    pd$Xc <- rep(seq(xr[1], xr[2], length.out = 50), 3)
    pd$Zc <- rep(zlevels * sdz, each = 50)
    pd$yv <- predict(fint, newdata = pd)
    pd$group <- factor(rep(c(paste0(izL, " 低(-1SD)"), paste0(izL, " 均值(M)"), paste0(izL, " 高(+1SD)")), each = 50),
                       levels = c(paste0(izL, " 低(-1SD)"), paste0(izL, " 均值(M)"), paste0(izL, " 高(+1SD)")))
    # 只保留基于 predict(fint) 的预测线（geom_line）；此前还叠加过 intercept=0 的 geom_abline 参考
    # 线，会画出错误的过原点直线并把 y 轴范围撑坏，已删除。
    print(ggplot2::ggplot(pd, ggplot2::aes(x = Xc, y = yv, group = group, color = group)) +
            ggplot2::geom_line(linewidth = 1) +
            ggplot2::labs(title = "Simple-slope interaction plot", x = ixL, y = dvL, color = izL) + ggplot2::theme_minimal())
  })
  guide("\n【结果怎么读（两步）】")
  guide(sprintf("  第1步 看交互项：Xc:Zc 的 B = %s，%s → %s。",
                fmt3(b3), fmt_p_inline(p3), ifelse(p3 < ctx$alpha, "存在调节效应（X的斜率随Z变化），进入第2步", "无调节证据，X的效应不随Z变化，报告主效应即可")))
  guide(sprintf("  第2步 看简单斜率（表2）：Z低(%s)时 X的斜率 = %s（%s）；Z高(+1SD)时 = %s（%s）——描述\"X的效应在Z不同水平下分别多强、是否显著\"。",
                fmt1(-sdz), fmt3(slopes$simple_slope_of_X[1]), fmt_p_inline(slopes$p[1]), fmt3(slopes$simple_slope_of_X[3]), fmt_p_inline(slopes$p[3])))
  guide("  交互图（interaction.png）中三条线斜率不同即为调节的直观表现；线越陡该条件下X效应越强。")
  guide("\n【结果写法（模板：请按你的实际结果核对方向与措辞）】",
        sprintf("%s 对 %s 的效应%s：交互项 B = %s，%s；简单斜率显示，%s 低（-1SD）时 B = %s（%s），高（+1SD）时 B = %s（%s）。",
                ixL, dvL,
                ifelse(p3 < ctx$alpha, sprintf("受 %s 调节（X 的斜率随 %s 变化）", izL, izL), sprintf("未发现受 %s 调节的证据", izL)),
                fmt3(b3), fmt_p_inline(p3), izL, fmt3(slopes$simple_slope_of_X[1]), fmt_p_inline(slopes$p[1]),
                fmt3(slopes$simple_slope_of_X[3]), fmt_p_inline(slopes$p[3])))
  guide("\n【注意】① 乘积项必须用中心化后的X、Z构造（减少共线性）；② 交互显著后\"主效应\"是平均值意义上的斜率，解释要小心；③ Johnson-Neyman区间（X效应显著的Z取值范围）可在PROCESS中勾选输出；④ 分类调节变量（如性别）直接做0/1编码交互。")
  invisible(NULL)
}
