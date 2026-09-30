# ── Core: attributable mortality ────────────────────────────────────────
#
# Mortality() orchestrates: spatial alignment -> ingestion -> column
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
.check_inputs <- function(datasets, calc_fild) {
  key_cols <- names(calc_fild)
  problems <- character(0)

  for (nm in names(datasets)) {
    ds <- datasets[[nm]]
    if (is.null(ds)) next

    missing_val <- setdiff(.REQUIRED_VALUE_COLS[[nm]], names(ds))
    if (length(missing_val) > 0) {
      problems <- c(problems, sprintf(
        "`%s` is missing required column(s): %s.",
        nm, paste0("`", missing_val, "`", collapse = ", ")
      ))
    }
    if (length(intersect(names(ds), key_cols)) == 0) {
      problems <- c(problems, sprintf(
        "`%s` shares no join key with `calc_fild` (keys available: %s; `%s` has: %s).",
        nm, paste0("`", key_cols, "`", collapse = ", "), nm,
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
    stop(
      "Invalid input data:\n  - ", paste(problems, collapse = "\n  - "), hint,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Coordinate keys of a gridded data.frame, one "x y" string per cell; NULL
# when the table carries no coordinate pair to key on.
.grid_keys <- function(df) {
  if (!is.data.frame(df)) {
    return(NULL)
  }
  xy <- .grid_xy(df)
  if (length(xy) != 2) {
    return(NULL)
  }
  unique(paste(df[[xy[1]]], df[[xy[2]]]))
}

# Check a `calc_fild` against the raster grid, at two levels of severity.
#
# A raster input defines the analysis grid, and a coordinate-keyed `calc_fild`
# is joined against it. A skeleton handed back from an earlier run -- a
# `build_grid_info()` table, or one written for another resolution -- would
# otherwise restrict the analysis to whatever happens to overlap, silently.
# No key in common at all means the two are different grids, so the call stops;
# a partial overlap is reported as a warning, because coarser skeletons are
# legal (a table of domain centroids is one). `validate = "off"` turns both off
# with the rest of the validation.
.check_grid_match <- function(calc_fild, raster_grids, res = NA_real_) {
  keys <- .grid_keys(calc_fild)
  grid <- unique(unlist(lapply(raster_grids, .grid_keys), use.names = FALSE))
  if (is.null(keys) || length(grid) == 0) {
    return(invisible(FALSE))
  }

  matched <- length(intersect(keys, grid))
  if (matched == length(keys)) {
    return(invisible(FALSE))
  }

  res_txt <- if (is.finite(res)) {
    paste0(" (raster grid resolution ", format(res), " deg)")
  } else {
    ""
  }
  fix <- paste0(
    ". Regenerate the table with `build_grid_info()` from the same rasters, ",
    "or set `target_res=` so that both land on one grid."
  )

  if (matched == 0) {
    stop(
      "`calc_fild` shares no coordinate key with the raster grid: 0 of ",
      length(keys), " coordinate key(s) match a raster cell", res_txt,
      ". The two are on different grids, so nothing can be joined", fix,
      call. = FALSE
    )
  }

  warning(
    "`calc_fild` is not on the raster grid: ", length(keys) - matched, " of ",
    length(keys), " coordinate key(s) match no raster cell", res_txt, fix,
    call. = FALSE
  )
  invisible(TRUE)
}

# ── the grain of the run, said out loud ─────────────────────────────────
#
# Mortality() is grain-agnostic: `calc_fild` decides whether the analysis is
# one row per grid cell or one row per domain, and `mort_lvl` decides whether
# the relative risks are calibrated inside a domain. Neither is readable from
# the arguments, and the two grains are not numerically identical -- a grid
# run takes the population-weighted mean of the relative risks of a domain's
# cells, a domain-only run takes the relative risk at the domain's
# population-weighted mean concentration (a Jensen gap, see
# domain_summary()). One line per run keeps that visible instead of letting
# the grain be dispatched silently. `validate = "off"` is the quiet mode and
# prints nothing at all.

# Resolution of the analysis grid, in degrees: the aligned raster when one
# defines the grid, otherwise the mean spacing of the tabular cell centres.
# NA when there is nothing to measure.
.grain_res <- function(calc_fild, template = NULL) {
  if (!is.null(template)) {
    return(mean(terra::res(template)))
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
    res_txt <- if (is.finite(res)) {
      paste0(" on a ", format(signif(res, 3), trim = TRUE, scientific = FALSE),
             " deg grid")
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
#' @param CRF Character. Concentration-response model name (see
#'   [cr_models()]; matched case-insensitively) or a data.frame with the
#'   same structure as [RR_std()] output (`conc`, `endpoint`, `age`, `RR`).
#' @param CI Character. Which RR table to use: `"MEAN"` (default), `"UP"` or
#'   `"LOW"`. `"UPPER"`/`"LOWER"` are accepted as aliases. Ignored when
#'   `CRF` is a data.frame.
#' @param calc_fild Attribution field: the spatial/administrative skeleton
#'   that all other inputs are joined onto. Must contain coordinate columns
#'   (`x`/`y`, `lon`/`lat`) and/or domain columns (`location`, `Country`,
#'   `province`, ...).
#'
#'   Optional for a **raster** `conc_real` (a file path or a `SpatRaster`):
#'   the ingestion of `conc_real` already carries the grid, so `NULL` builds
#'   the skeleton from the ingested exposure data (`x`/`y` only, one row per
#'   cell) and a raster-only call needs no separate attribution file. Tabular
#'   input still requires `calc_fild`.
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
#' @param mort_lvl Character. Domain column used to calibrate the
#'   population-weighted relative risk (PWRR), e.g. `"location"`. It must
#'   exist in both `calc_fild` and `mort_rate`. `NULL` skips calibration and
#'   computes at the finest available level.
#' @param scenario Character. Scenario (column or raster band) to extract
#'   from wide-format inputs via [getConc()], [getPop()], [getAge()] and
#'   [getMort()]. `NULL` uses the inputs as given.
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
#' @param target_res Numeric. Target grid resolution in degrees. `NULL`
#'   (default) auto-detects the finest input resolution and asks for
#'   confirmation interactively.
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
#' @seealso [build_grid_info()], [domain_summary()],
#'   [Decomposition()], [aggregate_mortality()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' extdata <- system.file("extdata", package = "AttrMort")
#' grid_info <- readxl::read_excel(file.path(extdata, "grid_info.xlsx"))
#' grid_exposure <- readxl::read_excel(file.path(extdata, "grid_exposure.xlsx"))
#' grid_pop  <- readxl::read_excel(file.path(extdata, "grid_pop.xlsx"))
#' national_age   <- readxl::read_excel(file.path(extdata, "national_age_structure.xlsx"))
#' national_mort  <- readxl::read_excel(file.path(extdata, "national_mortality.xlsx"))
#'
#' # Wide tables: extract one scenario by name
#' Mortality(
#'   CRF = "GEMM", calc_fild = grid_info, scenario = "base2015",
#'   conc_real = grid_exposure, pop_total = grid_pop,
#'   age_struc = national_age, mort_rate = national_mort, mort_lvl = "location"
#' )
#'
#' # File paths, one call
#' Mortality(
#'   CRF = "GEMM", scenario = "base2015",
#'   calc_fild = file.path(extdata, "grid_info.xlsx"),
#'   conc_real = "exposure.tif", pop_total = "population.tif",
#'   age_struc = file.path(extdata, "national_age_structure.xlsx"),
#'   mort_rate = file.path(extdata, "national_mortality.xlsx"),
#'   mort_lvl  = "location", admin = "boundaries.shp", admin_col = "NAME"
#' )
#' }
Mortality <- function(
    CRF,
    CI           = "MEAN",
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
    chunk_ages   = NULL
) {
  validate     <- match.arg(validate)
  aggregate_by <- match.arg(aggregate_by, c("total", "endpoint", "age", "all"))
  CI           <- .match_ci(CI)

  if (!is.null(aggregate) && !isTRUE(aggregate) && !is.character(aggregate)) {
    stop("`aggregate` must be NULL, TRUE, or a character vector of columns.",
         call. = FALSE)
  }
  if (!is.logical(uncertain) || length(uncertain) != 1 || is.na(uncertain)) {
    stop("`uncertain` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.numeric(conc_uncert) || length(conc_uncert) != 1 ||
      is.na(conc_uncert) || conc_uncert < 0) {
    stop("`conc_uncert` is a percentage and must be a single non-negative ",
         "number.", call. = FALSE)
  }
  if (!is.null(chunk_ages) &&
      (!is.numeric(chunk_ages) || length(chunk_ages) != 1 ||
         is.na(chunk_ages) || chunk_ages < 1)) {
    stop("`chunk_ages` must be NULL or a single positive number of age ",
         "strata per pass.", call. = FALSE)
  }

  # A concentration raster already carries the analysis grid, so it can stand
  # in for `calc_fild` and, when domain calibration is asked for without
  # boundaries, for `admin` as well. Both are read off the input types: there
  # is no switch for them.
  conc_raster <- .is_raster_input(conc_real)
  pop_raster  <- .is_raster_input(pop_total)
  # Only a skeleton the user supplied can be stale; the one taken from a
  # raster `conc_real` below is the grid by construction.
  own_skeleton <- !is.null(calc_fild)

  .check_input_files(
    calc_fild = calc_fild, conc_real = conc_real, conc_cf = conc_cf,
    pop_total = pop_total, age_struc = age_struc, mort_rate = mort_rate,
    admin     = admin
  )

  # ── spatial alignment of raster inputs ─────────────────────────────
  spatial   <- .align_raster_inputs(conc_real, pop_total, conc_cf, scenario,
                                    target_res, dgt_coord)
  conc_real <- spatial$conc_real
  pop_total <- spatial$pop_total
  conc_cf   <- spatial$conc_cf
  template  <- spatial$template

  # ── ingestion and column mapping ───────────────────────────────────
  conc_real <- .ingest_and_map(conc_real, schema = "location",
                               dgt_coord = dgt_coord, label = "conc_real")
  if (is.null(calc_fild)) {
    # Grid-native skeleton: the ingested exposure raster is one row per cell,
    # so its coordinates are the attribution field.
    if (!conc_raster) {
      stop(
        "`calc_fild = NULL` is only supported when `conc_real` is a raster ",
        "(a file path or a SpatRaster), because the analysis grid is then ",
        "taken from the exposure data. Tabular `conc_real` needs an explicit ",
        "`calc_fild` supplying the grid coordinates and/or the domains.",
        call. = FALSE
      )
    }
    calc_fild <- conc_real[, c("x", "y")] |> distinct()
  } else {
    calc_fild <- .ingest_and_map(calc_fild, schema = "location",
                                 dgt_coord = dgt_coord, label = "calc_fild")
  }
  pop_total <- .ingest_and_map(pop_total, schema = "location",
                               dgt_coord = dgt_coord, label = "pop_total")
  age_struc <- .ingest_and_map(age_struc, schema = c("age", "prop", "location"),
                               dgt_coord = dgt_coord, label = "age_struc")
  mort_rate <- .ingest_and_map(mort_rate,
                               schema = c("age", "cause", "mortrate", "location"),
                               dgt_coord = dgt_coord, label = "mort_rate")
  if (!is.null(conc_cf)) {
    conc_cf <- .ingest_and_map(conc_cf, schema = "location",
                               dgt_coord = dgt_coord, label = "conc_cf")
  }

  # ── grid consistency of a supplied skeleton ────────────────────────
  # The rasters define the grid and `calc_fild` is joined onto them by
  # coordinate key, so a skeleton from another grid -- a `build_grid_info()`
  # table reused across resolutions, say -- would silently restrict the
  # analysis to whatever happens to overlap. No key in common means the two
  # grids are different and the call stops; a partial overlap is reported as a
  # warning, because a deliberately coarser table is legal. `validate = "off"`
  # turns both off with the rest of the validation.
  if (validate != "off" && own_skeleton && (conc_raster || pop_raster)) {
    .check_grid_match(
      calc_fild,
      list(if (conc_raster) conc_real, if (pop_raster) pop_total),
      res = if (is.null(template)) NA_real_ else mean(terra::res(template))
    )
  }

  # ── administrative boundaries ──────────────────────────────────────
  # A raster run that names a `mort_lvl` of `mort_rate` but carries no such
  # column in `calc_fild` wants domain calibration without boundaries:
  # default to national boundaries. `admin =` always wins; tabular runs are
  # untouched, so `admin = NULL` still means "no domain column" there.
  national_admin <- FALSE
  if (is.null(admin) && conc_raster && !is.null(mort_lvl) &&
      mort_lvl %in% names(mort_rate) && !mort_lvl %in% names(calc_fild)) {
    if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
      stop(
        "The raster-only path defaults to national boundaries, which needs ",
        "the `rnaturalearth` package (a Suggests dependency). Install it with ",
        "install.packages(\"rnaturalearth\"), or pass `admin =` (a shapefile ",
        "path or an sf object) to supply boundaries yourself.",
        call. = FALSE
      )
    }
    message("`admin = NULL`: rasterizing national boundaries ",
            "(rnaturalearth, scale = 110) onto the analysis grid for ",
            "`mort_lvl = \"", mort_lvl, "\"`. Pass `admin =` to override the ",
            "administrative level.")
    admin          <- rnaturalearth::ne_countries(scale = 110,
                                                  returnclass = "sf")
    national_admin <- TRUE
  }

  calc_fild <- .attach_admin(calc_fild, admin, admin_col, mort_lvl, mort_rate,
                             template = template, target_res = target_res,
                             dgt_coord = dgt_coord)

  if (national_admin) {
    # Country names are the usual failure mode: a name that does not match
    # `mort_rate[[mort_lvl]]` silently drops that domain, so report the count.
    matched <- length(intersect(unique(calc_fild[[mort_lvl]]),
                                unique(mort_rate[[mort_lvl]])))
    domains <- length(unique(mort_rate[[mort_lvl]]))
    message("National boundaries: ", matched, " of ", domains, " `", mort_lvl,
            "` value(s) of `mort_rate` matched the rasterized grid.",
            if (matched < domains) {
              paste0(" Country names have to match `", mort_lvl, "` exactly; ",
                     "pass `admin =` with `admin_col =` for your own naming.")
            } else {
              ""
            })
  }

  # ── scenario extraction from wide inputs ───────────────────────────
  extracted <- .extract_scenario(conc_real, pop_total, age_struc, mort_rate,
                                 conc_cf, scenario, dgt_conc)
  conc_real <- extracted$conc_real
  pop_total <- extracted$pop_total
  age_struc <- extracted$age_struc
  mort_rate <- extracted$mort_rate
  conc_cf   <- extracted$conc_cf

  if (is.null(conc_cf)) {
    conc_cf <- conc_real
  }

  # ── data validation ────────────────────────────────────────────────
  if (validate != "off") {
    report <- validate_mortality_input(
      list(conc = conc_real, pop = pop_total, age_struc = age_struc,
           mort_rate = mort_rate),
      cr_model = if (is.character(CRF)) .match_cr_model(CRF) else NA_character_,
      dgt_conc = dgt_conc
    )
    if (!report$valid && validate == "stop") {
      stop("Input validation failed:\n  - ",
           paste(report$issues, collapse = "\n  - "), call. = FALSE)
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
  # message belongs to Mortality(), not to the age-chunked kernel, which is
  # entered several times for one run.
  if (validate != "off") {
    message(.grain_message(calc_fild, mort_lvl, mort_rate,
                           res = .grain_res(calc_fild, template)))
  }

  # ── central estimate, plus the range when requested ────────────────
  # Every branch -- central, CRF range and the conc_uncert chain -- goes
  # through the same age-chunked helper, so `chunk_ages` cannot change one of
  # them without the others.
  compute <- function(ci, conc_r = conc_real, conc_c = conc_cf) {
    .calc_attributable_ages(calc_fild, conc_r, conc_c, pop_total, age_struc,
                            mort_rate, mort_lvl, CRF, ci, chunk_ages)
  }

  grid     <- compute(CI)
  key_cols <- intersect(names(calc_fild), names(grid))

  lower_frames <- upper_frames <- NULL
  if (uncertain) {
    lower_frames <- list(.total_frame(compute("LOW"), key_cols))
    upper_frames <- list(.total_frame(compute("UP"), key_cols))

    if (conc_uncert > 0) {
      for (side in c("low", "up")) {
        factor <- if (side == "low") {
          1 - conc_uncert / 100
        } else {
          1 + conc_uncert / 100
        }
        shifted <- .total_frame(
          compute(CI,
                  .scale_conc(conc_real, factor, dgt_conc),
                  .scale_conc(conc_cf, factor, dgt_conc)),
          key_cols
        )
        if (side == "low") {
          lower_frames <- c(lower_frames, list(shifted))
        } else {
          upper_frames <- c(upper_frames, list(shifted))
        }
      }
    }
  }

  # ── optional domain aggregation ────────────────────────────────────
  if (!is.null(aggregate)) {
    at <- if (isTRUE(aggregate)) {
      if (is.null(mort_lvl)) {
        message("`aggregate = TRUE` with `mort_lvl = NULL`: the whole field ",
                "is aggregated into a single row.")
        character(0)
      } else {
        mort_lvl
      }
    } else {
      aggregate
    }

    missing_cols <- setdiff(at, names(grid))
    if (length(missing_cols) > 0) {
      stop("`aggregate` column(s) not found in the result: ",
           paste(missing_cols, collapse = ", "), ".", call. = FALSE)
    }

    out <- if (length(at) == 0) {
      data.frame(total = sum(.row_total(grid, key_cols)))
    } else {
      aggregate_mortality(grid, calc_fild = calc_fild, at = at,
                          by = aggregate_by)
    }

    pwe <- .domain_pwe(calc_fild, conc_real, pop_total, at)
    out <- if (length(at) == 0) {
      cbind(out, pwe)
    } else {
      left_join(out, pwe, by = at)
    }

    if (uncertain) {
      out <- .attach_range(out, lower_frames, upper_frames, at)
    }
    return(out)
  }

  if (uncertain) {
    grid$CI_LOW <- .range_sum(lower_frames, key_cols, "low",
                              aggregate = FALSE)
    grid$CI_UP  <- .range_sum(upper_frames, key_cols, "up",
                              aggregate = FALSE)
  }
  grid
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
# warning that goes with it (or NULL when there is nothing to warn about).
# Split out so that the age-chunked path can warn once instead of once per
# age block.
.mort_lvl_warning <- function(mort_lvl, mort_rate) {
  if (is.null(mort_lvl)) {
    return(paste0("The `mort_lvl` is set NULL, calculation will ignore ",
                  "calibration of mort_rate."))
  }
  if (mort_lvl %in% names(mort_rate)) {
    return(NULL)
  }
  paste0("The `mort_lvl` is not a domain column of `mort_rate` dataset, ",
         "calculation will regard the field as one.")
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
  lapply(starts, function(s) ages[s:min(s + size - 1L, length(ages))])
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
                                    age_struc, mort_rate, mort_lvl, CRF, CI,
                                    chunk_ages = NULL) {
  RR_tbl <- if (is.data.frame(CRF)) CRF else RR_std(.match_cr_model(CRF), CI)
  ages   <- .chunkable_ages(mort_rate, RR_tbl)

  if (length(ages) == 0) {
    # No shared age stratum: leave the report to .calc_attributable().
    return(.calc_attributable(calc_fild, conc_real, conc_cf, pop_total,
                              age_struc, mort_rate, mort_lvl, CRF, CI))
  }

  size   <- .resolve_chunk_ages(chunk_ages, nrow(calc_fild), length(ages),
                                length(unique(RR_tbl$endpoint)))
  blocks <- .split_ages(ages, size)

  # The branch warning is a property of the whole run, so only the first
  # block emits it; the blocks themselves are independent computations.
  parts <- lapply(seq_along(blocks), function(i) {
    block <- blocks[[i]]
    .calc_attributable(
      calc_fild, conc_real, conc_cf, pop_total,
      age_struc |> filter(.standardize_age_key(age) %in% block),
      mort_rate |> filter(.standardize_age_key(age) %in% block),
      mort_lvl, CRF, CI, warn = i == 1L
    )
  })

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
  parts <- lapply(seq_along(blocks), function(i) {
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
# for the whole run.
.calc_attributable <- function(calc_fild, conc_real, conc_cf, pop_total,
                               age_struc, mort_rate, mort_lvl, CRF, CI,
                               warn = TRUE) {
  crf_label <- if (is.character(CRF)) .match_cr_model(CRF) else "user-supplied"
  RR_tbl <- if (is.data.frame(CRF)) CRF else RR_std(crf_label, CI)

  # Canonicalise the join keys of the tabular inputs.
  mort_rate <- mort_rate |>
    mutate(endpoint = tolower(as.character(endpoint)),
           age      = .standardize_age_key(age))
  age_struc <- age_struc |>
    mutate(age = .standardize_age_key(age))

  # A CRF whose endpoints are absent from mort_rate can only produce an empty
  # result: say so instead of returning zero rows.
  ep_rr   <- unique(RR_tbl$endpoint)
  ep_mort <- unique(mort_rate$endpoint)
  if (length(intersect(ep_rr, ep_mort)) == 0) {
    stop(
      "No shared disease endpoint between CRF \"", crf_label,
      "\" and `mort_rate`.\n",
      "  CRF endpoints   : ", paste(sort(ep_rr), collapse = ", "), "\n",
      "  mort_rate values: ", paste(head(sort(ep_mort), 20), collapse = ", "),
      call. = FALSE
    )
  }

  branch_msg <- .mort_lvl_warning(mort_lvl, mort_rate)
  if (warn && !is.null(branch_msg)) {
    warning(branch_msg, call. = FALSE)
  }

  if (is.null(mort_lvl)) {
    out <- list(calc_fild, conc_real, RR_tbl, age_struc, mort_rate, pop_total) |>
      reduce(left_join) |>
      mutate(M = pop * prop * mortrate, .keep = "unused") |>
      mutate(AttrMort = M * (RR - 1) / RR / 1e5, .keep = "unused") |>
      pivot_wider(
        names_from  = c("endpoint", "age"),
        names_sep   = "_",
        values_from = "AttrMort"
      )
  } else if (mort_lvl %in% names(mort_rate)) {
    PWRR <- list(calc_fild, conc_real, pop_total, RR_tbl) |>
      reduce(left_join) |>
      na.omit() |>
      group_by(pick(all_of(mort_lvl)), endpoint, age) |>
      summarise(PWRR = weighted.mean(RR, pop, na.rm = TRUE)) |>
      ungroup()

    out <- list(calc_fild, conc_cf, pop_total, RR_tbl, mort_rate, age_struc,
                PWRR) |>
      reduce(left_join) |>
      select(-conc) |>
      na.omit() |>
      mutate(M = pop * prop * mortrate, .keep = "unused") |>
      mutate(AttrMort = M * (RR - 1) / PWRR / 1e5, .keep = "unused") |>
      pivot_wider(
        names_from  = c("endpoint", "age"),
        names_sep   = "_",
        values_from = "AttrMort"
      )
  } else {
    PWRR <- list(calc_fild, conc_real, pop_total, RR_tbl) |>
      reduce(left_join) |>
      na.omit() |>
      group_by(endpoint, age) |>
      summarise(PWRR = weighted.mean(RR, pop, na.rm = TRUE)) |>
      ungroup()

    out <- list(calc_fild, pop_total, mort_rate, age_struc) |>
      reduce(left_join) |>
      group_by(endpoint, age) |>
      summarise(M = sum(pop * prop * mortrate / 1e5, na.rm = TRUE)) |>
      ungroup() |>
      left_join(PWRR) |>
      na.omit() |>
      mutate(AttrMort = M * (1 - 1 / PWRR), .keep = "unused") |>
      pivot_wider(
        names_from  = c("endpoint", "age"),
        names_sep   = "_",
        values_from = "AttrMort"
      )
  }

  if (nrow(out) == 0) {
    stop(
      "No rows survived the join between the inputs and the ",
      "concentration-response table. Check that `mort_rate` covers the same ",
      "domains and age groups as `calc_fild`, and that `age` values match ",
      "the CRF age strata (e.g. ", paste(head(sort(unique(RR_tbl$age)), 5),
                                         collapse = ", "), ", ...).",
      call. = FALSE
    )
  }

  out
}
