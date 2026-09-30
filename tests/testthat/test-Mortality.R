# Tests for Mortality() — the core attributable-mortality calculation

describe("Mortality() on the small fixture", {
  it("computes attributable deaths calibrated by the population-weighted RR", {
    d   <- .attr_small_long()
    out <- .attr_run()

    expect_s3_class(out, "data.frame")
    expect_equal(nrow(out), 4)
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(out)))

    # Independent reconstruction of the PWRR branch:
    #   AttrMort = pop * prop * mortrate * (RR - 1) / PWRR / 1e5
    #   PWRR     = weighted.mean(RR, pop) over the domain
    rr   <- RR_std("GEMM", "MEAN")
    sel  <- rr$endpoint == "ncd+lri" & rr$age == "25"
    rr25 <- rr$RR[sel]
    rr_cell <- rr25[match(d$conc_real$conc, rr$conc[sel])]

    expect_true(all(rr_cell > 1))
    pwrr <- sum(d$pop_total$pop * rr_cell) / sum(d$pop_total$pop)
    expected <- d$pop_total$pop[1] * 0.5 * 1000 * (rr_cell[1] - 1) / pwrr / 1e5

    i <- which(out$x == "0" & out$y == "0")
    expect_equal(out[["ncd+lri_25"]][i], expected, tolerance = 1e-10)
  })

  it("is linear in the baseline mortality rate", {
    d <- .attr_small_long()
    base <- .attr_run()
    d$mort_rate$mortrate <- d$mort_rate$mortrate * 2
    doubled <- Mortality(
      CRF = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location"
    )
    expect_equal(doubled[["ncd+lri_25"]], base[["ncd+lri_25"]] * 2)
  })

  it("gives the same answer for wide inputs with `scenario` as for long ones", {
    long  <- .attr_run(long = TRUE)
    wide  <- .attr_run(long = FALSE, scenario = "base2015")
    expect_equal(wide[["ncd+lri_25"]], long[["ncd+lri_25"]])
    expect_equal(wide[["ncd+lri_30"]], long[["ncd+lri_30"]])
  })

  it("computes at grid level when mort_lvl is NULL", {
    expect_warning(out <- .attr_run(mort_lvl = NULL), "mort_lvl")
    expect_equal(nrow(out), 4)
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(out)))
  })

  it("treats the whole field as one unit when mort_lvl is not a domain column", {
    expect_warning(out <- .attr_run(mort_lvl = "nonexistent"),
                   "not a domain column")
    expect_equal(nrow(out), 1)
  })

  it("uses conc_cf for the risk term while conc_real drives the PWRR", {
    d    <- .attr_small_long()
    base <- .attr_run()
    with_cf <- .attr_run(conc_cf = d$conc_cf)

    expect_false(isTRUE(all.equal(with_cf[["ncd+lri_25"]],
                                  base[["ncd+lri_25"]])))

    # The fixture's counterfactual is flat (conc = 5 everywhere), so the
    # burden is proportional to population and nothing else.
    ratio <- with_cf[["ncd+lri_25"]] / d$pop_total$pop
    expect_equal(ratio, rep(ratio[1], 4))
  })

  it("accepts a user-supplied data.frame as CRF", {
    d  <- .attr_small_long()
    rr <- RR_std("GEMM", "MEAN")
    out <- Mortality(
      CRF = rr, calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location"
    )
    expect_equal(out[["ncd+lri_25"]], .attr_run()[["ncd+lri_25"]])
  })
})

describe("Mortality() input checks", {
  it("reports every input problem at once", {
    d <- .attr_small_long()
    msg <- tryCatch(
      Mortality(
        CRF = "GEMM", calc_fild = d$calc_fild,
        conc_real = data.frame(bogus = 1:3, conc = c("10", "20", "30")),
        pop_total = d$pop_total,
        age_struc = dplyr::select(d$age_struc, -prop),
        mort_rate = d$mort_rate,
        mort_lvl = "location", validate = "off"
      ),
      error = function(e) conditionMessage(e)
    )
    expect_match(msg, "Invalid input data")
    expect_match(msg, "`conc_real` shares no join key")
    expect_match(msg, "`age_struc` is missing required column")
  })

  it("rejects an unknown CR model and lists the valid ones", {
    expect_error(.attr_run(CRF = "NOPE"), "Unknown CR model")
    expect_error(.attr_run(CRF = "NOPE"), "GEMM")
  })

  it("explains an empty endpoint intersection instead of returning nothing", {
    msg <- tryCatch(.attr_run(CRF = "NO2"), error = function(e) conditionMessage(e))
    expect_match(msg, "No shared disease endpoint")
    expect_match(msg, "cause")
  })

  it("can turn validation into a hard error", {
    d <- .attr_small_long()
    d$mort_rate$mortrate[1] <- -1
    expect_error(
      Mortality(
        CRF = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
        pop_total = d$pop_total, age_struc = d$age_struc,
        mort_rate = d$mort_rate, mort_lvl = "location", validate = "stop"
      ),
      "validation failed"
    )
  })

  it("stops when a file path does not exist", {
    d <- .attr_small_long()
    expect_error(
      Mortality(
        CRF = "GEMM", calc_fild = d$calc_fild,
        conc_real = "no/such/file.tif", pop_total = d$pop_total,
        age_struc = d$age_struc, mort_rate = d$mort_rate
      ),
      "File not found"
    )
  })
})

describe("Mortality() on the shipped example data", {
  it("reproduces the reference GEMM / base2015 / location total", {
    out <- suppressWarnings(suppressMessages(Mortality(
      CRF        = "GEMM",
      calc_fild  = .attr_data("grid_info"),
      conc_real  = .attr_data("grid_exposure"),
      pop_total  = .attr_data("grid_pop"),
      age_struc  = .attr_data("national_age_structure"),
      mort_rate  = .attr_data("national_mortality"),
      mort_lvl   = "location",
      scenario   = "base2015",
      validate   = "off"
    )))

    expect_equal(nrow(out), 6000)
    num <- out[vapply(out, is.numeric, logical(1))]
    expect_equal(sum(as.matrix(num)), 58183.612439, tolerance = 1e-6)
  })
})

describe("Mortality_batch() and combine_batch()", {
  it("runs several scenarios and combines the results", {
    s <- .attr_small()
    s$conc_real$SSP1_2030 <- c(8, 16, 24, 32)
    s$pop_total$SSP1_2030 <- c(110, 210, 310, 410)
    s$age_struc$SSP1_2030 <- c(0.4, 0.6)
    s$mort_rate$SSP1_2030 <- c(900, 2100)

    res <- suppressMessages(Mortality_batch(
      CRF = "GEMM", calc_fild = s$calc_fild,
      conc_real = s$conc_real, pop_total = s$pop_total,
      age_struc = s$age_struc, mort_rate = s$mort_rate,
      mort_lvl = "location",
      scenarios = c("base2015", "SSP1_2030")
    ))

    expect_named(res, c("base2015", "SSP1_2030"))
    combined <- combine_batch(res, by = "location")
    expect_true("scenario" %in% names(combined))
    expect_equal(nrow(combined), 2)
  })
})
