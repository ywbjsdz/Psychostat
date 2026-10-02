#!/usr/bin/env Rscript
# Psychostat CTT/IRT third-party review, round 3.  Independent-engine audit only.
# Run: D:/学习/R-4.5.2/bin/Rscript.exe --vanilla tests/thirdparty/round3/review_round3.R

suppressPackageStartupMessages(library(TAM))
root <- normalizePath(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1])), "..", "..", ".."), winslash = "/", mustWork = TRUE)
out <- file.path(root, "tests", "thirdparty", "round3", "results")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

write_csv <- function(x, nm) write.csv(x, file.path(out, nm), row.names = FALSE, fileEncoding = "UTF-8")
write_txt <- function(x, nm) writeLines(x, file.path(out, nm), useBytes = TRUE)
readcsv <- function(...) read.csv(..., check.names = FALSE, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")
time_fit <- function(expr) {
  t0 <- proc.time()[["elapsed"]]
  z <- tryCatch(force(expr), error = function(e) e)
  list(value = z, elapsed = proc.time()[["elapsed"]] - t0)
}
fit_tam <- function(resp, Q, irtmodel, maxiter = 500L) {
  time_fit(TAM::tam.mml.2pl(resp = resp, Q = Q, irtmodel = irtmodel,
                             control = list(maxiter = maxiter, progress = FALSE)))
}
status_row <- function(name, z, n, p, dims, model) {
  data.frame(task = name, n = n, items = p, dimensions = dims, model = model,
             elapsed_seconds = z$elapsed, returned_parameters = !inherits(z$value, "error"),
             status = if (inherits(z$value, "error")) "error" else "ok",
             message = if (inherits(z$value, "error")) conditionMessage(z$value) else "",
             stringsAsFactors = FALSE)
}

# G1 calibration: same single-dimensional GPCM response matrix as the stored mirt result.
b_data <- readcsv(file.path(root, "examples", "simulated_datasets", "irt_B_polytomous_grm_n600_items15.csv"))
b_resp <- as.matrix(b_data) - min(as.matrix(b_data), na.rm = TRUE)
b_q <- matrix(1, ncol(b_resp), 1L, dimnames = list(colnames(b_resp), "F1"))
g1_cal <- fit_tam(b_resp, b_q, "GPCM")
write_csv(status_row("G1_calibration_1D", g1_cal, nrow(b_resp), ncol(b_resp), 1L, "GPCM"), "G1_feasibility.csv")
if (!inherits(g1_cal$value, "error")) {
  write_txt(capture.output(str(g1_cal$value, max.level = 2)), "G1_calibration_TAM_structure.txt")
  saveRDS(g1_cal$value, file.path(out, "G1_calibration_TAM_fit.rds"))
}

# G1 route A: first two dimensional blocks and n=200, as prescribed.
g_data <- readcsv(file.path(root, "examples", "simulated_datasets", "irt_G_multidimensional_gpcm_n900_items24.csv"))
g_map <- readcsv(file.path(root, "examples", "simulated_datasets", "irt_G_loading_matrix.csv"))
keep_dims <- sort(unique(g_map$dimension))[1:2]
keep_items <- g_map$item[g_map$dimension %in% keep_dims]
g_resp <- as.matrix(g_data[seq_len(200), keep_items, drop = FALSE]) - min(as.matrix(g_data), na.rm = TRUE)
g_q <- matrix(0, length(keep_items), length(keep_dims), dimnames = list(keep_items, keep_dims))
g_q[cbind(match(g_map$item[g_map$dimension %in% keep_dims], keep_items), match(g_map$dimension[g_map$dimension %in% keep_dims], keep_dims))] <- 1
g1_2d <- fit_tam(g_resp, g_q, "GPCM")
feas <- rbind(readcsv(file.path(out, "G1_feasibility.csv")), status_row("G1_routeA_2D", g1_2d, nrow(g_resp), ncol(g_resp), 2L, "GPCM"))
write_csv(feas, "G1_feasibility.csv")
if (!inherits(g1_2d$value, "error")) {
  write_txt(capture.output(str(g1_2d$value, max.level = 2)), "G1_2D_TAM_structure.txt")
  saveRDS(g1_2d$value, file.path(out, "G1_2D_TAM_fit.rds"))
}

# Same two-dimensional subset at n=900: this is the direct comparison run against the stored mirt CIFA output.
g_resp_full <- as.matrix(g_data[, keep_items, drop = FALSE]) - min(as.matrix(g_data), na.rm = TRUE)
g1_2d_full <- fit_tam(g_resp_full, g_q, "GPCM")
feas <- rbind(readcsv(file.path(out, "G1_feasibility.csv")), status_row("G1_routeA_2D_fullN", g1_2d_full, nrow(g_resp_full), ncol(g_resp_full), 2L, "GPCM"))
write_csv(feas, "G1_feasibility.csv")
if (!inherits(g1_2d_full$value, "error")) {
  write_txt(capture.output(str(g1_2d_full$value, max.level = 2)), "G1_2D_fullN_TAM_structure.txt")
  saveRDS(g1_2d_full$value, file.path(out, "G1_2D_fullN_TAM_fit.rds"))
}

# TAM parameterization: B[Cat k, Dim j] = k*a_j; AXsi_[Cat k] = -d_k.
# Hence a_j=B.Cat1.Dimj and b_dk=(AXsi_.Catk-AXsi_.Cat(k-1))/sqrt(sum_j a_j^2), AXsi_.Cat0=0.
tam_gpcm_params <- function(fit, dims, expected_q = NULL) {
  it <- fit$item
  ans <- list(); z <- 0L
  for (i in seq_len(nrow(it))) {
    av <- vapply(seq_along(dims), function(j) it[[paste0("B.Cat1.Dim", j)]][i], numeric(1))
    md <- sqrt(sum(av^2))
    for (j in seq_along(dims)) {
      if (is.null(expected_q) || expected_q[i, j] == 1) { z <- z + 1L; ans[[z]] <- data.frame(Item=it$item[i], dimension=dims[j], parameter="a", TAM=av[j]) }
    }
    prev <- 0
    for (k in 1:4) {
      xk <- it[[paste0("AXsi_.Cat", k)]][i]
      z <- z + 1L; ans[[z]] <- data.frame(Item=it$item[i], dimension=if (is.null(expected_q)) dims[1] else dims[which.max(expected_q[i, ])], parameter=paste0("b_d", k), TAM=(xk-prev)/md)
      prev <- xk
    }
  }
  do.call(rbind, ans)
}
metric_rows <- function(x, label) {
  splitx <- split(x, x$parameter)
  do.call(rbind, lapply(names(splitx), function(nm) { q <- splitx[[nm]]; data.frame(run=label, parameter=nm, n=nrow(q), r=cor(q$tool, q$TAM), mean_difference=mean(q$TAM-q$tool), RMSE=sqrt(mean((q$TAM-q$tool)^2)), max_abs_difference=max(abs(q$TAM-q$tool))) }))
}
# Calibration comparison: identical 1-D GPCM data, stored mirt parameters versus independent TAM refit.
if (!inherits(g1_cal$value, "error")) {
  tool <- readcsv(file.path(root, "outputs", "irt_analysis_gpcm_20260917_212101", "irt_analysis_gpcm_20260917_212101_item_parameters.csv"))
  tm <- tam_gpcm_params(g1_cal$value, "F1")
  tt <- rbind(data.frame(Item=tool$Item, dimension="F1", parameter="a", tool=tool$a1),
              do.call(rbind, lapply(1:4, function(k) data.frame(Item=tool$Item, dimension="F1", parameter=paste0("b_d",k), tool=tool[[paste0("b_d",k)]]))))
  cmp <- merge(tt, tm, by=c("Item","dimension","parameter"))
  write_csv(cmp, "G1_calibration_parameter_comparison.csv")
  write_csv(metric_rows(cmp, "G1_calibration_1D"), "G1_parameter_metrics.csv")
}
# Route A comparison: the n=900 TAM fit and the n=900 mirt CIFA output fit the same 16 items/2-D Q matrix.
if (exists("g1_2d_full") && !inherits(g1_2d_full$value, "error")) {
  tool <- readcsv(file.path(root, "outputs", "irt_analysis_mirt_cifa_20260918_091928", "irt_analysis_mirt_cifa_20260918_091928_item_parameters.csv"))
  tool <- tool[match(keep_items, tool$Item), , drop=FALSE]
  tm <- tam_gpcm_params(g1_2d_full$value, keep_dims, g_q)
  tt <- list(); z <- 0L
  for (i in seq_along(keep_items)) {
    j <- which(g_q[i, ] == 1)
    z <- z + 1L; tt[[z]] <- data.frame(Item=keep_items[i], dimension=keep_dims[j], parameter="a", tool=tool[[paste0("a",j)]][i])
    for (k in 1:4) { z <- z + 1L; tt[[z]] <- data.frame(Item=keep_items[i], dimension=keep_dims[j], parameter=paste0("b_d", k), tool=tool[[paste0("b_d",k)]][i]) }
  }
  cmp <- merge(do.call(rbind,tt), tm, by=c("Item","dimension","parameter"))
  write_csv(cmp, "G1_2D_parameter_comparison.csv")
  raw_metrics <- metric_rows(cmp, "G1_routeA_2D_fullN")
  # Align latent scales on the slope anchor: a_mirt = scale * a_TAM and b_mirt = b_TAM / scale.
  scale_anchor <- with(cmp[cmp$parameter == "a", ], sum(tool * TAM) / sum(TAM^2))
  cmp_aligned <- cmp
  cmp_aligned$TAM <- ifelse(cmp_aligned$parameter == "a", cmp_aligned$TAM * scale_anchor, cmp_aligned$TAM / scale_anchor)
  aligned_metrics <- metric_rows(cmp_aligned, "G1_routeA_2D_scale_aligned")
  write_csv(data.frame(scale_anchor = scale_anchor), "G1_2D_scale_alignment.csv")
  write_csv(cmp_aligned, "G1_2D_parameter_comparison_scale_aligned.csv")
  write_csv(rbind(readcsv(file.path(out,"G1_parameter_metrics.csv")), raw_metrics, aligned_metrics), "G1_parameter_metrics.csv")
}
# G3: true second engine for the same unidimensional 2PL response model.
a_data <- readcsv(file.path(root, "examples", "simulated_datasets", "irt_A_binary_2pl_n800_items20.csv"))
a_resp <- as.matrix(a_data)
a_q <- matrix(1, ncol(a_resp), 1L, dimnames = list(colnames(a_resp), "F1"))
g3_tam <- fit_tam(a_resp, a_q, "2PL")
feas <- rbind(readcsv(file.path(out, "G1_feasibility.csv")), status_row("G3_TAM_2PL", g3_tam, nrow(a_resp), ncol(a_resp), 1L, "2PL"))
write_csv(feas, "G1_feasibility.csv")
if (!inherits(g3_tam$value, "error")) {
  write_txt(capture.output(str(g3_tam$value, max.level = 2)), "G3_TAM_2PL_structure.txt")
  saveRDS(g3_tam$value, file.path(out, "G3_TAM_2PL_fit.rds"))
  g3_mf <- time_fit(TAM::tam.modelfit(g3_tam$value))
  write_csv(data.frame(elapsed_seconds = g3_mf$elapsed, returned = !inherits(g3_mf$value, "error"),
                       message = if (inherits(g3_mf$value, "error")) conditionMessage(g3_mf$value) else ""), "G3_TAM_modelfit_status.csv")
  if (!inherits(g3_mf$value, "error")) {
    write_txt(capture.output(str(g3_mf$value, max.level = 3)), "G3_TAM_modelfit_structure.txt")
    saveRDS(g3_mf$value, file.path(out, "G3_TAM_modelfit.rds"))
    mirt_cmp <- readcsv(file.path(root, "outputs", "irt_analysis_2pl_20260918_091532", "irt_analysis_2pl_20260918_091532_model_comparison.csv"))
    mirt_2pl <- mirt_cmp[tolower(mirt_cmp$Model) == "2pl", , drop = FALSE]
    tf <- g3_mf$value$fitstat
    g3_compare <- data.frame(
      metric = c("M2*", "df", "SRMR", "SRMSR", "TLI", "CFI"),
      mirt_value = c(mirt_2pl$M2[1], mirt_2pl$df[1], mirt_2pl$SRMR[1], mirt_2pl$SRMSR[1], mirt_2pl$TLI[1], mirt_2pl$CFI[1]),
      TAM_value = c(NA_real_, NA_real_, unname(tf[["SRMR"]]), unname(tf[["SRMSR"]]), NA_real_, NA_real_),
      comparability = c("not comparable: TAM tam.modelfit has no M2* global statistic", "not comparable: TAM does not report M2* df", "definition requires documentation-level caution", "same residual-index label; numerical comparison allowed", "not comparable: TAM does not report TLI", "not comparable: TAM does not report CFI"),
      stringsAsFactors = FALSE)
    g3_compare$difference_TAM_minus_mirt <- g3_compare$TAM_value - g3_compare$mirt_value
    write_csv(g3_compare, "G3_mirt_TAM_fit_comparison.csv")
  }
}

# G2 independent-engine capability and an ordinal OpenMx likelihood attempt.
omx_ok <- requireNamespace("OpenMx", quietly = TRUE)
if (omx_ok) {
  suppressPackageStartupMessages(library(OpenMx))
  caps <- grep("WLS|Threshold|Factor", getNamespaceExports("OpenMx"), value = TRUE)
  write_csv(data.frame(export = sort(caps)), "G2_OpenMx_capability.csv")
  cleaned <- readcsv(file.path(root, "outputs", "ctt_B_ctt_20260918_080516", "01_cleaned_items.csv"))
  map <- readcsv(file.path(root, "examples", "simulated_datasets", "ctt_B_cfa_mapping.csv"))
  items <- map$item; facs <- unique(map$dimension)
  ord <- cleaned[items]
  ord[] <- lapply(ord, function(v) mxFactor(v, levels = sort(unique(v))))
  # Explicit per-item thresholds are required by this OpenMx raw-ordinal model.
  paths <- list(
    mxPath(from = "one", to = items, arrows = 1, free = FALSE, values = 0, labels = paste0("mean_", items)),
    mxPath(from = items, arrows = 2, free = FALSE, values = 1),
    mxPath(from = facs, arrows = 2, free = FALSE, values = 1),
    mxPath(from = facs, to = facs, arrows = 2, connect = "unique.pairs", free = TRUE, values = .2)
  )
  for (it in items) paths <- c(paths, list(mxThreshold(vars = it, nThresh = nlevels(ord[[it]]) - 1L, free = TRUE, values = 0)))
  for (f in facs) paths <- c(paths, list(mxPath(from = f, to = map$item[map$dimension == f], arrows = 1, free = TRUE, values = .7)))
  omx_model <- do.call(mxModel, c(list("ordinal_CFA_ML", type = "RAM", manifestVars = items, latentVars = facs,
                                       mxData(ord, type = "raw")), paths, list(
    mxMatrix(type = "Full", nrow = 1, ncol = length(c(items, facs)), free = FALSE, values = 0, name = "M", dimnames = list("one", c(items, facs))),
    mxExpectationRAM(M = "M"), mxFitFunctionML())))
  g2_omx <- time_fit(mxRun(omx_model, silent = TRUE))
  write_csv(data.frame(engine = "OpenMx", estimator = "ordinal raw-data ML", target_estimator = "lavaan WLSMV",
                       elapsed_seconds = g2_omx$elapsed, returned = !inherits(g2_omx$value, "error"),
                       message = if (inherits(g2_omx$value, "error")) conditionMessage(g2_omx$value) else ""), "G2_OpenMx_attempt_status.csv")
  if (!inherits(g2_omx$value, "error")) {
    write_txt(capture.output(summary(g2_omx$value)), "G2_OpenMx_summary.txt")
    saveRDS(g2_omx$value, file.path(out, "G2_OpenMx_ordinal_ML_fit.rds"))
  }
} else write_csv(data.frame(engine = "OpenMx", estimator = NA, target_estimator = "lavaan WLSMV", elapsed_seconds = NA, returned = FALSE, message = "OpenMx not installed"), "G2_OpenMx_attempt_status.csv")

write_txt(capture.output(sessionInfo()), "sessionInfo.txt")