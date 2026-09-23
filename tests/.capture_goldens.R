# 黄金值维护工具：独立复算 test_numeric.R 第 3/4 节黄金值（统计量一律用 base R / pwr 直接计算，
# 不经过 run_* 管线代码）。输出数值供人工比对/更新 test_numeric.R 中的硬编码黄金值。
# 用法：Rscript tests/.capture_goldens.R --update   （无 --update 参数时只打印提示并退出 0）
if (!"--update" %in% commandArgs(TRUE)) {
  cat("黄金值维护工具：仅在你明确要重算黄金值时用 Rscript .capture_goldens.R --update 运行；常规验证请跑 test_numeric.R\n")
  quit(status = 0)
}
root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."))
suppressMessages({
  source(file.path(root, "scripts", "stats_common.R"))
  source(file.path(root, "scripts", "stats_modules.R"))
})
cfg <- list(simulation = list(seed = 20260904, n_per_group = 30), analysis = list(alpha = .05, posthoc = c("lsd","tukey","bonferroni"), correlation_method = "both"))
ctx <- list(out_dir = tempdir(), prefix = "g", alpha = .05, echo = FALSE)
stats_session$report <- character()
d <- simulate_independent_t(cfg); g1 <- droplevels(factor(d$gender)); t_eq <- t.test(suppressWarnings(as.numeric(d$spatial_score)) ~ g1, var.equal = TRUE)
cat(sprintf("independent_t t = %.10f\n", t_eq$statistic))
d <- simulate_one_way_anova(cfg); f <- summary(aov(score ~ method, d))[[1]]
cat(sprintf("one_way F = %.10f  df = %d %d  eta2p = %.10f\n", f[1,"F value"], f[1,"Df"], f[2,"Df"], f[1,"Sum Sq"]/(f[1,"Sum Sq"]+f[2,"Sum Sq"])))
d <- simulate_paired_t(cfg); dd <- d$post - d$pre
cat(sprintf("paired_t t = %.10f  (后-前)\n", t.test(dd)$statistic))
d <- simulate_rm_anova(cfg); wr <- as.matrix(d[grep("^time", names(d))])
ma <- suppressWarnings(summary(car::Anova(stats::lm(wr ~ 1), idata = data.frame(time = factor(1:4)), idesign = ~time, type = 3), multivariate = FALSE))
cat(sprintf("rm F = %.10f\n", ma$univariate.tests["time","F value"]))
d <- simulate_chi_square_independence(cfg)
cat(sprintf("chi_ind chisq = %.10f  df = %d\n", chisq.test(table(d$gender, d$career_pref), correct=FALSE)$statistic, chisq.test(table(d$gender, d$career_pref), correct=FALSE)$parameter))
d <- simulate_mediation(cfg); dd2 <- data.frame(X=d$stress, M=d$rumination, Y=d$depression)
a <- coef(lm(M ~ X, dd2))["X"]; b <- coef(lm(Y ~ X + M, dd2))["M"]
cat(sprintf("mediation ab = %.10f\n", a*b))
d <- simulate_two_way_anova(cfg); f2 <- summary(aov(score ~ method * motivation, d))[[1]]
cat(sprintf("two_way F: method = %.10f  motivation = %.10f  interaction = %.10f\n", f2[1,"F value"], f2[2,"F value"], f2[3,"F value"]))
d <- simulate_ancova(cfg); fa <- anova(lm(posttest ~ pretest, d), lm(posttest ~ pretest + method, d))
cat(sprintf("ancova F(组效应|协变量) = %.10f  斜率 pretest = %.10f\n", fa[2,"F"], coef(lm(posttest ~ pretest + method, d))[["pretest"]]))
d <- simulate_regression(cfg); fg <- lm(final_grade ~ study_hours + iq + test_anxiety, d)
ci <- confint(fg)["study_hours", ]
cat(sprintf("regression B[study_hours] = %.10f  CI = [%.10f, %.10f]\n", coef(fg)[["study_hours"]], ci[1], ci[2]))
d <- simulate_moderation(cfg)
Xc <- d$motivation - mean(d$motivation); Zc <- d$learning_resources - mean(d$learning_resources)
cat(sprintf("moderation B[Xc:Zc] = %.10f\n", coef(lm(d$engagement_score ~ Xc * Zc))[["Xc:Zc"]]))
nref <- pwr::pwr.t.test(d = 0.5, sig.level = 0.05, power = 0.8, type = "two.sample")$n
cat(sprintf("power d=.5/power=.80: n/组 = %.10f → ceiling %d → 模块表 N_total = 2×ceiling = %d（每组 = N_total/2）\n",
            nref, ceiling(nref), 2L * ceiling(nref)))
.orig_ca <- base::commandArgs
commandArgs <- function(trailingOnly = FALSE) if (trailingOnly) character(0) else paste0("--file=", normalizePath(file.path(root, "scripts", "ctt_pipeline.R")))
source(file.path(root, "scripts", "ctt_pipeline.R"), local = TRUE)
commandArgs <- .orig_ca
cttcfg <- normalise_ctt_config(yaml::read_yaml(file.path(root, "ctt_config.yaml")), root)
raw <- simulate_ctt_data(cttcfg$simulation); prepared <- prepare_ctt_items(raw, cttcfg); cleaned <- clean_ctt_data(raw, prepared$names, cttcfg)
cat(sprintf("ctt alpha = %.10f\n", psych::alpha(cleaned$items, check.keys=FALSE, warnings=FALSE)$total$raw_alpha))
