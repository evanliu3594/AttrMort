# Ingest quality on the raster path -------------------------------------
#
# Two conditions the pipeline used to meet without a word, found on real
# gridded data (`diagnosis/validate_raster_ingest_261002.md`):
#
#   * an *undeclared* fill / no-data value -- a netCDF or GeoTIFF that spells
#     missing as -999 without a `_FillValue` / `missing_value` / `NAflag`.
#     terra maps a declared flag to NA while reading, so what reaches
#     `raster_to_grid()` is an ordinary number, and the cell is kept;
#   * a `dgt_coord` too coarse for the raster resolution: distinct cell centres
#     render to one coordinate key, the grid skeleton loses cells and the value
#     table fans out on the duplicated key, which surfaces far away as a wrong
#     total or a list-column result.
#
# Nothing is repaired for either: dropping or rescaling a sentinel decides which
# cells the analysis covers and what every total means, which is the user's
# call. The tests therefore pin the *reports*, and pin that the values are
# still there unchanged.

# A small raster on the 0..12 degree box. `res` is only used for the cases that
# need a stated cell size.
.ingest_raster <- function(nrows, ncols, values, xmin = 0, xmax = 12,
                           ymin = 0, ymax = 12) {
  r <- terra::rast(nrows = nrows, ncols = ncols, xmin = xmin, xmax = xmax,
                   ymin = ymin, ymax = ymax)
  terra::values(r) <- values
  terra::crs(r) <- "EPSG:4326"
  r
}

# Arguments for `.prepare_inputs()` with a raster exposure: everything else
# comes from the small fixture, which the front end only reads and maps.
.ingest_prep_args <- function(conc_real, validate) {
  d <- .attr_small()
  list(
    crf = "GEMM", calc_fild = NULL, conc_real = conc_real, conc_cf = NULL,
    pop_total = d$pop_total, age_struc = d$age_struc, mort_rate = d$mort_rate,
    scenario = NULL, admin = NULL, admin_col = "admin", target_res = NULL,
    dgt_coord = 2, dgt_conc = 1, validate = validate, cr_config = NULL,
    mort_lvl = NULL
  )
}

# A one-domain boundary box, so the raster grid can carry a `mort_lvl`.
.ingest_boundary <- function() {
  sf::st_sf(
    location = "A",
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(c(-1, -1), c(3, -1), c(3, 3), c(-1, 3),
                                c(-1, -1)))),
      crs = 4326
    )
  )
}

describe("an undeclared fill value is reported, never cleaned", {
  it("keeps the sentinel in the ingested table", {
    # -999 with no declared flag is just a number to the reader. This is the
    # pin that makes cleaning a deliberate decision: if ingest ever starts
    # dropping or converting it, this test fails and the contract has to be
    # re-agreed with the user.
    r <- .ingest_raster(2, 2, c(10, -999, 30, 40))
    out <- AttrMort:::raster_to_grid(r, band_names = "conc", dgt = 0)

    expect_equal(nrow(out), 4L)
    expect_equal(sum(out$conc == -999), 1L)
    expect_false(anyNA(out$conc))
  })

  it("counts it and names the value it saw", {
    tbl <- data.frame(x = c("0", "1", "2"), y = "0",
                      conc = c(-999, -999, 5))

    expect_warning(
      report <- AttrMort:::.report_raster_fill(tbl, "conc_real"),
      "negative"
    )
    expect_equal(report$n_neg, 2L)
    expect_equal(report$n_value, 3L)
    expect_equal(report$n_cells, 3L)
    expect_equal(as.numeric(names(report$top)), -999)
    expect_equal(unname(report$top[[1]]), 2L)
  })

  it("stays quiet when every value is non-negative", {
    tbl <- data.frame(x = c("0", "1"), y = "0", conc = c(0, 5))
    expect_no_warning(report <- AttrMort:::.report_raster_fill(tbl, "conc_real"))
    expect_equal(report$n_neg, 0L)
  })

  it("stays quiet when asked to, and still reports", {
    tbl <- data.frame(x = "0", y = "0", conc = -999)
    expect_no_warning(report <- AttrMort:::.report_raster_fill(
      tbl, "conc_real", quiet = TRUE
    ))
    expect_equal(report$n_neg, 1L)
  })

  it("is wired into the front end, and silenced by `validate = \"off\"`", {
    r <- .ingest_raster(2, 2, c(10, -999, 30, 40))

    expect_warning(
      suppressMessages(do.call(AttrMort:::.prepare_inputs,
                               .ingest_prep_args(r, validate = "warn"))),
      "are negative"
    )
    expect_no_warning(
      suppressMessages(do.call(AttrMort:::.prepare_inputs,
                               .ingest_prep_args(r, validate = "off")))
    )
  })
})

describe("a raster finer than `dgt_coord` is reported", {
  # 0.001 deg cells: adjacent centres are 0.001 apart, two decimals cannot
  # keep them apart.
  .fine_raster <- function(n = 4) {
    .ingest_raster(n, n, seq_len(n * n), xmin = 0, xmax = 0.001 * n,
                   ymin = 0, ymax = 0.001 * n)
  }

  it("warns and names the number of digits that would keep the grid apart", {
    expect_warning(
      out <- AttrMort:::raster_to_grid(.fine_raster(), band_names = "conc",
                                       dgt = 2),
      "collapse into 1 coordinate key"
    )
    # the report is a report: no cell is dropped, the keys just collide
    expect_equal(nrow(out), 16L)
    expect_equal(nrow(dplyr::distinct(out, x, y)), 1L)
  })

  it("warns on the 0.01 degree near miss, and not at three decimals", {
    # 0.01 deg (about 1.1 km) with the default `dgt_coord = 2` loses half the
    # grid -- the case a real 1 km product would hit.
    r <- .ingest_raster(100, 100, 1, xmin = 100, xmax = 101,
                        ymin = 20, ymax = 21)

    expect_warning(
      out <- AttrMort:::raster_to_grid(r, band_names = "conc", dgt = 2),
      "dgt_coord = 3"
    )
    expect_lt(nrow(dplyr::distinct(out, x, y)), 10000L)

    expect_no_warning(
      fine <- AttrMort:::raster_to_grid(r, band_names = "conc", dgt = 3)
    )
    expect_equal(nrow(dplyr::distinct(fine, x, y)), 10000L)
  })

  it("says nothing when the keys keep the grid apart", {
    expect_no_warning(
      AttrMort:::raster_to_grid(.fine_raster(), band_names = "conc", dgt = 4)
    )
  })

  it("reports the collapse before the run hands back a broken grid", {
    skip_if_not_installed("sf")

    r   <- .fine_raster()
    pop <- .ingest_raster(4, 4, 100, xmin = 0, xmax = 0.004,
                          ymin = 0, ymax = 0.004)
    age  <- data.frame(location = "A", age = c("25", "30"), prop = c(0.5, 0.5))
    mort <- data.frame(location = "A", age = c("25", "30"),
                       endpoint = "ncd+lri", mortrate = c(1000, 2000))

    run <- function(dgt_coord) {
      suppressMessages(mortality(
        crf = "GEMM", conc_real = r, pop_total = pop, age_struc = age,
        mort_rate = mort, mort_lvl = "location", admin = .ingest_boundary(),
        admin_col = "location", target_res = 0.001, dgt_coord = dgt_coord
      ))
    }

    # At the default 2 the grid collapses; the run says so while ingesting,
    # rather than only failing later on the duplicated key. Only that report is
    # asserted: the fixture's own shortfalls (a two-group age structure, the
    # endpoints it does not carry), the list-columns the collapsed grid
    # produces, and whatever a later validation decides to make of duplicate
    # keys are all noise here.
    seen <- character(0)
    tryCatch(
      withCallingHandlers(
        run(2),
        warning = function(w) {
          seen <<- c(seen, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) NULL
    )
    expect_true(any(str_detect(seen, "merges raster cells")))

    # At the resolution the grid actually needs, all 16 cells survive.
    expect_equal(nrow(suppressWarnings(run(4))), 16L)
  })
})
