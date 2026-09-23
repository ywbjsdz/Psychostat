# Common helpers for the Psychostat CTT workflow.  All text files are UTF-8.
`%||%` <- function(x, y) if (is.null(x)) y else x
stopf <- function(...) stop(sprintf(...), call. = FALSE)

hex_to_utf8 <- function(hex) {
  if (!nzchar(hex) || nchar(hex) %% 2L || !grepl("^[0-9A-Fa-f]+$", hex)) stopf("Invalid UTF-8 hexadecimal path marker.")
  raw_path <- as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
  enc2utf8(rawToChar(raw_path))
}

load_ctt_config <- function(args = commandArgs(trailingOnly = TRUE)) {
  i_hex <- match("--config-utf8-hex", args); i_plain <- match("--config", args)
  if (!is.na(i_hex) && i_hex < length(args)) path <- normalizePath(hex_to_utf8(args[i_hex + 1L]), mustWork = TRUE)
  else if (!is.na(i_plain) && i_plain < length(args)) path <- normalizePath(args[i_plain + 1L], mustWork = TRUE)
  else stopf("A configuration file is required.")
  ext <- tolower(tools::file_ext(path))
  if (!ext %in% c("yaml", "yml", "json")) stopf("Configuration must be YAML or JSON: %s", path)
  cfg <- if (ext == "json") jsonlite::fromJSON(path, simplifyVector = FALSE) else yaml::read_yaml(path)
  list(config = cfg, path = path, base_dir = dirname(path))
}

resolve_ctt_path <- function(path, base_dir) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:|^/", path)) path else normalizePath(file.path(base_dir, path), mustWork = FALSE)
}

as_character_vector <- function(x) {
  if (is.null(x)) return(NULL)
  unname(as.character(unlist(x, use.names = FALSE)))
}

# 配置层硬校验（与 stats 分支的 config_string_or 同款实现）：output.directory / input.path /
# output.project_label 决定 CTT 的输入输出路径。yaml 里写成 "."（会被解析成数值 NA）、"~"/"null"（NULL）、
# 数字或逻辑值时，as.character 会静默转换或让 NA 混进路径（结果被写进 ...\NA\... 之类的目录）。
# 缺省时取 default；显式给出的值必须是长度1的非NA非空字符串（input.path 允许空串 ""，与默认配置 path: "" 兼容）。
config_string_or <- function(value, field, default, allow_empty = FALSE) {
  if (is.null(value)) return(default)
  ok <- is.character(value) && length(value) == 1L && !is.na(value) && (allow_empty || nzchar(value))
  if (!ok)
    stopf("配置项 %s 必须是长度为1的非NA非空字符串（当前值：%s；请填写形如 '%s' 的文本值，不要用 NA/数字/逻辑值）。",
          field, paste(deparse(value), collapse = " "), default)
  value
}

normalise_ctt_config <- function(cfg, base_dir) {
  cfg$input <- cfg$input %||% list(); cfg$cleaning <- cfg$cleaning %||% list()
  cfg$analysis <- cfg$analysis %||% list(); cfg$output <- cfg$output %||% list(); cfg$simulation <- cfg$simulation %||% list()
  cfg$input$mode <- tolower(as.character(cfg$input$mode %||% "file"))
  if (!cfg$input$mode %in% c("file", "simulate")) stopf("input.mode must be file or simulate.")
  cfg$input$path <- resolve_ctt_path(config_string_or(cfg$input$path, "input.path", "", allow_empty = TRUE), base_dir)
  cfg$input$id_column <- cfg$input$id_column %||% NULL
  cfg$input$item_columns <- as_character_vector(cfg$input$item_columns %||% "auto")
  cfg$cleaning$reverse_items <- as_character_vector(cfg$cleaning$reverse_items)
  cfg$cleaning$scale_maximum <- as.integer(cfg$cleaning$scale_maximum %||% 5L)
  if (is.na(cfg$cleaning$scale_maximum) || cfg$cleaning$scale_maximum < 2L) stopf("cleaning.scale_maximum must be at least 2.")
  cfg$cleaning$missing_5_to_20 <- tolower(as.character(cfg$cleaning$missing_5_to_20 %||% "stop"))
  if (!cfg$cleaning$missing_5_to_20 %in% c("stop", "listwise", "median_impute")) stopf("cleaning.missing_5_to_20 must be stop, listwise, or median_impute.")
  cfg$cleaning$attention_item <- cfg$cleaning$attention_item %||% NULL
  cfg$cleaning$attention_correct_value <- cfg$cleaning$attention_correct_value %||% NULL
  cfg$cleaning$response_time_column <- cfg$cleaning$response_time_column %||% NULL
  cfg$cleaning$minimum_response_seconds <- as.numeric(cfg$cleaning$minimum_response_seconds %||% NA_real_)
  cfg$cleaning$straightline_action <- tolower(as.character(cfg$cleaning$straightline_action %||% "flag"))
  cfg$cleaning$extreme_action <- tolower(as.character(cfg$cleaning$extreme_action %||% "flag"))
  if (!cfg$cleaning$straightline_action %in% c("flag", "remove") || !cfg$cleaning$extreme_action %in% c("flag", "remove")) stopf("straightline_action and extreme_action must be flag or remove.")
  cfg$analysis$rotation <- tolower(as.character(cfg$analysis$rotation %||% "promax"))
  if (!cfg$analysis$rotation %in% c("varimax", "promax")) stopf("analysis.rotation must be varimax or promax.")
  # CFA 的 ordered 处理口径：true=全部题目按有序类别（WLSMV）；false=按连续变量（ML）；auto=所有题目非缺失唯一值≤10 时按有序。
  cfg$analysis$ordered <- tolower(as.character(cfg$analysis$ordered %||% "auto"))
  if (!cfg$analysis$ordered %in% c("auto", "true", "false")) stopf("analysis.ordered must be auto, true, or false.")
  cfg$analysis$n_factors <- cfg$analysis$n_factors %||% "auto"
  cfg$analysis$max_efa_iterations <- as.integer(cfg$analysis$max_efa_iterations %||% 10L)
  # Analysis route (mirrors the IRT eifa/cifa choice): quality = cleaning+item analysis+reliability only;
  # efa = quality + exploratory factor analysis; cfa = quality + confirmatory factor analysis on a
  # user-supplied item-dimension mapping (never EFA-then-CFA on the same data).
  cfg$analysis$goal <- tolower(as.character(cfg$analysis$goal %||% ""))
  if (!nzchar(cfg$analysis$goal)) {
    legacy <- tolower(as.character(cfg$analysis$cfa_source %||% ""))
    cfg$analysis$goal <- if (legacy %in% c("file", "cfa")) "cfa" else if (legacy %in% c("skip", "quality", "none")) "quality" else "efa"
  }
  if (!cfg$analysis$goal %in% c("quality", "efa", "cfa")) stopf("analysis.goal must be quality, efa, or cfa.")
  if (cfg$analysis$goal == "efa" && identical(tolower(as.character(cfg$analysis$cfa_source %||% "")), "efa"))
    warning("Legacy cfa_source='efa' (EFA-then-CFA on the same data) is deprecated; running the EFA route only. Use goal='cfa' with an item-dimension mapping for CFA.")
  cfg$analysis$cfa_mapping <- resolve_ctt_path(as.character(cfg$analysis$cfa_mapping %||% ""), base_dir)
  cfg$analysis$cfa_source <- if (cfg$analysis$goal == "cfa") "file" else "skip"
  if (cfg$analysis$goal == "cfa" && cfg$input$mode == "file" && (!is.character(cfg$analysis$cfa_mapping) || !nzchar(cfg$analysis$cfa_mapping)))
    stopf("CFA 路线需要题目-维度对照表（analysis.cfa_mapping：含 item,dimension 两列的 CSV/Excel，模板见 examples/ctt_cfa_mapping_template.csv）。")
  cfg$analysis$criterion_column <- cfg$analysis$criterion_column %||% NULL
  cfg$analysis$criterion_direction <- tolower(as.character(cfg$analysis$criterion_direction %||% "positive"))
  if (!cfg$analysis$criterion_direction %in% c("positive", "negative")) stopf("analysis.criterion_direction must be positive or negative.")
  cfg$analysis$known_group_column <- cfg$analysis$known_group_column %||% NULL
  cfg$output$directory <- resolve_ctt_path(config_string_or(cfg$output$directory, "output.directory", "outputs"), base_dir)
  cfg$output$project_label <- gsub("[^A-Za-z0-9_-]", "_", config_string_or(cfg$output$project_label, "output.project_label", "ctt_analysis"))
  cfg$output$report_language <- tolower(as.character(cfg$output$report_language %||% "zh"))
  cfg
}

read_ctt_data <- function(path) {
  if (!file.exists(path)) stopf("Input file not found: %s", path)
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") return(read.csv(path, check.names = FALSE, na.strings = c("", "NA", "."), fileEncoding = "UTF-8-BOM"))
  if (ext %in% c("xlsx", "xls")) return(as.data.frame(readxl::read_excel(path)))
  if (ext == "sav") return(as.data.frame(haven::read_sav(path)))
  stopf("Unsupported input extension: %s", ext)
}

numeric_item_candidates <- function(data, excluded = character()) {
  nms <- setdiff(names(data), excluded)
  nms[vapply(data[nms], function(x) {
    if (is.factor(x) || is.character(x) || is.logical(x)) return(FALSE)  # factors/characters are never items
    z <- suppressWarnings(as.numeric(haven::zap_labels(x))); u <- unique(z[!is.na(z)])
    length(u) >= 2L && length(u) <= 12L && all(is.finite(u))
  }, logical(1))]
}

# Auto item detection must refuse columns whose names look like IDs / demographics / composites.
# 末尾的 check|attention|verify|careless|valid 与中文"注意|检验|甄别|作答"用于拦住**注意检验/质量
# 校验类**列：它们常常是 1–5 的整数作答、格式上与量表题无法区分，若不声明 cleaning.attention_item
# 就会被静默当成一道量表题目纳入 α 与 EFA（实测同一份模拟数据 α 从 .8086 掉到 .7453）。
suspicious_item_columns <- function(nms) {
  pat <- "id$|^id|_id|编号|姓名|年龄|性别|总分|得分|班级|组别|^no$|_no$|age|aged|gender|^sex|male|female|total|sum|score|grade|^class|group|birth|year|month|day$|height|weight|bmi|phone|email|time|check|attention|verify|careless|valid|注意|检验|甄别|作答"
  nms[grepl(pat, tolower(nms))]
}

# 自动识别时把"看起来像题目但已经退化"的列显式报出来。此前这些列因为"唯一取值 <2"被静默丢弃，
# 用户只会看到题目少了几道；整列全缺失往往意味着数据导出出错，零方差列通常是恒定的同意/人口学列。
# 返回 data.frame(item, reason, detail)；无退化列时返回 NULL。
degenerate_item_columns <- function(data, excluded = character()) {
  nms <- setdiff(names(data), excluded)
  rows <- lapply(nms, function(nm) {
    z <- data[[nm]]
    if (is.factor(z) || is.character(z)) return(NULL)
    z <- suppressWarnings(as.numeric(haven::zap_labels(z)))
    obs <- z[is.finite(z)]
    if (!length(obs)) return(data.frame(item = nm, reason = "all_missing", detail = "整列全缺失", stringsAsFactors = FALSE))
    u <- unique(obs)
    if (length(u) == 1L && all(abs(u - round(u)) < 1e-8))
      return(data.frame(item = nm, reason = "zero_variance", detail = sprintf("所有观测值都等于 %g", u), stringsAsFactors = FALSE))
    NULL
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) NULL else out
}

auto_items_guarded <- function(data, excluded, what = "item_columns") {
  cand <- numeric_item_candidates(data, excluded)
  susp <- intersect(suspicious_item_columns(cand), cand)
  if (length(susp))
    stopf("自动识别的题目列中包含疑似非题目列：%s。\n请在配置 input.%s 中显式列出题目列；自动识别的全部候选：%s。",
          paste(susp, collapse = ", "), what, paste(cand, collapse = ", "))
  if (!length(cand)) stopf("未自动识别到任何计分题目列，请在配置 input.%s 中显式列出。", what)
  deg <- degenerate_item_columns(data, excluded)
  if (!is.null(deg)) {
    am <- deg$item[deg$reason == "all_missing"]; zv <- deg$item[deg$reason == "zero_variance"]
    if (length(am)) cat("注意：以下列整列全缺失，已排除在题目之外（请检查数据导出）：", paste(am, collapse = ", "), "\n")
    if (length(zv)) cat("注意：以下列零方差（所有观测值相同），已排除在题目之外：", paste(zv, collapse = ", "), "\n")
  }
  cat("题目列自动识别（纳入）：", paste(cand, collapse = ", "), "\n")
  cat("数值列自动识别（排除，类别过多或非数值）：", paste(setdiff(names(data)[vapply(data, function(z) is.numeric(z) || is.factor(z), logical(1))], c(cand, excluded)), collapse = ", "), "\n")
  cand
}

prepare_ctt_items <- function(data, cfg) {
  excluded <- unique(c(cfg$input$id_column, cfg$analysis$criterion_column, cfg$analysis$known_group_column, cfg$cleaning$response_time_column, cfg$cleaning$attention_item))
  requested <- cfg$input$item_columns
  if (length(requested) == 1L && tolower(requested) == "auto") requested <- auto_items_guarded(data, excluded, what = "item_columns")
  missing <- setdiff(requested, names(data)); if (length(missing)) stopf("Configured item columns not found: %s", paste(missing, collapse = ", "))
  inter <- intersect(requested, names(data))
  # 整列全缺失优先报错：read.csv 会把全空列读成 logical，若不先判空，下一条类型检查会把它报成
  # "非计分类型（因子/逻辑）"，让人找不到真正原因。
  all_na <- vapply(data[inter], function(z) all(is.na(z)), logical(1))
  if (any(all_na)) stopf("以下题目列整列全缺失：%s。请先确认数据导出是否完整，或从数据中删除这些列。", paste(inter[all_na], collapse = ", "))
  # Explicitly listed factor/logical columns are almost certainly group/id metadata or a miscoding:
  # as.numeric() on a factor returns level codes, silently turning e.g. gender 男/女 into 1/2 "scores".
  # 注意：用 inter[idx] 取列名，不能写 names(data)[inter][idx]——names(data) 是无名字的字符向量，
  # 用字符向量索引它会得到 NA，报错信息里就只剩一个 "NA"，看不出是哪一列。
  bad_type <- inter[vapply(data[inter], function(z) is.factor(z) || is.logical(z), logical(1))]
  if (length(bad_type)) stopf("显式列出的题目列中含非计分类型（因子/逻辑）：%s。题目列必须是数值计分列；分组/ID/注意检验列请在配置的对应字段中指定。", paste(bad_type, collapse = ", "))
  if (length(requested) < 3L) stopf("At least three scored items are required.")
  x <- as.data.frame(lapply(data[requested], function(z) suppressWarnings(as.numeric(haven::zap_labels(z)))), check.names = FALSE)
  if (any(!vapply(x, function(z) all(is.na(z) | is.finite(z)), logical(1)))) stopf("Items contain non-numeric values. Specify item_columns explicitly.")
  list(items = x, names = requested)
}

read_mapping <- function(path, item_names = NULL) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) stopf("CFA mapping file was not found.")
  z <- if (tolower(tools::file_ext(path)) == "csv") read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8-BOM") else as.data.frame(readxl::read_excel(path))
  names(z) <- tolower(trimws(names(z)))
  if (!all(c("item", "dimension") %in% names(z))) stopf("CFA mapping must contain item and dimension columns.")
  z <- z[, c("item", "dimension")]; z$item <- trimws(as.character(z$item)); z$dimension <- trimws(as.character(z$dimension))
  if (any(!nzchar(z$item)) || any(!nzchar(z$dimension)) || anyDuplicated(z$item)) stopf("CFA mapping has blank or duplicated items.")
  if (!is.null(item_names)) {
    if (length(setdiff(item_names, z$item))) stopf("CFA mapping omits: %s", paste(setdiff(item_names, z$item), collapse = ", "))
    if (length(setdiff(z$item, item_names))) stopf("CFA mapping includes unknown items: %s", paste(setdiff(z$item, item_names), collapse = ", "))
  }
  z
}

write_csv_utf8 <- function(x, path) write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")

simulate_ctt_data <- function(settings = list()) {
  set.seed(as.integer(settings$seed %||% 20260826L)); n <- as.integer(settings$n_persons %||% 480L)
  lambda <- matrix(0, 15L, 3L); lambda[cbind(1:15, rep(1:3, each = 5))] <- rep(c(.78, .72, .67, .63, .59), 3L)
  phi <- matrix(c(1, .35, .30, .35, 1, .32, .30, .32, 1), 3, 3)
  eta <- MASS::mvrnorm(n, mu = rep(0, 3), Sigma = phi)
  residual_sd <- sqrt(pmax(1 - rowSums(lambda^2), .20)); y <- eta %*% t(lambda) + matrix(rnorm(n * 15L), n, 15L) * rep(residual_sd, each = n)
  cuts <- c(-Inf, -0.84, -0.25, .25, .84, Inf)
  x <- apply(y, 2, function(v) as.integer(cut(v, breaks = cuts, labels = FALSE)))
  x <- as.data.frame(x); names(x) <- paste0("Item", seq_len(15L))
  x$Item5 <- 6L - x$Item5 # raw reverse-keyed item; configuration reverses it before analysis
  miss <- matrix(runif(n * 15L) < .018, n, 15L); x[miss] <- NA
  group <- factor(ifelse(eta[, 1] + rnorm(n, 0, .5) > 0, "High", "Low"))
  criterion <- .55 * eta[, 1] + .25 * eta[, 2] + rnorm(n, 0, .7)
  x$attention_check <- 3L; x$attention_check[sample.int(n, max(1, floor(.03 * n)))] <- sample(c(1L, 2L, 4L, 5L), max(1, floor(.03 * n)), replace = TRUE)
  x$response_time_sec <- round(pmax(20, rlnorm(n, log(180), .4)), 1)
  x$criterion <- criterion; x$known_group <- group; x$participant_id <- sprintf("P%03d", seq_len(n))
  x
}
