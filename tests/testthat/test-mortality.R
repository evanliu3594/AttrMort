# Tests for mortality() — the core attributable-mortality calculation

describe("mortality() on the small fixture", {
  it("computes attributable deaths calibrated by the population-weighted RR", {
    d   <- .attr_small_long()
    out <- .attr_run()

    expect_s3_class(out, "data.frame")
    expect_equal(nrow(out), 4)
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(out)))

    # Independent reconstruction of the PWRR branch:
    #   AttrMort = pop * prop * mortrate * (RR - 1) / PWRR / 1e5
    #   PWRR     = weighted.mean(RR, pop) over the domain
    rr   <- rr_std("GEMM", "MEAN")
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
    doubled <- mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
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
    # The uncalibrated mode is reported with a message, not a warning.
    expect_message(out <- suppressWarnings(.attr_run(mort_lvl = NULL, validate = "warn")),
                   "not calibrated against")
    expect_equal(nrow(out), 4)
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(out)))
  })

  it("falls back to the domain column mort_rate carries itself", {
    # `mort_lvl` names a column the mortality table does not have: rather than
    # silently calibrating the whole field as one unit, the run says so and
    # calibrates on the domain column that is there -- the same numbers as
    # naming that column outright.
    warns <- character(0)
    out <- withCallingHandlers(
      .attr_run(mort_lvl = "nonexistent", validate = "warn"),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_true(any(grepl("calibrating on its own domain column", warns)))
    expect_equal(out, .attr_run(mort_lvl = "location"), tolerance = 1e-12)
  })

  it("treats the whole field as one unit when mort_rate has no domain column", {
    d <- .attr_small_long()
    d$mort_rate <- d$mort_rate[, c("age", "endpoint", "mortrate")]

    # The run cannot get far without a shared key, but the reason is reported
    # before the key check rather than as a bare "shares no join key".
    warns <- character(0)
    withCallingHandlers(
      try(mortality(
        crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
        pop_total = d$pop_total, age_struc = d$age_struc,
        mort_rate = d$mort_rate, mort_lvl = "location", validate = "warn"
      ), silent = TRUE),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_true(any(grepl("carries no geographic column", warns)))
  })

  it("warns about concentrations outside the CRF lookup range", {
    d <- .attr_small_long()
    d$conc_real$conc[3] <- "400"          # GEMM lookup ends at 300
    warns <- new.env(parent = emptyenv())
    warns$msg <- character(0)
    out <- withCallingHandlers(
      mortality(
        crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
        pop_total = d$pop_total, age_struc = d$age_struc,
        mort_rate = d$mort_rate, mort_lvl = "location", validate = "warn"
      ),
      warning = function(w) {
        warns$msg <- c(warns$msg, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_true(any(grepl("outside the CRF lookup range", warns$msg)))
    expect_true(any(grepl("`conc_real`", warns$msg)))
    expect_equal(nrow(out), 3)            # the out-of-range cell is dropped
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
    rr <- rr_std("GEMM", "MEAN")
    out <- mortality(
      crf = rr, calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    )
    expect_equal(out[["ncd+lri_25"]], .attr_run()[["ncd+lri_25"]])
  })
})

describe("mortality() input checks", {
  it("reports every input problem at once", {
    d <- .attr_small_long()
    msg <- tryCatch(
      mortality(
        crf = "GEMM", calc_fild = d$calc_fild,
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

  it("reads single value columns under arbitrary names without a scenario", {
    d <- .attr_small_long()
    loose <- d
    names(loose$conc_real)[names(loose$conc_real) == "conc"] <- "PM25_2017"
    names(loose$pop_total)[names(loose$pop_total) == "pop"] <- "Pop2017"
    names(loose$age_struc)[names(loose$age_struc) == "prop"] <- "share"
    names(loose$mort_rate)[names(loose$mort_rate) == "mortrate"] <- "rate_2017"

    out <- suppressMessages(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = loose$conc_real,
      pop_total = loose$pop_total, age_struc = loose$age_struc,
      mort_rate = loose$mort_rate, mort_lvl = "location", validate = "off"
    ))

    expect_equal(out, .attr_run(), tolerance = 1e-12)
  })

  it("lets inputs that are not scenario-addressed pass through", {
    d <- .attr_small()
    out <- suppressMessages(mortality(
      crf = "GEMM", calc_fild = d$calc_fild,
      conc_real = d$conc_real,                       # wide: base2015
      pop_total = .slice_pop(d$pop_total, "base2015"),   # long: pop
      age_struc = .slice_age(d$age_struc, "base2015", min_age_groups = 0),
      mort_rate = .slice_mort(d$mort_rate, "base2015"),
      scenario = "base2015", mort_lvl = "location", validate = "off"
    ))

    expect_equal(out, .attr_run(long = FALSE, scenario = "base2015"),
                 tolerance = 1e-12)
  })

  it("refuses to choose between several value columns", {
    d <- .attr_small_long()
    two <- data.frame(x = d$pop_total$x, y = d$pop_total$y,
                      Pop2015 = d$pop_total$pop, Pop2017 = d$pop_total$pop)

    expect_error(
      mortality(
        crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
        pop_total = two, age_struc = d$age_struc, mort_rate = d$mort_rate,
        scenario = "base2015", mort_lvl = "location", validate = "off"
      ),
      "Value candidates"
    )
  })

  it("rejects an unknown CR model and lists the valid ones", {
    expect_error(.attr_run(crf = "NOPE"), "Unknown CR model")
    expect_error(.attr_run(crf = "NOPE"), "GEMM")
  })

  it("explains an empty endpoint intersection instead of returning nothing", {
    msg <- tryCatch(.attr_run(crf = "NO2"), error = function(e) conditionMessage(e))
    expect_match(msg, "No shared disease endpoint")
    expect_match(msg, "cause")
  })

  it("can turn validation into a hard error", {
    d <- .attr_small_long()
    d$mort_rate$mortrate[1] <- -1
    # the validation warnings that precede the stop are not what this test is
    # about; they have their own tests in test-schema-detect.R
    expect_error(
      suppressWarnings(
        mortality(
          crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
          pop_total = d$pop_total, age_struc = d$age_struc,
          mort_rate = d$mort_rate, mort_lvl = "location", validate = "stop"
        )
      ),
      "validation failed"
    )
  })

  it("stops when a file path does not exist", {
    d <- .attr_small_long()
    expect_error(
      mortality(
        crf = "GEMM", calc_fild = d$calc_fild,
        conc_real = "no/such/file.tif", pop_total = d$pop_total,
        age_struc = d$age_struc, mort_rate = d$mort_rate
      ),
      "File not found"
    )
  })

  it("prints no dplyr natural-join messages", {
    # The internal joins pass their keys explicitly; dplyr's one-message-per-
    # natural-join output used to bury the run's own messages.
    msgs <- suppressWarnings(capture_messages(.attr_run(validate = "warn")))
    expect_false(any(grepl("Joining with", msgs)))
  })
})

describe("mortality() on the shipped example data", {
  it("reproduces the reference GEMM / base2015 / location total", {
    out <- suppressWarnings(suppressMessages(mortality(
      crf        = "GEMM",
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
