# ── Column-name detection and input validation ──────────────────────────
#
# Both functions are internal: mortality() calls them on every invocation, so
# their output has to be quiet when the data is fine and specific when it is
# not.

# The endpoints each CR model can use now live in the C-R configuration
# (inst/extdata/cr_models.json, read through cr_config()) instead of being
# duplicated here.

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
# per-field warnings and the mapping report, which is what mortality() wants
# when a missing field is not an error.
detect_columns <- function(data,
                           schema = c("age", "cause", "mortrate", "prop",
                                      "location"),
                           quiet = FALSE) {
  stopifnot(is.data.frame(data))
  col_names <- names(data)
  col_lower <- tolower(col_names)

  result <- character(0)
  used   <- character(0)   # actual columns already assigned to a semantic

  for (semantic in schema) {
    variants <- .COLUMN_VARIANTS[[semantic]]
    if (is.null(variants)) {
      next
    }

    found <- NULL

    # exact match on the normalised name first (`Mort Rate` finds mortrate)
    for (v in variants) {
      idx <- which(col_lower == tolower(v) | .norm_name(col_names) == .norm_name(v))
      if (length(idx) == 1 && !col_names[idx] %in% used) {
        found <- col_names[idx]
        break
      }
    }

    # then a substring match
    if (is.null(found)) {
      for (v in variants) {
        idx <- which(str_detect(col_lower, fixed(tolower(v))))
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
      cli::cli_warn("detect_columns: no column found for '{semantic}'")
    }
  }

  if (!quiet && length(result) > 0) {
    cli::cli_inform(str_c(
      "Column mapping detected: ",
      "{paste(sprintf(\"%s -> %s\", names(result), result), collapse = \", \")}"
    ))
  }

  result
}

# The skeleton columns a table actually shares with `calc_fild`. When the caller
# does not say (`mortality()` does; a direct call and `decompose()` do not), the
# documented domain aliases the preparation step leaves behind are used; a table
# that carries none of them is keyed on whatever non-value columns it has, which
# is what keeps a legitimate custom domain column out of the "extra" report.
.input_key_cols <- function(ds, key_cols = NULL) {
  if (is.null(key_cols)) {
    hits <- intersect(names(ds), c("location", "x", "y", "lon", "lat"))
    if (length(hits) == 0L) {
      hits <- setdiff(names(ds), c("conc", "pop", "age", "endpoint", "prop",
                                   "mortrate"))
    }
    return(hits)
  }
  intersect(names(ds), key_cols)
}

# The `mort_rate` columns a calculation joins a cell on: `endpoint` and `age`
# are the CRF axes, the rest are the columns `mort_rate` shares with the
# skeleton (a domain column, or coordinates).
#
# `mortality()` passes the skeleton's own column names, which is the exact
# answer; a caller that does not gets `.input_key_cols()`'s fallback. Guessing
# too narrowly would flag legitimate keys as duplicates.
.mort_key_cols <- function(mort, key_cols = NULL) {
  intersect(names(mort),
            unique(c(.input_key_cols(mort, key_cols), "endpoint", "age")))
}

# The value columns of each input, as `mortality()` prepares them: what an input
# is *for*. Anything else it carries is payload.
.INPUT_VALUE_COLS <- list(
  conc      = "conc",
  pop       = "pop",
  age_struc = c("age", "prop"),
  mort_rate = c("age", "endpoint", "mortrate")
)

# The age keys a CR model declares, as the character keys the tables join on
# (`.cr_ages()` has already normalised every endpoint's range or vector).
.crf_age_keys <- function(entry) {
  ages <- unlist(map(entry$endpoints, "ages"), use.names = FALSE)
  as.character(sort(unique(as.numeric(ages))))
}


# Duplicated keys in `mort_rate`, summarised for the report: how many keys, how
# many rows, a couple of example keys, and the columns outside the key that
# vary inside a duplicated key -- which is what the caller has to filter on.
# The value column is not one of them: it varying is the symptom, not the
# thing to filter on.
#
# A duplicated key is never a legitimate input. `.left_join_common()` copies
# the skeleton onto every duplicate, so the wide result either grows a row per
# duplicate or -- when the duplicates agree on every key -- collapses into
# list-columns and the run dies much later with `invalid 'type' (list) of
# argument`. The usual cause is a table that keeps a year / sex / scenario
# column: GBD publishes one row per (location, age, cause) *per year*.
.duplicate_key_problem <- function(mort, key_cols = NULL, value_cols = NULL) {
  key_cols <- .mort_key_cols(mort, key_cols)
  if (length(key_cols) < 2L || nrow(mort) == 0L) {
    return(NULL)
  }

  key      <- do.call(paste, c(lapply(mort[key_cols], as.character),
                              list(sep = "\r")))
  repeated <- duplicated(key) | duplicated(key, fromLast = TRUE)
  if (!any(repeated)) {
    return(NULL)
  }

  bad_rows <- mort[repeated, , drop = FALSE]
  bad_key  <- key[repeated]
  extra    <- setdiff(names(mort), c(key_cols, value_cols))
  varying  <- extra[vapply(extra, function(col) {
    any(vapply(split(bad_rows[[col]], bad_key),
               function(v) length(unique(v)) > 1L, logical(1)))
  }, logical(1))]

  first  <- bad_rows[!duplicated(bad_key), key_cols, drop = FALSE]
  first  <- head(first, 3L)
  sample <- map_chr(seq_len(nrow(first)), function(i) {
    value <- vapply(first, function(col) as.character(col[[i]]), character(1))
    str_c(names(first), " = ", value, collapse = ", ")
  })

  list(
    n_keys  = length(unique(bad_key)),
    n_rows  = sum(repeated),
    sample  = sample,
    varying = varying,
    keys    = key_cols
  )
}

# Validate the prepared inputs. Returns a report instead of throwing, so the
# caller decides whether a problem is fatal (`validate = "stop"` in
# mortality()).
#
# `blocking` collects the problems that must abort the calculation (missing
# data, impossible values, a CRF whose endpoints are absent, a `mort_rate`
# whose keys repeat); `issues` collects everything, including soft warnings.
#
# `key_cols` is the set of columns the skeleton (`calc_fild`) joins on; the
# key-uniqueness check joins it with `endpoint` and `age` to get the key a
# `mort_rate` row has to be unique on.
validate_mortality_input <- function(data_list,
                                     cr_model      = NA_character_,
                                     age_tolerance = 0.01,
                                     max_rate      = 5e4,
                                     dgt_conc      = 1,
                                     config        = NULL,
                                     key_cols      = NULL) {
  state <- new.env(parent = emptyenv())
  state$issues   <- character(0)
  state$blocking <- character(0)

  warnf <- function(fmt, ...) {
    msg <- sprintf(fmt, ...)
    state$issues <- c(state$issues, msg)
    cli::cli_warn("{msg}")
  }
  blockf <- function(fmt, ...) {
    msg <- sprintf(fmt, ...)
    state$issues   <- c(state$issues, msg)
    state$blocking <- c(state$blocking, msg)
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
      nums <- names(mort)[map_lgl(mort, is.numeric)]
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

    # Age keys join the CRF's strata as characters. A value that names no
    # stratum can only produce an empty join, and until now it did so quietly:
    # the rows disappeared between the inputs and the lookup. Say which values
    # they are, so a mislabelled age column is visible before it costs rows.
    age_col <- intersect(c("age", "age_group", "agegroup"), mort_cols)
    if (length(age_col) > 0) {
      stray <- setdiff(unique(.standardize_age_key(mort[[age_col[1]]])),
                       .STD_AGE_GROUPS)
      if (length(stray) > 0) {
        warnf(paste0(
          "mort_rate: %s age value(s) are not a standard 5-year stratum (%s); ",
          "unless the CRF defines them, those rows are dropped by the join ",
          "and contribute nothing. The CRF keys are the lower bound of each ",
          "stratum: %s."
        ),
        format(length(stray), big.mark = ","),
        paste(head(sort(stray), 8), collapse = ", "),
        paste(.STD_AGE_GROUPS, collapse = ", "))
      }
    }

    # The model resolves once and serves both remaining checks.
    entry <- NULL
    if (!is.na(cr_model) && nzchar(cr_model)) {
      entry <- tryCatch(
        .cr_model_entry(.as_cr_config(config), cr_model),
        error = function(e) NULL
      )
    }

    # Each CRF carries a curve only for the strata it lists. A stratum the
    # caller supplies that the model does not cover can only produce an empty
    # join, so the result covers fewer strata than the inputs do -- and that is
    # invisible in the result. Name the strata and what share of the age
    # structure they carry. Only standard strata: a label the CRF cannot use at
    # all is the previous check's business.
    if (length(age_col) > 0 && !is.null(entry)) {
      covered   <- .crf_age_keys(entry)
      supplied  <- intersect(unique(.standardize_age_key(mort[[age_col[1]]])),
                             .STD_AGE_GROUPS)
      uncovered <- setdiff(supplied, covered)
      if (length(uncovered) > 0) {
        share_txt <- ""
        age_df <- data_list[["age_struc"]]
        if (is.data.frame(age_df) && all(c("age", "prop") %in% names(age_df))) {
          prop  <- suppressWarnings(as.numeric(age_df$prop))
          key   <- .standardize_age_key(age_df$age)
          total <- sum(prop, na.rm = TRUE)
          share <- if (is.finite(total) && total > 0) {
            sum(prop[key %in% uncovered], na.rm = TRUE) / total
          } else {
            NA_real_
          }
          if (is.finite(share)) {
            share_txt <- str_c(" and carry ", sprintf("%.1f%%", 100 * share),
                               " of `age_struc`'s `prop`")
          }
        }
        warnf(paste0(
          "mort_rate: %s age stratum(s) have no curve for the model `%s` (%s)%s; ",
          "those rows are dropped by the join and contribute nothing. ",
          "The CRF covers %s."
        ),
        format(length(uncovered), big.mark = ","), cr_model,
        paste(uncovered, collapse = ", "), share_txt,
        paste(covered, collapse = ", "))
      }
    }

    # A repeated key is a broken input, not a data pattern: the join fans the
    # skeleton out and the wide result stops meaning one row per cell.
    value_label <- if (length(rate_col) > 0L) rate_col[1] else "mortrate"
    dup <- .duplicate_key_problem(mort, key_cols, value_cols = rate_col)
    if (!is.null(dup)) {
      blockf(paste0(
        "mort_rate: %s duplicated key(s) over (%s): %s row(s) share a key ",
        "with another row.\n",
        "  example key(s): %s\n",
        "  column(s) that differ inside a duplicated key: %s\n",
        "  `mort_rate` must hold one row per key: filter the table to a ",
        "single year / sex / scenario first."
      ),
      format(dup$n_keys, big.mark = ","),
      paste(dup$keys, collapse = ", "),
      format(dup$n_rows, big.mark = ","),
      paste(dup$sample, collapse = " | "),
      if (length(dup$varying) == 0L) {
        str_c("none (the rows differ only in `", value_label,
              "`: the table carries several values per key)")
      } else {
        paste0("`", dup$varying, "`", collapse = ", ")
      })
    }

    # The calculation lower-cases the literal `endpoint` column
    # (`.standardize_join_keys()`), so that is the column this report has to
    # describe; `cause` is only a fallback for a caller that hands the validator
    # a table directly. Both present is ambiguous input: say so, because one of
    # them is silently unused.
    cause_col <- intersect(c("endpoint", "cause"), mort_cols)
    if (all(c("cause", "endpoint") %in% mort_cols)) {
      warnf(paste0(
        "mort_rate: the table carries both `cause` and `endpoint`; the ",
        "calculation reads `endpoint` and keeps `cause` as a payload column of ",
        "the wide result. Keep one of them."
      ))
    }
    if (length(cause_col) > 0 && !is.null(entry)) {
      expected_ep <- map_chr(entry$endpoints, "name")
      # `held` keeps the caller's own spelling for the message, `actual` is
      # what the join will compare -- the endpoints are matched as strings.
      held   <- unique(as.character(mort[[cause_col[1]]]))
      actual <- unique(tolower(held))
      absent <- setdiff(expected_ep, actual)
      extra  <- setdiff(actual, expected_ep)

      held_txt <- paste(head(held, 20), collapse = ", ")
      hint_txt <- str_c(
        "AttrMort does not translate disease names: rename the values in `",
        cause_col[1], "` to the CRF spelling."
      )

      if (length(absent) == length(expected_ep)) {
        blockf(paste0(
          "mort_rate: none of the endpoints the model `%s` needs (%s) is ",
          "present in `%s`.\n  `%s` holds: %s\n  %s"
        ), cr_model, paste(expected_ep, collapse = ", "), cause_col[1],
        cause_col[1], held_txt, hint_txt)
      } else if (length(absent) > 0) {
        warnf(paste0(
          "mort_rate: %s of the %s endpoint(s) the model `%s` needs are ",
          "absent from `%s` (%s); those strata cannot be computed.\n",
          "  `%s` holds: %s\n  %s"
        ), length(absent), length(expected_ep), cr_model, cause_col[1],
        paste(absent, collapse = ", "), cause_col[1], held_txt, hint_txt)
      }
      if (length(extra) > 0) {
        extra_held <- head(held[tolower(held) %in% extra], 20)
        cli::cli_inform(str_c(
          "mort_rate: {length(extra)} endpoint value(s) in `{cause_col[1]}` are ",
          "not used by {cr_model} ({paste(extra_held, collapse = \", \")}); they ",
          "will not contribute to the result. If they name a disease the model ",
          "covers, rename them to the CRF spelling -- AttrMort does not ",
          "translate disease names."
        ))
      }
    }
  }

  # ── columns that are neither a key nor a value ─────────────────────
  # `.widen_mort()` pivots on `(endpoint, age)` and keeps every other column of
  # the joined frame as an identity column of the result. A column an input
  # carries beyond the join key and its own value columns therefore decides the
  # row identity instead of filling it: one row per distinct combination
  # instead of one row per cell, NA wherever that combination was never
  # computed, and `sum()` over the result is NA.
  #
  # This is what a `scenario = NULL` run keeps: only `scenario =` goes through
  # the per-input slicers, which narrow a table to its canonical columns. Say
  # which columns they are -- and the calculation refuses the polluted shape, so
  # the report is where the fix is explained.
  for (nm in names(.INPUT_VALUE_COLS)) {
    ds <- data_list[[nm]]
    if (is.null(ds)) {
      next
    }
    extra <- setdiff(names(ds),
                     c(.INPUT_VALUE_COLS[[nm]], .input_key_cols(ds, key_cols)))
    if (length(extra) == 0L) {
      next
    }
    warnf(paste0(
      "%s: %s column(s) are neither a join key nor a value column (%s). Each one ",
      "becomes an identity column of the wide result: one row per distinct ",
      "combination instead of one row per cell, with NA in every value column ",
      "that combination never computed. Keep only the key column(s) and %s."
    ),
    nm, format(length(extra), big.mark = ","),
    paste0("`", extra, "`", collapse = ", "),
    paste0("`", .INPUT_VALUE_COLS[[nm]], "`", collapse = ", "))
  }

  # ── age structure ──────────────────────────────────────────────────
  age_df <- data_list[["age_struc"]]
  if (!is.null(age_df)) {
    age_col  <- intersect(c("age", "age_group", "agegroup"), names(age_df))
    prop_col <- intersect(c("prop", "proportion", "fraction"), names(age_df))
    loc_col  <- detect_columns(age_df, schema = "location", quiet = TRUE)

    if (length(age_col) > 0) {
      # The same key the calculation will join on: labels such as
      # "15-19 years" are the stratum "15" there, so they are one here too.
      actual_ages  <- unique(.standardize_age_key(age_df[[age_col[1]]]))
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
      nums <- names(conc_df)[map_lgl(conc_df, is.numeric)]
      conc_col <- setdiff(nums, c("x", "y", "lon", "lat"))
    }
    if (length(conc_col) > 0) {
      conc_vals <- suppressWarnings(as.numeric(conc_df[[conc_col[1]]]))
      n_neg <- sum(conc_vals < 0, na.rm = TRUE)
      if (n_neg > 0) {
        blockf("conc: %s negative value(s) in '%s'",
               format(n_neg, big.mark = ","), conc_col[1])
      }

      # A character concentration column is trusted as a key, so it has to
      # already be rendered the way the lookup tables are: matchable() at
      # `dgt_conc`. Anything else (e.g. "35.20") simply never joins, and the
      # symptom is an empty join several steps later -- say it here instead.
      raw <- conc_df[[conc_col[1]]]
      if (is.factor(raw)) {
        raw <- as.character(raw)
      }
      if (is.character(raw)) {
        canon <- matchable(conc_vals, dgt = dgt_conc)
        bad   <- !is.na(conc_vals) & raw != canon
        if (any(bad)) {
          first <- which(bad)[1]
          warnf(paste0("conc: %s value(s) are not rendered at `dgt_conc = %d` ",
                       "(e.g. '%s' instead of '%s'); exposure keys must be ",
                       "matchable(conc, dgt_conc) to join the lookup table"),
                format(sum(bad), big.mark = ","), dgt_conc,
                raw[first], canon[first])
        }
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

  list(valid = length(state$blocking) == 0, issues = state$issues,
       blocking = state$blocking)
}
