# ── Concentration-response lookup tables ────────────────────────────────
#
# The model metadata lives in the JSON config (R/cr-config.R). This file turns
# one configured model into a join-ready long table:
#   conc[chr] / endpoint[chr] / age[chr] / RR[num]
#
# Lookups are `list(MEAN, LOW, UP)` of wide data.frames carrying a
# concentration column (`conc` for the shipped rda tables, `conc_col` for
# user-supplied files) plus one `{endpoint}_{age}` column per stratum. An age
# without its own column inherits the nearest previous age, starting from the
# endpoint's `_ALL` row when it exists: that keeps the `_ALL`-only tables
# (MRBRT2021) working and reproduces GEMM's 85/90/95 <- 80 semantics, both
# pinned by the fingerprints.

# Canonicalise a user-supplied CI / index label.
.match_ci <- function(index) {
  if (!is.character(index) || length(index) != 1) {
    stop("`CI` must be a single character string.", call. = FALSE)
  }
  key <- toupper(trimws(index))
  key <- switch(key, UPPER = "UP", LOWER = "LOW", key)
  if (!key %in% c("MEAN", "UP", "LOW")) {
    stop(
      "`CI` must be one of \"MEAN\", \"UP\" or \"LOW\" ",
      "(aliases \"UPPER\"/\"LOWER\" are accepted). Got: \"", index, "\".",
      call. = FALSE
    )
  }
  key
}

# Canonicalise a user-supplied CR model name against a config.
.match_cr_model <- function(CR_Model, config) {
  if (!is.character(CR_Model) || length(CR_Model) != 1) {
    stop("`CRF` must be a single character string or a data.frame.",
         call. = FALSE)
  }
  .cr_model_entry(config, CR_Model)$name
}

# Resolve a lookup path relative to the config file (never the cwd).
# Accepts POSIX-absolute, drive-letter-absolute and UNC paths.
.cr_lookup_path <- function(path, config) {
  if (grepl("^(/|[A-Za-z]:[\\\\/]|\\\\\\\\|//)", path)) {
    return(path)
  }
  file.path(dirname(config$path), path)
}

# Validate a loaded lookup and hand back list(MEAN, LOW, UP) with the
# concentration column renamed to the canonical `conc`.
.cr_lookup_check <- function(tab, entry, source) {
  if (!is.list(tab) || !all(c("MEAN", "LOW", "UP") %in% names(tab))) {
    stop(
      "Lookup ", source, " must be a list with elements MEAN, LOW and UP.",
      call. = FALSE
    )
  }

  value_cols <- NULL
  for (branch in c("MEAN", "LOW", "UP")) {
    df <- tab[[branch]]
    if (!is.data.frame(df)) {
      stop("Lookup ", source, " branch ", branch, " is not a data.frame.",
           call. = FALSE)
    }
    if (!entry$conc_col %in% names(df)) {
      stop(
        "Lookup ", source, " branch ", branch, " has no concentration ",
        "column \"", entry$conc_col, "\" (columns: ",
        paste(names(df), collapse = ", "), ").",
        call. = FALSE
      )
    }
    names(df)[names(df) == entry$conc_col] <- "conc"
    if (anyNA(suppressWarnings(as.numeric(df$conc)))) {
      stop("Lookup ", source, " branch ", branch,
           " has a non-numeric concentration column.", call. = FALSE)
    }
    cols <- setdiff(names(df), "conc")
    if (length(cols) == 0) {
      stop("Lookup ", source, " branch ", branch,
           " has no endpoint-age columns.", call. = FALSE)
    }
    if (is.null(value_cols)) {
      value_cols <- cols
    } else if (!identical(sort(value_cols), sort(cols))) {
      stop("Lookup ", source, " branches do not share the same columns; ",
           "MEAN has ", length(value_cols), " and ", branch, " has ",
           length(cols), ".", call. = FALSE)
    }
    tab[[branch]] <- df
  }

  # Every configured endpoint must be anchored: its first configured age needs
  # its own `{prefix}_{age}` column or the endpoint needs a `{prefix}_ALL`
  # column to inherit from. Later ages may intentionally inherit the previous
  # age's value (GEMM 85/90/95 <- 80), but an endpoint with no anchor at all
  # would silently produce NA relative risks.
  cols_low <- tolower(value_cols)
  for (ep in entry$endpoints) {
    prefix  <- tolower(ep$lookup)
    has_all <- paste0(prefix, "_all") %in% cols_low
    first   <- paste0(prefix, "_", ep$ages[1]) %in% cols_low
    if (!has_all && !first) {
      stop(
        "Lookup ", source, " has no columns for endpoint \"", prefix,
        "\" of model \"", entry$name, "\" (needs \"", prefix, "_",
        ep$ages[1], "\" or \"", prefix, "_ALL\"). Available columns: ",
        paste(value_cols, collapse = ", "), ".",
        call. = FALSE
      )
    }
  }

  tab
}

# Load one configured lookup as list(MEAN, LOW, UP) of wide data.frames.
.cr_lookup_load <- function(entry, config) {
  lk <- entry$lookup
  if (identical(lk$kind, "rda")) {
    tab <- tryCatch(
      get(lk$table, envir = asNamespace("AttrMort")),
      error = function(e) NULL
    )
    if (is.null(tab)) {
      stop("Lookup table not found in AttrMort: ", lk$table, ".", call. = FALSE)
    }
    return(.cr_lookup_check(tab, entry, lk$table))
  }

  path <- .cr_lookup_path(lk$path, config)

  if (identical(lk$kind, "xlsx")) {
    if (!file.exists(path)) {
      stop("Lookup file not found: ", path, call. = FALSE)
    }
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop("Reading xlsx lookup tables needs the `readxl` package. ",
           "Install it, or use an `rda`/`csv` lookup.", call. = FALSE)
    }
    read_branch <- function(branch) {
      sheet <- if (!is.null(lk$sheets[[branch]])) lk$sheets[[branch]] else branch
      tryCatch(
        as.data.frame(readxl::read_excel(path, sheet = sheet)),
        error = function(e) {
          stop("Cannot read sheet \"", sheet, "\" (branch ", branch,
               ") from ", path, ": ", conditionMessage(e), call. = FALSE)
        }
      )
    }
  } else {
    if (!dir.exists(path)) {
      stop("CSV lookup path must be a directory of MEAN.csv/LOW.csv/UP.csv: ",
           path, " not found.", call. = FALSE)
    }
    read_branch <- function(branch) {
      file <- if (!is.null(lk$sheets[[branch]])) {
        lk$sheets[[branch]]
      } else {
        paste0(branch, ".csv")
      }
      file <- file.path(path, file)
      if (!file.exists(file)) {
        stop("Lookup csv not found: ", file, call. = FALSE)
      }
      as.data.frame(readr::read_csv(file, show_col_types = FALSE))
    }
  }

  tab <- stats::setNames(
    lapply(c("MEAN", "LOW", "UP"), read_branch),
    c("MEAN", "LOW", "UP")
  )
  .cr_lookup_check(tab, entry, path)
}

#' Standardize a concentration-response lookup table
#'
#' Turns the wide lookup table of one configured model into a join-ready long
#' table with one row per concentration, endpoint and age group. The endpoints,
#' their applicable ages and the lookup location come from [cr_config()].
#' An age without its own column inherits the nearest previous age (the
#' `_ALL` row when that is the only one), which is how the shipped GEMM and
#' MRBRT tables are defined. The concentration axis is rendered as character
#' keys (`matchable()` precision `dgt`) so that it can be joined against
#' exposure data regardless of how that data is stored.
#'
#' @param CR_Model Character. CR model name; see [cr_models()] for the
#'   accepted values. Matched case-insensitively, aliases included.
#' @param index Character. Which table to use: `"MEAN"` (default), `"UP"` or
#'   `"LOW"`. `"UPPER"` and `"LOWER"` are accepted as aliases.
#' @param dgt Integer. Decimal places used to render the concentration keys.
#'   Must match the precision used for the exposure side (`dgt_conc` in
#'   [Mortality()]). Default 1.
#' @param config Optional configuration from [cr_config()], or a path to a
#'   JSON config. `NULL` (default) uses the shipped config.
#'
#' @return A data.frame with columns `conc` (character), `endpoint`,
#'   `age` (character) and `RR`.
#' @export
#'
#' @examples
#' head(RR_std("GEMM", "MEAN"))
#' unique(RR_std("O3", "MEAN")$endpoint)
RR_std <- function(CR_Model, index = "MEAN", dgt = 1, config = NULL) {
  index  <- .match_ci(index)
  config <- .as_cr_config(config)
  entry  <- .cr_model_entry(config, CR_Model)
  RR     <- .cr_lookup_load(entry, config)
  wide   <- RR[[index]]

  long <- wide |>
    pivot_longer(
      cols      = -conc,
      values_to = "RR",
      names_to  = c("endpoint", "agegroup"),
      names_sep = "_"
    ) |>
    mutate(endpoint = tolower(endpoint))

  # One expansion per configured endpoint; the exposed `endpoint` name may
  # differ from the lookup column prefix (`lookup`), e.g. allcause <- CAUSE.
  # Ages without their own column inherit the nearest previous age (the `_ALL`
  # column when that is the only one): this is the shipped tables' semantics
  # (e.g. GEMM 85/90/95 use age 80's RR), pinned by the fingerprints.
  grid <- lapply(entry$endpoints, function(ep) {
    expand_grid(
      conc     = wide$conc,
      endpoint = ep$name,
      src      = tolower(ep$lookup),
      age      = c("ALL", ep$ages)
    )
  }) |>
    bind_rows()

  out <- grid |>
    left_join(long, by = c("conc", "src" = "endpoint", "age" = "agegroup")) |>
    group_by(conc, src, endpoint) |>
    fill(RR) |>
    ungroup() |>
    filter(age != "ALL") |>
    transmute(
      conc,
      endpoint = tolower(endpoint),
      age,
      RR
    )

  # Configured ages that neither have a column nor an `_ALL` fallback are
  # caught at load time; this is the last line of defence against a lookup
  # that slips through (e.g. a missing `_ALL` column).
  if (anyNA(out$RR)) {
    hole <- out[which(is.na(out$RR))[1], ]
    stop(
      "Model \"", entry$name, "\": the lookup has no RR value for endpoint \"",
      hole$endpoint, "\" at age ", hole$age, ". Add that age's column or an \"",
      toupper(hole$endpoint), "_ALL\" column to the lookup.",
      call. = FALSE
    )
  }

  # Stable order: concentration, then configured endpoint order, then age.
  ep_names <- tolower(vapply(entry$endpoints, `[[`, "", "name"))
  ep_order <- match(out$endpoint, ep_names)
  out <- out[order(as.numeric(out$conc), ep_order, as.numeric(out$age)), ,
             drop = FALSE]
  rownames(out) <- NULL

  # Contract: the concentration key is always character, at `dgt` decimals.
  out$conc <- matchable(as.numeric(out$conc), dgt = dgt)
  out
}
