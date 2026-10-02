# ── Aggregation & export of mortality() results ───────────────────────────
#
# Aggregation and export of mortality() results. Three rules are deliberate:
#
#   1. No global state.  The attribution field is passed in through the
#      `calc_fild` argument, and output paths are always explicit arguments.
#   2. The summed columns are *explicitly listed* from the `{endpoint}_{age}`
#      naming convention instead of "every numeric column".  The source version
#      summed x/y along with the mortality columns, which silently added
#      coordinates to the death counts (known bug).
#   3. Column-name parsing takes the LAST `_` as the endpoint/age separator, so
#      endpoints that themselves contain `_` or `+` (e.g. `ncd+lri`) survive.
#
# Internal helpers (not exported):
#   .is_coord_cols()           — x/y/lon/lat detection
#   .split_ci_suffix()         — split a trailing `_MEAN`/`_UP`/`_LOW` token
#   .split_mort_names()        — parse `{endpoint}_{age}[_{CI}]` column names
#   .mort_names()              — list the value columns of a result
#   .resolve_at()              — resolve `at` to domain columns
#   .resolve_by()              — normalize `by` to the kept dimensions
#   .aggregate_mortality_one() — aggregate one branch of one data.frame

# ── internal helpers ─────────────────────────────────────────────────────

#' Coordinate column names of a grid-level data.frame
#' @param x A data.frame.
#' @return Character vector of coordinate column names.
#' @noRd
.is_coord_cols <- function(x) {
  str_subset(names(x), regex("^x$|^y$|^lon|^lat", ignore_case = TRUE))
}

#' Split `\{endpoint\}_\{age\}` column names on the LAST underscore
#'
#' @param nm Character vector of column names.
#' @return A data.frame with columns `name`, `endpoint`, `age`, `ci`
#'   (`ci` is `NA` for names without a CI suffix).  Unparseable names get
#'   `NA` in `endpoint`/`age`.
#' @noRd
.split_mort_names <- function(nm) {
  parts <- .split_ci_suffix(nm)
  ci <- parts$ci
  base <- parts$stem
  age <- str_extract(base, "[^_]+$")
  endpoint <- rep(NA_character_, length(base))
  for (i in seq_along(base)) {
    if (is.na(age[i])) {
      next
    }
    cut <- str_length(base[i]) - str_length(age[i]) - 1L
    if (cut < 1L) {
      next
    }
    endpoint[i] <- str_sub(base[i], 1L, cut)
  }
  tibble(name = nm, endpoint = endpoint, age = age, ci = ci)
}

#' Canonical CI branch labels
#'
#' `mortality(ci = ...)` accepts `"MEAN"`, `"UPPER"` and `"LOWER"`
#' (`"UP"`/`"LOW"` are accepted aliases). A result assembled from those three
#' runs is normally suffixed `_MEAN` / `_UPPER` / `_LOWER`, but `_UP` / `_LOW`
#' is accepted too. The label returned here is the canonical one used in the
#' output column names.
#' @noRd
.ci_branches <- c("MEAN", "UP", "LOW")
.ci_aliases <- c(MEAN = "MEAN", UP = "UP", UPPER = "UP", LOW = "LOW", LOWER = "LOW")

#' Split a CI column name into its CI label and the underlying branch column
#' @param nm Character vector of column names.
#' @return A list with `ci` (canonical label or `NA`) and `stem` (the name with
#'   the CI suffix removed; unchanged when there is no suffix).
#' @noRd
.split_ci_suffix <- function(nm) {
  token <- str_extract(nm, "_(MEAN|UP|UPPER|LOW|LOWER)$") |> str_remove("_")
  list(
    ci = unname(.ci_aliases[token]),
    stem = if_else(is.na(token), nm, str_remove(nm, "_(MEAN|UP|UPPER|LOW|LOWER)$"))
  )
}

#' Does a column name look like a mortality value column?
#' @param parse Parsed names from [.split_mort_names()].
#' @return Logical vector.
#' @noRd
.is_mort_parsed <- function(parse) {
  !is.na(parse$age) & str_detect(parse$age, "[0-9]") & !is.na(parse$endpoint)
}

#' mortality (value) column names of a data.frame
#'
#' A mortality column is `\{endpoint\}_\{age\}`, optionally followed by a CI
#' suffix (`_MEAN`, `_UP`, `_LOW`).  Nothing else is treated as a value column.
#'
#' @param x A data.frame.
#' @return Character vector of value column names, in column order.
#' @noRd
.mort_names <- function(x) {
  parsed <- .split_mort_names(names(x))
  keep <- .is_mort_parsed(parsed) & !names(x) %in% .is_coord_cols(x)
  parsed$name[keep]
}

#' Resolve the `at` argument to a set of domain columns
#' @param x A data.frame (the first branch/input).
#' @param at `"grid"`, `"geo"`, or a character vector of column names.
#' @param value_cols Value columns to exclude from `at = "geo"` domains.
#' @param calc_fild Optional attribution field; when an explicit `at` names a
#'   column that only exists there, it is accepted (it is joined in later).
#' @return Character vector of domain columns (empty for `at = "grid"`).
#' @noRd
.resolve_at <- function(x, at, value_cols, calc_fild = NULL) {
  if (!is.character(at)) {
    .abort("`at` must be \"grid\", \"geo\", or a character vector of column names.")
  }
  if (identical(at, "grid")) {
    return(character(0))
  }
  if (identical(at, "geo")) {
    domain <- str_subset(
      names(x),
      regex("^x$|^y$|^lon|^lat", ignore_case = TRUE),
      negate = TRUE
    )
    return(setdiff(domain, value_cols))
  }
  if (anyNA(at) || any(at == "")) {
    .abort(str_c(
      "`at` must be \"grid\", \"geo\", or a character vector of column names. ",
      "Got: {paste(utils::capture.output(str(at)), collapse = \" \")}"
    ))
  }
  available <- union(names(x), if (is.data.frame(calc_fild)) names(calc_fild))
  missing_cols <- setdiff(at, available)
  if (length(missing_cols) > 0L) {
    .abort(str_c(
      "Domain column(s) not found in `x`: ",
      "{paste0(\"`\", missing_cols, \"`\") |> paste(collapse = \", \")}. Available columns: ",
      "{paste0(\"`\", names(x), \"`\") |> paste(collapse = \", \")}."
    ))
  }
  unique(at)
}

#' Normalize the `by` argument
#' @param by Character. `"total"`, `"endpoint"`, `"age"`, or `"all"`.
#' @return `character(0)` for `"total"`, the kept dimensions otherwise.
#' @noRd
.resolve_by <- function(by) {
  valid_by <- c("total", "endpoint", "age", "all")
  if (!is.character(by) || length(by) != 1L || !by %in% valid_by) {
    .abort(str_c(
      "`by` must be one of: \"{paste(valid_by, collapse = \"\\\", \\\"\")}\". ",
      "Got: {paste(utils::capture.output(str(by)), collapse = \" \")}"
    ))
  }
  switch(by,
    total = character(0),
    endpoint = "endpoint",
    age = "age",
    all = c("endpoint", "age")
  )
}

#' Aggregate one branch (one CI level, or the plain values) of one data.frame
#'
#' Restricts the sum to `names(value_cols)`, i.e. the explicitly listed
#' `\{endpoint\}_\{age\}` columns — never to "all numeric columns", so the grid
#' coordinates are never summed into the death counts.
#'
#' @param x A data.frame holding the value columns plus domain columns.
#' @param value_cols Named character vector: value column name → key suffix
#'   (e.g. `c("ncd+lri_25" = "ncd+lri_25")`), the same for every branch so that
#'   branches can be joined row by row afterwards.
#' @param domain Columns to group by (empty = no aggregation).
#' @param keys Dimensions kept in the output (`character(0)`, `"endpoint"`,
#'   `"age"`, or `c("endpoint", "age")`).
#' @param total_name Name of the all-endpoints × all-ages total column.
#' @param na_rm Logical. Drop `NA` when summing.
#' @param parse Parsed column names from [.split_mort_names()], one row per
#'   column of `x`.
#' @return A data.frame: domains, then the total column, then the kept margins.
#' @noRd
.aggregate_mortality_one <- function(x, value_cols, keep, domain, keys,
                                     total_name, na_rm, parse) {
  if (length(keep) != length(value_cols)) {
    .abort("Internal error: `keep` must have one flag per element of `value_cols`.")
  }
  value_cols <- value_cols[keep]
  if (length(value_cols) == 0L) {
    .abort("Internal error: no mortality columns selected for `{total_name}`.")
  }
  info <- parse[match(names(value_cols), parse$name), , drop = FALSE]

  if (length(domain) == 0L && length(keys) == 0L) {
    # at = "grid", by = "total": only append the total column.
    if (total_name %in% names(x)) {
      .abort(str_c(
        "Column `{total_name}` already exists in `x`; it would collide with ",
        "the aggregated total column. Rename it before aggregating."
      ))
    }
    return(
      x |>
        bind_cols(
          x |>
            transmute(
              "{total_name}" := rowSums(pick(all_of(names(value_cols))), na.rm = na_rm)
            )
        )
    )
  }

  domain <- unique(domain)
  margin_cols <- unique(c(domain, keys))
  if (total_name %in% names(x) && !total_name %in% margin_cols) {
    .abort(str_c(
      "Column `{total_name}` already exists in `x`; it would collide with ",
      "the aggregated total column. Rename it before aggregating."
    ))
  }

  # Long form: one row per (domain, endpoint, age).  Labels are attached before
  # summing, so every branch of a MEAN/UP/LOW run shares this exact key layout
  # and the branches can be joined row by row afterwards.
  long <- x |>
    select(all_of(unique(c(domain, names(value_cols))))) |>
    pivot_longer(
      cols = all_of(names(value_cols)),
      names_to = "column",
      values_to = "value"
    ) |>
    mutate(
      endpoint = info$endpoint[match(column, info$name)],
      age = info$age[match(column, info$name)],
      column = NULL
    )

  margin <- NULL
  if (length(keys) > 0L) {
    # Collapsed dimensions are labelled `all`, so an endpoint marginal is named
    # `{endpoint}_all` and an age marginal `all_{age}`.
    margin <- if (identical(keys, "endpoint")) {
      long |>
        summarise(
          value = sum(value, na.rm = na_rm),
          .by = all_of(unique(c(domain, "endpoint")))
        ) |>
        pivot_wider(
          names_from = "endpoint",
          names_glue = "{endpoint}_all",
          values_from = "value"
        )
    } else if (identical(keys, "age")) {
      long |>
        summarise(
          value = sum(value, na.rm = na_rm),
          .by = all_of(unique(c(domain, "age")))
        ) |>
        pivot_wider(
          names_from = "age",
          names_prefix = "all_",
          values_from = "value"
        )
    } else {
      long |>
        summarise(
          value = sum(value, na.rm = na_rm),
          .by = all_of(unique(c(domain, "endpoint", "age")))
        ) |>
        pivot_wider(
          names_from = all_of(keys),
          values_from = "value",
          names_sep = "_"
        )
    }
  }

  totals <- long |>
    summarise(value = sum(value, na.rm = na_rm), .by = all_of(domain)) |>
    rename_with(~total_name, "value")

  out <- if (is.null(margin)) totals else left_join(totals, margin, by = domain)
  if (length(domain) > 0L) {
    out <- out |> arrange(pick(all_of(domain)))
  }
  out
}

# ── aggregate_mortality ──────────────────────────────────────────────────

#' Aggregate grid-level attributable mortality by domain
#'
#' @description
#' Takes the wide grid-level output of [mortality()] — one row per grid cell,
#' one column per `\{endpoint\}_\{age\}` combination, plus the coordinate columns
#' (`x`/`y`) and any domain columns carried over from the attribution field —
#' and aggregates it to administrative domains.
#'
#' **Column-name convention.** A mortality column is named
#' `\{endpoint\}_\{age\}`, where the name is split at the **last** underscore: the
#' trailing token is the age group (`25`, `50`, `95`, ...) and everything before
#' it is the endpoint.  Endpoints may therefore contain further underscores,
#' dots or `+` without being mis-parsed (e.g. `ncd+lri_50` → endpoint `ncd+lri`,
#' age `50`; `copd_lri_v2_50` → endpoint `copd_lri_v2`, age `50`).  Columns whose
#' trailing token holds no digit are not mortality columns and are never summed.
#' Inputs already carrying a CI suffix (`_MEAN`, `_UP`, `_LOW`) are handled by
#' [aggregate_ci()].
#'
#' Only the explicitly listed `\{endpoint\}_\{age\}` columns are summed — the
#' coordinate columns are never part of the sum.
#'
#' @param x A data.frame from [mortality()], or a named list of them (one per
#'   scenario).  The name of each element is used as the `scenario` column of
#'   the corresponding output.
#' @param calc_fild Optional attribution field (a data.frame with `x`/`y` and
#'   the domain columns).  Supply it when `x` does not already carry the domain
#'   columns; it is joined by `x`/`y` when those are present in both, otherwise
#'   it is joined by the domain columns the two share.
#' @param at Aggregation level:
#'   * `"grid"` — no aggregation, one row per grid cell;
#'   * `"geo"` — group by every non-coordinate, non-value column present in `x`
#'     (i.e. every domain column of the attribution field);
#'   * a single column name, or a character vector of column names, to group by
#'     exactly those columns.
#' @param by Breakdown kept in the output:
#'   * `"total"` — sum over all endpoints and all age groups (`total` column);
#'   * `"endpoint"` — one column per endpoint (`\{endpoint\}_all`);
#'   * `"age"` — one column per age group (`all_\{age\}`);
#'   * `"all"` — both dimensions kept (`\{endpoint\}_\{age\}` columns).
#'
#'   For `by = "endpoint"` and `by = "age"` the all-endpoints × all-ages
#'   `total` column is returned alongside the marginals; for `by = "all"` the
#'   `\{endpoint\}_\{age\}` columns are returned alongside it.
#' @param na_rm Logical. Drop `NA` when summing (passed to `sum()` as
#'   `na.rm`). Default `TRUE`, matching [mortality()]'s use of `na.rm = TRUE`.
#'
#' @return A data.frame with the domain columns, a `total` column, the requested
#'   marginals, and a `scenario` column when `x` was a named list.
#'
#' @seealso [aggregate_ci()] for CI-branch (`mortality(ci = ...)`) output,
#'   [write_mortality_xlsx()] to write a result to a caller-supplied `path`.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Needs a mortality() result to post-process; see its examples.
#'   grid <- mortality(
#'     crf = "GEMM", calc_fild = grid_info,
#'     conc_real = .slice_conc(grid_exposure, "base2015"),
#'     pop_total = .slice_pop(grid_pop, "base2015"),
#'     age_struc = .slice_age(national_age_structure, "base2015"),
#'     mort_rate = .slice_mort(national_mortality, "base2015"),
#'     mort_lvl = "location"
#'   )
#'
#'   # one row per location, all endpoints and ages summed
#'   aggregate_mortality(grid, at = "location", by = "total")
#'
#'   # keep every domain column of the attribution field, break down by endpoint
#'   aggregate_mortality(grid, calc_fild = grid_info, at = "geo", by = "endpoint")
#'
#'   # keep both dimensions, several scenarios at once
#'   aggregate_mortality(
#'     list(base2015 = grid, SSP1_2030 = grid),
#'     at = "location", by = "all"
#'   )
#' }
aggregate_mortality <- function(x, calc_fild = NULL, at = "location",
                                by = "total", na_rm = TRUE) {
  inputs <- .as_named_inputs(x)

  if (!is.logical(na_rm) || length(na_rm) != 1L || is.na(na_rm)) {
    .abort("`na_rm` must be TRUE or FALSE.")
  }

  value_names <- .mort_names(inputs[[1L]])
  ci_suffixed <- !is.na(.split_ci_suffix(value_names)$ci)
  if (any(ci_suffixed)) {
    found_txt <- paste0("`", utils::head(value_names[ci_suffixed], 3L), "`") |>
      paste(collapse = ", ")
    .abort(str_c(
      "`x` mixes plain and CI-suffixed mortality columns (found {found_txt}). ",
      "Use aggregate_mortality() for plain output and aggregate_ci() for ",
      "`mortality(ci = ...)` output."
    ))
  }
  if (length(value_names) == 0L) {
    .abort(str_c(
      "No endpoints x age columns found in `x`. Expected columns named ",
      "`{{endpoint}}_{{age}}` (e.g. `ncd+lri_50`, `ihd_25`). A result carrying CI ",
      "suffixes (`_MEAN`, `_UP`, `_LOW`) must be passed to aggregate_ci()."
    ))
  }

  value_cols <- set_names(value_names)
  domain <- .resolve_at(inputs[[1L]], at, value_names, calc_fild = calc_fild)
  keys <- .resolve_by(by)

  out <- inputs |>
    map(function(result) {
      result <- .join_calc_fild(result, calc_fild, domain)
      .aggregate_mortality_one(
        x = result, value_cols = value_cols,
        keep = rep(TRUE, length(value_cols)),
        domain = domain, keys = keys,
        total_name = "total", na_rm = na_rm,
        parse = .split_mort_names(names(result))
      )
    })

  .attach_scenario(out, names(inputs))
}

# ── aggregate_ci ─────────────────────────────────────────────────────────

#' Aggregate mortality() output carrying CI branches
#'
#' @description
#' Accepts a mortality result whose columns are named `\{endpoint\}_\{age\}_\{CI\}`
#' with `ci` in `MEAN`/`UP`/`LOW` — the three CI branches of [mortality()]
#' sitting side by side in the same data.frame — and aggregates each branch
#' independently by domain.  Every row of the result keeps the three branches
#' together, as `total_MEAN` / `total_UP` / `total_LOW` (and
#' `\{endpoint\}_all_MEAN` / `..._UP` / `..._LOW`, etc., for `by = "endpoint"`
#' or `by = "age"`).
#'
#' [mortality()] itself does not append the `ci` suffix, so build the input by
#' running it once per branch and pasting the suffix on, e.g.
#' `paste0(names(x), "_MEAN")` for the `ci = "MEAN"` run.  `_UPPER` / `_LOWER`
#' (the names [mortality()] uses for its `ci` argument) are accepted as aliases
#' and normalized to `_UP` / `_LOW` in the output.
#'
#' The column-name convention is the one described in [aggregate_mortality()],
#' extended by a trailing CI token: the name is split at the **last** underscore
#' for the CI token, and at the last underscore of what remains for the age
#' group, so `ncd+lri_50_UP` → endpoint `ncd+lri`, age `50`, CI `UP`.
#'
#' @param x A data.frame with CI-suffixed columns, or a named list of them
#'   (one per scenario).
#' @param calc_fild Optional attribution field; see [aggregate_mortality()].
#' @param at Aggregation level; see [aggregate_mortality()].
#' @param by Breakdown kept in the output; `"total"`, `"endpoint"`, `"age"`, or
#'   `"all"`. Marginals are suffixed with the CI level, not combined with it.
#'
#' @return A data.frame with the domain columns, the total triplet
#'   (`total_MEAN`, `total_UP`, `total_LOW`) side by side, the requested
#'   marginals, and a `scenario` column when `x` was a named list.
#'
#' @seealso [aggregate_mortality()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Needs the three CI-suffixed tables built by three mortality() runs.
#'   run <- function(ci) mortality(
#'     crf = "GEMM", ci = ci, calc_fild = grid_info,
#'     conc_real = .slice_conc(grid_exposure, "base2015"),
#'     pop_total = .slice_pop(grid_pop, "base2015"),
#'     age_struc = .slice_age(national_age_structure, "base2015"),
#'     mort_rate = .slice_mort(national_mortality, "base2015"),
#'     mort_lvl = "location"
#'   )
#'
#'   # mortality() does not add the CI suffix — paste it on per branch
#'   mean_ <- run("MEAN"); up <- run("UPPER"); low <- run("LOWER")
#'   vals <- setdiff(names(mean_), c("x", "y", "location"))
#'   names(mean_)[names(mean_) %in% vals] <- paste0(vals, "_MEAN")
#'   names(up)[names(up) %in% vals] <- paste0(vals, "_UP")
#'   names(low)[names(low) %in% vals] <- paste0(vals, "_LOW")
#'   grid_ci <- mean_ |> left_join(up, by = c("x", "y", "location")) |>
#'     left_join(low, by = c("x", "y", "location"))
#'
#'   # one row per location, MEAN/UP/LOW side by side
#'   aggregate_ci(grid_ci, at = "location", by = "total")
#'
#'   # keep the endpoint breakdown
#'   aggregate_ci(grid_ci, at = "location", by = "endpoint")
#' }
aggregate_ci <- function(x, calc_fild = NULL, at = "location", by = "total") {
  inputs <- .as_named_inputs(x)
  parse <- .split_mort_names(names(inputs[[1L]]))

  ci_cols <- parse$name[!is.na(parse$ci)]
  if (length(ci_cols) == 0L) {
    .abort(str_c(
      "No CI-suffixed columns found in `x`. aggregate_ci() expects columns ",
      "named `{{endpoint}}_{{age}}_{{CI}}` with CI in MEAN/UP/LOW ",
      "(`_UPPER`/`_LOWER` are accepted aliases), i.e. the MEAN, UP and LOW ",
      "runs of mortality() side by side. For plain `{{endpoint}}_{{age}}` output ",
      "use aggregate_mortality()."
    ))
  }

  found <- unique(parse$ci[!is.na(parse$ci)])
  missing_ci <- setdiff(.ci_branches, found)
  if (length(missing_ci) > 0L) {
    .abort(str_c(
      "Incomplete CI triplet in `x`: found {paste(found, collapse = \", \")} ",
      "but missing {paste(missing_ci, collapse = \", \")}. aggregate_ci() needs MEAN, ",
      "UP and LOW side by side."
    ))
  }

  unparsed <- ci_cols[is.na(parse$endpoint[match(ci_cols, parse$name)])]
  if (length(unparsed) > 0L) {
    .abort(str_c(
      "Cannot parse CI column name(s): ",
      "{paste0(\"`\", unparsed, \"`\") |> paste(collapse = \", \")}. ",
      "Expected `{{endpoint}}_{{age}}_{{CI}}`."
    ))
  }

  value_cols <- set_names(ci_cols)
  domain <- .resolve_at(inputs[[1L]], at, ci_cols, calc_fild = calc_fild)
  keys <- .resolve_by(by)

  out <- inputs |>
    map(function(result) {
      result <- .join_calc_fild(result, calc_fild, domain)
      result_parse <- .split_mort_names(names(result))
      # aliases are normalized, so `_UPPER`/`_LOWER` inputs still produce the
      # canonical `total_UP` / `total_LOW` output columns
      col_branch <- set_names(
        result_parse$ci[match(ci_cols, result_parse$name)], ci_cols
      )

      branches <- .ci_branches |>
        map(function(ci) {
          branch <- .aggregate_mortality_one(
            x = result, value_cols = value_cols, keep = col_branch == ci,
            domain = domain, keys = keys,
            total_name = "total", na_rm = TRUE, parse = result_parse
          )
          # suffix every value column — total as well as the marginals — with
          # the branch label, so the three branches never collide on a name
          values <- setdiff(names(branch), c(domain, keys))
          branch |>
            rename_with(~paste0(.x, "_", ci), all_of(values))
        })

      # Branches share domain + margin columns; join on those, not the values.
      # The margin columns carry the CI suffix too (`all_25_MEAN`, ...), so the
      # join keys are read back from the MEAN branch rather than reconstructed.
      key_cols <- str_remove(names(branches[[1L]]), "_MEAN$") |>
        intersect(names(branches[[1L]]))
      merged <- if (length(key_cols) == 0L) {
        # at = "grid": nothing to join on — the three branches are row-aligned
        branches |> reduce(function(acc, nxt) bind_cols(acc, nxt))
      } else {
        branches |> reduce(function(acc, nxt) full_join(acc, nxt, by = key_cols))
      }
      merged |>
        relocate(
          all_of(paste0("total_", c("MEAN", "UP", "LOW"))),
          .after = all_of(utils::tail(domain, 1L))
        )
    })

  .attach_scenario(out, names(inputs))
}

# ── shared plumbing ──────────────────────────────────────────────────────

#' Coerce `x` to a named list of data.frames
#' @param x A data.frame or a named list of data.frames.
#' @return A named list (a bare data.frame becomes `list(scenario = x)`).
#' @noRd
.as_named_inputs <- function(x) {
  if (is.data.frame(x)) {
    return(list(scenario = x))
  }
  if (!is.list(x) || length(x) == 0L) {
    .abort(str_c(
      "`x` must be a data.frame or a non-empty named list of data.frames. Got: ",
      "{class(x)[1L]}"
    ))
  }
  bad <- !map_lgl(x, is.data.frame)
  if (any(bad)) {
    .abort(str_c(
      "Every element of `x` must be a data.frame. Not a data.frame: ",
      "{paste0(\"`\", names(x)[bad], \"`\") |> paste(collapse = \", \")}"
    ))
  }
  if (is.null(names(x)) || any(names(x) == "")) {
    .abort(str_c(
      "`x` must be a NAMED list. Name each element (e.g. with `set_names()` or ",
      "`list(base2015 = ..., SSP1_2030 = ...)`)."
    ))
  }
  x
}

#' Join the attribution field into a grid-level result when it is needed
#'
#' @param result A grid-level result.
#' @param calc_fild The attribution field, or `NULL`.
#' @param domain Domain columns required by the aggregation.
#' @return `result`, with the missing domain columns added from `calc_fild`.
#' @noRd
.join_calc_fild <- function(result, calc_fild, domain) {
  if (is.null(calc_fild) || all(domain %in% names(result))) {
    return(result)
  }
  if (!is.data.frame(calc_fild)) {
    .abort("`calc_fild` must be a data.frame or NULL.")
  }

  # Coordinates first: `result` is one row per grid cell, so joining it on a
  # coarser domain column copies a whole domain's rows onto every cell of it
  # (two cells, two provinces, both provinces get the national total). A domain
  # join is only used when there is no full coordinate pair to match on, i.e.
  # for a result that is already domain-level.
  coords_r <- .is_coord_cols(result)
  coords_c <- .is_coord_cols(calc_fild)
  shared <- if (length(coords_r) > 0 && length(coords_r) == length(coords_c)) {
    intersect(coords_r, coords_c)
  } else {
    character(0)
  }
  if (length(shared) == 0L) {
    shared <- intersect(
      setdiff(names(result), c(.mort_names(result), coords_r)),
      setdiff(names(calc_fild), coords_c)
    )
  }
  if (length(shared) == 0L) {
    .abort(str_c(
      "Cannot join `calc_fild` to `x`: no shared domain or coordinate column. ",
      "`x` has ",
      "{paste0(\"`\", names(result), \"`\") |> paste(collapse = \", \")}; ",
      "`calc_fild` has ",
      "{paste0(\"`\", names(calc_fild), \"`\") |> paste(collapse = \", \")}."
    ))
  }

  # A skeleton that repeats a key would multiply the result rows, which is a
  # data fault rather than something to average away.
  dup <- sum(duplicated(calc_fild[shared]))
  if (dup > 0L) {
    .abort(str_c(
      "`calc_fild` is not unique on the join key(s) ",
      "{paste0(\"`\", shared, \"`\") |> paste(collapse = \", \")}: ",
      dup, " duplicated row(s). A repeated key would multiply the result."
    ))
  }

  joined <- left_join(result, calc_fild, by = shared)
  still_missing <- setdiff(domain, names(joined))
  if (length(still_missing) > 0L) {
    .abort(str_c(
      "Domain column(s) ",
      "{paste0(\"`\", still_missing, \"`\") |> paste(collapse = \", \")}",
      " are absent from both `x` and `calc_fild`."
    ))
  }
  joined
}

#' Tag a list of aggregated data.frames with their scenario names
#' @param out A list of data.frames.
#' @param nms Scenario names.
#' @return A single data.frame with a leading `scenario` column when there is
#'   more than one scenario, or the bare data.frame otherwise.
#' @noRd
.attach_scenario <- function(out, nms) {
  if (length(out) == 1L) {
    return(out[[1L]])
  }
  out |>
    imap(function(result, nm) mutate(result, scenario = nm, .before = 1L)) |>
    bind_rows()
}

# ── export helper ────────────────────────────────────────────────────────

#' Write mortality results to an xlsx workbook
#'
#' Writes a single data.frame, or a named list of data.frames (one sheet per
#' element), with `writexl::write_xlsx()`. `writexl` is a `Suggests`
#' dependency, so the call is guarded by `requireNamespace()` and fails with an
#' actionable message when the package is absent.
#'
#' Where the file goes is always the caller's decision: `path` is either the
#' full file path (an `.xlsx` extension is added when missing), or an existing
#' directory together with an explicit `suffix` naming the file. No output file
#' name is ever invented by the package.
#'
#' @param results A data.frame, or a named list of data.frames.
#' @param path Character. Full output file path, or an existing directory when
#'   `suffix` is given.
#' @param suffix Optional character. File name without extension, created
#'   inside the directory `path`.
#'
#' @return The normalized output path, invisibly.
#' @export
#'
#' @seealso [aggregate_mortality()], [aggregate_ci()]
#'
#' @examples
#' \dontrun{
#' Writes files, so it is not run by R CMD check.
#'   out <- data.frame(location = "A", total = 1)
#'   write_mortality_xlsx(out, path = "location_total_260930.xlsx")
#'   write_mortality_xlsx(out, path = "output", suffix = "location_total_260930")
#' }
write_mortality_xlsx <- function(results, path, suffix = NULL) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    .abort(
      str_c(
        "Writing xlsx output requires the `writexl` package, which is not ",
        "installed (it is a Suggests dependency of AttrMort).\n",
        "Install it with install.packages(\"writexl\"), or pass the path to ",
        "another writer (e.g. openxlsx::write.xlsx())."
      )
    )
  }

  if (is.data.frame(results)) {
    results <- list(Sheet1 = results)
  }
  if (!is.list(results) || length(results) == 0L ||
    !all(map_lgl(results, is.data.frame))) {
    .abort(
      str_c(
        "`results` must be a data.frame or a non-empty list of data.frames. Got: ",
        "{class(results)[1L]}"
      )
    )
  }
  if (is.null(names(results)) || any(names(results) == "")) {
    names(results) <- paste0("Sheet", seq_along(results))
  }
  names(results) <- str_sub(names(results), 1L, 31L)

  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    .abort(
      "`path` must be a single character file or directory path."
    )
  }
  if (!is.null(suffix)) {
    if (!is.character(suffix) || length(suffix) != 1L || is.na(suffix) || !nzchar(suffix)) {
      .abort(
        "`suffix` must be NULL or a non-empty file name without extension."
      )
    }
    path <- file.path(path, paste0(suffix, ".xlsx"))
  } else if (dir.exists(path) || str_ends(path, regex("[/\\\\]$"))) {
    .abort(
      str_c(
        "`path` is a directory: pass the full file path, or name the file with ",
        "`suffix =`."
      )
    )
  }
  if (!str_detect(tolower(path), "\\.xlsx$")) {
    path <- paste0(path, ".xlsx")
  }
  if (!dir.exists(dirname(path))) {
    .abort(
      str_c(
        "Output directory does not exist: ",
        "{dirname(path)}. Create it first, or pass a path inside an existing directory."
      )
    )
  }

  writexl::write_xlsx(results, path = path)
  invisible(path)
}
