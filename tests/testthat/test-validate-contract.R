# Table-side data contract -------------------------------------------------
#
# What the real GBD exports in `validate-data/` broke: duplicated keys when a
# table carries a column the caller did not filter, age columns published as
# labels ("15-19 years") instead of the lookup's stratum keys ("15"), and
# endpoint messages that list the CRF's names without saying what to do with
# them. Every fixture here is synthetic -- the GBD files are not a test
# dependency; the numbers they produced are in
# `diagnosis/validate_table_contract_261002.md`.

# Run `validate_mortality_input()` and collect both the report and the warnings,
# because most of these cases are about *what is said*, not only about `valid`.
.validate_report <- function(data_list, ...) {
  state <- new.env(parent = emptyenv())
  state$warn <- character(0)
  state$info <- character(0)
  report <- withCallingHandlers(
    AttrMort:::validate_mortality_input(data_list, ...),
    warning = function(w) {
      state$warn <- c(state$warn, conditionMessage(w))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      state$info <- c(state$info, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  list(report = report, warn = state$warn, info = state$info)
}

# The shipped small fixture, as the validator sees it: canonical column names.
.contract_inputs <- function(mort_rate = NULL) {
  d <- .attr_small_long()
  list(
    conc = d$conc_real, pop = d$pop_total,
    age_struc = d$age_struc,
    mort_rate = if (is.null(mort_rate)) d$mort_rate else mort_rate
  )
}

# The 20 age labels GBD publishes, in the lookup's stratum order.
.gbd_age_labels <- function() {
  lower <- seq(0, 90, 5)
  c("<5 years", paste0(lower[-1], "-", lower[-1] + 4, " years"), "95+ years")
}

describe("mort_rate key uniqueness", {
  it("blocks a key that appears more than once", {
    d <- .attr_small_long()
    dup <- bind_rows(d$mort_rate, d$mort_rate[1, ])
    res <- .validate_report(.contract_inputs(dup), cr_model = "GEMM")

    expect_false(res$report$valid)
    expect_match(res$report$blocking, "duplicated key")
    expect_match(res$report$blocking, "2 row\\(s\\) share a key")
    expect_match(res$report$blocking, "location = A")
    # nothing outside the key varies: the value is the only difference, and
    # naming it would read as advice to filter on `mortrate`
    expect_match(res$report$blocking, "differ only in `mortrate`")
  })

  it("names the column that fans the key out", {
    d <- .attr_small_long()
    fan <- bind_rows(
      mutate(d$mort_rate, year = 2018),
      mutate(d$mort_rate, year = 2019)
    )
    res <- .validate_report(.contract_inputs(fan), cr_model = "GEMM")

    expect_false(res$report$valid)
    expect_match(res$report$blocking, "duplicated key")
    expect_match(res$report$blocking, "year")
  })

  it("counts duplicated keys, not duplicated rows", {
    d <- .attr_small_long()
    # three rows for the 25 stratum and two for the 30 stratum
    fan <- bind_rows(
      mutate(d$mort_rate, year = 2018),
      d$mort_rate,
      filter(d$mort_rate, age == "25") |> mutate(year = 2020)
    )
    res <- .validate_report(.contract_inputs(fan), cr_model = "GEMM")

    expect_false(res$report$valid)
    expect_match(res$report$blocking, "2 duplicated key\\(s\\)")
    expect_match(res$report$blocking, "5 row\\(s\\) share a key")
  })

  it("stays out of the way when every key is unique", {
    res <- .validate_report(.contract_inputs(), cr_model = "GEMM")

    expect_true(res$report$valid)
    expect_false(any(grepl("duplicated", res$report$issues)))
  })

  it("stops the run under validate = 'stop' and not under validate = 'off'", {
    d <- .attr_small_long()
    dup <- bind_rows(d$mort_rate, d$mort_rate[1, ])
    args <- list(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc, mort_rate = dup,
      mort_lvl = "location"
    )

    expect_error(
      suppressWarnings(do.call(mortality, c(args, list(validate = "stop")))),
      "duplicated key"
    )
    # `validate = "off"` is the documented escape hatch: no reporting at all,
    # so the duplicated keys reach the kernel (and produce list-columns) rather
    # than being blocked here.
    expect_error(
      suppressWarnings(do.call(mortality, c(args, list(validate = "off")))),
      NA
    )
  })
})

describe(".standardize_age_key()", {
  it("translates the labels the lookup tables spell as a stratum", {
    expect_equal(
      AttrMort:::.standardize_age_key(
        c("<5 years", "5-9 years", "15-19 years", "90-94 years", "95+ years")
      ),
      c("0", "5", "15", "90", "95")
    )
    expect_equal(
      AttrMort:::.standardize_age_key(c("<5", "15-19", "95+")),
      c("0", "15", "95")
    )
  })

  it("leaves canonical keys and non-stratum labels exactly as they were", {
    keys <- as.character(seq(0, 95, 5))
    expect_identical(AttrMort:::.standardize_age_key(keys), keys)
    expect_identical(AttrMort:::.standardize_age_key(25), "25")
    expect_identical(AttrMort:::.standardize_age_key(25.4), "25")
    expect_identical(AttrMort:::.standardize_age_key(as.numeric(keys)), keys)
    expect_identical(
      # a single-year label is not a 5-year stratum: mapping it would be a guess
      AttrMort:::.standardize_age_key(c("All ages", "Age-standardized", "1 year")),
      c("All ages", "Age-standardized", "1 year")
    )
  })
})

describe("age labels in a run", {
  it("a labeled age column gives the same numbers as the stratum keys", {
    d <- .attr_small_long()
    labeled <- d
    labeled$age_struc$age <- c("25-29 years", "30-34 years")
    labeled$mort_rate$age <- c("25-29 years", "30-34 years")

    args <- list(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, mort_lvl = "location", validate = "warn"
    )
    keyed <- suppressWarnings(do.call(mortality, c(
      args, list(age_struc = d$age_struc, mort_rate = d$mort_rate)
    )))
    from_labels <- suppressWarnings(do.call(mortality, c(
      args, list(age_struc = labeled$age_struc, mort_rate = labeled$mort_rate)
    )))

    expect_equal(from_labels, keyed)
  })

  it("recognises labeled age_struc rows as the standard strata", {
    d <- .attr_small_long()
    d$age_struc <- data.frame(
      location = "A",
      age = .gbd_age_labels(),
      prop = 1 / length(.gbd_age_labels())
    )

    res <- .validate_report(
      list(conc = d$conc_real, pop = d$pop_total, age_struc = d$age_struc,
           mort_rate = d$mort_rate),
      cr_model = "GEMM"
    )

    expect_false(any(grepl("non-standard age", res$warn)))
    expect_false(any(grepl("standard age group\\(s\\) absent", res$warn)))
  })

  it("reports age values that name no stratum instead of dropping them quietly", {
    d <- .attr_small_long()
    d$mort_rate$age <- c("25", "All ages")

    res <- .validate_report(.contract_inputs(d$mort_rate), cr_model = "GEMM")

    expect_match(res$warn, "not a standard 5-year stratum", all = FALSE)
    expect_match(res$warn, "All ages", all = FALSE)
    expect_true(res$report$valid)   # a dropped stratum is a warning, not a stop
  })
})

describe("endpoint messages", {
  it("says what the model needs and what the table holds", {
    res <- .validate_report(.contract_inputs(), cr_model = "NO2")

    expect_false(res$report$valid)
    expect_match(res$report$blocking, "none of the endpoints")
    expect_match(res$report$blocking, "allcause")     # what the CRF needs
    expect_match(res$report$blocking, "ncd\\+lri")    # what mort_rate holds
    expect_match(res$report$blocking, "does not translate disease names")
  })

  it("warns about a partial match and names both sides", {
    d <- .attr_small_long()
    d$mort_rate <- data.frame(
      location = "A", age = rep(c("25", "30"), each = 2),
      endpoint = rep(c("copd", "Ischemic heart disease"), 2),
      mortrate = c(1000, 900, 2000, 1800)
    )
    res <- .validate_report(.contract_inputs(d$mort_rate), cr_model = "5COD")

    expect_true(res$report$valid)
    expect_match(res$warn, "ihd", all = FALSE)
    expect_match(res$warn, "not translate disease names", all = FALSE)
    expect_match(res$info, "Ischemic heart disease", all = FALSE)
  })
})
