# ── Concentration-response lookup tables ────────────────────────────────
#
# Built-in tables are stored as list(MEAN = , UP = , LOW = ) of wide
# data.frames: one `conc` column plus one `{endpoint}_{age}` column per
# endpoint/age stratum.

# Model name -> built-in lookup table object. Names are matched
# case-insensitively; `NULL` entries are not allowed.
.CR_TABLE_REGISTRY <- list(
  GEMM      = "GEMM_Lookup_Table",
  `NCD+LRI` = "GEMM_Lookup_Table",
  `5COD`    = "GEMM_Lookup_Table",
  IER       = "IER2017_Lookup_Table",
  IER2017   = "IER2017_Lookup_Table",
  IER2015   = "IER2015_Lookup_Table",
  IER2013   = "IER2013_Lookup_Table",
  IER2010   = "IER2010_Lookup_Table",
  MRBRT     = "MRBRT2021_Lookup_Table",
  MRBRT2021 = "MRBRT2021_Lookup_Table",
  MRBRT2019 = "MRBRT2019_Lookup_Table",
  O3        = "O3_CR_Lookup_Table",
  NO2       = "NO2_CR_Lookup_Table"
)

#' Valid CR model names
#'
#' @return Character vector of accepted `CRF`/`CR_Model` values.
#' @export
#' @examples
#' cr_models()
cr_models <- function() {
  names(.CR_TABLE_REGISTRY)
}

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

# Canonicalise a user-supplied CR model name.
.match_cr_model <- function(CR_Model) {
  if (!is.character(CR_Model) || length(CR_Model) != 1) {
    stop("`CRF` must be a single character string or a data.frame.", call. = FALSE)
  }
  valid <- names(.CR_TABLE_REGISTRY)
  hit   <- valid[toupper(valid) == toupper(trimws(CR_Model))]
  if (length(hit) == 0) {
    stop(
      "Unknown CR model \"", CR_Model, "\". Valid models: ",
      paste(valid, collapse = ", "), ". ", call. = FALSE
    )
  }
  hit[1]
}

# Fetch one built-in lookup table as list(MEAN, UP, LOW).
.cr_table <- function(CR_Model) {
  get(.CR_TABLE_REGISTRY[[CR_Model]], envir = asNamespace("AttrMort"))
}

#' Standardize a concentration-response lookup table
#'
#' Turns a built-in wide lookup table into a join-ready long table with one
#' row per concentration, endpoint and age group. The concentration axis is
#' rendered as character keys (`matchable()` precision `dgt`) so that it can
#' be joined against exposure data regardless of how that data is stored.
#'
#' @param CR_Model Character. CR model name; see [cr_models()] for the
#'   accepted values. Matched case-insensitively.
#' @param index Character. Which table to use: `"MEAN"` (default), `"UP"` or
#'   `"LOW"`. `"UPPER"` and `"LOWER"` are accepted as aliases.
#' @param dgt Integer. Decimal places used to render the concentration keys.
#'   Must match the precision used for the exposure side (`dgt_conc` in
#'   [Mortality()]). Default 1.
#'
#' @return A data.frame with columns `conc` (character), `endpoint`,
#'   `age` (character) and `RR`.
#' @export
#'
#' @examples
#' head(RR_std("GEMM", "MEAN"))
#' unique(RR_std("O3", "MEAN")$endpoint)
RR_std <- function(CR_Model, index = "MEAN", dgt = 1) {
  index    <- .match_ci(index)
  CR_Model <- .match_cr_model(CR_Model)
  RR       <- .cr_table(CR_Model)

  RR_tbl <- RR[[index]] |>
    pivot_longer(
      cols      = -conc,
      values_to = "RR",
      names_to  = c("endpoint", "age"),
      names_sep = "_"
    ) |>
    mutate(endpoint = tolower(endpoint))

  RR_reshape <- if (CR_Model == "5COD") {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = c("copd", "ihd", "lc", "lri", "stroke"),
      age      = c("ALL", seq(25, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      group_by(conc, endpoint) |>
      fill(RR) |>
      ungroup() |>
      filter(age != "ALL")
  } else if (CR_Model %in% c("GEMM", "NCD+LRI")) {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = "ncd+lri",
      age      = c("ALL", seq(25, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      group_by(conc, endpoint) |>
      fill(RR) |>
      ungroup() |>
      filter(age != "ALL")
  } else if (str_detect(CR_Model, "^IER")) {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = c("copd", "ihd", "lc", "stroke", "lri"),
      age      = c("ALL", seq(0, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      group_by(conc, endpoint) |>
      fill(RR) |>
      ungroup() |>
      filter(age != "ALL") |>
      filter(
        (endpoint %in% c("copd", "ihd", "lc", "stroke") &
           as.numeric(age) >= 25) |
          (endpoint == "lri" & as.numeric(age) < 5)
      )
  } else if (CR_Model %in% c("MRBRT", "MRBRT2021")) {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = c("copd", "dm2", "ihd", "lc", "lri", "stroke"),
      age      = c("ALL", seq(0, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      group_by(conc, endpoint) |>
      fill(RR) |>
      ungroup() |>
      filter(age != "ALL") |>
      filter(
        endpoint %in% c("copd", "dm2", "ihd", "lc", "stroke", "lri") &
          as.numeric(age) >= 25
      )
  } else if (CR_Model == "MRBRT2019") {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = c("copd", "dm2", "ihd", "lc", "lri", "stroke"),
      age      = c("ALL", seq(0, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      group_by(conc, endpoint) |>
      fill(RR) |>
      ungroup() |>
      filter(age != "ALL") |>
      filter(
        (endpoint %in% c("copd", "dm2", "ihd", "lc", "stroke") &
           as.numeric(age) >= 25) |
          (endpoint == "lri" & as.numeric(age) < 5)
      )
  } else if (CR_Model == "O3") {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = "copd",
      age      = c("ALL", seq(25, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      fill(RR) |>
      filter(age != "ALL")
  } else if (CR_Model == "NO2") {
    expand_grid(
      conc     = RR[[index]] |> pull(conc),
      endpoint = "cause",
      age      = c("ALL", seq(15, 95, 5) |> matchable(0))
    ) |>
      left_join(RR_tbl) |>
      fill(RR) |>
      filter(age != "ALL")
  }

  # Contract: the concentration key is always character, at `dgt` decimals.
  RR_reshape |>
    mutate(conc = matchable(as.numeric(conc), dgt = dgt)) |>
    select(conc, endpoint, age, RR)
}
