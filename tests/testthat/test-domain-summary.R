# Tests for the domain grain ---------------------------------------------
#
# The analysis grain of Mortality() is the grain of `calc_fild`: one row per
# grid cell, or one row per domain. A domain-only skeleton is a legitimate
# input -- one population-weighted concentration per country is the national
# workflow -- but the two grains do not give the same number. On the grid, a
# domain's PWRR is the population-weighted mean of the relative risks of its
# cells; on a domain-only skeleton it is the relative risk at the domain's
# population-weighted mean concentration. That is a Jensen gap (mean of RR
# against RR of mean), and it is pinned here so that it cannot be dispatched
# away silently.
#
# Given  - the shipped example grid, its three fictional countries, and the
#          domain tables a national-only analysis would run on
# When   - the same exposure is summarised by `domain_summary()` and run at
#          grid grain and at domain grain
# Then   - every summary column matches what plain R computes, the two grains
#          differ by the measured relative amount, the table written to disk
#          round-trips, and every run says which grain it used

# ── local helpers ───────────────────────────────────────────────────────

# A fresh directory below the session temporary directory.
.ds_temp_dir <- function() {
  dir <- tempfile("attrmort-domain-summary", tmpdir = tempdir())
  dir.create(dir)
  dir
}

# Cache for the expensive end-to-end runs: the grid run pushes the shipped
# example through 6000 cells, and several tests read the same result.
.ds_cache <- new.env(parent = emptyenv())

.ds_memo <- function(name, expr) {
  if (!exists(name, envir = .ds_cache, inherits = FALSE)) {
    assign(name, force(expr), envir = .ds_cache)
  }
  get(name, envir = .ds_cache, inherits = FALSE)
}

# The shipped example grid, its exposure and its population. `national_*`
# tables are read through .attr_data(); the wide example is narrowed to one
# scenario wherever a run needs a single value column.
.ds_example_grid <- function() {
  merge(.attr_data("grid_info"), .attr_data("grid_exposure"), by = c("x", "y"))
}

# The domain tables of the national workflow, built from the *raw* example
# files with plain R: per-country population-weighted mean concentration and
# per-country population. Deliberately not built with domain_summary(), so
# that the end-to-end test of the domain-only path stands on its own.
.ds_plain_domains <- function(scenario = "base2015") {
  grid <- .ds_example_grid()
  pop  <- .attr_data("grid_pop")
  d    <- merge(grid, pop, by = c("x", "y"),
                suffixes = c("_conc", "_pop"))

  out <- do.call(rbind, lapply(split(d, d$location), function(z) {
    data.frame(location = z$location[1],
               conc     = weighted.mean(z[[paste0(scenario, "_conc")]],
                                        z[[paste0(scenario, "_pop")]]),
               pop      = sum(z[[paste0(scenario, "_pop")]]))
  }))
  rownames(out) <- NULL
  out[order(out$location), ]
}

# The same three domains, computed by plain R *the way the pipeline sees
# them*: every exposure is rendered as a `dgt_conc = 1` key before anything
# is computed, so the concentration a summary reports is the mean of those
# keys. This is the independent reference for the summary columns.
.ds_reference <- function(scenario = "base2015") {
  grid <- .ds_example_grid()
  pop  <- .attr_data("grid_pop")
  d    <- merge(grid, pop, by = c("x", "y"),
                suffixes = c("_conc", "_pop"))
  conc <- as.numeric(matchable(d[[paste0(scenario, "_conc")]], 1))
  w    <- d[[paste0(scenario, "_pop")]]

  out <- do.call(rbind, lapply(split(seq_len(nrow(d)), d$location), function(i) {
    data.frame(location  = d$location[i][1],
               conc_pwe  = weighted.mean(conc[i], w[i]),
               conc_mean = mean(conc[i]),
               pop_total = sum(w[i]),
               n_cells   = length(i))
  }))
  rownames(out) <- NULL
  out[order(out$location), ]
}

# The argument list of the shipped-example summary, `path` left out.
.ds_args <- function() {
  list(conc_real = .ds_example_grid(),
       pop_total = .attr_data("grid_pop"),
       scenario  = "base2015")
}

.ds_summary <- function() {
  .ds_memo("summary", suppressMessages(do.call(domain_summary, .ds_args())))
}

# One Mortality() run at grid grain: the shipped 6000-cell grid, calibrated
# per domain. `validate` is the switch that decides whether the run talks.
.ds_grid_call <- function(validate = "warn", aggregate = NULL) {
  suppressWarnings(Mortality(
    CRF = "GEMM", calc_fild = .attr_data("grid_info"),
    conc_real = .attr_data("grid_exposure"), pop_total = .attr_data("grid_pop"),
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = validate,
    aggregate = aggregate
  ))
}

# The grid run, aggregated to the domain totals a national number is read off.
.ds_grid_totals <- function() {
  .ds_memo("grid_totals", .ds_grid_call(validate = "off", aggregate = TRUE))
}

# The national workflow of the README: the three rows of domain_summary()
# handed back to Mortality() as a domain-only skeleton. One row per domain,
# so the run evaluates one relative risk per domain.
.ds_domain_call <- function(ds, validate = "warn") {
  suppressWarnings(Mortality(
    CRF = "GEMM", calc_fild = data.frame(location = ds$location),
    conc_real = data.frame(location = ds$location, base2015 = ds$conc_pwe),
    pop_total = data.frame(location = ds$location, base2015 = ds$pop_total),
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = validate,
    aggregate = TRUE
  ))
}

.ds_domain_totals <- function() {
  .ds_memo("domain_totals", .ds_domain_call(.ds_summary(), validate = "off"))
}

# Totals in the country order of the example data.
.ds_totals_of <- function(res) {
  res$total[match(c("Aland", "Borduria", "Cyrenia"), res$location)]
}

# A four-cell grid in which nothing carries a domain column: the mortality
# rate and the age structure are keyed by cell, which is the only way the
# uncalibrated branch can run without a domain.
.ds_grid_only <- function() {
  fld <- data.frame(x = c("0", "1", "0", "1"), y = c("0", "0", "1", "1"))
  list(
    calc_fild = fld,
    conc_real = data.frame(fld, conc = c("10", "20", "30", "40")),
    pop_total = data.frame(fld, pop = c(100, 200, 300, 400)),
    age_struc = merge(fld, data.frame(age = c("25", "30"), prop = c(0.5, 0.5))),
    mort_rate = merge(fld, data.frame(age = "25", endpoint = "ncd+lri",
                                      mortrate = 1000))
  )
}

.ds_grid_only_call <- function(validate = "warn", mort_lvl = NULL) {
  d <- .ds_grid_only()
  suppressWarnings(Mortality(
    CRF = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
    pop_total = d$pop_total, age_struc = d$age_struc, mort_rate = d$mort_rate,
    mort_lvl = mort_lvl, validate = validate
  ))
}

# The `Analysis grain:` lines of one run. The rest of the pipeline's chatter
# (column mapping, dplyr's join notices) is not what is under test here, and
# `message()` appends a newline that the line itself does not carry.
.ds_grain_lines <- function(expr) {
  msgs <- capture_messages(res <- force(expr))
  trimws(grep("Analysis grain:", msgs, value = TRUE))
}

# The 0.25 degree template of the shipped example grid: 100 x 60 cells.
# Snapping the extent back onto the resolution is what recovers the cell
# edges from the rounded cell centres.
.ds_template <- function(res = 0.25) {
  info <- .attr_data("grid_info")
  snap <- function(v) round(v / res) * res
  xs <- sort(unique(as.numeric(info$x)))
  ys <- sort(unique(as.numeric(info$y)))

  template <- terra::rast(
    nrows = length(ys), ncols = length(xs),
    xmin = snap(min(xs) - res / 2), xmax = snap(max(xs) + res / 2),
    ymin = snap(min(ys) - res / 2), ymax = snap(max(ys) + res / 2)
  )
  terra::crs(template) <- "EPSG:4326"
  template
}

# One value per example cell, placed at its cell centre. `round_to` is used
# for the exposure: a raster has to store values already at the concentration
# key's precision, or Float32 noise can push one across a rounding boundary
# and make it miss the lookup table.
.ds_raster <- function(df, col, round_to = NA_real_,
                       template = .ds_template()) {
  v <- df[[col]]
  if (!is.na(round_to)) {
    v <- round(v, round_to)
  }
  cells  <- terra::cellFromXY(template, as.matrix(df[c("x", "y")]))
  values <- rep(NA_real_, terra::ncell(template))
  values[cells] <- v

  out <- template
  terra::values(out) <- values
  out
}

# The three fictional countries are split by longitude at 13 and 21 degrees,
# so three rectangles cover the example grid exactly.
.ds_boundaries <- function() {
  band <- function(xmin, xmax, location) {
    sf::st_sf(
      location = location,
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(xmin, 35), c(xmax, 35), c(xmax, 50),
                                  c(xmin, 50), c(xmin, 35)))),
        crs = 4326
      )
    )
  }
  rbind(band(5, 13, "Aland"), band(13, 21, "Borduria"), band(21, 30, "Cyrenia"))
}

# ── the measured grains ─────────────────────────────────────────────────
#
# Read off the shipped example data, in the country order of the example.
# They are the regression anchor of this file: a change in either number
# means the grain of one of the two paths moved, and `rel` is the Jensen gap
# between them (mean of RR against RR of mean). Quoted to enough digits that
# any drift shows up; `rel` is (domain - grid) / grid.
.ds_measured <- list(
  grid   = c(Aland = 13908.9100620534, Borduria = 25847.8546879926,
             Cyrenia = 18426.8476893385),
  domain = c(Aland = 13921.9018415047, Borduria = 25857.9077349357,
             Cyrenia = 18425.9527744127),
  rel    = c(Aland = 9.34061647776498e-04, Borduria = 3.88931579215588e-04,
             Cyrenia = -4.85658177082846e-05)
)

describe("domain_summary()", {
  it("reduces the example grid to one row per domain", {
    ds <- .ds_summary()
    ref <- .ds_reference()

    # the documented columns, in the documented order
    expect_s3_class(ds, "data.frame")
    expect_equal(names(ds),
                 c("location", "conc_pwe", "conc_mean", "pop_total", "n_cells"))
    expect_equal(nrow(ds), 3L)
    expect_setequal(ds$location, c("Aland", "Borduria", "Cyrenia"))

    # every column, against plain R on the same cells
    expect_equal(ds$location, ref$location)
    expect_equal(ds$conc_pwe, ref$conc_pwe, tolerance = 1e-12)
    expect_equal(ds$conc_mean, ref$conc_mean, tolerance = 1e-12)
    expect_equal(ds$pop_total, ref$pop_total, tolerance = 1e-12)
    expect_equal(ds$n_cells, ref$n_cells)
    expect_type(ds$n_cells, "integer")

    # the population-weighted mean is the one the pipeline itself reports,
    # so a summary and an aggregated run cannot disagree about it
    grid <- .ds_grid_totals()
    expect_equal(ds$conc_pwe,
                 grid$conc_pwe[match(ds$location, grid$location)],
                 tolerance = 1e-12)

    # the contrast the column exists for: on this data the unweighted mean
    # sits below the population-weighted one in every country
    expect_true(all(ds$conc_mean != ds$conc_pwe))
    expect_true(all(abs(ds$conc_mean - ds$conc_pwe) > 1e-3))

    # the shipped example: 1920 / 1920 / 2160 cells and the national
    # populations, which the example's own population table also carries
    expect_equal(ds$n_cells, c(1920L, 1920L, 2160L))
    expect_equal(ds$pop_total, .attr_data("national_population")$base2015[
      match(ds$location, .attr_data("national_population")$location)
    ], tolerance = 1e-12)
  })

  it("labels the domains from boundaries rasterized onto the grid", {
    ds <- .ds_summary()

    # The raster route of Mortality(): the boundaries are rasterized onto the
    # grid the exposure raster brings with it. `mort_lvl` is the name the
    # domain column takes, as it is in Mortality().
    by_admin <- suppressWarnings(suppressMessages(domain_summary(
      conc_real = .ds_raster(.attr_data("grid_exposure"), "base2015",
                             round_to = 1),
      pop_total = .ds_raster(.attr_data("grid_pop"), "base2015"),
      admin     = .ds_boundaries(), admin_col = "location",
      mort_lvl  = "iso3", target_res = 0.25
    )))

    expect_equal(names(by_admin)[1], "iso3")
    expect_equal(as.character(by_admin$iso3), ds$location)
    expect_equal(by_admin$pop_total, ds$pop_total, tolerance = 1e-9)
    expect_equal(by_admin$n_cells, ds$n_cells)
    # The raster route resamples the exposure onto its own cell centres, so
    # the concentrations agree well below the 0.1 concentration-key step
    # rather than bit for bit.
    expect_equal(by_admin$conc_pwe, ds$conc_pwe, tolerance = 1e-3)
  })

  it("refuses to summarise an input with no domain column, and says why", {
    expect_error(
      domain_summary(conc_real = .attr_data("grid_exposure"),
                     pop_total = .attr_data("grid_pop"),
                     scenario  = "base2015"),
      "No domain column in `conc_real`"
    )

    # Pinned as it stands today: boundaries are rasterized onto a template
    # built from the coordinate range when no raster defines the grid, and
    # that template does not coincide with the tabular cell centres, so every
    # label comes back NA. Reported instead of being summarised as one
    # unnamed domain; a fix to the tabular rasterization would turn this into
    # a passing summary and this expectation into its counterpart.
    expect_error(
      suppressMessages(domain_summary(
        conc_real = .ds_example_grid(), pop_total = .attr_data("grid_pop"),
        admin = .ds_boundaries(), admin_col = "location", target_res = 0.25,
        scenario = "base2015"
      )),
      "labelled no cell"
    )
  })

  it("writes the table by extension and returns it either way", {
    dir <- .ds_temp_dir()
    ds  <- .ds_summary()

    rds <- file.path(dir, "domain_summary.rds")
    messages <- capture_messages(
      written <- do.call(domain_summary, c(.ds_args(), list(path = rds)))
    )
    expect_length(grep("Domain summary written to", messages, value = TRUE), 1L)
    expect_equal(written, ds)
    expect_equal(readRDS(rds), ds)

    csv <- file.path(dir, "domain_summary.csv")
    messages <- capture_messages(
      do.call(domain_summary, c(.ds_args(), list(path = csv)))
    )
    expect_length(grep("Domain summary written to", messages, value = TRUE), 1L)

    from_csv <- readr::read_csv(csv, show_col_types = FALSE)
    expect_equal(names(from_csv), names(ds))
    expect_equal(as.character(from_csv$location), as.character(ds$location))
    expect_equal(from_csv$conc_pwe, ds$conc_pwe, tolerance = 1e-9)
    expect_equal(from_csv$pop_total, ds$pop_total, tolerance = 1e-9)
    expect_equal(from_csv$n_cells, ds$n_cells)

    expect_error(
      do.call(domain_summary,
              c(.ds_args(), list(path = file.path(dir, "ds.txt")))),
      "Unsupported `path` extension"
    )
  })
})

describe("the domain grain of Mortality()", {
  it("runs a domain-only skeleton end to end, one row per domain", {
    dom <- .ds_plain_domains()

    res <- .ds_memo("plain_domain_run", suppressWarnings(suppressMessages(
      Mortality(
        CRF = "GEMM", calc_fild = data.frame(location = dom$location),
        conc_real = data.frame(location = dom$location, base2015 = dom$conc),
        pop_total = data.frame(location = dom$location, base2015 = dom$pop),
        age_struc = .attr_data("national_age_structure"),
        mort_rate = .attr_data("national_mortality"),
        mort_lvl  = "location", scenario = "base2015", validate = "off"
      )
    )))

    # One row per domain, keyed by the domain column and nothing else: no
    # coordinate key anywhere, so no phase may assume one.
    expect_s3_class(res, "data.frame")
    expect_equal(nrow(res), 3L)
    expect_equal(ncol(res), 16L)
    expect_equal(names(res)[1], "location")
    expect_setequal(res$location, dom$location)
    expect_false(any(c("x", "y") %in% names(res)))

    # The burden of the domain grain, from the plain-R domain tables.
    totals <- .ds_totals_of(data.frame(location = res$location,
                                       total = rowSums(
                                         as.matrix(res[, names(res) != "location"])
                                       )))
    expect_true(all(is.finite(totals)))
    expect_equal(unname(totals), unname(.ds_measured$domain), tolerance = 1e-9)
  })

  it("keeps the two grains apart by the measured Jensen gap", {
    grid   <- .ds_grid_totals()
    domain <- .ds_domain_totals()

    grid_total   <- .ds_totals_of(grid)
    domain_total <- .ds_totals_of(domain)

    # (i) both grains produce a number
    expect_true(all(is.finite(grid_total)))
    expect_true(all(is.finite(domain_total)))
    expect_true(all(grid_total > 0))
    expect_true(all(domain_total > 0))

    # (ii) and they are not the same number: the grid path calibrates on the
    # population-weighted mean of the relative risks of a domain's cells, the
    # domain path on the relative risk at the domain's population-weighted
    # mean concentration
    expect_false(isTRUE(all.equal(unname(grid_total), unname(domain_total))))
    expect_true(all(domain_total != grid_total))

    # (iii) by the measured amount. Relative differences measured on the
    # shipped example data, country by country (see .ds_measured above):
    #   Aland     +9.34061647776498e-04
    #   Borduria  +3.88931579215588e-04
    #   Cyrenia   -4.85658177082846e-05
    # The gap is the Jensen difference alone: the concentration-response
    # tables are keyed at `dgt_conc = 1`, so re-rendering a domain mean as a
    # key (Aland: 24.2220960 -> 24.2) looks the same relative risk up again.
    # A change here means one of the two grains moved.
    rel <- (domain_total - grid_total) / grid_total
    expect_equal(unname(grid_total), unname(.ds_measured$grid),
                 tolerance = 1e-9)
    expect_equal(unname(domain_total), unname(.ds_measured$domain),
                 tolerance = 1e-9)
    expect_equal(unname(rel), unname(.ds_measured$rel), tolerance = 1e-6)

    # The national total carries the same gap, and it is small but non-zero.
    national <- (sum(domain_total) - sum(grid_total)) / sum(grid_total)
    expect_true(is.finite(national))
    expect_gt(abs(national), 0)
    expect_lt(abs(national), 1e-2)
  })

  it("says which grain it used, once per run", {
    # grid grain: many cells over a few domains, calibrated inside each one
    expect_equal(
      .ds_grain_lines(.ds_grid_call(validate = "warn")),
      paste0("Analysis grain: 6000 cell(s) in 3 domain(s) on a 0.25 deg grid; ",
             "PWRR calibrated per domain.")
    )

    # domain grain: one row per domain, so PWRR has nothing to average over
    expect_equal(
      .ds_grain_lines(.ds_domain_call(.ds_summary(), validate = "warn")),
      paste0("Analysis grain: 3 domain(s) with one row each; PWRR reduces to ",
             "a single RR evaluation per domain (domain-level burden).")
    )

    # no domain at all: the uncalibrated branch, which is the only one that
    # can run on a skeleton carrying no domain column
    expect_equal(
      .ds_grain_lines(.ds_grid_only_call(validate = "warn")),
      paste0("Analysis grain: 4 cell(s) with no domain column; ",
             "grid-level PAF without calibration.")
    )

    # a `mort_lvl` that is not a column of `mort_rate`: the whole field is
    # one calibration unit, which is a different branch again
    expect_equal(
      .ds_grain_lines(.ds_grid_only_call(validate = "warn",
                                         mort_lvl = "nonexistent")),
      paste0("Analysis grain: 4 cell(s) with no domain column; PWRR ",
             "calibrated on the whole field (`mort_lvl` is not a column of ",
             "`mort_rate`).")
    )

    # the same three runs, quiet: `validate = "off"` silences the line with
    # the rest of the validation
    expect_length(.ds_grain_lines(.ds_grid_only_call(validate = "off")), 0L)
    expect_length(.ds_grain_lines(.ds_domain_call(.ds_summary(),
                                                  validate = "off")), 0L)
  })
})
