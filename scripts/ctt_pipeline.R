# Psychostat CTT pipeline: cleaning, item analysis, reliability/validity, EFA, CFA and exports.
script_arg <- commandArgs(FALSE)
script_arg <- sub("^--file=", "", script_arg[grep("^--file=", script_arg)][1])
source(file.path(dirname(normalizePath(script_arg)), "ctt_common.R"))

make_result_dir <- function(cfg) {
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out <- file.path(cfg$output$directory, sprintf("%s_ctt_%s", cfg$output$project_label, stamp))
  dir.create(out, recursive = TRUE, showWarnings = FALSE); out
}

save_png <- function(path, draw_fun, width = 8, height = 5) {
  grDevices::png(path, width = width, height = height, units = "in", res = 300, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE); draw_fun()
}

clean_ctt_data <- function(data, item_names, cfg) {
  raw_n <- nrow(data); items <- data[item_names]
  audit <- data.frame(participant = seq_len(raw_n), missing_pct = rowMeans(is.na(items)) * 100, attention_fail = FALSE,
                      too_fast = FALSE, straightline = FALSE, extreme_z = FALSE, extreme_iqr = FALSE, removed = FALSE)
  # Reverse scoring is done before imputation so every later statistic uses a common scoring direction.
  reverse <- intersect(cfg$cleaning$reverse_items %||% character(), item_names)
  absent_reverse <- setdiff(cfg$cleaning$reverse_items %||% character(), item_names)
  if (length(absent_reverse)) stopf("Reverse-scored item(s) are not among item_columns: %s", paste(absent_reverse, collapse = ", "))
  # 反向计分前先确认观测范围与 scale_maximum 一致：公式 k+1-x 只在 1..k 计分下成立。
  # 若数据是 0..4 编码而 scale_maximum 配成 5，反向会得到 6..2——数值全错且原来不会报错。
  .all_obs <- unlist(items, use.names = FALSE); .all_obs <- .all_obs[!is.na(.all_obs)]
  if (length(.all_obs)) {
    .lo <- min(.all_obs); .hi <- max(.all_obs)
    if (length(reverse) && (.lo < 1 || .hi > cfg$cleaning$scale_maximum))
      stopf("Reverse scoring assumes 1..scale_maximum, but observed responses range %g..%g while cleaning.scale_maximum = %g. Fix the coding or the scale_maximum setting.", .lo, .hi, cfg$cleaning$scale_maximum)
    if (.hi > cfg$cleaning$scale_maximum)
      cat(sprintf("提示：观测最大值 %g 超过 cleaning.scale_maximum = %g；若数据是 0..k-1 编码请改成 k-1。\n", .hi, cfg$cleaning$scale_maximum))
  }
  if (length(reverse)) for (nm in reverse) items[[nm]] <- cfg$cleaning$scale_maximum + 1L - items[[nm]]
  attention <- cfg$cleaning$attention_item
  if (!is.null(attention) && nzchar(attention)) {
    if (!attention %in% names(data)) stopf("attention_item was not found: %s", attention)
    if (is.null(cfg$cleaning$attention_correct_value)) stopf("attention_correct_value is required when attention_item is set.")
    audit$attention_fail <- !is.na(data[[attention]]) & as.character(data[[attention]]) != as.character(cfg$cleaning$attention_correct_value)
  }
  time_col <- cfg$cleaning$response_time_column
  if (!is.null(time_col) && nzchar(time_col)) {
    if (!time_col %in% names(data)) stopf("response_time_column was not found: %s", time_col)
    if (is.na(cfg$cleaning$minimum_response_seconds)) stopf("minimum_response_seconds is required when response_time_column is set.")
    audit$too_fast <- suppressWarnings(as.numeric(data[[time_col]])) < cfg$cleaning$minimum_response_seconds
    audit$too_fast[is.na(audit$too_fast)] <- FALSE
  }
  audit$straightline <- apply(items, 1L, function(z) { z <- z[!is.na(z)]; length(z) >= 3L && length(unique(z)) == 1L })
  # Case-level missing rule: <5% median imputation; >20% deletion.  5–20% follows explicit config.
  high_missing <- audit$missing_pct > 20
  mid_missing <- audit$missing_pct >= 5 & audit$missing_pct <= 20
  if (any(mid_missing) && cfg$cleaning$missing_5_to_20 == "stop") stopf("%d participant(s) have 5%%–20%% missing values. Set cleaning.missing_5_to_20 to listwise or median_impute after review.", sum(mid_missing))
  remove_missing <- high_missing | (mid_missing & cfg$cleaning$missing_5_to_20 == "listwise")
  impute_rows <- audit$missing_pct < 5 | (mid_missing & cfg$cleaning$missing_5_to_20 == "median_impute")
  # 中位数只应基于**会保留下来**的个案计算。早先在整个样本（含将被删除的高缺失个案）上取中位数，
  # 会把被删个案的反应也掺进插补值里——虽然影响通常很小，但它可复现且没有理由保留。
  median_rows <- !remove_missing
  medians <- vapply(items, function(z) stats::median(z[median_rows], na.rm = TRUE), numeric(1))
  for (nm in names(items)) {
    ix <- is.na(items[[nm]]) & impute_rows
    items[[nm]][ix] <- medians[[nm]]
  }
  # Mark extremes from temporarily available total score; their removal remains user-controlled.
  score <- rowSums(items, na.rm = TRUE); z <- as.numeric(scale(score)); q <- stats::quantile(score, c(.25, .75), na.rm = TRUE); iqr <- q[2] - q[1]
  audit$extreme_z <- abs(z) > 3
  audit$extreme_iqr <- score < q[1] - 1.5 * iqr | score > q[2] + 1.5 * iqr
  removal <- remove_missing | audit$attention_fail | audit$too_fast
  if (cfg$cleaning$straightline_action == "remove") removal <- removal | audit$straightline
  if (cfg$cleaning$extreme_action == "remove") removal <- removal | audit$extreme_z | audit$extreme_iqr
  audit$removed <- removal
  kept <- !removal
  if (sum(kept) < 30L) stopf("Too few usable participants after cleaning (%d). At least 30 are required.", sum(kept))
  items <- items[kept, , drop = FALSE]; original <- data[kept, , drop = FALSE]
  if (anyNA(items)) stopf("Missing values remain after cleaning. Review the missing-data rule.")
  list(items = items, metadata = original, audit = audit, summary = data.frame(
    raw_n = raw_n, retained_n = nrow(items), removed_n = sum(removal), global_missing_pct = mean(is.na(data[item_names])) * 100,
    reverse_scored = if (length(reverse)) paste(reverse, collapse = "; ") else "None",
    attention_failed = sum(audit$attention_fail), too_fast = sum(audit$too_fast), straightline_flagged = sum(audit$straightline),
    extreme_flagged = sum(audit$extreme_z | audit$extreme_iqr), stringsAsFactors = FALSE))
}

run_item_analysis <- function(items) {
  n <- nrow(items); total <- rowSums(items); order_index <- order(total); group_n <- max(1L, floor(.27 * n))
  low <- order_index[seq_len(group_n)]; high <- order_index[(n - group_n + 1L):n]
  alpha_obj <- psych::alpha(items, check.keys = FALSE, warnings = FALSE)
  citc <- stats::setNames(alpha_obj$item.stats[match(names(items), rownames(alpha_obj$item.stats)), "r.drop"], names(items))
  rows <- lapply(names(items), function(nm) {
    # CR 决断值主列对齐 SPSS/教材口径：合并方差 t（df = n_high + n_low - 2，整数）；Welch 校正结果保留为 CR_t_welch/df_welch 参考列。
    tt <- stats::t.test(items[[nm]][high], items[[nm]][low], var.equal = TRUE)
    tw <- stats::t.test(items[[nm]][high], items[[nm]][low], var.equal = FALSE)
    data.frame(item = nm, low_mean = mean(items[[nm]][low]), high_mean = mean(items[[nm]][high]), CR_t = unname(tt$statistic), df = as.integer(round(unname(tt$parameter))), p = tt$p.value,
               CR_t_welch = unname(tw$statistic), df_welch = unname(tw$parameter), CITC = citc[[nm]], CR_pass = unname(tt$statistic) > 3 && tt$p.value < .05, CITC_pass = citc[[nm]] > .30,
               retain_recommendation = (unname(tt$statistic) > 3 && tt$p.value < .05 && citc[[nm]] > .30), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

cohens_d <- function(x, g) {
  lev <- levels(g); a <- x[g == lev[1]]; b <- x[g == lev[2]]
  sp <- sqrt(((length(a)-1)*stats::var(a) + (length(b)-1)*stats::var(b)) / (length(a)+length(b)-2))
  (mean(a)-mean(b))/sp
}

run_reliability_validity <- function(items, metadata, cfg, mapping = NULL, mapping_source = NULL) {
  notes <- character()
  # ω（单因子 McDonald's omega，nfactors=1）：失败/无定义时记 NA 并进运行日志提示，不阻塞信度表；<3 题不计算（调用处已保证）。
  omega_1f <- function(x, label) {
    om <- tryCatch(suppressMessages(suppressWarnings(psych::omega(x, nfactors = 1, plot = FALSE))), error = function(e) NULL)
    if (is.null(om) || is.null(om$omega.tot) || !is.finite(as.numeric(om$omega.tot))) { notes <<- c(notes, sprintf("%s 的 omega 计算失败或无定义，已记为 NA（Cronbach's α 不受影响）。", label)); return(NA_real_) }
    as.numeric(om$omega.tot)
  }
  a <- psych::alpha(items, check.keys = FALSE, warnings = FALSE)
  total <- rowSums(items)
  # alpha_ci_*：α 的 95% 正态近似置信区间（raw_alpha ± 1.96×ase，ase 为 psych::alpha 的标准误）。
  reliability <- data.frame(scale = "Total", n_items = ncol(items), alpha = a$total$raw_alpha, acceptable_alpha_gt_70 = a$total$raw_alpha > .70,
                            omega = omega_1f(items, "总量表"), alpha_ci_lower = a$total$raw_alpha - stats::qnorm(.975) * a$total$ase,
                            alpha_ci_upper = a$total$raw_alpha + stats::qnorm(.975) * a$total$ase, source = "Total", stringsAsFactors = FALSE)
  alpha_deleted <- data.frame(item = rownames(a$alpha.drop), alpha_if_deleted = a$alpha.drop$raw_alpha, delete_recommendation = a$alpha.drop$raw_alpha - a$total$raw_alpha > .05, row.names = NULL)
  if (!is.null(mapping) && nrow(mapping)) {
    for (d in unique(mapping$dimension)) {
      its <- mapping$item[mapping$dimension == d]; if (length(its) >= 2L) {
        aa <- psych::alpha(items[its], check.keys = FALSE, warnings = FALSE)
        reliability <- rbind(reliability, data.frame(scale = d, n_items = length(its), alpha = aa$total$raw_alpha, acceptable_alpha_gt_70 = aa$total$raw_alpha > .70,
                              omega = if (length(its) >= 3L) omega_1f(items[its], sprintf("分量表 %s", d)) else NA_real_,
                              alpha_ci_lower = aa$total$raw_alpha - stats::qnorm(.975) * aa$total$ase,
                              alpha_ci_upper = aa$total$raw_alpha + stats::qnorm(.975) * aa$total$ase,
                              source = mapping_source %||% NA_character_, stringsAsFactors = FALSE))
      }
    }
  }
  criterion <- data.frame(status = "Not assessed: no criterion column was supplied.")
  cn <- cfg$analysis$criterion_column
  if (!is.null(cn) && nzchar(cn)) {
    if (!cn %in% names(metadata)) stopf("criterion_column was not found: %s", cn)
    z <- suppressWarnings(as.numeric(metadata[[cn]])); ok <- is.finite(z)
    if (sum(ok) >= 3L) { ct <- stats::cor.test(total[ok], z[ok]); expected <- cfg$analysis$criterion_direction
      criterion <- data.frame(criterion = cn, r = unname(ct$estimate), p = ct$p.value, expected_direction = expected,
                              direction_matches = if (expected == "positive") unname(ct$estimate) > 0 else unname(ct$estimate) < 0,
                              significant = ct$p.value < .05) }
  }
  known <- data.frame(status = "Not assessed: no known-group column was supplied.")
  gn <- cfg$analysis$known_group_column
  if (!is.null(gn) && nzchar(gn)) {
    if (!gn %in% names(metadata)) stopf("known_group_column was not found: %s", gn)
    g <- droplevels(as.factor(metadata[[gn]])); ok <- !is.na(g)
    if (nlevels(g[ok]) < 2L) stopf("known_group_column needs at least two non-empty groups.")
    if (nlevels(g[ok]) == 2L) { tt <- stats::t.test(total[ok] ~ g[ok]); known <- data.frame(test = "Welch t", groups = paste(levels(g[ok]), collapse = " vs "), statistic = unname(tt$statistic), df = unname(tt$parameter), p = tt$p.value, effect = "Cohen_d", effect_value = cohens_d(total[ok], g[ok]), significant = tt$p.value < .05) }
    else { fit <- stats::aov(total[ok] ~ g[ok]); tab <- summary(fit)[[1]]; eta2 <- tab[1, "Sum Sq"] / sum(tab[, "Sum Sq"]); known <- data.frame(test = "One-way ANOVA", groups = nlevels(g[ok]), statistic = tab[1, "F value"], df = sprintf("%s, %s", tab[1, "Df"], tab[2, "Df"]), p = tab[1, "Pr(>F)"], effect = "eta_squared", effect_value = eta2, significant = tab[1, "Pr(>F)"] < .05) }
  }
  list(reliability = reliability, alpha_deleted = alpha_deleted, criterion = criterion, known_group = known, notes = notes)
}

choose_n_factors <- function(items, configured) {
  if (!identical(tolower(as.character(configured)), "auto")) return(max(1L, as.integer(configured)))
  # 因子数默认改用平行分析（psych::fa.parallel）取代 Kaiser 特征值>1 经验规则；
  # 固定局部种子并在结束后恢复随机数状态，保证同一配置重复运行结论一致。
  had_seed <- exists(".Random.seed", .GlobalEnv, inherits = FALSE)
  if (had_seed) keep_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  set.seed(1899L)
  pa <- tryCatch(psych::fa.parallel(items, fa = "fa", n.iter = 100, plot = FALSE), error = function(e) NULL)
  if (had_seed) assign(".Random.seed", keep_seed, envir = .GlobalEnv) else rm(".Random.seed", envir = .GlobalEnv)
  k <- if (!is.null(pa) && is.finite(suppressWarnings(as.numeric(pa$nfact)))) max(1L, as.integer(pa$nfact)) else
    max(1L, sum(eigen(stats::cor(items), symmetric = TRUE, only.values = TRUE)$values > 1))
  cat(sprintf("平行分析建议因子数=%d%s\n", k, if (is.null(pa)) "（平行分析失败，退回 Kaiser 特征值>1）" else ""))
  k
}

run_efa_iterative <- function(items, cfg, out_dir) {
  current <- items; history <- data.frame(iteration = integer(), item = character(), reason = character())
  if (ncol(current) < 3L) stopf("Fewer than three items remain for EFA.")
  kmo <- psych::KMO(stats::cor(current)); bart <- psych::cortest.bartlett(stats::cor(current), n = nrow(current))
  diagnostics <- data.frame(KMO = kmo$MSA, KMO_pass_gt_60 = kmo$MSA > .60, Bartlett_chisq = bart$chisq, Bartlett_df = bart$df, Bartlett_p = bart$p.value, Bartlett_pass = bart$p.value < .05)
  # 适切性门槛降级为警告：不再中止分析，完整报告照常输出，解读因子解时需谨慎。
  if (is.na(kmo$MSA) || !(kmo$MSA > .60)) warning(sprintf("KMO=%.2f 低于 .60，样本适切性偏弱，解读因子解需谨慎。", kmo$MSA), call. = FALSE, immediate. = TRUE)
  if (is.na(bart$p.value) || !(bart$p.value < .05)) warning(sprintf("Bartlett 球形检验不显著（p=%.3g），变量间共享方差偏弱，解读因子解需谨慎。", bart$p.value), call. = FALSE, immediate. = TRUE)
  # 教学默认改为“只标注不删题”：以下删除标准照常计算并输出建议删除清单（表+日志），
  # 但全部题目保留进入后续信度/EFA/CFA，不再把删题后的题目集写回；是否删题由研究者结合理论决定。
  nf <- min(choose_n_factors(current, cfg$analysis$n_factors), max(1L, floor(ncol(current) / 3L)))
  efa <- psych::fa(current, nfactors = nf, rotate = cfg$analysis$rotation, fm = "minres", warnings = FALSE)
  L <- as.matrix(efa$loadings[]); absL <- abs(L)
  # 单因子解（nf = 1）必须单独处理：apply 与 vapply 在"每行只返回 1 个值"时都会退化成向量，
  # t() 之后变成 1×n 矩阵，于是 ordered[, 1] 取到的是"第一题"而不是"每题的主载荷"
  # （primary_loading 变成常数）、ordered[, 2] 取到"第二题"（干净数据也被误判 cross_loading），
  # 且 names(main) 只剩一个名字，使"主载荷 < .40"的判定失效（真正的低载荷题反而漏报）。
  # nf = 1 时不存在交叉载荷，主载荷就是该因子上的载荷，直接取即可；nf ≥ 2 才需要排序矩阵。
  if (ncol(absL) == 1L) {
    main <- stats::setNames(as.numeric(absL[, 1L]), rownames(L)); second <- rep(0, nrow(absL))
  } else {
    ordered <- t(apply(absL, 1L, sort, decreasing = TRUE))
    main <- ordered[, 1L]; second <- ordered[, 2L]
  }
  comm <- efa$communality; owner <- colnames(L)[max.col(absL, ties.method = "first")]; counts <- table(owner)
  remove_low <- names(main)[main < .40]; remove_cross <- names(main)[second > .30 & (main - second) < .20]; remove_comm <- names(comm)[comm < .20]
  weak_factor <- names(counts)[counts < 3L]; remove_factor <- names(owner)[owner %in% weak_factor]
  reasons <- list(`main_loading_lt_.40` = remove_low, `cross_loading` = remove_cross, `communality_lt_.20` = remove_comm, `factor_fewer_than_3_items` = remove_factor)
  to_remove <- unique(unlist(reasons, use.names = FALSE))
  for (reason in names(reasons)) if (length(reasons[[reason]])) history <- rbind(history, data.frame(iteration = 1L, item = reasons[[reason]], reason = reason, stringsAsFactors = FALSE))
  if (length(to_remove)) cat("建议删除题目（仅标注，未自动删除，是否删题由研究者结合理论决定）：", paste(to_remove, collapse = ", "), "\n") else
    cat("未发现达到删除标准的题目（主载荷<.40 / 交叉载荷 / 共同度<.20 / 因子少于3题）。\n")
  loadings <- data.frame(item = rownames(L), L, communality = comm, primary_factor = owner, primary_loading = main, suggest_delete = rownames(L) %in% to_remove, stringsAsFactors = FALSE)
  # 单因子解的 Vaccounted 没有 Cumulative Var 行，需回退为与 Proportion Var 相同（累积=自身），避免门槛降级后仍无报告。
  vacc <- efa$Vaccounted
  variance <- data.frame(factor = colnames(L), SS_loading = vacc["SS loadings", ], proportion = vacc["Proportion Var", ],
                         cumulative = if ("Cumulative Var" %in% rownames(vacc)) vacc["Cumulative Var", ] else vacc["Proportion Var", ])
  list(items = current, efa = efa, diagnostics = diagnostics, loadings = loadings, variance = variance, history = history,
       mapping = data.frame(item = rownames(L), dimension = owner), eigen = eigen(stats::cor(current), symmetric = TRUE, only.values = TRUE)$values)
}

make_cfa_syntax <- function(mapping) {
  pieces <- lapply(split(mapping$item, mapping$dimension), function(items) paste(items, collapse = " + "))
  paste(sprintf("%s =~ %s", names(pieces), pieces), collapse = "\n")
}

run_cfa <- function(items, mapping, out_dir, ordered_mode = "auto") {
  if (is.null(mapping) || !nrow(mapping)) return(NULL)
  dims <- split(mapping$item, mapping$dimension); if (any(lengths(dims) < 3L)) stopf("CFA requires at least three items per factor.")
  # ── 语法安全化 ──────────────────────────────────────────────────────────────
  # 题目列名/维度名常含空格、`-`、顿号、括号、前导数字（如 "1. 我常感到紧张"）。
  # lavaan 模型语法由字符串解析：非语法名会让 CFA 整条路线直接失败。
  # 因此在内部改用 ASCII 安全名（Item1…/F1…）建语法，输出表再按原名回显。
  orig_items <- as.character(mapping$item); orig_dims <- as.character(mapping$dimension)
  safe_item <- paste0("Item", seq_along(orig_items))
  dim_levels <- unique(orig_dims)
  safe_dim <- paste0("F", seq_along(dim_levels))
  map_tab <- data.frame(item = orig_items, dimension = orig_dims,
                        safe_item = safe_item, safe_dimension = safe_dim[match(orig_dims, dim_levels)],
                        stringsAsFactors = FALSE)
  items_safe <- items[orig_items]; names(items_safe) <- safe_item
  mapping_safe <- data.frame(item = map_tab$safe_item, dimension = map_tab$safe_dimension, stringsAsFactors = FALSE)
  # ordered 口径由配置 analysis.ordered 决定：true=全部按有序类别+WLSMV；false=按连续变量+ML；auto=所有题目非缺失唯一值≤10 时按有序。
  use_ordered <- if (ordered_mode == "true") TRUE else if (ordered_mode == "false") FALSE else
    all(vapply(items_safe, function(z) length(unique(z[!is.na(z)])) <= 10L, logical(1)))
  estimator <- if (use_ordered) "WLSMV" else "ML"
  .badnames <- orig_items[!grepl("^[A-Za-z][A-Za-z0-9._]*$", orig_items)]
  if (length(.badnames)) cat(sprintf("列名说明：以下题目名不是合法的 R 变量名，已在 CFA 语法内部改用安全名（Item1…）计算，输出表仍按原题名显示：%s\n", paste(unique(.badnames), collapse = "、")))
  syntax <- make_cfa_syntax(mapping_safe)
  fit <- lavaan::cfa(syntax, data = items_safe, ordered = if (use_ordered) mapping_safe$item else NULL, estimator = estimator, std.lv = TRUE)
  cat(sprintf("CFA 估计口径：analysis.ordered=%s（%s），estimator=%s。\n", ordered_mode, if (use_ordered) "题目按有序类别处理" else "题目按连续变量处理", estimator))
  if (!lavaan::lavInspect(fit, "converged")) stopf("CFA did not converge.")
  # 把安全名翻回原始题目名/维度名，供全部输出表使用
  to_orig_item <- function(x) { i <- match(x, map_tab$safe_item); ifelse(is.na(i), x, map_tab$item[i]) }
  to_orig_dim <- function(x) { i <- match(x, map_tab$safe_dimension); ifelse(is.na(i), x, map_tab$dimension[i]) }
  fitm <- lavaan::fitMeasures(fit, c("chisq", "df", "pvalue", "cfi", "tli", "rmsea", "srmr", "aic", "bic"))
  fit_table <- data.frame(chisq = fitm[["chisq"]], df = fitm[["df"]], chisq_df = fitm[["chisq"]] / fitm[["df"]], p = fitm[["pvalue"]], CFI = fitm[["cfi"]], TLI = fitm[["tli"]], RMSEA = fitm[["rmsea"]], SRMR = fitm[["srmr"]], AIC = fitm[["aic"]], BIC = fitm[["bic"]], chisq_df_pass_lt_5 = fitm[["chisq"]] / fitm[["df"]] < 5, CFI_pass_gt_90 = fitm[["cfi"]] > .90, TLI_pass_gt_90 = fitm[["tli"]] > .90, RMSEA_pass_lt_08 = fitm[["rmsea"]] < .08, SRMR_pass_lt_08 = fitm[["srmr"]] < .08)
  pe <- lavaan::parameterEstimates(fit, standardized = TRUE); loads <- pe[pe$op == "=~", c("lhs", "rhs", "est", "se", "z", "pvalue", "std.all")]
  names(loads) <- c("factor", "item", "loading", "SE", "z", "p", "standardized_loading")
  conv <- do.call(rbind, lapply(split(loads, loads$factor), function(z) { lam <- z$standardized_loading; cr <- sum(lam)^2 / (sum(lam)^2 + sum(1 - lam^2)); ave <- mean(lam^2); data.frame(factor = z$factor[1], min_loading = min(lam), all_loadings_gt_50 = all(lam > .50), CR = cr, CR_pass_gt_70 = cr > .70, AVE = ave, AVE_pass_gt_50 = ave > .50) }))
  corrs <- pe[pe$op == "~~" & pe$lhs != pe$rhs & pe$lhs %in% mapping_safe$dimension & pe$rhs %in% mapping_safe$dimension, c("lhs", "rhs", "std.all")]
  names(corrs) <- c("factor1", "factor2", "correlation")
  # 安全名 → 原始题目名/维度名（输出表与后续报告全部使用原名）
  loads$factor <- to_orig_dim(loads$factor); loads$item <- to_orig_item(loads$item)
  conv$factor <- to_orig_dim(conv$factor)
  corrs$factor1 <- to_orig_dim(corrs$factor1); corrs$factor2 <- to_orig_dim(corrs$factor2)
  fl <- diag(sqrt(conv$AVE)); rownames(fl) <- colnames(fl) <- conv$factor
  for (i in seq_len(nrow(corrs))) { fl[corrs$factor1[i], corrs$factor2[i]] <- corrs$correlation[i]; fl[corrs$factor2[i], corrs$factor1[i]] <- corrs$correlation[i] }
  discr <- data.frame(factor1 = corrs$factor1, factor2 = corrs$factor2, correlation = corrs$correlation, correlation_lt_85 = abs(corrs$correlation) < .85,
                      sqrt_AVE_exceeds_correlation = mapply(function(a,b,r) sqrt(conv$AVE[conv$factor == a]) > abs(r) && sqrt(conv$AVE[conv$factor == b]) > abs(r), corrs$factor1, corrs$factor2, corrs$correlation))
  # Heywood/不合规解检查：标准化载荷|λ|>1 或方差估计（op=="~~" 且 lhs==rhs）为负 → 控制台醒目中文告警（不中止），并在载荷表加 heywood_warning 布尔列。
  # 注意：pe 里的题目名是建模时用的安全名，而上面的 loads$item 已翻回原始题名，故这里必须先翻译再比较，
  # 否则"方差估计为负"这一半的判定会永远为 FALSE（静默漏报）。
  neg_var <- !is.na(pe$est) & pe$op == "~~" & pe$lhs == pe$rhs & pe$est < 0
  hey_items <- to_orig_item(unique(c(pe$lhs[neg_var], pe$rhs[neg_var])))
  loads$heywood_warning <- abs(loads$standardized_loading) > 1 | loads$item %in% hey_items
  if (any(loads$heywood_warning))
    cat("\n*** Heywood 告警：以下题目的标准化载荷绝对值>1 或对应方差估计为负：", paste(loads$item[loads$heywood_warning], collapse = ", "),
        "。该解属不合规解（improper solution），载荷/信效度结果不可直接报告；请检查模型设定、每因子题数与样本量。分析不中止，其余输出照常生成。***\n\n")
  # 修正指数：按 mi 降序取前 20 行；计算失败或无更多可放宽参数时写出带表头的空表并提示。
  # 注：lavaan 0.6-21 的 modindices 无 minimum.n 参数，等价过滤用 minimum.value = 0（保留全部 mi>0 的候选再排序）。
  mi <- tryCatch(lavaan::modindices(fit, sort. = TRUE, minimum.value = 0), error = function(e) NULL)
  if (is.null(mi)) { cat("提示：修正指数计算失败，06_cfa_modification_indices.csv 将写出空表。\n")
    mi <- data.frame(lhs = character(), op = character(), rhs = character(), mi = numeric(), epc = numeric(), sepc.all = numeric()) }
  else mi <- utils::head(as.data.frame(mi), 20L)
  if (!nrow(mi)) cat("提示：模型无更多可放宽的参数，修正指数为空（仍写出带表头的空表）。\n")
  # 修正指数表的 lhs/rhs 同样由安全名翻回原名（维度名与题目名混在同一列，两者都试一次）
  if (nrow(mi)) {
    for (cc in intersect(c("lhs", "rhs"), names(mi))) {
      v <- as.character(mi[[cc]])
      v <- to_orig_dim(v); v <- to_orig_item(v)
      mi[[cc]] <- v
    }
  }
  list(fit = fit, syntax = syntax, fit_table = fit_table, loadings = loads, convergent = conv, correlations = corrs, fornell_larcker = fl, discriminant = discr,
       modindices = mi, estimator_note = sprintf("analysis.ordered=%s（%s），estimator=%s", ordered_mode, if (use_ordered) "题目按有序类别" else "题目按连续变量", estimator))
}

plot_efa <- function(efa_result, out_dir) {
  save_png(file.path(out_dir, "efa_scree_plot.png"), function() { plot(efa_result$eigen, type = "b", pch = 19, xlab = "Component number", ylab = "Eigenvalue", main = "EFA scree plot"); abline(h = 1, lty = 2, col = "firebrick") })
  fac_cols <- grep("^MR|^PA|^ML|^Factor", names(efa_result$loadings), value = TRUE)
  long <- do.call(rbind, lapply(fac_cols, function(fc) data.frame(item = efa_result$loadings$item, factor = fc, loading = efa_result$loadings[[fc]], stringsAsFactors = FALSE)))
  p <- ggplot2::ggplot(long, ggplot2::aes(factor, item, fill = loading)) + ggplot2::geom_tile(color = "white") + ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", loading)), size = 3) + ggplot2::scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0) + ggplot2::labs(title = "Rotated factor loading heatmap", x = NULL, y = NULL) + ggplot2::theme_minimal(base_size = 11)
  save_png(file.path(out_dir, "efa_loading_heatmap.png"), function() print(p), 8, max(4, .35 * nrow(efa_result$loadings) + 2))
}

plot_cfa <- function(cfa, out_dir) {
  # semPlot 仅用于绘制路径图，属可选依赖（不在 run_ctt_analysis.ps1 的必需包清单里，安装失败不阻塞 CFA）。
  if (!requireNamespace("semPlot", quietly = TRUE)) {
    cat("\n********************************************************************************\n")
    cat("提示：未安装 semPlot 包，本次不生成 CFA 路径图（cfa_path_diagram.png）。\n")
    cat("拟合指标、因子载荷、信效度等其余 CFA 结果均不受影响；安装后重跑即可补出路径图。\n")
    cat("安装命令：Rscript -e \"install.packages('semPlot')\"\n")
    cat("********************************************************************************\n\n")
    return("未安装 semPlot，未生成 CFA 路径图（其余 CFA 结果不受影响）。")
  }
  save_png(file.path(out_dir, "cfa_path_diagram.png"), function() semPlot::semPaths(cfa$fit, what = "std", whatLabels = "std", layout = "tree", residuals = FALSE, intercepts = FALSE, edge.label.cex = .7), 10, 7)
  NULL
}

# Mapping for the simulate demo CFA route: simulate_ctt_data loads items 1-5 on F1, 6-10 on F2, 11-15 on F3.
simulation_truth_mapping <- function(item_names) {
  k <- 5L
  data.frame(item = item_names, dimension = paste0("F", (seq_along(item_names) - 1L) %/% k + 1L))
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

run_ctt_pipeline <- function(config_path_args = commandArgs(trailingOnly = TRUE)) {
  loaded <- load_ctt_config(config_path_args); cfg <- normalise_ctt_config(loaded$config, loaded$base_dir); out_dir <- make_result_dir(cfg)
  file.copy(loaded$path, file.path(out_dir, paste0("config_snapshot.", tools::file_ext(loaded$path))), overwrite = TRUE)
  route_zh <- switch(cfg$analysis$goal,
                     quality = "量表质量检查（清洗+项目分析+信度+效度证据；不做因子分析）",
                     efa = "质量 + 探索性因子分析 EFA（数据驱动找结构）",
                     cfa = "质量 + 验证性因子分析 CFA（验证预设结构）")
  cat("分析路线：", route_zh, "\n")
  cat("统计核心包：psych", as.character(utils::packageVersion("psych")), "（项目分析/信度/EFA）、lavaan", as.character(utils::packageVersion("lavaan")), "（CFA）\n\n")
  if (cfg$input$mode == "simulate") {
    raw <- simulate_ctt_data(cfg$simulation); sim_path <- file.path(out_dir, "simulated_ctt_data.csv"); write_csv_utf8(raw, sim_path)
  } else raw <- read_ctt_data(cfg$input$path)
  # CFA 路线：题目集合由对照表决定，避免 auto 识别混入注意力题/人口学列。
  if (cfg$analysis$goal == "cfa" && cfg$input$mode == "file") cfg$input$item_columns <- read_mapping(cfg$analysis$cfa_mapping)$item
  prepared <- prepare_ctt_items(raw, cfg); cleaned <- clean_ctt_data(raw, prepared$names, cfg)
  write_csv_utf8(cleaned$summary, file.path(out_dir, "01_cleaning_summary.csv"))
  # 01_cleaned_items.csv / 01_case_cleaning_audit.csv 带被试 ID 首列便于核对：优先用配置的 input.id_column（须存在于原始数据），
  # 否则用原始行号列 participant（与 audit 的行号一致）。写出的只是副本，cleaned$items 本身保持纯题目列，下游 α/EFA/CFA 不受影响。
  id_nm <- cfg$input$id_column
  if (!is.null(id_nm) && nzchar(id_nm) && !id_nm %in% names(raw)) { cat("提示：配置的 input.id_column（", id_nm, "）在数据中不存在，改用原始行号 participant 作为 ID 列。\n", sep = ""); id_nm <- NULL }
  if (is.null(id_nm) || !nzchar(id_nm)) id_nm <- NULL
  kept_rows <- which(!cleaned$audit$removed)
  items_export <- if (!is.null(id_nm)) { z <- data.frame(cleaned$metadata[[id_nm]], cleaned$items, check.names = FALSE); names(z)[1] <- id_nm; z } else cbind(participant = kept_rows, cleaned$items)
  audit_export <- cleaned$audit
  if (!is.null(id_nm)) { z <- data.frame(raw[[id_nm]], cleaned$audit, check.names = FALSE); names(z)[1] <- if (id_nm %in% names(cleaned$audit)) paste0(id_nm, "_id") else id_nm; audit_export <- z }
  write_csv_utf8(audit_export, file.path(out_dir, "01_case_cleaning_audit.csv")); write_csv_utf8(items_export, file.path(out_dir, "01_cleaned_items.csv"))
  item <- run_item_analysis(cleaned$items); write_csv_utf8(item, file.path(out_dir, "02_item_analysis.csv"))
  # EFA and CFA are mutually exclusive routes. EFA first (when chosen) because its retained structure
  # defines provisional dimensions for factor-level reliability; CFA uses only a user mapping.
  efa <- NULL; mapping <- NULL; items_for_reliability <- cleaned$items
  if (cfg$analysis$goal == "efa") {
    efa <- run_efa_iterative(cleaned$items, cfg, out_dir); write_csv_utf8(efa$diagnostics, file.path(out_dir, "04_efa_diagnostics.csv")); write_csv_utf8(efa$history, file.path(out_dir, "04_efa_deletion_history.csv")); write_csv_utf8(efa$loadings, file.path(out_dir, "04_efa_rotated_loadings.csv")); write_csv_utf8(efa$variance, file.path(out_dir, "04_efa_variance.csv")); write_csv_utf8(efa$mapping, file.path(out_dir, "04_efa_item_dimension_mapping.csv")); plot_efa(efa, out_dir)
    mapping <- efa$mapping; items_for_reliability <- efa$items
  } else if (cfg$analysis$goal == "cfa") {
    mapping <- if (cfg$input$mode == "file") read_mapping(cfg$analysis$cfa_mapping, names(cleaned$items)) else simulation_truth_mapping(names(cleaned$items))
    write_csv_utf8(mapping, file.path(out_dir, "05_cfa_item_dimension_mapping.csv"))
  }
  # 分表来源标注：EFA 路线的分量表来自同一批数据的 EFA（α 偏乐观）；CFA 路线为用户对照表映射。
  reliability <- run_reliability_validity(items_for_reliability, cleaned$metadata, cfg, mapping,
                                          mapping_source = if (cfg$analysis$goal == "efa") "EFA-derived (optimistic)" else if (cfg$analysis$goal == "cfa") "CFA-mapping" else NULL); write_csv_utf8(reliability$reliability, file.path(out_dir, "03_reliability.csv")); write_csv_utf8(reliability$alpha_deleted, file.path(out_dir, "03_alpha_if_deleted.csv")); write_csv_utf8(reliability$criterion, file.path(out_dir, "03_criterion_validity.csv")); write_csv_utf8(reliability$known_group, file.path(out_dir, "03_known_group_validity.csv"))
  if (cfg$analysis$goal == "efa") cat("提示：分量表维度来自同一批数据的 EFA，其 α 偏乐观，应在独立样本验证后再报告。\n")
  if (length(reliability$notes)) cat("提示：", paste(reliability$notes, collapse = "\n"), "\n", sep = "")
  cfa <- if (cfg$analysis$goal == "cfa" && !is.null(mapping)) run_cfa(cleaned$items, mapping, out_dir, cfg$analysis$ordered) else NULL
  path_note <- switch(cfg$analysis$goal,
                      quality = "Route was quality-only: no factor analysis was run.",
                      efa = "Route was EFA-only: CFA was not run on the same data (EFA-derived structures need an independent sample for validation).",
                      "CFA was not run.")
  if (!is.null(cfa)) { writeLines(cfa$syntax, file.path(out_dir, "05_cfa_model_syntax.lav"), useBytes = TRUE); write_csv_utf8(cfa$fit_table, file.path(out_dir, "05_cfa_fit.csv")); write_csv_utf8(cfa$loadings, file.path(out_dir, "05_cfa_loadings.csv")); write_csv_utf8(cfa$convergent, file.path(out_dir, "05_cfa_convergent_validity.csv")); write_csv_utf8(cfa$correlations, file.path(out_dir, "05_cfa_factor_correlations.csv")); write_csv_utf8(as.data.frame(cfa$fornell_larcker), file.path(out_dir, "05_fornell_larcker.csv")); write_csv_utf8(cfa$discriminant, file.path(out_dir, "05_cfa_discriminant_validity.csv")); write_csv_utf8(cfa$modindices, file.path(out_dir, "06_cfa_modification_indices.csv")); path_note <- plot_cfa(cfa, out_dir) %||% "CFA path diagram generated." }
  # 运行清单只记录真实用到的包（psych/lavaan/GPArotation 等）；CTT 包从未被调用，不得强制要求安装。
  core_pkgs <- c("psych", "lavaan", "GPArotation")
  writeLines(c("Psychostat CTT run log", paste("Run:", format(Sys.time(), "%FT%T%z")), paste("Route:", cfg$analysis$goal), paste("R:", R.version.string), paste("Packages:", paste(sprintf("%s %s", core_pkgs, vapply(core_pkgs, function(p) as.character(utils::packageVersion(p)), character(1))), collapse = "; ")),
               if (!is.null(cfa)) paste("CFA estimation:", cfa$estimator_note), paste("CFA path diagram:", path_note),
               c(if (cfg$analysis$goal == "efa") "Reliability note: EFA 路线的分量表维度来自同一批数据的 EFA，其 α 偏乐观，应在独立样本验证后再报告。" else NULL, sprintf("Reliability note: %s", reliability$notes)),
               "Interpretation warning: 本工具只标注建议删除项，不自动删除；是否删题由研究者结合理论决定。Automatic item-retention flags are decision aids; review content validity. EFA and CFA are separate routes: validating an EFA-derived structure requires an independent sample."), file.path(out_dir, "run_log.txt"), useBytes = TRUE)
  write_run_manifest(out_dir, cfg, c(core_pkgs, "ggplot2", "readxl", "haven", "yaml", "jsonlite", "MASS"),
                     cfg$analysis$goal, loaded$path)
  cat("RESULT_DIR_UTF8_HEX=", paste(sprintf("%02X", as.integer(charToRaw(enc2utf8(normalizePath(out_dir))))), collapse = ""), "\n", sep = "")
}

if (sys.nframe() == 0L) run_ctt_pipeline()
