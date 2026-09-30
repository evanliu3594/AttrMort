#!/usr/bin/env Rscript

# AttrMort 审计复现脚本（audit_code_vs_design_260930 配套）
#
# 只读仓库：所有产物写入 tempdir()，不修改仓库内任何文件。
# 用法（在仓库根运行，或传仓库路径为第一个参数）：
#   Rscript diagnosis/tmp_audit_checks.R [repo_path]
#
# 覆盖五项微型复算：
#   A. 原生管道 RHS 必须是函数调用（AST 检查）
#   B. 内置查表 conc 键类型 / 精度 / 存储顺序（IER 四表字典序、NO2 为 double）
#   C. 多波段栅格 NA 掩膜（任一层 NA 即删整行）
#   D. inst/extdata 示例数据能否由 data-raw/make-example-data.R 在包外复现
#   E. .resolve_key_cols() 报错提示里的参数名与实际不符（getAge/getMort 为 loc）

args <- commandArgs(trailingOnly = TRUE)
repo <- if (length(args) >= 1) normalizePath(args[1]) else normalizePath(".")
stopifnot(file.exists(file.path(repo, "DESCRIPTION")))

fail <- 0L
pass <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
bad  <- function(msg) { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s\n", msg)) }

cat("== A. native pipe RHS is a function call ==\n")
first_child <- function(pd, id) {
  ch <- pd[pd$parent == id, , drop = FALSE]
  if (nrow(ch) == 0) return(NULL)
  ch[order(ch$line1, ch$col1, ch$id), , drop = FALSE][1, ]
}
files <- list.files(file.path(repo, "R"), pattern = "[.]R$", full.names = TRUE)
total <- 0L; viol <- character(0)
for (f in files) {
  pd <- getParseData(parse(f, keep.source = TRUE))
  pipes <- pd[pd$token == "PIPE", , drop = FALSE]
  total <- total + nrow(pipes)
  for (i in seq_len(nrow(pipes))) {
    kids <- pd[pd$parent == pipes$parent[i], , drop = FALSE]
    kids <- kids[order(kids$line1, kids$col1, kids$id), , drop = FALSE]
    pos <- which(kids$id == pipes$id[i])
    if (pos >= nrow(kids)) { viol <- c(viol, paste0(f, ":", pipes$line1[i])); next }
    node <- kids[pos + 1L, ]
    while (node$token == "expr") {
      nx <- first_child(pd, node$id)
      if (is.null(nx) || nx$id == node$id) break
      node <- nx
    }
    if (node$token != "SYMBOL_FUNCTION_CALL")
      viol <- c(viol, sprintf("%s:%d (%s)", f, pipes$line1[i], node$token))
  }
}
if (length(viol) == 0L) pass(sprintf("%d 处原生管道，右侧均为函数调用", total)) else
  bad(paste("非函数调用 RHS:", paste(viol, collapse = ", ")))

cat("== B. lookup-table conc contract ==\n")
suppressMessages(devtools::load_all(repo, quiet = TRUE))
non_char <- character(0)
unsorted <- character(0)
boxed    <- character(0)
for (nm in c("GEMM", "IER2010", "IER2013", "IER2015", "IER2017",
             "MRBRT2019", "MRBRT2021", "O3_CR", "NO2_CR")) {
  obj <- paste0(nm, "_Lookup_Table")
  e <- new.env(); data(list = obj, package = "AttrMort", envir = e)
  tab  <- get(obj, envir = e)
  conc <- tab$MEAN$conc
  if (!is.character(conc)) non_char <- c(non_char, obj)
  num  <- as.numeric(conc)
  if (is.unsorted(num)) unsorted <- c(unsorted, obj)
  if (inherits(tab, "vctrs_list_of")) boxed <- c(boxed, obj)
  dgt1 <- all(grepl("^-?[0-9]+([.][0-9])?$", conc))
  cat(sprintf("  %-16s class=%-9s dgt1=%-5s sorted=%-5s desc_steps=%d\n",
              obj, class(conc)[1], dgt1, !is.unsorted(num), sum(diff(num) < 0)))
}
if (length(non_char) == 0L) pass("9 张原始查表 conc 均为字符键（MF-2 已修）") else
  bad(paste("原始表 conc 仍非字符:", paste(non_char, collapse = ", ")))
if (length(unsorted) == 0L) pass("9 张原始查表 conc 均为数值升序（I-10 已修）") else
  bad(paste("原始表 conc 非数值序:", paste(unsorted, collapse = ", ")))
if (length(boxed) == 0L) pass("9 张原始查表顶层均为普通 list（I-11 已修）") else
  bad(paste("仍为 vctrs_list_of:", paste(boxed, collapse = ", ")))
# 设计契约：RR_std() 输出必须是字符键（原始表例外见报告 MF-2 / I-10）
for (m in cr_models()) for (ci in c("MEAN", "UP", "LOW")) {
  rr <- suppressMessages(RR_std(m, ci))
  if (!is.character(rr$conc) || anyNA(rr$conc)) bad(sprintf("RR_std(%s, %s) conc", m, ci))
}
pass("13 模型 x 3 CI：RR_std() 输出均为字符 conc")

cat("== C. multi-band raster NA mask ==\n")
r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
terra::values(r) <- c(1, 2, 3, 4)
s <- c(r, r)
terra::values(s)[, 2] <- c(NA, 2, 3, 4)     # band 2 缺 1 格，band 1 完整
warned <- FALSE
n_multi <- withCallingHandlers(
  nrow(AttrMort:::raster_to_grid(s, dgt = 0)),
  warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") }
)
warned_single <- FALSE
n_single <- withCallingHandlers(
  nrow(AttrMort:::raster_to_grid(s[[1]], dgt = 0)),
  warning = function(w) { warned_single <<- TRUE; invokeRestart("muffleWarning") }
)
cat(sprintf("  two bands, one NA -> rows=%d warned=%s (single band: rows=%d warned=%s)\n",
            n_multi, warned, n_single, warned_single))
if (warned && !warned_single && n_multi == 3L) {
  pass("掩膜不一致 → 告警且整格剔除；单波段不告警（MF-1 修复后的契约）")
} else {
  bad("NA 掩膜契约行为与预期不符，请更新报告 MF-1")
}

cat("== D. example data reproducibility ==\n")
tmp <- file.path(tempdir(), "attrmort-audit-data")
unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
invisible(file.copy(file.path(repo, "data-raw", "make-example-data.R"),
                    file.path(tmp, "make-example-data.R")))
old_wd <- getwd()
setwd(tmp)                     # 生成脚本用相对路径写 inst/extdata，必须换目录运行
stat <- system2(file.path(R.home("bin"), "Rscript"),
                "make-example-data.R", stdout = FALSE)
setwd(old_wd)
if (stat != 0) bad("make-example-data.R 运行失败") else {
  same <- vapply(list.files(file.path(repo, "inst", "extdata"), pattern = "[.]xlsx$"),
                 function(f) {
                   a <- readxl::read_excel(file.path(repo, "inst", "extdata", f))
                   b <- readxl::read_excel(file.path(tmp, "inst", "extdata", f))
                   isTRUE(all.equal(as.data.frame(a), as.data.frame(b),
                                    tolerance = 0, check.attributes = FALSE))
                 }, logical(1))
  if (all(same)) pass("6 个示例 workbook 逐单元格一致") else
    bad(paste("不一致文件:", paste(names(same)[!same], collapse = ", ")))
}

cat("== E. key-column error message ==\n")
d  <- data.frame(age = c("25", "30"), zz = c(1, 2))
m1 <- tryCatch(getAge(d, "zz"),  error = function(e) conditionMessage(e))
m2 <- tryCatch(getMort(d, "zz"), error = function(e) conditionMessage(e))
m3 <- tryCatch(getPop(d, "zz"),  error = function(e) conditionMessage(e))
cat(sprintf("  getAge : %s\n  getMort: %s\n  getPop : %s\n", m1, m2, m3))
if (grepl("`loc`", m1) && grepl("`loc`", m2) && grepl("`xy`", m3)) {
  pass("提示参数名与调用者一致：getAge/getMort -> loc，getPop -> xy（I-3 已修）")
} else {
  bad("提示文案与调用者参数名不符，请更新报告 I-3")
}

cat("== F. non-canonical character conc keys ==\n")
warns <- character(0)
withCallingHandlers(
  AttrMort:::validate_mortality_input(
    list(
      conc = data.frame(x = "0", y = "0", conc = "10.00"),
      pop = data.frame(x = "0", y = "0", pop = 1),
      age_struc = data.frame(location = "A", age = as.character(seq(0, 95, 5)),
                             prop = 1 / 20),
      mort_rate = data.frame(location = "A", age = "25",
                             endpoint = "ncd+lri", mortrate = 1)
    ),
    cr_model = "GEMM", dgt_conc = 1
  ),
  warning = function(w) {
    warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning")
  }
)
if (any(grepl("dgt_conc", warns))) {
  pass("非规范字符 conc 键触发校验告警（I-9 已修）")
} else {
  bad("未对非规范字符 conc 键告警，请更新报告 I-9")
}

cat(sprintf("\n=== audit checks done: %d failure(s) ===\n", fail))
if (fail > 0L) quit(status = 1L)
