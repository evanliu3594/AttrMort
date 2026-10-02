# ── Concentration-response tables from coefficients ─────────────────────
#
# Builds a lookup table from published coefficients. The coefficients are an
# argument, the concentration axis and confidence level are configurable, and
# the result is exactly what rr_std() consumes:
# a list(MEAN, LOW, UP) of wide data.frames carrying a `conc` column plus one
# `{cause}_{age}` column per stratum.
#
# Formulas, unchanged from the source:
#   IER : RR(x) = alpha * (1 - exp(-beta * max(x - tmrel, 0)^gamma)) + 1
#         MEAN/LOW/UP are taken across the parameter draws of each
#         cause x age stratum.
#   GEMM: RR(x) = exp(theta * log(1 + z / alpha) / (1 + exp((mu - z) / gama)))
#         with z = max(x - 2.4, 0); the interval uses theta +/- z * SE.theta.

.GEMM_Z_MEDIAN <- 2.4

# Accept a data.frame, a CSV or an Excel file as the coefficient table.
.read_coefficient_input <- function(parameters) {
  if (is.data.frame(parameters)) {
    return(as.data.frame(parameters))
  }
  if (!is.character(parameters) || length(parameters) != 1) {
    .abort("`parameters` must be a data.frame or a single file path.")
  }
  if (!file.exists(parameters)) {
    .abort("File not found: {parameters}")
  }
  ext <- tolower(file_ext(parameters))
  switch(ext,
    csv = ,
    txt = as.data.frame(read_csv(parameters, show_col_types = FALSE)),
    xls = ,
    xlsx = as.data.frame(read_excel(parameters)),
    .abort(str_c(
      "Unsupported coefficient file format: .{ext}. ",
      "Use .csv, .txt, .xls or .xlsx."
    ))
  )
}

# Rename the first column matching `pattern` to `target`, if `target` is absent.
.rename_first <- function(coefs, target, pattern) {
  if (target %in% names(coefs)) {
    return(coefs)
  }
  hit <- names(coefs)[str_detect(names(coefs), regex(pattern, ignore_case = TRUE))]
  if (length(hit) == 0) {
    return(coefs)
  }
  coefs <- rename_with(coefs, ~ target, all_of(hit[1]))
  coefs
}

# "ALRI" is the GBD spelling of LRI; everything else is kept as written so
# that built tables keep the endpoint names of their coefficients.
.normalise_cr_cause <- function(x) {
  x <- as.character(x)
  if_else(tolower(x) == "alri", "LRI", x)
}

# "All Age" -> "ALL"; "25.0" -> "25".
.normalise_cr_age <- function(x) {
  x <- as.character(x)
  x <- if_else(str_detect(x, regex("^(A|a)ll ?(A|a)ge", ignore_case = TRUE)),
               "ALL", x)
  str_replace(x, "^([0-9]+)\\.0+$", "\\1")
}

# Canonicalise and validate the coefficient table for one model.
.cr_coefficients <- function(parameters, model) {
  coefs <- .read_coefficient_input(parameters) |>
    .rename_first("cause", "^cause") |>
    .rename_first("age", "^age") |>
    .rename_first("tmrel", "^zcf|^tmrel") |>
    .rename_first("gamma", "^gamma|^delta") |>
    .rename_first("gama", "^gama") |>
    .rename_first("theta", "^theta") |>
    .rename_first("SE.theta", "^se[._]?theta")

  required <- if (model == "IER") {
    c("cause", "age", "alpha", "beta", "gamma", "tmrel")
  } else {
    c("cause", "age", "theta", "SE.theta", "alpha", "mu", "gama")
  }

  missing <- setdiff(required, names(coefs))
  if (length(missing) > 0) {
    .abort(str_c(
      "Coefficient table for model \"{model}\" ",
      "is missing column(s): {paste(missing, collapse = \", \")}. ",
      "Columns found: {paste(names(coefs), collapse = \", \")}."
    ))
  }
  if (nrow(coefs) == 0) {
    .abort("Coefficient table is empty.")
  }

  numeric_cols <- setdiff(required, c("cause", "age"))
  for (col in numeric_cols) {
    coefs[[col]] <- suppressWarnings(as.numeric(coefs[[col]]))
  }
  bad <- map_lgl(numeric_cols, function(col) anyNA(coefs[[col]]))
  if (any(bad)) {
    .abort(str_c(
      "Coefficient column(s) are not numeric: ",
      "{paste(numeric_cols[bad], collapse = \", \")}."
    ))
  }

  coefs$cause <- .normalise_cr_cause(coefs$cause)
  coefs$age   <- .normalise_cr_age(coefs$age)
  coefs
}

# IER: one curve per draw, summarised within each cause x age stratum.
.cr_long_ier <- function(coefs, axis_chr, axis_num, probs) {
  groups <- split(seq_len(nrow(coefs)),
                  paste(coefs$cause, coefs$age, sep = "\r"))
  out <- vector("list", length(groups))

  for (i in seq_along(groups)) {
    idx <- groups[[i]]
    alpha <- coefs$alpha[idx]
    beta  <- coefs$beta[idx]
    gamma <- coefs$gamma[idx]
    tmrel <- coefs$tmrel[idx]

    curves <- vapply(axis_num, function(x) {
      alpha * (1 - exp(-beta * pmax(x - tmrel, 0)^gamma)) + 1
    }, numeric(length(idx)))
    if (is.null(dim(curves))) {
      curves <- matrix(curves, ncol = length(axis_num))
    }

    # `curves` is a draws x concentrations matrix, so summarise down columns.
    out[[i]] <- tibble(
      conc  = axis_chr,
      cause = coefs$cause[idx[1]],
      age   = coefs$age[idx[1]],
      MEAN  = colMeans(curves),
      LOW   = apply(curves, 2, stats::quantile, probs = probs[1],
                    names = FALSE),
      UP    = apply(curves, 2, stats::quantile, probs = probs[2],
                    names = FALSE)
    )
  }
  list_rbind(out)
}

# GEMM: one parameter set per cause x age stratum, so the interval comes from
# the standard error of theta rather than from a distribution of draws.
.cr_long_gemm <- function(coefs, axis_chr, axis_num, probs) {
  z    <- pmax(axis_num - .GEMM_Z_MEDIAN, 0)
  zfac <- stats::qnorm(probs[2])
  n    <- nrow(coefs)
  each <- length(axis_num)

  zz     <- rep(z, times = n)
  theta  <- rep(coefs$theta, each = each)
  se     <- rep(coefs$SE.theta, each = each)
  alpha  <- rep(coefs$alpha, each = each)
  mu     <- rep(coefs$mu, each = each)
  gama   <- rep(coefs$gama, each = each)
  base   <- log(1 + zz / alpha) / (1 + exp((mu - zz) / gama))

  tibble(
    conc  = rep(axis_chr, times = n),
    cause = rep(coefs$cause, each = each),
    age   = rep(coefs$age, each = each),
    MEAN  = exp(theta * base),
    LOW   = exp((theta - zfac * se) * base),
    UP    = exp((theta + zfac * se) * base)
  )
}

# Map a model name onto the functional form that generates its table. IER
# variants (IER2010, IER2017, ...) all use the IER form, as in the source.
.cr_model_form <- function(model) {
  if (!is.character(model) || length(model) != 1) {
    .abort("`model` must be a single character string.")
  }
  key <- toupper(trimws(model))
  if (str_detect(key, "^IER")) {
    return("IER")
  }
  if (str_detect(key, "^GEMM")) {
    return("GEMM")
  }
  .abort(str_c(
    "`model` must be \"IER\" (or an IER variant such as \"IER2017\") or ",
    "\"GEMM\". Got: \"{model}\"."
  ))
}

#' Build a concentration-response lookup table from coefficients
#'
#' Turns published concentration-response coefficients into the wide
#' `list(MEAN, LOW, UP)` structure that [rr_std()] consumes and that the
#' built-in tables in `data/` use. This is the entry point for a pollutant or
#' endpoint set that the package does not ship: supply the coefficients and
#' get a table that can be handed to `mortality(crf = )` — either directly as
#' the list, or as a three-sheet workbook after `path` is written.
#'
#' @param parameters A data.frame or a `.csv`/`.txt`/`.xls`/`.xlsx` path of
#'   coefficients. For `model = "IER"` the required columns are `cause`,
#'   `age`, `alpha`, `beta`, `gamma` and `tmrel` (several rows may share a
#'   cause and age group: the interval is taken across those draws). For
#'   `model = "GEMM"` they are `cause`, `age`, `theta`, `SE.theta`, `alpha`,
#'   `mu` and `gama`. Coefficient files with other spellings (``Causes``, ``Age``,
#'   `zcf`, `delta`) are accepted, and `ALRI`/`All Age` are normalised to
#'   `LRI`/`ALL`.
#' @param model Character. Which functional form to use: `"IER"` (default) or
#'   `"GEMM"`. A single string: the model is chosen per call, not guessed.
#' @param conc Numeric vector of concentrations to evaluate.
#'   Default `seq(0, 300, 0.1)`, the axis used for the shipped tables.
#' @param dgt Integer. Decimal places used to render the concentration keys,
#'   matching `dgt_conc` in [mortality()]. Default 1.
#' @param level Numeric. Confidence level for the `LOW`/`UP` sheets.
#'   Default 0.95.
#' @param path Character or `NULL`. When given, the three sheets are also
#'   written to this `.xlsx` path (requires the `writexl` package).
#'
#' @return A named list of three wide data.frames (`MEAN`, `LOW`, `UP`), each
#'   with a character `conc` column and one `\{cause\}_\{age\}` column per
#'   stratum.
#'
#' @seealso [rr_std()], [cr_models()], [mortality()]
#'
#' @export
#'
#' @examples
#' ier <- data.frame(cause = "IHD", age = "25", alpha = 5, beta = 0.01,
#'                   gamma = 0.5, tmrel = 3)
#' tab <- build_cr_table(ier, model = "IER", conc = seq(0, 20, 0.1))
#' names(tab)
#' head(tab$MEAN)
build_cr_table <- function(parameters,
                           model         = "IER",
                           conc          = NULL,
                           dgt           = 1,
                           level         = 0.95,
                           path          = NULL) {
  model <- .cr_model_form(model)

  if (!is.numeric(level) || length(level) != 1 || level <= 0 || level >= 1) {
    .abort("`level` must be a single number strictly between 0 and 1.")
  }
  if (is.null(conc)) {
    conc <- seq(0, 300, 0.1)
  }
  if (!is.numeric(conc) || length(conc) == 0) {
    .abort("`conc` must be a non-empty numeric vector.")
  }

  coefs   <- .cr_coefficients(parameters, model)
  axis_num <- as.numeric(conc)
  axis_chr <- matchable(axis_num, dgt = dgt)
  probs   <- c((1 - level) / 2, 1 - (1 - level) / 2)

  long <- if (model == "IER") {
    .cr_long_ier(coefs, axis_chr, axis_num, probs)
  } else {
    .cr_long_gemm(coefs, axis_chr, axis_num, probs)
  }

  tabs <- map(c("MEAN", "LOW", "UP"), function(index) {
    long |>
      select(conc, cause, age, RR = all_of(index)) |>
      pivot_wider(names_from = c(cause, age), names_sep = "_",
                  values_from = RR)
  })
  names(tabs) <- c("MEAN", "LOW", "UP")

  if (!is.null(path)) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      .abort(str_c(
        "Writing the lookup table requires the `writexl` package, which ",
        "is not installed. Install it with install.packages(\"writexl\"), ",
        "or use the returned list directly."
      ))
    }
    writexl::write_xlsx(tabs, path = path)
  }

  tabs
}
