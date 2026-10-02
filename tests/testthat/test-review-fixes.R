# Regression tests for the review findings fixed in batches A and B
# (diagnosis/plan_fixes_261001.md). Each one failed before its fix.

describe("A1: data text is never evaluated as an expression", {
  it("shows an endpoint literally, braces and all", {
    s <- .attr_small()
    s$mort_rate$endpoint <- "{1+1}"

    msg <- tryCatch(
      {
        suppressWarnings(suppressMessages(mortality(
          crf = "GEMM", calc_fild = s$calc_fild, conc_real = s$conc_real,
          pop_total = s$pop_total, age_struc = s$age_struc,
          mort_rate = s$mort_rate, scenario = "base2015", validate = "off"
        )))
        "no error"
      },
      error = function(e) conditionMessage(e)
    )

    expect_match(msg, "mort_rate values: \\{1\\+1\\}", fixed = FALSE)
    expect_false(grepl("mort_rate values: 2", msg))
  })
})

describe("A2: a CR configuration cannot expand without bound", {
  it("refuses an age range nobody would write", {
    expect_error(AttrMort:::.cr_ages(list(from = 0, to = 10000, by = 5), "ages"),
                 "looks wrong")
    expect_error(AttrMort:::.cr_ages(as.list(1:200), "ages"),
                 "more than the 100 allowed")
  })

  it("accepts the ranges the shipped models use", {
    expect_length(AttrMort:::.cr_ages(list(from = 0, to = 95, by = 5), "ages"), 20L)
    expect_length(AttrMort:::.cr_ages(list(25, 30), "ages"), 2L)
  })
})

describe("B3: the counterfactual joins the exposure lattice", {
  it("puts conc_cf on the analysis grid, not on its own extent", {
    mk <- function(xmin) {
      r <- terra::rast(nrows = 1, ncols = 2, xmin = xmin, xmax = xmin + 2,
                       ymin = 0, ymax = 1)
      terra::values(r) <- c(10, 20)
      terra::crs(r) <- "EPSG:4326"
      r
    }
    prep <- suppressMessages(AttrMort:::.prepare_inputs(
      "GEMM", NULL, mk(0), mk(0.25), mk(0),
      data.frame(location = "A", age = c(25, 30), prop = c(0.5, 0.5)),
      data.frame(location = "A", age = c(25, 30), endpoint = "ncd+lri",
                 mortrate = c(1000, 2000)),
      scenario = NULL, admin = NULL, admin_col = "admin", target_res = NULL,
      dgt_coord = 2, dgt_conc = 1, validate = "off", cr_config = NULL,
      mort_lvl = NULL
    ))

    expect_equal(prep$conc_cf$x, prep$conc_real$x)
    expect_equal(prep$conc_cf$y, prep$conc_real$y)
  })
})

describe("B4: refining a population raster conserves the total", {
  it("divides a source cell between the finer cells", {
    pop <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
    terra::values(pop) <- 100
    terra::crs(pop) <- "EPSG:4326"
    tpl <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
    terra::crs(tpl) <- "EPSG:4326"

    out <- suppressWarnings(AttrMort:::.aggregate_pop(pop, tpl))

    expect_equal(terra::global(out, "sum", na.rm = TRUE)[[1]], 100)
    expect_equal(sort(terra::values(out)), rep(25, 4))
  })
})

describe("B1: every decomposition state is matched by key", {
  it("leaves a cell NA instead of borrowing the neighbouring value", {
    d      <- .attr_two_scenario()
    groups <- .attr_groups(d)
    # the `to` group stops covering the first cell: any state that reads its
    # population from `to` cannot be computed there
    groups$to$pop_total <- groups$to$pop_total[groups$to$pop_total$x == "1", ,
                                               drop = FALSE]

    out <- suppressWarnings(suppressMessages({
      res <- NULL
      utils::capture.output(res <- decompose(
        crf = "GEMM", calc_fild = d$calc_fild, from = groups$from,
        to = groups$to, mort_lvl = "location", validate = "warn"
      ))
      res
    }))[["PG-PA-EXP-ORF"]]

    # every cell and stratum is still there
    expect_equal(nrow(out), 8L)
    # the cells the `to` group does not cover are not given another cell's value
    head_cells <- out[out$x == "0", ]
    expect_true(all(is.na(head_cells$End)))
    expect_true(all(is.na(head_cells$PG)))
    # and the cell that is covered still gets a number
    expect_false(anyNA(out[out$x == "1", "End"]))
  })
})

describe("B2: the uncertainty range is matched by key", {
  it("leaves a cell NA instead of borrowing another cell's interval", {
    d <- .attr_small_long()
    # +20% takes the second cell's concentration out of the C-R lookup, so that
    # chain cannot compute it at all
    d$conc_real$conc <- c("250", "290")

    # `validate = "warn"`: the run reports how many cells have no interval.
    # The data validation also warns about the fixture, so the warnings are
    # collected rather than matched one by one.
    warns <- character(0)
    out <- withCallingHandlers(
      suppressMessages(mortality(
        crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
        pop_total = d$pop_total, age_struc = d$age_struc,
        mort_rate = d$mort_rate, mort_lvl = "location", validate = "warn",
        uncertain = TRUE, conc_uncert = 20
      )),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_true(any(grepl("have no interval", warns)))

    expect_equal(nrow(out), 4L)          # every grid cell is still there
    expect_true(anyNA(out$CI_UP))        # the ones no chain could compute
    ok <- !is.na(out$CI_UP)
    expect_true(all(out$CI_UP[ok] >= out$CI_LOW[ok]))
  })
})

describe("C1: validate = \"off\" is complete silence", {
  it("says nothing at all, on either entry point", {
    s <- .attr_small()
    expect_silent(
      out <- mortality(
        crf = "GEMM", calc_fild = s$calc_fild, conc_real = s$conc_real,
        pop_total = s$pop_total, age_struc = s$age_struc,
        mort_rate = s$mort_rate, mort_lvl = "location", validate = "off"
      )
    )
    expect_equal(nrow(out), 4L)

    d <- .attr_two_scenario()
    g <- .attr_groups(d)
    expect_silent(
      res <- decompose(crf = "GEMM", calc_fild = d$calc_fild, from = g$from,
                       to = g$to, mort_lvl = "location", validate = "off")
    )
    expect_length(res, 24L)
  })

  it("still reports everything when validation is on", {
    s <- .attr_small()
    expect_message(
      suppressWarnings(mortality(
        crf = "GEMM", calc_fild = s$calc_fild, conc_real = s$conc_real,
        pop_total = s$pop_total, age_struc = s$age_struc,
        mort_rate = s$mort_rate, mort_lvl = "location", scenario = "base2015"
      ))
    )
  })
})


describe("B6: aggregating onto a skeleton prefers coordinates", {
  it("does not copy a whole domain onto every cell", {
    d   <- .attr_small_long()
    res <- suppressWarnings(suppressMessages(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    )))

    # a skeleton that adds a finer geography beside the domain column the
    # result already carries: joining on that coarser column would copy the
    # whole field onto each province
    skel <- d$calc_fild
    skel$province <- ifelse(skel$x == "0", "P0", "P1")
    agg <- aggregate_mortality(res, calc_fild = skel, at = "province")

    expect_equal(nrow(agg), 2L)
    expect_false(isTRUE(all.equal(agg$total[1], agg$total[2])))
    expect_equal(sum(agg$total), sum(res[["ncd+lri_25"]]) + sum(res[["ncd+lri_30"]]),
                 tolerance = 1e-10)
  })
})

