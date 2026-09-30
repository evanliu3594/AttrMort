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

describe("getConc()", {
  df <- data.frame(x = c("0", "1"), y = c("0", "1"),
                   base2015 = c(35.24, 41.71), SSP1_2030 = c(30, 28))

  it("extracts one scenario and rounds it to `dgt`", {
    out <- getConc(df, "base2015")
    expect_equal(names(out), c("x", "y", "conc"))
    expect_type(out$conc, "character")
    expect_equal(out$conc, c("35.2", "41.7"))
  })

  it("honours a coarser or finer `dgt`", {
    expect_equal(getConc(df, "base2015", dgt = 0)$conc, c("35", "42"))
    expect_equal(getConc(df, "base2015", dgt = 2)$conc, c("35.24", "41.71"))
  })

  it("falls back to domain columns when there are no coordinates", {
    dom <- data.frame(location = c("A", "B"), base2015 = c(10, 20))
    expect_message(out <- getConc(dom, "base2015"), "joining on")
    expect_equal(names(out), c("location", "conc"))
  })

  it("reports an unknown scenario with the available columns", {
    expect_error(getConc(df, "nope"), "not found in the data")
    expect_error(getConc(df, "nope"), "base2015")
  })
})

describe("getPop() / getAge() / getMort()", {
  it("renames the scenario column to the canonical name", {
    df <- data.frame(x = "0", y = "0", base2015 = 5)
    expect_equal(names(getPop(df, "base2015")), c("x", "y", "pop"))
  })

  it("renormalises age proportions within each domain", {
    df <- data.frame(
      location = rep(c("A", "B"), each = 2), age = rep(c("25", "30"), 2),
      base2015 = c(3, 1, 1, 1)          # counts, not proportions
    )
    out <- getAge(df, "base2015", min_age_groups = 0)
    expect_equal(out$prop[out$location == "A"], c(0.75, 0.25))
    expect_equal(out$prop[out$location == "B"], c(0.5, 0.5))
  })

  it("warns, rather than fails, on an incomplete age structure", {
    df <- data.frame(location = "A", age = c("25", "30"),
                     base2015 = c(0.5, 0.5))
    expect_warning(getAge(df, "base2015"), "age group")
    expect_silent(getAge(df, "base2015", min_age_groups = 0))
  })

  it("maps cause/endpoint aliases onto the canonical names", {
    df <- data.frame(location = "A", age = c(25, 30), cause = "copd",
                     base2015 = c(1, 2))
    out <- getMort(df, "base2015")
    expect_equal(names(out), c("location", "age", "endpoint", "mortrate"))
    expect_equal(out$endpoint, c("copd", "copd"))
  })
})
