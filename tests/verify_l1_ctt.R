#!/usr/bin/env Rscript
# =============================================================================
# CTT 输出 L1「可解析性质」复算脚本
# -----------------------------------------------------------------------------
# 用途：读一个（或多个）CTT 结果目录，用**教科书闭式公式**从清洗后数据独立复算
#       工具输出的若干量，逐条打印 PASS / FAIL / SKIP。
#
# 为什么需要它：CTT 分支的计算引擎是 psych + lavaan。用 psych::alpha 去验证一个内部
# 就是 psych::alpha 的工具属于同义反复。本脚本只依赖：
#   ① 结果目录里的 `01_cleaned_items.csv`（清洗后数据，工具自己的产物，作为输入而非答案）
#   ② 教科书公式（Cronbach 1951；Cureton 1957；Kaiser 1974；Bartlett 1937；Fornell & Larcker 1981）
# 因此它检验的是"工具把权威包用对了没有"，而不是"再把权威包跑一遍"。
#
# 用法（Windows PowerShell 里必须用位置参数，Rscript -f 在本机会崩）：
#   Rscript --vanilla tests\verify_l1_ctt.R outputs\ctt_A_ctt_2026xxxx
#   Rscript --vanilla tests\verify_l1_ctt.R outputs\ctt_*
#
# 退出码：全部非 SKIP 的检查通过 → 0；有 FAIL → 1
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("用法：Rscript --vanilla tests/verify_l1_ctt.R <结果目录> [更多结果目录...]")
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
ROOT <- if (is.na(.self)) "." else dirname(dirname(normalizePath(.self)))

OK <- TRUE; n_pass <- 0L; n_fail <- 0L; n_skip <- 0L
say  <- function(...) cat(sprintf(...), "\n", sep = "")
good <- function(nm, cond, detail = "") {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("[PASS]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
  else { n_fail <<- n_fail + 1L; OK <<- FALSE; cat("[FAIL]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
}
skip <- function(nm, why) { n_skip <<- n_skip + 1L; cat("[SKIP]", nm, "--", why, "\n") }
info <- function(nm, detail) cat("[INFO]", nm, "--", detail, "\n")
pick <- function(dir, suffix) { f <- list.files(dir, pattern = suffix, full.names = TRUE); if (length(f)) f[1L] else NA_character_ }
rd   <- function(f) utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a
relmax <- function(a, b) max(abs(a - b)) / max(1e-12, max(abs(b)))

## Cronbach α（协方差口径，= psych 的 raw_alpha）
alpha_cov <- function(X) {
  k <- ncol(X); S <- stats::cov(X)
  k / (k - 1) * (1 - sum(diag(S)) / sum(S))
}
## KMO（Kaiser 1974）：反像偏相关
kmo_closed <- function(R) {
  Ri <- tryCatch(solve(R), error = function(e) NULL); if (is.null(Ri)) return(NA_real_)
  d <- 1 / sqrt(diag(Ri)); P <- -Ri * outer(d, d); diag(P) <- 0
  r2 <- sum(R[row(R) != col(R)]^2); p2 <- sum(P[row(P) != col(P)]^2)
  r2 / (r2 + p2)
}
## Bartlett 球形检验（Bartlett 1937）
bartlett_closed <- function(R, n) {
  p <- ncol(R); detR <- det(R)
  if (!is.finite(detR) || detR <= 0) return(c(chisq = NA_real_, df = p * (p - 1) / 2))
  c(chisq = -((n - 1) - (2 * p + 5) / 6) * log(detR), df = p * (p - 1) / 2)
}

verify <- function(dir) {
  say("\n===== %s =====", basename(dir))
  cf <- pick(dir, "01_cleaned_items\\.csv$"); ia <- pick(dir, "02_item_analysis\\.csv$")
  if (is.na(cf) || is.na(ia)) { skip("整目录", "缺少 01_cleaned_items.csv 或 02_item_analysis.csv"); return(invisible(NULL)) }
  cleaned <- rd(cf); itab <- rd(ia)
  items <- itab$item
  if (!all(items %in% names(cleaned))) { skip("整目录", "清洗后数据里找不到 02_item_analysis.csv 列出的题目"); return(invisible(NULL)) }
  X <- as.matrix(cleaned[items]); k <- ncol(X); n <- nrow(X)
  say("  清洗后：%d 人 × %d 题；数据是否完整：%s", n, k, ifelse(anyNA(X), "否（有缺失）", "是"))

  ## C1 总量表 α（协方差闭式）
  rl <- pick(dir, "03_reliability\\.csv$")
  if (is.na(rl)) skip("C1 总量表 α = k/(k−1)·(1−Σσᵢ²/σ²)", "缺少 03_reliability.csv") else {
    R <- rd(rl); a_tool <- R$alpha[R$scale == "Total"][1L]
    good("C1 总量表 α = k/(k−1)·(1−Σσᵢ²/σ²)", isTRUE(abs(a_tool - alpha_cov(X)) < 1e-10),
         sprintf("工具 %.10f vs 闭式 %.10f", a_tool, alpha_cov(X)))
  }

  ## C9 删除项后的 α（闭式：每次少一题重算）
  ad <- pick(dir, "03_alpha_if_deleted\\.csv$")
  if (is.na(ad)) skip("C9 删除项后的 α", "缺少 03_alpha_if_deleted.csv") else {
    A <- rd(ad); want <- vapply(A$item, function(nm) alpha_cov(X[, setdiff(items, nm), drop = FALSE]), numeric(1))
    good("C9 删除项后的 α = 去掉该题后重算的 α", relmax(A$alpha_if_deleted, want) < 1e-10,
         sprintf("最大相对差 %.3e", relmax(A$alpha_if_deleted, want)))
  }

  ## C2 CITC = cor(题, 总分−该题)
  tot <- rowSums(X)
  citc_hand <- vapply(seq_len(k), function(j) stats::cor(X[, j], tot - X[, j]), numeric(1))
  good("C2 CITC = cor(题, 总分−该题)",
       relmax(itab$CITC, citc_hand) < 1e-10, sprintf("最大相对差 %.3e", relmax(itab$CITC, citc_hand)))

  ## C3 CR 决断值：高低 27% 分组 + 合并方差 t
  g <- max(1L, floor(.27 * n)); o <- order(tot)
  lo <- o[seq_len(g)]; hi <- o[(n - g + 1L):n]
  tt <- vapply(seq_len(k), function(j) {
    stats::t.test(X[hi, j], X[lo, j], var.equal = TRUE)$statistic
  }, numeric(1))
  good("C3 CR 决断值 = 高低 27% 组的合并方差 t",
       relmax(itab$CR_t, tt) < 1e-10, sprintf("每组 %d 人，最大相对差 %.3e", g, relmax(itab$CR_t, tt)))

  ## C4/C5 KMO 与 Bartlett（从清洗后数据的相关矩阵闭式重算）
  Rm <- stats::cor(X); diag(Rm) <- 1
  dg <- pick(dir, "04_efa_diagnostics\\.csv$")
  if (is.na(dg)) skip("C4/C5 KMO 与 Bartlett", "本目录不是 EFA 路线（无 04_efa_diagnostics.csv）") else {
    D <- rd(dg); km <- kmo_closed(Rm); bt <- bartlett_closed(Rm, n)
    good("C4 KMO = Σr²/(Σr²+Σ偏相关²)", isTRUE(abs(D$KMO[1] - km) < 1e-8),
         sprintf("工具 %.8f vs 闭式 %.8f", D$KMO[1], km))
    good("C5 Bartlett χ² = −[(n−1)−(2p+5)/6]·ln|R|", isTRUE(abs(D$Bartlett_chisq[1] - bt["chisq"]) < 1e-6),
         sprintf("工具 %.6f vs 闭式 %.6f（df 均 %d）", D$Bartlett_chisq[1], bt["chisq"], bt["df"]))
    good("C5b Bartlett df = p(p−1)/2", D$Bartlett_df[1] == bt["df"], sprintf("工具 %d，闭式 %d", D$Bartlett_df[1], bt["df"]))
  }

  ## C6 EFA 表内部一致性
  ld <- pick(dir, "04_efa_rotated_loadings\\.csv$"); vv <- pick(dir, "04_efa_variance\\.csv$")
  if (is.na(ld)) skip("C6 EFA 载荷/方差表一致性", "本目录不是 EFA 路线") else {
    L <- rd(ld); fcols <- setdiff(names(L), c("item", "communality", "primary_factor", "primary_loading", "suggest_delete"))
    M <- as.matrix(L[, fcols, drop = FALSE])
    prim_max <- apply(abs(M), 1L, max)
    good("C6a primary_loading = 该行最大 |载荷|", relmax(L$primary_loading, prim_max) < 1e-10,
         sprintf("最大相对差 %.3e", relmax(L$primary_loading, prim_max)))
    pf_ok <- vapply(seq_len(nrow(L)), function(i) fcols[which.max(abs(M[i, ]))] == L$primary_factor[i], logical(1))
    good("C6b primary_factor = 最大 |载荷| 所在列", all(pf_ok), sprintf("%d/%d 行一致", sum(pf_ok), nrow(L)))
    if (!is.na(vv)) {
      V <- rd(vv)
      good("C6c proportion = SS_loading / 题目数", relmax(V$proportion, V$SS_loading / k) < 1e-10,
           sprintf("最大相对差 %.3e", relmax(V$proportion, V$SS_loading / k)))
      good("C6d cumulative = 逐行累加 proportion", relmax(V$cumulative, cumsum(V$proportion)) < 1e-10, "")
    }
  }

  ## C7 CFA：CR / AVE 从标准化载荷闭式重算（Fornell & Larcker 1981）
  cl <- pick(dir, "05_cfa_loadings\\.csv$"); cv <- pick(dir, "05_cfa_convergent_validity\\.csv$")
  if (is.na(cl) || is.na(cv)) skip("C7 CFA 的 CR/AVE 闭式复算", "本目录不是 CFA 路线") else {
    Ld <- rd(cl); Cv <- rd(cv)
    lam <- Ld$standardized_loading; fac <- Ld$factor
    cr_hand <- vapply(Cv$factor, function(f) { z <- lam[fac == f]; sum(z)^2 / (sum(z)^2 + sum(1 - z^2)) }, numeric(1))
    ave_hand <- vapply(Cv$factor, function(f) mean(lam[fac == f]^2), numeric(1))
    good("C7a CR = (Σλ)²/((Σλ)²+Σ(1−λ²))", relmax(Cv$CR, cr_hand) < 1e-10, sprintf("最大相对差 %.3e", relmax(Cv$CR, cr_hand)))
    good("C7b AVE = mean(λ²)", relmax(Cv$AVE, ave_hand) < 1e-10, sprintf("最大相对差 %.3e", relmax(Cv$AVE, ave_hand)))
  }

  ## C8 单因子解的 ω（闭式，输入取工具自己打印的载荷；公式来自教科书）
  if (!is.na(rl) && !is.na(ld)) {
    L <- rd(ld)
    fcols <- setdiff(names(L), c("item", "communality", "primary_factor", "primary_loading", "suggest_delete"))
    if (length(fcols) == 1L) {
      lam <- L[[fcols[1]]]
      om <- sum(lam)^2 / (sum(lam)^2 + sum(1 - lam^2))
      R <- rd(rl); om_tool <- R$omega[R$scale == "Total"][1L]
      good("C8 单因子 ω = (Σλ)²/((Σλ)²+Σ(1−λ²))", isTRUE(abs(om_tool - om) < 1e-3),
           sprintf("工具 %.6f vs 闭式 %.6f（载荷来自工具同一张表）", om_tool, om))
    } else skip("C8 单因子 ω 闭式复算", sprintf("本目录是 %d 因子解，ω 不是单因子量", length(fcols)))
  }

  ## B1 α 的 95% CI：工具用正态近似；这里用 Feldt (1965) 精确式作独立对照
  if (!is.na(rl)) {
    R <- rd(rl); a_tool <- R$alpha[R$scale == "Total"][1L]
    lo_tool <- R$alpha_ci_lower[R$scale == "Total"][1L]; hi_tool <- R$alpha_ci_upper[R$scale == "Total"][1L]
    df1 <- n - 1; df2 <- (n - 1) * (k - 1)
    lo_f <- 1 - (1 - a_tool) * stats::qf(1 - .025, df1, df2)
    hi_f <- 1 - (1 - a_tool) * stats::qf(.025, df1, df2)
    info("B1 α 的 95% CI（两种口径）",
         sprintf("工具正态近似 [%.4f, %.4f]；Feldt 精确 [%.4f, %.4f]", lo_tool, hi_tool, lo_f, hi_f))
    good("B1b 两种 CI 口径实质一致（区间重叠且宽度相差 < 25%）",
         lo_f < hi_tool && lo_tool < hi_f && abs((hi_tool - lo_tool) - (hi_f - lo_f)) / (hi_f - lo_f) < .25,
         sprintf("宽度 工具 %.4f vs Feldt %.4f", hi_tool - lo_tool, hi_f - lo_f))
  }

  ## B3 EFA 结构用 stats::factanal（ML + varimax）独立复核：比"哪题落哪个因子"，不比载荷数值
  if (!is.na(ld)) {
    L <- rd(ld)
    fcols <- setdiff(names(L), c("item", "communality", "primary_factor", "primary_loading", "suggest_delete"))
    if (length(fcols) < 2L) skip("B3 EFA 结构独立复核（factanal）", "单因子解无结构可比") else {
      fm <- tryCatch(stats::factanal(X, factors = length(fcols), rotation = "varimax"), error = function(e) NULL)
      if (is.null(fm)) skip("B3 EFA 结构独立复核（factanal）", "factanal 无法拟合（相关矩阵可能接近奇异）") else {
        load <- unclass(fm$loadings); load <- load[items, , drop = FALSE]
        asg_fa <- apply(abs(load), 1L, which.max)
        M <- as.matrix(L[, fcols, drop = FALSE])
        asg_tool <- apply(abs(M), 1L, which.max)
        # 因子编号可任意置换，取最优匹配后的题目归属一致率
        best <- 0
        perms <- if (length(fcols) == 2L) list(c(1, 2), c(2, 1)) else if (length(fcols) == 3L) {
          list(c(1,2,3),c(1,3,2),c(2,1,3),c(2,3,1),c(3,1,2),c(3,2,1))
        } else list(seq_along(fcols))
        for (pm in perms) best <- max(best, sum(asg_fa == pm[asg_tool]))
        good("B3 EFA 题目归属与 factanal（ML+varimax）在最优因子匹配后一致",
             best / length(items) >= .80,
             sprintf("%d/%d 题一致（工具用 minres+%s，方法不同，故只比结构）", best, length(items), "promax/varimax"))
      }
    }
  }

  ## C10 清洗计数：从原始数据 + 配置独立复现整套规则，与工具的审计表逐项比
  snap <- pick(dir, "config_snapshot\\.yaml$")
  cs <- pick(dir, "01_cleaning_summary\\.csv$"); ca <- pick(dir, "01_case_cleaning_audit\\.csv$")
  if (is.na(snap) || is.na(cs)) skip("C10 清洗计数独立复现", "缺少 config_snapshot.yaml 或 01_cleaning_summary.csv") else {
    cfg <- tryCatch(yaml::read_yaml(snap), error = function(e) NULL)
    np <- if (!is.null(cfg$input$path)) basename(as.character(cfg$input$path)) else NA_character_
    # 用文件名精确匹配定位原始数据（不做正则转义，避免 TRE 语法坑）
    .allf <- if (is.na(np)) character(0) else list.files(ROOT, recursive = TRUE, full.names = TRUE)
    cand <- .allf[basename(.allf) == np]
    cand <- cand[!grepl("[/\\\\]outputs[/\\\\]", cand)]
    if (length(cand) != 1L) skip("C10 清洗计数独立复现", sprintf("无法在仓库内唯一定位原始数据 %s（匹配 %d 个）", np, length(cand))) else {
      raw <- rd(cand[1L])
      it <- items
      if (!all(it %in% names(raw))) skip("C10 清洗计数独立复现", "原始数据里缺少分析用题目列") else {
        cl <- cfg$cleaning %||% list()
        smax <- as.numeric(cl$scale_maximum %||% 5)
        rev_items <- as.character(unlist(cl$reverse_items) %||% character(0))
        rev_items <- intersect(rev_items, it)
        D <- raw[it]
        for (nm in rev_items) D[[nm]] <- smax + 1L - D[[nm]]
        n0 <- nrow(D)
        miss_pct <- rowMeans(is.na(D)) * 100
        att <- rep(FALSE, n0)
        if (!is.null(cl$attention_item) && nzchar(cl$attention_item %||% "") && cl$attention_item %in% names(raw))
          att <- !is.na(raw[[cl$attention_item]]) & as.character(raw[[cl$attention_item]]) != as.character(cl$attention_correct_value)
        fast <- rep(FALSE, n0)
        if (!is.null(cl$response_time_column) && nzchar(cl$response_time_column %||% "") && cl$response_time_column %in% names(raw)) {
          fast <- suppressWarnings(as.numeric(raw[[cl$response_time_column]]) < as.numeric(cl$minimum_response_seconds)); fast[is.na(fast)] <- FALSE
        }
        sl <- apply(D, 1L, function(z) { z <- z[!is.na(z)]; length(z) >= 3L && length(unique(z)) == 1L })
        high <- miss_pct > 20; mid <- miss_pct >= 5 & miss_pct <= 20
        mode520 <- tolower(as.character(cl$missing_5_to_20 %||% "median_impute"))
        rm_missing <- high | (mid & mode520 == "listwise")
        impute_rows <- miss_pct < 5 | (mid & mode520 == "median_impute")
        keep <- !rm_missing
        med <- vapply(D, function(z) stats::median(z[keep], na.rm = TRUE), numeric(1))
        for (nm in names(D)) { ix <- is.na(D[[nm]]) & impute_rows; D[[nm]][ix] <- med[[nm]] }
        sc <- rowSums(D, na.rm = TRUE); zz <- as.numeric(scale(sc))
        q <- stats::quantile(sc, c(.25, .75), na.rm = TRUE); iqr <- q[2] - q[1]
        ez <- abs(zz) > 3; eiqr <- sc < q[1] - 1.5 * iqr | sc > q[2] + 1.5 * iqr
        removal <- rm_missing | att | fast
        if (tolower(as.character(cl$straightline_action %||% "flag")) == "remove") removal <- removal | sl
        if (tolower(as.character(cl$extreme_action %||% "flag")) == "remove") removal <- removal | ez | eiqr
        S <- rd(cs)
        chk <- c(raw_n = n0, retained_n = sum(!removal), removed_n = sum(removal),
                 attention_failed = sum(att), too_fast = sum(fast),
                 straightline_flagged = sum(sl), extreme_flagged = sum(ez | eiqr))
        dif <- vapply(names(chk), function(nm) abs(as.numeric(S[[nm]][1]) - chk[[nm]]), numeric(1))
        good("C10 清洗计数（raw/retained/removed/注意/过快/直线/极端）可从原始数据独立复现",
             all(dif == 0), sprintf("最大偏差 %g（逐项：%s）", max(dif),
                                    paste(sprintf("%s %g", names(dif), dif), collapse = ", ")))
        if (!is.na(ca)) {
          A <- rd(ca)
          good("C10b 个案级 removed 标记与复现结果逐一相同", nrow(A) == n0 && identical(as.logical(A$removed), removal),
               sprintf("%d 行；不一致 %d 处", nrow(A), if (nrow(A) == n0) sum(as.logical(A$removed) != removal) else NA_integer_))
        }
      }
    }
  }

  invisible(NULL)
}

for (d in args) {
  if (!dir.exists(d)) { n_fail <- n_fail + 1L; OK <- FALSE; cat("[FAIL] 目录不存在:", d, "\n") } else verify(d)
}
say("\n================================")
say("L1_PASS=%d L1_FAIL=%d L1_SKIP=%d", n_pass, n_fail, n_skip)
say(if (OK) "CTT L1 复算：全部通过" else "CTT L1 复算：存在失败项")
quit(status = if (OK) 0L else 1L)
