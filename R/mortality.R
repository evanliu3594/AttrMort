# ── Core: attributable mortality ────────────────────────────────────────
#
# mortality() orchestrates: spatial alignment -> ingestion -> column
# mapping -> admin join -> scenario extraction -> validation -> computation.
# The computation itself lives in .calc_attributable() and is deliberately
# free of I/O so that it can be reasoned about on its own.

# Value columns each input must provide, after column mapping.
.REQUIRED_VALUE_COLS <- list(
  conc_real = "conc",
  conc_cf   = "conc",
  pop_total = "pop",
  age_struc = c("age", "prop"),
  mort_rate = c("age", "endpoint", "mortrate")
)

# Age keys are joined as characters; numeric age columns are rounded to
# whole years first so that user-supplied tables join against the lookup
# tables regardless of how ages were stored.
.standardize_age_key <- function(x) {
  if (is.numeric(x)) matchable(x, dgt = 0) else as.character(x)
}

# Every input must carry its value columns and share at least one join key
# with calc_fild. All problems are reported at once, then the call aborts.
.check_inputs <- function(datasets, calc_fild, group = NULL) {
  key_cols <- names(calc_fild)
  problems <- character(0)

  for (nm in names(datasets)) {
    ds <- datasets[[nm]]
    if (is.null(ds)) {
      next
    }
    # `nm` selects the required columns, the label only names the dataset in
    # the message: `decompose()` checks two groups of the same roles.
    what <- if (is.null(group)) nm else str_c(nm, " (", group, ")")

    missing_val <- setdiff(.REQUIRED_VALUE_COLS[[nm]], names(ds))
    if (length(missing_val) > 0) {
      problems <- c(problems, sprintf(
        "`%s` is missing required column(s): %s.",
        what, paste0("`", missing_val, "`", collapse = ", ")
      ))
    }
    if (length(intersect(names(ds), key_cols)) == 0) {
      problems <- c(problems, sprintf(
        "`%s` shares no join key with `calc_fild` (keys available: %s; `%s` has: %s).",
        what, paste0("`", key_cols, "`", collapse = ", "), what,
        paste0("`", names(ds), "`", collapse = ", ")
      ))
    }
  }

  if (length(problems) > 0) {
    # A skeleton holding nothing but coordinates cannot carry the domain-keyed
    # inputs (`age_struc`, `mort_rate`), which is what a raster-only call
    # without boundaries runs into: say what to add rather than only what is
    # missing.
    hint <- if (all(key_cols %in% c("x", "y", "lon", "lat"))) {
      paste0(
        "\n  `calc_fild` carries coordinate keys only, so the domain-keyed ",
        "inputs cannot be attached to the grid. Pass `admin =` (a shapefile ",
        "path or an sf object) to rasterize domains onto it, or supply a ",
        "`calc_fild` that carries a domain column."
      )
    } else {
      ""
    }
    problems_txt <- paste(problems, collapse = "\n  - ")
    .abort("Invalid input data:\n  - {problems_txt}{hint}")
  }
  invisible(TRUE)
}

# Coordinate keys of a gridded data.frame, one "x y" string per cell; NULL
# when the table carries no coordinate pair to key on.
.grid_keys <- function(grid) {
  if (!is.data.frame(grid)) {
    return(NULL)
  }
  xy <- .grid_xy(grid)
  if (length(xy) != 2) {
    return(NULL)
  }
  unique(paste(grid[[xy[1]]], grid[[xy[2]]]))
}


# ── the grain of the run, said out loud ─────────────────────────────────
#
# mortality() is grain-agnostic: `calc_fild` decides whether the analysis is
# one row per grid cell or one row per domain, and `mort_lvl` decides whether
# the relative risks are calibrated inside a domain. Neither is readable from
# the arguments, and the two grains are not numerically identical -- a grid
# run takes the population-weighted mean of the relative risks of a domain's
# cells, a domain-only run takes the relative risk at the domain's
# population-weighted mean concentration (a Jensen gap, see
# the caller guess. One line per run keeps that visible instead of letting
# the grain be dispatched silently. `validate = "off"` is the quiet mode and
# prints nothing at all.

# Resolution of the analysis grid, in degrees: the aligned raster when one
# defines the grid, otherwise the spacing of the tabular cell centres. One
# number for a square grid, c(res_x, res_y) for a non-square one. NA when
# there is nothing to measure.
.grain_res <- function(calc_fild, template = NULL) {
  if (!is.null(template)) {
    return(.as_res(terra::res(template)))
  }
  xy <- .grid_xy(calc_fild)
  if (length(xy) != 2) {
    return(NA_real_)
  }
  .grid_georef(calc_fild[[xy[1]]], calc_fild[[xy[2]]])$res
}

# The `Analysis grain:` line for one run. Pure string assembly: the skeleton
# says where the analysis lives, the `mort_lvl` branch says how the relative
# risks are calibrated.
.grain_message <- function(calc_fild, mort_lvl, mort_rate, res = NA_real_) {
  n     <- nrow(calc_fild)
  dcol  <- .domain_col_of(calc_fild, mort_lvl)
  ndom  <- if (is.null(dcol)) NA_integer_ else length(unique(calc_fild[[dcol]]))
  # One row per domain: PWRR has nothing to average over, it *is* the
  # relative risk at that row's concentration.
  domain_grain <- !is.null(dcol) && n == ndom

  where <- if (domain_grain) {
    paste0(ndom, " domain(s) with one row each")
  } else if (!is.null(dcol)) {
    res_txt <- if (all(is.finite(res)) && length(res) > 0) {
      paste0(" on a ", .fmt_res(res), " deg grid")
    } else {
      ""
    }
    paste0(n, " cell(s) in ", ndom, " domain(s)", res_txt)
  } else {
    paste0(n, " cell(s) with no domain column")
  }

  branch <- if (is.null(mort_lvl)) {
    if (domain_grain) {
      "domain-level PAF without calibration."
    } else {
      "grid-level PAF without calibration."
    }
  } else if (mort_lvl %in% names(mort_rate)) {
    if (domain_grain) {
      paste0("PWRR reduces to a single RR evaluation per domain ",
             "(domain-level burden).")
    } else {
      "PWRR calibrated per domain."
    }
  } else {
    paste0("PWRR calibrated on the whole field (`mort_lvl` is not a column ",
           "of `mort_rate`).")
  }

  paste0("Analysis grain: ", where, "; ", branch)
}

#' Calculate attributable mortality
#'
#' @description
#' Estimates the number of deaths attributable to a change in exposure,
#' given population size, age structure, cause-specific baseline mortality
#' and a concentration-response function.
#'
#' Each data argument accepts a **data.frame**, a **file path** (`.csv`,
#' `.txt`, `.xls`, `.xlsx`, `.tif`, `.tiff`) or, for the gridded inputs, an
#' aligned pair of rasters. File inputs are loaded and their columns are
#' mapped onto the canonical schema (`conc`, `pop`, `age`, `prop`,
#' `endpoint`, `mortrate`, `location`) automatically; unrecognised column
#' names are matched by [detect_columns()] heuristics.
#'
#' Raster inputs are aligned before any computation: `conc_real` defines the
#' spatial grid, `pop_total` is aggregated onto it, and `admin` is
#' rasterized onto it. See [align_to_target()] and [.resolve_target_res()]
#' for the resolution logic.
#'
#' @param crf Character. Concentration-response model name (see
#'   [cr_models()]; matched case-insensitively) or a data.frame with the
#'   same structure as [rr_std()] output (`conc`, `endpoint`, `age`, `RR`).
#' @param ci Character. Which RR table to use: `"MEAN"` (default), `"UP"` or
#'   `"LOW"`. `"UPPER"`/`"LOWER"` are accepted as aliases. Ignored when
#'   `crf` is a data.frame.
#' @param calc_fild Attribution field: the spatial/administrative skeleton
#'   that all other inputs are joined onto. A **spatial vector layer**
#'   (`sf`, or a path to a `.shp`/`.gpkg`/`.geojson`) is accepted as well:
#'   it is then the boundary source, its polygons label the cells of the
#'   exposure grid, and `admin_col` says which of its columns holds the
#'   names (the first character column is used, with a warning, when the
#'   name is not found).
#'   that all other inputs are joined onto. Must contain coordinate columns
#'   (`x`/`y`, `lon`/`lat`) and/or domain columns (`location`, `Country`,
#'   `province`, ...).
#'
#'   Optional whenever `conc_real` carries coordinates: for a **raster** (a
#'   file path or a `SpatRaster`) the grid comes from the raster itself, and
#'   for a **table** it is the exposure's own cells (`x`/`y`, one row per
#'   cell, reported in a message), so a run needs no separate attribution
#'   file. An exposure that has already been aggregated to domains has no
#'   coordinates to build a grid from and must be given `calc_fild`.
#'
#'   The skeleton built that way holds coordinates only. A run whose
#'   `mort_lvl` needs a domain column gets it from `admin` (boundaries are
#'   rasterized onto the grid, or matched to the cell centres of a table);
#'   without `admin` the domain-keyed inputs cannot be joined and the error
#'   says so.
#'
#'   When it is supplied next to a raster input its coordinate keys are checked
#'   against the raster grid (see `validate`): a skeleton that shares no
#'   coordinate key with that grid is an error, a partial overlap is a warning.
#'   [build_grid_info()] produces such a skeleton from the same inputs.
#' @param conc_real Real-world exposure data. Multi-band rasters and wide
#'   tables are treated as multi-scenario; see `scenario`.
#' @param conc_cf Counterfactual exposure. `NULL` (default) means zero
#'   additional burden above the counterfactual, i.e. `conc_real` is reused.
#' @param pop_total Population counts.
#' @param age_struc Population age structure: one row per domain and age
#'   group with the population proportion in `prop`.
#' @param mort_rate Cause-specific baseline mortality rate, in deaths per
#'   100,000 population.
#'   A `mort_lvl` that names no column of `mort_rate` falls back to the
#'   domain column `mort_rate` carries itself, with a warning; a `mort_rate`
#'   with no domain column at all calibrates the whole field as one unit, on
#'   the population-weighted mean relative risk of the field -- the
#'   counterfactual exposure does not enter that fallback.
#' @param mort_lvl Character. Domain column used to calibrate the
#'   population-weighted relative risk (PWRR), e.g. `"location"`. It must
#'   exist in both `calc_fild` and `mort_rate`. `NULL` skips calibration and
#'   computes at the finest available level.
#' @param scenario Character. Scenario (column or raster band) to extract
#'   from wide-format inputs (one value column per role). It is a per-input
#'   selector, not a contract across inputs:
#'   an input that does not carry the column is used as it is when it has its
#'   canonical column (`conc`, `pop`, `prop`, `mortrate`) or a single numeric
#'   value column. `NULL` uses the inputs as given. The package never judges
#'   whether the inputs belong to the same scenario or year.
#' @param admin Administrative boundaries: a shapefile path, an `sf` object,
#'   or `NULL`. When supplied it is rasterized onto the analysis grid and
#'   joined into `calc_fild`. When `NULL` no domain column is added — with one
#'   exception, which is detected from the inputs: a **raster** run whose
#'   `mort_lvl` is a column of `mort_rate` but not of `calc_fild` asks for
#'   domain calibration without supplying boundaries, so national boundaries
#'   are taken from `rnaturalearth::ne_countries(scale = 110)` and rasterized
#'   onto the grid. Passing `admin =` always overrides that level; tabular
#'   runs keep `admin = NULL` meaning "no domain column".
#' @param admin_col Character. Attribute column of `admin` holding the admin
#'   unit name. Renamed to `mort_lvl` when the two differ.
#' @param target_res Numeric. Target grid resolution in degrees: one number,
#'   or two for the x and y cell size of a non-square grid. `NULL` (default)
#'   auto-detects the finest input resolution: grids of up to 5e6 cells are
#'   confirmed silently, larger ones interactively, and in a non-interactive
#'   session a grid above 5e7 cells **falls back to 0.1 deg** with a message.
#'   Set `target_res` explicitly to pin the grid in scripted runs.
#' @param dgt_coord Integer. Decimal places used to render coordinate keys.
#'   Default 2.
#' @param dgt_conc Integer. Decimal places used to render exposure keys.
#'   Must match the precision of the lookup table. Default 1.
#' @param validate Character. `"warn"` (default) reports data problems as
#'   warnings, `"stop"` turns them into errors, `"off"` skips validation --
#'   including the grid-consistency check of a supplied `calc_fild`. That check
#'   treats zero coordinate keys in common with the raster grid as an error and
#'   a partial match as a warning; `"off"` disables it entirely. The
#'   `Analysis grain:` line every run prints is part of the same switch: it
#'   reports the grain the call resolved to and the branch `mort_lvl`
#'   selected, and `"off"` -- the quiet mode -- suppresses it.
#' @param aggregate `NULL` (default) returns the grid-level result. `TRUE`
#'   aggregates onto `mort_lvl`, and a character vector aggregates onto those
#'   columns of the result (e.g. `"location"`, or
#'   `c("location", "province")`).
#' @param aggregate_by Character. Which dimension to keep when aggregating:
#'   `"total"` (default, a single `total` column), `"endpoint"`, `"age"` or
#'   `"all"`. See [aggregate_mortality()].
#' @param uncertain Logical. Also evaluate the low/high concentration-response
#'   tables -- and, when `conc_uncert > 0`, a perturbed exposure -- and report
#'   the resulting `CI_LOW`/`CI_UP` next to the central estimate.
#'   Default `FALSE`.
#' @param conc_uncert Numeric. Relative exposure uncertainty **in percent**.
#'   When positive the analysis is repeated with every concentration scaled by
#'   `1 +/- conc_uncert / 100`, and the interval becomes the union of the CRF
#'   range and the exposure range. Default 0.
#' @param chunk_ages Integer. Number of age strata computed per pass. `NULL`
#'   (default) sizes the pass from the problem: ages are grouped so that one
#'   pass stays under roughly 2 GB, all ages in one pass while the estimate is
#'   small. Splitting by age is numerically exact — the population-weighted
#'   relative risk is computed per (domain, endpoint, age) and the per-cell
#'   burden is element-wise — and it is what keeps a 0.1 degree global run
#'   inside 32 GB. It applies to the central estimate and to the
#'   `uncertain`/`conc_uncert` chains alike.
#' @param cr_config Optional configuration from [cr_config()], or a path to a
#'   JSON config, used when `crf` is a model name. `NULL` (default) uses the
#'   shipped configuration. Ignored for a data.frame `crf`.
#'
#' @section Uncertainty:
#' The interval is a **range**, not a sampling interval. The same low/high
#' tables are applied to every grid cell and the per-cell burdens are summed,
#' so a CRF shared by all cells adds up linearly instead of averaging out --
#' the correct behaviour for one curve applied globally. With a single shared
#' parameter the quantiles of the total are exactly the total evaluated at the
#' parameter quantiles, which is what this computes. An earlier version
#' propagated first-order sensitivities as `sigma^2 = sum(Sensi^2)`; that
#' assumes independent perturbations per cell and shrinks the CRF term roughly
#' like `1/sqrt(n_cells)`, so it was removed.
#'
#' @return A data.frame. At grid level (`aggregate = NULL`) it carries the key
#'   columns plus one wide `\{endpoint\}_\{age\}` column per stratum; with
#'   `aggregate` it carries the aggregation columns and the aggregated value
#'   columns instead, plus `conc_pwe` (population-weighted exposure). With
#'   `uncertain = TRUE` two extra columns, `CI_LOW` and `CI_UP`, hold the
#'   range for each row total.
#'
#' @seealso [build_grid_info()],
#'   [decompose()], [aggregate_mortality()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Reads the shipped example workbooks and runs the whole pipeline.
#' extdata <- system.file("extdata", package = "AttrMort")
#' grid_info <- readxl::read_excel(file.path(extdata, "grid_info.xlsx"))
#' grid_exposure <- readxl::read_excel(file.path(extdata, "grid_exposure.xlsx"))
#' grid_pop  <- readxl::read_excel(file.path(extdata, "grid_pop.xlsx"))
#' national_age   <- readxl::read_excel(file.path(extdata, "national_age_structure.xlsx"))
#' national_mort  <- readxl::read_excel(file.path(extdata, "national_mortality.xlsx"))
#'
#' # Wide tables: extract one scenario by name
#' mortality(
#'   crf = "GEMM", calc_fild = grid_info, scenario = "base2015",
#'   conc_real = grid_exposure, pop_total = grid_pop,
#'   age_struc = national_age, mort_rate = national_mort, mort_lvl = "location"
#' )
#'
#' # File paths, one call
#' mortality(
#'   crf = "GEMM", scenario = "base2015",
#'   calc_fild = file.path(extdata, "grid_info.xlsx"),
#'   conc_real = "exposure.tif", pop_total = "population.tif",
#'   age_struc = file.path(extdata, "national_age_structure.xlsx"),
#'   mort_rate = file.path(extdata, "national_mortality.xlsx"),
#'   mort_lvl  = "location", admin = "boundaries.shp", admin_col = "NAME"
#' )
#' }
mortality <- function(
    crf,
    ci           = "MEAN",
    calc_fild    = NULL,
    conc_real,
    conc_cf      = NULL,
    pop_total,
    age_struc,
    mort_rate,
    mort_lvl     = NULL,
    scenario     = NULL,
    admin        = NULL,
    admin_col    = "admin",
    target_res   = NULL,
    dgt_coord    = 2,
    dgt_conc     = 1,
    validate     = c("warn", "stop", "off"),
    aggregate    = NULL,
    aggregate_by = "total",
    uncertain    = FALSE,
    conc_uncert  = 0,
    chunk_ages   = NULL,
    cr_config    = NULL
) {
  validate     <- match.arg(validate)
  aggregate_by <- match.arg(aggregate_by, c("total", "endpoint", "age", "all"))
  ci           <- .match_ci(ci)

  # Arguments first: a typo fails here, not after a long ingest.
  .check_mortality_args(aggregate, uncertain, conc_uncert, chunk_ages)

  # ── every input, prepared once ─────────────────────────────────────
  # ── every input, prepared once (see R/prepare-inputs.R) ────────────
  # `validate = "off"` means the run says nothing at all: it is not "less
  # checking" but "no reporting", so the whole preparation -- resolution,
  # column mapping, boundaries, the `calc_fild = NULL` note -- runs under a
  # silence guard. `mortality()` is an entry point, so this is where the
  # decision belongs; the stages below stay unaware of it.
  quiet     <- validate == "off"
  prep_args <- list(crf, calc_fild, conc_real, conc_cf, pop_total, age_struc,
                    mort_rate, scenario, admin, admin_col, target_res,
                    dgt_coord, dgt_conc, validate, cr_config, mort_lvl)
  prep      <- if (quiet) {
    suppressWarnings(suppressMessages(do.call(.prepare_inputs, prep_args)))
  } else {
    do.call(.prepare_inputs, prep_args)
  }
  calc_fild <- prep$calc_fild
  conc_real <- prep$conc_real
  conc_cf   <- prep$conc_cf
  pop_total <- prep$pop_total
  age_struc <- prep$age_struc
  mort_rate <- prep$mort_rate
  template  <- prep$template
  config    <- prep$config
  crf_name  <- prep$crf_name
  mort_lvl  <- prep$mort_lvl

  # ── data validation ────────────────────────────────────────────────
  if (validate != "off") {
    report <- validate_mortality_input(
      list(conc = conc_real, pop = pop_total, age_struc = age_struc,
           mort_rate = mort_rate),
      cr_model = crf_name,
      dgt_conc = dgt_conc,
      config   = config
    )
    if (!report$valid && validate == "stop") {
      issues_txt <- paste(report$issues, collapse = "\n  - ")
      .abort("Input validation failed:\n  - {issues_txt}")
    }
  }

  # ── join keys ──────────────────────────────────────────────────────
  .check_inputs(
    list(conc_real = conc_real, conc_cf = conc_cf, pop_total = pop_total,
         age_struc = age_struc, mort_rate = mort_rate),
    calc_fild
  )

  # ── the grain this call resolved to ────────────────────────────────
  # Report it before anything is computed, and exactly once per run: the
  # message belongs to mortality(), not to the age-chunked kernel, which is
  # entered several times for one run.
  if (validate != "off") {
    cli::cli_inform(.grain_message(calc_fild, mort_lvl, mort_rate,
                                   res = .grain_res(calc_fild, template)))
  }

  # ── central estimate, plus the range when requested ────────────────
  # Every branch -- central, CRF range and the conc_uncert chain -- goes
  # through the same age-chunked helper, so `chunk_ages` cannot change one of
  # them without the others. The branch notice belongs to the run, not to one
  # pass: only the first `compute()` reports it, so the uncertainty chains
  # stay quiet.
  compute <- function(ci, conc_r = conc_real, conc_c = conc_cf,
                      notify = FALSE) {
    .calc_attributable_ages(calc_fild, conc_r, conc_c, pop_total, age_struc,
                            mort_rate, mort_lvl, crf, ci, chunk_ages,
                            config = config, dgt_conc = dgt_conc,
                            notify = notify)
  }

  grid     <- compute(ci, notify = !quiet)
  key_cols <- intersect(names(calc_fild), names(grid))
  ranges   <- if (uncertain) {
    .uncertainty_frames(compute, key_cols, ci, conc_real, conc_cf,
                        conc_uncert, dgt_conc)
  }

  # ── optional domain aggregation ────────────────────────────────────
  if (!is.null(aggregate)) {
    at <- .aggregate_keys(aggregate, mort_lvl)
    return(.aggregate_result(grid, calc_fild, conc_real, pop_total, at,
                             aggregate_by, key_cols, ranges))
  }

  if (uncertain) {
    # `grid` is the key space every chain is expected to cover; aligning to it
    # is what keeps a chain that lost a cell from shifting the others.
    keys_frame  <- grid[key_cols]
    grid$CI_LOW <- .range_sum(ranges$lower, key_cols, "low",
                              aggregate = FALSE, keys_frame = keys_frame)
    grid$CI_UP  <- .range_sum(ranges$upper, key_cols, "up",
                              aggregate = FALSE, keys_frame = keys_frame)
  }
  grid
}

# ── Stages of mortality(), each one call in the orchestrator ────────────

# ── the stage both entry points share ───────────────────────────────────


# Argument checks that need no data. They all run before anything is read, so a
# typo fails on the spot rather than after a long ingest.
.check_mortality_args <- function(aggregate, uncertain, conc_uncert, chunk_ages) {
  if (!is.null(aggregate) && !isTRUE(aggregate) && !is.character(aggregate)) {
    .abort("`aggregate` must be NULL, TRUE, or a character vector of columns.")
  }
  if (!is.logical(uncertain) || length(uncertain) != 1 || is.na(uncertain)) {
    .abort("`uncertain` must be TRUE or FALSE.")
  }
  if (!is.numeric(conc_uncert) || length(conc_uncert) != 1 ||
      is.na(conc_uncert) || conc_uncert < 0) {
    .abort(str_c("`conc_uncert` is a percentage and must be a single ",
                 "non-negative number."))
  }
  if (!is.null(chunk_ages) &&
      (!is.numeric(chunk_ages) || length(chunk_ages) != 1 ||
         is.na(chunk_ages) || chunk_ages < 1)) {
    .abort(str_c("`chunk_ages` must be NULL or a single positive ",
                 "number of age strata per pass."))
  }
  invisible(NULL)
}




# The low and high sides of the reported range: the CR table quantiles, plus --
# when exposure uncertainty was asked for -- a second chain with every
# concentration scaled. `.range_sum()` reduces each side with pmin/pmax, so the
# range is the union of the two perturbations rather than their product.
.uncertainty_frames <- function(compute, key_cols, ci, conc_real, conc_cf,
                                conc_uncert, dgt_conc) {
  lower <- list(.total_frame(compute("LOW"), key_cols))
  upper <- list(.total_frame(compute("UP"), key_cols))
  if (conc_uncert <= 0) {
    return(list(lower = lower, upper = upper))
  }
  factors <- c(1 - conc_uncert / 100, 1 + conc_uncert / 100)
  shifted <- map(factors, function(factor) {
    .total_frame(
      compute(ci, .scale_conc(conc_real, factor, dgt_conc),
              .scale_conc(conc_cf, factor, dgt_conc)),
      key_cols
    )
  })
  list(lower = c(lower, shifted[1]), upper = c(upper, shifted[2]))
}

# Which columns the aggregate is grouped by: the calibration domains, or the
# whole field when the run is uncalibrated (`TRUE` with `mort_lvl = NULL`).
.aggregate_keys <- function(aggregate, mort_lvl) {
  if (!isTRUE(aggregate)) {
    return(aggregate)
  }
  if (!is.null(mort_lvl)) {
    return(mort_lvl)
  }
  cli::cli_inform(str_c(
    "`aggregate = TRUE` with `mort_lvl = NULL`: the whole field ",
    "is aggregated into a single row."
  ))
  character(0)
}

# The `aggregate = ` path: one row per group, that group's population-weighted
# exposure, and the range when one was asked for.
.aggregate_result <- function(grid, calc_fild, conc_real, pop_total, at,
                              aggregate_by, key_cols, ranges) {
  missing_cols <- setdiff(at, names(grid))
  if (length(missing_cols) > 0) {
    missing_txt <- paste(missing_cols, collapse = ", ")
    .abort("`aggregate` column(s) not found in the result: {missing_txt}.")
  }

  out <- if (length(at) == 0) {
    tibble(total = sum(.row_total(grid, key_cols)))
  } else {
    aggregate_mortality(grid, calc_fild = calc_fild, at = at,
                        by = aggregate_by)
  }

  pwe <- .domain_pwe(calc_fild, conc_real, pop_total, at)
  out <- if (length(at) == 0) {
    bind_cols(out, pwe)
  } else {
    left_join(out, pwe, by = at)
  }

  if (is.null(ranges)) {
    return(out)
  }
  .attach_range(out, ranges$lower, ranges$upper, at)
}

# ── age chunking ────────────────────────────────────────────────────────
#
# PWRR is computed per (domain, endpoint, age) and the per-cell burden is
# element-wise, so a subset of the age strata can be computed on its own and
# the resulting wide blocks joined back together without changing a number:
# the join only adds the columns of the other ages. The reason to do it at
# all is peak memory -- the intermediate long table grows like
# cells x ages x endpoints, which is what puts a 0.1 degree global run
# (6.5e6 cells x 15 ages) out of reach of 32 GB.

# Which branch .calc_attributable() takes on `mort_lvl`, expressed as the
# notice that goes with it (or NULL when there is nothing to say). The two
# branches are not equally surprising: `mort_lvl = NULL` is a documented mode
# -- the grid-level PAF, deliberately uncalibrated -- so it is only reported,
# while a `mort_lvl` that is not a column of `mort_rate` falls back to one
# field-wide calibration unit, which is worth a warning. Split out so that the
# age-chunked path and the uncertainty chains notify once per run rather than
# once per pass.
.mort_lvl_notice <- function(mort_lvl, mort_rate) {
  if (is.null(mort_lvl)) {
    return(list(
      kind = "info",
      text = paste0(
        "`mort_lvl` is NULL: the grid-level result is not calibrated ",
        "against `mort_rate`."
      )
    ))
  }
  if (mort_lvl %in% names(mort_rate)) {
    return(NULL)
  }
  list(
    kind = "warn",
    text = paste0(
      "`mort_lvl` is not a column of `mort_rate`: the whole field is treated ",
      "as one calibration unit."
    )
  )
}

# The age strata that can contribute anything: those present in both
# `mort_rate` and the concentration-response table. Any other age can only
# produce an empty join, so it is dropped before the chunking (which is also
# what keeps the chunks a partition of the ages that matter). Returned in
# increasing age order, so that consecutive groups are consecutive ages.
.chunkable_ages <- function(mort_rate, RR_tbl) {
  ages <- intersect(.standardize_age_key(mort_rate$age), unique(RR_tbl$age))
  ages[order(suppressWarnings(as.numeric(ages)), ages, na.last = TRUE)]
}

# Split `ages` into consecutive groups of at most `size` strata.
.split_ages <- function(ages, size) {
  starts <- seq.int(1L, length(ages), by = size)
  map(starts, function(s) ages[s:min(s + size - 1L, length(ages))])
}

# The `{endpoint}_{age}` value columns of `nm` whose age stratum is in `ages`,
# using the same parsing as .mort_names().
.age_value_columns <- function(nm, ages) {
  parsed <- .split_mort_names(nm)
  parsed$name[.is_mort_parsed(parsed) & parsed$age %in% ages]
}

# Put the value columns of an assembled result back into the order a single
# pass produces. Concatenating age blocks would otherwise sort them
# endpoint-minor (every endpoint of the first block, then every endpoint of
# the second, ...), while one pass emits them in the order of the CRF's
# (endpoint, age) pairs. The numbers do not depend on this; the columns of a
# chunked run simply read like the columns of an unchunked one.
.order_value_columns <- function(x, RR_tbl) {
  parsed <- .split_mort_names(names(x))
  value  <- .is_mort_parsed(parsed)
  if (sum(value) <= 1L) {
    return(x)
  }
  reference <- unique(paste(RR_tbl$endpoint, RR_tbl$age, sep = "_"))
  rank      <- match(paste(parsed$endpoint, parsed$age, sep = "_")[value],
                     reference)
  # strata the CRF does not list keep their relative order at the end
  ord       <- order(rank, seq_along(rank), na.last = TRUE)

  select(x, all_of(c(names(x)[!value], names(x)[value][ord])))
}

# Peak bytes of one pass: every double in the long table counts 8 bytes and
# the pipeline is assumed to hold about eight such vectors at once.
.chunk_peak_bytes <- function(n_cells, n_ages, n_endpoints,
                              bytes = 8, copies = 8) {
  as.numeric(n_cells) * n_ages * n_endpoints * bytes * copies
}

# Age strata per pass. An explicit `chunk_ages` is honoured (capped at the
# number of ages available); `NULL` sizes the pass from the problem -- the
# fewest passes that keep one pass under `budget`, i.e. a single pass while
# the estimate is small and one age at a time when even that is too big.
.resolve_chunk_ages <- function(chunk_ages, n_cells, n_ages, n_endpoints,
                                budget = 2 * 1024^3) {
  if (n_ages <= 1L) {
    return(n_ages)
  }
  if (!is.null(chunk_ages)) {
    return(min(as.integer(chunk_ages), n_ages))
  }
  n_passes <- 1L
  while (n_passes < n_ages &&
         .chunk_peak_bytes(n_cells, ceiling(n_ages / n_passes),
                           n_endpoints) > budget) {
    n_passes <- n_passes + 1L
  }
  as.integer(ceiling(n_ages / n_passes))
}

# .calc_attributable() over age blocks, joined back into one wide result.
#
# Each block carries the grid key columns plus its own `{endpoint}_{age}`
# columns. A cell can be absent from a block (no population for that age
# there), and it has to come back as NA rather than disappear, so the blocks
# are joined on the grid keys -- never cbind()ed.
.calc_attributable_ages <- function(calc_fild, conc_real, conc_cf, pop_total,
                                    age_struc, mort_rate, mort_lvl, crf, ci,
                                    chunk_ages = NULL, config = NULL,
                                    dgt_conc = 1, notify = FALSE) {
  # Resolve the model and build its RR table once: every age block below runs
  # the same lookup, so rebuilding it per block is pure repeated work.
  crf_label <- if (is.data.frame(crf)) {
    "user-supplied"
  } else {
    .match_cr_model(crf, config)
  }
  RR_tbl <- if (is.data.frame(crf)) {
    crf
  } else {
    rr_std(crf_label, ci, dgt = dgt_conc, config = config)
  }
  ages   <- .chunkable_ages(mort_rate, RR_tbl)

  if (length(ages) == 0) {
    # No shared age stratum: leave the report to .calc_attributable().
    return(.calc_attributable(calc_fild, conc_real, conc_cf, pop_total,
                              age_struc, mort_rate, mort_lvl, crf, ci,
                              warn = notify, config = config,
                              dgt_conc = dgt_conc,
                              RR_tbl = RR_tbl, crf_label = crf_label))
  }

  size   <- .resolve_chunk_ages(chunk_ages, nrow(calc_fild), length(ages),
                                length(unique(RR_tbl$endpoint)))
  blocks <- .split_ages(ages, size)

  # The branch notice is a property of the whole run, so only the first
  # block emits it; the blocks themselves are independent computations. An
  # empty block is allowed here and dropped below: a GBD age structure can
  # lack a stratum that the CRF and `mort_rate` both carry, and the
  # unchunked result simply has no column for it.
  parts <- map(seq_along(blocks), function(i) {
    block <- blocks[[i]]
    .calc_attributable(
      calc_fild, conc_real, conc_cf, pop_total,
      age_struc |> filter(.standardize_age_key(age) %in% block),
      mort_rate |> filter(.standardize_age_key(age) %in% block),
      mort_lvl, crf, ci, warn = notify && i == 1L, config = config,
      dgt_conc = dgt_conc, RR_tbl = RR_tbl, crf_label = crf_label,
      allow_empty = TRUE
    )
  })

  empty <- map_lgl(parts, function(part) nrow(part) == 0L)
  if (all(empty)) {
    # No block contributed a row. Fall through to the unchunked check so the
    # run reports the problem exactly as a single pass would, rather than
    # blaming the age chunking.
    return(.calc_attributable(
      calc_fild, conc_real, conc_cf, pop_total, age_struc, mort_rate,
      mort_lvl, crf, ci, warn = FALSE, config = config, dgt_conc = dgt_conc,
      RR_tbl = RR_tbl, crf_label = crf_label
    ))
  }
  parts  <- parts[!empty]
  blocks <- blocks[!empty]

  if (length(parts) == 1L) {
    return(parts[[1L]])
  }

  # Key columns come from the attribution field. The first block also carries
  # the incidental columns of the wide result (the per-cell `conc` of the
  # uncalibrated branch), which the later blocks must not duplicate.
  keys  <- intersect(names(calc_fild), names(parts[[1L]]))
  ages1 <- .age_value_columns(names(parts[[1L]]), ages)
  extra <- setdiff(names(parts[[1L]]), c(keys, ages1))

  # A block computes only its own ages, but the joins can widen the result to
  # every CRF age (the uncalibrated branch takes its age strata from the CRF
  # rather than from `mort_rate`), so each block is cut back to the ages it
  # was given before the blocks are joined. That is also what keeps the value
  # columns of the blocks disjoint, so the join appends rather than renames.
  parts <- map(seq_along(blocks), function(i) {
    keep <- .age_value_columns(names(parts[[i]]), blocks[[i]])
    select(parts[[i]],
           all_of(unique(c(keys, if (i == 1L) extra, keep))))
  })

  out <- reduce(parts, function(a, b) left_join(a, b, by = keys))
  .order_value_columns(out, RR_tbl)
}

# Core computation. Pure data-frame in / data-frame out: no file access, no
# raster handling, no column-name guessing. `warn` is FALSE only for the age
# blocks of .calc_attributable_ages(), which reports the branch warning once
# for the whole run. `allow_empty` makes an empty join return the (0-row, key
# carrying) table instead of aborting; the age-chunked caller uses it to drop
# blocks that cannot contribute, and still aborts when every block is empty.
# Deaths per 100,000: mortality rates are published in those units, while an
# attributable burden is a number of deaths.
.PER_100K <- 1e5

# One row per cell (or domain), one column per `{endpoint}_{age}` stratum: the
# shape every branch of the calculation returns.
.widen_mort <- function(x) {
  pivot_wider(
    x,
    names_from  = c("endpoint", "age"),
    names_sep   = "_",
    values_from = "attr_mort"
  )
}

# The CR table and its label. `.calc_attributable_ages()` passes both down so a
# chunked run does not rebuild the same lookup per age block; the defaults keep
# the kernel usable on its own.
.resolve_crf_tables <- function(crf, ci, config, dgt_conc, RR_tbl, crf_label) {
  if (is.null(crf_label)) {
    crf_label <- if (is.character(crf)) {
      .match_cr_model(crf, config)
    } else {
      "user-supplied"
    }
  }
  if (is.null(RR_tbl)) {
    RR_tbl <- if (is.data.frame(crf)) {
      crf
    } else {
      rr_std(crf_label, ci, dgt = dgt_conc, config = config)
    }
  }
  list(RR_tbl = RR_tbl, crf_label = crf_label)
}

# Out-of-range exposures simply never join the lookup key. Say how many values
# that affects instead of letting them disappear in drop_na(); `conc_real` and
# `conc_cf` are often the same table, so identical axes are reported once.
.warn_conc_out_of_range <- function(RR_tbl, conc_real, conc_cf) {
  if (nrow(RR_tbl) == 0) {
    return(invisible(NULL))
  }
  rng <- range(as.numeric(RR_tbl$conc), na.rm = TRUE)
  checked <- NULL
  for (nm in c("conc_real", "conc_cf")) {
    conc_tbl <- if (identical(nm, "conc_real")) conc_real else conc_cf
    if (!is.data.frame(conc_tbl) || !"conc" %in% names(conc_tbl)) {
      next
    }
    v <- suppressWarnings(as.numeric(conc_tbl$conc))
    if (!is.null(checked) && identical(v, checked)) {
      next
    }
    checked <- v
    n_out <- sum(!is.na(v) & (v < rng[1] | v > rng[2]))
    if (n_out > 0) {
      cli::cli_warn(str_c(
        n_out, " value(s) in `", nm, "` fall outside the CRF lookup range [",
        format(rng[1]), ", ", format(rng[2]),
        "] and are dropped by the join; they contribute nothing to the result."
      ))
    }
  }
  invisible(NULL)
}

# Endpoints and ages are joined as characters, so the user's tables have to
# speak the lookup tables' spellings.
.standardize_join_keys <- function(mort_rate, age_struc) {
  list(
    mort_rate = mort_rate |>
      mutate(endpoint = tolower(as.character(endpoint)),
             age      = .standardize_age_key(age)),
    age_struc = age_struc |>
      mutate(age = .standardize_age_key(age))
  )
}

# A CRF whose endpoints are absent from `mort_rate` can only produce an empty
# result: say so instead of returning zero rows.
.check_endpoint_overlap <- function(RR_tbl, mort_rate, crf_label) {
  ep_rr   <- unique(RR_tbl$endpoint)
  ep_mort <- unique(mort_rate$endpoint)
  if (length(intersect(ep_rr, ep_mort)) > 0) {
    return(invisible(NULL))
  }
  # Everything that comes from the data is interpolated as a value, never
  # concatenated into the template: cli evaluates whatever sits between braces
  # in a message, so an endpoint literally called `{1+1}` would be executed.
  label_txt   <- crf_label
  ep_rr_txt   <- paste(sort(ep_rr), collapse = ", ")
  ep_mort_txt <- paste(head(sort(ep_mort), 20), collapse = ", ")
  .abort(paste0(
    "No shared disease endpoint between CRF \"{label_txt}\" and `mort_rate`.\n",
    "  CRF endpoints   : {ep_rr_txt}\n",
    "  mort_rate values: {ep_mort_txt}"
  ))
}

# The one-unit fallback is reached only when `mort_rate` carries no domain at
# all (`.resolve_mort_lvl()` reports that). Its risk term is the population
# weighted mean RR of the field rather than the counterfactual exposure, which
# is what `mortality()` reports when `mort_lvl` names a column neither table
# has: the exposure data is not there to be attributed cell by cell.
#
# Which branch the run took is a property of the run, not a fault: say it once,
# and as a warning only when it is actually surprising (`.mort_lvl_notice()`).
.notify_mort_lvl <- function(mort_lvl, mort_rate) {
  branch_msg <- .mort_lvl_notice(mort_lvl, mort_rate)
  if (is.null(branch_msg)) {
    return(invisible(NULL))
  }
  if (identical(branch_msg$kind, "warn")) {
    cli::cli_warn(branch_msg$text)
  } else {
    cli::cli_inform(branch_msg$text)
  }
  invisible(NULL)
}

# PWRR per (domain, endpoint, age): the population-weighted mean relative risk
# of the real exposure, which is what makes the domain the calibration unit.
.pwrr_by_domain <- function(calc_fild, conc_real, pop_total, RR_tbl, mort_lvl) {
  list(calc_fild, conc_real, pop_total, RR_tbl) |>
    reduce(.left_join_common) |>
    drop_na() |>
    group_by(pick(all_of(mort_lvl)), endpoint, age) |>
    summarise(PWRR = weighted.mean(RR, pop, na.rm = TRUE)) |>
    ungroup()
}

# Branch 1 -- `mort_lvl = NULL`: the grid-level PAF, the risk term RR(conc_real)
# applied cell by cell with no calibration.
.attributable_grid <- function(calc_fild, conc_real, RR_tbl, age_struc,
                               mort_rate, pop_total) {
  list(calc_fild, conc_real, RR_tbl, age_struc, mort_rate, pop_total) |>
    reduce(.left_join_common) |>
    mutate(mort_base = pop * prop * mortrate, .keep = "unused") |>
    mutate(attr_mort = mort_base * (RR - 1) / RR / .PER_100K, .keep = "unused") |>
    .widen_mort()
}

# Branch 2 -- `mort_lvl` names a column of `mort_rate`: the domain is the
# calibration unit, so the risk term uses the counterfactual exposure `conc_cf`
# while the calibration uses the real one.
.attributable_by_domain <- function(calc_fild, conc_real, conc_cf, pop_total,
                                    RR_tbl, age_struc, mort_rate, mort_lvl) {
  pwrr <- .pwrr_by_domain(calc_fild, conc_real, pop_total, RR_tbl, mort_lvl)

  list(calc_fild, conc_cf, pop_total, RR_tbl, mort_rate, age_struc, pwrr) |>
    reduce(.left_join_common) |>
    select(-conc) |>
    drop_na() |>
    mutate(mort_base = pop * prop * mortrate, .keep = "unused") |>
    mutate(attr_mort = mort_base * (RR - 1) / PWRR / .PER_100K, .keep = "unused") |>
    .widen_mort()
}

# Branch 3 -- `mort_lvl` is not a column of `mort_rate`: the whole field is one
# calibration unit, so the burden is aggregated to (endpoint, age) before the
# ratio and the PWRR is field-wide.
.attributable_one_field <- function(calc_fild, conc_real, pop_total, RR_tbl,
                                    age_struc, mort_rate) {
  pwrr <- list(calc_fild, conc_real, pop_total, RR_tbl) |>
    reduce(.left_join_common) |>
    drop_na() |>
    group_by(endpoint, age) |>
    summarise(PWRR = weighted.mean(RR, pop, na.rm = TRUE)) |>
    ungroup()

  list(calc_fild, pop_total, mort_rate, age_struc) |>
    reduce(.left_join_common) |>
    group_by(endpoint, age) |>
    summarise(mort_base = sum(pop * prop * mortrate / .PER_100K,
                              na.rm = TRUE)) |>
    ungroup() |>
    .left_join_common(pwrr) |>
    drop_na() |>
    mutate(attr_mort = mort_base * (1 - 1 / PWRR), .keep = "unused") |>
    .widen_mort()
}

.calc_attributable <- function(calc_fild, conc_real, conc_cf, pop_total,
                               age_struc, mort_rate, mort_lvl, crf, ci,
                               warn = TRUE, config = NULL, dgt_conc = 1,
                               RR_tbl = NULL, crf_label = NULL,
                               allow_empty = FALSE) {
  tables <- .resolve_crf_tables(crf, ci, config, dgt_conc, RR_tbl, crf_label)
  RR_tbl     <- tables$RR_tbl
  crf_label  <- tables$crf_label

  if (warn) {
    .warn_conc_out_of_range(RR_tbl, conc_real, conc_cf)
  }

  keys       <- .standardize_join_keys(mort_rate, age_struc)
  mort_rate  <- keys$mort_rate
  age_struc  <- keys$age_struc

  .check_endpoint_overlap(RR_tbl, mort_rate, crf_label)
  if (warn) {
    .notify_mort_lvl(mort_lvl, mort_rate)
  }

  out <- if (is.null(mort_lvl)) {
    .attributable_grid(calc_fild, conc_real, RR_tbl, age_struc, mort_rate,
                       pop_total)
  } else if (mort_lvl %in% names(mort_rate)) {
    .attributable_by_domain(calc_fild, conc_real, conc_cf, pop_total, RR_tbl,
                            age_struc, mort_rate, mort_lvl)
  } else {
    .attributable_one_field(calc_fild, conc_real, pop_total, RR_tbl,
                            age_struc, mort_rate)
  }

  if (nrow(out) == 0) {
    if (allow_empty) {
      return(out)
    }
    # interpolated, not concatenated: see `.check_endpoint_overlap()`
    age_txt <- paste(head(sort(unique(RR_tbl$age)), 5), collapse = ", ")
    .abort(paste0(
      "No rows survived the join between the inputs and the ",
      "concentration-response table. Check that `mort_rate` covers the same ",
      "domains and age groups as `calc_fild`, and that `age` values match ",
      "the CRF age strata (e.g. {age_txt}, ...)."
    ))
  }

  out
}
