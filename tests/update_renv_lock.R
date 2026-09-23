# Regenerate renv.lock for Psychostat (R dependency pinning).
# 用法：Rscript tests/update_renv_lock.R
# renv.lock 供 CI/贡献者用 `renv::restore()` 精确复现 R 依赖（见 README"环境要求"）。
# 注意：需先安装全部依赖包（首次运行任一启动器会自动安装），再执行本脚本。
script_arg <- commandArgs(FALSE)
script_arg <- sub("^--file=", "", script_arg[grep("^--file=", script_arg)][1])
root <- normalizePath(file.path(dirname(normalizePath(script_arg)), ".."))
pkgs <- c("yaml", "jsonlite", "car", "emmeans", "nortest", "onewaytests", "pwr", "ggplot2", "readxl", "haven", "MASS",
          "psych", "lavaan", "GPArotation", "mirt")
inst <- utils::installed.packages()
lock_pkgs <- lapply(pkgs, function(p) {
  list(Package = p,
       Version = if (p %in% rownames(inst)) unname(inst[p, "Version"]) else NA_character_,
       Source = "Repository", Repository = "CRAN")
})
names(lock_pkgs) <- pkgs
r_ver <- regmatches(R.version.string, regexpr("[0-9.]+", R.version.string))
lock <- list(R = list(Version = r_ver,
                      Repositories = list(list(Name = "CRAN", URL = "https://cloud.r-project.org"))),
             Packages = lock_pkgs)
jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
cat("renv.lock updated (R", r_ver, "，", length(pkgs), "个包)：\n", sep = "")
for (p in pkgs) cat(sprintf("  %-10s %s\n", p, lock_pkgs[[p]]$Version))
if (any(is.na(vapply(lock_pkgs, function(z) z$Version, character(1)))))
  warning("部分包未在本机安装，版本记录为 NA——请先运行任一启动器完成依赖安装。")
