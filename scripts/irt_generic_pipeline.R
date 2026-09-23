#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(yaml); library(jsonlite); library(mirt); library(ggplot2); library(readxl); library(haven)})
script_arg <- commandArgs(FALSE)[grep("^--file=",commandArgs(FALSE))][1]
source(file.path(dirname(normalizePath(sub("^--file=","",script_arg))),"irt_common.R"),encoding="UTF-8")
say <- function(...) cat(sprintf(...),"\n")

# Machine-readable run manifest (run_manifest.json): timestamp/branch/R and package versions for reproducibility.
write_run_manifest <- function(out_dir, cfg, packages, methods_label, config_path = NULL, extra = NULL) {
  root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", script_arg), mustWork = FALSE)), ".."))
  branch <- tryCatch({ h <- readLines(file.path(root, ".git", "HEAD"), warn = FALSE); sub("^ref: refs/heads/", "", h[1]) }, error = function(e) NA_character_)
  version_of <- function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  m <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            branch = if (length(branch) && !is.na(branch)) branch else "unknown",
            r_version = R.version.string,
            os = paste0(R.version$platform, " / ", .Platform$OS.type),
            packages = stats::setNames(lapply(packages, version_of), packages),
            seed = cfg$simulation$seed %||% NULL,
            input_mode = cfg$input$mode,
            input_path = if (nzchar(cfg$input$path %||% "")) cfg$input$path else NULL,
            config_path = if (!is.null(config_path)) config_path else NULL,
            methods = methods_label)
  if (!is.null(extra)) m <- utils::modifyList(m, extra)
  jsonlite::write_json(m, file.path(out_dir, "run_manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
}
loaded <- load_analysis_config(); config_path <- loaded$path; config_ext <- loaded$ext; base_dir <- dirname(config_path)
cfg <- normalise_config(loaded$cfg,base_dir)

model_syntax <- function(dims) {
  factors <- vapply(names(dims),function(z) paste0(z," = ",paste(dims[[z]],collapse=",")),character(1))
  if(length(dims)==1L) return(factors)
  pairs <- apply(combn(names(dims),2L),2L,paste,collapse="*")
  paste(c(factors,paste0("COV = ",paste(pairs,collapse=", "))),collapse="\n")
}
detect_dimensions <- function(x,maxd=4L) {
  r <- suppressWarnings(cor(x,use="pairwise.complete.obs")); r[is.na(r)] <- 0; diag(r) <- 1
  # 二分数据：相关矩阵改用四分相关（psych::tetrachoric 的 $rho，Phi 相关会低估关联强度）；失败时静默退回 cor()。
  used_tet <- FALSE
  if(all(vapply(x,function(z) length(unique(z[!is.na(z)])),integer(1))==2L)) {
    tet <- tryCatch(psych::tetrachoric(x),error=function(e) NULL)
    if(!is.null(tet) && !is.null(tet$rho)) { r <- as.matrix(tet$rho); r[is.na(r)] <- 0; diag(r) <- 1; used_tet <- TRUE }
  }
  # 维度数建议改用平行分析（psych::fa.parallel，fa="pc"）取代 Kaiser 特征值>1 经验规则；失败时退回 Kaiser。
  # 固定局部种子并在结束后恢复随机数状态；结果设下限 1、上限 max_auto_dimensions。
  # 注意：EIFA 路线的最终维度数仍由 BIC 比较决定，这里只提供候选范围与默认建议。
  had_seed <- exists(".Random.seed",.GlobalEnv,inherits=FALSE); if(had_seed) keep_seed <- get(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
  set.seed(1899L)
  pa_error <- NULL
  run_pa <- function() if(used_tet) psych::fa.parallel(r,n.obs=nrow(x),fa="pc",n.iter=100,plot=FALSE) else psych::fa.parallel(x,fa="pc",n.iter=100,plot=FALSE)
  pa <- tryCatch(run_pa(),error=function(e) { pa_error <<- e; NULL })
  if(had_seed) assign(".Random.seed",keep_seed,envir=.GlobalEnv) else rm(".Random.seed",envir=.GlobalEnv)
  if(!is.null(pa) && is.finite(suppressWarnings(as.numeric(pa$ncomp)))) {
    k <- max(1L,min(as.integer(maxd),as.integer(pa$ncomp))); say("平行分析建议维度数=%d",k)
  } else {
    k <- max(1L,min(as.integer(maxd),sum(eigen(r,symmetric=TRUE,only.values=TRUE)$values>1)))
    reason <- if(!is.null(pa_error)) { m <- conditionMessage(pa_error); if(nchar(m)>120L) paste0(substr(m,1L,120L),"...") else m } else "未返回有效的主成分个数"
    say("平行分析不可用（%s），退回 Kaiser 特征值>1 规则：维度数=%d",reason,k)
  }
  k
}
fit_statistics <- function(fit,compute_m2=TRUE) {
  base <- data.frame(Model=NA_character_,logLik=as.numeric(logLik(fit)),Minus2LL=-2*as.numeric(logLik(fit)),AIC=fit@Fit$AIC,BIC=fit@Fit$BIC,SABIC=fit@Fit$SABIC,M2=NA_real_,df=NA_real_,p=NA_real_,RMSEA=NA_real_,SRMR=NA_real_,SRMSR=NA_real_,TLI=NA_real_,CFI=NA_real_)
  m2 <- if(isTRUE(compute_m2)) tryCatch(M2(fit,type="M2*",calcNull=TRUE,na.rm=TRUE),error=function(e) NULL) else NULL
  if(!is.null(m2)) {
    for(nm in intersect(c("M2","df","p","RMSEA","TLI","CFI"),names(m2))) base[[nm]] <- unname(m2[[nm]])
    srmr_name <- intersect(c("SRMR","SRMSR"),names(m2)); if(length(srmr_name)) { base$SRMR <- unname(m2[[srmr_name[1]]]); base$SRMSR <- base$SRMR }
  }
  base
}
plot_irt_curves <- function(fit,x,pars,acols,owner,fn,cfg) {
  theta <- seq(cfg$analysis$theta_min,cfg$analysis$theta_max,length.out=cfg$analysis$theta_points)
  a <- as.matrix(pars[acols]); if(!ncol(a)) a <- matrix(1,nrow(x),1)
  dim_names <- colnames(a); if(is.null(dim_names)) dim_names <- paste0("F",seq_len(ncol(a)))
  traces <- list(); infos <- list()
  # 题目标签：CIFA 路线内部用安全名（Item1…）拟合，而 pars$Item 已在写出前翻回用户原始题名。
  # 这里沿用 pars$Item，否则 icc_data / iif_data / tif_data 会写安全名——实测 CIFA 目录里
  # 这几个表写 "Item1"、item_parameters 等表写 "Item01"，同一批输出无法按 Item 直接 join。
  labs_item <- if(!is.null(pars$Item) && length(pars$Item)==ncol(x)) as.character(pars$Item) else names(x)
  for(i in seq_len(ncol(x))) {
    di <- match(owner[i],dim_names); if(is.na(di)) di <- 1L
    tm <- matrix(0,length(theta),ncol(a)); tm[,di] <- theta
    pr <- probtrace(extract.item(fit,i),Theta=tm)
    traces[[i]] <- data.frame(Theta=rep(theta,ncol(pr)),Probability=as.vector(pr),Category=factor(rep(seq_len(ncol(pr)),each=length(theta))),Item=labs_item[i],Dimension=owner[i])
    # 信息函数需要 P_k'(θ)。mirt 的 probtrace() 不提供解析导数，只能数值微分；
    # 早先用 3 点格式（内部中心差分 h=0.05、边界单侧差分），截断误差 O(h^2)，
    # 实测题目信息量相对解析解最大偏到峰值的 2.7%（θ 网格两端更大）。
    # 这里改用 4 阶格式（内部 5 点中心差分、两端 4 阶单侧差分），误差降到 ~1e-7 量级，
    # 与解析解一致到峰值的 0.01% 以内（校验见 tests/verify_l1_irt.R 的 I4）。
    .h <- theta[2L]-theta[1L]; .n <- length(theta)
    dp <- apply(pr,2,function(pk) {
      d <- numeric(.n)
      if(.n >= 5L) {
        i <- 3L:(.n-2L)
        d[i] <- (-pk[i+2L]+8*pk[i+1L]-8*pk[i-1L]+pk[i-2L])/(12*.h)
        d[1L] <- (-25*pk[1L]+48*pk[2L]-36*pk[3L]+16*pk[4L]-3*pk[5L])/(12*.h)
        d[2L] <- (-3*pk[1L]-10*pk[2L]+18*pk[3L]-6*pk[4L]+pk[5L])/(12*.h)
        d[.n] <- (25*pk[.n]-48*pk[.n-1L]+36*pk[.n-2L]-16*pk[.n-3L]+3*pk[.n-4L])/(12*.h)
        d[.n-1L] <- (3*pk[.n]+10*pk[.n-1L]-18*pk[.n-2L]+6*pk[.n-3L]-pk[.n-4L])/(12*.h)
      } else {
        d[1L] <- (pk[2L]-pk[1L])/.h
        if(.n > 2L) d[2L:(.n-1L)] <- (pk[3L:.n]-pk[1L:(.n-2L)])/(2*.h)
        d[.n] <- (pk[.n]-pk[.n-1L])/.h
      }
      d
    })
    infos[[i]] <- data.frame(Theta=theta,Information=rowSums(dp^2/pmax(pr,1e-10)),Item=labs_item[i],Dimension=owner[i])
  }
  tr <- do.call(rbind,traces); ii <- do.call(rbind,infos); tif <- do.call(rbind,lapply(unique(owner),function(d) { z <- aggregate(Information~Theta,ii[ii$Dimension==d,],sum); z$Dimension <- d; z }))
  write.csv(tr,fn("icc_data"),row.names=FALSE); write.csv(ii,fn("iif_data"),row.names=FALSE); write.csv(tif,fn("tif_data"),row.names=FALSE)
  p1 <- ggplot(tr,aes(Theta,Probability,colour=Category))+geom_line(linewidth=.5)+facet_wrap(~Item,ncol=4)+theme_minimal(base_size=10)+labs(title="Item characteristic curves (conditional slices)")
  p2 <- ggplot(ii,aes(Theta,Information,colour=Dimension))+geom_line()+facet_wrap(~Item,ncol=4)+theme_minimal(base_size=10)+labs(title="Item information functions (conditional slices)")
  p3 <- ggplot(tif,aes(Theta,Information,colour=Dimension))+geom_line(linewidth=1)+theme_minimal(base_size=11)+labs(title="Test information functions (conditional slices)")
  ggsave(fn("icc","png"),p1,width=12,height=max(6,ceiling(ncol(x)/4)*2.4),dpi=300); ggsave(fn("iif","png"),p2,width=12,height=max(6,ceiling(ncol(x)/4)*2.4),dpi=300); ggsave(fn("tif","png"),p3,width=8,height=5,dpi=300)
}
extract_cifa_significance <- function(fit,dims) {
  estimated <- tryCatch(coef(fit,printSE=TRUE,rawug=TRUE,simplify=FALSE,verbose=FALSE),error=function(e) NULL)
  if(is.null(estimated)) return(data.frame(Item=character(),Dimension=character(),Loading=double(),SE=double(),z=double(),p=double(),stringsAsFactors=FALSE))
  rows <- list(); factor_names <- names(dims)
  for(dimension in names(dims)) for(current_item in dims[[dimension]]) {
    tab <- estimated[[current_item]]; column <- paste0("a",match(dimension,factor_names)); if(is.null(tab) || !(column %in% colnames(tab))) next
    estimate <- as.numeric(tab["par",column]); se <- if("SE" %in% rownames(tab)) as.numeric(tab["SE",column]) else NA_real_
    z <- if(is.finite(se) && se>0) estimate/se else NA_real_; p <- if(is.finite(z)) 2*pnorm(abs(z),lower.tail=FALSE) else NA_real_
    rows[[length(rows)+1L]] <- data.frame(Item=cifa_to_orig_item(current_item),Dimension=dimension,Loading=estimate,SE=se,z=z,p=p,stringsAsFactors=FALSE)
  }
  if(length(rows)) do.call(rbind,rows) else data.frame(Item=character(),Dimension=character(),Loading=double(),SE=double(),z=double(),p=double())
}

if(cfg$input$mode=="simulate") { sim <- simulate_irt_data(cfg$simulation); raw <- sim$data; source_label <- paste0("simulated_",sim$model); items <- names(raw) } else { cfg$input$path <- resolve_path(cfg$input$path,base_dir); raw <- read_irt_data(cfg$input$path); source_label <- tools::file_path_sans_ext(basename(cfg$input$path)); items <- cfg$input$item_columns %||% "auto" }
prep <- prepare_items(raw,items,cfg$input$id_column); x <- prep$x; items <- prep$items
n_before <- nrow(x); total_cells <- nrow(x)*ncol(x); missing_cells_n <- sum(is.na(x)); missing_cells_pct <- 100*missing_cells_n/total_cells
analysis_rows <- seq_len(n_before); analysis_id <- if(!is.null(cfg$input$id_column) && cfg$input$id_column %in% names(raw)) raw[[cfg$input$id_column]] else analysis_rows
person_missing <- data.frame(Row=analysis_rows,ID=analysis_id,Missing_n=rowSums(is.na(x)),Missing_pct=round(100*rowMeans(is.na(x)),2),check.names=FALSE)
item_missing <- data.frame(Item=names(x),Observed_n=colSums(!is.na(x)),Missing_n=colSums(is.na(x)),Missing_pct=round(100*colMeans(is.na(x)),2),check.names=FALSE)
if(any(item_missing$Observed_n<2)) stopf("At least two observed responses are required for every item. Insufficient data: %s",paste(item_missing$Item[item_missing$Observed_n<2],collapse=", "))
# 整行全缺失的被试：没有任何题目反应，无论哪种缺失策略都无法进入模型估计，也不应计入 n_after 口径。
# 对所有 missing 策略统一在拟合前显式剔除（listwise 本来就会删掉它们，这里先剔除以保证统一计数、避免重复）。
all_missing <- rowSums(is.na(x))==ncol(x); all_missing_removed_n <- sum(all_missing)
if(all_missing_removed_n>0L) { say("剔除整行全缺失的被试 %d 人（无任何题目反应，无法提供能力信息，不进入模型估计）。",all_missing_removed_n); x <- x[!all_missing,,drop=FALSE]; analysis_rows <- analysis_rows[!all_missing]; analysis_id <- analysis_id[!all_missing]; if(nrow(x)<2) stopf("Removing respondents with no observed item responses left fewer than two respondents. Check the data or the missing-data strategy.") }
if(cfg$input$missing=="listwise") { keep <- complete.cases(x); removed_n <- sum(!keep); x <- x[keep,,drop=FALSE]; analysis_rows <- analysis_rows[keep]; analysis_id <- analysis_id[keep]; if(nrow(x)<2) stopf("Listwise deletion left fewer than two respondents. Choose missing: none or pairwise, or inspect the data.") } else removed_n <- 0L
n_after <- nrow(x); zero_var <- names(x)[vapply(x,function(z) length(unique(z[!is.na(z)]))<2,logical(1))]; if(length(zero_var)) stopf("Zero-variance items: %s",paste(zero_var,collapse=", "))
missing_note <- switch(cfg$input$missing,listwise="Complete cases were retained; respondents with any missing item response were excluded before fitting; respondents with no observed response at all are excluded under every strategy.",pairwise="pairwise is equivalent to none for model fitting: mirt fitted observed response patterns without any imputation; pairwise only affects the pairwise.complete.obs correlations used by the dimensionality heuristic. Respondents with no observed response at all are excluded under every strategy.",none="No preprocessing beyond excluding respondents with no observed response at all; mirt fitted observed response patterns directly without imputation, which is identical to the pairwise option.")
missing_summary <- data.frame(Original_N=n_before,Analysed_N=n_after,Items=ncol(x),Missing_cells_before=missing_cells_n,Missing_pct_before=round(missing_cells_pct,2),All_missing_removed=all_missing_removed_n,Listwise_removed=removed_n,Strategy=cfg$input$missing)
overview <- do.call(rbind,lapply(names(x),function(nm) { z <- x[[nm]]; u <- sort(unique(z[!is.na(z)])); data.frame(Item=nm,N=sum(!is.na(z)),Missing_pct=round(mean(is.na(z))*100,2),Min=min(z,na.rm=TRUE),Max=max(z,na.rm=TRUE),Categories=length(u),Least_category_n=min(table(z))) }))
category_counts <- vapply(x,function(z) length(unique(z[!is.na(z)])),integer(1)); binary <- all(category_counts==2L); response_type <- if(binary) "binary" else "ordered_polytomous"; requested_scoring <- tolower(cfg$analysis$response_format %||% "auto")
if(requested_scoring=="binary" && !binary) stopf("The configuration requested binary scoring, but the data contain ordered polytomous items.")
if(requested_scoring=="ordinal" && binary) say("Scoring note: data are binary; dichotomous IRT models will be used.")
requested <- cfg$analysis$model; is_mirt <- requested=="mirt"; mirt_mode <- cfg$analysis$mirt_mode
mirt_item_model <- cfg$analysis$mirt_item_model %||% "auto"
if(is_mirt && !binary && mirt_item_model %in% c("2pl","3pl")) stopf("Ordered polytomous data require multidimensional GRM/GPCM; 2PL/3PL are binary-only MIRT options.")
itemtype <- if(!is_mirt) { if(binary) "2PL" else if(requested=="gpcm") "gpcm" else "graded" } else if(!binary) { if(mirt_item_model=="gpcm") "gpcm" else "graded" } else if(mirt_item_model=="3pl") "3PL" else "2PL"
mirt_item_label <- if(itemtype=="graded") "GRM" else if(itemtype=="gpcm") "GPCM" else itemtype
if(is_mirt && mirt_mode=="cifa") dims <- if(!is.null(cfg$analysis$loading_matrix)) mapping_from_loading_matrix(cfg$analysis$loading_matrix,names(x)) else validate_dimension_mapping(cfg$analysis$dimension_mapping,names(x)) else dims <- NULL
# ── CIFA 语法安全化 ────────────────────────────────────────────────────────────
# mirt 的模型语法是字符串（如 "F1 = Item1,Item2"、"COV = F1*F2"），题目列名/维度名若含
# 空格、`-`、顿号、括号、前导数字，语法解析会失败或静默变形。内部改用 ASCII 安全名拟合，
# 输出表（载荷矩阵/显著性/题目参数）再按原名回显。
cifa_item_map <- NULL
cifa_dim_map <- NULL
if(is_mirt && mirt_mode=="cifa" && !is.null(dims)) {
  orig_items <- names(x)
  safe_items <- paste0("Item", seq_along(orig_items))
  dim_levels <- names(dims)
  safe_dims <- paste0("F", seq_along(dim_levels))
  cifa_item_map <- data.frame(orig = orig_items, safe = safe_items, stringsAsFactors = FALSE)
  cifa_dim_map <- stats::setNames(dim_levels, safe_dims)   # 安全维度名 -> 原始维度名
  xa <- x; names(xa) <- safe_items; x <- xa
  # 保持"每题归属哪个维度"的对应关系，把 dims 的值换成安全题目名、键换成安全维度名
  dims <- stats::setNames(split(safe_items, rep(safe_dims, lengths(dims))), safe_dims)
}
cifa_to_orig_item <- function(v) { if (is.null(cifa_item_map)) return(v); i <- match(v, cifa_item_map$safe); ifelse(is.na(i), v, cifa_item_map$orig[i]) }
cifa_to_orig_dim <- function(v) v
recommended_dim <- detect_dimensions(x,cfg$analysis$max_auto_dimensions %||% 6L)
if(is_mirt && mirt_mode=="eifa") { candidate_dims <- parse_dimension_range(cfg$analysis$dimension_range,cfg$analysis$max_auto_dimensions %||% 6L); if(is.null(candidate_dims)) candidate_dims <- seq_len(max(2L,recommended_dim)); dim_count <- recommended_dim } else dim_count <- if(!is.null(dims)) length(dims) else as.integer(cfg$analysis$dimension_count %||% recommended_dim)
say("Detected %s data: N=%d, items=%d; dimension recommendation=%d",response_type,nrow(x),ncol(x),recommended_dim)
fit_model <- function(model,itemtype_value=itemtype,se=FALSE,label="") { say("Fitting %s...",label); tryCatch(mirt(x,model=model,itemtype=itemtype_value,method=cfg$analysis$estimator %||% "EM",technical=list(NCYCLES=cfg$analysis$max_iterations),SE=se,verbose=FALSE),error=identity) }

if(is_mirt && mirt_mode=="eifa") {
  eifa_fits <- lapply(candidate_dims,function(d) { fit <- fit_model(d,se=FALSE,label=paste0(d,"D EIFA-",mirt_item_label)); list(dimension=d,fit=fit) })
  ok <- Filter(function(z) !inherits(z$fit,"error"),eifa_fits); if(!length(ok)) stopf("No EIFA model fitted: %s",paste(vapply(eifa_fits,function(z) if(inherits(z$fit,"error")) conditionMessage(z$fit) else "",character(1)),collapse="; "))
  comparison <- do.call(rbind,lapply(ok,function(z) { out <- fit_statistics(z$fit,cfg$analysis$compute_m2 %||% TRUE); out$Model <- paste0("EIFA_",z$dimension,"D"); out$Dimensions <- z$dimension; out }))
  comparison <- comparison[order(comparison$BIC),,drop=FALSE]; chosen_row <- comparison[1L,]; chosen <- ok[[which(vapply(ok,function(z) z$dimension==chosen_row$Dimensions,logical(1)))[1L]]]; chosen_name <- "mirt"; selected_label <- paste0(chosen$dimension,"D EIFA-",mirt_item_label); model_mode_label <- "EIFA"
  eifa_dimension_comparison <- comparison
} else if(is_mirt && mirt_mode=="cifa") {
  cifa_fit <- fit_model(model_syntax(dims),se=TRUE,label=paste0(length(dims),"D CIFA-",mirt_item_label)); if(inherits(cifa_fit,"error")) stopf("CIFA model did not converge: %s",conditionMessage(cifa_fit))
  unidim_fit <- fit_model(1L,se=FALSE,label=paste0("Unidimensional ",mirt_item_label)); if(inherits(unidim_fit,"error")) stopf("The CIFA comparison model did not converge: %s",conditionMessage(unidim_fit))
  cifa_stats <- fit_statistics(cifa_fit,cfg$analysis$compute_m2 %||% TRUE); cifa_stats$Model <- "CIFA"; unidim_stats <- fit_statistics(unidim_fit,cfg$analysis$compute_m2 %||% TRUE); unidim_stats$Model <- paste0("Unidimensional_",mirt_item_label); comparison <- rbind(cifa_stats,unidim_stats)
  delta_fields <- c("CFI","RMSEA","AIC","BIC")
  cifa_vs_unidimensional <- data.frame(CIFA_model="CIFA",Unidimensional_model=unidim_stats$Model,stringsAsFactors=FALSE)
  for(metric in delta_fields) { cifa_vs_unidimensional[[paste0("Unidim_",metric)]] <- unidim_stats[[metric]][1]; cifa_vs_unidimensional[[paste0("CIFA_",metric)]] <- cifa_stats[[metric]][1]; cifa_vs_unidimensional[[paste0("Delta_",metric)]] <- cifa_stats[[metric]][1]-unidim_stats[[metric]][1] }
  chosen <- list(fit=cifa_fit,dimension=length(dims)); chosen_name <- "mirt"; selected_label <- paste0(length(dims),"D CIFA-",mirt_item_label); model_mode_label <- "CIFA"
} else {
  dim_for_auto <- cfg$analysis$dimension_count %||% recommended_dim; if(is.character(dim_for_auto) && tolower(dim_for_auto)=="auto") dim_for_auto <- recommended_dim; dim_for_auto <- as.integer(dim_for_auto)
  default_candidates <- function() { if(requested!="auto") return(requested); if(binary) { z <- c("rasch","2pl"); if(isTRUE(cfg$analysis$allow_3pl) && nrow(x)>=500) z <- c(z,"3pl"); if(dim_for_auto>1L) z <- c(z,"mirt"); z } else { z <- "grm"; if(nrow(x)>=500) z <- c("grm","gpcm"); if(dim_for_auto>1L) z <- c(z,"mirt"); z } }
  candidates <- cfg$analysis$compare_models; if(is.null(candidates) || (length(candidates)==1L && tolower(candidates)=="auto")) candidates <- default_candidates(); candidates <- tolower(unlist(candidates)); if(!binary) candidates <- setdiff(candidates,c("rasch","2pl","3pl")); if(binary) candidates <- setdiff(candidates,c("grm","gpcm")); if(!length(candidates)) stopf("No compatible candidate model was specified.")
  regular_fits <- lapply(candidates,function(name) { model <- if(name=="mirt") dim_for_auto else 1L; it <- if(binary) if(name=="rasch") "Rasch" else if(name=="3pl") "3PL" else "2PL" else if(name=="gpcm") "gpcm" else "graded"; list(name=name,fit=fit_model(model,it,FALSE,if(name=="mirt") paste0(dim_for_auto,"D MIRT") else toupper(name))) })
  ok <- Filter(function(z)!inherits(z$fit,"error"),regular_fits); if(!length(ok)) stopf("No model fitted: %s",paste(vapply(regular_fits,function(z) if(inherits(z$fit,"error")) conditionMessage(z$fit) else "",character(1)),collapse="; "))
  comparison <- do.call(rbind,lapply(ok,function(z) { out <- fit_statistics(z$fit,cfg$analysis$compute_m2 %||% TRUE); out$Model <- z$name; out })); criterion <- cfg$analysis$selection_criterion %||% "BIC"; comparison <- comparison[order(comparison[[criterion]]),,drop=FALSE]
  chosen <- if(requested=="auto") ok[[which(vapply(ok,function(z) z$name==comparison$Model[1L],logical(1)))[1L]]] else ok[[which(vapply(ok,function(z) z$name==requested,logical(1)))[1L]]]; if(is.null(chosen)) stopf("Requested model did not converge.")
  chosen$dimension <- if(chosen$name=="mirt") dim_for_auto else 1L; chosen_name <- chosen$name; selected_label <- if(chosen$name=="mirt") paste0(dim_for_auto,"D MIRT") else toupper(chosen$name); model_mode_label <- if(chosen$name=="mirt") "Legacy MIRT" else "Single-model/automatic"
}

stamp <- format(Sys.time(),"%Y%m%d_%H%M%S"); prefix <- paste(cfg$output$project_label,if(is_mirt) paste0("mirt_",tolower(model_mode_label)) else chosen_name,stamp,sep="_"); out <- file.path(cfg$output$directory,prefix); dir.create(out,recursive=TRUE,showWarnings=FALSE); fn <- function(s,ext="csv") file.path(out,paste0(prefix,"_",s,".",ext))
# Selected 必须是**本次实际使用**的那个模型。早先写的是"BIC 最优那一行"，
# 于是当用户在配置里显式钉死 model: 3pl（同时用 compare_models 并列比较 2pl/3pl）时，
# 推荐表会把 2pl 标成 Selected=TRUE，而实际拟合与报告用的都是 3PL——表与运行自相矛盾。
selected_model_label <- if(is_mirt && mirt_mode=="eifa") comparison$Model[1L] else if(is_mirt && mirt_mode=="cifa") "CIFA" else chosen_name
recommendation <- data.frame(Rank=seq_len(nrow(comparison)),Model=comparison$Model,BIC=comparison$BIC,Selected=comparison$Model==selected_model_label,stringsAsFactors=FALSE)
write.csv(comparison,fn("model_comparison"),row.names=FALSE); write.csv(recommendation,fn("model_recommendation"),row.names=FALSE); write.csv(overview,fn("item_overview"),row.names=FALSE); write.csv(missing_summary,fn("missingness_summary"),row.names=FALSE); write.csv(person_missing,fn("person_missingness"),row.names=FALSE); write.csv(item_missing,fn("item_missingness"),row.names=FALSE)
if(exists("eifa_dimension_comparison")) write.csv(eifa_dimension_comparison,fn("eifa_dimension_comparison"),row.names=FALSE)
if(exists("cifa_vs_unidimensional")) write.csv(cifa_vs_unidimensional,fn("cifa_vs_unidimensional"),row.names=FALSE)
if(cfg$input$mode=="simulate") { write.csv(raw,fn("simulated_responses"),row.names=FALSE); write.csv(sim$truth,fn("simulation_truth"),row.names=FALSE); write.csv(sim$theta,fn("simulation_true_theta"),row.names=FALSE) }
co <- coef(chosen$fit,simplify=TRUE); pars <- as.data.frame(co$items); pars$Item <- rownames(pars)
# CIFA 路线内部用安全名（Item1…/F1…）拟合；这里把 Item 列翻回用户原始题目名再写出
pars$Item <- cifa_to_orig_item(pars$Item)
# 判别力列：只取 a1..aD（各维度的斜率）。**必须排除 GPCM 的类别乘子列 ak0..ak4**——
# mirt 的 gpcm 记作 P(X=k) ∝ exp(k·(a'θ) + d_k)，coef() 除 a1..aD 外还会带回
# ak0..ak4 = 0,1,2,3,4 这些类别序号乘子。早先的 grep("^a") 把它们当成维度载荷，于是
#   MDISC = sqrt(Σaⱼ² + Σak_k²)   → 单维 gpcm 实测 5.536，而该题 a 只有 0.805；
#   b_d*  被同一个因子整体压错；Primary_dimension 还会输出 "ak4" 这种并不存在的维度。
acols <- grep("^a[0-9]+$",names(pars),value=TRUE)
# Rasch/1PL 等斜率固定的模型，mirt 的 coef() 可能**不返回 a 列**（斜率是固定参数）。
# 此时 MDISC = sqrt(0) = 0 → b_ = -d/0 = ±Inf，会被直接写进 item_parameters.csv 与中英文
# 报告表格。这里显式补 a = 1 并断言 MDISC > 0，避免把 Inf 打进发表用表格。
if(!length(acols)) { pars$a1 <- 1; acols <- "a1" }
pars$MDISC <- sqrt(rowSums(as.matrix(pars[acols])^2))
if(any(!is.finite(pars$MDISC)) || any(pars$MDISC <= 0)) {
  say("警告：判别力 MDISC 出现 0/非有限值（a 列=%s），b 参数将不可用；已按 NA 处理。", paste(acols,collapse=","))
  pars$MDISC[!is.finite(pars$MDISC) | pars$MDISC <= 0] <- NA_real_
}
# b 列换算分两种口径（这也是 mirt 自己的口径）：
#   · GRM / MIRT-GRM：d_k 本身就是阈值        → b_k = -d_k / MDISC（与 mirt 的
#     coef(fit, IRTpars=TRUE) 逐题相同，已实测最大绝对差 = 0）。
#   · GPCM / MGPCM  ：mirt 的 d_k 是**类别截距**（含参考类别 d0 ≡ 0），标准台阶难度是
#     **相邻截距之差** b_k = -(d_k - d_{k-1}) / MDISC。若照搬 -d_k/MDISC 得到的是
#     "累积和"：既不单调、也没有台阶含义，还会多出一列恒为 0 的 b_d0。
dcols <- grep("^d([0-9]+)?$",names(pars),value=TRUE)
if(any(grepl("^ak[0-9]+$",names(pars))) && length(dcols)>1L) {
  dcum <- as.matrix(pars[dcols])
  dstep <- dcum[,-1L,drop=FALSE] - dcum[,-ncol(dcum),drop=FALSE]
  for(j in seq_len(ncol(dstep))) pars[[paste0("b_d",j)]] <- -dstep[,j]/pars$MDISC
} else for(j in dcols) pars[[paste0("b_",j)]] <- -pars[[j]]/pars$MDISC
owner <- if(length(acols)>1L) colnames(pars[acols])[max.col(abs(as.matrix(pars[acols])),ties.method="first")] else rep("F1",nrow(pars)); pars$Primary_dimension <- owner; write.csv(pars,fn("item_parameters"),row.names=FALSE)
if(is_mirt && mirt_mode=="eifa") {
  rotation <- tryCatch(summary(chosen$fit,rotate="oblimin",verbose=FALSE),error=function(e) NULL)
  if(!is.null(rotation)) { rotated <- as.data.frame(rotation$rotF); rotated$Item <- rownames(rotated); rotated$h2 <- as.numeric(rotation$h2); write.csv(rotated,fn("eifa_rotated_loadings"),row.names=FALSE); corr <- rotation$fcor } else corr <- co$cov
  r <- suppressWarnings(cor(x,use="pairwise.complete.obs")); r[is.na(r)] <- 0; diag(r) <- 1; eig <- eigen(r,symmetric=TRUE,only.values=TRUE)$values; write.csv(data.frame(Component=seq_along(eig),Eigenvalue=eig),fn("eifa_eigenvalues"),row.names=FALSE)
} else { corr <- co$cov }
if(is_mirt && mirt_mode=="cifa") {
  loading_matrix <- data.frame(Item = cifa_to_orig_item(rownames(pars)), as.data.frame(as.matrix(pars[acols]), check.names = FALSE), check.names = FALSE)
  names(loading_matrix)[-1L] <- if(is.null(cifa_dim_map)) names(dims) else unname(cifa_dim_map[names(dims)])
  write.csv(loading_matrix,fn("cifa_loading_matrix"),row.names=FALSE)
  write.csv(extract_cifa_significance(chosen$fit,dims),fn("cifa_loading_significance"),row.names=FALSE)
}
tryCatch(plot_irt_curves(chosen$fit,x,pars,acols,owner,fn,cfg),error=function(e) say("Curve generation skipped: %s",conditionMessage(e)))
item_fit <- tryCatch(as.data.frame(itemfit(chosen$fit,method="S_X2",na.rm=TRUE)),error=function(e) NULL); if(!is.null(item_fit)) { item_fit$item <- cifa_to_orig_item(item_fit$item); item_fit$Item <- item_fit$item; pc <- grep("^p\\.S_X2$",names(item_fit),value=TRUE); if(!length(pc)) stopf("S-X2 item fit table has no p.S_X2 column (columns: %s); cannot run BH correction.",paste(names(item_fit),collapse=", ")); item_fit$BH_p <- p.adjust(item_fit[[pc]],"BH"); write.csv(item_fit,fn("item_fit"),row.names=FALSE) }
fs_mat <- fscores(chosen$fit,method="MAP",full.scores=TRUE,full.scores.SE=TRUE); theta <- as.data.frame(fs_mat); if(!is.null(cfg$input$id_column) && cfg$input$id_column %in% names(raw)) theta <- cbind(setNames(data.frame(analysis_id),cfg$input$id_column),theta); write.csv(theta,fn("ability_estimates"),row.names=FALSE)
tcols <- grep("^F[0-9]+$|^Theta",names(theta),value=TRUE); if(!length(tcols)) tcols <- names(theta)[vapply(theta,is.numeric,logical(1))][seq_len(min(chosen$dimension,sum(vapply(theta,is.numeric,logical(1)))))]
theta_summary <- data.frame(Dimension=tcols,N_valid=vapply(theta[tcols],function(z) sum(!is.na(z)),integer(1)),Mean=sapply(theta[tcols],mean,na.rm=TRUE),SD=sapply(theta[tcols],sd,na.rm=TRUE),Min=sapply(theta[tcols],min,na.rm=TRUE),Max=sapply(theta[tcols],max,na.rm=TRUE)); write.csv(theta_summary,fn("ability_summary"),row.names=FALSE)
# 边际/经验信度：marginal_rxx 基于模型隐含分布，仅适用于单维模型（多维会报错，按 NA 处理）；
# empirical_rxx 直接接收 fscores(full.scores.SE=TRUE) 的完整矩阵（按列名拆分 F 与 SE_ 列），逐维度给出经验信度。
align_rel <- function(v,n) if(length(v)==n) suppressWarnings(as.numeric(v)) else if(length(v)==1L && !is.na(suppressWarnings(as.numeric(v)))) rep(suppressWarnings(as.numeric(v)),n) else rep(NA_real_,n)
rel_marginal <- tryCatch(mirt::marginal_rxx(chosen$fit),error=function(e) NA_real_)
rel_empirical <- tryCatch(mirt::empirical_rxx(fs_mat),error=function(e) NA_real_)
reliability <- data.frame(Dimension=tcols,Marginal_rxx=align_rel(rel_marginal,length(tcols)),Empirical_rxx=align_rel(rel_empirical,length(tcols)),check.names=FALSE); write.csv(reliability,fn("reliability"),row.names=FALSE)
tl <- stack(theta[tcols]); names(tl) <- c("Theta","Dimension"); p <- ggplot(tl,aes(Theta))+geom_histogram(bins=30,fill="#2C7FB8",colour="white")+facet_wrap(~Dimension,scales="free")+theme_minimal(base_size=11)+labs(title="MAP ability distributions"); ggsave(fn("theta_distribution","png"),p,width=9,height=4,dpi=300)
if(!is.null(corr) && nrow(corr)>1L) { corr <- cov2cor(corr); write.csv(corr,fn("dimension_correlations")) }
long <- stack(x); names(long) <- c("Response","Item"); long <- long[!is.na(long$Response),]; p <- ggplot(long,aes(factor(Response)))+geom_bar(fill="#2C7FB8")+facet_wrap(~Item,scales="free_y")+theme_minimal(base_size=10)+labs(title="Response distributions",x="Category",y="Count"); ggsave(fn("response_distributions","png"),p,width=12,height=max(5,ceiling(ncol(x)/6)*2.2),dpi=300)
mdtable <- function(z,d=3) { z <- as.data.frame(z); z[] <- lapply(z,function(v) if(is.numeric(v)) format(round(v,d),trim=TRUE) else as.character(v)); paste(c(paste(names(z),collapse=" | "),paste(rep("---",ncol(z)),collapse=" | "),apply(z,1,paste,collapse=" | ")),collapse="\n") }
zh <- c("# IRT 自动分析报告","",sprintf("## %s",model_mode_label),sprintf("本次分析原始数据包含 %d 名被试与 %d 个项目；进入模型估计的被试数为 %d。缺失值策略为 `%s`：%s",n_before,ncol(x),n_after,cfg$input$missing,missing_note),"","## 数据与缺失值",mdtable(missing_summary),"","## 结果",mdtable(comparison),"","### 信度估计","边际信度（marginal_rxx）基于模型隐含的误差分布，仅适用于单维模型；经验信度（empirical_rxx）基于 MAP 能力估计值及其标准误逐维度计算；NA 表示该指标在当前模型/估计方式下不可用。",mdtable(reliability),"","### 项目参数",mdtable(pars),"","### 能力估计",mdtable(theta_summary),"","## 讨论与限制","模型选择不替代理论结构、计分方向、局部独立性和 DIF 检验。能力估计采用 MAP（最大后验）方法，存在向均值收缩（回归均值）的倾向，极端能力会被低估；解读极端组时应结合标准误（SE）。图形与表格均见同目录输出文件。")
en <- c("# Automated IRT Analysis Report","",sprintf("## %s",model_mode_label),sprintf("The original data contained %d respondents and %d items; %d respondents entered estimation. Missing-data strategy `%s`: %s",n_before,ncol(x),n_after,cfg$input$missing,missing_note),"","## Data and missingness",mdtable(missing_summary),"","## Results",mdtable(comparison),"","### Reliability","Marginal reliability (marginal_rxx) is derived from the model-implied error distribution and is defined for unidimensional models only; empirical reliability (empirical_rxx) is computed per dimension from the MAP ability estimates and their standard errors; NA indicates the value is unavailable for the selected model or scoring method.",mdtable(reliability),"","### Item parameters",mdtable(pars),"","### Ability estimates",mdtable(theta_summary),"","## Discussion and limitations","Model selection does not replace construct theory, scoring-direction checks, local-dependence diagnostics, or DIF analyses. MAP ability estimates shrink toward the mean, so extreme abilities are underestimated; interpret extreme groups alongside their standard errors. Figures and tables are stored in this result directory.")
langs <- cfg$output$report_languages %||% c("zh","en"); if("zh"%in%langs) writeLines(zh,fn("report_zh","md")); if("en"%in%langs) writeLines(en,fn("report_en","md")); snapshot_ext <- if(config_ext=="json") "json" else "yaml"; file.copy(config_path,fn("config_snapshot",snapshot_ext),overwrite=TRUE); if(isTRUE(cfg$output$save_model_object %||% TRUE)) saveRDS(chosen$fit,fn("selected_model","rds"))
write_run_manifest(out, cfg, c("mirt", "psych", "GPArotation", "readxl", "haven", "yaml", "jsonlite"), model_mode_label, config_path,
  extra = list(model = chosen_name, mirt_mode = if (is_mirt) mirt_mode else "not_applicable",
               mirt_item_model = if (is_mirt) mirt_item_label else "not_applicable",
               response_type = response_type, dimension_count = chosen$dimension, source = source_label,
               missing_strategy = cfg$input$missing, n_before = n_before, n_after = n_after,
               missing_cells_before_n = missing_cells_n, missing_cells_before_pct = round(missing_cells_pct, 2),
               listwise_removed_n = removed_n))
auto_bic_ranking <- if(requested=="auto") paste(sprintf("%s=%.2f",comparison$Model,comparison$BIC),collapse=" | ") else NULL
say("Selected model: %s",selected_label); if(!is.null(auto_bic_ranking)) cat("AUTO_BIC_RANKING=",auto_bic_ranking,"\n",sep=""); result_path <- enc2utf8(normalizePath(out)); result_hex <- paste(sprintf("%02X",as.integer(charToRaw(result_path))),collapse=""); cat("RESULT_DIR_UTF8_HEX=",result_hex,"\n",sep=""); cat("RESULT_DIR=",result_path,"\n",sep="")