# 规范化 data/ 下内置查表，使其满足数据契约：
#   1. `conc` 键为字符、固定 `dgt = 1` 位（原 NO2 表是带浮点尾差的 double）；
#   2. `conc` 行按数值升序（原 IER2010/2013/2015/2017 按字符串字典序存储）；
#   3. 顶层类统一为普通 list（原 MRBRT2021 是 vctrs_list_of）。
#
# 只改表示与行序，不动任何 RR 值；幂等：没有变化的文件不重写。
#
#   Rscript data-raw/normalise-lookup-keys.R
#
# 重跑后请比对指纹参照：
#   Rscript -e "Sys.setenv(ATTRMORT_FINGERPRINTS='1'); devtools::test(filter = 'fingerprints')"

dgt <- 1L
files <- list.files("data", pattern = "[.]rda$", full.names = TRUE)
changed <- character(0)

for (f in files) {
  e <- new.env()
  load(f, envir = e)
  obj <- ls(e)[1]
  tab <- get(obj, envir = e)
  notes <- character(0)

  if (inherits(tab, "vctrs_list_of")) {
    tab <- unclass(tab)
    notes <- c(notes, "plain list")
  }

  for (branch in names(tab)) {
    df   <- tab[[branch]]
    conc <- df$conc

    if (!is.character(conc)) {
      num <- as.numeric(conc)
      new <- as.character(round(num, dgt))
      if (anyNA(new)) {
        stop(obj, " / ", branch, ": rounding produced NA.")
      }
      if (max(abs(as.numeric(new) - num)) > 1e-9) {
        stop(obj, " / ", branch, ": rounding changed a value by more than 1e-9.")
      }
      df$conc <- new
      notes   <- c(notes, paste0(branch, ": character keys"))
    }

    ord <- order(as.numeric(df$conc))
    if (is.unsorted(as.numeric(df$conc))) {
      # reorder whole rows: every RR column follows its concentration
      df    <- df[ord, , drop = FALSE]
      notes <- c(notes, paste0(branch, ": numeric order"))
    }
    tab[[branch]] <- df
  }

  if (length(notes) > 0) {
    assign(obj, tab, envir = e)
    save(list = obj, file = f, envir = e, compress = "xz", version = 3)
    changed <- c(changed, basename(f))
    cat(sprintf("%-30s %s\n", basename(f), paste(unique(notes), collapse = "; ")))
  }
}

if (length(changed) == 0) {
  cat("nothing to do: every table already satisfies the contract\n")
} else {
  cat("\nrewritten:", paste(changed, collapse = ", "), "\n")
}
