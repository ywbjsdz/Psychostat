#!/usr/bin/env Rscript
suppressWarnings(suppressPackageStartupMessages({library(yaml); library(jsonlite); library(mirt); library(readxl); library(haven)}))
script_arg <- commandArgs(FALSE)[grep("^--file=",commandArgs(FALSE))][1]
source(file.path(dirname(normalizePath(sub("^--file=","",script_arg))),"irt_common.R"),encoding="UTF-8")
args <- commandArgs(trailingOnly=TRUE); output_pos <- match("--output-utf8-hex",args); output_path <- if(!is.na(output_pos) && output_pos<length(args)) hex_to_utf8(args[output_pos+1]) else NULL
emit <- function(payload,status=0L) { json <- jsonlite::toJSON(payload,auto_unbox=TRUE,null="null",na="null"); if(!is.null(output_path)) { writeLines(enc2utf8(json),output_path,useBytes=TRUE); cat("PREFLIGHT_FILE_WRITTEN=1\n") } else cat("PREFLIGHT_JSON=",json,"\n",sep=""); quit(save="no",status=status) }
main <- function() {
  loaded <- load_analysis_config(args); cfg <- normalise_config(loaded$cfg,dirname(loaded$path))
  if(cfg$input$mode=="simulate") { sim <- simulate_irt_data(cfg$simulation); raw <- sim$data; source_label <- paste0("simulated_",sim$model); cfg$input$id_column <- NULL; cfg$input$item_columns <- names(raw) }
  else if(cfg$input$mode=="file") { input_path <- resolve_path(cfg$input$path,dirname(loaded$path)); raw <- read_irt_data(input_path); source_label <- basename(input_path) } else stopf("input.mode must be file or simulate.")
  prep <- prepare_items(raw,cfg$input$item_columns,cfg$input$id_column); x <- prep$x; observed <- colSums(!is.na(x)); category_counts <- vapply(x,function(z) length(unique(z[!is.na(z)])),integer(1)); zero_var <- names(x)[category_counts<2L]; all_missing <- names(x)[observed==0L]
  # 被自动识别排除的退化列（整列全缺失 / 零方差）必须显式报告：否则它们根本进不了 x，
  # 下面两条 fatal 检查就永远不会触发，用户只会发现"题目少了几道"。
  # 仅当题目列由 auto 识别时统计（未配置 item_columns 时 prepare_items 也按 auto 处理；显式列出时上面的检查已覆盖）
  item_cols <- cfg$input$item_columns
  auto_items <- is.null(item_cols) || (is.character(item_cols) && length(item_cols)==1L && tolower(item_cols)=="auto")
  deg <- if(auto_items) degenerate_item_columns(raw,cfg$input$id_column) else NULL
  deg_tbl <- if(is.null(deg)) data.frame(item=character(),reason=character(),detail=character(),stringsAsFactors=FALSE) else deg
  fatal <- character(); warnings <- character(); if(length(all_missing)) fatal <- c(fatal,paste0("以下题目全部缺失：",paste(all_missing,collapse="、"))); if(length(zero_var)) fatal <- c(fatal,paste0("以下题目没有变异（零方差）：",paste(zero_var,collapse="、")))
  missing_pct <- round(100*mean(is.na(x)),2); item_missing <- data.frame(item=names(x),missing_n=colSums(is.na(x)),missing_pct=round(100*colMeans(is.na(x)),2),stringsAsFactors=FALSE); if(missing_pct>10) warnings <- c(warnings,sprintf("总体缺失率为 %.2f%%，建议核查缺失机制与处理策略。",missing_pct)); high_missing <- item_missing$item[item_missing$missing_pct>20]; if(length(high_missing)) warnings <- c(warnings,paste0("以下题目缺失率超过 20%：",paste(high_missing,collapse="、")))
  rare <- names(x)[vapply(x,function(z) { tab <- table(z,useNA="no"); length(tab)&&any(tab<max(5,ceiling(sum(tab)*.01))) },logical(1))]; if(length(rare)) warnings <- c(warnings,paste0("以下题目存在极少使用的反应类别：",paste(rare,collapse="、")))
  if(nrow(deg_tbl)) warnings <- c(warnings,paste0("自动识别已排除退化列（不作为题目参与估计）：",
    paste(sprintf("%s（%s）",deg_tbl$item,deg_tbl$detail),collapse="、"),
    "。整列全缺失通常意味着数据导出不完整；如这些列本就是题目，请修正数据或显式列出题目列。"))
  scoring <- if(all(category_counts==2L)) "binary" else "ordered_polytomous"; requested_scoring <- tolower(cfg$analysis$response_format %||% "auto"); if(requested_scoring=="binary" && scoring!="binary") fatal <- c(fatal,"选择了二分计分，但数据中存在多级题目；请改选有序多级/自动识别或清理数据。"); if(requested_scoring=="ordinal" && scoring=="binary") warnings <- c(warnings,"数据实际为二分计分；将按二分模型处理。")
  requested_model <- tolower(cfg$analysis$model %||% "auto"); if(scoring=="ordered_polytomous" && requested_model %in% c("rasch","2pl","3pl")) fatal <- c(fatal,"多级有序数据不能直接拟合 Rasch/2PL/3PL；请选择 GRM、MIRT 或自动选模。")
  if(requested_model=="mirt") {
    mirt_item_model <- cfg$analysis$mirt_item_model %||% "auto"
    if(scoring=="ordered_polytomous" && mirt_item_model %in% c("2pl","3pl")) fatal <- c(fatal,"多级有序数据的 MIRT 应使用多维 GRM/GPCM；多维 2PL/3PL 仅适用于二分数据。")
    if(scoring=="binary" && mirt_item_model %in% c("grm","gpcm")) fatal <- c(fatal,"二分数据的 MIRT 应使用多维 2PL 或 3PL；请改为 auto、2pl 或 3pl。")
    if(nrow(x)<200) warnings <- c(warnings,"MIRT 样本量低于 200，参数与拟合指标可能不稳定。")
    mode <- cfg$analysis$mirt_mode %||% "eifa"
    check <- tryCatch({ if(mode=="cifa") { if(!is.null(cfg$analysis$loading_matrix)) mapping_from_loading_matrix(cfg$analysis$loading_matrix,names(x)) else validate_dimension_mapping(cfg$analysis$dimension_mapping,names(x)) } else parse_dimension_range(cfg$analysis$dimension_range,cfg$analysis$max_auto_dimensions %||% 6L); NULL },error=function(e) conditionMessage(e))
    if(!is.null(check)) fatal <- c(fatal,paste0("MIRT 设置无效：",check))
  }
  # 通用小样本警告：IRT 参数估计对样本量敏感（2PL 每题多估一个区分度；多级/3PL 参数更多）。
  # 原来只有 MIRT 分支里一条"低于 200"的提示，n=30 跑 2PL/GRM 会毫无提示地出结果。
  # 因此放在 mirt 分支**之外**，对全部 IRT 路线生效。
  .n <- nrow(x); .many_param <- (scoring!="binary") || (tolower(cfg$analysis$model %||% "auto") %in% c("3pl","gpcm"))
  if(.n<50) warnings <- c(warnings,sprintf("样本量仅 %d：IRT 参数估计极不稳定，结果仅供流程演示，不要用于结论。",.n))
  else if(.n<100 && .many_param) warnings <- c(warnings,sprintf("样本量 %d 且模型参数较多（多级/3PL/GPCM）：参数估计不稳定，建议 N≥250-500。",.n))
  list(status=if(length(fatal))"fatal" else if(length(warnings))"warning" else "ok",source=source_label,sample_size=nrow(x),item_count=ncol(x),scoring=scoring,category_min=min(category_counts),category_max=max(category_counts),missing_pct=missing_pct,zero_variance=zero_var,item_missing=item_missing,rare_category_items=rare,excluded_degenerate_columns=deg_tbl,fatal=fatal,warnings=warnings,detected_items=names(x))
}
tryCatch(emit(main()),error=function(e) emit(list(status="fatal",sample_size=NA,item_count=NA,fatal=paste0("数据体检无法完成：",conditionMessage(e)),warnings=character()),2L))