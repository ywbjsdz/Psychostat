#!/usr/bin/env Rscript
# =============================================================================
# Psychostat 模拟数据集生成器
# -----------------------------------------------------------------------------
# 用途：为 CTT（经典测量理论）与 IRT（项目反应理论）两个分支生成"可直接试跑"的
#       模拟数据，并同时导出**生成真值**（题目参数、维度归属、被试真能力），
#       便于做参数恢复（parameter recovery）与教学演示。
#
# 用法：
#   Rscript scripts/generate_simulated_datasets.R                 # 生成全部
#   Rscript scripts/generate_simulated_datasets.R --seed 2027     # 换一组随机种子
#   Rscript scripts/generate_simulated_datasets.R --out D:/my     # 指定输出目录
#
# 输出目录（默认）：examples/simulated_datasets/
#   每个数据集 = 一个 CSV（一行一名被试）+ 可选真值 CSV + 一个可直接使用的 YAML 配置
#   详细说明见同目录 README_模拟数据说明.md
#
# 依赖：仅 base R + MASS。IRT 数据由本脚本按标准参数化自行生成（不调用 mirt），
#       以便生成过程与真值完全透明、可核对；阈值的多维折算采用 mirt 的标准口径
#       b = -d / MDISC，因此恢复出的 b 应与真值高度吻合。
# =============================================================================

suppressWarnings(suppressPackageStartupMessages(library(MASS)))

## ---------------------------------------------------------------- 基础工具 ----
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) args[i + 1L] else default
}
script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
root_dir <- if (is.na(script_path)) "." else dirname(dirname(normalizePath(script_path)))
SEED <- as.integer(arg_value("--seed", "20260912"))
OUT  <- arg_value("--out", file.path(root_dir, "examples", "simulated_datasets"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) cat(sprintf(fmt, ...), "\n", sep = "")
say("输出目录：%s", OUT)
say("随机种子：%d", SEED)

## 序数化：把连续潜变量按固定切点转成 1..K 的整数（模拟李克特作答）
ordinalise <- function(y, cuts) as.integer(cut(y, breaks = c(-Inf, cuts, Inf), labels = FALSE))

## 从类别概率矩阵抽样（p 为 n × K 的矩阵，返回 1..K）
sample_categories <- function(p) {
  u <- runif(nrow(p))
  cum <- t(apply(p, 1L, cumsum))
  vapply(seq_len(nrow(p)), function(i) max(1L, which(u[i] <= cum[i, ])[1L]), integer(1))
}

## GRM 作答抽样：P(X >= k | θ) = plogis(a'θ - b_k·MDISC)，k = 1..K-1（b 升序）
## 二维时 a 为长度 D 的向量，θ 为 n × D 矩阵；返回 1..K
sim_grm <- function(theta, a, b) {
  eta <- as.numeric(theta %*% a)
  mdisc <- sqrt(sum(a^2))
  P <- sapply(b, function(bk) plogis(eta - bk * mdisc))
  if (length(b) == 1L) P <- matrix(P, ncol = 1L)
  K <- length(b) + 1L
  mids <- if (K > 2L) sapply(seq_len(K - 2L), function(j) P[, j] - P[, j + 1L]) else NULL
  probs <- cbind(1 - P[, 1L], mids, P[, ncol(P)])
  probs <- pmax(probs, 1e-12); probs <- probs / rowSums(probs)
  sample_categories(probs)
}

## 二分作答抽样：P(X=1) = c + (1-c)·plogis(a'θ - b·MDISC)；返回 0/1
sim_binary <- function(theta, a, b, guess = 0) {
  eta <- as.numeric(theta %*% a)
  p <- guess + (1 - guess) * plogis(eta - b * sqrt(sum(a^2)))
  rbinom(length(p), 1L, p)
}

## GPCM 作答抽样（Muraki 1992 相邻类别 logit；即 mirt itemtype="gpcm" / 多维 MGPCM）。
## mirt 的 gpcm 用「斜率—截距」形式 P(X=k) ∝ exp(k·a'θ + d_k)，参考类别 k=0 的 d_0 = 0，
## 报告时 b_k = -(d_k - d_{k-1}) / MDISC。因此这里按 d_k = -MDISC·Σ_{r≤k} b_r 生成，
## 恢复出的 b_k 应与真值一致（与 sim_grm 的 b 口径可直接对照）。返回 1..K
sim_gpcm <- function(theta, a, b) {
  eta <- as.numeric(theta %*% a)
  mdisc <- sqrt(sum(a^2))
  K <- length(b) + 1L
  cum_b <- c(0, cumsum(b))
  ex <- sapply(0:(K - 1L), function(k) k * eta - mdisc * cum_b[k + 1L])
  ex <- ex - apply(ex, 1L, max)                 # 防溢出：按行减去最大线性预测子
  probs <- exp(ex); probs <- probs / rowSums(probs)
  sample_categories(probs)
}

## 写出 CSV（UTF-8 无 BOM、行尾统一 LF）
## 注意：Windows 上 write.csv 走文本连接，会把 "\n" 落成 "\r\n"，导致同一份真值在不同平台
## 生成出字节不同的文件（`git status` 一片 M）。仓库约定 CSV 为 LF，故写完后统一转回，
## 保证「换个平台重跑生成器，产物与仓库里的一模一样」。
w <- function(x, name) {
  path <- file.path(OUT, name)
  write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
  raw <- readBin(path, "raw", file.size(path))
  if (length(raw)) {
    crlf <- raw == as.raw(13L) & c(raw[-1L], as.raw(0L)) == as.raw(10L)
    if (any(crlf)) writeBin(raw[!crlf], path)
  }
  say("  · %-48s %s 行 × %s 列", name, nrow(x), ncol(x))
}

## 写出可直接使用的 YAML 配置
wcfg <- function(text, name) {
  writeLines(enc2utf8(text), file.path(OUT, name), useBytes = TRUE)
  say("  · %s", name)
}

## ============================================================ CTT 数据集 ====
## A：干净单维量表——最省事的入门数据（GUI 选文件即可跑，无需任何配置）
make_ctt_A <- function() {
  set.seed(SEED + 1L); n <- 600L; k <- 15L
  lambda <- seq(.80, .55, length.out = k)
  theta <- rnorm(n)
  y <- outer(theta, lambda) + matrix(rnorm(n * k), n, k) * rep(sqrt(pmax(1 - lambda^2, .10)), each = n)
  x <- as.data.frame(lapply(seq_len(k), function(j) ordinalise(y[, j], c(-.85, -.25, .25, .85))))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "ctt_A_clean_unidimensional_n600_items15.csv")
  w(data.frame(item = names(x), dimension = "F1", true_loading = round(lambda, 3)), "ctt_A_truth.csv")
  wcfg(c(
    "# CTT-A：干净单维量表（600 人 × 15 题，5 点计分，无缺失、无反向题）",
    "# 用法：Rscript scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_A_config.yaml",
    "input:",
    "  mode: file",
    "  path: \"./ctt_A_clean_unidimensional_n600_items15.csv\"",
    "  id_column: null",
    "  item_columns: auto",
    "cleaning:",
    "  scale_maximum: 5",
    "  reverse_items: []",
    "  missing_5_to_20: median_impute",
    "analysis:",
    "  goal: efa                      # 也可改成 quality（只做质量检查）或 cfa（需对照表）",
    "  rotation: promax",
    "  n_factors: auto",
    "output:",
    "  directory: \"../../outputs\"",
    "  project_label: ctt_A",
    "  report_language: zh"
  ), "ctt_A_config.yaml")
}

## B：完整问卷——三维结构 + 反向题 + 注意检验 + 反应时 + 效标 + 已知组 + 少量缺失
make_ctt_B <- function() {
  set.seed(SEED + 2L); n <- 500L
  dims <- c(F1 = 7L, F2 = 7L, F3 = 6L)
  phi <- matrix(c(1, .35, .30, .35, 1, .40, .30, .40, 1), 3, 3)
  eta <- MASS::mvrnorm(n, mu = rep(0, 3), Sigma = phi)
  colnames(eta) <- names(dims)
  lam <- list(F1 = seq(.75, .58, length.out = dims[["F1"]]),
              F2 = seq(.72, .55, length.out = dims[["F2"]]),
              F3 = seq(.70, .56, length.out = dims[["F3"]]))
  blocks <- lapply(names(dims), function(f) {
    L <- lam[[f]]
    outer(eta[, f], L) + matrix(rnorm(n * length(L)), n, length(L)) * rep(sqrt(pmax(1 - L^2, .10)), each = n)
  })
  y <- do.call(cbind, blocks)
  x <- as.data.frame(lapply(seq_len(ncol(y)), function(j) ordinalise(y[, j], c(-.85, -.25, .25, .85))))
  names(x) <- sprintf("Item%02d", seq_len(ncol(x)))
  rev_items <- c("Item07", "Item15")                    # 反向计分题：先正向生成再物理反向
  for (nm in rev_items) x[[nm]] <- 6L - x[[nm]]
  miss <- matrix(runif(n * ncol(x)) < .015, n, ncol(x)); x[miss] <- NA
  attention <- rep(3L, n); bad <- sample.int(n, round(.03 * n))
  attention[bad] <- sample(c(1L, 2L, 4L, 5L), length(bad), TRUE)
  rtime <- round(pmax(20, rlnorm(n, log(190), .38)), 1)
  fast <- sample.int(n, round(.02 * n)); rtime[fast] <- round(runif(length(fast), 12, 40), 1)
  criterion <- .55 * eta[, 1] + .25 * eta[, 2] + rnorm(n, 0, .75)
  grp <- factor(ifelse(eta[, 1] + rnorm(n, 0, .6) > 0, "High", "Low"))
  full <- data.frame(participant_id = sprintf("P%03d", seq_len(n)), x,
                     attention_check = attention, response_time_sec = rtime,
                     criterion = round(as.numeric(criterion), 3), known_group = grp,
                     check.names = FALSE)
  w(full, "ctt_B_full_survey_n500_items20.csv")
  w(data.frame(item = names(x),
               dimension = rep(names(dims), unlist(dims)),
               true_loading = round(unlist(lam), 3),
               reverse_keyed = ifelse(names(x) %in% rev_items, "yes", "")), "ctt_B_truth.csv")
  w(data.frame(item = names(x), dimension = rep(names(dims), unlist(dims))), "ctt_B_cfa_mapping.csv")
  wcfg(c(
    "# CTT-B：完整问卷（500 人 × 20 题 × 3 维；含 2 道反向题、注意检验、反应时、效标、已知组、1.5% 缺失）",
    "# 注意：务必声明 attention_item 与 response_time_column，否则注意检验题会被当成量表题目纳入分析",
    "input:",
    "  mode: file",
    "  path: \"./ctt_B_full_survey_n500_items20.csv\"",
    "  id_column: participant_id",
    "  item_columns: [Item01, Item02, Item03, Item04, Item05, Item06, Item07, Item08, Item09, Item10,",
    "                 Item11, Item12, Item13, Item14, Item15, Item16, Item17, Item18, Item19, Item20]",
    "cleaning:",
    "  scale_maximum: 5",
    "  reverse_items: [Item07, Item15]",
    "  missing_5_to_20: median_impute",
    "  attention_item: attention_check",
    "  attention_correct_value: 3",
    "  response_time_column: response_time_sec",
    "  minimum_response_seconds: 45",
    "  straightline_action: flag",
    "  extreme_action: flag",
    "analysis:",
    "  goal: cfa                      # 换成 efa 可探索结构；quality 只做质量检查",
    "  cfa_mapping: \"./ctt_B_cfa_mapping.csv\"",
    "  criterion_column: criterion",
    "  criterion_direction: positive",
    "  known_group_column: known_group",
    "output:",
    "  directory: \"../../outputs\"",
    "  project_label: ctt_B",
    "  report_language: zh"
  ), "ctt_B_config.yaml")
}

## C：问题数据——坏题 + 各类脏作答，用来观察清洗与"建议删题"
make_ctt_C <- function() {
  set.seed(SEED + 3L); n <- 400L; k <- 16L
  r <- .45
  theta1 <- rnorm(n); theta2 <- r * theta1 + sqrt(1 - r^2) * rnorm(n)
  lam1 <- seq(.72, .55, length.out = 8); lam2 <- seq(.70, .55, length.out = 8)
  y <- cbind(
    outer(theta1, lam1) + matrix(rnorm(n * 8), n, 8) * rep(sqrt(1 - lam1^2), each = n),
    outer(theta2, lam2) + matrix(rnorm(n * 8), n, 8) * rep(sqrt(1 - lam2^2), each = n))
  y[, 7]  <- .10 * theta1 + rnorm(n, 0, .99)                    # Item07：低载荷
  y[, 8]  <- .45 * theta1 + .42 * theta2 + rnorm(n, 0, .72)     # Item08：双重载荷
  y[, 16] <- .28 * theta2 + rnorm(n, 0, .96)                    # Item16：载荷偏低
  x <- as.data.frame(lapply(seq_len(k), function(j) ordinalise(y[, j], c(-.85, -.25, .25, .85))))
  names(x) <- sprintf("Item%02d", seq_len(k))
  mid <- sample.int(n, 12)                                      # 12 人 5–20% 缺失
  for (i in mid) { j <- sample.int(k, sample(1:3, 1)); x[i, j] <- NA }
  hi <- sample(setdiff(seq_len(n), mid), 5)                     # 5 人 >20% 缺失
  for (i in hi) { j <- sample.int(k, sample(4:7, 1)); x[i, j] <- NA }
  attention <- rep(3L, n); af <- sample.int(n, 18); attention[af] <- sample(c(1L, 2L, 4L, 5L), 18, TRUE)
  rtime <- round(pmax(20, rlnorm(n, log(180), .40)), 1); tf <- sample.int(n, 15)
  rtime[tf] <- round(runif(15, 10, 40), 1)
  straight <- sample(setdiff(seq_len(n), c(mid, hi)), 20)       # 20 人直线作答
  for (i in straight) x[i, ] <- sample(1:5, 1)
  full <- data.frame(participant_id = sprintf("S%03d", seq_len(n)), x,
                     attention_check = attention, response_time_sec = rtime, check.names = FALSE)
  w(full, "ctt_C_problem_items_n400_items16.csv")
  w(data.frame(item = names(x),
               dimension = c(rep("F1", 6), "问题题", "问题题", rep("F2", 7), "问题题"),
               note = c(rep("正常题", 6), "Item07 与所有题几乎无关（低载荷/低共同度）",
                        "Item08 同时载荷 F1 与 F2（双重载荷）", rep("正常题", 7),
                        "Item16 载荷偏低")), "ctt_C_truth.csv")
  wcfg(c(
    "# CTT-C：问题数据（400 人 × 16 题；含 1 道无关题、1 道双重载荷题、1 道低载荷题 + 各类脏作答）",
    "# 预期：清洗报告显示注意检验失败/过快作答/高缺失被删除（直线作答与极端值只标记）；",
    "#       EFA 给出 suggest_delete 建议清单（Item07 / Item08 / Item16），但**不会自动删题**。",
    "input:",
    "  mode: file",
    "  path: \"./ctt_C_problem_items_n400_items16.csv\"",
    "  id_column: participant_id",
    "  item_columns: [Item01, Item02, Item03, Item04, Item05, Item06, Item07, Item08, Item09, Item10,",
    "                 Item11, Item12, Item13, Item14, Item15, Item16]",
    "cleaning:",
    "  scale_maximum: 5",
    "  reverse_items: []",
    "  missing_5_to_20: median_impute",
    "  attention_item: attention_check",
    "  attention_correct_value: 3",
    "  response_time_column: response_time_sec",
    "  minimum_response_seconds: 45",
    "  straightline_action: flag",
    "  extreme_action: flag",
    "analysis:",
    "  goal: efa",
    "  rotation: promax",
    "  n_factors: auto",
    "output:",
    "  directory: \"../../outputs\"",
    "  project_label: ctt_C",
    "  report_language: zh"
  ), "ctt_C_config.yaml")
}

## ============================================================ IRT 数据集 ====
## IRT 配置模板：path 必须落在 input 段内
irt_config <- function(path, model, note, extra_input = character(), extra_analysis = character(),
                       mirt_mode = "eifa", missing = "none") {
  c(note,
    "# 用法：Rscript scripts/irt_generic_pipeline.R --config examples/simulated_datasets/<本文件>",
    "input:",
    "  mode: file",
    paste0("  path: \"", path, "\""),
    "  item_columns: auto",
    paste0("  missing: ", missing, "            # none 与 pairwise 等价；listwise 会先删人"),
    extra_input,
    "analysis:",
    paste0("  model: ", model),
    paste0("  mirt_mode: ", mirt_mode),
    "  selection_criterion: BIC",
    "  compute_m2: true",
    extra_analysis,
    "output:",
    "  directory: \"../../outputs\"",
    "  report_languages: [zh, en]",
    "  save_model_object: true")
}

## A：二分 2PL（N=800，20 题）——最典型的 IRT 入门数据
make_irt_A <- function() {
  set.seed(SEED + 11L); n <- 800L; k <- 20L
  a <- round(runif(k, .8, 2.0), 3); b <- round(runif(k, -2, 2), 3)
  theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(matrix(theta), a[j], b[j])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_A_binary_2pl_n800_items20.csv")
  w(data.frame(Item = names(x), a = a, b = b), "irt_A_truth.csv")
  w(data.frame(Row = seq_len(n), Theta = round(theta, 4)), "irt_A_true_theta.csv")
  wcfg(irt_config("./irt_A_binary_2pl_n800_items20.csv", "auto",
    "# IRT-A：二分 2PL 数据（800 人 × 20 题，真值 a∈[0.8,2.0]、b∈[-2,2]）"),
    "irt_A_config.yaml")
}

## B：有序多级 GRM（N=600，15 题，1–5 计分）
make_irt_B <- function() {
  set.seed(SEED + 12L); n <- 600L; k <- 15L
  a <- round(runif(k, .9, 1.9), 3)
  B <- t(replicate(k, sort(round(runif(4, -2.2, 2.2), 3))))
  theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_grm(matrix(theta), a[j], B[j, ])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_B_polytomous_grm_n600_items15.csv")
  truth <- data.frame(Item = names(x), a = a, B, check.names = FALSE)
  names(truth)[3:6] <- sprintf("b%d", 1:4)
  w(truth, "irt_B_truth.csv")
  w(data.frame(Row = seq_len(n), Theta = round(theta, 4)), "irt_B_true_theta.csv")
  wcfg(irt_config("./irt_B_polytomous_grm_n600_items15.csv", "gpcm",
    "# IRT-B（GPCM 版）：同一份多级数据改用 GPCM（Muraki 1992 相邻类别 logit）拟合",
    "# 教学点：Likert 数据 GRM 与 GPCM 都合理，用 BIC 比较；两者对同一份数据的台阶参数口径不同",
    extra_analysis = "  compare_models: [grm, gpcm]   # 一次拟合两个模型并比较"),
    "irt_B_config_gpcm.yaml")
  wcfg(irt_config("./irt_B_polytomous_grm_n600_items15.csv", "grm",
    "# IRT-B：有序多级 GRM 数据（600 人 × 15 题，1–5 计分，每题 4 个阈值）"),
    "irt_B_config.yaml")
}

## C：二维 GRM（N=1000，24 题，每维 12 题）——演示 EIFA 选维与 CIFA 验证
make_irt_C <- function() {
  set.seed(SEED + 13L); n <- 1000L; k <- 24L
  owner <- rep(1:2, each = k / 2)
  A <- matrix(round(runif(k * 2, 0, .20), 3), k, 2)
  A[cbind(seq_len(k), owner)] <- round(runif(k, .9, 1.7), 3)
  B <- t(replicate(k, sort(round(runif(4, -2.2, 2.2), 3))))
  theta <- MASS::mvrnorm(n, mu = c(0, 0), Sigma = matrix(c(1, .45, .45, 1), 2, 2))
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_grm(theta, A[j, ], B[j, ])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_C_multidimensional_grm_n1000_items24.csv")
  truth <- data.frame(Item = names(x), a1 = A[, 1], a2 = A[, 2],
                      primary_dimension = paste0("F", owner), B, check.names = FALSE)
  names(truth)[5:8] <- sprintf("b%d", 1:4)
  w(truth, "irt_C_truth.csv")
  w(data.frame(item = names(x), dimension = paste0("F", owner)), "irt_C_loading_matrix.csv")
  w(data.frame(Row = seq_len(n), F1 = round(theta[, 1], 4), F2 = round(theta[, 2], 4)), "irt_C_true_theta.csv")
  # 给两份配置：EIFA（探索，按 BIC 选维度）与 CIFA（按载荷矩阵验证 2 维结构）
  wcfg(irt_config("./irt_C_multidimensional_grm_n1000_items24.csv", "mirt",
    "# IRT-C（探索路线 EIFA）：二维 GRM 数据（1000 人 × 24 题，每维 12 题；维度间相关 .45）",
    extra_analysis = "  dimension_range: 1-3       # 试 1..3 维，按 BIC 选维度",
    mirt_mode = "eifa"),
    "irt_C_config_eifa.yaml")
  wcfg(irt_config("./irt_C_multidimensional_grm_n1000_items24.csv", "mirt",
    "# IRT-C（验证路线 CIFA）：按 irt_C_loading_matrix.csv 验证 2 维结构，并与单维模型比较",
    extra_analysis = "  loading_matrix: \"./irt_C_loading_matrix.csv\"",
    mirt_mode = "cifa"),
    "irt_C_config_cifa.yaml")
}

## D：带缺失的二分数据（5% MCAR）——演示三种缺失策略
make_irt_D <- function() {
  set.seed(SEED + 14L); n <- 800L; k <- 20L
  a <- round(runif(k, .8, 2.0), 3); b <- round(runif(k, -2, 2), 3)
  theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(matrix(theta), a[j], b[j])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  # 用矩阵索引设置缺失（data.frame 的单个整数索引会被当成列索引，故先转矩阵）
  m <- as.matrix(x)
  idx <- sample(length(m), floor(.05 * length(m)))
  m[idx] <- NA
  x <- as.data.frame(m)
  w(x, "irt_D_binary_missing5pct_n800_items20.csv")
  w(data.frame(Item = names(x), a = a, b = b), "irt_D_truth.csv")
  for (strategy in c("none", "listwise", "pairwise")) {
    wcfg(irt_config("./irt_D_binary_missing5pct_n800_items20.csv", "2pl",
      sprintf("# IRT-D：含 5%% 随机缺失的二分数据（800 人 × 20 题）——缺失策略：%s", strategy),
      missing = strategy),
      sprintf("irt_D_config_missing_%s.yaml", strategy))
  }
}

## E：真 Rasch（a 恒为 1，N=500，15 题）——演示"真模型能否被 BIC 选出来"
make_irt_E <- function() {
  set.seed(SEED + 15L); n <- 500L; k <- 15L
  b <- round(runif(k, -2.5, 2.5), 3); theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(matrix(theta), 1, b[j])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_E_rasch_n500_items15.csv")
  w(data.frame(Item = names(x), a = 1, b = b), "irt_E_truth.csv")
  w(data.frame(Row = seq_len(n), Theta = round(theta, 4)), "irt_E_true_theta.csv")
  wcfg(irt_config("./irt_E_rasch_n500_items15.csv", "auto",
    "# IRT-E：真 Rasch 数据（500 人 × 15 题，所有题目区分度 a = 1）",
    extra_analysis = "  compare_models: [rasch, 2pl]   # 教学点：真模型是 Rasch 时 BIC 应偏向 rasch"),
    "irt_E_config.yaml")
}

## F：数据体检演示（故意含零方差题、全缺失题、稀有类别、高缺失）
make_irt_F <- function() {
  set.seed(SEED + 16L); n <- 200L; k <- 9L
  theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(matrix(theta), runif(1, .9, 1.8), runif(1, -1.5, 1.5))))
  names(x) <- sprintf("Item%02d", seq_len(k))
  miss <- matrix(runif(n * k) < .06, n, k); x[miss] <- NA       # 正常题 6% 缺失
  x$Item10 <- 1L                                                # 零方差：全部答对
  x$Item11 <- 1L; x$Item11[sample.int(n, 3)] <- 0L              # 稀有类别：仅 3 人答 0
  x$Item12 <- NA_integer_                                       # 整题全缺失
  w(x, "irt_F_preflight_problems_n200_items12.csv")
  wcfg(c("# IRT-F：数据体检演示（故意含 1 道零方差题 Item10、1 道全缺失题 Item12、1 道稀有类别题 Item11）",
         "# 重要：item_columns 用 auto 时，零方差列与全缺失列会被“自动识别”直接排除（不报致命错误）；",
         "#       只有**显式列出题目列**，体检才会把零方差/全缺失判为 fatal —— 两个配置都在本目录，可对比。",
         "# 用法：先跑  Rscript scripts/irt_preflight.R --config examples/simulated_datasets/irt_F_config.yaml",
         "input:",
         "  mode: file",
         "  path: \"./irt_F_preflight_problems_n200_items12.csv\"",
         "  missing: none",
         "analysis:",
         "  model: 2pl",
         "output:",
         "  directory: \"../../outputs\"",
         "  project_label: irt_F"), "irt_F_config.yaml")
  wcfg(c("# IRT-F（显式题目列版）：把 12 列全部声明为题目，用于观察数据体检的 fatal 判定",
         "# 预期：Item10（零方差）与 Item12（全缺失）触发 fatal，体检阻止拟合",
         "input:",
         "  mode: file",
         "  path: \"./irt_F_preflight_problems_n200_items12.csv\"",
         "  item_columns: [Item01, Item02, Item03, Item04, Item05, Item06, Item07, Item08, Item09, Item10,",
         "                 Item11, Item12]",
         "  missing: none",
         "analysis:",
         "  model: 2pl",
         "output:",
         "  directory: \"../../outputs\"",
         "  project_label: irt_F_explicit"), "irt_F_config_explicit_items.yaml")
}

## D：三因子近似正交结构（N=700，18 题 = 3 维 × 6 题）
##     现有三份 CTT 数据都是 promax 斜交 + 因子数 auto，本数据专为**没被覆盖的两个键**准备：
##     `rotation: varimax`（正交旋转）与 `n_factors: 3`（手动指定因子数）。
make_ctt_D <- function() {
  set.seed(SEED + 4L); n <- 700L
  dims <- c(F1 = 6L, F2 = 6L, F3 = 6L)
  phi <- matrix(c(1, .18, .12, .18, 1, .15, .12, .15, 1), 3, 3)   # 近似正交，与 varimax 假设一致
  eta <- MASS::mvrnorm(n, mu = rep(0, 3), Sigma = phi); colnames(eta) <- names(dims)
  lam <- list(F1 = seq(.78, .60, length.out = 6L),
              F2 = seq(.76, .58, length.out = 6L),
              F3 = seq(.74, .57, length.out = 6L))
  blocks <- lapply(names(dims), function(f) {
    L <- lam[[f]]
    outer(eta[, f], L) + matrix(rnorm(n * length(L)), n, length(L)) * rep(sqrt(pmax(1 - L^2, .10)), each = n)
  })
  y <- do.call(cbind, blocks)
  x <- as.data.frame(lapply(seq_len(ncol(y)), function(j) ordinalise(y[, j], c(-.85, -.25, .25, .85))))
  names(x) <- sprintf("Item%02d", seq_len(ncol(x)))
  w(x, "ctt_D_three_factor_n700_items18.csv")
  w(data.frame(item = names(x), dimension = rep(names(dims), unlist(dims)),
               true_loading = round(unlist(lam), 3)), "ctt_D_truth.csv")
  wcfg(c(
    "# CTT-D：三因子近似正交结构（700 人 × 18 题，5 点计分，无缺失、无反向题）",
    "# 教学点：结构近似正交时用 varimax；因子数由设计确定，故直接写死 3（不靠平行分析）",
    "# 用法：Rscript scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_D_config.yaml",
    "input:",
    "  mode: file",
    "  path: \"./ctt_D_three_factor_n700_items18.csv\"",
    "  id_column: null",
    "  item_columns: auto",
    "cleaning:",
    "  scale_maximum: 5",
    "  reverse_items: []",
    "  missing_5_to_20: median_impute",
    "analysis:",
    "  goal: efa",
    "  rotation: varimax              # 正交旋转：因子间相关很小时比 promax 更易解释",
    "  n_factors: 3                   # 手动指定：设计上就是 3 个因子",
    "output:",
    "  directory: \"../../outputs\"",
    "  project_label: ctt_D",
    "  report_language: zh"
  ), "ctt_D_config.yaml")
}

## E：脏作答「真的删掉」+ 负向效标（N=450，15 题）
##     现有 CTT 数据里 straightline_action / extreme_action 全是 flag（只标记不删）、
##     criterion_direction 全是 positive，本数据专为 `remove` 与 `negative` 两条分支准备。
make_ctt_E <- function() {
  # 这份数据的载荷**刻意做低**（.18–.48，α ≈ .65），为的是让极端值规则真的能命中。
  # 原因：k 题 K 点量表上，总分 |z| 的理论上限约为 2/sqrt(2·r̄)（r̄ = 题间平均相关）。
  # 只要 α ≥ .70（r̄ ≳ .15），上限就只有 ~3.0，而离群个案自己还会把 SD 抬高，
  # 于是 |z|>3 在 15 题 5 点量表上**几乎不可能触发**；IQR 上界也会超过满分。
  # 沿用其他数据集的 .55–.78 时实测：SD = 13.4、|z| 上界 91、IQR 上界 91.5（满分才 75）
  # → `extreme_action: remove` 这条分支一个都删不掉，等于没被测到。
  set.seed(SEED + 5L); n <- 800L; k <- 15L
  lambda <- seq(.48, .18, length.out = k)
  theta <- rnorm(n)
  y <- outer(theta, lambda) + matrix(rnorm(n * k), n, k) * rep(sqrt(pmax(1 - lambda^2, .10)), each = n)
  x <- as.data.frame(lapply(seq_len(k), function(j) ordinalise(y[, j], c(-.85, -.25, .25, .85))))
  names(x) <- sprintf("Item%02d", seq_len(k))
  ## 注入脏作答（人数写进真值文件，便于核对清洗是否删对了人）
  ## 两组脏作答刻意设计成**互不干扰**，便于分别核对"删对了谁"：
  ## 直线作答整卷同选 3（总分落在均值附近，不会被极端值规则重复命中）；
  ## 极端作答整卷 4/5 堆叠（总分离群，会被 |z|>3 与 1.5×IQR 同时命中）。
  ## 早先版本让 24 人一半全 5、一半全 1，把总分 SD 从 ~6.5 抬到 15，
  ## 结果 z>3 的门槛变成 91 分、IQR 上界 91.5——两种规则一个都没命中，remove 分支等于没被测到。
  straight <- sample.int(n, 24L)
  for (i in straight) x[i, ] <- 3L
  extreme <- setdiff(sample.int(n, 80L), straight)[seq_len(10L)]
  for (i in extreme) { v <- rep(5L, k); v[sample.int(k, 2L)] <- 4L; x[i, ] <- v }
  miss <- matrix(runif(n * k) < .02, n, k); x[miss] <- NA           # 2% 随机缺失
  attention <- rep(3L, n); bad <- sample.int(n, 25L)                # 注意检验失败 25 人
  attention[bad] <- sample(c(1L, 2L, 4L, 5L), 25L, TRUE)
  rtime <- round(pmax(20, rlnorm(n, log(185), .38)), 1)
  fast <- sample.int(n, 20L); rtime[fast] <- round(runif(20L, 12, 40), 1)   # 过快作答 20 人
  criterion <- -.55 * theta + rnorm(n, 0, .8)                       # 负向效标：量表分越高、效标越低
  grp <- factor(ifelse(theta + rnorm(n, 0, .6) > 0, "High", "Low"))
  full <- data.frame(participant_id = sprintf("E%03d", seq_len(n)), x,
                     attention_check = attention, response_time_sec = rtime,
                     criterion = round(as.numeric(criterion), 3), known_group = grp,
                     check.names = FALSE)
  w(full, "ctt_E_dirty_remove_n800_items15.csv")
  w(data.frame(item = names(x), dimension = "F1", true_loading = round(lambda, 3),
               injected_dirty = c(sprintf("straightline n=%d", length(straight)),
                                  sprintf("extreme n=%d", length(extreme)),
                                  sprintf("attention_fail n=%d", length(bad)),
                                  sprintf("too_fast n=%d", length(fast)),
                                  sprintf("missing_cells n=%d", sum(miss)),
                                  rep("", k - 5L))), "ctt_E_truth.csv")
  wcfg(c(
    "# CTT-E：脏作答「处理而非仅标记」（800 人 × 15 题，5 点计分）",
    "# 教学点：straightline/extreme 都设为 remove（真的删人并报告删了几人），",
    "#         效标为**负向**（criterion_direction: negative），看方向判断是否正确",
    "# 用法：Rscript scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_E_config.yaml",
    "input:",
    "  mode: file",
    "  path: \"./ctt_E_dirty_remove_n800_items15.csv\"",
    "  id_column: participant_id",
    "  item_columns: auto",
    "cleaning:",
    "  scale_maximum: 5",
    "  reverse_items: []",
    "  missing_5_to_20: median_impute",
    "  attention_item: attention_check",
    "  attention_correct_value: 3",
    "  response_time_column: response_time_sec",
    "  minimum_response_seconds: 45",
    "  straightline_action: remove    # flag（默认，只标记）| remove（直接删人）",
    "  extreme_action: remove         # flag（默认，只标记）| remove（直接删人）",
    "analysis:",
    "  goal: quality                  # 质量检查路线：清洗 + 项目分析 + 信度 + 效标/已知组效度",
    "  criterion_column: criterion",
    "  criterion_direction: negative  # positive（默认）| negative",
    "  known_group_column: known_group",
    "output:",
    "  directory: \"../../outputs\"",
    "  project_label: ctt_E",
    "  report_language: zh"
  ), "ctt_E_config.yaml")
}

## G：三维 GPCM（MGPCM，N=900，24 题 = 3 维 × 8 题，1–5 计分）
##     此前全仓库没有任何一份可直接试跑的**多维 GPCM** 数据，而这条路径曾因
##     irt_common.R 的校验白名单漏列 gpcm 而完全不可用（选了就报错退出）。
make_irt_G <- function() {
  set.seed(SEED + 17L); n <- 900L; d <- 3L; per <- 8L; k <- d * per
  phi <- matrix(c(1, .40, .30, .40, 1, .35, .30, .35, 1), d, d)
  theta <- matrix(rnorm(n * d), n, d) %*% chol(phi)
  owner <- rep(seq_len(d), each = per)
  A <- matrix(0, k, d)
  for (j in seq_len(k)) {
    A[j, owner[j]] <- round(runif(1, .9, 1.9), 3)
    A[j, -owner[j]] <- round(runif(d - 1L, 0, .18), 3)      # 小交叉载荷
  }
  B <- t(replicate(k, sort(round(runif(4, -2.0, 2.0), 3))))
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_gpcm(theta, A[j, ], B[j, ])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_G_multidimensional_gpcm_n900_items24.csv")
  truth <- data.frame(Item = names(x), dimension = paste0("F", owner),
                      a_primary = round(apply(A, 1L, function(z) sqrt(sum(z^2))), 3),
                      check.names = FALSE)
  truth <- cbind(truth, B); names(truth)[4:7] <- sprintf("b%d", 1:4)
  w(truth, "irt_G_truth.csv")
  w(data.frame(item = names(x), dimension = paste0("F", owner)), "irt_G_loading_matrix.csv")
  w(data.frame(Row = seq_len(n), F1 = round(theta[, 1], 4), F2 = round(theta[, 2], 4),
               F3 = round(theta[, 3], 4)), "irt_G_true_theta.csv")
  wcfg(irt_config("./irt_G_multidimensional_gpcm_n900_items24.csv", "mirt",
    "# IRT-G（探索路线 EIFA）：三维 GPCM 数据（900 人 × 24 题，1–5 计分）",
    extra_analysis = "  mirt_item_model: gpcm   # 显式指定多维 GPCM（MGPCM）"),
    "irt_G_config_eifa.yaml")
  wcfg(irt_config("./irt_G_multidimensional_gpcm_n900_items24.csv", "mirt",
    "# IRT-G（验证路线 CIFA）：按 irt_G_loading_matrix.csv 验证 3 维结构",
    extra_analysis = paste0("  mirt_item_model: gpcm\n  loading_matrix: \"./irt_G_loading_matrix.csv\""),
    mirt_mode = "cifa"),
    "irt_G_config_cifa.yaml")
}

## H：二分 3PL（N=1500，20 题，含猜测参数 c∈[0.08,0.25]）
##     现有 IRT 数据没有一份带猜测参数；3PL 是「标准化选择题」场景的标准模型。
make_irt_H <- function() {
  set.seed(SEED + 18L); n <- 1500L; k <- 20L
  a <- round(runif(k, .8, 2.0), 3); b <- round(runif(k, -2, 2), 3); g <- round(runif(k, .08, .25), 3)
  theta <- rnorm(n)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(matrix(theta), a[j], b[j], g[j])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_H_binary_3pl_n1500_items20.csv")
  w(data.frame(Item = names(x), a = a, b = b, c = g), "irt_H_truth.csv")
  w(data.frame(Row = seq_len(n), Theta = round(theta, 4)), "irt_H_true_theta.csv")
  wcfg(irt_config("./irt_H_binary_3pl_n1500_items20.csv", "3pl",
    "# IRT-H：二分 3PL 数据（1500 人 × 20 题，猜测参数 c∈[0.08,0.25]）",
    extra_analysis = "  compare_models: [2pl, 3pl]   # 教学点：真有猜测时 3PL 的 BIC 应优于 2PL"),
    "irt_H_config.yaml")
  wcfg(irt_config("./irt_H_binary_3pl_n1500_items20.csv", "2pl",
    "# IRT-H（对照组）：同一份数据**故意只按 2PL 拟合**，用来看忽略猜测参数会把难度估偏多少",
    extra_analysis = "  compare_models: [2pl]"),
    "irt_H_config_ignore_guess.yaml")
}

## I：二维二分 M2PL（N=800，20 题 = 2 维 × 10 题）
##     现有唯一的 MIRT 数据 IRT-C 是多级 GRM；二分多维（M2PL）此前没有数据。
make_irt_I <- function() {
  set.seed(SEED + 19L); n <- 800L; d <- 2L; per <- 10L; k <- d * per
  theta <- matrix(rnorm(n * d), n, d) %*% chol(matrix(c(1, .45, .45, 1), d, d))
  owner <- rep(seq_len(d), each = per)
  A <- matrix(0, k, d)
  for (j in seq_len(k)) {
    A[j, owner[j]] <- round(runif(1, .9, 2.0), 3)
    A[j, -owner[j]] <- round(runif(1, 0, .20), 3)
  }
  b <- round(runif(k, -1.8, 1.8), 3)
  x <- as.data.frame(sapply(seq_len(k), function(j) sim_binary(theta, A[j, ], b[j])))
  names(x) <- sprintf("Item%02d", seq_len(k))
  w(x, "irt_I_multidimensional_binary_n800_items20.csv")
  truth <- data.frame(Item = names(x), dimension = paste0("F", owner), b = b,
                      a_primary = round(apply(A, 1L, function(z) sqrt(sum(z^2))), 3),
                      check.names = FALSE)
  w(truth, "irt_I_truth.csv")
  w(data.frame(item = names(x), dimension = paste0("F", owner)), "irt_I_loading_matrix.csv")
  w(data.frame(Row = seq_len(n), F1 = round(theta[, 1], 4), F2 = round(theta[, 2], 4)), "irt_I_true_theta.csv")
  wcfg(irt_config("./irt_I_multidimensional_binary_n800_items20.csv", "mirt",
    "# IRT-I（探索路线 EIFA）：二维二分数据（800 人 × 20 题，0/1 计分）",
    extra_analysis = "  mirt_item_model: 2pl   # 显式指定多维 2PL（M2PL）"),
    "irt_I_config_eifa.yaml")
  wcfg(irt_config("./irt_I_multidimensional_binary_n800_items20.csv", "mirt",
    "# IRT-I（验证路线 CIFA）：按 irt_I_loading_matrix.csv 验证 2 维结构",
    extra_analysis = paste0("  mirt_item_model: 2pl\n  loading_matrix: \"./irt_I_loading_matrix.csv\""),
    mirt_mode = "cifa"),
    "irt_I_config_cifa.yaml")
}

## ------------------------------------------------------------------ 主流程 ----
say("\n[CTT]"); make_ctt_A(); make_ctt_B(); make_ctt_C(); make_ctt_D(); make_ctt_E()
say("\n[IRT]"); make_irt_A(); make_irt_B(); make_irt_C(); make_irt_D(); make_irt_E(); make_irt_F()
say("\n[IRT 追加]"); make_irt_G(); make_irt_H(); make_irt_I()
say("\n完成：数据、真值与配置文件已写入 %s", OUT)
say("详细说明见：%s", file.path(OUT, "README_模拟数据说明.md"))
