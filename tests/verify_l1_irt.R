#!/usr/bin/env Rscript
# =============================================================================
# IRT 输出 L1「可解析性质」复算脚本
# -----------------------------------------------------------------------------
# 用途：读一个（或多个）IRT 结果目录，用**教科书闭式公式**从原始数据/参数表独立复算
#       工具输出的若干量，逐条打印 PASS / FAIL / SKIP。
#
# 为什么需要它：IRT 分支的计算引擎是 mirt，用 mirt 去验证 mirt 是同义反复。
# 本脚本只依赖：
#   ① 参数表里的 a/d/g（mirt 的斜率—截距形式原始值）
#   ② 教科书公式（Samejima 1969 GRM、Muraki 1992 GPCM、Birnbaum 2PL/3PL、Fisher 信息量）
# 因此它是一次**独立复算**，而不是把包再跑一遍。
#
# 用法（Windows PowerShell 里必须用位置参数，Rscript -f 在本机会崩）：
#   Rscript --vanilla tests\verify_l1_irt.R outputs\irt_analysis_2pl_2026xxxx
#   Rscript --vanilla tests\verify_l1_irt.R outputs\irt_analysis_2pl_* outputs\irt_analysis_3pl_*
#
# 退出码：全部非 SKIP 的检查通过 → 0；有 FAIL → 1
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("用法：Rscript --vanilla tests/verify_l1_irt.R <结果目录> [更多结果目录...]")

OK <- TRUE
n_pass <- 0L; n_fail <- 0L; n_skip <- 0L
say  <- function(...) cat(sprintf(...), "\n", sep = "")
good <- function(nm, cond, detail = "") {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("[PASS]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
  else { n_fail <<- n_fail + 1L; OK <<- FALSE; cat("[FAIL]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
}
skip <- function(nm, why) { n_skip <<- n_skip + 1L; cat("[SKIP]", nm, "--", why, "\n") }
info <- function(nm, detail) cat("[INFO]", nm, "--", detail, "\n")
pick <- function(dir, suffix) { f <- list.files(dir, pattern = suffix, full.names = TRUE); if (length(f)) f[1L] else NA_character_ }
rd   <- function(f) utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE)
num  <- function(x) suppressWarnings(as.numeric(x))
sig  <- function(z) 1 / (1 + exp(-z))                 # logistic
relmax <- function(a, b) max(abs(a - b)) / max(1e-12, max(abs(b)))

## ── 题目匹配：按"数字键"对齐，而不是字符串相等 ─────────────────────────────
## 工具在 CIFA（多维）路线内部用安全名拟合，历史版本把 Item1… 直接写进了
## icc_data / iif_data / tif_data / item_fit / cifa_loading_significance，
## 而参数表写 Item01…。字符串相等匹配会让 Item1..Item9 静默失配、检查假装通过。
## 这里用数字键（Item01 ↔ Item1）对齐；两边都没有数字时退回字符串精确匹配；
## 都匹配不上则返回 NULL —— 调用方必须判为 FAIL，不得静默跳过。
ikey <- function(v) suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(v))))
prow <- function(pars, item) {
  k <- ikey(item)
  i <- if (!is.na(k)) match(k, ikey(pars$Item)) else NA_integer_
  if (is.na(i)) i <- match(as.character(item), as.character(pars$Item))
  if (is.na(i)) return(NULL)
  pars[i, , drop = FALSE]
}

## ── 模型判定：只依据参数表的列结构（不读包内部对象）────────────────────────
classify <- function(pars) {
  is_gpcm_family <- any(grepl("^ak[0-9]+$", names(pars)))
  is_dich <- "d" %in% names(pars) && !any(grepl("^d[0-9]+$", names(pars)))
  if (is_dich) return(if (is_gpcm_family) "dichotomous" else "dichotomous")
  if (is_gpcm_family) "gpcm" else "graded"
}
acols_of <- function(pars) grep("^a[0-9]+$", names(pars), value = TRUE)
dcols_of <- function(pars) {
  d <- grep("^d[0-9]+$", names(pars), value = TRUE)
  if (!length(d) && "d" %in% names(pars)) d <- "d"
  d[order(as.integer(sub("^d", "", ifelse(d == "d", "0", d))))]        # d, d0, d1, d2 ...
}

## ── 闭式：某题在 θ（其余维度固定为 0）下各类别的概率 ──────────────────────
## 返回长度 K 的向量，索引 1..K 对应工具 icc_data 里的 Category "1".."K"
probs_closed <- function(kind, pars, item, theta, adim) {
  rw <- prow(pars, item); if (is.null(rw)) return(NULL)
  ar <- num(rw[[adim]]); if (!length(ar) || is.na(ar)) return(NULL)
  eta <- ar * theta
  if (kind == "dichotomous") {
    dr <- num(rw[["d"]]); g <- if ("g" %in% names(rw)) num(rw[["g"]]) else 0
    if (!is.finite(g)) g <- 0
    p1 <- g + (1 - g) * sig(eta + dr)
    return(c(1 - p1, p1))
  }
  dc <- dcols_of(pars); dvals <- num(unlist(rw[dc]))
  if (kind == "graded") {
    # d 列是 d1..d_{K-1}（不含 d0）；P(X>=k) = sig(eta + d_k)，P(X>=0) = 1
    surv <- c(1, sig(eta + dvals))                       # 长度 K
    return(c(surv[-length(surv)] - surv[-1], surv[length(surv)]))
  }
  # gpcm：d0..d_{K-1}，P(X=k) ∝ exp(k*eta + d_k)
  k <- seq_along(dvals) - 1L
  ex <- exp(k * eta + dvals); ex / sum(ex)
}

## ── 闭式：题目信息函数 I(θ) = Σ_k (P_k')² / P_k（解析导数，不用数值差分）──
info_closed <- function(kind, pars, item, theta, adim) {
  rw <- prow(pars, item); if (is.null(rw)) return(NULL)
  ar <- num(rw[[adim]]); if (!length(ar) || is.na(ar)) return(NULL)
  eta <- ar * theta
  if (kind == "dichotomous") {
    dr <- num(rw[["d"]]); g <- if ("g" %in% names(rw)) num(rw[["g"]]) else 0
    if (!is.finite(g)) g <- 0
    s <- sig(eta + dr); p1 <- g + (1 - g) * s; p0 <- 1 - p1
    dp1 <- (1 - g) * s * (1 - s) * ar
    return(dp1^2 / p1 + dp1^2 / p0)
  }
  dc <- dcols_of(pars); dvals <- num(unlist(rw[dc]))
  if (kind == "graded") {
    # Samejima(1969) 的题目信息定义式：I(θ) = Σ_k [P_k'(θ)]² / P_k(θ)。
    # 注意 P_k = S_k − S_{k+1}（S_k = P(X≥k) = σ(η+d_k)）：两个相邻累积函数相减之后
    # **不存在** Σ_k [S_k']²/(S_k(1−S_k)) 这类"等价式"。本文件早先用该式，实测把 GRM 的
    # I(θ) 系统性放大约 2 倍、虚报 191% 的失败；对拍工具的 4 阶数值微分后确认是验证器
    # 自身错误（工具值与本式里 P_k 的 4 阶差分吻合到 1.4e-14，与解析式吻合到峰值的 0.001%）。
    S <- sig(eta + dvals)
    sv <- c(1, S, 0)                       # 长度 K+1；S_{K+1} = P(X≥K+1) 恒为 0
    dsv <- c(0, S * (1 - S) * ar, 0)
    pk <- sv[-length(sv)] - sv[-1]
    dpk <- dsv[-length(dsv)] - dsv[-1]
    ok <- pk > 0                           # 极端尾类概率恰为 0 时跳过（其导数同为 0，不损失信息）
    return(sum(dpk[ok]^2 / pk[ok]))
  }
  # GPCM：I(θ) = a²·Var(类别序号)，可由 Σ_k (P_k')²/P_k 推出；写成方差式避免小概率除法
  p <- probs_closed(kind, pars, item, theta, adim)
  k <- seq_along(p) - 1L
  ar^2 * (sum(k^2 * p) - sum(k * p)^2)
}

## ── 单目录检查 ────────────────────────────────────────────────────────────
verify <- function(dir) {
  say("\n===== %s =====", basename(dir))
  pf <- pick(dir, "_item_parameters\\.csv$")
  if (is.na(pf)) { skip("整目录", "缺少 *_item_parameters.csv"); return(invisible(NULL)) }
  pars <- rd(pf)
  # 路线判定（供 I6/I7c 使用）：model=mirt 且 mirt_mode=eifa 时，维度编号来自
  # 未旋转载荷的 argmax，维度分组是**旋转依赖**的；cifa 则由用户的对照表指定。
  snap0 <- pick(dir, "_config_snapshot\\.(yaml|json)$")
  cfg0 <- if (is.na(snap0)) NULL else tryCatch(if (grepl("\\.yaml$", snap0)) yaml::read_yaml(snap0) else jsonlite::fromJSON(snap0), error = function(e) NULL)
  req_model <- tolower(as.character(cfg0$analysis$model %||% ""))
  mirt_mode0 <- tolower(as.character(cfg0$analysis$mirt_mode %||% "eifa"))
  is_eifa <- identical(req_model, "mirt") && identical(mirt_mode0, "eifa")
  ac <- acols_of(pars)
  if (!length(ac)) { skip("整目录", "参数表没有 a1..aD 列"); return(invisible(NULL)) }
  kind <- classify(pars)
  say("  模型判定（按参数表列结构）：%s；判别力列 %s", kind, paste(ac, collapse = ","))

  ## I1  MDISC = sqrt(Σaⱼ²)
  md <- sqrt(rowSums(as.matrix(pars[ac])^2))
  good("I1  MDISC = sqrt(Σaⱼ²)", relmax(pars$MDISC, md) < 1e-8,
       sprintf("最大相对差 %.3e", relmax(pars$MDISC, md)))

  ## I2  b 与 d 的换算（GRM/二分：b=-d/MDISC；GPCM：台阶 = 相邻截距之差）
  dc <- dcols_of(pars)
  if (kind == "gpcm") {
    # 台阶列名固定为 b_d1..b_d(K-1)（参考类别 d0 不产生台阶）
    bcols <- paste0("b_d", seq_len(length(dc) - 1L))
    D <- as.matrix(pars[dc]); dstep <- D[, -1L, drop = FALSE] - D[, -ncol(D), drop = FALSE]
    expb <- -dstep / pars$MDISC
    if (!all(bcols %in% names(pars))) skip("I2  GPCM 台阶 b", sprintf("缺少列 %s", paste(setdiff(bcols, names(pars)), collapse = ","))) else {
      good("I2  GPCM 台阶 b = -(d_k - d_{k-1})/MDISC",
           relmax(as.matrix(pars[bcols]), expb) < 1e-8,
           sprintf("%d 列，最大相对差 %.3e", length(bcols), relmax(as.matrix(pars[bcols]), expb)))
      good("I2b 无多余 b_d0 列", !("b_d0" %in% names(pars)), "")
    }
  } else {
    bcols <- paste0("b_", dc)                     # 二分是 b_d；多级是 b_d1..b_d(K-1)
    if (!all(bcols %in% names(pars))) skip("I2  b = -d/MDISC", sprintf("缺少列 %s", paste(setdiff(bcols, names(pars)), collapse = ","))) else {
      expb <- -as.matrix(pars[dc]) / pars$MDISC
      good("I2  b = -d/MDISC（GRM/二分）",
           relmax(as.matrix(pars[bcols]), expb) < 1e-8, sprintf("列 %s，最大相对差 %.3e", paste(bcols, collapse = ","), relmax(as.matrix(pars[bcols]), expb)))
    }
  }

  ## I3  ICC：用闭式重算每一题每一条曲线，与 *_icc_data.csv 比
  icf <- pick(dir, "_icc_data\\.csv$")
  if (is.na(icf)) skip("I3  ICC 闭式复算", "缺少 *_icc_data.csv") else {
    icc <- rd(icf)
    dim_of <- function(it) { d <- unique(icc$Dimension[icc$Item == it])[1L]; if (!is.na(d) && d %in% names(pars)) d else sub("^F", "a", d) }
    worst <- 0; worst_at <- ""
    for (it in unique(icc$Item)) {
      sub <- icc[icc$Item == it, , drop = FALSE]
      adim <- dim_of(it)
      if (!adim %in% names(pars)) { worst <- NA; worst_at <- paste0(it, "（维度列 ", adim, " 不在参数表里）"); break }
      for (th in unique(sub$Theta)) {
        p <- probs_closed(kind, pars, it, th, adim)
        # 复算不出来（参数表里找不到该题 / 该维度列）必须判 FAIL，不能 next 静默跳过——
        # 早先 CIFA 目录正是靠静默跳过把 Item1..Item9 的失配掩盖成了 PASS。
        if (is.null(p)) { worst <- NA; worst_at <- paste0(it, "（参数表里找不到该题或维度列 ", adim, "）"); break }
        got <- num(sub$Probability[sub$Theta == th][order(as.integer(sub$Category[sub$Theta == th]))])
        if (length(got) != length(p)) { worst <- NA; worst_at <- paste0(it, " 类别数不符"); break }
        d <- max(abs(got - p))
        if (is.na(worst) || d > worst) { worst <- d; worst_at <- sprintf("%s @θ=%.2f", it, th) }
      }
      if (is.na(worst)) break
    }
    good("I3  ICC 用 Samejima/Muraki/Birnbaum 闭式逐点复算",
         isTRUE(worst < 1e-8), sprintf("最大绝对差 %.3e（最差点 %s）", worst, worst_at))
  }

  ## I4  IIF：I(θ) = Σ_k (P_k')²/P_k
  iif <- pick(dir, "_iif_data\\.csv$")
  if (is.na(iif)) skip("I4  IIF 闭式复算", "缺少 *_iif_data.csv") else {
    D <- rd(iif); worst <- 0; wa <- ""; absw <- 0
    dim_of2 <- function(it) { d <- unique(D$Dimension[D$Item == it])[1L]; if (!is.na(d) && d %in% names(pars)) d else sub("^F", "a", d) }
    for (it in unique(D$Item)) {
      adim <- dim_of2(it); if (!adim %in% names(pars)) { worst <- NA; wa <- it; break }
      for (th in D$Theta[D$Item == it]) {
        want <- info_closed(kind, pars, it, th, adim)
        if (is.null(want)) { worst <- NA; wa <- paste0(it, "（参数表里找不到该题或维度列 ", adim, "）"); break }
        got <- D$Information[D$Item == it & D$Theta == th]
        absw <- max(absw, abs(got - want))
        d <- abs(got - want) / max(1e-9, abs(want))
        if (is.na(worst) || d > worst) { worst <- d; wa <- sprintf("%s @θ=%.2f", it, th) }
      }
      if (is.na(worst)) break
    }
    # 判据按"占信息量峰值的比例"，不用逐点相对差：工具用 θ 网格**数值差分**算 IIF
    # （内部中心差分 h=0.05、边界单侧差分），在 I(θ)≈0 的尾部相对误差会放大到 >100%，
    # 但绝对误差始终很小。用峰值占比才能反映"这个近似够不够用"。
    peak <- max(abs(D$Information))
    good("I4  IIF = Σ_k (P_k')²/P_k（解析导数；按峰值占比判定）", isTRUE(absw < 0.01 * peak) && !is.na(worst),
         sprintf("最大绝对差 %.3e = 峰值的 %.2f%%（逐点相对差最大 %.1f%%，出现在 I(θ)≈0 的尾部；\n         成因：工具用 θ 网格数值差分，非缺陷）",
                 absw, 100 * absw / peak, 100 * worst))
  }

  ## I5  TIF = Σ IIF
  tf <- pick(dir, "_tif_data\\.csv$")
  if (is.na(tf) || is.na(iif)) skip("I5  TIF = Σ IIF", "缺少 *_tif_data.csv 或 *_iif_data.csv") else {
    T <- rd(tf); D <- rd(iif); worst <- 0; wa <- ""
    for (dm in unique(T$Dimension)) {
      for (th in T$Theta[T$Dimension == dm]) {
        got <- T$Information[T$Dimension == dm & T$Theta == th]
        sel <- D$Dimension == dm & D$Theta == th
        want <- if (any(sel)) sum(D$Information[sel]) else NA_real_
        # 判别力修正（第三方复核指出）：早先这里静默 next——TIF 里有某维度而 IIF 表里没有时
        # 直接跳过、不计入失败，与本文件"失配一律判失败"的纪律相悖（当前数据下未触发，属隐患）。
        if (is.na(want)) { worst <- NA_real_; wa <- sprintf("%s @θ=%.2f（IIF 表里没有该维度）", dm, th); break }
        d <- abs(got - want) / max(1e-9, abs(want))
        if (!is.na(worst) && d > worst) { worst <- d; wa <- sprintf("%s @θ=%.2f", dm, th) }
      }
      if (is.na(worst)) break
    }
    good("I5  TIF = 各题 IIF 之和", isTRUE(worst < 1e-6) && !is.na(worst), sprintf("最大相对差 %.3e（最差点 %s）", worst, wa))
  }

  ## I6  SE(θ) 与信息量的关系（MAP 下是近似，只看形状与量级）
  af <- pick(dir, "_ability_estimates\\.csv$")
  if (is.na(af) || is.na(iif)) skip("I6  SE ≈ 1/sqrt(I(θ))", "缺少 ability_estimates 或 iif_data") else {
    A <- rd(af); D <- rd(iif)
    se_cols <- grep("^SE_", names(A), value = TRUE)
    if (!length(se_cols)) skip("I6  SE ≈ 1/sqrt(I(θ))", "能力表没有 SE_ 列") else {
      # 维度名归一：能力表用 mirt 的 F1/F2，而 iif_data 用判别力列名 a1/a2
      # （多维时 owner = a1,a2）。两者必须映射后再比对，否则取不到行、
      # aggregate() 会直接报 "no rows to aggregate"（不是返回 NA）。
      dm_all <- unique(as.character(D$Dimension))
      dimkey <- function(d) if (d %in% dm_all) d else if (sub("^F", "a", d) %in% dm_all) sub("^F", "a", d) else NA_character_
      dk <- vapply(sub("^SE_", "", se_cols), dimkey, character(1))
      use <- !is.na(dk)
      if (!any(use)) {
        info("I6  SE 与 1/sqrt(I(θ)) 量级一致",
             sprintf("能力表的维度 %s 在 iif_data 的 Dimension（%s）中全部没有对应项，无法核对",
                     paste(sub("^SE_", "", se_cols)[!use], collapse = ","), paste(dm_all, collapse = ",")))
      } else {
      ratio_med <- vapply(se_cols[use], function(sc) {
        dim <- dk[match(sc, se_cols)]; tcol <- if (dim %in% names(A)) dim else names(A)[1L]
        tot <- aggregate(Information ~ Theta, D[D$Dimension == dim, , drop = FALSE], sum)
        if (nrow(tot) < 2L) return(NA_real_)
        inv <- stats::approx(tot$Theta, 1 / sqrt(pmax(tot$Information, 1e-12)), xout = A[[tcol]])$y
        stats::median(A[[sc]] / inv, na.rm = TRUE)
      }, numeric(1))
      rs <- vapply(se_cols[use], function(sc) {
        dim <- dk[match(sc, se_cols)]; tcol <- if (dim %in% names(A)) dim else names(A)[1L]
        # θ 是从 CSV 读回来的字符串，逐值精确相等会因浮点表示而落空 → 取最近网格点
        grid <- sort(unique(D$Theta[D$Dimension == dim]))
        info_at <- vapply(A[[tcol]], function(th) {
          if (!length(grid) || is.na(th)) return(NA_real_)
          g <- grid[which.min(abs(grid - th))]
          s <- D$Dimension == dim & abs(D$Theta - g) < 1e-9
          if (any(s)) sum(D$Information[s]) else NA_real_
        }, numeric(1))
        suppressWarnings(stats::cor(1 / sqrt(info_at), A[[sc]], use = "complete.obs"))
      }, numeric(1))
      # MAP 估计下 SE 是后验 SD，天然小于 1/sqrt(I)（收缩），且多级/3PL 下逐点噪声更大：
      # 实测 2PL 的 r = .999、GRM 的 r = .762，但两者的**中位比值都 ≈ 0.93**。
      # 因此判据放在量级比值上，r 只作弱结构证据。
      oknow <- all(ratio_med >= 0.75 & ratio_med <= 1.25, na.rm = TRUE) && all(rs >= 0.70, na.rm = TRUE)
      det <- sprintf("已核对维度 %s：中位比值 %s；r = %s",
                     paste(sub("^SE_", "", se_cols[use]), collapse = ","),
                     paste(sprintf("%.3f", ratio_med), collapse = ", "), paste(sprintf("%.3f", rs), collapse = ", "))
      nm6 <- "I6  SE 与 1/sqrt(I(θ)) 量级一致（中位比值 ∈ [0.75, 1.25]，且 r ≥ .70）"
      if (length(ac) > 1L) {
        # 多维模型不适用该等式：mirt 的 SE 取自**完整信息矩阵**（含维度间交叉信息，以及
        # 全部题目通过 a_d 对每一维的贡献），而工具的 tif_data 是"按主维度分组、其余维度
        # 取 0"的**条件切面**之和。两者不是同一个量，逐点比大小没有意义 → 只报告数值。
        info("I6  SE 与 1/sqrt(I(θ))（多维模型不适用，仅报告）",
             sprintf("%s；多维下工具 TIF 为条件切面，与完整信息矩阵的 SE 无等式关系", det))
      } else if (!anyNA(dk)) {
        good(nm6, oknow, det)
      } else if (is_eifa) {
        # EIFA：维度分组取自未旋转载荷的 argmax，可能出现"没有任何题目以第 k 维为主维度"
        # → 工具不输出该维的 TIF（tif_data 只含出现过的维度），该维 SE 因而无从核对。
        # 这是旋转依赖造成的**不可核对**，不是缺陷：已核对的维度照常判定，其余记为 INFO。
        if (!oknow) good(nm6, FALSE, det)
        info("I6  SE 与 1/sqrt(I(θ)) 量级一致（EIFA 部分维度不可核对）", sprintf(
          "%s；%s 无法核对：EIFA 的维度分组取自未旋转载荷的 argmax，本次没有任何题目以该维为主维度，工具不输出其 TIF",
          det, paste(sub("^SE_", "", se_cols)[!use], collapse = ",")))
      } else {
        good(nm6, FALSE, sprintf("能力表维度 %s 在 iif_data 的 Dimension（%s）里找不到对应项",
                                 paste(sub("^SE_", "", se_cols)[!use], collapse = ","), paste(dm_all, collapse = ",")))
      }
      }
    }
  }

  ## I7  模型比较表排序与 Selected 列
  mf <- pick(dir, "_model_comparison\\.csv$"); rf <- pick(dir, "_model_recommendation\\.csv$")
  if (is.na(mf) || is.na(rf)) skip("I7  模型比较/推荐表一致性", "缺少 model_comparison 或 model_recommendation") else {
    C <- rd(mf); R <- rd(rf)
    crit <- if ("BIC" %in% names(C)) "BIC" else names(C)[grep("AIC|BIC|SABIC", names(C))][1L]
    good("I7a 比较表按准则升序排列", !is.unsorted(C[[crit]]), sprintf("准则 %s", crit))
    good("I7b 推荐表 Selected 恰有一行", sum(R$Selected) == 1L, sprintf("Selected 行数 = %d", sum(R$Selected)))
    snap <- pick(dir, "_config_snapshot\\.(yaml|json)$")
    if (is.na(snap)) skip("I7c Selected = 实际使用的模型", "缺少 config_snapshot，无法判定应为哪个模型") else {
      cfg <- tryCatch(if (grepl("\\.yaml$", snap)) yaml::read_yaml(snap) else jsonlite::fromJSON(snap), error = function(e) NULL)
      req <- tryCatch(tolower(as.character(cfg$analysis$model)), error = function(e) NA_character_)
      mode <- tryCatch(tolower(as.character(cfg$analysis$mirt_mode %||% "eifa")), error = function(e) "eifa")
      sel <- R$Model[R$Selected][1L]
      # 期望值按工具自身声明的口径（irt_generic_pipeline.R 的 selected_model_label）：
      #   · auto          → BIC 最优行
      #   · mirt + cifa   → "CIFA"（维度由用户对照表指定，不做维度搜索）
      #   · mirt + eifa   → BIC 最优行（在 1..D 维之间搜索，标签形如 EIFA_3D）
      #   · 其余单维模型   → 该模型名
      if (is.na(req) || !nzchar(req)) skip("I7c Selected = 实际使用的模型", "配置里读不到 model")
      else {
        expect <- if (req == "auto") C$Model[1L]
                  else if (req == "mirt" && mode == "cifa") "CIFA"
                  else if (req == "mirt") C$Model[1L]
                  else req
        hit <- identical(sel, expect) || grepl(expect, sel, fixed = TRUE) || grepl(sel, expect, fixed = TRUE)
        good(sprintf("I7c Selected = 应选模型（配置 model=%s%s）", req, if (req == "mirt") paste0("/", mode) else ""),
             hit, sprintf("Selected=%s，应为 %s（BIC 最优=%s）", sel, expect, C$Model[1L]))
      }
    }
  }

  ## I8  CIFA 载荷矩阵结构
  cf <- pick(dir, "_cifa_loading_matrix\\.csv$")
  if (is.na(cf)) skip("I8  CIFA 载荷矩阵结构", "本目录不是 CIFA 路线") else {
    L <- rd(cf); lc <- setdiff(names(L), c("Item", "item"))
    good("I8a 行数 = 题目数且每题只出现一次",
         nrow(L) == nrow(pars) && !any(duplicated(L[[1L]])), sprintf("%d 行 vs 参数表 %d 题", nrow(L), nrow(pars)))
    nz <- rowSums(abs(as.matrix(L[, lc, drop = FALSE])) > 1e-12)
    good("I8b 简单结构：每行恰有一个非零载荷（未指定维度固定为 0）", all(nz == 1L),
         sprintf("非零个数分布：%s", paste(names(table(nz)), table(nz), sep = "×", collapse = " ")))
    good("I8c 载荷矩阵题名与参数表逐行对齐（按数字键）", identical(ikey(L[[1L]]), ikey(pars$Item)),
         sprintf("前 3 个：%s vs %s", paste(head(L[[1L]], 3), collapse = ","), paste(head(pars$Item, 3), collapse = ",")))
  }

  ## I9  缺失审计勾稽
  ms <- pick(dir, "_missingness_summary\\.csv$")
  if (is.na(ms)) skip("I9  缺失审计勾稽", "缺少 missingness_summary.csv") else {
    M <- rd(ms)
    good("I9a Original_N - Listwise_removed = Analysed_N",
         all(M$Original_N - M$Listwise_removed - M$All_missing_removed == M$Analysed_N),
         sprintf("%d - %d - %d = %d", M$Original_N, M$Listwise_removed, M$All_missing_removed, M$Analysed_N))
    pv <- pick(dir, "_item_missingness\\.csv$")
    if (is.na(pv)) skip("I9b Missing_cells 与逐题缺失之和一致", "缺少 item_missingness.csv") else {
      P <- rd(pv)
      good("I9b Missing_cells_before = 逐题缺失之和", sum(P$missing_n) == M$Missing_cells_before,
           sprintf("%d vs %d", sum(P$missing_n), M$Missing_cells_before))
    }
  }

  ## I10 真 Rasch：a 必须恒为 1
  # 判别力修正（第三方复核指出）：早先的守卫条件 `max|a−1| < 1e-8` 与断言本身是同一件事，
  # 属**近恒真**——若工具真把 Rasch 拟合成别的模型（a≠1），这里只会 SKIP（文案"本目录不是
  # Rasch"）而**永远不会 FAIL**。现改为按**配置声明的模型**决定该不该查：
  #   声明 rasch（或 auto 且实际选中 rasch）⇒ 断言 a 恒为 1，失配即 FAIL；
  #   其余情况才允许 SKIP，且说明是配置决定而非数据决定。
  i10_nm <- "I10 Rasch：区分度 a 恒为 1"
  i10_sel <- tryCatch({
    rf10 <- pick(dir, "_model_recommendation\\.csv$")
    if (is.na(rf10)) NA_character_ else { R10 <- rd(rf10); as.character(R10$Model[which(as.logical(R10$Selected))[1L]]) }
  }, error = function(e) NA_character_)
  i10_want <- identical(req_model, "rasch") || (identical(req_model, "auto") && identical(i10_sel, "rasch"))
  if (!i10_want) {
    skip(i10_nm, sprintf("配置声明 model=%s%s，本目录不按 Rasch 判定",
                         if (nzchar(req_model)) req_model else "（未知）",
                         if (is.na(i10_sel)) "" else paste0("，实际选中 ", i10_sel)))
  } else if (length(ac) != 1L || !"d" %in% names(pars)) {
    good(i10_nm, FALSE, sprintf("配置声明 Rasch，但参数表结构不符（判别力列 %d 个）", length(ac)))
  } else {
    good(i10_nm, diff(range(pars[[ac]])) < 1e-8 && max(abs(pars[[ac]] - 1)) < 1e-8,
         sprintf("配置声明 Rasch；极差 %.3e，max|a−1| %.3e", diff(range(pars[[ac]])), max(abs(pars[[ac]] - 1))))
  }


  ## I11 题目拟合表的 BH 校正（对应修复 R1：列匹配必须精确、不得静默降级）
  itf <- pick(dir, "_item_fit\\.csv$")
  if (is.na(itf)) skip("I11 BH_p = p.adjust(p.S_X2, 'BH')", "缺少 item_fit.csv") else {
    F <- rd(itf)
    if (!all(c("p.S_X2", "BH_p") %in% names(F)))
      skip("I11 BH_p = p.adjust(p.S_X2, 'BH')", sprintf("缺列（现有：%s）", paste(names(F), collapse = ","))) else
      good("I11 题目拟合的 BH 校正 = p.adjust(p.S_X2, 'BH')",
           isTRUE(all.equal(F$BH_p, stats::p.adjust(F$p.S_X2, "BH"), tolerance = 1e-12)),
           sprintf("n = %d，最大差 %.3e", nrow(F), max(abs(F$BH_p - stats::p.adjust(F$p.S_X2, "BH")))))
  }

  ## I12 题名口径一致性（守门检查：CIFA 路线曾把安全名 Item1… 写进部分表，
  ##      与参数表的 Item01… 不一致，导致同批输出无法按 Item 直接 join）
  csvs <- list.files(dir, pattern = "\\.csv$", full.names = TRUE)
  keyed <- list()
  for (f in csvs) {
    D <- tryCatch(rd(f), error = function(e) NULL)
    if (is.null(D) || !nrow(D)) next
    ic <- intersect(c("Item", "item", "Items"), names(D))
    if (!length(ic)) next
    v <- as.character(D[[ic[1L]]])
    if (length(unique(v)) < 2L) next            # 只有一行/单值的表（如汇总行）不参与
    keyed[[basename(f)]] <- v
  }
  if (length(keyed) < 2L) skip("I12 各输出表题名口径一致", "含 Item 列的表不足 2 个") else {
    # 只比较"题目集合"，不比较整列向量：各表的行粒度本来就不同
    # （icc/iif 是 题目×θ 网格，item_parameters 是每题一行），比长度必然误报。
    ref <- sort(unique(ikey(keyed[[1L]])))
    bad <- names(keyed)[!vapply(keyed, function(v) identical(sort(unique(ikey(v))), ref), logical(1))]
    good(sprintf("I12 各输出表题名口径一致（按数字键对齐，共 %d 个表）", length(keyed)), length(bad) == 0L,
         if (!length(bad)) sprintf("全部 %d 个含 Item 列的表题目集合一致：%s …", length(keyed), paste(head(keyed[[1L]], 3), collapse = ", "))
         else sprintf("题名不一致的表：%s", paste(bad, collapse = "；")))
  }

  ## I16 经验信度与 SE 的闭式关系
  rl <- pick(dir, "_reliability\\.csv$")
  if (is.na(rl) || is.na(af)) skip("I16 经验信度 ≈ 1 - mean(SE²)/var(θ)", "缺少 reliability 或 ability_estimates") else {
    Rl <- rd(rl); A <- rd(af)
    if (!all(c("Empirical_rxx") %in% names(Rl))) skip("I16 经验信度 ≈ 1 - mean(SE²)/var(θ)", "信度表没有 Empirical_rxx 列") else {
      dif <- vapply(seq_len(nrow(Rl)), function(i) {
        dm <- as.character(Rl$Dimension[i]); se <- paste0("SE_", dm); th <- if (dm %in% names(A)) dm else names(A)[1L]
        if (!(se %in% names(A))) return(NA_real_)
        want <- 1 - mean(A[[se]]^2, na.rm = TRUE) / stats::var(A[[th]], na.rm = TRUE)
        abs(Rl$Empirical_rxx[i] - want)
      }, numeric(1))
      # 工具调用的是 mirt::empirical_rxx()（该参数的权威实现），本脚本用的是常见近似式
      # 1 - mean(SE²)/var(θ)。两者定义不完全相同，实测差 0.02～0.11 → 只报告，不判合格。
      info("I16 经验信度（工具=mirt::empirical_rxx vs 近似式 1-mean(SE²)/var(θ)）",
           sprintf("逐维绝对差 %s（定义差异，非缺陷；逐位对齐请以 mirt 文档为准）",
                   paste(sprintf("%.4f", dif), collapse = ", ")))
    }
  }
  invisible(NULL)
}

for (d in args) {
  if (!dir.exists(d)) { n_fail <- n_fail + 1L; OK <- FALSE; cat("[FAIL] 目录不存在:", d, "\n") } else verify(d)
}
say("\n================================")
say("L1_PASS=%d L1_FAIL=%d L1_SKIP=%d", n_pass, n_fail, n_skip)
say(if (OK) "IRT L1 复算：全部通过" else "IRT L1 复算：存在失败项")
quit(status = if (OK) 0L else 1L)
