# Input preparation: the front end `mortality()` and `decompose()` share
#
# Everything that happens between "the user hands over data" and "the
# kernel gets canonical tables" lives in this file. Both entry points call
# `.prepare_inputs()` and nothing else here; `grid_info.R` and
# `build_grid_info()` reuse the lower layers (`.check_input_files()`,
# `.align_raster_inputs()`, `.ingest_and_map()`, `.attach_admin()`,
# `.extract_scenario()`), which stay in `ingest.R` and `raster-io.R` because
# they are also the raster/format layer.
#
# The flow, in the order it runs:
#
#   1. `.check_input_files()`   every character input is a file that exists
#   2. `.align_raster_inputs()` detect rasters, resolve the target resolution,
#                               reproject/resample them onto one lattice
#                               (`.resolve_target_res()`, `align_to_target()`),
#                               hand back a `template`
#   3. `.map_input_columns()`   read every input and map its columns onto the
#                               canonical schema (`.ingest_and_map()`)
#   4. `.check_grid_match()`    a skeleton the user supplied must overlap the
#                               raster grid: no key in common stops the run,
#                               a partial overlap warns
#   5. `.default_national_admin()` + `.attach_admin()` +
#      `.report_boundary_match()`  boundaries become the domain column of
#                               `calc_fild`
#   6. `.extract_scenario()`    one value column per role, named canonically
#                               (`scenario =` is a per-input column selector;
#                               the four `.slice_*()` do one input each)
#
# Which input type goes where is stated once, as data, in `.INPUT_ROUTES`
# below; `test-prepare-inputs.R` checks that the handlers it names exist.
# `.check_input_files()` and `.align_raster_inputs()` are in `ingest.R`.

# ── the routing table ──────────────────────────────────────────────────

# One row per decision the front end makes: `given` is what it sees, `when` the
# condition, `then` what happens, `handler` the function that does it. Editing
# the flow means editing this table and its handler together.
.INPUT_ROUTES <- tibble::tribble(
  ~given,                       ~when,                                                      ~then,                                                           ~handler,
  "data.frame",                 "always",                                                   "used as it is",                                                 ".ingest_single_input",
  "character path",             "extension is a raster format",                             "raster_to_grid(): one row per cell",                            ".ingest_single_input",
  "character path",             "extension is .csv/.txt",                                   "readr::read_csv()",                                             ".ingest_single_input",
  "character path",             "extension is .xls/.xlsx",                                  "readxl::read_excel()",                                          ".ingest_single_input",
  "character path",             "any other extension",                                      "stop, listing the supported formats",                           ".ingest_single_input",
  "conc_real is a raster",      "calc_fild = NULL",                                         "the exposure grid is the analysis skeleton",                    ".map_input_columns",
  "conc_real has coordinates",  "calc_fild = NULL",                                         "its coordinates are the analysis grid, reported in a message",   ".map_input_columns",
  "conc_real is a domain table", "calc_fild = NULL",                                        "stop: a grid cannot be derived from domain rows",                ".map_input_columns",
  "any raster input",           "target_res given",                                         "that resolution is used",                                       ".resolve_target_res",
  "any raster input",           "target_res = NULL, non-interactive",                       "detected; auto-confirmed, reported or refused by cell count",   ".resolve_target_res",
  "any raster input",           "target_res = NULL, interactive",                           "menu of candidate resolutions",                                 ".prompt_resolution",
  "two rasters",                "different resolutions",                                    "aggregate(sum) then resample, totals checked",                  ".aggregate_pop",
  "skeleton + rasters",         "no coordinate key in common",                              "stop: the two grids are different",                             ".check_grid_match",
  "skeleton + rasters",         "partial overlap",                                          "warn with the number of unmatched keys",                        ".check_grid_match",
  "calc_fild is a vector map",  "always",                                                   "the grid comes from the exposure, the map labels it",           ".prepare_inputs",
  "calc_fild is a vector map",  "`admin` was passed as well",                               "stop: two boundary sources",                                    ".prepare_inputs",
  "admin given",                "a raster template exists",                                 "boundaries rasterized onto the grid",                           ".attach_admin",
  "admin given",                "the skeleton is a table",                                  "point-in-polygon labels",                                        ".attach_admin",
  "admin = NULL, raster input", "mort_lvl is a column of mort_rate, not of calc_fild",      "national boundaries (rnaturalearth), match count reported",      ".default_national_admin",
  "admin = NULL, raster input", "the same, without rnaturalearth",                          "stop, naming the Suggests dependency",                           ".default_national_admin",
  "tabular input",              "several value candidates and no canonical column",         "stop, listing the candidates",                                   ".resolve_case_col",
  "tabular input",              "no column named by `scenario`",                            "canonical column, or the single numeric one, with a message",    ".extract_scenario",
  "tabular input",              "`scenario` names a column",                                "that column becomes the value column",                           ".extract_scenario"
)

# ── grid consistency ───────────────────────────────────────────────────

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
  grid <- map(raster_grids, .grid_keys) |>
    list_c() |>
    unique()
  if (is.null(keys) || length(grid) == 0) {
    return(invisible(FALSE))
  }

  matched <- length(intersect(keys, grid))
  if (matched == length(keys)) {
    return(invisible(FALSE))
  }

  res_txt <- if (all(is.finite(res)) && length(res) > 0) {
    paste0(" (raster grid resolution ", .fmt_res(res), " deg)")
  } else {
    ""
  }
  fix <- paste0(
    ". Regenerate the table with `build_grid_info()` from the same rasters, ",
    "or set `target_res=` so that both land on one grid."
  )

  if (matched == 0) {
    .abort(str_c(
      "`calc_fild` shares no coordinate key with the raster grid: 0 of ",
      length(keys), " coordinate key(s) match a raster cell", res_txt,
      ". The two are on different grids, so nothing can be joined", fix
    ))
  }

  cli::cli_warn(str_c(
    "`calc_fild` is not on the raster grid: ", length(keys) - matched, " of ",
    length(keys), " coordinate key(s) match no raster cell", res_txt, fix
  ))
  invisible(TRUE)
}

# ── boundaries ─────────────────────────────────────────────────────────

# A raster run that names a `mort_lvl` of `mort_rate` but carries no such column
# in `calc_fild` asks for domain calibration without boundaries, so it falls
# back to the national boundaries shipped with rnaturalearth. `admin =` always
# wins, and a tabular run is untouched: `admin = NULL` still means "no domain
# column" there.
.default_national_admin <- function(admin, conc_raster, mort_lvl, mort_rate,
                                    calc_fild) {
  if (!is.null(admin) || !conc_raster || is.null(mort_lvl) ||
      !mort_lvl %in% names(mort_rate) || mort_lvl %in% names(calc_fild)) {
    return(list(admin = admin, national = FALSE))
  }
  if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
    .abort(str_c(
      "The raster-only path defaults to national boundaries, which needs ",
      "the `rnaturalearth` package (a Suggests dependency). Install it with ",
      "install.packages(\"rnaturalearth\"), or pass `admin =` (a shapefile ",
      "path or an sf object) to supply boundaries yourself."
    ))
  }
  cli::cli_inform(str_c(
    "`admin = NULL`: rasterizing national boundaries ",
    "(rnaturalearth, scale = 110) onto the analysis grid for ",
    "`mort_lvl = \"", mort_lvl, "\"`. Pass `admin =` to override the ",
    "administrative level."
  ))
  list(admin    = rnaturalearth::ne_countries(scale = 110, returnclass = "sf"),
       national = TRUE)
}

# Country names are the usual failure mode of the national default: a name that
# does not match `mort_rate[[mort_lvl]]` silently drops that domain, so report
# how many matched instead.
.report_boundary_match <- function(calc_fild, mort_rate, mort_lvl,
                                   source = "National boundaries") {
  matched <- length(intersect(unique(calc_fild[[mort_lvl]]),
                              unique(mort_rate[[mort_lvl]])))
  domains <- length(unique(mort_rate[[mort_lvl]]))
  match_hint <- if (matched < domains) {
    str_c(" Country names have to match `", mort_lvl, "` exactly; ",
          "pass `admin =` with `admin_col =` for your own naming.")
  } else {
    ""
  }
  cli::cli_inform(str_c(
    source, ": ", matched, " of ", domains, " `", mort_lvl,
    "` value(s) of `mort_rate` matched the gridded labels.", match_hint
  ))
  invisible(NULL)
}

# ── ingestion and column mapping ───────────────────────────────────────

# Read every input and map its columns onto the canonical names. `calc_fild` is
# the analysis grid; without one it is taken from `conc_real`, whose coordinates
# are the attribution field (a raster is grid-native, a table is the cells the
# exposure was measured on). Domains are not part of that skeleton: a run whose
# `mort_lvl` needs one gets it from `admin` (boundaries, joined onto the grid).
# The order below is the order the mapping messages come out in, which is the
# order the inputs are documented in.
.map_input_columns <- function(calc_fild, conc_real, pop_total, age_struc,
                               mort_rate, conc_cf, conc_raster, dgt_coord) {
  conc_real <- .ingest_and_map(conc_real, schema = "location",
                               dgt_coord = dgt_coord, label = "conc_real")
  if (is.null(calc_fild)) {
    # Grid-native skeleton: the ingested exposure is one row per cell, so its
    # coordinates are the attribution field. A table with no coordinates
    # (already aggregated to domains) cannot define a grid: it needs an
    # explicit `calc_fild` carrying the grid, or a raster exposure.
    xy <- .grid_xy(conc_real)
    if (length(xy) != 2) {
      .abort(str_c(
        "`calc_fild = NULL` needs a `conc_real` that carries coordinates: ",
        "the analysis grid is taken from the exposure data. A raster does ",
        "that by construction; a table does it when it has coordinate ",
        "columns (found: {paste(names(conc_real), collapse = ', ')}). Pass ",
        "`calc_fild =` -- `build_grid_info()` writes one --, pass a raster ",
        "`conc_real`, or pass `admin =` with a gridded exposure."
      ))
    }
    calc_fild <- conc_real[, xy, drop = FALSE] |> distinct()
    if (!conc_raster) {
      cli::cli_inform(str_c(
        "`calc_fild = NULL`: the analysis grid is the {nrow(calc_fild)} ",
        "coordinate pair(s) of `conc_real`. Pass `calc_fild =` (see ",
        "`build_grid_info()`) to use a grid of your own, and `admin =` to put ",
        "domains on it."
      ))
    }
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
  list(calc_fild = calc_fild, conc_real = conc_real, pop_total = pop_total,
       age_struc = age_struc, mort_rate = mort_rate, conc_cf = conc_cf)
}

# ── the calibration level ──────────────────────────────────────────────

# Which column of `mort_rate` the calibration is keyed on. `mort_lvl` names it
# the way the caller sees the data, but the column mapping renames a recognised
# variant to the canonical `location` before anyone looks: a caller who wrote
# `Country` would name a column that no longer exists, and the run would
# silently calibrate the whole field as one unit. Roles are therefore resolved
# against the mapped tables, and a name that still matches nothing falls back
# to whatever domain column `mort_rate` carries itself -- with a warning, never
# silently.
.resolve_mort_lvl <- function(mort_lvl, mort_rate, calc_fild) {
  if (is.null(mort_lvl) || is.null(mort_rate) || !is.data.frame(mort_rate)) {
    return(mort_lvl)
  }
  if (mort_lvl %in% names(mort_rate)) {
    return(mort_lvl)
  }
  variants <- c(.COLUMN_VARIANTS$location, .DOMAIN_VARIANTS)
  if (tolower(mort_lvl) %in% tolower(variants)) {
    hit <- intersect(c("location", .DOMAIN_VARIANTS, variants), names(mort_rate))[1]
    if (!is.na(hit)) {
      cli::cli_inform(str_c(
        "`mort_lvl = \"", mort_lvl, "\"` is mapped to `", hit,
        "` when the inputs are read; calibrating on `", hit, "`."
      ))
      return(hit)
    }
  }
  own <- setdiff(names(mort_rate), c("age", "endpoint", "mortrate",
                                     .COLUMN_VARIANTS$age, .COLUMN_VARIANTS$cause,
                                     .COLUMN_VARIANTS$mortrate))
  if (length(own) > 0) {
    cli::cli_warn(str_c(
      "`mort_lvl = \"", mort_lvl, "\"` is not a column of `mort_rate`; ",
      "calibrating on its own domain column `", own[1], "`."
    ))
    return(own[1])
  }
  cli::cli_warn(str_c(
    "`mort_rate` carries no geographic column: the calibration is one unit ",
    "for the whole field, whatever `mort_lvl` says."
  ))
  mort_lvl
}

# ── scenario extraction ────────────────────────────────────────────────

# Extract one value column per input, and name it canonically.
#
# `scenario` is a per-input column selector, not a contract across inputs: the
# package computes from whatever the inputs hold, without judging whether they
# belong to the same scenario or year. When `scenario` is given, each input
# that carries that column is narrowed by it; an input that does not carry it
# is used as it is when it has its canonical column or a single numeric value
# column. With `scenario = NULL` every input is already one value column per
# role, which is named canonically here (`.resolve_case_col()` reports which
# column was used). Several value candidates and no canonical column stop with
# the candidates listed rather than picking one silently.
.extract_scenario <- function(conc_real, pop_total, age_struc, mort_rate,
                              conc_cf, scenario, dgt_conc) {
  if (is.null(scenario)) {
    canon <- function(data, canonical, keys, label,
                      allow_key_strings = FALSE) {
      if (!is.data.frame(data)) {
        return(data)
      }
      value <- .resolve_case_col(data, NULL, keys, canonical, label,
                                 strict = FALSE,
                                 allow_key_strings = allow_key_strings)
      if (!identical(value, canonical) && value %in% names(data)) {
        data <- rename(data, !!canonical := all_of(value))
      }
      data
    }
    # The concentration key still has to follow the data contract: a
    # single-band raster or an already-long table hands the value over as a
    # plain number, while the lookup table keys are strings.
    as_key <- function(data) {
      if (is.data.frame(data) && is.numeric(data$conc)) {
        data$conc <- matchable(data$conc, dgt = dgt_conc)
      }
      data
    }

    conc_real <- canon(conc_real, "conc", .value_key_cols(conc_real),
                       "`conc_real`", allow_key_strings = TRUE) |>
      as_key()
    conc_cf <- canon(conc_cf, "conc", .value_key_cols(conc_cf),
                     "`conc_cf`", allow_key_strings = TRUE) |>
      as_key()

    return(list(
      conc_real = conc_real,
      pop_total = canon(pop_total, "pop", .value_key_cols(pop_total),
                        "`pop_total`"),
      age_struc = canon(age_struc, "prop",
                        .value_key_cols(age_struc, age = TRUE),
                        "`age_struc`"),
      mort_rate = canon(mort_rate, "mortrate",
                        .value_key_cols(mort_rate, age = TRUE, cause = TRUE),
                        "`mort_rate`"),
      conc_cf = conc_cf
    ))
  }
  # Every input is extracted only when it is present: `conc_cf` is optional in
  # mortality() and the domain summary carries no age structure or mortality
  # table at all, so NULL stays NULL instead of being handed to .slice_age().
  # .slice_age()'s own age-completeness check is skipped here: mortality() reports
  # the same problem once, through validate_mortality_input(), and reporting it
  # twice only trains users to ignore warnings.
  list(
    conc_real = .slice_conc(conc_real, scenario, dgt = dgt_conc),
    pop_total = .slice_pop(pop_total, scenario),
    age_struc = if (is.null(age_struc)) {
      NULL
    } else {
      .slice_age(age_struc, scenario, min_age_groups = 0)
    },
    mort_rate = if (is.null(mort_rate)) NULL else .slice_mort(mort_rate, scenario),
    conc_cf   = if (is.null(conc_cf)) NULL else .slice_conc(conc_cf, scenario,
                                                        dgt = dgt_conc)
  )
}

# ── one input, one scenario ────────────────────────────────────────────

# The four slice functions narrow one input to one scenario and name the result
# canonically. They are the per-input half of `.extract_scenario()`, which is
# their only caller: `mortality()` and `decompose()` both go through it rather
# than through these, so they stay internal.
#
# `case` is a per-input column selector, not a contract across inputs: an input
# that does not carry the column falls back to its canonical column, or to its
# single numeric non-key column. Several candidates and no canonical column
# stop with the list rather than picking one silently.
.slice_conc <- function(data, case, xy = NULL, dgt = 1) {
  if (!is.data.frame(data)) {
    .abort("Only accept data.frame INPUT.")
  }
  keys  <- .resolve_key_cols(data, xy, .COORD_VARIANTS, .DOMAIN_VARIANTS,
                             key_arg = "xy")
  value <- .resolve_case_col(data, case,
                             keys = c(keys, .value_key_cols(data)),
                             canonical = "conc", label = "the exposure data",
                             allow_key_strings = TRUE)

  data |>
    select(all_of(keys), conc = all_of(value)) |>
    mutate(conc = if (is.numeric(conc)) matchable(conc, dgt = dgt) else conc)
}

.slice_pop <- function(data, case, xy = NULL) {
  if (!is.data.frame(data)) {
    .abort("Only accept data.frame INPUT.")
  }
  keys  <- .resolve_key_cols(data, xy, .COORD_VARIANTS, .DOMAIN_VARIANTS,
                             key_arg = "xy")
  value <- .resolve_case_col(data, case,
                             keys = c(keys, .value_key_cols(data)),
                             canonical = "pop", label = "the population data")

  data |> select(all_of(keys), pop = all_of(value))
}

# The proportions are renormalised to sum to 1 within each domain, so inputs
# expressed as counts and as percentages are both accepted. The number of age
# groups is checked against `min_age_groups`, because the C-R tables are only
# defined for 5-year strata; `.extract_scenario()` passes 0 there and lets
# `validate_mortality_input()` report the same problem once per run.
.slice_age <- function(data, case, loc = NULL, min_age_groups = 20) {
  if (!is.data.frame(data)) {
    .abort("Only accept data.frame INPUT.")
  }
  loc_cols <- .resolve_key_cols(data, loc, .DOMAIN_VARIANTS, .COORD_VARIANTS,
                                key_arg = "loc")

  age_col <- .pick_column(data, "age", prefer = c("age", "age_group", "agegroup"))
  if (is.null(age_col)) {
    .abort(str_c(
      "No age column found in the age-structure data. Available columns: ",
      "{paste(names(data), collapse = \", \")}."
    ))
  }

  value <- .resolve_case_col(data, case,
                             keys = c(loc_cols,
                                      .value_key_cols(data, age = TRUE)),
                             canonical = "prop", label = "the age-structure data")

  n_age <- length(unique(data[[age_col]]))
  if (min_age_groups > 0 && n_age < min_age_groups) {
    cli::cli_warn(str_c(
      "The age structure data have {n_age} age group(s); {min_age_groups} are ",
      "expected. Results will only cover the age groups present in the data. ",
      "Set `min_age_groups = 0` to silence this warning."
    ))
  }

  data |>
    select(all_of(loc_cols), age = all_of(age_col), prop = all_of(value)) |>
    group_by(across(any_of(loc_cols))) |>
    mutate(prop = prop.table(prop)) |>
    ungroup()
}

.slice_mort <- function(data, case, loc = NULL) {
  if (!is.data.frame(data)) {
    .abort("Only accept data.frame INPUT.")
  }
  loc_cols <- .resolve_key_cols(data, loc, .DOMAIN_VARIANTS, .COORD_VARIANTS,
                                key_arg = "loc")

  age_col <- .pick_column(data, "age", prefer = c("age", "age_group", "agegroup"))
  if (is.null(age_col)) {
    .abort(str_c(
      "No age column found in the mortality data. Available columns: ",
      "{paste(names(data), collapse = \", \")}."
    ))
  }

  cause_col <- .pick_column(data, "cause|endpoint", prefer = c("endpoint", "cause"))
  if (is.null(cause_col)) {
    .abort(str_c(
      "No cause/endpoint column found in the mortality data. Available columns: ",
      "{paste(names(data), collapse = \", \")}."
    ))
  }

  value <- .resolve_case_col(data, case,
                             keys = c(loc_cols,
                                      .value_key_cols(data, age = TRUE,
                                                      cause = TRUE)),
                             canonical = "mortrate", label = "the mortality data")

  data |>
    select(all_of(loc_cols), age = all_of(age_col),
           endpoint = all_of(cause_col), mortrate = all_of(value))
}

# ── the front door ─────────────────────────────────────────────────────

# Everything a run does before it calculates: read every input, align the
# rasters, map the columns, check the grid, attach boundaries and narrow each
# input to one scenario. `mortality()` calls it once; `decompose()` calls it
# once per group, the second group passing the template the first resolved so
# both land on the same lattice.

# Returns the canonical tables `.calc_attributable()` takes plus what a caller
# needs to describe the run: the grid template, the C-R config and the model
# label. `conc_cf` is never NULL on the way out: a group without its own
# counterfactual is compared against its own exposure.
.prepare_inputs <- function(crf, calc_fild, conc_real, conc_cf, pop_total,
                            age_struc, mort_rate, scenario = NULL, admin,
                            admin_col, target_res, dgt_coord, dgt_conc,
                            validate, cr_config, mort_lvl, template = NULL) {
  # A map handed in as `calc_fild` is a boundary source, not a table of
  # cells: the grid still comes from the exposure and the map labels it,
  # which is the same route as `admin =`, so the two cannot be combined.
  map_skeleton <- .is_vector_map(calc_fild)
  if (map_skeleton) {
    if (!is.null(admin)) {
      .abort(str_c(
        "Pass the boundaries either as `calc_fild` or as `admin`, not both."
      ))
    }
    admin    <- calc_fild
    calc_fild <- NULL
  }

  config   <- if (is.character(crf)) .as_cr_config(cr_config) else NULL
  crf_name <- if (is.character(crf)) .match_cr_model(crf, config) else
    NA_character_

  # A concentration raster already carries the analysis grid, so it can stand
  # in for `calc_fild` and, when domain calibration is asked for without
  # boundaries, for `admin` as well. Both are read off the input types: there
  # is no switch for them.
  conc_raster <- .is_raster_input(conc_real)
  pop_raster  <- .is_raster_input(pop_total)
  # Only a skeleton the user supplied can be stale; the one taken from a
  # raster `conc_real` below is the grid by construction.
  own_skeleton <- !is.null(calc_fild)

  # ── 1. every path must exist ───────────────────────────────────────
  .check_input_files(
    calc_fild = calc_fild, conc_real = conc_real, conc_cf = conc_cf,
    pop_total = pop_total, age_struc = age_struc, mort_rate = mort_rate,
    admin     = admin
  )

  # ── 2. spatial alignment of the raster inputs ──────────────────────
  spatial <- .align_raster_inputs(conc_real, pop_total, conc_cf, scenario,
                                  target_res, dgt_coord, template = template)

  # ── 3. ingestion and column mapping ────────────────────────────────
  cols <- .map_input_columns(calc_fild, spatial$conc_real, spatial$pop_total,
                             age_struc, mort_rate, spatial$conc_cf,
                             conc_raster, dgt_coord)

  # `mort_lvl` is resolved here, once, so every later stage sees the same
  # column name the tables actually carry.
  mort_lvl <- .resolve_mort_lvl(mort_lvl, cols$mort_rate, cols$calc_fild)

  # ── 4. grid consistency of a supplied skeleton ─────────────────────
  # The rasters define the grid and `calc_fild` is joined onto them by
  # coordinate key, so a skeleton from another grid -- a `build_grid_info()`
  # table reused across resolutions, say -- would silently restrict the
  # analysis to whatever happens to overlap. No key in common means the two
  # grids are different and the call stops; a partial overlap is reported as a
  # warning, because a deliberately coarser table is legal. `validate = "off"`
  # turns both off with the rest of the validation.
  if (validate != "off" && own_skeleton && (conc_raster || pop_raster)) {
    .check_grid_match(
      cols$calc_fild,
      list(if (conc_raster) cols$conc_real, if (pop_raster) cols$pop_total),
      res = if (is.null(spatial$template)) {
        NA_real_
      } else {
        .as_res(terra::res(spatial$template))
      }
    )
  }

  # ── 5. administrative boundaries ───────────────────────────────────
  boundary       <- .default_national_admin(admin, conc_raster, mort_lvl,
                                            cols$mort_rate, cols$calc_fild)
  cols$calc_fild <- .attach_admin(cols$calc_fild, boundary$admin, admin_col,
                                  mort_lvl, cols$mort_rate,
                                  template = spatial$template,
                                  dgt_coord = dgt_coord)
  # How many of the mortality table's domains the labels actually cover: a
  # map whose names do not match `mort_rate` is reported here rather than
  # showing up much later as rows dropped by a join.
  if (!is.null(mort_lvl) && mort_lvl %in% names(cols$calc_fild) &&
      !is.null(cols$mort_rate) && mort_lvl %in% names(cols$mort_rate)) {
    if (boundary$national) {
      .report_boundary_match(cols$calc_fild, cols$mort_rate, mort_lvl)
    } else if (map_skeleton) {
      .report_boundary_match(cols$calc_fild, cols$mort_rate, mort_lvl,
                             source = "`calc_fild` map")
    }
  }

  # ── 6. one scenario per input ──────────────────────────────────────
  extracted <- .extract_scenario(cols$conc_real, cols$pop_total,
                                 cols$age_struc, cols$mort_rate,
                                 cols$conc_cf, scenario, dgt_conc)

  list(calc_fild = cols$calc_fild,
       mort_lvl  = mort_lvl,
       conc_real = extracted$conc_real,
       conc_cf   = if (is.null(extracted$conc_cf)) {
         extracted$conc_real
       } else {
         extracted$conc_cf
       },
       pop_total = extracted$pop_total,
       age_struc = extracted$age_struc,
       mort_rate = extracted$mort_rate,
       template = spatial$template, config = config, crf_name = crf_name,
       conc_raster = conc_raster, pop_raster = pop_raster)
}
