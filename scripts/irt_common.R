`%||%` <- function(x,y) if(is.null(x)) y else x
stopf <- function(...) stop(sprintf(...),call.=FALSE)

hex_to_utf8 <- function(hex) {
  if(!nzchar(hex) || nchar(hex)%%2L || !grepl("^[0-9A-Fa-f]+$",hex)) stopf("Invalid UTF-8 hexadecimal path marker.")
  raw_path <- as.raw(strtoi(substring(hex,seq(1,nchar(hex),by=2),seq(2,nchar(hex),by=2)),16L))
  enc2utf8(rawToChar(raw_path))
}

as_chr_vec <- function(x) if(is.null(x)) x else unname(unlist(x,use.names=FALSE))

load_analysis_config <- function(args=commandArgs(trailingOnly=TRUE)) {
  p_hex <- match("--config-utf8-hex",args); p <- match("--config",args)
  if(!is.na(p_hex) && p_hex<length(args)) path <- normalizePath(hex_to_utf8(args[p_hex+1]),mustWork=TRUE)
  else { if(is.na(p) || p==length(args)) stopf("A configuration file is required."); path <- normalizePath(args[p+1],mustWork=TRUE) }
  ext <- tolower(tools::file_ext(path))
  if(!(ext %in% c("yaml","yml","json"))) stopf("Configuration must be YAML or JSON: %s",path)
  cfg <- if(ext=="json") jsonlite::fromJSON(path,simplifyVector=FALSE) else yaml::read_yaml(path)
  list(cfg=cfg,path=path,ext=if(ext=="json")"json" else "yaml")
}

resolve_path <- function(path,base_dir) {
  if(is.null(path)||!nzchar(path)) return(path)
  if(grepl("^[A-Za-z]:|^/",path)) path else normalizePath(file.path(base_dir,path),mustWork=FALSE)
}

# 配置层硬校验：output.directory / input.path / output.project_label / loading_matrix 决定输入输出路径。
# yaml 里裸写 "."（被解析成数值 NA）、"~"/"null"（NULL）、数字或逻辑值时，as.character 会静默转换或让
# NA 混进路径（结果被写进 ...\NA\... 之类的目录）。缺省时取 default；显式给出的值必须是长度1的非NA非空
# 字符串（input.path / loading_matrix 允许空串 ""，与默认配置文件里的 path: "" 用法兼容）。
config_string_or <- function(value,field,default,allow_empty=FALSE) {
  if(is.null(value)) return(default)
  ok <- is.character(value) && length(value)==1L && !is.na(value) && (allow_empty || nzchar(value))
  if(!ok) stopf("配置项 %s 必须是长度为1的非NA非空字符串（当前值：%s；请填写形如 '%s' 的文本值，不要用 NA/数字/逻辑值）。",
                field,paste(deparse(value),collapse=" "),default)
  value
}

normalise_config <- function(cfg,base_dir) {
  cfg$input <- cfg$input %||% list(); cfg$analysis <- cfg$analysis %||% list(); cfg$output <- cfg$output %||% list(); cfg$simulation <- cfg$simulation %||% list()
  for(section in c("input","analysis","output")) for(field in c("item_columns","compare_models","report_languages")) if(!is.null(cfg[[section]][[field]]) && is.list(cfg[[section]][[field]])) cfg[[section]][[field]] <- as_chr_vec(cfg[[section]][[field]])
  cfg$input$mode <- tolower(cfg$input$mode %||% "file")
  if(cfg$input$mode=="file") cfg$input$path <- config_string_or(cfg$input$path,"input.path","",allow_empty=TRUE)
  cfg$input$missing <- tolower(as.character(cfg$input$missing %||% "none"))
  if(!(cfg$input$missing %in% c("none","listwise","pairwise"))) stopf("input.missing must be one of: none, listwise, pairwise.")
  cfg$analysis$model <- tolower(cfg$analysis$model %||% "auto")
  cfg$analysis$mirt_mode <- tolower(cfg$analysis$mirt_mode %||% if(!is.null(cfg$analysis$dimension_mapping)) "cifa" else "eifa")
  if(!(cfg$analysis$mirt_mode %in% c("eifa","cifa"))) stopf("analysis.mirt_mode must be eifa or cifa.")
  cfg$analysis$mirt_item_model <- tolower(cfg$analysis$mirt_item_model %||% "auto")
  # 允许值必须与下游保持一致：irt_generic_pipeline.R 的 itemtype 解析认 gpcm，
  # irt_preflight.R 也把 gpcm 当作已知取值（二分+gpcm 由 preflight 拦、多级+gpcm 放行），
  # 两个入口（GUI 模型向导的「MGPCM」、终端「多维项目反应模型→多维 GPCM」）都能产出 gpcm。
  # 此处曾漏列 gpcm，导致选 MGPCM 必定在读配置这一步就失败。
  if(!(cfg$analysis$mirt_item_model %in% c("auto","grm","gpcm","2pl","3pl"))) stopf("analysis.mirt_item_model must be auto, grm, gpcm, 2pl, or 3pl.")
  cfg$analysis$dimension_range <- as.character(cfg$analysis$dimension_range %||% "auto")
  if(!is.null(cfg$analysis$loading_matrix)) cfg$analysis$loading_matrix <- resolve_path(config_string_or(cfg$analysis$loading_matrix,"analysis.loading_matrix","",allow_empty=TRUE),base_dir)
  cfg$analysis$max_iterations <- as.integer(cfg$analysis$max_iterations %||% 500)
  cfg$analysis$theta_min <- cfg$analysis$theta_min %||% -3; cfg$analysis$theta_max <- cfg$analysis$theta_max %||% 3; cfg$analysis$theta_points <- as.integer(cfg$analysis$theta_points %||% 121)
  cfg$output$project_label <- gsub("[^A-Za-z0-9_-]","_",config_string_or(cfg$output$project_label,"output.project_label","irt_analysis"))
  cfg$output$directory <- resolve_path(config_string_or(cfg$output$directory,"output.directory","outputs"),base_dir)
  cfg
}

parse_dimension_range <- function(value,max_dimensions=6L) {
  value <- gsub("\\s+","",tolower(as.character(value %||% "auto")))
  if(!nzchar(value) || value=="auto") return(NULL)
  bits <- strsplit(value,"-",fixed=TRUE)[[1]]; if(length(bits)==1L && grepl("^[0-9]+$",bits)) bits <- rep(bits,2L)
  if(length(bits)!=2L || any(!grepl("^[0-9]+$",bits))) stopf("dimension_range must use the form 1-3 or auto.")
  values <- as.integer(bits)
  if(values[1]<1L || values[2]<values[1] || values[2]>max_dimensions) stopf("dimension_range must be between 1 and %d, with the lower value no greater than the upper value.",max_dimensions)
  seq.int(values[1],values[2])
}

read_loading_matrix <- function(path) {
  if(is.null(path) || !nzchar(path)) stopf("CIFA requires analysis.loading_matrix or analysis.dimension_mapping.")
  if(!file.exists(path)) stopf("Loading matrix file not found: %s",path)
  signature <- readBin(path,what="raw",n=4L)
  is_xlsx <- length(signature)==4L && identical(as.integer(signature),c(80L,75L,3L,4L))
  ext <- tolower(tools::file_ext(path))
  if(is_xlsx) z <- as.data.frame(readxl::read_xlsx(path))
  else {
    if(ext!="csv") stopf("The CIFA loading matrix must be CSV or Excel, with columns item and dimension.")
    z <- read.csv(path,check.names=FALSE,stringsAsFactors=FALSE,na.strings=c("","NA"),fileEncoding="UTF-8-BOM")
  }
  names(z) <- tolower(trimws(names(z)))
  if(!all(c("item","dimension") %in% names(z))) stopf("The CIFA loading matrix must contain columns named item and dimension.")
  z <- z[,c("item","dimension"),drop=FALSE]; z$item <- trimws(as.character(z$item)); z$dimension <- trimws(as.character(z$dimension))
  if(!nrow(z) || any(!nzchar(z$item)) || any(!nzchar(z$dimension))) stopf("The CIFA loading matrix contains blank item or dimension values.")
  if(anyDuplicated(z$item)) stopf("Each CIFA item must be assigned to exactly one dimension; duplicates include: %s",paste(unique(z$item[duplicated(z$item)]),collapse=", "))
  z
}

mapping_from_loading_matrix <- function(path,item_names=NULL) {
  z <- read_loading_matrix(path)
  if(!is.null(item_names)) { unknown <- setdiff(z$item,item_names); absent <- setdiff(item_names,z$item); if(length(unknown)) stopf("The CIFA loading matrix includes items absent from the data: %s",paste(unknown,collapse=", ")); if(length(absent)) stopf("The CIFA loading matrix does not assign these data items: %s",paste(absent,collapse=", ")) }
  dims <- split(z$item,z$dimension)
  if(length(dims)<2L) stopf("CIFA requires at least two dimensions.")
  too_small <- names(dims)[lengths(dims)<2L]; if(length(too_small)) stopf("Each CIFA dimension needs at least two items; check: %s",paste(too_small,collapse=", "))
  stats::setNames(unname(lapply(dims,as.character)),names(dims))
}

validate_dimension_mapping <- function(mapping,item_names) {
  if(is.null(mapping) || !length(mapping)) stopf("CIFA requires a non-empty dimension mapping.")
  dims <- lapply(mapping,function(z) trimws(as.character(unlist(z,use.names=FALSE))))
  if(is.null(names(dims)) || any(!nzchar(names(dims)))) stopf("Each CIFA dimension must have a name.")
  items <- unlist(dims,use.names=FALSE); if(any(!nzchar(items))) stopf("The CIFA dimension mapping contains a blank item name."); if(anyDuplicated(items)) stopf("Each CIFA item must be assigned to exactly one dimension.")
  unknown <- setdiff(items,item_names); absent <- setdiff(item_names,items); if(length(unknown)) stopf("dimension_mapping contains unknown items: %s",paste(unknown,collapse=", ")); if(length(absent)) stopf("dimension_mapping does not assign these data items: %s",paste(absent,collapse=", "))
  if(length(dims)<2L) stopf("CIFA requires at least two dimensions.")
  small <- names(dims)[lengths(dims)<2L]; if(length(small)) stopf("Each CIFA dimension needs at least two items; check: %s",paste(small,collapse=", "))
  dims
}

read_irt_data <- function(path) {
  if(!file.exists(path)) stopf("Input file not found: %s",path); ext <- tolower(tools::file_ext(path))
  if(ext=="csv") return(read.csv(path,check.names=FALSE,na.strings=c("","NA","."),fileEncoding="UTF-8-BOM"))
  if(ext %in% c("xlsx","xls")) return(as.data.frame(readxl::read_excel(path)))
  if(ext=="sav") return(as.data.frame(haven::read_sav(path)))
  stopf("Unsupported input extension: %s",ext)
}

# Auto item detection must refuse non-numeric types and columns whose names look like IDs/demographics.
# 末尾的 check|attention|verify|careless|valid 与中文"注意|检验|甄别|作答"用于拦住注意检验/质量
# 校验类列（它们常是 1–5 的整数作答，格式上与量表题无法区分）。
suspicious_item_columns <- function(nms) {
  pat <- "id$|^id|_id|编号|姓名|年龄|性别|总分|得分|班级|组别|^no$|_no$|age|aged|gender|^sex|male|female|total|sum|score|grade|^class|group|birth|year|month|day$|height|weight|bmi|phone|email|time|check|attention|verify|careless|valid|注意|检验|甄别|作答"
  nms[grepl(pat, tolower(nms))]
}

integer_item_names <- function(data,id_column=NULL) {
  candidates <- setdiff(names(data),id_column %||% character())
  valid <- vapply(data[candidates],function(x) {
    if(is.factor(x)||is.character(x)||is.logical(x)) return(FALSE)  # factors/characters/logicals are never items
    x <- suppressWarnings(as.numeric(haven::zap_labels(x))); values <- unique(x[!is.na(x)])
    length(values)>=2 && length(values)<=10 && all(abs(values-round(values))<1e-8)
  },logical(1))
  candidates[valid]
}

# 退化列探测：自动识别此前把"整列全缺失"和"零方差"的数值列静默丢掉，用户只会发现题目少了几道；
# 更糟的是 irt_preflight.R 里针对 all_missing / zero_variance 的两条 fatal 检查因此永远不会触发。
# 这里把它们显式列出来（pipeline 打印警告，preflight 写进 JSON 的 excluded_degenerate_columns 字段）。
# 返回 data.frame(item, reason, detail)；无退化列时返回 NULL。
degenerate_item_columns <- function(data, id_column=NULL) {
  nms <- setdiff(names(data), id_column %||% character())
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

auto_items_guarded_irt <- function(data,id_column=NULL) {
  excluded <- id_column %||% character()
  cand <- integer_item_names(data,excluded)
  susp <- intersect(suspicious_item_columns(cand),cand)
  if(length(susp)) stopf("自动识别的题目列中包含疑似非题目列：%s。\n请在配置 input.item_columns 中显式列出题目列；自动识别的全部候选：%s。",paste(susp,collapse=", "),paste(cand,collapse=", "))
  if(!length(cand)) stopf("未自动识别到任何整数计分题目列，请在配置 input.item_columns 中显式列出。")
  deg <- degenerate_item_columns(data,id_column)
  if(!is.null(deg)) {
    am <- deg$item[deg$reason=="all_missing"]; zv <- deg$item[deg$reason=="zero_variance"]
    if(length(am)) cat("注意：以下列整列全缺失，已排除在题目之外（请检查数据导出）：",paste(am,collapse=", "),"\n")
    if(length(zv)) cat("注意：以下列零方差（所有观测值相同），已排除在题目之外：",paste(zv,collapse=", "),"\n")
  }
  cat("题目列自动识别（纳入）：",paste(cand,collapse=", "),"\n")
  cand
}

prepare_items <- function(data,item_columns,id_column=NULL) {
  items <- item_columns %||% "auto"; if(is.character(items) && length(items)==1 && tolower(items)=="auto") items <- auto_items_guarded_irt(data,id_column)
  missing <- setdiff(items,names(data)); if(length(missing)) stopf("Configured item columns not found: %s",paste(missing,collapse=", "))
  inter <- intersect(items,names(data))
  # 整列全缺失优先报错：read.csv 把全空列读成 logical，若不先判空，下一条类型检查会把它报成
  # "非计分类型（因子/逻辑）"，掩盖真正原因（整列没数据）。
  all_na <- vapply(data[inter],function(z) all(is.na(z)),logical(1))
  if(any(all_na)) stopf("以下题目列整列全缺失：%s。请先确认数据导出是否完整，或从数据中删除这些列。",paste(inter[all_na],collapse=", "))
  # Explicitly listed factor/logical columns would silently convert to level codes / 0-1 under as.numeric().
  # 注意：用 inter[idx] 取列名，不能写 names(data)[inter][idx]——names(data) 是无名字的字符向量，
  # 用字符向量索引它会得到 NA，报错信息里就只剩一个 "NA"，看不出是哪一列。
  bad_type <- inter[vapply(data[inter],function(z) is.factor(z)||is.logical(z),logical(1))]
  if(length(bad_type)) stopf("显式列出的题目列中含非计分类型（因子/逻辑）：%s。题目列必须是整数计分数值列；分组/ID 列请放在配置的对应字段。",paste(bad_type,collapse=", "))
  x <- as.data.frame(lapply(data[items],function(z) suppressWarnings(as.numeric(haven::zap_labels(z)))),check.names=FALSE)
  invalid <- names(x)[!vapply(x,function(z) all(is.na(z)|abs(z-round(z))<1e-8),logical(1))]; if(length(invalid)) stopf("Items must be integer-scored: %s",paste(invalid,collapse=", "))
  if(ncol(x)<3) stopf("At least three items are required."); list(x=x,items=items)
}

simulate_irt_data <- function(settings) {
  set.seed(as.integer(settings$seed %||% 20260815)); model <- tolower(settings$model %||% "grm"); n <- as.integer(settings$n_persons %||% 300); k <- as.integer(settings$n_items %||% 20)
  dimensions <- if(model=="mirt") as.integer(settings$n_dimensions %||% 2) else 1; categories <- as.integer(settings$response_categories %||% if(model%in%c("rasch","2pl","3pl"))2 else 5)
  theta <- matrix(rnorm(n*dimensions),n,dimensions); colnames(theta) <- paste0("F",seq_len(dimensions)); a <- matrix(0,k,dimensions); owner <- rep(1L,k)
  if(model=="rasch") a[,1] <- 1 else if(model%in%c("2pl","3pl")) a[,1] <- runif(k,.7,1.8) else if(model=="mirt") { owner <- rep(rep(seq_len(dimensions),each=ceiling(k/dimensions)),length.out=k); a[cbind(seq_len(k),owner)] <- runif(k,.8,1.8); a <- a+matrix(runif(k*dimensions,0,.15),k,dimensions) } else a[,1] <- runif(k,.7,1.8)
  # Thresholds are placed on each item's PRIMARY dimension: d = -b * a_primary, so the exported b is the
  # point on the primary-dimension axis where the category boundary reaches .5 (consistent for 1D and MIRT;
  # using a[,1] for multidimensional items would collapse thresholds of items owned by dimensions 2+).
  a_primary <- if(dimensions>1L) a[cbind(seq_len(k),owner)] else a[,1]
  if(categories==2) { b <- runif(k,-1.5,1.5); d <- matrix(-b*a_primary,k,1); guess <- if(model=="3pl") runif(k,.05,.25) else rep(0,k); x <- mirt::simdata(a=a,d=d,guess=guess,itemtype=if(model=="3pl")"3PL" else "2PL",Theta=theta) }
  else { b <- t(replicate(k,sort(runif(categories-1,-2,2)))); d <- -b*a_primary; x <- mirt::simdata(a=a,d=d,itemtype="graded",Theta=theta) }
  x <- as.data.frame(x); names(x) <- paste0("Item",seq_len(k)); truth <- data.frame(Item=names(x),a,check.names=FALSE)
  if(dimensions>1L) truth$primary_dimension <- paste0("F",owner)
  if(categories==2) truth$b1 <- b else for(j in seq_len(ncol(b))) truth[[paste0("b",j)]] <- b[,j]
  attr(truth,"d") <- d; attr(truth,"a") <- a
  list(data=x,truth=truth,theta=as.data.frame(theta),model=model)
}