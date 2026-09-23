#!/usr/bin/env Rscript
# =============================================================================
# IRT 的 L2「已知真值恢复」复算脚本
# -----------------------------------------------------------------------------
# 用途：读 IRT 结果目录，把工具估计出的题目参数与能力值和**生成真值**比对。
#
# 为什么这层不可替代：IRT 分支的引擎就是 mirt，"拿 mirt 验证 mirt"是同义反复；
# 而 L1 只能证明"公式与表自洽"，证明不了"估出来的东西接近真相"。
# 真值恢复用的是**生成数据时写下的 a / b / c / θ**，与任何实现都无关。
#
# 用法（Windows PowerShell 用位置参数，Rscript -f 在本机会崩）：
#   Rscript --vanilla tests\verify_recovery_irt.R outputs\irt_analysis_2pl_2026xxxx ...
#
# 判定口径说明（重要）：
#   · a / b / θ 有明确阈值；
#   · **c（3PL 猜测）不给 FAIL 阈值**：实测逐题恢复 r ≈ -0.41，这是该参数的已知弱识别
#     性质（均值无偏、个体排序不可用），不是缺陷 → 只报告数值。
#   · **EIFA 的 θ 也不给 FAIL 阈值**：探索性解经斜交旋转，因子顺序/取向不固定，
#     逐因子比对没有意义 → 只报告，并提示改用 CIFA。
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("用法：Rscript --vanilla tests/verify_recovery_irt.R <结果目录> [更多...]")
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
ROOT <- if (is.na(.self)) "." else dirname(dirname(normalizePath(.self)))

OK <- TRUE; n_pass <- 0L; n_fail <- 0L; n_skip <- 0L
good <- function(nm, cond, detail = "") {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("[PASS]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
  else { n_fail <<- n_fail + 1L; OK <<- FALSE; cat("[FAIL]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
}
skip <- function(nm, why) { n_skip <<- n_skip + 1L; cat("[SKIP]", nm, "--", why, "\n") }
info <- function(nm, detail) cat("[INFO]", nm, "--", detail, "\n")
pick <- function(dir, suffix) { f <- list.files(dir, pattern = suffix, full.names = TRUE); if (length(f)) f[1L] else NA_character_ }
rd <- function(f) utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE)
num <- function(x) suppressWarnings(as.numeric(x))
## 题名数字键：Item01 ↔ Item1（工具 CIFA 路线内部用安全名，曾把 Item1… 写进部分输出表）
ikey <- function(v) suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(v))))
rmse <- function(a, b) sqrt(mean((a - b)^2))
slope <- function(x, y) { ok <- is.finite(x) & is.finite(y); stats::cov(x[ok], y[ok]) / stats::var(x[ok]) }

truth_files <- function(datname) {
  tag <- sub("^(irt_[A-Z])_.*$", "\\1", datname)
  d <- file.path(ROOT, "examples", "simulated_datasets")
  list(item = file.path(d, paste0(tag, "_truth.csv")), theta = file.path(d, paste0(tag, "_true_theta.csv")))
}

verify <- function(dir) {
  cat(sprintf("\n===== %s =====\n", basename(dir)))
  snap <- pick(dir, "config_snapshot\\.(yaml|json)$")
  pf <- pick(dir, "_item_parameters\\.csv$"); af <- pick(dir, "_ability_estimates\\.csv$")
  if (is.na(snap) || is.na(pf)) { skip("整目录", "缺少 config_snapshot 或 item_parameters"); return(invisible(NULL)) }
  cfg <- tryCatch(if (grepl("\\.yaml$", snap)) yaml::read_yaml(snap) else jsonlite::fromJSON(snap), error = function(e) NULL)
  np <- if (!is.null(cfg$input$path)) basename(as.character(cfg$input$path)) else NA_character_
  if (is.na(np)) { skip("整目录", "配置里没有 input.path"); return(invisible(NULL)) }
  tf <- truth_files(np)
  if (!file.exists(tf$item)) { skip("整目录", sprintf("找不到 %s 的真值文件", np)); return(invisible(NULL)) }
  T <- rd(tf$item); P <- rd(pf)
  mode <- tolower(as.character(cfg$analysis$mirt_mode %||% "eifa"))
  is_mirt <- tolower(as.character(cfg$analysis$model %||% "")) == "mirt"
  cat(sprintf("  真值：%s（%d 题）｜路线：%s\n", basename(tf$item), nrow(T),
              if (is_mirt) paste0("MIRT-", toupper(mode)) else "单维"))

  ## 题目对齐用"数字键"（Item01 ↔ Item1）：CIFA 路线内部用安全名拟合，
  ## 历史版本会把 Item1… 写进部分输出表；字符串直接 merge 会静默少配若干题，
  ## 让恢复检查在"只对上了一半题"的情况下照样通过。这里既归一化又断言全覆盖。
  m <- merge(transform(P, .k = ikey(Item)), transform(T, .k = ikey(Item)), by = ".k", suffixes = c("_est", "_true"))
  if (nrow(m) != nrow(T)) {
    good("L2 题目与真值文件全覆盖对齐", FALSE,
         sprintf("真值 %d 题，只对齐上 %d 题；真值题名 %s ／ 输出题名 %s",
                 nrow(T), nrow(m), paste(head(T$Item, 3), collapse = ","), paste(head(P$Item, 3), collapse = ",")))
    return(invisible(NULL))
  }
  good("L2 题目与真值文件全覆盖对齐", TRUE, sprintf("%d 题全部对齐（按数字键）", nrow(m)))

  ## ── a：区分度 ──
  tcol <- if ("a_primary" %in% names(m)) "a_primary" else if ("a" %in% names(m)) "a" else NA_character_
  if (is.na(tcol)) skip("L2 a 恢复", "真值文件没有 a / a_primary 列") else {
    e <- num(m$MDISC); t <- num(m[[tcol]]); r <- suppressWarnings(stats::cor(e, t))
    # Rasch/1PL 的区分度是**固定参数**（a ≡ 1），估计值方差为 0 → 相关系数无定义（NA）。
    # 此时用"逐题偏差"判定：真值与估计都是常数且 RMSE ≈ 0，就是完全一致，
    # 不该因为 r 无定义而判失败（早先 Rasch 目录因此虚报一次 FAIL）。
    if (!is.finite(r) && stats::sd(e, na.rm = TRUE) < 1e-12 && stats::sd(t, na.rm = TRUE) < 1e-12 && rmse(e, t) < 1e-8) {
      good("L2 a（区分度）恢复：r ≥ .70", TRUE,
           sprintf("固定参数模型（a ≡ %.3f）：估计与真值均为常数、逐题偏差 %.1e，r 因方差为 0 无定义，按完全一致判定", t[1L], rmse(e, t)))
    } else
    good("L2 a（区分度）恢复：r ≥ .70", is.finite(r) && r >= .70,
         sprintf("r = %.3f，RMSE = %.3f，均值 真值 %.3f / 估计 %.3f", r, rmse(e, t), mean(t), mean(e)))
  }

  ## ── b：难度 / 台阶 ──
  bsteps <- grep("^b_d[0-9]+$", names(P), value = TRUE)
  if ("b" %in% names(m)) {                       # 二分：单难度
    e <- num(m$b_d); t <- num(m$b); r <- suppressWarnings(stats::cor(e, t))
    good("L2 b（难度）恢复：r ≥ .90", is.finite(r) && r >= .90,
         sprintf("r = %.3f，RMSE = %.3f，平均偏差 %+.3f", r, rmse(e, t), mean(e - t)))
  } else if ("b1" %in% names(m) && length(bsteps)) {
    K <- length(bsteps); e <- c(); t <- c()
    for (i in seq_len(K)) {
      cn <- paste0("b_d", i); tn <- paste0("b", i)
      if (cn %in% names(m) && tn %in% names(m)) { e <- c(e, num(m[[cn]])); t <- c(t, num(m[[tn]])) }
    }
    r <- suppressWarnings(stats::cor(e, t))
    good("L2 台阶 b1..bK 恢复：r ≥ .90", is.finite(r) && r >= .90,
         sprintf("r = %.3f，RMSE = %.3f（%d 个值）", r, rmse(e, t), length(e)))
  } else skip("L2 b 恢复", "真值/估计的 b 列无法对应")

  ## ── c：3PL 猜测（**只报告，不判 FAIL**）──
  if ("c" %in% names(m) && "g" %in% names(m)) {
    e <- num(m$g); t <- num(m$c); r <- suppressWarnings(stats::cor(e, t))
    info("L2 c（猜测参数）恢复——已知弱识别，不判合格",
         sprintf("r = %.3f，RMSE = %.3f，均值 真值 %.3f / 估计 %.3f；个体排序不可用，报告时须注明",
                 r, rmse(e, t), mean(t), mean(e)))
  }

  ## ── θ：能力恢复 ──
  if (is.na(af)) skip("L2 θ 恢复", "缺少 ability_estimates.csv") else {
    A <- rd(af); TT <- if (file.exists(tf$theta)) rd(tf$theta) else NULL
    if (is.null(TT)) skip("L2 θ 恢复", "没有真值能力文件") else {
      ecols <- grep("^F[0-9]+$|^Theta$", names(A), value = TRUE)
      tcols <- grep("^F[0-9]+$|^Theta$", names(TT), value = TRUE)
      if (!length(ecols) || !length(tcols)) skip("L2 θ 恢复", "能力列名无法识别") else {
        # 配对口径（第三方复核指出）：下面按**位置**配对 ecols[i] ↔ tcols[i]，前提是"工具的维度
        # 编号顺序 = 真值的维度编号顺序"。CIFA 路线这个前提由用户的题目-维度对照表固定（对照表里
        # 维度的出现顺序决定 a1/a2… ），本批数据成立；但换一份对照表若维度排序不同就会误判。
        # 这里把前提显式化：CIFA 下先用载荷矩阵反查"工具的第 i 维 ↔ 真值的第 i 维"是否同序，
        # 同序才允许按位置配对，否则明确报出无法配对（不静默给出可能错位的 r）。
        pair_ok <- TRUE; pair_note <- ""
        if (is_mirt && mode == "cifa") {
          lmf0 <- pick(dir, "_cifa_loading_matrix\\.csv$")
          tmap0 <- file.path(ROOT, "examples", "simulated_datasets",
                             paste0(sub("^(irt_[A-Z])_.*$", "\\1", np), "_loading_matrix.csv"))
          if (!is.na(lmf0) && file.exists(tmap0)) {
            L0 <- rd(lmf0); M0 <- rd(tmap0); names(M0) <- c("item", "dim")
            lc0 <- setdiff(names(L0), c("Item", "item"))
            est_dim <- lc0[max.col(abs(as.matrix(L0[, lc0, drop = FALSE])), ties.method = "first")]
            k0 <- ikey(L0[[1L]]); m0 <- match(k0, ikey(M0$item))
            same <- all(!is.na(m0)) && all(est_dim == M0$dim[m0])
            if (!same) { pair_ok <- FALSE
              pair_note <- "；工具维度与对照表维度不同序，按位置配对会错位，故不给出逐维 r" }
          }
        }
        if (!pair_ok) {
          info("L2 θ 恢复：逐维度 r ≥ .80（配对前提不成立，未判定）",
               paste0("工具维度列 ", paste(ecols, collapse = ","), " 与真值维度列 ", paste(tcols, collapse = ","), pair_note))
        } else {
        rs <- vapply(seq_len(min(length(ecols), length(tcols))), function(i) {
          suppressWarnings(stats::cor(A[[ecols[i]]], TT[[tcols[i]]]))
        }, numeric(1))
        label <- paste(sprintf("%s: r = %.3f", ecols[seq_along(rs)], rs), collapse = "，")
        if (is_mirt && mode == "eifa") {
          info("L2 θ 恢复（EIFA）——旋转后不可逐因子比对，不判合格", label)
        } else {
          good("L2 θ 恢复：逐维度 r ≥ .80", all(rs >= .80, na.rm = TRUE), label)
          se <- grep("^SE_", names(A), value = TRUE)
          if (length(se)) {
            sl <- slope(num(TT[[tcols[1]]]), num(A[[ecols[1]]]))
            info("L2 θ 的收缩与精度", sprintf("回归斜率 = %.3f（MAP 收缩会 <1）、平均 SE = %.3f",
                                              sl, mean(num(A[[se[1]]]), na.rm = TRUE)))
          }
        }
        }
      }
    }
  }

  ## ── CIFA：结构恢复 ──
  lmf <- pick(dir, "_cifa_loading_matrix\\.csv$")
  if (!is.na(lmf)) {
    L <- rd(lmf); lc <- setdiff(names(L), c("Item", "item"))
    tmap <- if (file.exists(file.path(ROOT, "examples", "simulated_datasets",
                                      paste0(sub("^(irt_[A-Z])_.*$", "\\1", np), "_loading_matrix.csv"))))
      rd(file.path(ROOT, "examples", "simulated_datasets",
                   paste0(sub("^(irt_[A-Z])_.*$", "\\1", np), "_loading_matrix.csv"))) else NULL
    if (is.null(tmap)) skip("L2 CIFA 结构恢复", "没有对照表真值") else {
      names(tmap) <- c("item", "dim")
      M <- merge(data.frame(item = ikey(L[[1L]]), est = lc[max.col(abs(as.matrix(L[, lc, drop = FALSE])), ties.method = "first")],
                            stringsAsFactors = FALSE), transform(tmap, item = ikey(item)), by = "item")
      if (nrow(M) != nrow(L)) {
        good("L2 CIFA：每题的估计主维度 = 对照表指定维度", FALSE,
             sprintf("载荷矩阵 %d 题，只与对照表对齐上 %d 题（题名口径不一致）", nrow(L), nrow(M)))
      } else {
      agree <- mean(M$est == M$dim)
      good("L2 CIFA：每题的估计主维度 = 对照表指定维度", agree >= .95,
           sprintf("%d/%d 题一致（%.0f%%）", sum(M$est == M$dim), nrow(M), 100 * agree))
      }
    }
  }
  invisible(NULL)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
for (d in args) {
  if (!dir.exists(d)) { n_fail <- n_fail + 1L; OK <- FALSE; cat("[FAIL] 目录不存在:", d, "\n") } else verify(d)
}
cat("\n================================\n")
cat(sprintf("L2_PASS=%d L2_FAIL=%d L2_SKIP=%d\n", n_pass, n_fail, n_skip))
cat(if (OK) "IRT L2 真值恢复：全部通过\n" else "IRT L2 真值恢复：存在失败项\n")
quit(status = if (OK) 0L else 1L)
