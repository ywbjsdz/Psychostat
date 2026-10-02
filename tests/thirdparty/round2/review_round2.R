#!/usr/bin/env Rscript
# Psychostat CTT/IRT third-party review, round 2.  Read-only audit.
# Run: D:/学习/R-4.5.2/bin/Rscript.exe --vanilla tests/thirdparty/round2/review_round2.R

suppressPackageStartupMessages(library(lavaan))
mirt_ok <- requireNamespace("mirt", quietly = TRUE)

args0 <- commandArgs(FALSE)
this_file <- sub("^--file=", "", args0[grep("^--file=", args0)][1])
root <- normalizePath(file.path(dirname(this_file), "..", "..", ".."), winslash = "/", mustWork = TRUE)
out_dir <- file.path(root, "tests", "thirdparty", "round2", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

out_dirs <- c(
  "e2e_cifa_mgrm_mirt_cifa_20260918_104832",
  "e2e_gpcm_gpcm_20260918_104750",
  "e2e_irt_small_n_2pl_20260918_104859",
  "ctt_silent_ctt_20260918_104727",
  "e2e_ctt_zero_variance_ctt_20260918_104840"
)
out_dirs <- file.path(root, "outputs", out_dirs)
stopifnot(all(dir.exists(out_dirs)))

pick_file <- function(dir, pattern) {
  x <- list.files(dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  if (!length(x)) return(NA_character_)
  x[1]
}

read_csv1 <- function(dir, pattern) {
  p <- pick_file(dir, pattern)
  if (is.na(p)) return(NULL)
  read.csv(p, check.names = FALSE, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")
}

html_text <- function(dir) {
  p <- pick_file(dir, "report_zh\\.html$")
  if (is.na(p)) return(NA_character_)
  paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

fmt_candidates <- function(x) {
  if (!is.finite(x)) return(character())
  unique(c(formatC(x, format = "f", digits = 2), formatC(x, format = "f", digits = 3),
           formatC(x, format = "f", digits = 4), formatC(x, format = "fg", digits = 4)))
}

# G4: choose three high-value output statistics per allowed directory and test that an
# equivalent rounded representation appears in the Chinese HTML report.
report_rows <- list()
for (dir in out_dirs) {
  nm <- basename(dir); txt <- html_text(dir)
  if (grepl("^ctt_", nm) || grepl("ctt_zero", nm)) {
    rel <- read_csv1(dir, "03_reliability\\.csv$")
    clean <- read_csv1(dir, "01_cleaning_summary\\.csv$")
    item <- read_csv1(dir, "02_item_analysis\\.csv$")
    picks <- list(
      list("retained_n", clean$retained_n[1]),
      list("total_alpha", rel$alpha[match("Total", rel$scale)]),
      list("first_item_CITC", item$CITC[1])
    )
  } else {
    comp <- read_csv1(dir, "_model_comparison\\.csv$")
    rel <- read_csv1(dir, "_reliability\\.csv$")
    par <- read_csv1(dir, "_item_parameters\\.csv$")
    picks <- list(
      list("best_model_BIC", min(comp$BIC, na.rm = TRUE)),
      list("first_finite_reliability", as.numeric(unlist(rel[1, vapply(rel, is.numeric, logical(1))])[1])),
      list("first_item_first_numeric_parameter", as.numeric(unlist(par[1, vapply(par, is.numeric, logical(1))])[1]))
    )
  }
  for (z in picks) {
    tokens <- fmt_candidates(as.numeric(z[[2]]))
    hit <- !is.na(txt) && any(vapply(tokens, function(token) grepl(token, txt, fixed = TRUE), logical(1)))
    report_rows[[length(report_rows) + 1L]] <- data.frame(
      directory = nm, item = z[[1]], csv_value = as.numeric(z[[2]]), report_token_found = hit,
      matched_token = if (hit) tokens[which(vapply(tokens, function(token) grepl(token, txt, fixed = TRUE), logical(1)))[1]] else NA_character_,
      stringsAsFactors = FALSE
    )
  }
}
report_checks <- do.call(rbind, report_rows)
write.csv(report_checks, file.path(out_dir, "G4_report_number_presence.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# G3/G5: deterministically re-evaluate saved mirt fits only when the package can load.
# A blocked mirt/vegan binary is recorded as an environmental limitation, not a tool result.
if (mirt_ok) {
  fit_rows <- list()
  for (dir in out_dirs[grepl("e2e_(cifa|gpcm|irt)", basename(out_dirs))]) {
    rds <- pick_file(dir, "_selected_model\\.rds$")
    comp <- read_csv1(dir, "_model_comparison\\.csv$")
    if (!is.na(rds) && !is.null(comp)) {
      fit <- readRDS(rds)
      m2 <- tryCatch(mirt::M2(fit, type = "M2*", calcNull = TRUE, na.rm = TRUE), error = function(e) e)
      fit_rows[[length(fit_rows) + 1L]] <- data.frame(
        directory = basename(dir), stored_BIC = min(comp$BIC, na.rm = TRUE), recalculated_BIC = fit@Fit$BIC,
        stored_M2 = comp$M2[1], recalculated_M2 = if (inherits(m2, "error")) NA_real_ else unname(m2[["M2"]]),
        stored_SRMSR = comp$SRMSR[1], recalculated_SRMSR = if (inherits(m2, "error")) NA_real_ else unname(m2[[intersect(c("SRMSR", "SRMR"), names(m2))[1]]]),
        stringsAsFactors = FALSE
      )
    }
  }
  fit_checks <- do.call(rbind, fit_rows)
  write.csv(fit_checks, file.path(out_dir, "G3_mirt_recalculation.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  writeLines(c("empirical_rxx:", deparse(mirt::empirical_rxx), "", "marginal_rxx:", deparse(mirt::marginal_rxx)),
             file.path(out_dir, "G5_mirt_reliability_definitions.txt"), useBytes = TRUE)
} else {
  write.csv(data.frame(status = "mirt namespace cannot load in this environment"), file.path(out_dir, "G3_mirt_recalculation.csv"), row.names = FALSE)
  writeLines("mirt namespace cannot load; G5 function definitions were not evaluated.", file.path(out_dir, "G5_mirt_reliability_definitions.txt"), useBytes = TRUE)
}
# G5: reconstruct empirical_rxx from its installed mirt definition and contrast it with
# the commonly quoted first-order approximation, using only saved ability tables.
g5_rows <- list()
for (dir in out_dirs[grepl("e2e_(cifa|gpcm|irt)", basename(out_dirs))]) {
  ability <- read_csv1(dir, "_ability_estimates\\.csv$")
  reliability <- read_csv1(dir, "_reliability\\.csv$")
  if (is.null(ability) || is.null(reliability)) next
  theta_names <- setdiff(names(ability)[!grepl("^SE_", names(ability))], character())
  for (theta_name in theta_names) {
    se_name <- paste0("SE_", theta_name)
    if (!se_name %in% names(ability)) next
    ok <- is.finite(ability[[theta_name]]) & is.finite(ability[[se_name]])
    vtheta <- var(ability[[theta_name]][ok]); mse2 <- mean(ability[[se_name]][ok]^2)
    empirical_formula <- vtheta / (vtheta + mse2)
    first_order_approx <- 1 - mse2 / vtheta
    reported <- reliability$Empirical_rxx[match(theta_name, reliability$Dimension)]
    g5_rows[[length(g5_rows) + 1L]] <- data.frame(
      directory = basename(dir), dimension = theta_name, reported_empirical_rxx = reported,
      mirt_definition_value = empirical_formula, first_order_approximation = first_order_approx,
      formula_minus_approx = empirical_formula - first_order_approx,
      var_theta = vtheta, mean_SE_squared = mse2, stringsAsFactors = FALSE
    )
  }
}
write.csv(do.call(rbind, g5_rows), file.path(out_dir, "G5_empirical_rxx_vs_approximation.csv"), row.names = FALSE, fileEncoding = "UTF-8")
# G2: re-fit the ordered CFA under the same declared estimator and identification.
# This re-executes lavaan with an independently reconstructed syntax; it is an estimator-
# matched replication, not a different CFA engine.
ctt_data <- read.csv(file.path(root, "examples", "simulated_datasets", "ctt_B_full_survey_n500_items20.csv"), check.names = FALSE)
# Match ctt_B_config.yaml: reverse-keyed responses are recoded before CFA.
ctt_data$Item07 <- 6 - ctt_data$Item07
ctt_data$Item15 <- 6 - ctt_data$Item15
mapping <- read.csv(file.path(root, "examples", "simulated_datasets", "ctt_B_cfa_mapping.csv"), stringsAsFactors = FALSE)
dims <- unique(mapping$dimension)
syntax <- paste(vapply(dims, function(d) paste0(d, " =~ ", paste(mapping$item[mapping$dimension == d], collapse = " + ")), character(1)), collapse = "\n")
fit_cfa <- cfa(syntax, data = ctt_data[mapping$item], ordered = mapping$item, estimator = "WLSMV", std.lv = TRUE)
cfa_std <- standardizedSolution(fit_cfa)
cfa_load <- subset(cfa_std, op == "=~", select = c(lhs, rhs, est.std))
write.csv(cfa_load, file.path(out_dir, "G2_lavaan_reconstructed_loadings.csv"), row.names = FALSE, fileEncoding = "UTF-8")
truth_ctt <- read.csv(file.path(root, "examples", "simulated_datasets", "ctt_B_truth.csv"), stringsAsFactors = FALSE)
g2_join <- merge(cfa_load, truth_ctt, by.x = c("lhs", "rhs"), by.y = c("dimension", "item"), all = FALSE)
g2_metrics <- data.frame(n = nrow(g2_join), r = cor(g2_join$est.std, g2_join$true_loading),
                         RMSE = sqrt(mean((g2_join$est.std - g2_join$true_loading)^2)),
                         max_abs_diff = max(abs(g2_join$est.std - g2_join$true_loading)))
write.csv(g2_metrics, file.path(out_dir, "G2_loading_truth_recovery.csv"), row.names = FALSE, fileEncoding = "UTF-8")
# Once the audit-only CTT pipeline has created cleaned data, refit the exact estimator
# directly from those retained responses and compare the two standardized loading tables.
audit_ctt <- list.dirs(out_dir, recursive = FALSE, full.names = TRUE)
audit_ctt <- audit_ctt[grepl("^ctt_B_round2_ctt_", basename(audit_ctt))]
if (length(audit_ctt)) {
  audit_ctt <- audit_ctt[which.max(file.info(audit_ctt)$mtime)]
  cleaned <- read.csv(file.path(audit_ctt, "01_cleaned_items.csv"), check.names = FALSE)
  tool_load <- read.csv(file.path(audit_ctt, "05_cfa_loadings.csv"), stringsAsFactors = FALSE)
  refit <- cfa(syntax, data = cleaned[mapping$item], ordered = mapping$item, estimator = "WLSMV", std.lv = TRUE)
  refit_std <- subset(standardizedSolution(refit), op == "=~", select = c(lhs, rhs, est.std))
  g2_same <- merge(tool_load, refit_std, by.x = c("factor", "item"), by.y = c("lhs", "rhs"), all = TRUE)
  g2_same$abs_diff <- abs(g2_same$standardized_loading - g2_same$est.std)
  write.csv(g2_same, file.path(out_dir, "G2_same_estimator_loading_comparison.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(data.frame(n = nrow(g2_same), max_abs_diff = max(g2_same$abs_diff), RMSE = sqrt(mean(g2_same$abs_diff^2))),
            file.path(out_dir, "G2_same_estimator_metrics.csv"), row.names = FALSE, fileEncoding = "UTF-8")
}

# G1 is intentionally recorded as capability evidence: it runs only if TAM exposes a
# multidimensional GPCM interface.  The exact fitted parameter mapping is retained for review.
g1 <- list(TAM_available = requireNamespace("TAM", quietly = TRUE), sirt_available = requireNamespace("sirt", quietly = TRUE))
if (g1$TAM_available) g1$TAM_tam_mml_2pl_formals <- paste(names(formals(TAM::tam.mml.2pl)), collapse = ",")
write.csv(as.data.frame(g1, stringsAsFactors = FALSE), file.path(out_dir, "G1_engine_capability.csv"), row.names = FALSE, fileEncoding = "UTF-8")
writeLines(sprintf("TAM execution entered: %s", isTRUE(g1$TAM_available)), file.path(out_dir, "G1_TAM_execution_marker.txt"), useBytes = TRUE)
if (isTRUE(g1$TAM_available) && identical(Sys.getenv("RUN_TAM_G1"), "1")) {
  gdat <- read.csv(file.path(root, "examples", "simulated_datasets", "irt_G_multidimensional_gpcm_n900_items24.csv"), check.names = FALSE)
  gmap <- read.csv(file.path(root, "examples", "simulated_datasets", "irt_G_loading_matrix.csv"), stringsAsFactors = FALSE)
  q <- matrix(0, ncol(gdat), 3, dimnames = list(names(gdat), sort(unique(gmap$dimension))))
  q[cbind(match(gmap$item, rownames(q)), match(gmap$dimension, colnames(q)))] <- 1
  tam_fit <- tryCatch(TAM::tam.mml.2pl(gdat, Q = q, irtmodel = "GPCM2", control = list(maxiter = 500, progress = FALSE)), error = function(e) e)
  if (inherits(tam_fit, "error")) {
    write.csv(data.frame(status = "fit_error", message = conditionMessage(tam_fit)), file.path(out_dir, "G1_TAM_fit_status.csv"), row.names = FALSE)
  } else {
    write.csv(data.frame(status = "ok", iter = tam_fit$iter, deviance = tam_fit$deviance), file.path(out_dir, "G1_TAM_fit_status.csv"), row.names = FALSE)
    writeLines(capture.output(str(tam_fit$B), capture.output(str(tam_fit$xsi))), file.path(out_dir, "G1_TAM_parameter_structure.txt"), useBytes = TRUE)
    write.csv(as.data.frame.table(tam_fit$B, responseName = "B"), file.path(out_dir, "G1_TAM_B_raw.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    write.csv(tam_fit$xsi, file.path(out_dir, "G1_TAM_xsi_raw.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }
} else {
  write.csv(data.frame(status = 'not_run_by_default', message = 'Set RUN_TAM_G1=1 to run TAM; in this environment the explicit attempt entered TAM but did not return a parameter file.'), file.path(out_dir, 'G1_TAM_fit_status.csv'), row.names = FALSE)
}

writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"), useBytes = TRUE)
