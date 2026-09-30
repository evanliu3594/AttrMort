# Tests for the explicit analysis grid ------------------------------------
#
# `build_grid_info()` renders the grid a `Mortality()` run uses as a table, and
# `Mortality()` checks a skeleton handed back to it against the rasters, so a
# table from another grid cannot be joined silently.
#
# Given  - the shipped example grid, its three fictional countries, and a
#          GeoTIFF pair built from them
# When   - the grid table is built from the rasters and handed back as
#          `calc_fild`
# Then   - all three routes to that grid give the same national totals, the
#          documented columns and attributes come back, and a skeleton from
#          another grid is refused (a partly overlapping one is reported)
#          instead of being used

# A fresh directory below the session temporary directory.
.gi_temp_dir <- function() {
  dir <- tempfile("attrmort-grid-info", tmpdir = tempdir())
  dir.create(dir)
  dir
}

# The example grid is 0.25 degrees with cell centres stored as rounded
# coordinate keys, so snapping the extent back onto the resolution recovers the
# cell edges those centres came from.
.gi_grid_template <- function(info, res = 0.25) {
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

# One value per example cell, placed at its cell centre.
.gi_grid_raster <- function(template, df, value_col) {
  cells  <- terra::cellFromXY(template, as.matrix(df[c("x", "y")]))
  values <- rep(NA_real_, terra::ncell(template))
  values[cells] <- df[[value_col]]
  out <- template
  terra::values(out) <- values
  out
}

# GeoTIFF pair for the shipped example grid. The exposure is stored at the
# concentration-key precision (dgt_conc = 1), so the raster values cannot slip
# across a rounding boundary and miss the lookup table.
.gi_example_tifs <- function(dir) {
  info     <- .attr_data("grid_info")
  exposure <- .attr_data("grid_exposure")
  exposure$base2015 <- round(exposure$base2015, 1)

  template <- .gi_grid_template(info)
  paths <- c(conc = file.path(dir, "exposure.tif"),
             pop  = file.path(dir, "population.tif"))
  suppressWarnings(
    terra::writeRaster(.gi_grid_raster(template, exposure, "base2015"),
                       paths[["conc"]], overwrite = TRUE)
  )
  suppressWarnings(
    terra::writeRaster(.gi_grid_raster(template, .attr_data("grid_pop"),
                                       "base2015"),
                       paths[["pop"]], overwrite = TRUE)
  )
  as.list(paths)
}

# The three fictional countries of the example data are split by longitude at
# 13 and 21 degrees, so three rectangles cover them exactly.
.gi_example_boundaries <- function() {
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

# The info table of the GeoTIFF pair, with the boundaries rasterized onto it.
# `quiet = FALSE` keeps the "written to" message visible to the caller.
.gi_build <- function(tifs, ..., quiet = TRUE) {
  args <- list(conc_real = tifs$conc, pop_total = tifs$pop,
               admin = .gi_example_boundaries(), admin_col = "location",
               target_res = 0.25)
  build <- function() {
    suppressWarnings(do.call(build_grid_info, c(args, list(...))))
  }
  if (quiet) suppressMessages(build()) else build()
}

# National totals in the country order of the example data.
.gi_totals <- function(res) {
  res$total[match(c("Aland", "Borduria", "Cyrenia"), res$location)]
}

# One raster run. Without `calc_fild` the grid comes from the rasters; with the
# info table it comes from the table, and `admin = NULL` is then the right call
# because that table already carries the domain column.
.gi_raster_run <- function(tifs, calc_fild = NULL,
                           admin = .gi_example_boundaries()) {
  args <- list(
    CRF = "GEMM", conc_real = tifs$conc, pop_total = tifs$pop,
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = "off",
    admin = admin, admin_col = "location",
    aggregate = TRUE, aggregate_by = "total"
  )
  if (!is.null(calc_fild)) {
    args$calc_fild <- calc_fild
  }
  suppressWarnings(suppressMessages(do.call(Mortality, args)))
}

# The same run on the shipped wide tables, with `calc_fild` as given.
.gi_tabular_run <- function(calc_fild = .attr_data("grid_info")) {
  suppressWarnings(suppressMessages(Mortality(
    CRF = "GEMM", calc_fild = calc_fild,
    conc_real = .attr_data("grid_exposure"),
    pop_total = .attr_data("grid_pop"),
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = "off",
    aggregate = TRUE, aggregate_by = "total"
  )))
}

describe("build_grid_info() feeding Mortality()", {
  it("gives the same national totals as the tabular and raster-only routes", {
    tifs <- .gi_example_tifs(.gi_temp_dir())

    tabular <- .gi_tabular_run()
    raster  <- .gi_raster_run(tifs)

    gi <- .gi_build(tifs)
    handed <- .gi_raster_run(tifs, calc_fild = gi, admin = NULL)

    expect_setequal(handed$location, tabular$location)
    expect_equal(.gi_totals(raster), .gi_totals(tabular), tolerance = 1e-6)
    expect_equal(.gi_totals(handed), .gi_totals(tabular), tolerance = 1e-6)
  })

  it("returns the documented columns and attributes", {
    tifs <- .gi_example_tifs(.gi_temp_dir())
    gi   <- .gi_build(tifs)

    expect_s3_class(gi, "data.frame")
    expect_equal(names(gi), c("x", "y", "location"))
    expect_false(any(c("conc", "pop", "band_1") %in% names(gi)))
    expect_type(gi$x, "character")
    expect_type(gi$y, "character")

    # the example grid: 100 x 60 cells of 0.25 degree
    expect_equal(nrow(gi), 6000L)
    expect_equal(attr(gi, "n_cells"), 6000L)
    expect_type(attr(gi, "n_cells"), "integer")
    expect_equal(attr(gi, "res"), 0.25, tolerance = 1e-6)
    expect_equal(attr(gi, "dgt_coord"), 2L)
    expect_type(attr(gi, "ext"), "double")
    expect_equal(attr(gi, "ext"), c(5, 30, 35, 50), tolerance = 1e-9)
    expect_type(attr(gi, "crs"), "character")
    expect_match(attr(gi, "crs"), "WGS 84")
  })

  it("errors on a skeleton off the raster grid, and validate = 'off' lets it run", {
    tifs <- .gi_example_tifs(.gi_temp_dir())

    # A skeleton from another grid: the example cells shifted by 0.1 degree,
    # which shares no coordinate key with the 0.25 degree raster grid.
    stale <- .attr_data("grid_info")
    stale$x <- matchable(as.numeric(stale$x) + 0.1, 2)
    stale$y <- matchable(as.numeric(stale$y) + 0.1, 2)

    run <- function(validate) {
      # The uncalibrated branch is the one that can finish on a skeleton with
      # no matching cell at all: the PWRR branch drops every row of an empty
      # coordinate join and reports "No rows survived the join" instead. The
      # guard is what is under test here, not the numbers.
      suppressMessages(Mortality(
        CRF = "GEMM", calc_fild = stale, conc_real = tifs$conc,
        pop_total = tifs$pop, age_struc = .attr_data("national_age_structure"),
        mort_rate = .attr_data("national_mortality"),
        mort_lvl = NULL, scenario = "base2015", validate = validate
      ))
    }

    # Two grids with no key in common cannot be joined at all: the call stops
    # and names both ways of bringing the table onto the raster grid. (The
    # alignment warning of the rasters is not what is under test here.)
    expect_error(
      suppressWarnings(run("warn")),
      "shares no coordinate key"
    )

    # `validate = "off"` turns the check off: the same call completes on the
    # empty coordinate join, as it did before the check existed.
    off <- NULL
    expect_length(
      grep("coordinate key", capture_warnings(off <- run("off")), value = TRUE),
      0L
    )
    expect_s3_class(off, "data.frame")
    expect_gt(nrow(off), 0)
  })

  it("warns without stopping when only part of the skeleton is off the grid", {
    tifs <- .gi_example_tifs(.gi_temp_dir())

    # Half of the example cells shifted by 0.1 degree: those keys leave the
    # raster grid while the other half still joins, which is a partial overlap.
    partial <- .attr_data("grid_info")
    partial$x[1:3000] <- matchable(as.numeric(partial$x[1:3000]) + 0.1, 2)

    warned <- capture_warnings(kept <- suppressMessages(Mortality(
      CRF = "GEMM", calc_fild = partial, conc_real = tifs$conc,
      pop_total = tifs$pop, age_struc = .attr_data("national_age_structure"),
      mort_rate = .attr_data("national_mortality"),
      mort_lvl = "location", scenario = "base2015", validate = "warn"
    )))

    # One warning, carrying the unmatched count and the raster resolution.
    expect_length(grep("3000 of 6000 coordinate key", warned, value = TRUE), 1L)
    expect_length(
      grep("raster grid resolution 0.25 deg", warned, value = TRUE),
      1L
    )

    # Reported, never fatal: the run finishes, on the 3000 cells its keys do
    # reach, so the result is smaller than the full 6000-cell grid.
    expect_s3_class(kept, "data.frame")
    expect_equal(nrow(kept), 3000L)
    expect_lt(nrow(kept), 6000L)
  })

  it("writes the table by extension and returns it either way", {
    dir  <- .gi_temp_dir()
    tifs <- .gi_example_tifs(dir)
    gi   <- .gi_build(tifs)

    rds <- file.path(dir, "grid_info.rds")
    written <- NULL
    messages <- capture_messages(
      written <- .gi_build(tifs, path = rds, quiet = FALSE)
    )
    expect_length(grep("Grid info written to", messages, value = TRUE), 1L)
    expect_equal(written, gi)

    # .rds round-trips the table and its attributes
    reloaded <- readRDS(rds)
    expect_equal(reloaded, gi)
    expect_equal(attr(reloaded, "res"), attr(gi, "res"))
    expect_equal(attr(reloaded, "n_cells"), 6000L)

    csv <- file.path(dir, "grid_info.csv")
    messages <- capture_messages(.gi_build(tifs, path = csv, quiet = FALSE))
    expect_length(grep("Grid info written to", messages, value = TRUE), 1L)

    from_csv <- readr::read_csv(csv, show_col_types = FALSE)
    expect_equal(names(from_csv), names(gi))
    expect_equal(as.character(from_csv$x), as.character(gi$x))
    expect_equal(as.character(from_csv$y), as.character(gi$y))
    expect_equal(as.character(from_csv$location), as.character(gi$location))

    expect_error(.gi_build(tifs, path = file.path(dir, "grid_info.txt")),
                 "Unsupported `path` extension")
  })

  it("builds the info table from a tabular exposure table", {
    info <- .attr_data("grid_info")
    gi   <- build_grid_info(conc_real = info)

    # A tabular exposure table defines the grid through its own coordinates,
    # and keeps a domain column it already carries.
    expect_equal(names(gi), c("x", "y", "location"))
    expect_equal(nrow(gi), nrow(info))
    expect_equal(attr(gi, "n_cells"), 6000L)
    expect_equal(as.numeric(gi$x), info$x)
    expect_equal(as.numeric(gi$y), info$y)
    expect_equal(as.character(gi$location), as.character(info$location))

    # Georeferencing is derived from the cell centres: the nominal 0.25 degree
    # recovered from rounded centres, and no CRS to report.
    expect_equal(attr(gi, "res"), 0.25, tolerance = 1e-3)
    expect_length(attr(gi, "ext"), 4)
    expect_true(is.na(attr(gi, "crs")))

    # No coordinate columns at all is a clear error, not an empty grid.
    expect_error(build_grid_info(conc_real = .attr_data("national_population")),
                 "No grid coordinates")

    # The table stands in for the shipped skeleton it was built from.
    expect_equal(.gi_totals(.gi_tabular_run(calc_fild = gi)),
                 .gi_totals(.gi_tabular_run()),
                 tolerance = 1e-9)
  })
})
