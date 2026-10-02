# Numeric anchors ---------------------------------------------------------
#
# The other test files check that mortality() behaves as documented. This one
# checks that its *numbers* are the published formula's numbers: an independent
# second implementation of the PWRR branch, written in base R and joined by
# hand, is compared against a full run on the shipped example grid (6000 cells,
# three fictional countries, 20 age strata, 8 endpoints).
#
# Given  - the shipped example workbooks, reduced to one scenario
# When   - the attributable deaths are recomputed from those same tables with
#          merge() and the formula in AGENTS.md section 4
# Then   - the run matches the reconstruction cell for cell and stratum for
#          stratum, the domain summary is the sum of the grid cells, and the
#          per-100,000 conversion is applied exactly once

# The shipped example in canonical long form for one scenario. The grid info
# carries the domain labels, so `calc_fild` is the example's own grid.
.vn_example <- function(scenario = "base2015") {
  info <- .attr_data("grid_info")
  conc <- .attr_data("grid_exposure")[, c("x", "y", scenario), drop = FALSE]
  pop  <- .attr_data("grid_pop")[, c("x", "y", scenario), drop = FALSE]
  names(conc)[3] <- "conc"
  names(pop)[3]  <- "pop"

  age_struc <- .attr_data("national_age_structure")[, c("location", "age", scenario),
                                                    drop = FALSE]
  mort_rate <- .attr_data("national_mortality")[, c("location", "age", "endpoint",
                                                    scenario), drop = FALSE]
  names(age_struc)[3] <- "prop"
  names(mort_rate)[4] <- "mortrate"

  list(calc_fild = as.data.frame(info),
       conc_real = as.data.frame(conc),
       pop_total = as.data.frame(pop),
       age_struc = as.data.frame(age_struc),
       mort_rate = as.data.frame(mort_rate))
}

# The reconstruction. Base R only: merge() for the joins, weighted.mean() for
# the calibration, and the formula from AGENTS.md section 4 written out.
#   M_cell = pop * prop * mortrate / 1e5
#   PWRR   = weighted.mean(RR(conc_real), pop)   over (location, endpoint, age)
#   attr   = M_cell * (RR(conc_cf) - 1) / PWRR
.vn_hand <- function(d, rr_tbl, conc_cf = NULL) {
  if (is.null(conc_cf)) {
    conc_cf <- d$conc_real
  }

  # The concentration key is the documented one: character, dgt_conc digits.
  key <- function(v) as.character(round(v, 1))
  rr_tbl$conc <- as.character(rr_tbl$conc)

  # ── PWRR: the real exposure, population weighted, per stratum ──────
  # The package joins this set on `conc` alone (it is the only name the four
  # frames share), so the endpoint and age come from the lookup table.
  pw <- merge(d$calc_fild, d$conc_real, by = c("x", "y"))
  pw <- merge(pw, d$pop_total, by = c("x", "y"))
  pw$conc_key <- key(pw$conc)
  pw <- merge(pw, rr_tbl[, c("conc", "endpoint", "age", "RR")],
              by.x = "conc_key", by.y = "conc")
  pwr <- do.call(rbind, lapply(split(pw, list(pw$location, pw$endpoint, pw$age)),
                               function(g) {
    data.frame(location = g$location[1], endpoint = g$endpoint[1],
               age = g$age[1],
               PWRR = stats::weighted.mean(g$RR, g$pop, na.rm = TRUE))
  }))

  # ── the per-cell burden ───────────────────────────────────────────
  m <- merge(d$calc_fild, conc_cf, by = c("x", "y"))
  names(m)[names(m) == "conc"] <- "conc_cf"
  m <- merge(m, d$pop_total, by = c("x", "y"))
  # The mortality table comes first: it carries `age` and `endpoint`, which the
  # age structure and the lookup are then joined on.
  m <- merge(m, d$mort_rate, by = "location")
  m <- merge(m, d$age_struc, by = c("location", "age"))
  m$conc_key <- key(m$conc_cf)
  m <- merge(m, rr_tbl[, c("conc", "endpoint", "age", "RR")],
             by.x = c("conc_key", "endpoint", "age"),
             by.y = c("conc", "endpoint", "age"))
  m <- merge(m, pwr, by = c("location", "endpoint", "age"))

  m$mort_base <- m$pop * m$prop * m$mortrate / 1e5
  m$attr_mort <- m$mort_base * (m$RR - 1) / m$PWRR
  m
}

# Pivot the reconstruction to the wide shape mortality() returns.
.vn_wide <- function(m) {
  m$col <- paste0(m$endpoint, "_", m$age)
  wide <- stats::reshape(
    m[, c("x", "y", "location", "col", "attr_mort")],
    idvar = c("x", "y", "location"), timevar = "col", direction = "wide"
  )
  names(wide) <- sub("^attr_mort\\.", "", names(wide))
  wide
}

describe("the PWRR branch on the shipped example grid", {
  it("reproduces mortality() from an independent reconstruction", {
    d  <- .vn_example()
    rr <- rr_std("GEMM", "MEAN")
    rr <- rr[rr$endpoint == "ncd+lri", ]

    # One endpoint only, so the run cannot be doing anything else.
    d$mort_rate <- d$mort_rate[d$mort_rate$endpoint == "ncd+lri", ]

    out <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))

    hand <- .vn_wide(.vn_hand(d, rr))
    vcols <- grep("^ncd\\+lri_[0-9]+$", names(out), value = TRUE)
    expect_gt(length(vcols), 0)
    expect_equal(nrow(out), nrow(d$calc_fild))

    key_run  <- paste(out$x, out$y)
    key_hand <- paste(hand$x, hand$y)
    expect_equal(sort(key_run), sort(key_hand))

    i <- match(key_run, key_hand)
    for (cn in vcols) {
      expect_equal(out[[cn]], hand[[cn]][i], tolerance = 1e-10,
                   label = paste0("column ", cn))
    }

    # The reconstruction must actually carry a calibration term: without it the
    # comparison above would pass on a degenerate PWRR of 1.
    expect_true(all(hand$PWRR > 1))
  })

  it("keeps the two exposure roles apart when conc_cf differs", {
    d  <- .vn_example()
    rr <- rr_std("GEMM", "MEAN")
    rr <- rr[rr$endpoint == "ncd+lri", ]
    d$mort_rate <- d$mort_rate[d$mort_rate$endpoint == "ncd+lri", ]

    # Counterfactual exposure: every cell at 5 ug/m3, which is not what the
    # calibration averages over.
    cf <- d$conc_real
    cf$conc <- 5

    out <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      conc_cf = cf, pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))

    hand <- .vn_wide(.vn_hand(d, rr, conc_cf = cf))
    i    <- match(paste(out$x, out$y), paste(hand$x, hand$y))
    for (cn in grep("^ncd\\+lri_[0-9]+$", names(out), value = TRUE)) {
      expect_equal(out[[cn]], hand[[cn]][i], tolerance = 1e-10,
                   label = paste0("column ", cn))
    }
  })

  it("sums the grid cells to the domain summary", {
    d  <- .vn_example()
    d$mort_rate <- d$mort_rate[d$mort_rate$endpoint == "ncd+lri", ]

    grid <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))
    dom <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off",
      aggregate = TRUE
    ))

    vcols <- grep("^ncd\\+lri_[0-9]+$", names(grid), value = TRUE)
    expect_equal(nrow(dom), length(unique(d$calc_fild$location)))
    expect_true("total" %in% names(dom))

    # The domain total is the grid result summed over the domain's cells, one
    # row per domain (AGENTS.md section 4).
    by_domain <- vapply(split(seq_len(nrow(grid)), grid$location), function(i) {
      sum(as.matrix(grid[i, vcols]))
    }, numeric(1))
    expect_equal(dom$total[match(names(by_domain), dom$location)],
                 unname(by_domain), tolerance = 1e-12)
  })
})

# A two-cell fixture whose attributable deaths are known in closed form: no
# lookup-driven reconstruction, just the arithmetic the contract states.
.vn_closed_form <- function() {
  fld <- data.frame(x = c("0", "1"), y = c("0", "0"), location = "A")
  list(
    calc_fild = fld,
    conc_real = data.frame(fld[, c("x", "y")], conc = c(10, 30)),
    pop_total = data.frame(fld[, c("x", "y")], pop = c(1e5, 1e5)),
    age_struc = data.frame(location = "A", age = "25", prop = 0.5),
    mort_rate = data.frame(location = "A", age = "25", endpoint = "ncd+lri",
                           mortrate = 200)
  )
}

describe("the per-100,000 conversion", {
  it("is applied exactly once, and the calibration is the population mean", {
    d  <- .vn_closed_form()
    rr <- rr_std("GEMM", "MEAN")
    rr <- rr[rr$endpoint == "ncd+lri" & rr$age == "25", ]
    rr_of <- function(cc) rr$RR[match(as.character(round(cc, 1)), rr$conc)]

    out <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))

    # 1e5 people x 0.5 x 200 / 1e5 = 100 baseline deaths in each cell. The
    # literal 100 is that hand computation: a second division by 1e5 would put
    # the answer at 1e-3 instead.
    pwrr <- mean(c(rr_of(10), rr_of(30)))
    expect_equal(out[["ncd+lri_25"]],
                 100 * (c(rr_of(10), rr_of(30)) - 1) / pwrr,
                 tolerance = 1e-12)
    expect_equal(sum(out[["ncd+lri_25"]]),
                 100 * sum(c(rr_of(10), rr_of(30)) - 1) / pwrr,
                 tolerance = 1e-12)
  })

  it("scales the answer linearly with the baseline rate", {
    d   <- .vn_closed_form()
    base <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))
    d$mort_rate$mortrate <- d$mort_rate$mortrate * 7
    scaled <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location", validate = "off"
    ))
    expect_equal(scaled[["ncd+lri_25"]], base[["ncd+lri_25"]] * 7,
                 tolerance = 1e-12)
  })

  it("has no calibration term in the grid-level branch", {
    d <- .vn_closed_form()
    rr <- rr_std("GEMM", "MEAN")
    rr <- rr[rr$endpoint == "ncd+lri" & rr$age == "25", ]
    rr_v <- rr$RR[match(as.character(round(c(10, 30), 1)), rr$conc)]

    out <- suppressWarnings(mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = NULL, validate = "off"
    ))
    expect_equal(out[["ncd+lri_25"]], 100 * (rr_v - 1) / rr_v,
                 tolerance = 1e-12)
  })
})
