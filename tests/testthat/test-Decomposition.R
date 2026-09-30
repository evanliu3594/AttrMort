# Tests for Decomposition() — driving-factor decomposition
#
# The small fixture has one domain, four cells and two age groups; a second
# scenario is added so that `from`/`to` each carry the full set of inputs. The
# point of the tests is that the decomposition is not a separate calculation:
# every column must reproduce a Mortality() run with a specific prefix of the
# drivers switched from `from` to `to`.

.attr_two_scenario <- function() {
  s <- .attr_small()
  s$conc_real$SSP1_2030 <- c(8, 16, 24, 32)
  s$pop_total$SSP1_2030 <- c(110, 210, 310, 410)
  s$age_struc$SSP1_2030 <- c(0.4, 0.6)
  s$mort_rate$SSP1_2030 <- c(900, 2100)
  s
}

# Run Decomposition() quietly (it prints its summary with cat()) and return
# the data.frame.
.decomp_run <- function(serie, d) {
  out <- NULL
  suppressWarnings(suppressMessages(
    utils::capture.output(out <- Decomposition(
      serie = serie, crf = "GEMM", G = d$calc_fild,
      D = d$conc_real, P = d$pop_total, A = d$age_struc,
      M = d$mort_rate, L = "location",
      from = "base2015", to = "SSP1_2030"
    ))
  ))
  out
}

# One Mortality() run with an explicit scenario per input, matching what a
# decomposition step would compute for that prefix of drivers.
.decomp_one <- function(d, pop = "base2015", age = "base2015",
                        conc = "base2015", conc_cf = NULL, mort = "base2015") {
  args <- list(
    CRF = "GEMM", calc_fild = d$calc_fild,
    conc_real = getConc(d$conc_real, conc),
    pop_total = getPop(d$pop_total, pop),
    age_struc = getAge(d$age_struc, age, min_age_groups = 0),
    mort_rate = getMort(d$mort_rate, mort),
    mort_lvl = "location", validate = "off"
  )
  if (!is.null(conc_cf)) args$conc_cf <- getConc(d$conc_real, conc_cf)
  do.call(Mortality, args)
}

# Long-format value column of a grid-level result, in the same cell-major row
# order Decomposition() itself uses.
.decomp_long <- function(wide) {
  value_cols <- setdiff(names(wide), c("x", "y", "location"))
  wide |>
    tidyr::pivot_longer(
      tidyr::all_of(value_cols), names_to = "Cause_Age", values_to = "value"
    )
}

describe("Decomposition() permutations", {
  it("maps serie 1..24 onto the documented driver order", {
    perms <- AttrMort:::.permutations(AttrMort:::.DRIVER_ORDER)
    expect_length(perms, 24L)
    expect_equal(length(unique(vapply(perms, paste, "", collapse = "-"))), 24L)

    expect_equal(perms[[1]], c("PG", "PA", "EXP", "ORF"))
    expect_equal(perms[[13]], c("EXP", "PG", "PA", "ORF"))
    expect_equal(perms[[24]], c("ORF", "EXP", "PA", "PG"))
  })

  it("rejects a serie outside 1..24", {
    d <- .attr_two_scenario()
    expect_error(.decomp_run(0, d), "between 1 and 24")
    expect_error(.decomp_run(25, d), "between 1 and 24")
  })
})

describe("Decomposition() on the small fixture", {
  it("returns Start, the four drivers in serie order, and End", {
    d   <- .attr_two_scenario()
    out <- .decomp_run(1, d)

    expect_s3_class(out, "data.frame")
    expect_equal(names(out),
                 c("x", "y", "location", "Cause_Age",
                   "Start", "PG", "PA", "EXP", "ORF", "End"))
    # four cells x two age strata
    expect_equal(nrow(out), 8L)
  })

  it("starts at the `from` run and ends at the `to` run", {
    d    <- .attr_two_scenario()
    out  <- .decomp_run(1, d)
    from <- .decomp_one(d)
    to   <- .decomp_one(d, pop = "SSP1_2030", age = "SSP1_2030",
                        conc = "SSP1_2030", mort = "SSP1_2030")

    expect_equal(out$Start, .decomp_long(from)$value)
    expect_equal(out$End,   .decomp_long(to)$value)
  })

  it("isolates each driver as the difference to the previous prefix", {
    d   <- .attr_two_scenario()
    out <- .decomp_run(1, d)          # PG, PA, EXP, ORF

    base <- .decomp_long(.decomp_one(d))$value
    pg   <- .decomp_long(.decomp_one(d, pop = "SSP1_2030"))$value
    pa   <- .decomp_long(.decomp_one(d, pop = "SSP1_2030", age = "SSP1_2030"))$value
    exp_ <- .decomp_long(.decomp_one(d, pop = "SSP1_2030", age = "SSP1_2030",
                                     conc_cf = "SSP1_2030"))$value
    orf  <- .decomp_long(.decomp_one(d, pop = "SSP1_2030", age = "SSP1_2030",
                                     conc = "SSP1_2030",
                                     conc_cf = "SSP1_2030",
                                     mort = "SSP1_2030"))$value

    expect_equal(out$PG,  pg - base)
    expect_equal(out$PA,  pa - pg)
    expect_equal(out$EXP, exp_ - pa)
    expect_equal(out$ORF, orf - exp_)
  })

  it("telescopes to the total change and keeps it across orderings", {
    d <- .attr_two_scenario()
    a <- .decomp_run(1, d)
    b <- .decomp_run(24, d)

    expect_equal(a$Start, b$Start)
    expect_equal(a$End,   b$End)
    expect_equal(a$PG + a$PA + a$EXP + a$ORF, a$End - a$Start)
    expect_equal(b$PG + b$PA + b$EXP + b$ORF, b$End - b$Start)

    # The ordering is what changes one driver's contribution: the same total
    # change is split differently.
    expect_false(isTRUE(all.equal(a$PG, b$PG)))
  })

  it("keeps the CI branch it was given", {
    d   <- .attr_two_scenario()
    low <- NULL
    suppressWarnings(suppressMessages(
      utils::capture.output(low <- Decomposition(
        serie = 1, crf = "GEMM", ci = "LOW", G = d$calc_fild,
        D = d$conc_real, P = d$pop_total, A = d$age_struc,
        M = d$mort_rate, L = "location",
        from = "base2015", to = "SSP1_2030"
      ))
    ))
    mean_ <- .decomp_run(1, d)

    expect_equal(nrow(low), 8L)
    expect_false(isTRUE(all.equal(sum(low$End), sum(mean_$End))))
  })
})
