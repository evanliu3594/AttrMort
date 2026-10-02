# Regression: a missing age must pass through the label normalisation, not
# crash it. Found by the independent verifier (T5, D1) after the label
# normalisation landed: `any(str_detect(x, pattern))` is NA when `x` holds an
# NA that does not match, and `if (NA)` aborts with a message that says nothing
# about ages. Real GBD-style tables have missing ages, so this is reachable
# from `mortality()` at validation time.
test_that("a missing age label is passed through, not fatal", {
  expect_identical(AttrMort:::.standardize_age_key(c("25", NA_character_)),
                   c("25", NA_character_))
  expect_identical(AttrMort:::.standardize_age_key(c("<5 years", NA_character_)),
                   c("0", NA_character_))
  expect_identical(AttrMort:::.standardize_age_key(c("15-19 years", NA_character_)),
                   c("15", NA_character_))
  expect_identical(AttrMort:::.standardize_age_key(NA_character_), NA_character_)
  expect_identical(AttrMort:::.standardize_age_key(character(0)), character(0))

  # the recognisable labels still normalise, and the untouched ones still do not
  expect_identical(AttrMort:::.standardize_age_key(c("95+ years", "All ages")),
                   c("95", "All ages"))
})

test_that("a table with a missing age does not abort the run before validation", {
  # `calc_fild` carries a domain column, so the run reaches the calculation
  # rather than being stopped by the skeleton check; the NA age is dropped by
  # the join instead of crashing the age normalisation. The incidental
  # warnings (a missing stratum is 1 of 20, so 18 are absent by construction)
  # are the pre-existing validation chatter, not this test's subject: the pin
  # is that the call returns a frame with real numbers instead of aborting.
  cf <- data.frame(x = c("1.00", "2.00"), y = c("1.00", "1.00"),
                   location = "AA")
  conc <- data.frame(x = c("1.00", "2.00"), y = c("1.00", "1.00"),
                     conc = c("10", "10"))
  pop <- data.frame(x = c("1.00", "2.00"), y = c("1.00", "1.00"),
                    pop = c(1000, 1000))
  ag <- data.frame(location = "AA", age = c("25", NA, "30"),
                   prop = c(0.4, 0.2, 0.4))
  mr <- data.frame(location = "AA",
                   endpoint = rep(c("copd", "ihd"), each = 3),
                   age = rep(c("25", NA, "30"), 2),
                   mortrate = 100)

  out <- suppressWarnings(
    mortality(crf = "IER2017", calc_fild = cf, conc_real = conc,
              pop_total = pop, age_struc = ag, mort_rate = mr,
              mort_lvl = "location", validate = "warn")
  )
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 2L)
  # the two ages that are present survive; the NA one contributes no column
  expect_true(all(c("copd_25", "ihd_30") %in% names(out)))
  expect_false(any(grepl("NA", names(out), fixed = TRUE)))
  expect_false(anyNA(out[setdiff(names(out), c("x", "y", "location"))]))
})

test_that("a missing age is still reported rather than silently absorbed", {
  # Passing it through must not make it invisible: the pre-existing
  # "not a standard 5-year stratum" report already names it.
  cf <- data.frame(x = "1.00", y = "1.00", location = "AA")
  conc <- data.frame(x = "1.00", y = "1.00", conc = "10")
  pop <- data.frame(x = "1.00", y = "1.00", pop = 1000)
  ag <- data.frame(location = "AA", age = c("25", NA), prop = c(0.8, 0.2))
  mr <- data.frame(location = "AA", endpoint = "copd",
                   age = c("25", NA), mortrate = 100)

  expect_warning(
    mortality(crf = "IER2017", calc_fild = cf, conc_real = conc,
              pop_total = pop, age_struc = ag, mort_rate = mr,
              mort_lvl = "location", validate = "warn"),
    "not a standard 5-year stratum"
  )
})
