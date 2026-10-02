# Tests for decompose() — driving-factor decomposition
#
# The small fixture has one domain, four cells and two age groups; a second
# scenario is added so that `from`/`to` each carry the full set of inputs. The
# point of the tests is that the decomposition is not a separate calculation:
# every column must reproduce a mortality() run with a specific prefix of the
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
.decomp_all <- function(d, groups = .attr_groups(d)) {
  out <- NULL
  suppressWarnings(suppressMessages(
    utils::capture.output(out <- decompose(
      crf = "GEMM", calc_fild = d$calc_fild,
      from = groups$from, to = groups$to, mort_lvl = "location"
    ))
  ))
  out
}

# decompose() returns all 24 orderings in one call; the tests want one at a
# time, so the default fixture's list is computed once and reused.
.decomp_cache <- new.env(parent = emptyenv())
.decomp_run <- function(serie, d, groups = NULL) {
  if (!is.null(groups)) {
    return(.decomp_all(d, groups)[[serie]])
  }
  if (is.null(.decomp_cache$base)) {
    .decomp_cache$base <- .decomp_all(d)
  }
  .decomp_cache$base[[serie]]
}

# One mortality() run with an explicit scenario per input, matching what a
# decomposition step would compute for that prefix of drivers.
.decomp_one <- function(d, pop = "base2015", age = "base2015",
                        conc = "base2015", conc_cf = NULL, mort = "base2015") {
  args <- list(
    crf = "GEMM", calc_fild = d$calc_fild,
    conc_real = .slice_conc(d$conc_real, conc),
    pop_total = .slice_pop(d$pop_total, pop),
    age_struc = .slice_age(d$age_struc, age, min_age_groups = 0),
    mort_rate = .slice_mort(d$mort_rate, mort),
    mort_lvl = "location", validate = "off"
  )
  if (!is.null(conc_cf)) args$conc_cf <- .slice_conc(d$conc_real, conc_cf)
  do.call(mortality, args)
}

# Long-format value column of a grid-level result, in the same cell-major row
# order decompose() itself uses.
.decomp_long <- function(wide) {
  value_cols <- setdiff(names(wide), c("x", "y", "location"))
  wide |>
    tidyr::pivot_longer(
      tidyr::all_of(value_cols), names_to = "Cause_Age", values_to = "value"
    )
}

describe("decompose() permutations", {
  it("maps serie 1..24 onto the documented driver order", {
    perms <- AttrMort:::.permutations(AttrMort:::.DRIVER_ORDER)
    expect_length(perms, 24L)
    expect_equal(length(unique(vapply(perms, paste, "", collapse = "-"))), 24L)

    expect_equal(perms[[1]], c("PG", "PA", "EXP", "ORF"))
    expect_equal(perms[[13]], c("EXP", "PG", "PA", "ORF"))
    expect_equal(perms[[24]], c("ORF", "EXP", "PA", "PG"))
  })

  it("returns one named data.frame per ordering", {
    d   <- .attr_two_scenario()
    all <- .decomp_all(d)

    expect_type(all, "list")
    expect_length(all, 24L)
    expect_equal(names(all)[1], "PG-PA-EXP-ORF")
    expect_equal(names(all)[24], "ORF-EXP-PA-PG")
    expect_equal(length(unique(names(all))), 24L)
    expect_true(all(vapply(all, is.data.frame, TRUE)))

    # the labels are the orderings themselves, and every table carries the
    # same four drivers, in the order its label names them
    for (nm in names(all)) {
      expect_equal(names(all[[nm]])[6:9], strsplit(nm, "-", fixed = TRUE)[[1]])
    }
  })
})

describe("decompose() takes two groups of inputs", {
  it("accepts a group whose value column is canonical or scenario-named", {
    d <- .attr_two_scenario()
    groups <- .attr_groups(d)
    # The same tables, with the exposure column spelled canonically instead of
    # after the scenario: a group carries one value per role, either way.
    canonical <- groups
    canonical$from$conc_real <- d$conc_real[c("x", "y", "base2015")] |>
      rename(conc = "base2015")
    canonical$to$conc_real <- d$conc_real[c("x", "y", "SSP1_2030")] |>
      rename(conc = "SSP1_2030")

    expect_equal(.decomp_run(2, d, canonical), .decomp_run(2, d),
                 tolerance = 1e-12)
  })

  it("returns nothing to attribute when both groups are the same data", {
    d      <- .attr_two_scenario()
    groups <- .attr_groups(d)
    groups$to <- groups$from

    out <- .decomp_run(1, d, groups)

    expect_equal(out$Start, out$End, tolerance = 1e-12)
    for (driver in c("PG", "PA", "EXP", "ORF")) {
      expect_equal(out[[driver]], rep(0, nrow(out)), tolerance = 1e-12,
                   info = driver)
    }
  })

  it("rejects a group that is not a complete set of roles", {
    d      <- .attr_two_scenario()
    groups <- .attr_groups(d)

    expect_error(.decomp_run(1, d, list(from = groups$from, to = d$conc_real)),
                 "must be a list of input tables")
    expect_error(
      .decomp_run(1, d, list(from = groups$from[setdiff(names(groups$from), "age_struc")],
                             to = groups$to)),
      "missing: age_struc"
    )
    expect_error(
      .decomp_run(1, d, list(from = c(groups$from, list(concentration = 1)),
                             to = groups$to)),
      "Unknown element"
    )
  })
})

describe("decompose() on the small fixture", {
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

  it("isolates each step in the driver that moved, for every ordering", {
    # Every column is the difference between two consecutive prefixes of the
    # ordering, so a step may only move the driver it is named after (and PA
    # only moves the age structure, PG only the population, and so on). Checked
    # for all 24 orderings: the shipped code satisfied it for 20 of them, its
    # `PG EXP` second step read the population at `from` and the age structure
    # at `to` -- which moved PA's share into the EXP column.
    d     <- .attr_two_scenario()
    perms <- AttrMort:::.permutations(AttrMort:::.DRIVER_ORDER)
    # A reference run depends only on which drivers have moved, and the 24
    # orderings pass through 15 prefixes between them, so they are computed
    # once each rather than once per ordering.
    cache <- new.env(parent = emptyenv())
    reference <- function(moved) {
      key <- str_c(as.integer(c("PG", "PA", "EXP", "ORF") %in% moved),
                   collapse = "")
      if (is.null(cache[[key]])) {
        picked <- function(driver) {
          if (driver %in% moved) "SSP1_2030" else "base2015"
        }
        cache[[key]] <- .decomp_long(.decomp_one(
          d, pop = picked("PG"), age = picked("PA"), conc_cf = picked("EXP"),
          conc = picked("ORF"), mort = picked("ORF")
        ))$value
      }
      cache[[key]]
    }

    for (s in seq_along(perms)) {
      out  <- .decomp_run(s, d)
      step <- perms[[s]]

      prev <- reference(character(0))
      for (k in seq_len(4)) {
        run <- reference(step[seq_len(k)])

        expect_equal(out[[step[k]]], run - prev, tolerance = 1e-12,
                     info = paste("serie", s, "step", k, step[k]))
        prev <- run
      }
    }
  })

  it("keeps the CI branch it was given", {
    d      <- .attr_two_scenario()
    groups <- .attr_groups(d)
    low    <- NULL
    suppressWarnings(suppressMessages(
      utils::capture.output(low <- decompose(
        crf = "GEMM", ci = "LOW", calc_fild = d$calc_fild,
        from = groups$from, to = groups$to, mort_lvl = "location"
      ))
    ))
    mean_ <- .decomp_run(1, d)

    expect_equal(nrow(low), 8L)
    expect_false(isTRUE(all.equal(sum(low$End), sum(mean_$End))))
  })
})
    low   <- low[[1]]
