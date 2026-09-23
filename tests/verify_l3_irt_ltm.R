#!/usr/bin/env Rscript
# =============================================================================
# IRT 的 L3「独立实现对照」：用 ltm（另一套边际极大似然实现）复算同一份数据的题目参数
# -----------------------------------------------------------------------------
# 为什么需要：IRT 分支的引擎是 mirt，用 mirt 验证 mirt 是同义反复。
# ltm 是与 mirt 完全独立的另一套 IRT 实现（Rizopoulos 2006），两者在同一模型、
# 同一识别约束（θ ~ N(0,1)）下应当给出几乎相同的 a、b。
#
# 用法（Windows PowerShell 用位置参数）：
#   Rscript --vanilla tests\verify_l3_irt_ltm.R <IRT 结果目录> [更多...]
#
# 判据：r ≥ .99（排序一致）且 |平均偏差| ≤ .05、RMSE ≤ .05（点估计接近）。
# 注意 ltm 只做单维 2PL/GRM；多维与 GPCM 不在其覆盖范围内，脚本会 SKIP。
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("用法：Rscript --vanilla tests/verify_l3_irt_ltm.R <结果目录> [更多...]")
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
`%||%` <- function(a, b) if (is.null(a)) b else a

if (!requireNamespace("ltm", quietly = TRUE)) stop("需要 ltm 包：install.packages('ltm')")

verify <- function(dir) {
  cat(sprintf("\n===== %s =====\n", basename(dir)))
  snap <- pick(dir, "config_snapshot\\.(yaml|json)$"); pf <- pick(dir, "_item_parameters\\.csv$")
  if (is.na(snap) || is.na(pf)) { skip("整目录", "缺少 config_snapshot 或 item_parameters"); return(invisible(NULL)) }
  cfg <- tryCatch(if (grepl("\\.yaml$", snap)) yaml::read_yaml(snap) else jsonlite::fromJSON(snap), error = function(e) NULL)
  np <- if (!is.null(cfg$input$path)) basename(as.character(cfg$input$path)) else NA_character_
  model <- tolower(as.character(cfg$analysis$model %||% ""))
  # 配置写 auto 时按"实际选中的模型"判定：读 model_recommendation.csv 的 Selected 行。
  # 否则本可对照的 2PL/GRM 目录会因为配置写 auto 而被整目录跳过（早先 2PL 就是这样漏掉的）。
  if (!model %in% c("2pl", "grm")) {
    rf <- pick(dir, "_model_recommendation\\.csv$")
    if (!is.na(rf)) {
      R <- rd(rf); sel <- as.character(R$Model[which(as.logical(R$Selected))[1L]])
      if (!is.na(sel) && nzchar(sel)) model <- tolower(sel)
    }
  }
  if (!model %in% c("2pl", "grm")) { skip("L3 ltm 对照", sprintf("ltm 只覆盖单维 2PL/GRM，本次是 %s", model)); return(invisible(NULL)) }
  .allf <- list.files(ROOT, recursive = TRUE, full.names = TRUE)
  cand <- .allf[basename(.allf) == np]; cand <- cand[!grepl("[/\\\\]outputs[/\\\\]", cand)]
  if (length(cand) != 1L) { skip("L3 ltm 对照", sprintf("无法唯一定位原始数据 %s", np)); return(invisible(NULL)) }
  dat <- rd(cand[1L]); P <- rd(pf)
  items <- intersect(P$Item, names(dat)); if (length(items) < 3L) { skip("L3 ltm 对照", "题目名对不上"); return(invisible(NULL)) }
  # 全覆盖断言：题名口径不一致时 intersect 会静默少取若干题，让"一致"结论建立在半个数据上。
  if (length(items) != ncol(dat)) {
    good("L3 题目与原始数据全覆盖对齐", FALSE,
         sprintf("数据 %d 题，只对上 %d 题；数据题名 %s ／ 输出题名 %s",
                 ncol(dat), length(items), paste(head(names(dat), 3), collapse = ","), paste(head(P$Item, 3), collapse = ",")))
    return(invisible(NULL))
  }
  good("L3 题目与原始数据全覆盖对齐", TRUE, sprintf("%d 题全部对齐", length(items)))
  X <- dat[, items, drop = FALSE]
  # ltm 包的两种调用口径不同，不能用同一种写法：
  #   · ltm::ltm() 有公式接口（ltm(X ~ z1)），返回列 Dffclt, Dscrmn；
  #   · ltm::grm() 没有公式接口（第一个形参就是 data），必须 grm(X)，返回列 Extrmt1..ExtrmtK-1, Dscrmn。
  # 早先对两者都写 X ~ z1：grm() 直接把公式当成 data → "'data' must be either a numeric
  # matrix or a data.frame" 拟合失败，于是 GRM 的对照被静默降级成 SKIP。
  fit <- tryCatch(if (model == "2pl") ltm::ltm(X ~ z1, IRT.param = TRUE) else ltm::grm(X, IRT.param = TRUE),
                  error = function(e) e)
  if (inherits(fit, "error")) { skip("L3 ltm 对照", sprintf("ltm 拟合失败：%s", conditionMessage(fit))); return(invisible(NULL)) }
  co <- as.data.frame(stats::coef(fit))
  cat(sprintf("  ltm 参数列：%s\n", paste(names(co), collapse = ", ")))
  # 区分度列固定叫 Dscrmn（两种调用都一样）；其余列是难度/阈值，按数值顺序即为 b1..bK-1。
  # 早先取 names(co)[1] 当区分度，实际拿到的是 Dffclt/Extrmt1（难度），比的是两个不同的量。
  a_col <- grep("^Dscrmn$", names(co), value = TRUE)
  if (!length(a_col)) { skip("L3 ltm 对照", sprintf("ltm 输出里没有 Dscrmn 列（实际：%s）", paste(names(co), collapse = ","))); return(invisible(NULL)) }
  b_cols <- setdiff(names(co), a_col)
  b_cols <- b_cols[order(as.integer(sub("^[^0-9]*", "", b_cols)))]
  a_l <- num(co[[a_col]])
  Pcols <- c("Item", "MDISC", if (model == "2pl") "b_d" else grep("^b_d[0-9]+$", names(P), value = TRUE))
  m <- merge(data.frame(Item = items, a_ltm = a_l, co[, b_cols, drop = FALSE]), P[, Pcols], by = "Item")
  ra <- suppressWarnings(stats::cor(m$a_ltm, m$MDISC))
  da <- mean(m$a_ltm - m$MDISC)
  good("L3 a（区分度）与 ltm 独立实现一致", is.finite(ra) && ra >= .99 && abs(da) <= .05,
       sprintf("r = %.4f，平均偏差 %+.4f，RMSE = %.4f（n = %d 题）", ra, da, sqrt(mean((m$a_ltm - m$MDISC)^2)), nrow(m)))
  if (model == "2pl") {
    rb <- suppressWarnings(stats::cor(m[[b_cols[1L]]], m$b_d))
    good("L3 b（难度）与 ltm 独立实现一致", is.finite(rb) && rb >= .99 && abs(mean(m[[b_cols[1L]]] - m$b_d)) <= .05,
         sprintf("r = %.4f，平均偏差 %+.4f，RMSE = %.4f", rb, mean(m[[b_cols[1L]]] - m$b_d), sqrt(mean((m[[b_cols[1L]]] - m$b_d)^2))))
  } else {
    # GRM：逐阈值展开比对（ltm 的 Extrmt1..K-1 ↔ 工具的 b_d1..b_dK-1）
    bb <- grep("^b_d[0-9]+$", names(P), value = TRUE)
    if (length(b_cols) && length(bb) >= length(b_cols)) {
       bt <- unlist(m[bb[seq_along(b_cols)]]); be <- unlist(m[b_cols])
       rb <- suppressWarnings(stats::cor(be, bt))
       good("L3 GRM 各阈值 b1..bK-1 与 ltm 独立实现一致",
            is.finite(rb) && rb >= .99 && abs(mean(be - bt)) <= .05,
            sprintf("r = %.4f，平均偏差 %+.4f，RMSE = %.4f（%d 个阈值 × %d 题）",
                    rb, mean(be - bt), sqrt(mean((be - bt)^2)), length(b_cols), nrow(m)))
    } else skip("L3 GRM 阈值对照", "ltm 阈值列与工具 b_d* 列数不匹配")
  }
  invisible(NULL)
}

for (d in args) {
  if (!dir.exists(d)) { n_fail <- n_fail + 1L; OK <- FALSE; cat("[FAIL] 目录不存在:", d, "\n") } else verify(d)
}
cat("\n================================\n")
cat(sprintf("L3_PASS=%d L3_FAIL=%d L3_SKIP=%d\n", n_pass, n_fail, n_skip))
cat(if (OK) "IRT L3 独立实现对照（ltm）：全部通过\n" else "IRT L3 独立实现对照（ltm）：存在失败项\n")
quit(status = if (OK) 0L else 1L)
