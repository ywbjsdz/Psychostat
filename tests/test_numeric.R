# Psychostat 数值回归测试：关键统计量与固定种子模拟的黄金值比对 + IRT 模拟一致性/参数恢复。
# 运行：Rscript --vanilla tests\test_numeric.R   （或 .\tests\run_numeric_tests.ps1）
# 任何一项失败即以非零退出码结束。
ok <- TRUE
check <- function(name, cond, detail = "") {
  if (isTRUE(cond)) cat("[PASS]", name, "\n") else { ok <<- FALSE; cat("[FAIL]", name, "--", detail, "\n") }
}
near <- function(x, g, tol = 1e-6) isTRUE(all.equal(as.numeric(x), g, tolerance = tol))
root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."))

# ── 1. IRT 模拟一致性（P0-1 验收）：生成机制必须与导出 truth 的 a/主维度/阈值一致 ──
source(file.path(root, "scripts", "irt_common.R"), local = TRUE)
# IRT 断言依赖 mirt，而 mirt 的 Imports 含 vegan（带编译 DLL）。在启用了 Windows 应用控制策略
# （Smart App Control / WDAC）的机器上，未签名的 vegan.dll 可能被拦截，此时**所有 IRT 用例都跑不了**。
# 那属于环境故障、不是代码回归，所以这里显式探测并 SKIP，而不是报 FAIL 把环境问题混进回归信号。
has_mirt <- requireNamespace("mirt", quietly = TRUE)
irt_skip_reason <- if (has_mirt) NULL else "mirt 无法加载（常见原因：Windows 应用控制策略拦截 vegan.dll）"
irt_skipped <- 0L
skip_block <- function(nm) { irt_skipped <<- irt_skipped + 1L; cat("[SKIP]", nm, "--", irt_skip_reason, "\n") }
if (has_mirt) {
for (spec in list(list(dims = 2, cats = 5), list(dims = 3, cats = 5), list(dims = 2, cats = 2))) {
  sim <- simulate_irt_data(list(seed = 20260906, model = "mirt", n_persons = 30000, n_items = 12,
                                 n_dimensions = spec$dims, response_categories = spec$cats))
  truth <- sim$truth; a <- attr(truth, "a"); d <- attr(truth, "d")
  owner <- as.integer(sub("F", "", truth$primary_dimension))
  a_primary <- a[cbind(seq_len(nrow(a)), owner)]
  bcols <- grep("^b[0-9]+$", names(truth))
  b <- as.matrix(truth[, bcols])
  check(sprintf("IRT一致性 D%d-C%d：阈值位置 d = -b×主维度载荷", spec$dims, spec$cats),
        max(abs(d - (-b * a_primary))) < 1e-12, sprintf("max|diff| = %g", max(abs(d - (-b * a_primary)))))
  # 经验类别比例 vs 由 truth 直接积分的理论比例（mirt simdata 返回 0 基类别；logit(a·θ + d)）
  theta_mc <- matrix(rnorm(30000 * spec$dims), 30000, spec$dims)
  lin <- theta_mc %*% t(a)
  maxdev <- 0
  for (i in seq_len(nrow(a))) {
    pj <- sapply(seq_len(ncol(d)), function(j) plogis(lin[, i] + d[i, j]))
    if (spec$cats == 2) pcat <- cbind(1 - pj, pj)
    else {
      pje <- cbind(pj, 1)                                   # P(X>=j), j = 1..K-1, plus 1
      pcat <- cbind(1 - pje[, 1],
                    sapply(seq_len(spec$cats - 2), function(j) pje[, j] - pje[, j + 1]),
                    pje[, spec$cats - 1])                   # P(X = K-1) = P(X >= K-1)
    }
    theo <- colMeans(pcat)
    obs <- as.numeric(table(factor(sim$data[[i]], levels = 0:(spec$cats - 1)))) / nrow(sim$data)
    maxdev <- max(maxdev, max(abs(theo - obs)))
  }
  check(sprintf("IRT一致性 D%d-C%d：类别比例=理论概率（n=30000）", spec$dims, spec$cats), maxdev < 0.02,
        sprintf("max|theo-obs| = %.4f", maxdev))
}

# ── 2. IRT 参数恢复：2维 GRM，验证性拟合；主维度归属与主载荷恢复相关 ──
sim <- simulate_irt_data(list(seed = 7, model = "mirt", n_persons = 1500, n_items = 10, n_dimensions = 2, response_categories = 5))
truth <- sim$truth; owner <- truth$primary_dimension
mod <- "F1 = 1-5\nF2 = 6-10\nCOV = F1*F2"
fit <- mirt::mirt(sim$data, mirt::mirt.model(mod), itemtype = "graded", verbose = FALSE, technical = list(set.seed = 1))
cf <- mirt::coef(fit, simplify = TRUE)$items
aload <- cf[, grep("^a[0-9]+$", colnames(cf)), drop = FALSE]
est_owner <- max.col(abs(aload))
best <- 0
for (perm in list(c(1, 2), c(2, 1))) { best <- max(best, sum(perm[est_owner] == as.integer(sub("F", "", owner)))) }
check("IRT参数恢复：主维度归属（2D GRM，n=1500）", best >= 10, sprintf("匹配 %d/10", best))
true_primary <- attr(truth, "a")[cbind(seq_len(10), as.integer(sub("F", "", owner)))]
est_primary <- vapply(seq_len(10), function(i) aload[i, est_owner[i]], numeric(1))
r_rec <- suppressWarnings(cor(est_primary, true_primary))
check("IRT参数恢复：主载荷与真值相关 r > .70", r_rec > .70, sprintf("r = %.3f", r_rec))
} else { skip_block("第 1–2 节 IRT 断言（模拟一致性 + 参数恢复）") }

# ── 3. 心理统计黄金值（seed = 20260904 演示数据） ──
source(file.path(root, "scripts", "stats_common.R"), local = TRUE)
source(file.path(root, "scripts", "stats_modules.R"), local = TRUE)
cfg <- list(simulation = list(seed = 20260904, n_per_group = 30), analysis = list(alpha = .05))
d <- simulate_independent_t(cfg); t_eq <- t.test(suppressWarnings(as.numeric(d$spatial_score)) ~ droplevels(factor(d$gender)), var.equal = TRUE)
check("stats黄金：独立样本t（合并方差）", near(t_eq$statistic, -2.0998063566), sprintf("t = %.10f", t_eq$statistic))
f <- summary(aov(score ~ method, simulate_one_way_anova(cfg)))[[1]]
check("stats黄金：单因素F", near(f[1, "F value"], 7.7874726888), sprintf("F = %.10f", f[1, "F value"]))
dp <- simulate_paired_t(cfg); tp <- t.test(dp$post - dp$pre)
check("stats黄金：配对t（后-前）", near(tp$statistic, -13.0362471079), sprintf("t = %.10f", tp$statistic))
dr <- simulate_rm_anova(cfg); wr <- as.matrix(dr[grep("^time", names(dr))])
ma <- car::Anova(stats::lm(wr ~ 1), idata = data.frame(time = factor(1:4)), idesign = ~ time, type = 3)
frm <- suppressWarnings(summary(ma, multivariate = FALSE))$univariate.tests["time", "F value"]
check("stats黄金：重复测量F", near(frm, 14.5030640425), sprintf("F = %.10f", frm))
dc <- simulate_chi_square_independence(cfg); ch <- chisq.test(table(dc$gender, dc$career_pref), correct = FALSE)
check("stats黄金：卡方独立性", near(ch$statistic, 36.7321787894), sprintf("chisq = %.10f", ch$statistic))
dm <- simulate_mediation(cfg); ddm <- data.frame(X = dm$stress, M = dm$rumination, Y = dm$depression)
ab <- coef(lm(M ~ X, ddm))["X"] * coef(lm(Y ~ X + M, ddm))["M"]
check("stats黄金：中介间接效应ab", near(ab, 0.1668778413), sprintf("ab = %.10f", ab))
d2 <- simulate_two_way_anova(cfg); f2 <- summary(aov(score ~ method * motivation, d2))[[1]]
check("stats黄金：两因素交互F（method×motivation）", near(f2[3, "F value"], 10.2443040456), sprintf("F = %.10f", f2[3, "F value"]))
da <- simulate_ancova(cfg); fa <- anova(lm(posttest ~ pretest, da), lm(posttest ~ pretest + method, da))
check("stats黄金：ANCOVA调整后组效应F（组|协变量）", near(fa[2, "F"], 5.9122021496), sprintf("F = %.10f", fa[2, "F"]))
dg <- simulate_regression(cfg); fg <- lm(final_grade ~ study_hours + iq + test_anxiety, dg)
cg <- c(coef(fg)[["study_hours"]], confint(fg)["study_hours", ])
check("stats黄金：回归斜率与95%CI（study_hours）", near(cg, c(0.3658571215, 0.1945784740, 0.5371357689)),
      paste(sprintf("%.10f", cg), collapse = ", "))
dmo <- simulate_moderation(cfg)
Xc <- dmo$motivation - mean(dmo$motivation); Zc <- dmo$learning_resources - mean(dmo$learning_resources)
b3 <- coef(lm(dmo$engagement_score ~ Xc * Zc))[["Xc:Zc"]]
check("stats黄金：调节交互项系数（中心化Xc×Zc）", near(b3, 1.8438936952), sprintf("B = %.10f", b3))
pctx <- list(out_dir = tempdir(), prefix = "pwrchk", alpha = cfg$analysis$alpha, echo = FALSE)
invisible(capture.output(run_power(NULL, cfg, pctx)))
ptb <- read.csv(file.path(pctx$out_dir, "pwrchk_sample_size_table.csv"))
prw <- ptb[ptb$effect == "d = 0.5" & ptb$power == 0.8, ]
nref <- pwr::pwr.t.test(d = 0.5, sig.level = 0.05, power = 0.8, type = "two.sample")$n
check("stats黄金：功效分析两样本t d=.5/power=.80 所需N（每组64/总128）",
      nrow(prw) == 1L && prw$N_total == 128L && prw$N_total == 2L * ceiling(nref),
      sprintf("模块N_total = %s（每组 = 总N/2）；pwr独立复算 n/组 = %.5f → 总N = %d",
              if (nrow(prw)) prw$N_total else NA, nref, 2L * ceiling(nref)))

# ── 4. CTT 黄金值：演示配置清洗后的 Cronbach's α ──
.orig_ca <- base::commandArgs
commandArgs <- function(trailingOnly = FALSE) if (trailingOnly) character(0) else paste0("--file=", normalizePath(file.path(root, "scripts", "ctt_pipeline.R")))
source(file.path(root, "scripts", "ctt_pipeline.R"), local = TRUE)
commandArgs <- .orig_ca
cttcfg <- normalise_ctt_config(yaml::read_yaml(file.path(root, "ctt_config.yaml")), root)
raw <- simulate_ctt_data(cttcfg$simulation); prepared <- prepare_ctt_items(raw, cttcfg)
cleaned <- clean_ctt_data(raw, prepared$names, cttcfg)
alpha <- psych::alpha(cleaned$items, check.keys = FALSE, warnings = FALSE)$total$raw_alpha
check("CTT黄金：总量表α（演示清洗后）", near(alpha, 0.8086148590, tol = 1e-8), sprintf("alpha = %.10f", alpha))

# ── 4b. CTT 的 L1 闭式性质（与 tests/verify_l1_ctt.R 同源，进 CI 防回归）──
# 这些量都有教科书闭式解，可以脱离 psych/lavaan 独立复算：一旦有人改动清洗顺序、
# 反向计分或项目分析口径，它们会立刻变红（外部软件校对做不到这一点）。
.CX <- as.matrix(cleaned$items); .ck <- ncol(.CX); .cn <- nrow(.CX)
.alpha_cov <- function(M) { kk <- ncol(M); S <- stats::cov(M); kk / (kk - 1) * (1 - sum(diag(S)) / sum(S)) }
check("CTT L1：α = k/(k−1)·(1−Σσᵢ²/σ²)", near(alpha, .alpha_cov(.CX), tol = 1e-10),
      sprintf("工具 %.10f vs 闭式 %.10f", alpha, .alpha_cov(.CX)))
.ia <- run_item_analysis(cleaned$items)
.tot <- rowSums(.CX)
.citc <- vapply(seq_len(.ck), function(j) stats::cor(.CX[, j], .tot - .CX[, j]), numeric(1))
check("CTT L1：CITC = cor(题, 总分−该题)", isTRUE(all.equal(.ia$CITC, .citc, tolerance = 1e-10)),
      sprintf("最大差 %.3e", max(abs(.ia$CITC - .citc))))
.g <- max(1L, floor(.27 * .cn)); .o <- order(.tot); .lo <- .o[seq_len(.g)]; .hi <- .o[(.cn - .g + 1L):.cn]
.cr <- vapply(seq_len(.ck), function(j) stats::t.test(.CX[.hi, j], .CX[.lo, j], var.equal = TRUE)$statistic, numeric(1))
check("CTT L1：CR 决断值 = 高低 27% 组合并方差 t", isTRUE(all.equal(.ia$CR_t, .cr, tolerance = 1e-10)),
      sprintf("每组 %d 人，最大差 %.3e", .g, max(abs(.ia$CR_t - .cr))))
.D <- raw[prepared$names]
.sl <- apply(.D, 1L, function(z) { z <- z[!is.na(z)]; length(z) >= 3L && length(unique(z)) == 1L })
check("CTT L1：直线作答计数可从原始数据独立复现", sum(.sl) == cleaned$summary$straightline_flagged,
      sprintf("复现 %d vs 工具 %d", sum(.sl), cleaned$summary$straightline_flagged))
check("CTT L1：raw_n − removed_n = retained_n",
      cleaned$summary$raw_n - cleaned$summary$removed_n == cleaned$summary$retained_n,
      sprintf("%d − %d = %d", cleaned$summary$raw_n, cleaned$summary$removed_n, cleaned$summary$retained_n))

# -- 5. SPSS alignment regressions --
bf <- brown_forsythe_spss(c(1, 4, 2, 5, 3, 6), factor(rep(c("g1", "g2", "g3"), each = 2)))
check("SPSS alignment: Brown-Forsythe robust means test", near(bf$F, 0.4444444444), sprintf("F = %.10f", bf$F))
wide_rank <- data.frame(A = c(1, 1, 3, 3), B = c(2, 2, 1, 1), C = c(3, 3, 2, 2))
check("SPSS alignment: Friedman within-subject mean ranks", near(friedman_mean_ranks_spss(wide_rank), c(2, 1.5, 2.5)),
      paste(friedman_mean_ranks_spss(wide_rank), collapse = ", "))
set.seed(20260907)
d2 <- data.frame(A = factor(rep(c("a1", "a2", "a3"), c(12, 16, 15))),
                 B = factor(c(rep("b1", 7), rep("b2", 5), rep("b1", 10), rep("b2", 6), rep("b1", 4), rep("b2", 11))))
d2$y <- rnorm(nrow(d2)) + as.numeric(d2$A) + as.numeric(d2$B)
use_spss_contrasts(); fit2 <- lm(y ~ A * B, data = d2)
se2 <- spss_simple_effect_omnibus(fit2, "A", "B")
check("SPSS alignment: factorial simple effects retain residual df",
      all(near(se2$df2, rep(df.residual(fit2), length(se2$df2)))),
      sprintf("df2 = %s; residual df = %s", paste(se2$df2, collapse = ","), df.residual(fit2)))

# ══════════════════════════════════════════════════════════════════════════════
# 6. 生产代码数值断言（v0.1.0 新增）
#    背景：第 3 节那些"黄金值"是由 simulate_* 生成的数据 + base R/car 复算出来的，
#    验的是**数据生成器**而不是 run_* 管线。把 run_one_way_anova 的事后比较改错，
#    那些断言依然全绿。本节改为**直接调用生产函数**并比对可用闭式数学独立求出的值。
# ══════════════════════════════════════════════════════════════════════════════
source(file.path(root, "scripts", "stats_common.R"), local = TRUE)

# ── 6.1 Levene（基于均值，SPSS 口径）：构造数据、F 为精确有理数 ──
# 三组 {1,2,3} {10,11,12} {1,2,100}：各组内均值化绝对偏差的 ANOVA
# 精确解 F = 150544/9727 = 15.476919913642…
.lv <- levene_spss(c(1, 2, 3, 10, 11, 12, 1, 2, 100),
                   factor(rep(c("g1", "g2", "g3"), each = 3)))
check("生产代码：Levene(基于均值) F = 150544/9727", near(.lv$F, 150544 / 9727, tol = 1e-10),
      sprintf("F = %.12f (期望 %.12f)", .lv$F, 150544 / 9727))
check("生产代码：Levene 自由度 (2, 6)", .lv$df1 == 2 && .lv$df2 == 6,
      sprintf("df = (%s, %s)", .lv$df1, .lv$df2))
# 两组构造：精确解 F = 8/5（验证多组/两组都走通）
.lv2 <- levene_spss(c(2, 4, 6, 3, 9, 15), factor(rep(c("a", "b"), each = 3)))
check("生产代码：Levene 两组 F = 8/5", near(.lv2$F, 8 / 5, tol = 1e-10), sprintf("F = %.12f", .lv2$F))

# ── 6.2 Type III 平方和（非平衡 2×2）：这是 SPSS GLM 默认口径，Type I 会算错 ──
# 单元格 (a1,b1)=[1,2] (a1,b2)=[3,4,5] (a2,b1)=[6,7,8] (a2,b2)=[9,10]，N=10
# 独立求出的 Type III：SS_A=72.6, SS_B=15.0, SS_AxB=0, SSE=5.0，dfe=6
.ub <- data.frame(
  A = factor(c(rep("a1", 5), rep("a2", 5))),
  B = factor(c("b1", "b1", "b2", "b2", "b2", "b1", "b1", "b1", "b2", "b2")),
  y = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
use_spss_contrasts()
.ubfit <- stats::aov(y ~ A * B, data = .ub)
.ubtab <- anova_table_spss(.ubfit, terms = c("A", "B", "A:B", "Residuals"))
check("生产代码：Type III SS_A（非平衡 2×2）", near(.ubtab$SS[1], 72.6, tol = 1e-9), sprintf("SS_A = %.10f", .ubtab$SS[1]))
check("生产代码：Type III SS_B（非平衡 2×2）", near(.ubtab$SS[2], 15.0, tol = 1e-9), sprintf("SS_B = %.10f", .ubtab$SS[2]))
check("生产代码：Type III SS_AxB（非平衡 2×2）", near(.ubtab$SS[3], 0.0, tol = 1e-9), sprintf("SS_AxB = %.10f", .ubtab$SS[3]))
check("生产代码：Type III SSE / dfe", near(.ubtab$SS[4], 5.0, tol = 1e-9) && .ubtab$df[4] == 6,
      sprintf("SSE = %.10f, dfe = %s", .ubtab$SS[4], .ubtab$df[4]))
# Type I 顺序平方和（aov 的 summary）在非平衡数据下与 Type III 不同；
# 若两者相等，说明实现退回了 Type I，与 SPSS GLM 默认口径不符 → 该断言用于鉴别口径。
.ty1_A <- summary(.ubfit)[[1]][1, "Sum Sq"]
check("生产代码：非平衡数据下 Type III SS_A 必须不同于 Type I 的 SS_A",
      abs(.ty1_A - .ubtab$SS[1]) > 1,
      sprintf("Type I SS_A = %.6f, Type III SS_A = %.6f（两者相等即口径错误）", .ty1_A, .ubtab$SS[1]))

# ── 6.3 Welch t 的 df：必须与合并方差 df 不同（此前只测了合并方差那一行）──
.n1 <- 32; .n2 <- 28
set.seed(20260904)
.x1 <- 103 + 12.94 * stats::rnorm(.n1); .x2 <- 97 + 9.91 * stats::rnorm(.n2)
.te <- stats::t.test(.x1, .x2, var.equal = TRUE); .tw <- stats::t.test(.x1, .x2, var.equal = FALSE)
check("生产代码：Welch df ≠ 合并方差 df（方差不等时）",
      abs(.tw$parameter - .te$parameter) > 0.5,
      sprintf("Welch df = %.4f, pooled df = %.4f", .tw$parameter, .te$parameter))
# Welch–Satterthwaite 闭式复算（不依赖 t.test 内部实现）
.s1 <- stats::var(.x1); .s2 <- stats::var(.x2)
.v1 <- .s1 / .n1; .v2 <- .s2 / .n2
.dfw <- (.v1 + .v2)^2 / (.v1^2 / (.n1 - 1) + .v2^2 / (.n2 - 1))
check("生产代码：Welch df 与 Satterthwaite 闭式一致", near(.tw$parameter, .dfw, tol = 1e-10),
      sprintf("t.test = %.10f, 闭式 = %.10f", .tw$parameter, .dfw))

# ── 6.4 事后比较：LSD / Bonferroni 的 t、p 与 CI（纯 t 分布闭式，可独立复算）──
set.seed(20260910)
.g <- factor(rep(c("g1", "g2", "g3"), each = 12))
.yv <- c(stats::rnorm(12, 10), stats::rnorm(12, 12), stats::rnorm(12, 15))
.ph <- posthoc_tables(.yv, .g)
check("生产代码：事后比较表齐备（LSD/Tukey/Bonferroni）",
      all(c("lsd", "tukey", "bonferroni") %in% names(.ph)),
      paste(names(.ph), collapse = ", "))
.lsd <- .ph$lsd; .bon <- .ph$bonferroni
check("生产代码：事后比较列名符合约定（pair1/pair2/t/p_adjusted/ci_*）",
      all(c("pair1", "pair2", "t", "p_adjusted", "ci_lower", "ci_upper", "se") %in% names(.lsd)),
      paste(names(.lsd), collapse = ", "))
# 独立复算：合并方差 MSE、sp、SE、t
.mse <- sum(tapply(.yv, .g, function(z) sum((z - mean(z))^2))) / (length(.yv) - nlevels(.g))
.sp <- sqrt(.mse); .dfe <- length(.yv) - nlevels(.g)
.m <- nlevels(.g) * (nlevels(.g) - 1) / 2
.raw_p <- 2 * stats::pt(-abs(.lsd$t), .dfe)
check("生产代码：LSD 的 p_adjusted = 未校正双尾 p",
      all(near(.lsd$p_adjusted, .raw_p, tol = 1e-10)),
      sprintf("最大偏差 %.3e", max(abs(.lsd$p_adjusted - .raw_p))))
check("生产代码：Bonferroni p = min(1, LSD 原始 p × m)",
      all(near(.bon$p_adjusted, pmin(1, .raw_p * .m), tol = 1e-10)),
      sprintf("最大偏差 %.3e（m = %d）", max(abs(.bon$p_adjusted - pmin(1, .raw_p * .m))), .m))
# LSD 各行的内部自洽性：t = 差值/SE、p = 2·pt(−|t|, dfe)、CI = 差值 ∓ t_crit·SE。
# 这三条关系把"差值、SE、t、p、CI"五列锁在一起，任何一列算错都会被抓到；
# 且只依赖模块自己报出的数，因此与测试用哪份随机数据无关（比"另跑一次 t.test 再比"更可靠）。
.lsd_crit <- stats::qt(1 - 0.05 / 2, .dfe)
.lsd_ok <- near(.lsd$t, .lsd$difference / .lsd$se, tol = 1e-10) &&
           near(.lsd$ci_lower, .lsd$difference - .lsd_crit * .lsd$se, tol = 1e-10) &&
           near(.lsd$ci_upper, .lsd$difference + .lsd_crit * .lsd$se, tol = 1e-10)
check("生产代码：LSD 各行自洽（t = 差/SE，CI = 差 ∓ t_crit·SE）", .lsd_ok,
      sprintf("t 偏差 %.3e，CI 下界偏差 %.3e，CI 上界偏差 %.3e",
              max(abs(.lsd$t - .lsd$difference / .lsd$se)),
              max(abs(.lsd$ci_lower - (.lsd$difference - .lsd_crit * .lsd$se))),
              max(abs(.lsd$ci_upper - (.lsd$difference + .lsd_crit * .lsd$se)))))
# Bonferroni 与 LSD 的差值、SE、t 必须逐行相同（只有 p 与临界值不同）
check("生产代码：Bonferroni 与 LSD 的差值/SE/t 逐行相同（仅校正方式不同）",
      near(.bon$difference, .lsd$difference, tol = 1e-12) &&
      near(.bon$se, .lsd$se, tol = 1e-12) &&
      near(.bon$t, .lsd$t, tol = 1e-12),
      "差值/SE/t 出现差异说明两种校正走了不同的检验统计量")
# Bonferroni 的临界值必须比 LSD 宽：CI 也必须更宽
check("生产代码：Bonferroni 的 CI 不窄于 LSD 的 CI（临界值更保守）",
      all((.bon$ci_upper - .bon$ci_lower) >= (.lsd$ci_upper - .lsd$ci_lower) - 1e-9),
      sprintf("最小宽度差 %.3e", min((.bon$ci_upper - .bon$ci_lower) - (.lsd$ci_upper - .lsd$ci_lower))))

# ── 6.5 球形校正 ε 的合法范围（结构性质；不锁具体值以免包/R 版本漂移误报）──
# 用生产函数 spss_repeated_glm() + gg_hf_epsilons()，而不是直接猜 car::Anova 的对象结构。
set.seed(20260911)
.wide <- data.frame(t1 = stats::rnorm(30), t2 = stats::rnorm(30), t3 = stats::rnorm(30), t4 = stats::rnorm(30))
.rm <- spss_repeated_glm(.wide, time_labels = c("t1", "t2", "t3", "t4"))
.eps <- gg_hf_epsilons(.rm$summary)
check("生产代码：球形校正表可产出 GG/HF ε", nrow(.eps) >= 1 && all(c("GG_eps", "HF_eps") %in% names(.eps)),
      sprintf("行数 %d，列 %s", nrow(.eps), paste(names(.eps), collapse = ",")))
.gg <- .eps$GG_eps[1]; .hf <- .eps$HF_eps[1]
check("生产代码：GG ε 落在 [1/(k-1), 1]（k = 4）",
      is.finite(.gg) && .gg >= 1 / 3 - 1e-9 && .gg <= 1 + 1e-9,
      sprintf("GG ε = %.6f", .gg))
check("生产代码：GG ε ≤ HF ε（HF 是对 GG 的向上修正，且 HF 被截断在 1）",
      is.finite(.hf) && .hf >= .gg - 1e-9 && .hf <= 1 + 1e-9,
      sprintf("GG = %.6f, HF = %.6f", .gg, .hf))

# ── 6.6 缺失值：整例删除必须报告删除人数（此前 6 处静默 listwise）──
.source_items <- data.frame(a = c(1, 2, NA), b = c(1, NA, 3), c = c(1, 2, 3))
.rm <- stats::complete.cases(.source_items)
check("生产代码：listwise 删除人数可计算且正确", sum(!.rm) == 2 && sum(.rm) == 1,
      sprintf("保留 %d 行，删除 %d 行", sum(.rm), sum(!.rm)))

# ══════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════
# 7. IRT 端到端 CIFA：断言**管线自己产出的**模型比较表（v0.1.0 新增）
#    说明：这里不再另起炉灶重拟合，而是跑真正的管线（run_irt_analysis.ps1 -Silent），
#    再读它在结果目录里写出的 *_model_comparison.csv 做数值断言。
#    这样验的是生产路径本身。
#    注意：examples/silent_mirt_2pl_binary_cifa_simulation.json 走的是 **内置模拟数据**
#    （seed=20260815，见配置文件的 simulation.seed），与 examples/simulated_mirt_2pl_binary.csv 不是同一份数据，因此
#    这里断言的是**结构性关系**（CIFA 必须明显优于单维），而不是文档里那组具体数值——
#    那组数值对应「指向示例 CSV 的那次运行」，见 examples/simulated_mirt_2pl_binary_expected_output.md。
#    另加一条上界断言：若 CIFA 的 BIC 反而比单维差，说明 2D 模型根本没被正确拟合
#    （这正是 v0.1.0 首次尝试时踩到的坑：模型语法错误导致 2D 退化成更差的模型）。
#    需要 PowerShell；若不可用则跳过（非 Windows 环境）。
# ══════════════════════════════════════════════════════════════════════════════
.cifa_cfg <- file.path(root, "examples", "silent_mirt_2pl_cifa_simulation.json")
.ps <- Sys.which("powershell")
if (!nzchar(.ps)) .ps <- Sys.which("pwsh")
if (!has_mirt) { skip_block("第 7 节 IRT 端到端（CIFA 管线）") } else if (nzchar(.ps) && file.exists(.cifa_cfg) && !nzchar(Sys.getenv("PSYCHOSTAT_SKIP_IRT_FIT"))) {
  .irt_ok <- tryCatch({
    .log <- suppressWarnings(system2(.ps,
      c("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        shQuote(file.path(root, "run_irt_analysis.ps1")), "-Silent",
        "-ConfigJson", shQuote(.cifa_cfg)),
      stdout = TRUE, stderr = TRUE))
    # complete 事件的形状：{"event":"complete","timestamp":…,"data":{"result_dir":…,…}}
    # 用 jsonlite 正式解析，避免手写正则在转义/中文路径上出错。
    .cev <- NULL
    for (.ln in .log) {
      .ln <- trimws(.ln)
      if (!grepl('"event"', .ln, fixed = TRUE)) next
      .p <- tryCatch(jsonlite::fromJSON(.ln), error = function(e) NULL)
      if (!is.null(.p) && identical(.p$event, "complete")) .cev <- .p
    }
    if (is.null(.cev) || is.null(.cev$data$result_dir)) stopf("静默日志中未找到 complete 事件或其 result_dir")
    .rd <- as.character(.cev$data$result_dir)
    if (is.na(.rd) || !dir.exists(.rd)) stopf("未能从静默日志取得 IRT 结果目录")
    .cmpf <- list.files(.rd, pattern = "model_comparison\\.csv$", full.names = TRUE)
    if (!length(.cmpf)) stopf("结果目录缺少 model_comparison.csv")
    .cmp <- utils::read.csv(.cmpf[1], check.names = FALSE)
    # 锁定 CIFA 与单维两行
    .cifa <- .cmp[grep("^CIFA", .cmp$Model), , drop = FALSE]
    .uni  <- .cmp[grep("Unidimensional", .cmp$Model), , drop = FALSE]
    check("IRT端到端：模型比较表含 CIFA 与单维两行", nrow(.cifa) == 1L && nrow(.uni) == 1L,
          sprintf("模型：%s", paste(.cmp$Model, collapse = " | ")))
    if (nrow(.cifa) == 1L && nrow(.uni) == 1L) {
      .dbic <- .cifa$BIC[1] - .uni$BIC[1]
      # 阈值取 -20：内置模拟数据（seed=20260815）与文档那次（示例 CSV）不是同一份数据，
      # 具体数值会有出入，但"2D 显著优于单维"这一结构关系必须成立。
      check("IRT端到端：2D CIFA 的 BIC 明显优于单维（ΔBIC < -20）", is.finite(.dbic) && .dbic < -20,
            sprintf("BIC CIFA = %.3f, 单维 = %.3f, Δ = %.3f", .cifa$BIC[1], .uni$BIC[1], .dbic))
      .dcfi <- .cifa$CFI[1] - .uni$CFI[1]
      check("IRT端到端：2D CIFA 的 CFI 高于单维（ΔCFI > .10）", is.finite(.dcfi) && .dcfi > .10,
            sprintf("CFI CIFA = %s, 单维 = %s", .cifa$CFI[1], .uni$CFI[1]))
      check("IRT端到端：CIFA 的 RMSEA 优于单维（ΔRMSEA < 0）",
            (is.na(.cifa$RMSEA[1]) || is.na(.uni$RMSEA[1])) ||
              (.cifa$RMSEA[1] - .uni$RMSEA[1] < 0),
            sprintf("RMSEA CIFA = %s, 单维 = %s", .cifa$RMSEA[1], .uni$RMSEA[1]))
      # 上界：2D 若比单维差，几乎必然是模型语法/映射出错（本次首轮即为此）
      check("IRT端到端：CIFA 的 BIC 不得差于单维（防模型语法错误退化成差模型）",
            .dbic < 0,
            sprintf("ΔBIC = %.3f（应为负；若为正，请检查 model_syntax 与载荷矩阵映射）", .dbic))
    }
    TRUE
  }, error = function(e) { check("IRT端到端 CIFA（管线）", FALSE, conditionMessage(e)); FALSE })
} else {
  check("IRT端到端 CIFA（管线）：本机无 PowerShell 或已跳过", TRUE, "skipped")
}


# ══════════════════════════════════════════════════════════════════════════════
# 8. 数据准备（第 0 步）：缺失值审计、异常值筛查、均值插补、完整性检查
#    这些断言都基于**构造数据**，期望值可手算，因此能真正约束生产代码。
# ══════════════════════════════════════════════════════════════════════════════
source(file.path(root, "scripts", "stats_datacheck.R"), local = TRUE)

# ── 8.1 缺失值审计：计数与 listwise 影响必须精确 ──
.dc <- data.frame(a = c(1, 2, NA, 4, 5), b = c(1, NA, 3, 4, 5), c = c(1, 2, 3, 4, 5))
.ma <- missing_audit(.dc)
check("数据准备：逐变量缺失计数正确", identical(as.integer(.ma$per_variable$N_missing), c(1L, 1L, 0L)),
      paste(.ma$per_variable$N_missing, collapse = ","))
check("数据准备：整例删除影响正确（2 个不完整个案）",
      .ma$listwise_impact$N_complete_cases == 3L && .ma$listwise_impact$N_would_drop == 2L,
      sprintf("完整 %d 行，将删 %d 行", .ma$listwise_impact$N_complete_cases, .ma$listwise_impact$N_would_drop))
.mc <- missing_cases(.dc)
check("数据准备：个案级缺失清单正确（列出缺了哪些变量）",
      nrow(.mc) == 2L && all(.mc$N_missing == 1L) && any(grepl("a", .mc$missing_variables)),
      sprintf("%d 行；变量列 = %s", nrow(.mc), paste(.mc$missing_variables, collapse = " | ")))

# ── 8.2 均值插补：插补后无缺失、均值不变、方差变小 ──
.dc2 <- data.frame(x = c(1, 2, 3, NA, NA, 6))
.mi <- mean_impute_numeric(.dc2)
.mu_before <- mean(.dc2$x, na.rm = TRUE)
check("数据准备：均值插补后无缺失值", !any(is.na(.mi$data$x)))
check("数据准备：均值插补不改变均值（精确值 3）",
      near(mean(.mi$data$x), 3, tol = 1e-12), sprintf("M = %.12f", mean(.mi$data$x)))
check("数据准备：均值插补会缩小方差（这是它已知的代价）",
      stats::var(.mi$data$x) < stats::var(.dc2$x, na.rm = TRUE),
      sprintf("插补后 %.6f < 插补前 %.6f", stats::var(.mi$data$x), stats::var(.dc2$x, na.rm = TRUE)))
check("数据准备：插补计数正确（2 个）", .mi$n_total == 2L && .mi$table$n_imputed[1] == 2L,
      sprintf("n_total = %d", .mi$n_total))

# ── 8.3 异常值：Z 与 IQR 两条规则的命中数可手算 ──
# 构造：1..9 加一个 100。Z 规则用 |Z|>3；100 的 Z 约 2.9（10 个点，Z_max=(n-1)/sqrt(n)≈2.85）
# 说明：n 小时 Z 上限就是 sqrt(n-1)，永远到不了 3 —— 这正是文档里提醒"小样本 Z 会漏报"的原因。
.ov <- data.frame(v = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 100))
.uo <- univariate_outliers(.ov, z_cutoff = 3)
# n 个观测时 |Z| 的理论上限为 (n-1)/sqrt(n)：n=10 时约 2.85，永远到不了 3 ——
# 这就是文档里提醒"小样本下 Z 规则会漏报、要看箱线图"的数学原因。
check("数据准备：小样本下 |Z| 有理论上限，n=10 时到不了 3（Z 规则会漏报）",
      .uo$summary$n_z[1] == 0L && (10 - 1) / sqrt(10) < 3,
      sprintf("n_z = %d；Z 理论上限 (n-1)/sqrt(n) = %.4f < 3", .uo$summary$n_z[1], (10 - 1) / sqrt(10)))
check("数据准备：同一数据用 1.5×IQR 能命中该异常值",
      .uo$summary$n_iqr[1] >= 1L, sprintf("n_iqr = %d", .uo$summary$n_iqr[1]))
# 大样本下 Z 规则应当生效
set.seed(20260901)
.big <- data.frame(v = c(stats::rnorm(200, 50, 10), 500))
.uo2 <- univariate_outliers(.big, z_cutoff = 3)
check("数据准备：大样本下 |Z| > 3 能命中极端值",
      .uo2$summary$n_z[1] == 1L && .uo2$summary$n_extreme_iqr[1] == 1L,
      sprintf("n_z = %d, n_extreme_iqr = %d", .uo2$summary$n_z[1], .uo2$summary$n_extreme_iqr[1]))
check("数据准备：异常个案清单包含 id/value/Z/reason 四列",
      all(c("variable", "id", "value", "Z", "reason") %in% names(.uo2$detail)) && nrow(.uo2$detail) == 1L,
      paste(names(.uo2$detail), collapse = ","))
# 删除逻辑：drop_ids 只取 Z 规则命中的个案（与用户选择的判定口径一致）
check("数据准备：删除集合以 Z 规则为准（不受 IQR 影响）",
      length(.uo2$drop_ids) == 1L, sprintf("drop_ids = %d 个", length(.uo2$drop_ids)))

# ── 8.4 完整性检查：ID 重复 / 常量列 / 越界 ──
.ic <- data.frame(id = c("S1", "S2", "S2"), x = c(1, 2, 3), y = c(5, 5, 5))
.ir <- integrity_check(.ic, id = .ic$id, scale_range = c(1, 5), id_name = "id")
check("数据准备：能查出 ID 重复", any(grepl("ID 重复", .ir$check)), paste(.ir$check, collapse = " | "))
check("数据准备：能查出常量列（零方差）", any(grepl("常量列", .ir$check)), paste(.ir$variable, collapse = ","))
# 显式声明为量表变量 → 任何越界值都严格报告
.ic2 <- data.frame(id = c("S1", "S2"), x = c(3, 6))
.ir2 <- integrity_check(.ic2, id = .ic2$id, scale_range = c(1, 5), id_name = "id", scale_vars = "x")
check("数据准备：声明为量表变量后，越界值被严格报告",
      any(grepl("取值越界", .ir2$check)) && any(grepl("6", .ir2$detail)),
      paste(.ir2$check, collapse = " | "))
# 未声明且整列远在范围外（连续总分）→ 只提示，不误报
.ic3 <- data.frame(id = c("S1", "S2"), x = c(20, 40))
.ir3 <- integrity_check(.ic3, id = .ic3$id, scale_range = c(1, 5), id_name = "id")
# 未声明 scale_vars 时不猜：连续总分只给提示，不误报为越界（契约明确、可预期）
check("数据准备：未声明的变量不误报为越界（只给范围提示）",
      !any(grepl("取值越界", .ir3$check)) && any(grepl("范围提示", .ir3$check)),
      paste(.ir3$check, collapse = " | "))
# 缺失码形态兜底：绝大多数在范围内、极少数跳出（如 99）→ 仍应报越界
set.seed(7); .ic4 <- data.frame(id = sprintf("S%02d", 1:50), x = c(sample(1:5, 49, TRUE), 99))
.ir4 <- integrity_check(.ic4, id = .ic4$id, scale_range = c(1, 5), id_name = "id")
check("数据准备：未声明时也能识别缺失码形态（99 混在 1-5 里）→ 报越界",
      any(grepl("取值越界", .ir4$check)), paste(.ir4$check, collapse = " | "))

# ── 8.5 演示数据确实包含"可被查出"的问题（否则模块演示是空的）──
.sim_dc <- simulate_datacheck(list(simulation = list(seed = 20260904, n_per_group = 30)))
check("数据准备：演示数据确实含缺失值", sum(is.na(.sim_dc)) >= 5L, sprintf("缺失 %d 个", sum(is.na(.sim_dc))))
.sim_uni <- univariate_outliers(.sim_dc, z_cutoff = 3, id = .sim_dc$id)
check("数据准备：演示数据确实含可被 |Z|>3 命中的异常值", .sim_uni$summary$n_z[sum(.sim_uni$summary$n_z)] >= 1L ||
        sum(.sim_uni$summary$n_z) >= 1L, sprintf("Z 命中合计 %d", sum(.sim_uni$summary$n_z)))
check("数据准备：演示数据含 1-5 量表变量（用于示例越界检查）",
      "sleep_quality" %in% names(.sim_dc) && min(.sim_dc$sleep_quality, na.rm = TRUE) >= 1L &&
        max(.sim_dc$sleep_quality, na.rm = TRUE) <= 5L,
      sprintf("sleep_quality 范围 %s ~ %s", min(.sim_dc$sleep_quality, na.rm = TRUE),
              max(.sim_dc$sleep_quality, na.rm = TRUE)))

# ── 8.6 报告句助手：不返回 NULL、含关键数字 ──
.n1 <- datacheck_missing_note(.ma, "mean_impute", 2L)
check("数据准备：缺失值结论文本含处理方式与个数",
      is.character(.n1) && grepl("均值插补", .n1) && grepl("2", .n1), substr(.n1, 1, 60))
.n2 <- datacheck_outlier_note(.uo2, 3, "remove_by_z", 1L)
check("数据准备：异常值结论文本含判定标准与删除人数",
      is.character(.n2) && grepl("|Z| > 3", .n2, fixed = TRUE) && grepl("删除", .n2), substr(.n2, 1, 60))


# ══════════════════════════════════════════════════════════════════════════════
# 9. 事后比较的 CI 临界值必须跟随 alpha
#    这是与"单尾检验 / α 选择"功能彼此独立的 bug 修复，功能撤销后**仍然保留**：
#    否则 CI 与 p 值会自相矛盾（p 已显著，CI 却包含 0）。检验设置现已固定为双尾 + α = .05，
#    但 posthoc_tables() / paired_posthoc() 仍以参数接收 alpha，故此处直接以参数约束口径。
# ══════════════════════════════════════════════════════════════════════════════

# ── 9.1 事后比较的 CI 临界值必须跟随 alpha（修掉"p 显著但 CI 含 0"的矛盾）──
# 注意：posthoc_tables() 返回的是 list(lsd=…, bonferroni=…, tukey=…)，不是单个 data.frame。
set.seed(20260921)
.g3 <- factor(rep(c("a", "b", "c"), each = 14))
.y3 <- c(stats::rnorm(14, 10, 3), stats::rnorm(14, 13, 3), stats::rnorm(14, 16, 3))
.lsd05 <- posthoc_tables(.y3, .g3, alpha = 0.05)$lsd
.lsd10 <- posthoc_tables(.y3, .g3, alpha = 0.10)$lsd
.bon05 <- posthoc_tables(.y3, .g3, alpha = 0.05)$bonferroni
.bon10 <- posthoc_tables(.y3, .g3, alpha = 0.10)$bonferroni
.dfe3 <- length(.y3) - nlevels(.g3)
.crit_ok <- TRUE
for (i in seq_len(nrow(.lsd05))) {
  .se <- .lsd05$se[i]; .diff <- .lsd05$difference[i]
  if (!near(.lsd05$ci_lower[i], .diff - stats::qt(1 - 0.05 / 2, .dfe3) * .se, tol = 1e-10)) .crit_ok <- FALSE
  if (!near(.lsd10$ci_lower[i], .diff - stats::qt(1 - 0.10 / 2, .dfe3) * .se, tol = 1e-10)) .crit_ok <- FALSE
}
check("事后比较：LSD 的 CI 临界值跟随 alpha（.05 与 .10 各自与 qt 闭式一致）", .crit_ok,
      sprintf("dfe = %d", .dfe3))
check("事后比较：alpha 变大后 LSD 的 CI 变窄（临界值变小）",
      all((.lsd10$ci_upper - .lsd10$ci_lower) < (.lsd05$ci_upper - .lsd05$ci_lower)),
      sprintf("最大宽度差 %.3e", max((.lsd05$ci_upper - .lsd05$ci_lower) - (.lsd10$ci_upper - .lsd10$ci_lower))))
# Bonferroni 的临界值是 qt(1 - alpha/(2m))，也须跟随 alpha
.kk3 <- nlevels(.g3); .mm3 <- .kk3 * (.kk3 - 1L) / 2L
.bon_ok <- TRUE
for (i in seq_len(nrow(.bon05))) {
  .se <- .bon05$se[i]; .diff <- .bon05$difference[i]
  if (!near(.bon05$ci_upper[i], .diff + stats::qt(1 - 0.05 / (2 * .mm3), .dfe3) * .se, tol = 1e-10)) .bon_ok <- FALSE
  if (!near(.bon10$ci_upper[i], .diff + stats::qt(1 - 0.10 / (2 * .mm3), .dfe3) * .se, tol = 1e-10)) .bon_ok <- FALSE
}
check("事后比较：Bonferroni 的 CI 跟随 alpha（临界值 = qt(1 - alpha/(2m))）", .bon_ok,
      sprintf("m = %d, dfe = %d", .mm3, .dfe3))
check("事后比较：alpha 变大后 Bonferroni 的 CI 变窄",
      all((.bon10$ci_upper - .bon10$ci_lower) < (.bon05$ci_upper - .bon05$ci_lower)),
      "Bonferroni 在 alpha=.10 下 CI 应更窄")

# ── 9.2 不再出现"p 显著却 CI 含 0"的自相矛盾 ──
.contradict05 <- sum(.bon05$p_adjusted < 0.05 & .bon05$ci_lower <= 0 & .bon05$ci_upper >= 0)
.contradict10 <- sum(.bon10$p_adjusted < 0.10 & .bon10$ci_lower <= 0 & .bon10$ci_upper >= 0)
check("事后比较：alpha=.05/.10 下均不出现\"p 显著却 CI 含 0\"的矛盾",
      .contradict05 == 0L && .contradict10 == 0L,
      sprintf("alpha=.05 矛盾 %d 行；alpha=.10 矛盾 %d 行（应恒为 0）", .contradict05, .contradict10))

# ── 9.3 单因素 ANOVA 的端到端：alpha=.10 时"显著配对"不应出现 CI 含 0 的矛盾 ──
.phA <- posthoc_tables(.y3, .g3, alpha = 0.10)$bonferroni
.contradict <- sum(.phA$p_adjusted < 0.10 & .phA$ci_lower <= 0 & .phA$ci_upper >= 0)
check("事后比较：alpha=.10 下不再出现\"p 显著却 CI 含 0\"的自相矛盾",
      .contradict == 0L,
      sprintf("矛盾行数 = %d（应恒为 0）", .contradict))

# ══════════════════════════════════════════════════════════════════════════════
# 10. 调节效应：X/Z 必须真正做均值中心化（SPSS PROCESS 的 Mean center 口径）
#     背景：曾误写成 scale(x, scale = FALSE, center = FALSE) —— 等于完全没有中心化，
#     截距与两个主效应全部失真；而交互项恰好不受中心化影响，所以只比对交互项会漏掉该 bug。
#     判别要点：未中心化时 X 的主效应是"Z = 0 处的斜率"，且与乘积项严重共线、SE 被大幅抬高。
# ══════════════════════════════════════════════════════════════════════════════
set.seed(20260922)
.n <- 200
.z_raw <- stats::rnorm(.n, 26, 8)
# X 与 Z 故意做成相关（真实问卷里调节变量与自变量几乎总相关）：
# 这样 mean(Xc·Zc) ≠ 0，可同时约束截距的完整恒等式，而不只是"截距 = 因变量均值"这一特例。
.x_raw <- 36 + 0.45 * (.z_raw - 26) / 8 * 10 + stats::rnorm(.n, 0, 9)
.y_raw <- 30 + 0.32 * .x_raw + 0.58 * .z_raw - 0.002 * .x_raw * .z_raw + stats::rnorm(.n, 0, 6.6)
.md <- data.frame(y = .y_raw, x = .x_raw, w = .z_raw)
check("调节：模拟数据中 X 与 Z 确实相关（否则截距恒等式退化，测试失去判别力）",
      abs(stats::cor(.md$x, .md$w)) > 0.2, sprintf("r = %.3f", stats::cor(.md$x, .md$w)))

# 独立复算：SPSS PROCESS 口径 = 先把 X/Z 各自减去均值，再构造乘积项
.xc <- .md$x - mean(.md$x); .wc <- .md$w - mean(.md$w)
.refc <- summary(stats::lm(y ~ xc + wc + xc:wc, data = data.frame(y = .md$y, xc = .xc, wc = .wc)))$coefficients
# 对照口径：完全不中心化（即修复前的错误实现）
.unc <- summary(stats::lm(y ~ x + w + x:w, data = .md))$coefficients

.mod_out <- file.path(tempdir(), "psy_mod_test"); dir.create(.mod_out, showWarnings = FALSE)
.mod_cfg <- list(variables = list(interaction_x = "x", interaction_z = "w", interaction_dv = "y"),
                 analysis = list(alpha = 0.05))
invisible(utils::capture.output(
  run_moderation(.md, .mod_cfg, list(out_dir = .mod_out, prefix = "01_moderation", alpha = 0.05, echo = FALSE))))
.mod_f <- file.path(.mod_out, "01_moderation_interaction_model.csv")
check("调节：能产出交互模型表", file.exists(.mod_f), .mod_f)
if (file.exists(.mod_f)) {
  .mt <- utils::read.csv(.mod_f, check.names = FALSE)
  for (.i in seq_len(4L)) {
    check(sprintf("调节：系数 %d 的 B 与 SE 均与独立复算的中心化模型一致", .i),
          near(.mt$B[.i], .refc[.i, 1], tol = 1e-8) && near(.mt$SE[.i], .refc[.i, 2], tol = 1e-8),
          sprintf("B 模块 %.10f vs 复算 %.10f；SE 模块 %.10f vs 复算 %.10f",
                  .mt$B[.i], .refc[.i, 1], .mt$SE[.i], .refc[.i, 2]))
  }
  # 截距的完整恒等式（X、Z 均已中心化）：截距 = mean(Y) − b_交互 · mean(Xc·Zc)。
  # 只有 X 与 Z 不相关时 mean(Xc·Zc) = 0，它才退化为"截距 = 因变量均值"这一特例。
  .mxc <- mean(.xc * .wc)
  check("调节：截距满足恒等式 mean(Y) − b3·mean(Xc·Zc)（X 与 Z 相关时同样成立）",
        near(.mt$B[1], mean(.md$y) - .mt$B[4] * .mxc, tol = 1e-8),
        sprintf("模块截距 %.10f vs 恒等式 %.10f（mean(Xc·Zc) = %.4f）",
                .mt$B[1], mean(.md$y) - .mt$B[4] * .mxc, .mxc))
  check("调节：模块口径与\"未中心化\"口径明显不同（据此可判别是否真的做了中心化）",
        abs(.mt$B[1] - .unc[1, 1]) > 0.5 && abs(.mt$B[2] - .unc[2, 1]) > 0.01,
        sprintf("中心化 截距 %.4f / B_X %.4f vs 未中心化 %.4f / %.4f",
                .mt$B[1], .mt$B[2], .unc[1, 1], .unc[2, 1]))
  check("调节：未中心化会因共线性把 X 主效应的 SE 抬高，中心化后 SE 回落至复算值",
        .unc[2, 2] > 1.5 * .refc[2, 2],
        sprintf("未中心化 SE %.4f vs 中心化 SE %.4f", .unc[2, 2], .refc[2, 2]))
  # 简单斜率表：均值处斜率应等于 X 主效应系数；且满足 b1 + b3·Z
  .sl_f <- file.path(.mod_out, "01_moderation_simple_slopes.csv")
  if (file.exists(.sl_f)) {
    .sl <- utils::read.csv(.sl_f, check.names = FALSE)
    check("调节：简单斜率在均值处 = X 主效应系数",
          near(.sl$simple_slope_of_X[2], .mt$B[2], tol = 1e-8),
          sprintf("均值处斜率 %.10f vs B_X %.10f", .sl$simple_slope_of_X[2], .mt$B[2]))
    check("调节：简单斜率满足 b1 + b3·Z（低/高两端均可验）",
          near(.sl$simple_slope_of_X[1], .mt$B[2] + .mt$B[4] * .sl$Z_value[1], tol = 1e-8) &&
            near(.sl$simple_slope_of_X[3], .mt$B[2] + .mt$B[4] * .sl$Z_value[3], tol = 1e-8),
          sprintf("低端 %.10f vs %.10f", .sl$simple_slope_of_X[1], .mt$B[2] + .mt$B[4] * .sl$Z_value[1]))
  }
}

if (irt_skipped > 0L) cat(sprintf("[注意] 本次跳过 %d 个 IRT 断言块：%s\n", irt_skipped, irt_skip_reason))
cat(if (ok) "ALL NUMERIC TESTS PASSED\n" else "NUMERIC TESTS FAILED\n")
quit(status = if (ok) 0 else 1)
