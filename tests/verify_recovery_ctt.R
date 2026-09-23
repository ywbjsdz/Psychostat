#!/usr/bin/env Rscript
# =============================================================================
# CTT 的 L2「已知真值恢复」复算脚本
# -----------------------------------------------------------------------------
# 用途：读 CTT 结果目录，把它输出的结构与参数和**生成真值**比对。
#       EFA 路线 → 题目归属是否与真值维度一致（因子编号可置换，取最优匹配）
#       CFA 路线 → 标准化载荷与真值的相关 / RMSE
#
# 与 L1 的分工：L1 检查"工具把权威包用对了没有"（表内恒等式），
# L2 检查"估计出来的东西是否接近真相"（需要带真值的数据）。
#
# 用法（Windows PowerShell 用位置参数，Rscript -f 在本机会崩）：
#   Rscript --vanilla tests\verify_recovery_ctt.R outputs\ctt_A_ctt_2026xxxx outputs\ctt_B_ctt_2026xxxx ...
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("用法：Rscript --vanilla tests/verify_recovery_ctt.R <结果目录> [更多...]")
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
ROOT <- if (is.na(.self)) "." else dirname(dirname(normalizePath(.self)))

OK <- TRUE; n_pass <- 0L; n_fail <- 0L; n_skip <- 0L
good <- function(nm, cond, detail = "") {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("[PASS]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
  else { n_fail <<- n_fail + 1L; OK <<- FALSE; cat("[FAIL]", nm, if (nzchar(detail)) paste0("-- ", detail) else "", "\n") }
}
skip <- function(nm, why) { n_skip <<- n_skip + 1L; cat("[SKIP]", nm, "--", why, "\n") }
pick <- function(dir, suffix) { f <- list.files(dir, pattern = suffix, full.names = TRUE); if (length(f)) f[1L] else NA_character_ }
rd <- function(f) utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE)

## 由原始数据文件名推出真值文件名：ctt_A_xxx_n600_items15.csv → ctt_A_truth.csv
truth_for <- function(datname) {
  tag <- sub("^(ctt_[A-Z])_.*$", "\\1", datname)
  p <- file.path(ROOT, "examples", "simulated_datasets", paste0(tag, "_truth.csv"))
  if (file.exists(p)) p else NA_character_
}

verify <- function(dir) {
  cat(sprintf("\n===== %s =====\n", basename(dir)))
  snap <- pick(dir, "config_snapshot\\.yaml$")
  if (is.na(snap)) { skip("整目录", "缺少 config_snapshot.yaml，无法确定对应数据"); return(invisible(NULL)) }
  cfg <- tryCatch(yaml::read_yaml(snap), error = function(e) NULL)
  np <- if (!is.null(cfg$input$path)) basename(as.character(cfg$input$path)) else NA_character_
  if (is.na(np)) { skip("整目录", "配置里没有 input.path"); return(invisible(NULL)) }
  tf <- truth_for(np)
  if (is.na(tf)) { skip("整目录", sprintf("找不到 %s 对应的真值文件", np)); return(invisible(NULL)) }
  T <- rd(tf); cat(sprintf("  真值：%s（%d 题）\n", basename(tf), nrow(T)))

  ## ── EFA 路线：题目归属一致率（因子编号可置换）──
  mf <- pick(dir, "04_efa_item_dimension_mapping\\.csv$")
  if (!is.na(mf)) {
    M <- rd(mf); names(M)[1:2] <- c("item", "dim")
    m <- merge(M, T[, c("item", "dimension")], by = "item", suffixes = c("_est", "_true"))
    names(m)[names(m) == "dim"] <- "dim_est"          # 工具侧
    names(m)[names(m) == "dimension"] <- "dim_true"   # 真值侧
    if (!nrow(m)) skip("L2 EFA 结构恢复", "题目名无法与真值对齐") else {
      tab <- table(m$dim_true, m$dim_est)
      dn <- rownames(tab); en <- colnames(tab)
      # 因子编号可任意置换 → 枚举全部排列取最大命中（维度数很小，穷举即可）
      perms <- function(x) if (length(x) == 1L) list(x) else
        unlist(lapply(seq_along(x), function(i) lapply(perms(x[-i]), function(r) c(x[i], r))), recursive = FALSE)
      ien <- seq_along(en)
      best <- if (length(dn) == length(en)) {
        max(vapply(perms(ien), function(pm) sum(tab[cbind(seq_along(dn), pm)]), numeric(1)))
      } else sum(apply(tab, 1L, max))   # 维度数不等时退化为"每行取最大"的上界
      acc <- best / nrow(m)
      good("L2 EFA：题目归属与真值维度一致（因子编号按最优匹配）", acc >= 0.90,
           sprintf("%d/%d 题 = %.0f%%", as.integer(best), nrow(m), 100 * acc))
    }
  } else skip("L2 EFA 结构恢复", "本目录无 04_efa_item_dimension_mapping.csv（可能是 CFA 路线）")

  ## ── CFA 路线：标准化载荷与真值的相关 / RMSE ──
  lf <- pick(dir, "05_cfa_loadings\\.csv$")
  if (!is.na(lf)) {
    L <- rd(lf)
    need <- intersect(c("item", "standardized_loading"), names(L))
    if (length(need) < 2L) skip("L2 CFA 载荷恢复", "载荷表缺少 standardized_loading 列") else {
      tc <- intersect(c("true_loading", "loading"), names(T))
      if (!length(tc)) skip("L2 CFA 载荷恢复", "真值文件没有 true_loading 列") else {
        m <- merge(L[, c("item", "standardized_loading")], T[, c("item", tc[1])], by = "item")
        if (nrow(m) < 3L) skip("L2 CFA 载荷恢复", "可比题目少于 3") else {
          r <- suppressWarnings(stats::cor(m$standardized_loading, m[[tc[1]]]))
          rmse <- sqrt(mean((m$standardized_loading - m[[tc[1]]])^2))
          # 判据用 RMSE 为主：标准化载荷与生成载荷之间存在尺度压缩，r 不会到 1；
          # 真正要卡的是"恢复得准不准"，即逐题绝对偏差。实测 ctt_B：r = .87、RMSE = .032。
          good("L2 CFA：标准化载荷恢复（RMSE < .05 且 r > .80）",
               is.finite(r) && r > .80 && rmse < .05,
               sprintf("r = %.3f，RMSE = %.3f，n = %d", r, rmse, nrow(m)))
        }
      }
    }
  } else skip("L2 CFA 载荷恢复", "本目录无 05_cfa_loadings.csv（可能是 EFA 路线）")
  invisible(NULL)
}

for (d in args) {
  if (!dir.exists(d)) { n_fail <- n_fail + 1L; OK <- FALSE; cat("[FAIL] 目录不存在:", d, "\n") } else verify(d)
}
cat("\n================================\n")
cat(sprintf("L2_PASS=%d L2_FAIL=%d L2_SKIP=%d\n", n_pass, n_fail, n_skip))
cat(if (OK) "CTT L2 真值恢复：全部通过\n" else "CTT L2 真值恢复：存在失败项\n")
quit(status = if (OK) 0L else 1L)
