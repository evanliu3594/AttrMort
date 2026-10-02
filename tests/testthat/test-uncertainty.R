# Tests for the aggregation and uncertainty arguments of mortality()

describe("mortality(aggregate = ...)", {
  it("sums the grid-level burdens within a domain", {
    grid <- .attr_run()
    agg  <- .attr_run(aggregate = TRUE)

    expect_true(all(c("location", "total", "conc_pwe") %in% names(agg)))
    expect_equal(nrow(agg), 1)

    vals <- grid[vapply(grid, is.numeric, logical(1))]
    expect_equal(agg$total, sum(as.matrix(vals)), tolerance = 1e-10)
  })

  it("aggregates onto an explicitly named column vector", {
    d <- .attr_small_long()
    d$calc_fild$region <- "R1"
    agg <- mortality(
      crf = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
      pop_total = d$pop_total, age_struc = d$age_struc,
      mort_rate = d$mort_rate, mort_lvl = "location",
      aggregate = c("region", "location"), validate = "off"
    )
    expect_true(all(c("region", "location", "total") %in% names(agg)))
    expect_equal(nrow(agg), 1)
  })

  it("keeps the requested breakdown of the endpoint and age dimensions", {
    by_endpoint <- .attr_run(aggregate = TRUE, aggregate_by = "endpoint")
    expect_true(any(grepl("_all$", names(by_endpoint))))

    by_age <- .attr_run(aggregate = TRUE, aggregate_by = "age")
    expect_true(any(grepl("^all_", names(by_age))))

    by_all <- .attr_run(aggregate = TRUE, aggregate_by = "all")
    expect_true(all(c("ncd+lri_25", "ncd+lri_30") %in% names(by_all)))
    expect_true(all(c("total", "conc_pwe") %in% names(by_all)))
  })

  it("reports population-weighted exposure", {
    agg <- .attr_run(aggregate = TRUE)
    d   <- .attr_run()
    expected <- weighted.mean(
      as.numeric(.attr_small_long()$conc_real$conc),
      .attr_small_long()$pop_total$pop
    )
    expect_equal(agg$conc_pwe, expected, tolerance = 1e-12)
    expect_true(is.data.frame(d))
  })

  it("falls back to the whole field when aggregate = TRUE and mort_lvl is NULL", {
    # An uncalibrated run is a documented mode, not a fault: it is reported
    # with a message rather than a warning.
    expect_message(
      agg <- suppressWarnings(.attr_run(aggregate = TRUE, mort_lvl = NULL, validate = "warn")),
      "whole field"
    )
    expect_message(
      suppressWarnings(.attr_run(aggregate = TRUE, mort_lvl = NULL, validate = "warn")),
      "not calibrated against"
    )
    expect_equal(nrow(agg), 1)
    expect_true("total" %in% names(agg))
  })

  it("reports a whole-field range when aggregate = TRUE and mort_lvl is NULL", {
    # Uncalibrated grid-level runs aggregate to one row with `at = character(0)`;
    # the range must be attached to that row instead of erroring.
    agg <- suppressMessages(
      .attr_run(aggregate = TRUE, mort_lvl = NULL, uncertain = TRUE)
    )
    expect_equal(nrow(agg), 1)
    expect_true(all(c("total", "conc_pwe", "CI_LOW", "CI_UP") %in% names(agg)))
    expect_lte(agg$CI_LOW, agg$total)
    expect_lte(agg$total, agg$CI_UP)
  })

  it("rejects an unsupported aggregate value or breakdown", {
    expect_error(.attr_run(aggregate = 42), "must be NULL, TRUE")
    expect_error(.attr_run(aggregate = TRUE, aggregate_by = "nope"),
                 "should be one of")
  })

  it("leaves the grid-level result untouched when aggregate is NULL", {
    grid <- .attr_run()
    expect_false("total" %in% names(grid))
    expect_equal(nrow(grid), 4)
  })
})

describe("mortality(uncertain = TRUE)", {
  run_ci <- function(index, ...) {
    d <- .attr_small_long()
    mortality(
      crf = "GEMM", ci = index, calc_fild = d$calc_fild,
      conc_real = d$conc_real, pop_total = d$pop_total,
      age_struc = d$age_struc, mort_rate = d$mort_rate,
      mort_lvl = "location", validate = "off", ...
    )
  }
  total_of <- function(x) {
    vals <- x[vapply(x, is.numeric, logical(1))]
    sum(as.matrix(vals))
  }

  it("brackets the central estimate", {
    agg <- .attr_run(aggregate = TRUE, uncertain = TRUE)
    expect_true(all(c("CI_LOW", "CI_UP") %in% names(agg)))
    expect_lte(agg$CI_LOW, agg$total)
    expect_lte(agg$total, agg$CI_UP)
  })

  it("equals the sum of the per-cell low and high tables", {
    agg <- .attr_run(aggregate = TRUE, uncertain = TRUE)
    expect_equal(agg$total,  total_of(run_ci("MEAN")), tolerance = 1e-10)
    expect_equal(agg$CI_LOW, total_of(run_ci("LOW")),  tolerance = 1e-10)
    expect_equal(agg$CI_UP,  total_of(run_ci("UP")),   tolerance = 1e-10)
  })

  it("also reports a range at grid level", {
    grid <- .attr_run(uncertain = TRUE)
    low  <- run_ci("LOW")
    expect_true(all(c("CI_LOW", "CI_UP") %in% names(grid)))
    expect_equal(nrow(grid), 4)
    expect_true(all(grid$CI_LOW <= grid$CI_UP))
    expect_equal(grid$CI_LOW,
                 as.numeric(rowSums(as.matrix(
                   low[vapply(low, is.numeric, logical(1))]
                 ))),
                 tolerance = 1e-10)
  })

  it("widens the range when exposure uncertainty is included", {
    cr_only   <- .attr_run(aggregate = TRUE, uncertain = TRUE)
    with_conc <- .attr_run(aggregate = TRUE, uncertain = TRUE, conc_uncert = 20)
    expect_gte(with_conc$CI_UP, cr_only$CI_UP)
    expect_lte(with_conc$CI_LOW, cr_only$CI_LOW)
  })

  it("rejects a negative conc_uncert and a non-logical uncertain", {
    expect_error(.attr_run(conc_uncert = -1), "non-negative")
    expect_error(.attr_run(uncertain = "yes"), "TRUE or FALSE")
  })
})
