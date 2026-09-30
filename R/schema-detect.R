# ── Column-name detection and input validation ──────────────────────────
#
# Both functions are internal: Mortality() calls them on every invocation, so
# their output has to be quiet when the data is fine and specific when it is
# not.

# Disease endpoints each CR model can use. Kept in sync with the reshape
# branches of RR_std(); tests/testthat/test-schema-detect.R pins the two
# together.
.CR_ENDPOINTS <- list(
  `5COD`    = c("copd", "ihd", "lc", "lri", "stroke"),
  `NCD+LRI` = "ncd+lri",
  GEMM      = "ncd+lri",
  IER       = c("copd", "ihd", "lc", "stroke", "lri"),
  IER2010   = c("copd", "ihd", "lc", "stroke", "lri"),
  IER2013   = c("copd", "ihd", "lc", "stroke", "lri"),
  IER2015   = c("copd", "ihd", "lc", "stroke", "lri"),
  IER2017   = c("copd", "ihd", "lc", "stroke", "lri"),
  MRBRT     = c("copd", "dm2", "ihd", "lc", "lri", "stroke"),
  MRBRT2019 = c("copd", "dm2", "ihd", "lc", "lri", "stroke"),
  MRBRT2021 = c("copd", "dm2", "ihd", "lc", "lri", "stroke"),
  O3        = "copd",
  NO2       = "cause"
)

# Standard 5-year age strata used by the lookup tables.
.STD_AGE_GROUPS <- as.character(seq(0, 95, 5))

# Column-name variants per semantic field, in priority order.
.COLUMN_VARIANTS <- list(
  age      = c("age", "age_group", "agegroup", "age_grp", "Age", "AGE",
               "age_band", "agegroup_name"),
  cause    = c("cause", "endpoint", "disease", "Cause", "Endpoint",
               "disease_name", "diagnosis"),
  mortrate = c("mortrate", "mort_rate", "mortality_rate", "rate", "mx",
               "death_rate", "MortRate"),
  prop     = c("prop", "proportion", "fraction", "age_prop", "age_structure",
               "pct", "AgeStruc"),
  location = c("location", "country", "Country", "region", "province",
               "admin", "LOC", "iso3", "ISO3")
)

# Canonical column names expected by the computation pipeline, keyed by the
# semantic field names returned by detect_columns().
.COLUMN_TARGET <- c(
  age      = "age",
  cause    = "endpoint",
  mortrate = "mortrate",
  prop     = "prop",
  location = "location"
)

# Map arbitrary column names onto the canonical schema.
#
# Returns c(semantic = "<actual column>"); `quiet = TRUE` suppresses both the
# per-field warnings and the mapping report, which is what Mortality() wants
# when a missing field is not an error.
detect_columns <- function(df,
                           schema = c("age", "cause", "mortrate", "prop",
                                      "location"),
                           quiet = FALSE) {
  stopifnot(is.data.frame(df))
  col_names <- names(df)
  col_lower <- tolower(col_names)

  result <- character(0)
  used   <- character(0)   # actual columns already assigned to a semantic

  for (semantic in schema) {
    variants <- .COLUMN_VARIANTS[[semantic]]
    if (is.null(variants)) next

    found <- NULL

    # exact (case-insensitive) match first
    for (v in variants) {
      idx <- which(col_lower == tolower(v))
      if (length(idx) == 1 && !col_names[idx] %in% used) {
        found <- col_names[idx]
        break
      }
    }

    # then a substring match
    if (is.null(found)) {
      for (v in variants) {
        idx <- which(grepl(tolower(v), col_lower, fixed = TRUE))
        idx <- setdiff(idx, which(col_names %in% used))
        if (length(idx) >= 1) {
          found <- col_names[idx[1]]
          break
        }
      }
    }

    if (!is.null(found)) {
      result[semantic] <- found
      used <- c(used, found)
    } else if (!quiet) {
      warning("detect_columns: no column found for '", semantic, "'",
              call. = FALSE)
    }
  }

  if (!quiet && length(result) > 0) {
    message("Column mapping detected: ",
            paste(sprintf("%s -> %s", names(result), result), collapse = ", "))
  }

  result
}

# Validate the prepared inputs. Returns a report instead of throwing, so the
# caller decides whether a problem is fatal (`validate = "stop"` in
# Mortality()).
#
# `blocking` collects the problems that must abort the calculation (missing
# data, impossible values, a CRF whose endpoints are absent); `issues`
# collects everything, including soft warnings.
validate_mortality_input <- function(data_list,
                                     cr_model      = NA_character_,
                                     age_tolerance = 0.01,
                                     max_rate      = 5e4) {
  issues   <- character(0)
  blocking <- character(0)

  warnf <- function(fmt, ...) {
    msg <- sprintf(fmt, ...)
    issues <<- c(issues, msg)
    warning(msg, call. = FALSE)
  }
  blockf <- function(fmt, ...) {
    msg <- sprintf(fmt, ...)
    issues   <<- c(issues, msg)
    blocking <<- c(blocking, msg)
  }

  # ── data presence ──────────────────────────────────────────────────
  expected <- c("conc", "pop", "age_struc", "mort_rate")
  missing_slots <- setdiff(expected, names(data_list))
  if (length(missing_slots) > 0) {
    blockf("Missing data elements: %s", paste(missing_slots, collapse = ", "))
  }

  # ── mortality rates ────────────────────────────────────────────────
  mort <- data_list[["mort_rate"]]
  if (!is.null(mort)) {
    mort_cols <- names(mort)
    for (col in c("age", "endpoint", "mortrate")) {
      if (!col %in% mort_cols && length(detect_columns(mort, schema = col,
                                                       quiet = TRUE)) == 0) {
        blockf("mort_rate: missing required column '%s'", col)
      }
    }

    rate_col <- intersect(c("mortrate", "mort_rate"), mort_cols)
    if (length(rate_col) == 0) {
      nums <- names(mort)[vapply(mort, is.numeric, logical(1))]
      rate_col <- setdiff(nums, "age")
    }
    if (length(rate_col) > 0) {
      rate_vals <- suppressWarnings(as.numeric(mort[[rate_col[1]]]))
      n_neg <- sum(rate_vals < 0, na.rm = TRUE)
      if (n_neg > 0) {
        blockf("mort_rate: %s negative value(s) in '%s'",
               format(n_neg, big.mark = ","), rate_col[1])
      }
      n_high <- sum(rate_vals > max_rate, na.rm = TRUE)
      if (n_high > 0) {
        warnf("mort_rate: %s value(s) above %s per 100,000 in '%s'",
              format(n_high, big.mark = ","),
              format(max_rate, big.mark = ","), rate_col[1])
      }
    }

    cause_col <- intersect(c("cause", "endpoint"), mort_cols)
    if (length(cause_col) > 0 && !is.na(cr_model) &&
        cr_model %in% names(.CR_ENDPOINTS)) {
      actual   <- unique(tolower(as.character(mort[[cause_col[1]]])))
      expected_ep <- .CR_ENDPOINTS[[cr_model]]
      absent <- setdiff(expected_ep, actual)
      extra  <- setdiff(actual, expected_ep)

      if (length(absent) == length(expected_ep)) {
        blockf("mort_rate: none of the endpoints used by %s (%s) are present",
               cr_model, paste(expected_ep, collapse = ", "))
      } else if (length(absent) > 0) {
        warnf("mort_rate: endpoint(s) used by %s but absent: %s",
              cr_model, paste(absent, collapse = ", "))
      }
      if (length(extra) > 0) {
        message("mort_rate: ", length(extra), " endpoint(s) are not used by ",
                cr_model, " (", paste(extra, collapse = ", "),
                "); they will not contribute to the result.")
      }
    }
  }

  # ── age structure ──────────────────────────────────────────────────
  age_df <- data_list[["age_struc"]]
  if (!is.null(age_df)) {
    age_col  <- intersect(c("age", "age_group", "agegroup"), names(age_df))
    prop_col <- intersect(c("prop", "proportion", "fraction"), names(age_df))
    loc_col  <- detect_columns(age_df, schema = "location", quiet = TRUE)

    if (length(age_col) > 0) {
      actual_ages  <- unique(as.character(age_df[[age_col[1]]]))
      missing_ages <- setdiff(.STD_AGE_GROUPS, actual_ages)
      extra_ages   <- setdiff(actual_ages, .STD_AGE_GROUPS)
      if (length(missing_ages) > 0) {
        warnf("age_struc: %d standard age group(s) absent: %s",
              length(missing_ages), paste(head(missing_ages, 8), collapse = ", "))
      }
      if (length(extra_ages) > 0) {
        warnf("age_struc: %d non-standard age group(s): %s",
              length(extra_ages), paste(head(extra_ages, 8), collapse = ", "))
      }
    }

    if (length(prop_col) > 0 && length(loc_col) > 0) {
      sums <- tapply(as.numeric(age_df[[prop_col[1]]]),
                     age_df[[loc_col[1]]], sum, na.rm = TRUE)
      bad  <- names(sums)[abs(sums - 1) > age_tolerance]
      if (length(bad) > 0) {
        warnf("age_struc: %d location(s) whose proportions do not sum to 1 (%s)",
              length(bad), paste(head(bad, 5), collapse = ", "))
      }
    }
  }

  # ── exposure ───────────────────────────────────────────────────────
  conc_df <- data_list[["conc"]]
  if (!is.null(conc_df)) {
    conc_col <- intersect(c("conc", "concentration"), names(conc_df))
    if (length(conc_col) == 0) {
      nums <- names(conc_df)[vapply(conc_df, is.numeric, logical(1))]
      conc_col <- setdiff(nums, c("x", "y", "lon", "lat"))
    }
    if (length(conc_col) > 0) {
      conc_vals <- suppressWarnings(as.numeric(conc_df[[conc_col[1]]]))
      n_neg <- sum(conc_vals < 0, na.rm = TRUE)
      if (n_neg > 0) {
        blockf("conc: %s negative value(s) in '%s'",
               format(n_neg, big.mark = ","), conc_col[1])
      }
    }
  }

  # ── population ─────────────────────────────────────────────────────
  pop_df <- data_list[["pop"]]
  if (!is.null(pop_df)) {
    pop_col <- intersect(c("pop", "Pop", "population"), names(pop_df))
    if (length(pop_col) > 0) {
      pop_vals <- suppressWarnings(as.numeric(pop_df[[pop_col[1]]]))
      n_neg <- sum(pop_vals < 0, na.rm = TRUE)
      if (n_neg > 0) {
        blockf("pop: %s negative value(s) in '%s'",
               format(n_neg, big.mark = ","), pop_col[1])
      }
    }
  }

  list(valid = length(blocking) == 0, issues = issues, blocking = blocking)
}
