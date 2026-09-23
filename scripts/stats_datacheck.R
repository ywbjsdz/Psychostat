# ─────────────────────────────────────────────────────────────────────────────
# 数据准备（第 0 步）：缺失值审计与处理、异常值筛查与处理、数据完整性检查
#
# 设计原则（与 CTT 分支口径一致）：
#   1. 只标注、不擅自改数据 —— 默认 report；只有用户显式选择（交互询问或 YAML 配置）才动手
#   2. 一切进审计 —— 删了几个人、插补了几个值、原因是什么、最终 N 是多少，全部落盘可追溯
#   3. 顺序固定：先算 Z → 先删异常个案 → 再对剩余数据均值插补
#      理由：若先插补，插补值会把均值拉向中心、人为缩小 SD，使真实极端值"逃过"Z 检验；
#      反过来若先删个案再插补，插补用的是"干净数据"的均值，也更稳。
# ─────────────────────────────────────────────────────────────────────────────

# 逐变量缺失审计 + 整例删除（listwise）影响评估
missing_audit <- function(data) {
  n <- nrow(data)
  if (!n) stopf("数据为空（0 行），无法做缺失值审计。")
  per <- do.call(rbind, lapply(names(data), function(v) {
    x <- data[[v]]
    nm <- sum(is.na(x))
    data.frame(variable = v, N_total = n, N_missing = nm,
               pct_missing = round(100 * nm / n, 2), N_valid = n - nm,
               flag_high = nm / n > 0.20, stringsAsFactors = FALSE)
  }))
  complete <- stats::complete.cases(data)
  impact <- data.frame(
    N_total = n,
    N_complete_cases = sum(complete),
    N_would_drop = sum(!complete),
    pct_would_drop = round(100 * sum(!complete) / n, 2),
    stringsAsFactors = FALSE)
  list(per_variable = per, listwise_impact = impact, complete = complete)
}

# 逐个案缺失清单（每个被试缺哪些变量、缺几个）
missing_cases <- function(data, id = NULL) {
  na_mat <- is.na(data)
  n_missing <- rowSums(na_mat)
  keep <- n_missing > 0
  if (!any(keep)) {
    return(data.frame(id = character(0), N_missing = integer(0), missing_variables = character(0),
                      stringsAsFactors = FALSE))
  }
  ids <- if (!is.null(id) && length(id) == nrow(data)) as.character(id) else as.character(seq_len(nrow(data)))
  vars <- names(data)
  data.frame(id = ids[keep], N_missing = as.integer(n_missing[keep]),
             missing_variables = vapply(which(keep), function(i) paste(vars[na_mat[i, ]], collapse = "、"), character(1)),
             stringsAsFactors = FALSE)
}

# 单变量异常值：Z 分数（默认 |Z| > 3，SPSS 常用口径）与 IQR 规则（1.5×IQR 离群 / 3×IQR 极端）
univariate_outliers <- function(data, z_cutoff = 3, id = NULL) {
  ids <- if (!is.null(id) && length(id) == nrow(data)) as.character(id) else as.character(seq_len(nrow(data)))
  rows <- list(); summary_rows <- list()
  for (v in names(data)) {
    x <- suppressWarnings(as.numeric(data[[v]]))
    if (!is.numeric(data[[v]]) && all(is.na(x))) next          # 非数值列跳过
    finite <- is.finite(x)
    if (sum(finite) < 3L) next
    mu <- mean(x[finite]); sdx <- stats::sd(x[finite])
    z <- if (is.finite(sdx) && sdx > 0) (x - mu) / sdx else rep(NA_real_, length(x))
    qs <- stats::quantile(x[finite], c(.25, .75), names = FALSE, type = 7)
    iqr <- qs[2] - qs[1]
    lo15 <- qs[1] - 1.5 * iqr; hi15 <- qs[2] + 1.5 * iqr
    lo30 <- qs[1] - 3 * iqr;   hi30 <- qs[2] + 3 * iqr
    hit_z   <- finite & is.finite(z) & abs(z) > z_cutoff
    hit_iqr <- finite & (x < lo15 | x > hi15)
    hit_ext <- finite & (x < lo30 | x > hi30)
    flag <- hit_z | hit_iqr
    if (any(flag)) {
      reason <- vapply(which(flag), function(i) {
        r <- character(0)
        if (hit_z[i])   r <- c(r, sprintf("|Z|>%s（Z=%.2f）", z_cutoff, z[i]))
        if (hit_ext[i]) r <- c(r, "极端离群（超3×IQR）")
        else if (hit_iqr[i]) r <- c(r, "离群（超1.5×IQR）")
        paste(r, collapse = "；")
      }, character(1))
      rows[[v]] <- data.frame(variable = v, id = ids[flag], value = x[flag], Z = round(z[flag], 3),
                              reason = reason, stringsAsFactors = FALSE)
    }
    summary_rows[[v]] <- data.frame(variable = v, N_valid = sum(finite),
                                    n_z = sum(hit_z), n_iqr = sum(hit_iqr), n_extreme_iqr = sum(hit_ext),
                                    q1 = round(qs[1], 3), q3 = round(qs[2], 3),
                                    lower_fence = round(lo15, 3), upper_fence = round(hi15, 3),
                                    min = round(min(x[finite]), 3), max = round(max(x[finite]), 3),
                                    stringsAsFactors = FALSE)
  }
  detail <- if (length(rows)) do.call(rbind, rows) else
    data.frame(variable = character(0), id = character(0), value = numeric(0), Z = numeric(0),
               reason = character(0), stringsAsFactors = FALSE)
  summary <- if (length(summary_rows)) do.call(rbind, summary_rows) else
    data.frame(variable = character(0), N_valid = integer(0), n_z = integer(0), n_iqr = integer(0),
               n_extreme_iqr = integer(0), stringsAsFactors = FALSE)
  # 需删除的个案集合：以 Z 规则为准（用户口径），IQR 仅作标注
  drop_ids <- if (nrow(detail)) unique(detail$id[grepl("\\|Z\\|", detail$reason)]) else character(0)
  list(detail = detail, summary = summary, drop_ids = drop_ids)
}

# 均值插补（SPSS 常用口径）：只对数值列插补，返回插补后的数据与逐变量插补个数
mean_impute_numeric <- function(data) {
  out <- data; imputed <- integer(0)
  for (v in names(out)) {
    if (!is.numeric(out[[v]])) next
    nm <- sum(is.na(out[[v]]))
    if (!nm) next
    mu <- mean(out[[v]], na.rm = TRUE)
    if (!is.finite(mu)) next                    # 整列缺失：无法插补，保持原样并另行报错
    out[[v]][is.na(out[[v]])] <- mu
    imputed[[v]] <- nm
  }
  tab <- data.frame(variable = if (length(imputed)) names(imputed) else character(0),
                    n_imputed = as.integer(imputed), stringsAsFactors = FALSE)
  list(data = out, table = tab, n_total = sum(as.integer(imputed)))
}

# 数据完整性检查：ID 重复、完全重复行、常量列、取值范围越界
integrity_check <- function(data, id = NULL, scale_range = NULL, id_name = "id", scale_vars = NULL) {
  rows <- list()
  add <- function(check, variable, detail) {
    rows[[length(rows) + 1L]] <<- data.frame(check = check, variable = variable, detail = detail,
                                             stringsAsFactors = FALSE)
  }

  if (!is.null(id)) {
    ids <- as.character(id)
    dup <- unique(ids[duplicated(ids)])
    if (length(dup)) {
      add("ID 重复", id_name,
          sprintf("%d 个重复 ID，如：%s", length(dup), paste(utils::head(dup, 5), collapse = "、")))
    }
  }
  dup_rows <- sum(duplicated(data))
  if (dup_rows > 0) {
    add("完全重复的个案行", "（整行）",
        sprintf("有 %d 行与前面某行完全相同（可能是重复录入）", dup_rows))
  }

  for (v in names(data)) {
    x <- data[[v]]
    if (is.numeric(x)) {
      fin <- x[is.finite(x)]
      if (length(fin) && stats::sd(fin) == 0)
        add("常量列（零方差）", v, sprintf("所有有效值都等于 %s；该列无法参与相关/回归，比较均值也无意义", format(fin[1])))
      if (!is.null(scale_range) && length(scale_range) == 2L && length(fin)) {
        lo <- min(scale_range); hi <- max(scale_range)
        # 契约要明确：是否把某变量当成"这个量表的题"，只由 datacheck.scale_vars 决定。
        #   · 显式列在 scale_vars 里 → 严格判定（任何越界值都报）
        #   · 未声明 → 不猜；只在形态像缺失码时报警（见下），否则给"范围提示"，避免把连续总分误报成越界
        strict <- !is.null(scale_vars) && v %in% scale_vars
        # 宽松兜底：即便未声明，若形态"像缺失码"就直接报越界。
        # 缺失码的signature：① 绝大多数值在范围内、只有极少数跳出；② 跳出的值整齐（取值种类少）。
        # 连续变量（如焦虑 28~73）不会满足②（跳出的值往往各不相同）。两个条件都不满足时只给范围提示。
        out_vals <- fin[fin < lo | fin > hi]
        n_out <- length(out_vals)
        looks_like_code <- length(fin) >= 10L && n_out > 0 &&
                           (n_out / length(fin)) < 0.05 &&          # 极少数
                           length(unique(out_vals)) <= max(1L, ceiling(n_out / 2))  # 取值整齐（同码重复）

        if (strict || looks_like_code) {
          bad_vals <- sort(unique(fin[fin < lo | fin > hi]))
          if (length(bad_vals) > 0) {
            add("取值越界", v, sprintf("有 %d 个值超出量表范围 [%s, %s]（越界值：%s）——多半是把缺失码（如 99/999）当成了真实分数，必须核对原始数据后修正或改为缺失",
                                       sum(fin < lo | fin > hi), lo, hi,
                                       paste(utils::head(bad_vals, 10), collapse = "、")))
          }
        } else if (n_out > 0) {
          add("范围提示", v, sprintf("该变量的取值范围（%s ~ %s）与设定的量表范围 [%s, %s] 不一致。若它是连续变量（如总分）可忽略；若它是量表题，请在 datacheck.scale_vars 里显式列出该变量以便严格检查",
                                     format(min(fin)), format(max(fin)), lo, hi))
        }
      }
      if (length(fin)) {
        odd <- sum(fin < -1000 | fin > 1000)
        if (odd > 0) add("取值可疑", v, sprintf("有 %d 个值绝对值大于 1000，请确认是否为缺失码（如 999/9999）误当成了真实分数", odd))
      }
    } else {
      lv <- unique(as.character(x[!is.na(x)]))
      if (length(lv) == 1L) add("常量列（零方差）", v, sprintf("所有取值都是「%s」", lv))
    }
  }
  if (!length(rows)) {
    return(data.frame(check = "未发现问题", variable = "-", detail = "ID 无重复、无整行重复、无零方差列、未发现取值越界",
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# 异常个案删除
extreme_case_index <- function(data, id = NULL, z_cutoff = 3) {
  uni <- univariate_outliers(data, z_cutoff = z_cutoff, id = id)
  if (!nrow(uni$detail)) return(list(index = integer(0), detail = uni$detail))
  ids <- if (!is.null(id) && length(id) == nrow(data)) as.character(id) else as.character(seq_len(nrow(data)))
  list(index = which(ids %in% uni$drop_ids), detail = uni$detail)
}

# 供报告引用的模板句助手（与 stats_common.R 中的结果句模板风格一致）
datacheck_missing_note <- function(audit, action, imputed_n = 0L) {
  ns <- audit$per_variable
  with_missing <- ns[ns$N_missing > 0, , drop = FALSE]
  base <- if (!nrow(with_missing)) {
    "各变量均无缺失值，无需处理。"
  } else {
    sprintf("有 %d 个变量存在缺失：%s。整例删除（listwise）会损失 %d 个个案（%.1f%%）。",
            nrow(with_missing),
            paste(sprintf("%s(%d个)", with_missing$variable, with_missing$N_missing), collapse = "、"),
            audit$listwise_impact$N_would_drop, audit$listwise_impact$pct_would_drop)
  }
  act <- switch(action,
    mean_impute = sprintf(" → **已按你的选择做均值插补**：共替换 %d 个缺失值（用各变量的均值）。注意均值插补会缩小该变量的方差，报告时应说明处理方式。", imputed_n),
    remove      = " → **已按你的选择删除含缺失的个案（整例删除）**。",
    report      = " → 本次**未处理**，后续分析将按各方法自身的口径处理（多数模块为整例删除，届时会在该节写明删除了多少人）。",
    "")
  paste0(base, act)
}

datacheck_outlier_note <- function(uni, z_cutoff, action, removed_n = 0L) {
  tot_z <- sum(uni$summary$n_z); tot_iqr <- sum(uni$summary$n_iqr); tot_ext <- sum(uni$summary$n_extreme_iqr)
  if (!nrow(uni$summary) || (tot_z + tot_iqr + tot_ext) == 0L) {
    return(sprintf("按 |Z| > %s 与 1.5×IQR 两条规则，均未发现异常值。", z_cutoff))
  }
  base <- sprintf("按 **|Z| > %s** 命中 %d 个个案次；按 **1.5×IQR** 命中 %d 个个案次（其中超过 3×IQR 的极端值 %d 个）。",
                  z_cutoff, tot_z, tot_iqr, tot_ext)
  act <- switch(action,
    remove_by_z = sprintf(" → **已按你的选择删除**被 Z 规则命中的 %d 个个案。报告最终 N 时应说明删除依据与人数。", removed_n),
    report      = " → 本次**未删除**，仅在下方表格中标注（异常值是否剔除应结合专业判断，不能只看统计量）。",
    "")
  paste0(base, act)
}

# ─────────────────────────────────────────────────────────────────────────────
# 模块：数据准备与异常值筛查（datacheck）
# ─────────────────────────────────────────────────────────────────────────────

# 教学演示数据：故意含缺失值与异常值，用来演示第 0 步能发现什么
simulate_datacheck <- function(cfg) {
  set.seed(cfg$simulation$seed + 100L)
  n <- max(60L, cfg$simulation$n_per_group * 4L)
  d <- data.frame(
    id = sprintf("S%03d", seq_len(n)),
    gender = factor(rep(c("male", "female"), length.out = n)),
    anxiety = round(52 + 10 * stats::rnorm(n), 1),          # 连续：焦虑总分
    study_hours = round(8 + 3 * stats::rnorm(n), 1),        # 连续：每周学习时长
    sleep_quality = round(pmin(5, pmax(1, 3 + 0.9 * stats::rnorm(n)))),  # 1-5 量表题
    self_esteem = round(30 + 5 * stats::rnorm(n), 1),       # 连续：自尊总分
    stringsAsFactors = FALSE)
  # 故意制造三类常见问题，让"第 0 步"有东西可查：
  #   ① 两个变量各有约 3-4% 缺失（模拟漏答）
  #   ② 3 个极端值（2 个极高 + 1 个极低；模拟录入错误或真实极端个案）
  #   ③ 1 个把缺失码 99 当成真实分数录入的越界值
  miss_h <- sample.int(n, max(2L, round(n * 0.04)))     # 学习时长缺 ~4%
  miss_s <- sample.int(n, max(2L, round(n * 0.05)))     # 量表题缺 ~5%（量表缺失更像真实漏答）
  miss_e <- sample.int(n, max(2L, round(n * 0.03)))     # 自尊缺 ~3%
  d$study_hours[miss_h] <- NA_real_
  d$sleep_quality[miss_s] <- NA_real_
  d$self_esteem[miss_e] <- NA_real_
  pool <- setdiff(seq_len(n), c(miss_h, miss_s, miss_e))
  out_idx <- sample(pool, 3L)
  d$self_esteem[out_idx[1:2]] <- 95.0        # 极高值
  d$self_esteem[out_idx[3]]  <- 2.0          # 极低值
  d$study_hours[setdiff(pool, out_idx)[1]] <- 99.0   # 缺失码当成真实分数
  d
}

run_datacheck <- function(data, cfg, ctx) {
  dc <- cfg$datacheck %||% list()
  z_cut <- as.numeric(dc$z_cutoff %||% 3)
  miss_action <- tolower(as.character(dc$missing_action %||% "report"))
  out_action  <- tolower(as.character(dc$outlier_action %||% "report"))
  scale_range <- dc$scale_range
  scale_vars  <- if (is.null(dc$scale_vars)) NULL else as.character(unlist(dc$scale_vars))

  ids <- if ("id" %in% names(data)) data$id else NULL
  work <- data

  guide("\n【什么时候用】**任何统计分析之前的第一步。** 数据里常有缺失值、录入错误与极端值，")
  guide("  先看清它们再决定怎么处理，比跑出一堆结果后再回头查要省事得多；论文的方法部分也需要交代这一步。")
  guide("【SPSS操作】分析 > 描述统计 > 探索（含极端值表与箱线图）；缺失值另见 分析 > 缺失值分析。")
  guide("【本模块做什么】① 缺失值审计 ② 单变量异常值筛查（Z 分数 + IQR 双标准）③ 数据完整性检查 ④ 按你的选择处理并报告最终 N。")

  # ── ① 缺失值 ──────────────────────────────────────────────────────────────
  audit <- missing_audit(work)
  save_table(audit$per_variable, ctx, "missing_audit",
             "【表1】缺失值审计（SPSS: 分析>缺失值分析>单变量统计；本表给出逐变量缺失数与比例）")
  save_table(audit$listwise_impact, ctx, "listwise_impact",
             "【表2】整例删除的影响（对应SPSS各分析输出里的\"有效的 N (listwise)\"）")
  mc <- missing_cases(work, id = ids)
  save_table(mc, ctx, "missing_cases", "【表3】含缺失值的个案清单（逐被试列出缺了哪些变量）")

  guide("\n【缺失值怎么读】")
  guide("  · 缺失比例低（<5%）且分散：多数做法可接受；>20% 的变量要慎重，考虑剔除该变量或换指标。")
  guide("  · 整例删除（listwise）是最常见的默认做法，但会损失样本；样本小的时候要特别注意损失了多少人。")
  guide("  · 均值插补简单、SPSS 里也常用，但它会**人为缩小该变量的方差**，并削弱与其他变量的相关；")
  guide("    适合缺失少、且该变量不是核心分析对象的情形。报告时必须写明用了插补及插补个数。")
  imputed_n <- 0L
  if (miss_action == "mean_impute") {
    mi <- mean_impute_numeric(work)
    work <- mi$data; imputed_n <- mi$n_total
    if (nrow(mi$table)) {
      save_table(mi$table, ctx, "imputation",
                 "【表4】均值插补记录（每个变量替换了几个缺失值；均值插补的口径与SPSS「替换缺失值>序列均值」一致）")
    }
  } else if (miss_action == "listwise") {
    keep <- stats::complete.cases(work)
    work <- work[keep, , drop = FALSE]; if (!is.null(ids)) ids <- ids[keep]
  }
  guide("\n【本例缺失值结论】", datacheck_missing_note(audit, miss_action, imputed_n))

  # ── ② 异常值（在插补后计算；若做了插补，均值插补已使该变量无缺失）────────────
  uni <- univariate_outliers(work, z_cutoff = z_cut, id = ids)
  save_table(uni$summary, ctx, "outlier_summary",
             sprintf("【表5】异常值汇总（Z 与 IQR 双标准；SPSS: 探索>极端值表用 5 个最大/最小值，箱线图用 1.5×IQR）"))
  save_table(uni$detail, ctx, "outliers",
             sprintf("【表6】异常个案清单（|Z| > %s 或超出 1.5×IQR；含 ID、观测值、Z 与触发规则）", z_cut))

  guide("\n【异常值怎么读】**两条规则要看的是同一批可疑个案，但判定标准不同：**")
  guide(sprintf("  · Z 分数 |Z| > %s：以标准差为单位。样本量大时更稳；样本很小（n<30）时 Z 会偏小，容易漏掉真异常。", z_cut))
  guide("  · 箱线图 1.5×IQR：以四分位距为单位（SPSS 箱线图的\"离群点\"），不假设正态，对偏态数据更稳健。")
  guide("  · 超出 3×IQR 通常标为\"极端值\"。**两条规则都命中 = 更值得检查。**")
  guide("  · 异常值不一定是错误：真实的极端被试也是数据。删除前先回看原始问卷/作答记录，确认不是录入错误。")
  guide("  · 若决定保留，可在论文里说明\"未剔除异常值\"；若剔除，必须写明判定标准与剔除人数。")

  removed_n <- 0L
  if (out_action == "remove_by_z" && length(uni$drop_ids)) {
    hit <- if (!is.null(ids)) which(as.character(ids) %in% uni$drop_ids) else
      which(as.character(seq_len(nrow(work))) %in% uni$drop_ids)
    removed_n <- length(hit)
    if (removed_n) {
      removed_tab <- data.frame(id = if (!is.null(ids)) as.character(ids[hit]) else as.character(hit),
                                stringsAsFactors = FALSE)
      save_table(removed_tab, ctx, "outliers_removed", "【表7】已删除的异常个案（依据：|Z| 超过阈值的个案）")
      work <- work[-hit, , drop = FALSE]; if (!is.null(ids)) ids <- ids[-hit]
    }
  }
  guide("\n【本例异常值结论】", datacheck_outlier_note(uni, z_cut, out_action, removed_n))

  # ── ③ 完整性检查 ──────────────────────────────────────────────────────────
  integ <- integrity_check(work, id = ids, scale_range = scale_range,
                           id_name = if ("id" %in% names(work)) "id" else "id",
                           scale_vars = dc$scale_vars)
  save_table(integ, ctx, "integrity",
             "【表8】数据完整性检查（ID 重复 / 整行重复 / 常量列 / 取值越界）")
  guide("\n【完整性检查怎么读】")
  guide("  · **ID 重复 / 整行重复**：多半是重复录入，先确认再删，否则会人为放大样本量。")
  guide("  · **常量列（零方差）**：该列无法参与相关与回归（会报错或给出无意义结果），也不能比较均值。")
  guide("  · **取值越界**：量表题出现范围外的值，通常是缺失码（99/999）被当成真实分数，必须修正。")

  # ── ④ 处理摘要 ────────────────────────────────────────────────────────────
  summary_tab <- data.frame(
    item = c("原始个案数", "均值插补的缺失值个数", "按 |Z| 规则删除的个案数", "最终个案数"),
    value = c(nrow(data), imputed_n, removed_n, nrow(work)),
    note = c("读取到的原始行数",
             if (imputed_n > 0) "用各变量均值替换（会缩小方差）" else "本次未插补",
             if (removed_n > 0) sprintf("判定标准：|Z| > %s", z_cut) else "本次未删除（异常值仅标注）",
             "后续分析实际使用的样本量"),
    stringsAsFactors = FALSE)
  save_table(summary_tab, ctx, "preparation_summary",
             "【表9】数据准备摘要（论文方法部分可直接引用：原始 N → 处理 → 最终 N）")

  guide("\n【★ 数据准备摘要（写论文方法部分可直接用这段）】")
  guide(sprintf("  原始 N = %d；%s；%s；最终用于分析的 N = %d。",
                nrow(data),
                if (imputed_n > 0) sprintf("对缺失值做均值插补共 %d 个", imputed_n) else "未插补缺失值",
                if (removed_n > 0) sprintf("按 |Z| > %s 删除异常个案 %d 个", z_cut, removed_n) else "未删除异常个案",
                nrow(work)))

  # ── 图：箱线图（标注异常值）───────────────────────────────────────────────
  num_cols <- names(work)[vapply(work, is.numeric, logical(1))]
  if (length(num_cols)) {
    tryCatch(save_png(file.path(ctx$out_dir, paste0(ctx$prefix, "_boxplots.png")), function() {
      graphics::boxplot(lapply(work[num_cols], function(z) z[is.finite(z)]), col = "#8FB8DE",
                        border = "#2166AC", ylab = "Score", las = 2,
                        main = sprintf("Boxplots (circles = beyond 1.5*IQR; |Z|>%s 已单独列表)", z_cut))
    }), error = function(e) warning(sprintf("数据准备箱线图绘制失败，已跳过：%s", conditionMessage(e))))
  }
  invisible(NULL)
}
