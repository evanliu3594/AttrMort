# ── Wide-to-long helpers and small utilities ────────────────────────────

# Key-column aliases recognised when the user does not name them explicitly.
.COORD_VARIANTS <- c(
  "x", "y", "X", "Y", "lon", "lat", "Lon", "Lat",
  "long", "lat", "longitude", "latitude", "Longitude", "Latitude",
  "GID", "GridID"
)

.DOMAIN_VARIANTS <- c(
  "Country", "country", "Location", "location", "Province", "province",
  "Region", "region", "admin", "iso3", "ISO3", "LOC"
)

# Resolve the key columns of a wide table: explicit `keys` win, then the
# coordinate aliases, then the domain aliases.
.resolve_key_cols <- function(.data, keys, coord, domain) {
  nm <- names(.data)

  if (!is.null(keys)) {
    cols <- nm[nm %in% keys]
    if (length(cols) == 0) {
      stop("None of the requested key columns (", paste(keys, collapse = ", "),
           ") exist in the data. Available columns: ",
           paste(nm, collapse = ", "), ".", call. = FALSE)
    }
    return(cols)
  }

  cols <- nm[nm %in% coord]
  if (length(cols) > 0) {
    return(cols)
  }

  cols <- nm[nm %in% domain]
  if (length(cols) > 0) {
    message("No column from the preferred key set found; joining on: ",
            paste(cols, collapse = ", "))
    return(cols)
  }

  stop(
    "No coordinate or domain key column found. Available columns: ",
    paste(nm, collapse = ", "),
    ". Name them explicitly with the `xy` argument.", call. = FALSE
  )
}

# The column that labels the domains of a table: an explicitly named column
# first (`mort_lvl`, or the boundary column `admin_col` selects), then the
# documented domain aliases. Unlike .resolve_key_cols() this never falls back
# to coordinates and never errors -- callers decide what a missing domain
# column means -- so it returns NULL when the table carries none.
.domain_col_of <- function(.data, explicit = NULL) {
  nm <- names(.data)
  explicit <- explicit[!is.na(explicit) & nzchar(explicit)]
  for (col in explicit) {
    if (col %in% nm) {
      return(col)
    }
  }
  hits <- nm[nm %in% .DOMAIN_VARIANTS]
  if (length(hits) > 0) hits[1] else NULL
}

# Fail early, and helpfully, when a scenario column is missing.
.check_scenario <- function(.data, case) {
  if (!is.character(case) || length(case) != 1) {
    stop("The scenario must be a single column name.", call. = FALSE)
  }
  if (!case %in% names(.data)) {
    stop(
      "Scenario column \"", case, "\" not found in the data. ",
      "Available columns: ", paste(names(.data), collapse = ", "), ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Pick one column by regex, preferring canonical names over partial matches.
.pick_column <- function(.data, pattern, prefer = character(0)) {
  nm  <- names(.data)
  hit <- nm[str_detect(nm, regex(pattern, ignore_case = TRUE))]
  if (length(hit) == 0) {
    return(NULL)
  }
  for (p in prefer) {
    exact <- hit[tolower(hit) == tolower(p)]
    if (length(exact) > 0) {
      return(exact[1])
    }
  }
  hit[1]
}

#' Round numbers to a fixed precision for use as join keys
#'
#' Coordinates, concentrations and age groups are joined as strings: rounding
#' first removes floating-point noise, and rendering at a fixed number of
#' decimal places prevents grids of different resolutions from matching each
#' other by accident.
#'
#' @param num Numeric vector.
#' @param dgt Integer. Number of decimal places. Default 2.
#'
#' @return A character vector.
#' @export
#'
#' @examples
#' matchable(10 / 3, 1)
#' matchable(c(116.376, 116.381), 1)
matchable <- function(num, dgt = 2) {
  as.character(round(num, dgt))
}

#' Extract one scenario of gridded exposure data
#'
#' @param .data A wide data.frame: key columns plus one column per scenario.
#' @param case Character. Scenario (column) to extract.
#' @param xy Character vector of key columns. `NULL` (default) uses coordinate
#'   aliases when present, otherwise domain columns.
#' @param dgt Integer. Decimal places used to render the exposure key. Must
#'   match `dgt_conc` in [Mortality()]. Default 1.
#'
#' @return A data.frame with the key columns and `conc`.
#' @export
#'
#' @examples
#' df <- data.frame(x = c("1", "2"), y = c("1", "2"), base2015 = c(35.2, 41.7))
#' getConc(df, "base2015")
getConc <- function(.data, case, xy = NULL, dgt = 1) {
  if (!is.data.frame(.data)) {
    stop("Only accept data.frame INPUT.", call. = FALSE)
  }
  .check_scenario(.data, case)
  keys <- .resolve_key_cols(.data, xy, .COORD_VARIANTS, .DOMAIN_VARIANTS)

  .data |>
    select(all_of(keys), conc = !!case) |>
    mutate(conc = if (is.numeric(conc)) matchable(conc, dgt = dgt) else conc)
}

#' Extract one scenario of population data
#'
#' @inheritParams getConc
#'
#' @return A data.frame with the key columns and `pop`.
#' @export
#'
#' @examples
#' df <- data.frame(x = c("1", "2"), y = c("1", "2"), base2015 = c(1e5, 2e5))
#' getPop(df, "base2015")
getPop <- function(.data, case, xy = NULL) {
  if (!is.data.frame(.data)) {
    stop("Only accept data.frame INPUT.", call. = FALSE)
  }
  .check_scenario(.data, case)
  keys <- .resolve_key_cols(.data, xy, .COORD_VARIANTS, .DOMAIN_VARIANTS)

  .data |> select(all_of(keys), pop = !!case)
}

#' Extract one scenario of population age structure
#'
#' The proportions are renormalised to sum to 1 within each domain, so that
#' inputs expressed as counts or as percentages are both accepted. The number
#' of age groups is checked against `min_age_groups`, because the
#' concentration-response tables are only defined for 5-year strata; a
#' warning (rather than an error) lets non-standard structures through.
#'
#' @inheritParams getConc
#' @param loc Character vector of domain columns. `NULL` (default) uses the
#'   domain aliases.
#' @param min_age_groups Integer. Minimum number of age groups expected.
#'   Use 0 to skip the check. Default 20.
#'
#' @return A data.frame with the domain columns, `age` and `prop`.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   location = rep("A", 20), age = seq(0, 95, 5),
#'   base2015 = rep(1 / 20, 20)
#' )
#' head(getAge(df, "base2015"))
getAge <- function(.data, case, loc = NULL, min_age_groups = 20) {
  if (!is.data.frame(.data)) {
    stop("Only accept data.frame INPUT.", call. = FALSE)
  }
  .check_scenario(.data, case)
  loc_cols <- .resolve_key_cols(.data, loc, .DOMAIN_VARIANTS, .COORD_VARIANTS)

  age_col <- .pick_column(.data, "age",
                          prefer = c("age", "age_group", "agegroup"))
  if (is.null(age_col)) {
    stop("No age column found in the age-structure data. Available columns: ",
         paste(names(.data), collapse = ", "), ".", call. = FALSE)
  }

  n_age <- length(unique(.data[[age_col]]))
  if (min_age_groups > 0 && n_age < min_age_groups) {
    warning(
      "The age structure data have ", n_age, " age group(s); ",
      min_age_groups, " are expected. Results will only cover the age groups ",
      "present in the data. Set `min_age_groups = 0` to silence this warning.",
      call. = FALSE
    )
  }

  .data |>
    select(all_of(loc_cols), age = all_of(age_col), prop = !!case) |>
    group_by(across(any_of(loc_cols))) |>
    mutate(prop = prop.table(prop)) |>
    ungroup()
}

#' Extract one scenario of cause-specific mortality rates
#'
#' @inheritParams getAge
#'
#' @return A data.frame with the domain columns, `age`, `endpoint` and
#'   `mortrate` (deaths per 100,000).
#' @export
#'
#' @examples
#' df <- data.frame(
#'   location = rep("A", 2), age = c(25, 30), endpoint = rep("copd", 2),
#'   base2015 = c(12.5, 30.1)
#' )
#' getMort(df, "base2015")
getMort <- function(.data, case, loc = NULL) {
  if (!is.data.frame(.data)) {
    stop("Only accept data.frame INPUT.", call. = FALSE)
  }
  .check_scenario(.data, case)
  loc_cols <- .resolve_key_cols(.data, loc, .DOMAIN_VARIANTS, .COORD_VARIANTS)

  age_col <- .pick_column(.data, "age",
                          prefer = c("age", "age_group", "agegroup"))
  if (is.null(age_col)) {
    stop("No age column found in the mortality data. Available columns: ",
         paste(names(.data), collapse = ", "), ".", call. = FALSE)
  }

  cause_col <- .pick_column(.data, "cause|endpoint",
                            prefer = c("endpoint", "cause"))
  if (is.null(cause_col)) {
    stop("No cause/endpoint column found in the mortality data. ",
         "Available columns: ", paste(names(.data), collapse = ", "), ".",
         call. = FALSE)
  }

  .data |>
    select(
      all_of(loc_cols),
      age      = all_of(age_col),
      endpoint = all_of(cause_col),
      mortrate = !!case
    )
}
