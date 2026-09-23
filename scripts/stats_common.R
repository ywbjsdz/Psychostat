# Common helpers for the Psychostat undergraduate statistics workflow.  All text files are UTF-8.
# Statistics follow IBM SPSS conventions (default menus/parameters) so results can be cross-checked in SPSS.
`%||%` <- function(x, y) if (is.null(x)) y else x
stopf <- function(...) stop(sprintf(...), call. = FALSE)

hex_to_utf8 <- function(hex) {
  if (!nzchar(hex) || nchar(hex) %% 2L || !grepl("^[0-9A-Fa-f]+$", hex)) stopf("Invalid UTF-8 hexadecimal path marker.")
  raw_path <- as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
  enc2utf8(rawToChar(raw_path))
}

load_stats_config <- function(args = commandArgs(trailingOnly = TRUE)) {
  i_hex <- match("--config-utf8-hex", args); i_plain <- match("--config", args)
  if (!is.na(i_hex) && i_hex < length(args)) path <- normalizePath(hex_to_utf8(args[i_hex + 1L]), mustWork = TRUE)
  else if (!is.na(i_plain) && i_plain < length(args)) path <- normalizePath(args[i_plain + 1L], mustWork = TRUE)
  else stopf("A configuration file is required.")
  ext <- tolower(tools::file_ext(path))
  if (!ext %in% c("yaml", "yml", "json")) stopf("Configuration must be YAML or JSON: %s", path)
  cfg <- if (ext == "json") jsonlite::fromJSON(path, simplifyVector = FALSE) else yaml::read_yaml(path)
  list(config = cfg, path = path, base_dir = dirname(path))
}

resolve_stats_path <- function(path, base_dir) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:|^/", path)) path else normalizePath(file.path(base_dir, path), mustWork = FALSE)
}

as_character_vector <- function(x) {
  if (is.null(x)) return(NULL)
  unname(as.character(unlist(x, use.names = FALSE)))
}

# 配置层硬校验：output.directory / input.path / output.project_label 决定输入输出路径。yaml 里写成
# ".":（会被解析成数值 NA）、"~"/"null"（NULL）、数字或逻辑值时，as.character 会静默转换或让 NA
# 混进路径（结果被写进 ...\NA\... 之类的目录）。缺省时取 default；显式给出的值必须是长度1的
# 非NA非空字符串（input.path 允许空串 ""，与默认配置文件里的 path: "" 用法兼容）。
config_string_or <- function(value, field, default, allow_empty = FALSE) {
  if (is.null(value)) return(default)
  ok <- is.character(value) && length(value) == 1L && !is.na(value) && (allow_empty || nzchar(value))
  if (!ok)
    stopf("配置项 %s 必须是长度为1的非NA非空字符串（当前值：%s；请填写形如 '%s' 的文本值，不要用 NA/数字/逻辑值）。",
          field, paste(deparse(value), collapse = " "), default)
  value
}

STATS_METHODS <- list(
  datacheck               = list(label_zh = "数据准备与异常值筛查（建议先做）", spss = "分析 > 描述统计 > 探索（极端值表/箱线图）+ 分析 > 缺失值分析"),
  descriptives            = list(label_zh = "描述统计",             spss = "分析 > 描述统计 > 描述/探索"),
  normality               = list(label_zh = "正态性与方差齐性检验", spss = "分析 > 描述统计 > 探索 + 分析 > 比较均值 > 独立样本T检验（Levene行）"),
  one_sample_t            = list(label_zh = "单样本t检验",          spss = "分析 > 比较均值 > 单样本T检验"),
  independent_t           = list(label_zh = "独立样本t检验",        spss = "分析 > 比较均值 > 独立样本T检验"),
  paired_t                = list(label_zh = "配对样本t检验",        spss = "分析 > 比较均值 > 配对样本T检验"),
  one_way_anova           = list(label_zh = "单因素方差分析",       spss = "分析 > 比较均值 > 单因素ANOVA"),
  two_way_anova           = list(label_zh = "两因素方差分析",       spss = "分析 > 一般线性模型 > 单变量"),
  rm_anova                = list(label_zh = "重复测量方差分析",     spss = "分析 > 一般线性模型 > 重复测量"),
  mixed_anova             = list(label_zh = "混合设计方差分析",     spss = "分析 > 一般线性模型 > 重复测量（含被试间因子）"),
  ancova                  = list(label_zh = "协方差分析",           spss = "分析 > 一般线性模型 > 单变量（含协变量）"),
  correlation             = list(label_zh = "相关分析（含偏相关）",  spss = "分析 > 相关 > 双变量 / 偏相关"),
  regression              = list(label_zh = "多元线性回归",         spss = "分析 > 回归 > 线性"),
  chi_square_gof          = list(label_zh = "卡方适合度检验",       spss = "分析 > 非参数检验 > 旧对话框 > 卡方"),
  chi_square_independence = list(label_zh = "卡方独立性检验",       spss = "分析 > 描述统计 > 交叉表（卡方）"),
  mann_whitney            = list(label_zh = "Mann-Whitney U检验",   spss = "分析 > 非参数检验 > 旧对话框 > 2个独立样本"),
  wilcoxon_signed         = list(label_zh = "Wilcoxon符号秩检验",   spss = "分析 > 非参数检验 > 旧对话框 > 2个相关样本"),
  kruskal_wallis          = list(label_zh = "Kruskal-Wallis H检验", spss = "分析 > 非参数检验 > 旧对话框 > K个独立样本"),
  friedman                = list(label_zh = "Friedman检验",        spss = "分析 > 非参数检验 > 旧对话框 > K个相关样本"),
  mediation               = list(label_zh = "中介效应分析",         spss = "分析 > 回归 > PROCESS（Model 4，含Bootstrap）"),
  moderation              = list(label_zh = "调节效应分析",         spss = "分析 > 回归 > PROCESS（Model 1，简单斜率）"),
  power                   = list(label_zh = "统计功效与样本量",     spss = "对应 G*Power（pwr 包）")
)

DEMO_ORDER <- c("descriptives", "normality", "one_sample_t", "independent_t", "paired_t",
                "one_way_anova", "two_way_anova", "rm_anova", "mixed_anova", "ancova",
                "correlation", "regression", "chi_square_gof", "chi_square_independence",
                "mann_whitney", "wilcoxon_signed", "kruskal_wallis", "friedman", "mediation", "moderation", "power")

normalise_stats_config <- function(cfg, base_dir) {
  cfg$input <- cfg$input %||% list(); cfg$analysis <- cfg$analysis %||% list()
  cfg$output <- cfg$output %||% list(); cfg$simulation <- cfg$simulation %||% list()
  cfg$variables <- cfg$variables %||% list()
  if (is.character(cfg$method) && length(cfg$method) == 1L && tolower(cfg$method) == "all_demos") {
    cfg$method <- DEMO_ORDER
  } else {
    cfg$method <- tolower(as_character_vector(cfg$method))
    if (!length(cfg$method)) stopf("At least one method is required (or method: all_demos).")
  }
  unknown <- setdiff(cfg$method, names(STATS_METHODS))
  if (length(unknown)) stopf("Unknown methods: %s. Valid: %s", paste(unknown, collapse = ", "), paste(names(STATS_METHODS), collapse = ", "))
  cfg$input$mode <- tolower(as.character(cfg$input$mode %||% "simulate"))
  if (!cfg$input$mode %in% c("file", "simulate")) stopf("input.mode must be file or simulate.")
  cfg$input$path <- resolve_stats_path(config_string_or(cfg$input$path, "input.path", "", allow_empty = TRUE), base_dir)
  if (cfg$input$mode == "file" && (!is.character(cfg$input$path) || !nzchar(cfg$input$path) || !file.exists(cfg$input$path)))
    stopf("input.path must point to an existing CSV/XLSX/XLS/SAV file when input.mode is file.")
  cfg$analysis$alpha <- as.numeric(cfg$analysis$alpha %||% 0.05)
  if (is.na(cfg$analysis$alpha) || cfg$analysis$alpha <= 0 || cfg$analysis$alpha >= 1) stopf("analysis.alpha must be between 0 and 1.")
  cfg$analysis$correlation_method <- tolower(as.character(cfg$analysis$correlation_method %||% "pearson"))
  if (!cfg$analysis$correlation_method %in% c("pearson", "spearman", "both")) stopf("analysis.correlation_method must be pearson, spearman, or both.")
  cfg$analysis$posthoc <- intersect(as_character_vector(cfg$analysis$posthoc %||% c("lsd", "tukey", "bonferroni")), c("lsd", "tukey", "bonferroni"))
  cfg$analysis$incremental <- isTRUE(cfg$analysis$incremental %||% FALSE)
  # 数据准备（第 0 步）配置：默认只报告、不动数据；缺失值处理与异常值删除必须由用户显式指定
  cfg$datacheck <- cfg$datacheck %||% list()
  cfg$datacheck$missing_action <- tolower(as.character(cfg$datacheck$missing_action %||% "report"))
  if (!cfg$datacheck$missing_action %in% c("report", "mean_impute", "listwise"))
    stopf("datacheck.missing_action 必须是 report、mean_impute 或 listwise。")
  cfg$datacheck$outlier_action <- tolower(as.character(cfg$datacheck$outlier_action %||% "report"))
  if (!cfg$datacheck$outlier_action %in% c("report", "remove_by_z"))
    stopf("datacheck.outlier_action 必须是 report 或 remove_by_z。")
  cfg$datacheck$z_cutoff <- as.numeric(cfg$datacheck$z_cutoff %||% 3)
  if (!is.finite(cfg$datacheck$z_cutoff) || cfg$datacheck$z_cutoff <= 0)
    stopf("datacheck.z_cutoff 必须是正数（默认 3，即 |Z| > 3 视为异常值）。")
  if (!is.null(cfg$datacheck$scale_vars)) {
    cfg$datacheck$scale_vars <- as.character(unlist(cfg$datacheck$scale_vars))
    if (!length(cfg$datacheck$scale_vars)) cfg$datacheck$scale_vars <- NULL
  }
  if (!is.null(cfg$datacheck$scale_range)) {
    sr <- suppressWarnings(as.numeric(unlist(cfg$datacheck$scale_range)))
    if (length(sr) != 2L || any(!is.finite(sr))) stopf("datacheck.scale_range 必须是两个数字，如 [1, 5]。")
    cfg$datacheck$scale_range <- sr
  }
  cfg$simulation$seed <- as.integer(cfg$simulation$seed %||% 20260904L)
  cfg$simulation$n_per_group <- as.integer(cfg$simulation$n_per_group %||% 30L)
  cfg$output$directory <- resolve_stats_path(config_string_or(cfg$output$directory, "output.directory", "outputs"), base_dir)
  cfg$output$project_label <- gsub("[^A-Za-z0-9_-]", "_", config_string_or(cfg$output$project_label, "output.project_label", "stats_demo"))
  cfg$output$report_language <- tolower(as.character(cfg$output$report_language %||% "zh"))
  cfg
}

read_stats_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") return(read.csv(path, check.names = FALSE, na.strings = c("", "NA", "."), fileEncoding = "UTF-8-BOM"))
  if (ext %in% c("xlsx", "xls")) return(as.data.frame(readxl::read_excel(path)))
  if (ext == "sav") return(as.data.frame(haven::read_sav(path)))
  stopf("Unsupported input extension: %s", ext)
}

write_csv_utf8 <- function(x, path) write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
write_csv_bom <- function(x, path) {
  # SPSS/Excel-friendly UTF-8 with BOM: write UTF-8 first, then prepend the BOM bytes.
  write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  raw <- readBin(path, "raw", file.info(path)$size)
  con <- file(path, open = "wb", encoding = "native.enc")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), raw), con)
  close(con)
  invisible(path)
}

save_png <- function(path, draw_fun, width = 8, height = 5) {
  # Use the GDI ("windows") device on Windows so CJK labels (e.g. Chinese column names in user data)
  # render correctly; cairo without a configured CJK font draws empty boxes.
  type <- if (.Platform$OS.type == "windows") "windows" else "cairo"
  grDevices::png(path, width = width, height = height, units = "in", res = 300, type = type)
  on.exit(grDevices::dev.off(), add = TRUE); draw_fun()
}

# SPSS prints p-values as ".000" / ".021"; mirror that formatting in CSV tables and reports.
fmt_p <- function(p) ifelse(is.na(p), NA_character_, ifelse(p < 5e-4, ".000", sub("^0\\.", ".", formatC(p, format = "f", digits = 3))))

# SPSS EXAMINE reports g1/g2 skewness/kurtosis (population-corrected) with asymptotic standard errors.
spss_skewness <- function(x) {
  x <- x[is.finite(x)]; n <- length(x); m <- mean(x); s <- sd(x)
  if (n < 3L || s == 0) return(c(skewness = NA_real_, se = NA_real_))
  z <- (x - m) / s
  g1 <- (n / ((n - 1) * (n - 2))) * sum(z^3)
  se <- sqrt(6 * n * (n - 1) / ((n - 2) * (n + 1) * (n + 3)))
  c(skewness = g1, se = se)
}

spss_kurtosis <- function(x) {
  x <- x[is.finite(x)]; n <- length(x); m <- mean(x); s <- sd(x)
  if (n < 4L || s == 0) return(c(kurtosis = NA_real_, se = NA_real_))
  z <- (x - m) / s
  g2 <- ((n * (n + 1)) / ((n - 1) * (n - 2) * (n - 3))) * sum(z^4) - 3 * (n - 1)^2 / ((n - 2) * (n - 3))
  se_skew <- sqrt(6 * n * (n - 1) / ((n - 2) * (n + 1) * (n + 3)))
  se <- 2 * se_skew * sqrt((n^2 - 1) / ((n - 3) * (n + 5)))
  c(kurtosis = g2, se = se)
}

# SPSS t-tests use mean-centred Levene (car::leveneTest with center = "mean").
levene_spss <- function(y, group) {
  y <- as.numeric(y); group <- as.factor(group)
  ok <- is.finite(y) & !is.na(group); y <- y[ok]; group <- droplevels(group[ok])
  if (nlevels(group) < 2L) stopf("Levene's test needs at least two groups.")
  tab <- car::leveneTest(y ~ group, center = "mean")
  data.frame(F = unname(tab[1, "F value"]), df1 = unname(tab[1, "Df"]), df2 = unname(tab[2, "Df"]), p = unname(tab[1, "Pr(>F)"]))
}

# SPSS ONEWAY's Robust Tests table is a test of equality of means. It is
# distinct from the Brown-Forsythe variant of Levene's variance test.
brown_forsythe_spss <- function(y, group) {
  dd <- data.frame(y = as.numeric(y), group = droplevels(as.factor(group)))
  dd <- dd[is.finite(dd$y) & !is.na(dd$group), , drop = FALSE]
  if (nlevels(dd$group) < 2L) stopf("Brown-Forsythe test needs at least two groups.")
  z <- onewaytests::bf.test(y ~ group, data = dd, verbose = FALSE)
  data.frame(F = unname(z$statistic), df1 = unname(z$parameter[1]),
             df2 = unname(z$parameter[2]), p = z$p.value)
}

# Friedman ranks are assigned within each participant, then averaged by condition.
friedman_mean_ranks_spss <- function(wide) {
  x <- as.matrix(wide)
  if (!nrow(x) || !ncol(x)) return(numeric())
  colMeans(t(apply(x, 1L, rank, ties.method = "average")))
}

# SPSS 27+ effect sizes: d for independent samples uses the pooled SD (with Hedges' g shown alongside).
cohens_d_independent <- function(x, group) {
  g <- as.factor(group); lev <- levels(g); a <- as.numeric(x[g == lev[1]]); b <- as.numeric(x[g == lev[2]])
  sp <- sqrt(((length(a) - 1) * var(a) + (length(b) - 1) * var(b)) / (length(a) + length(b) - 2))
  d <- (mean(a) - mean(b)) / sp
  J <- 1 - 3 / (4 * (length(a) + length(b)) - 9)
  c(d = d, hedges_g = J * d)
}

cohens_d_paired <- function(differences) {
  d <- mean(differences) / sd(differences)
  n <- length(differences)
  J <- 1 - 3 / (4 * n - 9)
  c(d = d, hedges_g = J * d)
}

# Normalise aov-stratum tables: unclassed anova objects may carry dotted column names
# (Sum.Sq / F.value / Pr..F.) and padded row names; unify them with the classic SPSS-style names.
normalise_anova_tab <- function(tab) {
  if (is.null(tab)) return(NULL)
  tab <- as.data.frame(unclass(tab))
  nm <- names(tab)
  nm[nm %in% c("Sum.Sq", "Sum Sq")] <- "Sum Sq"
  nm[nm %in% c("Mean.Sq", "Mean Sq")] <- "Mean Sq"
  nm[nm %in% c("F.value", "F value")] <- "F value"
  nm[nm %in% c("Pr..F.", "Pr(>F)")] <- "Pr(>F)"
  names(tab) <- nm
  rownames(tab) <- trimws(rownames(tab))
  tab
}

partial_eta_sq <- function(ss_effect, ss_error) ss_effect / (ss_effect + ss_error)

interpret_d <- function(d) {
  d <- abs(d)
  ifelse(is.na(d), NA_character_, ifelse(d < 0.2, "小效应（≈0.2为小）", ifelse(d < 0.5, "偏小/接近中等", ifelse(d < 0.8, "中等效应（0.5）", "大效应（0.8）"))))
}

interpret_eta2 <- function(e) {
  ifelse(is.na(e), NA_character_, ifelse(e < 0.01, "小效应（.01）", ifelse(e < 0.06, "偏小/接近中等", ifelse(e < 0.14, "中等效应（.06）", "大效应（.14）"))))
}

interpret_r <- function(r) {
  r <- abs(r)
  ifelse(is.na(r), NA_character_, ifelse(r < 0.1, "小效应（.10）", ifelse(r < 0.3, "偏小/接近中等", ifelse(r < 0.5, "中等效应（.30）", "大效应（.50）"))))
}

interpret_cramers_v <- function(v, k) {
  # Cohen's benchmarks shrink with table size; use the small/medium/large thresholds scaled by df' = min(r,c)-1.
  dfa <- k - 1
  small <- 0.1 / sqrt(dfa); medium <- 0.3 / sqrt(dfa); large <- 0.5 / sqrt(dfa)
  ifelse(is.na(v), NA_character_, ifelse(v < small, "小效应", ifelse(v < medium, "偏小/接近中等", ifelse(v < large, "中等效应", "大效应"))))
}

# Interactive-guidance helpers: every analysis echoes what it is doing, which SPSS dialog it mirrors,
# and how to read the resulting table.  Text is buffered so the same guidance lands in the Markdown report.
stats_session <- new.env(parent = emptyenv())
stats_session$report <- character()

# Interactive-guidance helpers: every analysis echoes what it is doing, which SPSS dialog it mirrors,
# and how to read the resulting table.  Text is buffered so the same guidance lands in the Markdown report.
stats_session <- new.env(parent = emptyenv())
stats_session$report <- character()

guide <- function(..., section = NULL, echo = TRUE) {
  txt <- paste0(..., "\n")
  if (echo) cat(txt)
  if (!is.null(section)) {
    stats_session$report <- c(stats_session$report, section, txt)
  } else {
    stats_session$report <- c(stats_session$report, txt)
  }
  invisible(txt)
}

reset_report <- function() stats_session$report <- character()

write_report <- function(path, header) {
  body <- paste(stats_session$report, collapse = "")
  writeLines(enc2utf8(paste0(header, body)), path, useBytes = TRUE)
}

p_star <- function(p, alpha = 0.05) ifelse(is.na(p), "", ifelse(p < 0.001, "***", ifelse(p < 0.01, "**", ifelse(p < alpha, "*", ""))))

# 行内 p 值（"p < .001" / "p = .021"）。
fmt_p_inline <- function(p) ifelse(is.na(p), "p = NA", ifelse(p < 0.001, "p < .001", paste0("p = ", fmt_p(p))))

# ─── 正态性结论的统一表述 ─────────────────────────────────────────────────────
# Shapiro-Wilk 只在 3 ≤ n ≤ 5000 时计算；超出范围（大样本问卷很常见）sw_p 为 NA。
# 把"未检验"当成"检验不显著"，会输出"正态性通过"的假结论 —— 因此结论句必须经
# 以下函数产出，明确区分【未检验】/【显著偏离】/【未见偏离】三种状态。
normality_untested_note <- function(ntab) {
  untested <- if ("sw_tested" %in% names(ntab)) ntab[!is.na(ntab$sw_tested) & !ntab$sw_tested, ] else ntab[is.na(ntab$sw_p), ]
  if (!nrow(untested)) return(NULL)
  too_big <- untested$N > 5000L; too_small <- untested$N < 3L
  reason <- if (any(too_big) && any(too_small)) "样本量超出 S-W 适用范围（n < 3 或 n > 5000）"
            else if (any(too_big)) sprintf("样本量 > 5000，超出本工具 S-W 实现的适用范围（如 %s）", paste(unique(untested$segment[too_big]), collapse = "、"))
            else sprintf("有效样本量 < 3（如 %s）", paste(unique(untested$segment[too_small]), collapse = "、"))
  sprintf("%s【未检验】%s。请改看 K-S(Lilliefors) 列、偏度峰度与分布图自行判断，不要据此断言\"正态性通过\"。",
          paste(untested$segment, collapse = "、"), reason)
}

normality_violation_note <- function(ntab, alpha = 0.05) {
  tested <- if ("sw_tested" %in% names(ntab)) ntab[!is.na(ntab$sw_tested) & ntab$sw_tested, ] else ntab[!is.na(ntab$sw_p), ]
  bad <- tested[!is.na(tested$sw_p) & tested$sw_p < alpha, ]
  if (!nrow(bad)) return(NULL)
  sprintf("S-W p < %s 的变量·组段：%s", alpha, paste(bad$segment, collapse = "、"))
}

normality_ok_note <- function(ntab, alpha = 0.05) {
  tested <- if ("sw_tested" %in% names(ntab)) ntab[!is.na(ntab$sw_tested) & ntab$sw_tested, ] else ntab[!is.na(ntab$sw_p), ]
  tested <- tested[!is.na(tested$sw_p), ]
  if (!nrow(tested)) return(NULL)
  sprintf("已检验的 %d 个变量·组段 S-W 均 p > %s，未见显著偏离正态。", nrow(tested), alpha)
}

# ─── 结果句模板（数据驱动，不下固定结论）──────────────────────────────────────
# 背景：这些面向"怎么写结果"的示范句，此前把方向、构念名与"显著"写死在字符串里，
# 数字却来自用户数据 → 会产出与数据矛盾的结论（例如交互 p = .900 仍写"效应受调节"、
# 实验组均值更高却写"显著低于"）。现在一律由实际统计量与实际变量名填充；
# 凡无法从统计量唯一确定方向的（多组/多水平/交互），显式提示读者自行确认方向。
# 二分类/两组：方向由实际均值差决定（>0 表示第 1 组更高）
two_group_direction <- function(m1, m2, lab1, lab2) {
  if (!is.finite(m1) || !is.finite(m2)) return(c(txt = "（方向请对照组统计量）", verb = "高于/低于"))
  if (m1 > m2) c(txt = sprintf("%s 高于 %s", lab1, lab2), verb = "高于")
  else if (m1 < m2) c(txt = sprintf("%s 高于 %s", lab2, lab1), verb = "低于")
  else c(txt = sprintf("%s 与 %s 均值相等", lab1, lab2), verb = "等于")
}

# 多水平：报"均值最高/最低的水平"，不假设具体是哪一组
levels_shape_note <- function(labels, means) {
  ok <- is.finite(means)
  if (!any(ok)) return("（各组均值：见描述统计表）")
  sprintf("均值最高为 %s（M = %s），最低为 %s（M = %s）；差异方向与大小请对照描述统计表",
          labels[which.max(ifelse(ok, means, -Inf))], fmt2(max(means[ok])),
          labels[which.min(ifelse(ok, means, Inf))], fmt2(min(means[ok])))
}

# 成对比较：挑 |差| 最大的那一对，返回"高组 vs 低组（差 = x）"式的描述
pairwise_shape_note <- function(labels1, labels2, diffs) {
  d <- suppressWarnings(as.numeric(diffs)); ok <- is.finite(d)
  if (!any(ok)) return("（各配对差异：见事后比较表）")
  i <- which.max(abs(d[ok])); idx <- which(ok)[i]
  hi <- if (d[idx] > 0) labels1[idx] else labels2[idx]
  lo <- if (d[idx] > 0) labels2[idx] else labels1[idx]
  sprintf("差异最大的一对是 %s 高于 %s（差 = %s）", hi, lo, fmt2(abs(d[idx])))
}

# ─── 列名安全化（供 as.formula / lavaan 语法使用）─────────────────────────────
# 用户问卷表头常含空格、`-`、顿号、括号、前导数字（如 "T1-T3总分"、"1、我常感到紧张"）。
# 直接拼进 as.formula() 会被当作运算符/语法元素 → 模型静默变形或 object not found。
# 因此在建模前把参与公式的列改名为 ASCII 安全名，并保留原名↔安全名对照供表格回显。
unsafe_formula_names <- function(names_used) {
  used <- unique(as.character(names_used))
  used[!grepl("^[A-Za-z][A-Za-z0-9._]*$", used)]
}

formula_name_mapping <- function(names_used) {
  used <- unique(as.character(names_used))
  stats::setNames(paste0(".ps_", seq_along(used)), used)
}

rename_for_formula <- function(data, mapping) {
  out <- data
  for (nm in names(mapping)) out[[mapping[[nm]]]] <- data[[nm]]
  out
}

# Type III sums of squares everywhere (SPSS GLM/UNIANOVA default) requires sum-to-zero contrasts.
use_spss_contrasts <- function() options(contrasts = c("contr.sum", "contr.poly"))

# Extract a compact ANOVA row table (SPSS-style: SS, df, MS, F, p, partial eta squared).
anova_table_spss <- function(fit, terms = NULL) {
  tab <- car::Anova(fit, type = 3)
  rows <- rownames(tab)
  keep <- if (is.null(terms)) rows else intersect(terms, rows)
  out <- do.call(rbind, lapply(keep, function(r) {
    ss <- tab[r, "Sum Sq"]; df <- tab[r, "Df"]; ms <- ss / df
    f <- tab[r, "F value"]; p <- tab[r, "Pr(>F)"]
    sse <- tab["Residuals", "Sum Sq"]
    data.frame(source = r, SS = ss, df = df, MS = ms, F = f, p = p,
               partial_eta_sq = if (r == "Residuals") NA else partial_eta_sq(ss, sse))
  }))
  out
}


# Simple-effect omnibus tests must retain the fitted factorial model's error term.
# Splitting data and refitting one-way ANOVAs changes denominator df in unbalanced data.
spss_simple_effect_omnibus <- function(fit, focal, by) {
  emm <- emmeans::emmeans(
    fit,
    specs = stats::as.formula(sprintf("~ %s * %s", focal, by))
  )
  jt <- as.data.frame(emmeans::joint_tests(emm, by = by))
  keep <- jt[as.character(jt[["model term"]]) == focal, , drop = FALSE]
  if (!nrow(keep)) stopf("Cannot obtain simple effects of %s by %s from the fitted model.", focal, by)
  data.frame(
    by_level = as.character(keep[[by]]),
    F = keep[["F.ratio"]], df1 = keep$df1, df2 = keep$df2, p = keep$p.value
  )
}

# SPSS GLM repeated-measures Type III model, used by both repeated and mixed designs.
spss_repeated_glm <- function(wide, group = NULL, time_labels = colnames(wide)) {
  wide <- as.data.frame(wide)
  k <- ncol(wide)
  if (k < 2L) stopf("Repeated-measures analysis needs at least two within-subject columns.")
  idata <- data.frame(time = factor(seq_len(k), levels = as.character(seq_len(k)), labels = time_labels))
  if (is.null(group)) {
    fit <- stats::lm(as.matrix(wide) ~ 1)
  } else {
    d <- data.frame(grp = droplevels(as.factor(group)))
    fit <- stats::lm(as.matrix(wide) ~ grp, data = d)
  }
  ma <- car::Anova(fit, idata = idata, idesign = ~ time, type = 3)
  list(fit = fit, anova = ma, summary = suppressWarnings(summary(ma, multivariate = FALSE)))
}
# Sphericity helpers work on summary(car::Anova(mlm), multivariate = FALSE), whose layout is
# univariate.tests / pval.adjustments / sphericity.tests.  car's table only exposes W and p (no chisq),
# and its p is computed from the model's error df (N - g for mixed designs), so reconstructing chisq from W
# with the SPSS n-1 formula can disagree with the p in the same table by ~1%.  Instead invert car's own p
# (qchisq, exact) so chisq and p are guaranteed 同源: pchisq(chisq, df, lower.tail = FALSE) == p.
rm_univariate <- function(car_summary, term) {
  t <- car_summary$univariate.tests[term, ]
  list(SS = t[["Sum Sq"]], df1 = t[["num Df"]], SS_err = t[["Error SS"]], df2 = t[["den Df"]],
       F = t[["F value"]], p = t[["Pr(>F)"]])
}

gg_hf_epsilons <- function(car_summary) {
  empty <- data.frame(term = character(), GG_eps = numeric(), HF_eps = numeric(), GG_p = numeric(), HF_p = numeric())
  adj <- car_summary$pval.adjustments
  if (is.null(adj) || !nrow(adj)) return(empty)
  rn <- rownames(adj); cn <- colnames(adj)
  col <- function(cand) { h <- cand[cand %in% cn]; if (length(h)) adj[, h[1]] else rep(NA_real_, nrow(adj)) }
  data.frame(term = rn, GG_eps = col(c("GG eps", "GG_eps")), HF_eps = pmin(col(c("HF eps", "HF_eps")), 1),
             GG_p = col(c("Pr(>F[GG])", "GG p")), HF_p = col(c("Pr(>F[HF])", "HF p")))
}

mauchly_table <- function(car_summary, n = NULL, q = NULL) {
  st <- car_summary$sphericity.tests
  if (is.null(st) || !nrow(st)) return(data.frame(term = character(), Mauchly_W = numeric(), chisq = numeric(), df = numeric(), p = numeric()))
  W <- st[, 1]; p <- st[, 2]
  chisq <- rep(NA_real_, length(W)); df <- rep(NA_real_, length(W))
  if (!is.null(q)) {
    df <- q * (q + 1) / 2 - 1
    p_safe <- pmin(pmax(p, .Machine$double.xmin), 1 - .Machine$double.eps)
    chisq <- stats::qchisq(p_safe, df, lower.tail = FALSE)
  }
  data.frame(term = rownames(st), Mauchly_W = W, chisq = chisq, df = df, p = p)
}
