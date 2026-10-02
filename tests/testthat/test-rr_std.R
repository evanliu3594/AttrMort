# Tests for rr_std() — concentration-response lookup standardisation

describe("rr_std()", {
  it("returns a join-ready long table with character conc keys", {
    out <- rr_std("GEMM", "MEAN")
    expect_s3_class(out, "data.frame")
    expect_equal(names(out), c("conc", "endpoint", "age", "RR"))
    expect_type(out$conc, "character")
    expect_type(out$age, "character")
    expect_gt(nrow(out), 0)
  })

  it("keeps the conc keys at the requested precision", {
    d1 <- rr_std("GEMM", "MEAN", dgt = 1)$conc
    expect_true(all(grepl("^[0-9]+(\\.[0-9])?$", d1)))
    expect_equal(rr_std("GEMM", "MEAN", dgt = 0)$conc,
                 matchable(as.numeric(d1), 0))
    expect_equal(rr_std("GEMM", "MEAN", dgt = 2)$conc,
                 matchable(as.numeric(d1), 2))
  })

  it("matches model names case-insensitively", {
    expect_equal(rr_std("gemm", "MEAN"), rr_std("GEMM", "MEAN"))
  })

  it("accepts CI aliases and rejects anything else", {
    expect_equal(rr_std("GEMM", "UPPER"), rr_std("GEMM", "UP"))
    expect_equal(rr_std("GEMM", "lower"), rr_std("GEMM", "LOW"))
    expect_error(rr_std("GEMM", "MEANING"), "must be one of")
  })

  it("rejects an unknown model with the list of valid names", {
    expect_error(rr_std("UNKNOWN_MODEL"), "Unknown CR model")
    expect_error(rr_std("UNKNOWN_MODEL"), "MRBRT")
  })

  it("formats NCD+LRI for ages 25 and above", {
    out <- rr_std("NCD+LRI", "MEAN")
    expect_equal(unique(out$endpoint), "ncd+lri")
    ages <- as.integer(unique(out$age))
    expect_true(all(ages >= 25) && all(ages <= 95))
  })

  it("formats 5COD with its five endpoints", {
    out <- rr_std("5COD", "MEAN")
    expect_setequal(unique(out$endpoint), c("copd", "ihd", "lc", "lri", "stroke"))
  })

  it("restricts IER endpoints to the ages they apply to", {
    out <- rr_std("IER", "MEAN")
    lri <- as.integer(out$age[out$endpoint == "lri"])
    other <- as.integer(out$age[out$endpoint != "lri"])
    expect_true(all(lri < 5))
    expect_true(all(other >= 25))
  })

  it("returns only COPD for O3 and only all-cause for NO2", {
    expect_equal(unique(rr_std("O3", "MEAN")$endpoint), "copd")
    expect_equal(unique(rr_std("NO2", "MEAN")$endpoint), "allcause")
  })

  it("returns all three CI tables for every model", {
    for (model in cr_models()) {
      for (index in c("MEAN", "UP", "LOW")) {
        out <- rr_std(model, index)
        expect_gt(nrow(out), 0)
        expect_false(anyNA(out$RR))
      }
    }
  })
})

describe("cr_models()", {
  it("lists the accepted model names", {
    expect_true(all(c("GEMM", "IER", "MRBRT", "O3", "NO2") %in% cr_models()))
  })
})

describe("built-in lookup tables", {
  it("store conc keys as character at one decimal place", {
    # The data contract applies to the shipped tables themselves, not only to
    # what rr_std() renders: NO2 used to be a double column with ~1e-12
    # floating-point tail, which matchable() happened to paper over.
    tables <- c(
      "GEMM_Lookup_Table", "IER2010_Lookup_Table", "IER2013_Lookup_Table",
      "IER2015_Lookup_Table", "IER2017_Lookup_Table", "MRBRT2019_Lookup_Table",
      "MRBRT2021_Lookup_Table", "O3_CR_Lookup_Table", "NO2_CR_Lookup_Table"
    )
    for (nm in tables) {
      e <- new.env()
      utils::data(list = nm, package = "AttrMort", envir = e)
      tab <- get(nm, envir = e)
      for (branch in c("MEAN", "LOW", "UP")) {
        conc <- tab[[branch]]$conc
        expect_type(conc, "character")
        expect_true(all(grepl("^-?[0-9]+([.][0-9])?$", conc)),
                    info = paste(nm, branch))
        # stored in numeric order, so consuming the table row-wise cannot
        # silently read a lexicographic sequence like "1.9", "10", "10.1"
        expect_false(is.unsorted(as.numeric(conc)),
                     info = paste(nm, branch))
      }
      expect_true(is.list(tab), info = nm)
      expect_false(inherits(tab, "vctrs_list_of"), info = nm)
    }
  })
})
