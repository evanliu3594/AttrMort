# Tests for the grid-native raster path ---------------------------------
#
# A raster concentration input already carries the analysis grid, so the
# attribution field can be derived from it (`calc_fild = NULL`), national
# boundaries can stand in for a boundary file (`admin = NULL`), and the age
# strata can be computed in blocks (`chunk_ages`). All three are driven by
# the input types alone -- there is no switch to set.
#
# Given  - the shipped example grid, its three fictional countries, and a
#          GeoTIFF/netCDF pair built from them
# When   - mortality() is called on the raster inputs
# Then   - it returns what the tabular call returns

# A fresh directory below the session temporary directory.
.attr_temp_dir <- function() {
  dir <- tempfile("attrmort-grid", tmpdir = tempdir())
  dir.create(dir)
  dir
}

# The example grid is 0.25 degrees with cell centres stored as rounded
# coordinate keys, so snapping the extent back onto the resolution recovers
# the cell edges those centres came from.
.attr_grid_template <- function(info, res = 0.25) {
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
.attr_grid_raster <- function(template, df, value_col) {
  cells  <- terra::cellFromXY(template, as.matrix(df[c("x", "y")]))
  values <- rep(NA_real_, terra::ncell(template))
  values[cells] <- df[[value_col]]
  out <- template
  terra::values(out) <- values
  out
}

# GeoTIFF pair for the shipped example grid. The exposure is stored at the
# concentration-key precision (dgt_conc = 1): raster values carry about 1e-6
# relative error, which would push the cells sitting just below a .x5
# boundary onto the other side of the rounding the join keys use -- and those
# cells would then miss the lookup table.
.attr_example_tifs <- function(dir) {
  info     <- .attr_data("grid_info")
  exposure <- .attr_data("grid_exposure")
  exposure$base2015 <- round(exposure$base2015, 1)

  template <- .attr_grid_template(info)
  paths <- c(conc = file.path(dir, "exposure.tif"),
             pop  = file.path(dir, "population.tif"))
  terra::writeRaster(.attr_grid_raster(template, exposure, "base2015"),
                     paths[["conc"]], overwrite = TRUE)
  terra::writeRaster(.attr_grid_raster(template, .attr_data("grid_pop"),
                                       "base2015"),
                     paths[["pop"]], overwrite = TRUE)
  as.list(paths)
}

# The three fictional countries of the example data are split by longitude at
# 13 and 21 degrees, so three rectangles cover them exactly.
.attr_example_boundaries <- function() {
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

# National totals (one row per location) from the shipped tables.
.attr_tabular_totals <- function() {
  suppressWarnings(suppressMessages(mortality(
    crf = "GEMM", calc_fild = .attr_data("grid_info"),
    conc_real = .attr_data("grid_exposure"),
    pop_total = .attr_data("grid_pop"),
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = "off",
    aggregate = TRUE, aggregate_by = "total"
  )))
}

# The same run with no attribution field: the grid comes from the exposure
# raster, the domains from the rasterized boundaries.
.attr_raster_totals <- function(conc, pop,
                                admin = .attr_example_boundaries(), ...) {
  suppressWarnings(suppressMessages(mortality(
    crf = "GEMM", conc_real = conc, pop_total = pop,
    age_struc = .attr_data("national_age_structure"),
    mort_rate = .attr_data("national_mortality"),
    mort_lvl = "location", scenario = "base2015", validate = "off",
    admin = admin, admin_col = "location",
    aggregate = TRUE, aggregate_by = "total", ...
  )))
}

describe("mortality() on raster inputs without calc_fild", {
  it("reproduces the tabular national totals from a GeoTIFF pair", {
    tifs <- .attr_example_tifs(.attr_temp_dir())

    raster  <- .attr_raster_totals(tifs$conc, tifs$pop)
    tabular <- .attr_tabular_totals()

    expect_setequal(raster$location, tabular$location)
    expect_equal(raster$total[match(tabular$location, raster$location)],
                 tabular$total, tolerance = 1e-6)
  })

  it("takes a single-band raster without a `scenario`", {
    tifs <- .attr_example_tifs(.attr_temp_dir())

    # One band covers the whole field, so no scenario name is needed: the value
    # column is named after the canonical `conc` / `pop`. The age and mortality
    # tables then have to be long already, since `scenario =` is what extracts
    # a column from a wide table.
    age <- dplyr::select(.attr_data("national_age_structure"),
                         location, age, prop = base2015)
    mort <- dplyr::select(.attr_data("national_mortality"),
                          location, age, endpoint, mortrate = base2015)

    blank <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", conc_real = tifs$conc, pop_total = tifs$pop,
      age_struc = age, mort_rate = mort,
      mort_lvl = "location", validate = "off",
      admin = .attr_example_boundaries(), admin_col = "location",
      aggregate = TRUE, aggregate_by = "total"
    )))

    tabular <- .attr_tabular_totals()
    expect_setequal(blank$location, tabular$location)
    # Looser than the GeoTIFF test above: the wide-table path renormalises the
    # age proportions inside each domain (.slice_age()), a long table does not.
    expect_equal(blank$total[match(tabular$location, blank$location)],
                 tabular$total, tolerance = 1e-4)
  })

  it("keeps the uncalibrated grid level when boundaries are supplied", {
    tifs <- .attr_example_tifs(.attr_temp_dir())

    grid <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", conc_real = tifs$conc, pop_total = tifs$pop,
      age_struc = .attr_data("national_age_structure"),
      mort_rate = .attr_data("national_mortality"),
      mort_lvl = NULL, scenario = "base2015", validate = "off",
      admin = .attr_example_boundaries(), admin_col = "location"
    )))

    # `mort_lvl = NULL` stays the uncalibrated branch: one row per cell, no
    # national boundaries rasterized behind the user's back.
    expect_equal(nrow(grid), 6000)
    expect_true(all(c("x", "y", "location", "ncd+lri_25", "ncd+lri_95") %in%
                      names(grid)))
  })

  it("takes the grid from a tabular exposure, then asks for the domains", {
    # `calc_fild = NULL` with a coordinate-bearing table is allowed: the grid is
    # the exposure's own cells. What a coordinate-only skeleton cannot do is
    # carry the domain-keyed inputs, and that is what is reported -- with the
    # `admin =` hint rather than a bare "shares no join key".
    long <- .attr_small_long()
    expect_error(
      suppressWarnings(suppressMessages(mortality(
        crf = "GEMM", conc_real = long$conc_real, pop_total = long$pop_total,
        age_struc = long$age_struc, mort_rate = long$mort_rate,
        mort_lvl = "location"
      ))),
      "Pass `admin =`"
    )
  })

  it("stops when the tabular exposure has no coordinates to derive a grid from", {
    long <- .attr_small_long()
    domain_only <- long$age_struc          # one row per domain: no grid
    expect_error(
      mortality(
        crf = "GEMM", conc_real = domain_only, pop_total = long$pop_total,
        age_struc = long$age_struc, mort_rate = long$mort_rate,
        mort_lvl = "location"
      ),
      "needs a `conc_real` that carries coordinates"
    )
  })

  it("says so when nothing supplies a domain column", {
    tifs <- .attr_example_tifs(.attr_temp_dir())
    expect_error(
      suppressWarnings(mortality(
        crf = "GEMM", conc_real = tifs$conc, pop_total = tifs$pop,
        age_struc = .attr_data("national_age_structure"),
        mort_rate = .attr_data("national_mortality"),
        mort_lvl = NULL, scenario = "base2015", validate = "off"
      )),
      "shares no join key"
    )
  })
})

describe("mortality() national boundary default", {
  it("is the same run as passing those boundaries explicitly", {
    skip_if_not_installed("rnaturalearth")
    borders <- try(
      suppressWarnings(rnaturalearth::ne_countries(scale = 110,
                                                   returnclass = "sf")),
      silent = TRUE
    )
    skip_if(inherits(borders, "try-error"),
            "national boundaries are not available offline")

    # A coarse grid over metropolitan France, whose cells are all inside one
    # country, so the run needs a single domain of `mort_rate`.
    dir <- .attr_temp_dir()
    template <- terra::rast(nrows = 8, ncols = 8, xmin = 1, xmax = 5,
                            ymin = 44, ymax = 48)
    terra::crs(template) <- "EPSG:4326"
    terra::values(template) <- 10
    conc <- file.path(dir, "conc.tif")
    pop  <- file.path(dir, "pop.tif")
    terra::writeRaster(template, conc, overwrite = TRUE)
    terra::writeRaster(template, pop, overwrite = TRUE)

    age  <- data.frame(location = "France", age = c("25", "30"),
                       base2015 = c(0.5, 0.5))
    mort <- data.frame(location = "France", age = c("25", "30"),
                       endpoint = "ncd+lri", base2015 = c(1000, 2000))
    run <- function(admin) {
      suppressWarnings(suppressMessages(mortality(
        crf = "GEMM", conc_real = conc, pop_total = pop, age_struc = age,
        mort_rate = mort, mort_lvl = "location", scenario = "base2015",
        target_res = 0.5, validate = "off",
        aggregate = TRUE, aggregate_by = "total", admin = admin
      )))
    }

    default <- run(NULL)

    expect_equal(default$location, "France")
    # `admin =` overrides the default level, and the two agree when they name
    # the same boundaries.
    expect_equal(default, run(borders), tolerance = 1e-12)
  })
})

describe("mortality() with boundaries on a tabular grid", {
  it("labels the table's cells from the boundaries", {
    # The table's coordinate keys are rounded, so a regular raster lattice
    # cannot reproduce its cell centres; the boundaries are joined to the
    # cells point-in-polygon instead. The labels have to agree with the ones
    # the table carries itself.
    grid <- .attr_data("grid_info")[, c("x", "y")]
    run <- function(calc_fild) {
      suppressWarnings(suppressMessages(mortality(
        crf = "GEMM", calc_fild = calc_fild,
        conc_real = .attr_data("grid_exposure"),
        pop_total = .attr_data("grid_pop"),
        age_struc = .attr_data("national_age_structure"),
        mort_rate = .attr_data("national_mortality"),
        mort_lvl = "location", scenario = "base2015", validate = "off",
        admin = .attr_example_boundaries(), admin_col = "location",
        aggregate = TRUE, aggregate_by = "total"
      )))
    }

    expect_equal(run(grid), .attr_tabular_totals(), tolerance = 1e-12)
  })

  it("accepts a lon/lat coordinate pair instead of x/y", {
    # `.grid_xy()` recognises the lon/lat spelling, so the boundary join has
    # to map it onto the x/y keys the label table carries rather than reject
    # the skeleton.
    rename_xy <- function(tbl) {
      names(tbl)[names(tbl) == "x"] <- "lon"
      names(tbl)[names(tbl) == "y"] <- "lat"
      tbl
    }
    grid <- rename_xy(.attr_data("grid_info")[, c("x", "y")])

    out <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", calc_fild = grid,
      conc_real = rename_xy(.attr_data("grid_exposure")),
      pop_total = rename_xy(.attr_data("grid_pop")),
      age_struc = .attr_data("national_age_structure"),
      mort_rate = .attr_data("national_mortality"),
      mort_lvl = "location", scenario = "base2015", validate = "off",
      admin = .attr_example_boundaries(), admin_col = "location",
      aggregate = TRUE, aggregate_by = "total"
    )))

    expect_equal(out, .attr_tabular_totals(), tolerance = 1e-12)
  })

  it("reports boundaries that label no cell of the grid", {
    grid <- .attr_data("grid_info")[, c("x", "y")]
    far <- sf::st_sf(
      location = "Nowhere",
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
        crs = 4326
      )
    )

    expect_error(
      suppressWarnings(suppressMessages(mortality(
        crf = "GEMM", calc_fild = grid,
        conc_real = .attr_data("grid_exposure"),
        pop_total = .attr_data("grid_pop"),
        age_struc = .attr_data("national_age_structure"),
        mort_rate = .attr_data("national_mortality"),
        mort_lvl = "location", scenario = "base2015", validate = "off",
        admin = far, admin_col = "location"
      ))),
      "labelled no cell"
    )
  })
})

describe("mortality() age chunking", {
  it("gives the same result with one age per pass as with all ages", {
    base <- list(
      crf = "GEMM", calc_fild = .attr_data("grid_info"),
      conc_real = .slice_conc(.attr_data("grid_exposure"), "base2015"),
      pop_total = .slice_pop(.attr_data("grid_pop"), "base2015"),
      age_struc = .slice_age(.attr_data("national_age_structure"), "base2015"),
      mort_rate = .slice_mort(.attr_data("national_mortality"), "base2015"),
      mort_lvl = "location", validate = "off"
    )
    run <- function(...) {
      suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
    }

    expect_equal(run(chunk_ages = 1), run(), tolerance = 1e-12)
    expect_equal(run(chunk_ages = 4), run(), tolerance = 1e-12)
  })

  it("drops an age block the age structure does not carry", {
    # A GBD age structure can lack a stratum the CRF and `mort_rate` both
    # carry. That age is absent from the unchunked result, and a chunk that
    # contains only such ages must be skipped instead of aborting the run.
    age <- .slice_age(.attr_data("national_age_structure"), "base2015")
    base <- list(
      crf = "GEMM", calc_fild = .attr_data("grid_info"),
      conc_real = .slice_conc(.attr_data("grid_exposure"), "base2015"),
      pop_total = .slice_pop(.attr_data("grid_pop"), "base2015"),
      age_struc = age[age$age != "95", ],
      mort_rate = .slice_mort(.attr_data("national_mortality"), "base2015"),
      mort_lvl = "location", validate = "off"
    )
    run <- function(...) {
      suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
    }

    whole <- run()
    expect_false(any(grepl("_95$", names(whole))))
    for (size in c(1L, 2L, 5L)) {
      expect_equal(run(chunk_ages = size), whole, tolerance = 1e-12)
    }
  })

  it("still reports an empty join when no age can contribute", {
    base <- list(
      crf = "GEMM", calc_fild = .attr_data("grid_info"),
      conc_real = .slice_conc(.attr_data("grid_exposure"), "base2015"),
      pop_total = .slice_pop(.attr_data("grid_pop"), "base2015"),
      age_struc = .slice_age(.attr_data("national_age_structure"), "base2015")[0, ],
      mort_rate = .slice_mort(.attr_data("national_mortality"), "base2015"),
      mort_lvl = "location", validate = "off"
    )
    run <- function(...) {
      suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
    }

    whole  <- tryCatch(run(), error = function(e) conditionMessage(e))
    chunked <- tryCatch(run(chunk_ages = 1L), error = function(e) conditionMessage(e))
    expect_match(whole, "No rows survived")
    expect_identical(chunked, whole)
  })

  it("is exact for a multi-endpoint CRF, column order included", {
    base <- list(
      crf = "MRBRT", calc_fild = .attr_data("grid_info"),
      conc_real = .slice_conc(.attr_data("grid_exposure"), "base2015"),
      pop_total = .slice_pop(.attr_data("grid_pop"), "base2015"),
      age_struc = .slice_age(.attr_data("national_age_structure"), "base2015"),
      mort_rate = .slice_mort(.attr_data("national_mortality"), "base2015"),
      mort_lvl = "location", validate = "off"
    )
    run <- function(...) {
      suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
    }

    whole <- run()
    # 6 endpoints x 15 age strata, i.e. several age blocks per endpoint
    expect_length(setdiff(names(whole), c("x", "y", "location")), 90)
    expect_equal(run(chunk_ages = 3), whole, tolerance = 1e-12)
  })

  it("sizes the pass from the problem when chunk_ages is NULL", {
    # 15 ages over 6.48e6 cells (a global 0.1 degree grid) cannot stay in one
    # pass, but a few ages can; a small grid keeps all of them together.
    expect_equal(AttrMort:::.resolve_chunk_ages(NULL, 6000, 15, 1), 15)
    expect_equal(AttrMort:::.resolve_chunk_ages(NULL, 6.48e6, 15, 1), 5)
    expect_equal(AttrMort:::.resolve_chunk_ages(NULL, 6.48e6, 75, 5), 1)
    expect_equal(AttrMort:::.resolve_chunk_ages(4, 6000, 15, 1), 4)
  })

  it("rejects a chunk size that is not a positive number of strata", {
    expect_error(
      mortality(crf = "GEMM", conc_real = 1, pop_total = 1, age_struc = 1,
               mort_rate = 1, chunk_ages = 0),
      "chunk_ages"
    )
  })
})

describe("mortality() on netCDF exposure", {
  it("recognises .nc as a raster path", {
    expect_true(AttrMort:::.is_raster_path("x.nc"))
  })

  it("reproduces the GeoTIFF national totals from a netCDF layer", {
    skip_if_not(requireNamespace("ncdf4", quietly = TRUE),
                "ncdf4 is not installed")

    dir  <- .attr_temp_dir()
    tifs <- .attr_example_tifs(dir)
    nc   <- file.path(dir, "exposure.nc")
    terra::writeCDF(terra::rast(tifs$conc), nc, varname = "base2015",
                    overwrite = TRUE, prec = "double")

    from_nc  <- .attr_raster_totals(nc, tifs$pop)
    from_tif <- .attr_raster_totals(tifs$conc, tifs$pop)

    expect_setequal(from_nc$location, from_tif$location)
    expect_equal(from_nc$total[match(from_tif$location, from_nc$location)],
                 from_tif$total, tolerance = 1e-6)
  })
})
