# ── Wide-to-long helpers and small utilities ────────────────────────────

# Key-column aliases recognised when the user does not name them explicitly.
# Column names are compared after this: case and separators are spelling, not
# meaning, so `mort_rate`, `Mort Rate` and `mortrate` are the same column.
.norm_name <- function(x) gsub("[^a-z0-9]", "", tolower(x))

# A coordinate column under any spelling the inputs use, mapped to the two
# names the analysis grid is keyed on. `NULL` for anything that is not one.
.coord_alias <- function(name) {
  n <- .norm_name(name)
  if (n %in% c("x", "lon", "long", "longitude", "xcoord", "easting")) {
    "x"
  } else if (n %in% c("y", "lat", "latitude", "ycoord", "northing")) {
    "y"
  } else {
    NA_character_
  }
}

.COORD_VARIANTS <- c(
  "x", "y", "X", "Y", "lon", "lat", "Lon", "Lat",
  "long", "longitude", "latitude", "Longitude", "Latitude",
  "GID", "GridID"
)

.DOMAIN_VARIANTS <- c(
  "Country", "country", "Location", "location", "Province", "province",
  "Region", "region", "admin", "iso3", "ISO3", "LOC"
)

# Resolve the key columns of a wide table: explicit `keys` win, then the
# coordinate aliases, then the domain aliases. `key_arg` is the name of the
# caller's own argument so that the error can point at the parameter the user
# actually has in front of them (`xy` in .slice_conc()/.slice_pop(), `loc` in
# .slice_age()/.slice_mort()).
.resolve_key_cols <- function(.data, keys, coord, domain, key_arg = "xy") {
  nm <- names(.data)

  if (!is.null(keys)) {
    cols <- nm[nm %in% keys]
    if (length(cols) == 0) {
      .abort(
        str_c(
          "None of the requested key columns ({paste(keys, collapse = \", \")}) exist in the ",
          "data. Available columns: {paste(nm, collapse = \", \")}."
        )
      )
    }
    return(cols)
  }

  cols <- nm[nm %in% coord]
  if (length(cols) > 0) {
    return(cols)
  }

  cols <- nm[nm %in% domain]
  if (length(cols) > 0) {
    cli::cli_inform(str_c(
      "No column from the preferred key set found; joining on: {paste(cols, collapse = \", \")}"
    ))
    return(cols)
  }

  .abort(
    str_c(
      "No coordinate or domain key column found. Available columns: ",
      "{paste(nm, collapse = \", \")}. Name them explicitly with the `{key_arg}` argument."
    )
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

# Columns that cannot be an input's value column: the coordinate and domain
# aliases, plus any age / cause column the table carries under a non-canonical
# name. Used to count the value candidates of an input; a table with several
# numeric candidates and no canonical value column is an error, never a guess.
.value_key_cols <- function(.data, age = FALSE, cause = FALSE) {
  nm <- names(.data)
  keys <- unique(c(nm[!is.na(vapply(nm, .coord_alias, character(1)))],
                   nm[nm %in% .DOMAIN_VARIANTS]))
  if (age) {
    hit <- .pick_column(.data, "age",
                        prefer = c("age", "age_group", "agegroup"))
    keys <- c(keys, hit)
  }
  if (cause) {
    hit <- .pick_column(.data, "cause|endpoint",
                        prefer = c("endpoint", "cause"))
    keys <- c(keys, hit)
  }
  keys
}

# The value column an input contributes to the calculation.
#
# The package computes from a set of inputs; it does not arbitrate whether the
# inputs belong to the same scenario or year. `case` (`scenario =`) is a
# per-input column selector: when the input carries that column it is used,
# otherwise the canonical column, otherwise the input's single numeric
# non-key column -- an input that already holds one value column needs no
# scenario name. Several candidates and no canonical column stop with the
# candidates listed rather than picking one silently. `strict = FALSE` skips
# that stop and leaves the table untouched, so callers that collect several
# problems at once (`.check_inputs()`) still report them all.
.resolve_case_col <- function(.data, case, keys, canonical, label,
                              strict = TRUE, allow_key_strings = FALSE) {
  if (!is.null(case) && (!is.character(case) || length(case) != 1L)) {
    .abort("The scenario must be a single column name.")
  }
  nm <- names(.data)

  if (!is.null(case) && case %in% nm) {
    return(case)
  }
  if (canonical %in% nm) {
    if (!is.null(case)) {
      cli::cli_inform(str_c(
        "{label} has no column \"{case}\"; using `{canonical}` (the input is not ",
        "scenario-addressed)."
      ))
    }
    return(canonical)
  }

  # A concentration may be stored as a rendered character key; such a column
  # is still a value column, as long as every value parses as a number. Label
  # columns (`source`, `notes`) stay out of the count.
  candidate_like <- function(v) {
    if (is.numeric(v)) {
      return(TRUE)
    }
    if (allow_key_strings && (is.character(v) || is.factor(v))) {
      parsed <- suppressWarnings(as.numeric(as.character(v)))
      return(length(parsed) > 0L && !anyNA(parsed))
    }
    FALSE
  }
  candidates <- setdiff(nm, keys)
  candidates <- candidates[vapply(.data[candidates], candidate_like, logical(1))]

  if (length(candidates) == 1L) {
    cli::cli_inform(str_c(
      "{label}: using the single value column `{candidates}` as `{canonical}`."
    ))
    return(candidates)
  }

  if (!strict) {
    return(canonical)
  }

  if (is.null(case)) {
    # The candidate list and the advice that goes with it are built here rather
    # than inside the string: a multi-line `if` inside a glue expression cannot
    # be kept both readable and within the line width.
    candidates_txt <- if (length(candidates) == 0L) {
      "none"
    } else {
      paste0("`", candidates, "`", collapse = ", ")
    }
    hint_txt <- if (length(candidates) > 1L) {
      paste0(". Name the intended column `", canonical, "`, or select one ",
             "with `scenario=`.")
    } else {
      paste0(". Name the intended column `", canonical, "`.")
    }
    .abort(str_c(
      "No `{canonical}` column in {label}, and no single numeric value ",
      "column to use instead. Value candidates: {candidates_txt}{hint_txt}"
    ))
  }

  candidate_txt <- if (length(candidates) > 0L) {
    paste0(" Value candidates: ",
           paste0("`", candidates, "`", collapse = ", "), ".")
  } else {
    ""
  }
  .abort(str_c(
    "Scenario column \"{case}\" not found in the data. Available columns: ",
    "{paste(nm, collapse = \", \")}.{candidate_txt}"
  ))
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
# ── one input, one scenario ─────────────────────────────────────────────





# Write a table to `path`, chosen by extension: `.rds` (saveRDS()), `.csv`
# (readr::write_csv()) or `.xlsx` (writexl, Suggests-guarded). Shared by
# build_grid_info(); `label` names the product in the
# message so each caller says what it wrote. The write is a side effect, never
# a replacement for the return value.
.write_table_file <- function(x, path, label) {
  if (!is.character(path) || length(path) != 1 || is.na(path)) {
    .abort("`path` must be a single file path.")
  }

  ext <- tolower(file_ext(path))
  if (identical(ext, "rds")) {
    saveRDS(x, path)
  } else if (identical(ext, "csv")) {
    readr::write_csv(x, path)
  } else if (identical(ext, "xlsx")) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      .abort(
        str_c(
          "Writing `.xlsx` needs the `writexl` package (a suggested dependency). Install it with ",
          "install.packages(\"writexl\"), or write `.rds` / `.csv`, which need nothing extra."
        )
      )
    }
    writexl::write_xlsx(x, path)
  } else {
    .abort(
      str_c(
        "Unsupported `path` extension: \".{ext}\". Supported: \".rds\", \".csv\", \".xlsx\"."
      )
    )
  }

  cli::cli_inform("{label} written to: {normalizePath(path, mustWork = FALSE)}")
  invisible(path)
}

# Cell size as it is reported: the x and y values when the axes differ, one
# value when they agree. Two axes that agree to within rounding (the spacing
# recovered from coordinate keys stored rounded, e.g. 0.2501 vs 0.2502, is one
# nominal 0.25 deg grid) are collapsed to their mean, so a square grid keeps
# the long-standing shape of `attr(info, "res")` and of the grain message.
.as_res <- function(res) {
  res <- as.numeric(res)
  if (length(res) == 2L && !anyNA(res) &&
      abs(res[1] - res[2]) <= 1e-3 * max(abs(res))) {
    res <- mean(res)
  }
  res
}

# Cell size for a message: "2.5", "0.25" or "2.5 x 2".
.fmt_res <- function(res) {
  paste(format(signif(res, 3), trim = TRUE, scientific = FALSE), collapse = " x ")
}

# left_join() on the columns the two frames share. This is exactly the natural
# join, said explicitly: dplyr otherwise prints one "Joining with `by = ...`"
# message per call, which buries the run's own output (a real run printed more
# than a hundred of them).
#
# What goes through here is a grid or domain skeleton paired with one table per
# input, and the supporting tables legitimately fan a skeleton row out: a cell
# takes one `RR` per endpoint and age from the lookup, and `mort_rate` /
# `age_struc` copy a domain's rows onto every cell of that domain. That is the
# calculation, not an accident, so the relationship is declared -- otherwise
# dplyr's "unexpected many-to-many" warning fires on every calibrated run. The
# supporting tables are one row per key by construction (`rr_std()` renders one
# row per concentration, endpoint and age); the fan-out's row count is pinned in
# `tests/testthat/test-utils.R`.
.left_join_common <- function(x, y, relationship = "many-to-many") {
  left_join(x, y, by = intersect(names(x), names(y)), relationship = relationship)
}