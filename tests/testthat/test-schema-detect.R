# Tests for column-name detection and input validation

describe("detect_columns()", {
  it("maps arbitrary column names onto the canonical semantics", {
    df <- data.frame(age_group = 1:3, Country = LETTERS[1:3],
                     mortality_rate = c(1, 2, 3))
    map <- suppressWarnings(
      AttrMort:::detect_columns(df, schema = c("age", "mortrate", "location"),
                                quiet = TRUE)
    )
    expect_equal(unname(map[c("age", "mortrate", "location")]),
                 c("age_group", "mortality_rate", "Country"))
  })

  it("recognises the documented aliases", {
    expect_equal(
      unname(AttrMort:::detect_columns(data.frame(fraction = 1),
                                       schema = "prop", quiet = TRUE)),
      "fraction"
    )
    expect_equal(
      unname(AttrMort:::detect_columns(data.frame(Endpoint = "copd"),
                                       schema = "cause", quiet = TRUE)),
      "Endpoint"
    )
  })

  it("assigns a column to at most one semantic field", {
    map <- AttrMort:::detect_columns(
      data.frame(age = 1, age_group = 2),
      schema = c("age", "prop"), quiet = TRUE
    )
    expect_equal(length(unique(unname(map))), length(map))
  })

  it("stays silent when asked to", {
    expect_silent(
      AttrMort:::detect_columns(data.frame(zzz = 1), schema = "age",
                                quiet = TRUE)
    )
  })
})

describe("canonical column names", {
  it("renames detected columns onto the pipeline schema", {
    df <- data.frame(age_group = "25", Country = "A", Endpoint = "copd",
                     mortality_rate = 1, stringsAsFactors = FALSE)
    out <- suppressMessages(
      AttrMort:::.ingest_and_map(
        df, schema = c("age", "cause", "mortrate", "location"),
        label = "mort_rate"
      )
    )
    expect_true(all(c("age", "endpoint", "mortrate", "location") %in% names(out)))
    expect_false("Endpoint" %in% names(out))
  })

  it("keeps an existing canonical column instead of overwriting it", {
    df <- data.frame(age = "25", age_group = "26", endpoint = "copd")
    out <- suppressMessages(
      AttrMort:::.ingest_and_map(df, schema = c("age", "cause"),
                                 label = "mort_rate")
    )
    expect_equal(out$age, "25")
  })

  it("renders numeric coordinate columns as character keys", {
    df <- data.frame(x = c(1.25, 2.5), y = c(3, 4), conc = c("10", "20"))
    out <- AttrMort:::.ingest_and_map(df, schema = "location", dgt_coord = 2)
    expect_type(out$x, "character")
    expect_equal(out$x, c("1.25", "2.5"))
    expect_equal(out$y, c("3", "4"))
  })

  it("keeps numeric coordinates when dgt_coord is too coarse to distinguish them", {
    df <- data.frame(x = c(1.001, 1.002), y = c(2, 2), conc = c("10", "20"))
    expect_warning(
      out <- AttrMort:::.ingest_and_map(df, schema = "location",
                                        dgt_coord = 2),
      "stay unique"
    )
    expect_type(out$x, "double")
  })
})

describe("validate_mortality_input()", {
  it("returns an empty report for clean inputs", {
    d <- .attr_small_long()
    report <- suppressWarnings(AttrMort:::validate_mortality_input(
      list(conc = d$conc_real, pop = d$pop_total, age_struc = d$age_struc,
           mort_rate = d$mort_rate),
      cr_model = "GEMM"
    ))
    expect_true(report$valid)
    expect_length(report$blocking, 0)
  })

  it("blocks on negative rates and reports them", {
    d <- .attr_small_long()
    d$mort_rate$mortrate[1] <- -5
    report <- suppressWarnings(AttrMort:::validate_mortality_input(
      list(conc = d$conc_real, pop = d$pop_total, age_struc = d$age_struc,
           mort_rate = d$mort_rate),
      cr_model = "GEMM"
    ))
    expect_false(report$valid)
    expect_match(report$blocking, "negative")
  })

  it("blocks when none of the model's endpoints are present", {
    d <- .attr_small_long()
    report <- suppressWarnings(AttrMort:::validate_mortality_input(
      list(conc = d$conc_real, pop = d$pop_total, age_struc = d$age_struc,
           mort_rate = d$mort_rate),
      cr_model = "NO2"
    ))
    expect_false(report$valid)
    expect_match(report$blocking, "none of the endpoints")
  })

  it("warns about implausible rates without blocking", {
    d <- .attr_small_long()
    d$mort_rate$mortrate[1] <- 1e5
    # a complete standard age structure: this test is about the rate warning,
    # not the age-completeness warning
    d$age_struc <- data.frame(
      location = "A", age = as.character(seq(0, 95, 5)), prop = 1 / 20
    )
    expect_warning(
      report <- AttrMort:::validate_mortality_input(
        list(conc = d$conc_real, pop = d$pop_total, age_struc = d$age_struc,
             mort_rate = d$mort_rate),
        cr_model = "GEMM"
      ),
      "above"
    )
    expect_true(report$valid)
  })

  it("warns about concentration keys that are not canonical at dgt_conc", {
    capture_warnings <- function(data_list) {
      warns <- character(0)
      report <- withCallingHandlers(
        AttrMort:::validate_mortality_input(
          data_list, cr_model = "GEMM", dgt_conc = 1
        ),
        warning = function(w) {
          warns <<- c(warns, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      )
      list(report = report, warns = warns)
    }

    d <- .attr_small_long()
    d$conc_real$conc[1] <- "10.00"          # parseable, not matchable(10, 1)
    res <- capture_warnings(list(conc = d$conc_real, pop = d$pop_total,
                                 age_struc = d$age_struc,
                                 mort_rate = d$mort_rate))
    expect_true(any(grepl("dgt_conc", res$warns)))
    expect_true(res$report$valid)           # a key problem is not blocking

    d$conc_real$conc[1] <- "10"             # canonical: no key warning
    res <- capture_warnings(list(conc = d$conc_real, pop = d$pop_total,
                                 age_struc = d$age_struc,
                                 mort_rate = d$mort_rate))
    expect_false(any(grepl("dgt_conc", res$warns)))
  })
})
