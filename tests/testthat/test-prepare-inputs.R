# Tests for the input front end (R/prepare-inputs.R)
#
# `.INPUT_ROUTES` is the table the module documents its own decisions in, so
# the first test keeps it honest: every handler it names must exist. The rest
# check the routes a call can reach without any raster file on disk, which is
# what `calc_fild = NULL` means.

# `override` is applied with list assignment on purpose: `modifyList()` would
# drop an element set to NULL, and `calc_fild = NULL` is exactly what these
# tests pass.
.prep_args <- function(override = list()) {
  d <- .attr_small()
  args <- list(
    crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
    conc_cf = NULL, pop_total = d$pop_total, age_struc = d$age_struc,
    mort_rate = d$mort_rate, scenario = NULL, admin = NULL,
    admin_col = "admin", target_res = NULL, dgt_coord = 2, dgt_conc = 1,
    validate = "off", cr_config = NULL, mort_lvl = "location"
  )
  args[names(override)] <- override
  args
}

describe(".INPUT_ROUTES", {
  it("names handlers that exist in the package", {
    routes <- AttrMort:::.INPUT_ROUTES

    expect_s3_class(routes, "data.frame")
    expect_equal(names(routes), c("given", "when", "then", "handler"))
    expect_true(nrow(routes) >= 15L)
    for (h in unique(routes$handler)) {
      expect_true(is.function(get0(h, envir = asNamespace("AttrMort"))), info = h)
    }
  })
})

describe(".prepare_inputs()", {
  it("takes the grid from a tabular exposure that carries coordinates", {
    expect_message(
      prep <- do.call(AttrMort:::.prepare_inputs, .prep_args(list(calc_fild = NULL))),
      "coordinate pair"
    )
    expect_equal(nrow(prep$calc_fild), 4L)
    expect_equal(names(prep$calc_fild), c("x", "y"))
  })

  it("stops when the exposure is already a domain table", {
    # no coordinates to derive a grid from: this one is one row per domain
    args <- .prep_args(list(calc_fild = NULL, conc_real = .attr_small()$age_struc))
    expect_error(do.call(AttrMort:::.prepare_inputs, args),
                 "needs a `conc_real` that carries coordinates")
  })

  it("takes the grid from the exposure raster when calc_fild is NULL", {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
    terra::values(r) <- c(10, 20, 30, 40)
    terra::crs(r) <- "EPSG:4326"     # already the target: no reprojection note

    # no `mort_lvl`: with a coordinate-only skeleton and no `admin`, a domain
    # calibration would fall back to the national boundaries, which is a
    # different route (and a Suggests dependency)
    prep <- do.call(AttrMort:::.prepare_inputs,
                    .prep_args(list(calc_fild = NULL, conc_real = r,
                                    mort_lvl = NULL)))

    expect_equal(nrow(prep$calc_fild), 4L)
    expect_true(all(c("x", "y") %in% names(prep$calc_fild)))
    expect_true(all(c("x", "y", "conc") %in% names(prep$conc_real)))
  })

  it("accepts a vector map as calc_fild and labels the cells with it", {
    d  <- .attr_small()
    sq <- sf::st_sf(
      location = "A",
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(-1, -1), c(3, -1), c(3, 3), c(-1, 3), c(-1, -1)))),
        crs = 4326
      )
    )

    prep <- do.call(AttrMort:::.prepare_inputs,
                    .prep_args(list(calc_fild = sq, admin_col = "location"))) |>
      suppressMessages()

    # the map labels the grid, it does not replace it: the cells are still the
    # exposure's own, one row each
    expect_equal(nrow(prep$calc_fild), 4L)
    expect_true(all(prep$calc_fild$location == "A"))
  })

  it("refuses a map and admin at the same time", {
    sq <- sf::st_sf(
      location = "A",
      geometry = sf::st_sfc(
        sf::st_polygon(list(rbind(c(-1, -1), c(3, -1), c(3, 3), c(-1, 3), c(-1, -1)))),
        crs = 4326
      )
    )
    expect_error(
      do.call(AttrMort:::.prepare_inputs,
              .prep_args(list(calc_fild = sq, admin = sq, admin_col = "location"))),
      "either as `calc_fild` or as `admin`"
    )
  })

  it("hands back canonical tables, one scenario each", {
    prep <- do.call(AttrMort:::.prepare_inputs,
                    .prep_args(list(scenario = "base2015")))

    expect_equal(names(prep$conc_real), c("x", "y", "conc"))
    expect_equal(names(prep$pop_total), c("x", "y", "pop"))
    expect_true(all(c("age", "prop") %in% names(prep$age_struc)))
    expect_true(all(c("age", "endpoint", "mortrate") %in% names(prep$mort_rate)))
    # a group without its own counterfactual is compared against its own exposure
    expect_equal(prep$conc_cf, prep$conc_real)
    expect_equal(prep$crf_name, "GEMM")
  })
})

describe(".INPUT_ROUTES behaviour", {
  it("stops on an extension it cannot read", {
    # the route table's last reader row: an unknown extension names the
    # supported ones instead of letting terra/readxl complain
    args <- .prep_args(list(conc_real = "exposure.parquet"))
    file.create("exposure.parquet")
    on.exit(unlink("exposure.parquet"), add = TRUE)
    expect_error(do.call(AttrMort:::.prepare_inputs, args),
                 "Unsupported file format")
  })
})


describe("column-name matching", {
  it("treats lon/lat and x/y as the same key, in any spelling", {
    d <- .attr_small_long()
    # the skeleton says x/y, the exposure says lon/lat, the population spells
    # it out -- one grid, three spellings
    conc <- d$conc_real
    names(conc)[names(conc) == "x"] <- "lon"
    names(conc)[names(conc) == "y"] <- "lat"
    pop <- d$pop_total
    names(pop)[names(pop) == "x"] <- "longitude"
    names(pop)[names(pop) == "y"] <- "latitude"

    canon <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc, mort_rate = d$mort_rate,
      mort_lvl = "location", validate = "off"
    )))
    mixed <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = conc, pop_total = pop,
      age_struc = d$age_struc, mort_rate = d$mort_rate,
      mort_lvl = "location", validate = "off"
    )))

    expect_equal(mixed, canon, tolerance = 1e-12)
  })

  it("finds a column whose name is only a spelling variant", {
    d <- .attr_small_long()
    names(d$mort_rate)[names(d$mort_rate) == "mortrate"] <- "Mort Rate"
    names(d$age_struc)[names(d$age_struc) == "prop"]      <- "Proportion"

    hit <- detect_columns(d$mort_rate, schema = "mortrate")
    expect_equal(unname(hit["mortrate"]), "Mort Rate")
  })

  it("accepts a mixed coordinate pair", {
    grid <- data.frame(x = "0", lat = "0")
    expect_equal(AttrMort:::.grid_xy(grid), c("x", "lat"))
  })
})
