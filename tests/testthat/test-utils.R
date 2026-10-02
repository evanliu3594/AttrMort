# Tests for the wide-to-long helpers and matchable()

describe("matchable()", {
  it("rounds to the requested precision and returns character", {
    expect_equal(matchable(10 / 3), "3.33")
    expect_equal(matchable(10 / 3, 1), "3.3")
    expect_equal(matchable(3.14159, 0), "3")
    expect_type(matchable(1), "character")
  })

  it("keeps values at different resolutions distinct", {
    expect_false(matchable(116.38, 1) == matchable(116.376, 5))
  })
})

describe(".slice_conc()", {
  df <- data.frame(x = c("0", "1"), y = c("0", "1"),
                   base2015 = c(35.24, 41.71), SSP1_2030 = c(30, 28))

  it("extracts one scenario and rounds it to `dgt`", {
    out <- .slice_conc(df, "base2015")
    expect_equal(names(out), c("x", "y", "conc"))
    expect_type(out$conc, "character")
    expect_equal(out$conc, c("35.2", "41.7"))
  })

  it("honours a coarser or finer `dgt`", {
    expect_equal(.slice_conc(df, "base2015", dgt = 0)$conc, c("35", "42"))
    expect_equal(.slice_conc(df, "base2015", dgt = 2)$conc, c("35.24", "41.71"))
  })

  it("falls back to domain columns when there are no coordinates", {
    dom <- data.frame(location = c("A", "B"), base2015 = c(10, 20))
    expect_message(out <- .slice_conc(dom, "base2015"), "joining on")
    expect_equal(names(out), c("location", "conc"))
  })

  it("reports an unknown scenario with the available columns", {
    expect_error(.slice_conc(df, "nope"), "not found in the data")
    expect_error(.slice_conc(df, "nope"), "base2015")
  })

  it("uses the canonical column when the input is not scenario-addressed", {
    canon <- data.frame(x = "0", y = "0", conc = 35.2)
    expect_message(out <- .slice_conc(canon, "base2015"), "not scenario-addressed")
    expect_equal(out$conc, "35.2")
  })

  it("uses the single numeric value column when nothing is named", {
    loose <- data.frame(x = "0", y = "0", Conc2017 = 35.2, source = "WB")
    expect_message(out <- .slice_conc(loose, NULL), "Conc2017")
    expect_equal(out$conc, "35.2")
  })

  it("refuses to pick between several value columns", {
    two <- data.frame(x = c("0", "1"), y = c("0", "1"),
                      Conc2015 = c(35, 36), Conc2017 = c(30, 31))
    expect_error(.slice_conc(two, NULL), "Value candidates")
    expect_error(.slice_conc(two, "base2015"), "Conc2015")
    expect_error(.slice_conc(two, "base2015"), "Conc2017")
  })
})

describe(".slice_pop() / .slice_age() / .slice_mort()", {
  it("renames the scenario column to the canonical name", {
    df <- data.frame(x = "0", y = "0", base2015 = 5)
    expect_equal(names(.slice_pop(df, "base2015")), c("x", "y", "pop"))
  })

  it("renormalises age proportions within each domain", {
    df <- data.frame(
      location = rep(c("A", "B"), each = 2), age = rep(c("25", "30"), 2),
      base2015 = c(3, 1, 1, 1)          # counts, not proportions
    )
    out <- .slice_age(df, "base2015", min_age_groups = 0)
    expect_equal(out$prop[out$location == "A"], c(0.75, 0.25))
    expect_equal(out$prop[out$location == "B"], c(0.5, 0.5))
  })

  it("warns, rather than fails, on an incomplete age structure", {
    df <- data.frame(location = "A", age = c("25", "30"),
                     base2015 = c(0.5, 0.5))
    expect_warning(.slice_age(df, "base2015"), "age group")
    expect_silent(.slice_age(df, "base2015", min_age_groups = 0))
  })

  it("maps cause/endpoint aliases onto the canonical names", {
    df <- data.frame(location = "A", age = c(25, 30), cause = "copd",
                     base2015 = c(1, 2))
    out <- .slice_mort(df, "base2015")
    expect_equal(names(out), c("location", "age", "endpoint", "mortrate"))
    expect_equal(out$endpoint, c("copd", "copd"))
  })

  it("passes a long auxiliary table through when the scenario is absent", {
    age <- data.frame(location = "A", age = c("25", "30"),
                      prop = c(0.5, 0.5))
    expect_message(out <- .slice_age(age, "base2015", min_age_groups = 0),
                   "not scenario-addressed")
    expect_equal(names(out), c("location", "age", "prop"))

    mort <- data.frame(location = "A", age = "25", endpoint = "copd",
                       mortrate = 10)
    expect_message(out <- .slice_mort(mort, "base2015"), "not scenario-addressed")
    expect_equal(names(out), c("location", "age", "endpoint", "mortrate"))
  })

  it("uses the single numeric column of an auxiliary table", {
    pop <- data.frame(location = "A", Pop2017 = 1e5, source = "WB")
    expect_message(out <- .slice_pop(pop, NULL), "Pop2017")
    expect_equal(names(out), c("location", "pop"))
    expect_equal(out$pop, 1e5)
  })
})

describe(".left_join_common()", {
  it("declares the stratum fan-out instead of warning about it", {
    skeleton <- data.frame(x = c("0", "1"), y = c("0", "0"),
                           conc = c("5.0", "5.0"))
    lookup <- data.frame(conc = "5.0", endpoint = c("a", "b"),
                         RR = c(1.1, 1.2))

    expect_no_warning(out <- .left_join_common(skeleton, lookup))
    expect_equal(names(out), c("x", "y", "conc", "endpoint", "RR"))
    expect_equal(nrow(out), 4L)
  })

  it("still reports a relationship the caller declares itself", {
    skeleton <- data.frame(conc = c("5.0", "5.0"))
    lookup <- data.frame(conc = c("5.0", "6.0"), RR = c(1.1, 1.2))

    expect_error(
      .left_join_common(skeleton, lookup, relationship = "one-to-one"),
      class = "dplyr_error_join_relationship_one_to_one"
    )
  })
})
