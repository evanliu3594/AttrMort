# Tests for build_cr_table() — concentration-response tables from coefficients

describe("build_cr_table() for the IER form", {
  ier <- data.frame(cause = "IHD", age = "25", alpha = 5, beta = 0.01,
                    gamma = 0.5, tmrel = 3)

  it("returns 1 below the counterfactual and rises above it", {
    tab <- build_cr_table(ier, model = "IER", conc = seq(0, 20, 0.1))
    expect_equal(tab$MEAN$IHD_25[tab$MEAN$conc == "3"], 1)
    expect_equal(tab$MEAN$IHD_25[tab$MEAN$conc == "0"], 1)
    expect_gt(tab$MEAN$IHD_25[tab$MEAN$conc == "10"], 1)
    expect_true(all(diff(tab$MEAN$IHD_25) >= 0))
  })

  it("follows the published IER functional form", {
    tab <- build_cr_table(ier, model = "IER", conc = c(3, 10))
    expected <- 5 * (1 - exp(-0.01 * sqrt(10 - 3))) + 1
    expect_equal(tab$MEAN$IHD_25[2], expected, tolerance = 1e-12)
  })

  it("defaults to the IER form when `model` is omitted", {
    tab <- build_cr_table(ier, conc = c(3, 10))
    expect_named(tab, c("MEAN", "LOW", "UP"))
    expect_true("IHD_25" %in% names(tab$MEAN))
    expect_equal(tab$MEAN$IHD_25[2],
                 5 * (1 - exp(-0.01 * sqrt(10 - 3))) + 1,
                 tolerance = 1e-12)
  })

  it("summarises the interval across the parameter draws", {
    draws <- data.frame(cause = "IHD", age = "25",
                        alpha = c(4, 5, 6), beta = 0.01,
                        gamma = 0.5, tmrel = 3)
    tab <- build_cr_table(draws, model = "IER", conc = c(0, 10),
                          level = 0.95)
    curves <- c(4, 5, 6) * (1 - exp(-0.01 * sqrt(10 - 3))) + 1

    expect_equal(tab$MEAN$IHD_25[2], mean(curves), tolerance = 1e-12)
    expect_equal(tab$LOW$IHD_25[2],
                 unname(stats::quantile(curves, 0.025)), tolerance = 1e-12)
    expect_equal(tab$UP$IHD_25[2],
                 unname(stats::quantile(curves, 0.975)), tolerance = 1e-12)
    expect_gt(tab$UP$IHD_25[2], tab$MEAN$IHD_25[2])
    expect_lt(tab$LOW$IHD_25[2], tab$MEAN$IHD_25[2])
    expect_equal(tab$LOW$IHD_25[1], 1)
    expect_equal(tab$UP$IHD_25[1], 1)
  })

  it("accepts alternative coefficient-file spellings", {
    src <- data.frame(cause = "ALRI", age = "All Age", alpha = 5, beta = 0.01,
                      delta = 0.5, zcf = 3)
    tab <- build_cr_table(src, model = "IER", conc = c(0, 10))
    expect_equal(names(tab$MEAN), c("conc", "LRI_ALL"))
  })
})

describe("build_cr_table() for the GEMM form", {
  gemm <- data.frame(Causes = "IHD", Age = "25", theta = 0.5, SE.theta = 0.02,
                     alpha = 1.9, mu = 12, gama = 40.2)

  it("returns 1 at or below the 2.4 pivot and rises above it", {
    tab <- build_cr_table(gemm, model = "GEMM", conc = seq(0, 20, 0.1))
    expect_equal(tab$MEAN$IHD_25[tab$MEAN$conc == "0"], 1)
    expect_equal(tab$MEAN$IHD_25[tab$MEAN$conc == "2.4"], 1)
    expect_gt(tab$MEAN$IHD_25[tab$MEAN$conc == "10"], 1)
  })

  it("follows the published GEMM functional form", {
    tab <- build_cr_table(gemm, model = "GEMM", conc = c(0, 10))
    z <- 10 - 2.4
    expected <- exp(0.5 * log(1 + z / 1.9) / (1 + exp((12 - z) / 40.2)))
    expect_equal(tab$MEAN$IHD_25[2], expected, tolerance = 1e-12)
  })

  it("derives the interval from the standard error of theta", {
    tab <- build_cr_table(gemm, model = "GEMM", conc = c(0, 10))
    z <- 10 - 2.4
    base <- log(1 + z / 1.9) / (1 + exp((12 - z) / 40.2))
    expect_equal(tab$UP$IHD_25[2], exp((0.5 + 1.959964 * 0.02) * base),
                 tolerance = 1e-6)
    expect_gt(tab$UP$IHD_25[2], tab$MEAN$IHD_25[2])
    expect_lt(tab$LOW$IHD_25[2], tab$MEAN$IHD_25[2])
  })
})

describe("build_cr_table() output contract", {
  gemm2 <- data.frame(Causes = c("IHD", "IHD", "COPD"), Age = c("ALL", "25", "ALL"),
                      theta = c(0.29, 0.51, 0.25), SE.theta = c(0.018, 0.025, 0.068),
                      alpha = c(1.9, 1.9, 6.5), mu = c(12, 12, 2.5),
                      gama = c(40.2, 40.2, 32))

  it("returns MEAN/LOW/UP wide tables with character conc keys", {
    tab <- build_cr_table(gemm2, model = "GEMM", conc = seq(0, 5, 0.1))
    expect_named(tab, c("MEAN", "LOW", "UP"))
    for (sheet in tab) {
      expect_type(sheet$conc, "character")
      expect_equal(nrow(sheet), 51)
    }
    expect_setequal(names(tab$MEAN), c("conc", "IHD_ALL", "IHD_25", "COPD_ALL"))
  })

  it("renders conc keys at the requested precision", {
    coefs <- data.frame(cause = "IHD", age = "25", alpha = 5, beta = 0.01,
                        gamma = 0.5, tmrel = 3)
    tab <- build_cr_table(coefs, model = "IER", conc = c(0, 0.25),
                          dgt = 2)
    expect_equal(tab$MEAN$conc, c("0", "0.25"))
  })

  it("produces columns that rr_std() can reshape", {
    tab <- build_cr_table(gemm2, model = "GEMM", conc = seq(0, 5, 0.1))
    long <- tab$MEAN |>
      pivot_longer(-conc, names_to = c("endpoint", "age"), names_sep = "_")
    expect_setequal(unique(long$endpoint), c("IHD", "COPD"))
    expect_setequal(unique(long$age), c("ALL", "25"))
  })

  it("writes a three-sheet workbook when asked", {
    skip_if_not_installed("writexl")
    path <- tempfile(fileext = ".xlsx")
    on.exit(unlink(path), add = TRUE)
    build_cr_table(gemm2, model = "GEMM", conc = seq(0, 5, 0.1),
                   path = path)
    expect_equal(readxl::excel_sheets(path), c("MEAN", "LOW", "UP"))
  })
})

describe("build_cr_table() input checks", {
  ier <- data.frame(cause = "IHD", age = "25", alpha = 5, beta = 0.01,
                    gamma = 0.5, tmrel = 3)

  it("names the missing coefficient columns", {
    expect_error(build_cr_table(dplyr::select(ier, -tmrel), model = "IER"),
                 "missing column")
    expect_error(build_cr_table(dplyr::select(ier, -tmrel), model = "IER"),
                 "tmrel")
  })

  it("rejects non-numeric coefficients", {
    bad <- ier
    bad$beta <- "not a number"
    expect_error(build_cr_table(bad, model = "IER"), "not numeric")
  })

  it("rejects an empty table and a bad confidence level", {
    expect_error(build_cr_table(ier[0, ], model = "IER"), "empty")
    expect_error(build_cr_table(ier, model = "IER", level = 1.5),
                 "between 0 and 1")
  })

  it("reports a missing or unsupported coefficient file", {
    expect_error(build_cr_table("no/such/file.csv", model = "IER"),
                 "File not found")
    expect_error(build_cr_table(tempfile(fileext = ".json"), model = "IER"),
                 "File not found")
  })
})
