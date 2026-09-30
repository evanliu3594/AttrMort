# Tests for the raster ingestion layer

.make_raster <- function(nrows, ncols, value = 1, xmin = 0, xmax = 12,
                         ymin = 0, ymax = 12) {
  r <- terra::rast(nrows = nrows, ncols = ncols, xmin = xmin, xmax = xmax,
                   ymin = ymin, ymax = ymax)
  terra::values(r) <- value
  terra::crs(r) <- "EPSG:4326"
  r
}

describe("raster_to_grid()", {
  it("returns rounded character coordinates and one column per band", {
    r <- .make_raster(4, 4, 1:16)
    out <- AttrMort:::raster_to_grid(r, band_names = "base2015", dgt = 1)

    expect_equal(names(out), c("x", "y", "base2015"))
    expect_type(out$x, "character")
    expect_equal(nrow(out), 16)
  })

  it("reads values from a SpatRaster, not just from a path", {
    # Regression: terra::rast(<SpatRaster>) returns an empty template, which
    # silently produced zero rows for every aligned raster.
    r <- .make_raster(2, 2, c(1, 2, 3, 4))
    out <- AttrMort:::raster_to_grid(r, band_names = "v")
    expect_equal(nrow(out), 4)
    expect_equal(sort(out$v), c(1, 2, 3, 4))
  })

  it("falls back to band_N for rasters without layer names", {
    r <- .make_raster(2, 2, 1)
    expect_equal(names(AttrMort:::raster_to_grid(r)),
                 c("x", "y", "band_1"))
  })

  it("keeps meaningful layer names", {
    r <- .make_raster(2, 2, 1)
    names(r) <- "base2015"
    expect_equal(names(AttrMort:::raster_to_grid(r)),
                 c("x", "y", "base2015"))
  })

  it("rejects a band-name vector of the wrong length", {
    r <- .make_raster(2, 2)
    expect_error(AttrMort:::raster_to_grid(r, band_names = c("a", "b")),
                 "does not match")
  })
})

describe(".aggregate_pop()", {
  it("conserves the total when the resolutions are an exact multiple", {
    fine <- .make_raster(12, 12, 1)          # 1 degree cells, total = 144
    coarse <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 12,
                          ymin = 0, ymax = 12)
    terra::crs(coarse) <- "EPSG:4326"

    out <- AttrMort:::.aggregate_pop(fine, coarse)
    expect_equal(terra::global(out, fun = "sum", na.rm = TRUE)[[1]], 144)
  })

  it("warns when the resolutions are not a clean multiple", {
    fine <- .make_raster(12, 12, 1)
    odd <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 12,
                       ymin = 0, ymax = 12)
    terra::crs(odd) <- "EPSG:4326"
    expect_warning(AttrMort:::.aggregate_pop(fine, odd), "not an exact multiple")
  })
})

describe("align_to_target()", {
  it("puts a fine population raster onto the coarse exposure grid", {
    conc <- .make_raster(4, 4, 30)
    pop  <- .make_raster(12, 12, 1)

    aligned <- AttrMort:::align_to_target(
      list(conc = conc, pop = pop), target_res = 3, pop_names = "pop"
    )

    expect_equal(as.numeric(terra::res(aligned$conc)), c(3, 3))
    expect_equal(as.numeric(terra::res(aligned$pop)), c(3, 3))
    expect_equal(terra::global(aligned$pop, fun = "sum", na.rm = TRUE)[[1]], 144)
    expect_equal(terra::global(aligned$conc, fun = "mean", na.rm = TRUE)[[1]], 30)
  })
})

describe(".resolve_target_res()", {
  it("auto-confirms a resolution that fits comfortably", {
    r <- terra::rast(nrows = 180, ncols = 360, xmin = -180, xmax = 180,
                     ymin = -90, ymax = 90)          # 1 degree, 64,800 cells
    expect_message(
      res <- AttrMort:::.resolve_target_res(r, NULL, NULL),
      "auto-confirmed"
    )
    expect_equal(res, 1)
  })

  it("does not prompt in a non-interactive session", {
    r <- terra::rast(nrows = 18000, ncols = 36000, xmin = -180, xmax = 180,
                     ymin = -90, ymax = 90)          # 0.01 degree, 6.5e8 cells
    expect_false(interactive())
    expect_message(
      res <- AttrMort:::.resolve_target_res(r, NULL, NULL),
      "Non-interactive session"
    )
    expect_equal(res, 0.1)
  })

  it("refuses a resolution that is computationally infeasible", {
    r <- terra::rast(nrows = 180000, ncols = 360000, xmin = -180, xmax = 180,
                     ymin = -90, ymax = 90)          # 0.001 degree, 6.5e10 cells
    expect_error(AttrMort:::.resolve_target_res(r, NULL, NULL), "infeasible")
  })

  it("uses an explicit target resolution as given", {
    r <- .make_raster(4, 4)
    expect_message(res <- AttrMort:::.resolve_target_res(r, NULL, 0.05),
                   "Using specified target resolution")
    expect_equal(res, 0.05)
    expect_error(AttrMort:::.resolve_target_res(r, NULL, -1), "must be positive")
  })
})

describe("shapefile_to_grid()", {
  it("rasterizes an sf polygon onto the template grid", {
    skip_if_not_installed("sf")
    sq <- sf::st_sf(
      name = "A",
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(0, 0), c(6, 0), c(6, 6), c(0, 6), c(0, 0)))),
        crs = 4326
      )
    )
    template <- .make_raster(4, 4)

    out <- suppressWarnings(
      AttrMort:::shapefile_to_grid(sq, template, admin_col = "name", dgt = 1)
    )

    expect_true(all(c("x", "y", "name") %in% names(out)))
    expect_gte(nrow(out), 4)
    expect_true(all(out$name == "A"))
    expect_type(out$x, "character")
  })

  it("falls back to the first character column when admin_col is absent", {
    skip_if_not_installed("sf")
    sq <- sf::st_sf(
      region = "B",
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(0, 0), c(12, 0), c(12, 12), c(0, 12), c(0, 0)))),
        crs = 4326
      )
    )
    template <- .make_raster(4, 4)
    expect_warning(
      out <- AttrMort:::shapefile_to_grid(sq, template, admin_col = "nope"),
      "not found in shapefile"
    )
    expect_true(all(out$region == "B"))
  })
})

describe("Mortality() from gridded GeoTIFF inputs", {
  it("aligns two rasters and computes the burden end to end", {
    dir <- tempfile("attrmort-rast")
    dir.create(dir)
    on.exit(unlink(dir, recursive = TRUE), add = TRUE)

    conc <- .make_raster(4, 4, 30)                  # 3 degree cells
    pop  <- .make_raster(12, 12, 10)                # 1 degree cells
    conc_path <- file.path(dir, "conc.tif")
    pop_path  <- file.path(dir, "pop.tif")
    terra::writeRaster(conc, conc_path, overwrite = TRUE)
    terra::writeRaster(pop, pop_path, overwrite = TRUE)

    # calc_fild must share the conc grid's coordinates
    fld <- AttrMort:::raster_to_grid(terra::rast(conc_path)) |>
      dplyr::select(x, y) |>
      dplyr::mutate(location = "A")

    age  <- data.frame(location = "A", age = c("25", "30"),
                       base2015 = c(0.5, 0.5))
    mort <- data.frame(location = "A", age = c("25", "30"),
                       endpoint = "ncd+lri", base2015 = c(1000, 2000))

    out <- suppressMessages(Mortality(
      CRF = "GEMM", calc_fild = fld, scenario = "base2015",
      conc_real = conc_path, pop_total = pop_path,
      age_struc = age, mort_rate = mort, mort_lvl = "location",
      target_res = 3, validate = "off"
    ))

    expect_equal(nrow(out), 16)
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(out)))

    # Every cell sees a flat concentration of 30, so PWRR == RR and the
    # population of a target cell is 9 * 10 = 90.
    rr_all <- RR_std("GEMM", "MEAN")
    rr <- rr_all$RR[rr_all$endpoint == "ncd+lri" & rr_all$age == "25" &
                      rr_all$conc == "30"]
    m25 <- 90 * 0.5 * 1000 / 1e5
    expect_equal(sum(out[["ncd+lri_25"]]),
                 16 * m25 * (rr - 1) / rr, tolerance = 1e-9)
  })
})
