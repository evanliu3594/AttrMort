# Fingerprint regression: pins the per-column sums of every mortality() branch.
#
# The references in tests/testthat/fixtures/fingerprints/ are regenerated
# whenever the example data or a numeric code path changes, so any drift here
# means an unintended behaviour change.
#
# Opt-in, because it pushes the shipped example workbooks through a dozen
# branches (roughly a minute):
#   ATTRMORT_FINGERPRINTS=1       compare against the stored fingerprints
#   ATTRMORT_FINGERPRINTS=update  rewrite the stored fingerprints
#
# Run it before and after touching a numeric code path.

.fp_dir <- function() {
  testthat::test_path("fixtures", "fingerprints")
}

# Argument sets mirroring the branches a user can reach.
.fp_runs <- function() {
  base <- list(
    calc_fild = .attr_data("grid_info"),
    conc_real = .slice_conc(.attr_data("grid_exposure"), "base2015"),
    pop_total = .slice_pop(.attr_data("grid_pop"), "base2015"),
    age_struc = .slice_age(.attr_data("national_age_structure"), "base2015"),
    mort_rate = .slice_mort(.attr_data("national_mortality"), "base2015"),
    validate  = "off"
  )
  runs <- list()
  for (model in c("GEMM", "NCD+LRI", "5COD", "IER", "IER2017", "IER2015",
                  "MRBRT", "MRBRT2019", "O3", "NO2")) {
    runs[[paste0("crf-", model)]] <- c(list(crf = model, mort_lvl = "location"),
                                       base)
  }
  runs[["gemm-lvlNULL"]] <- c(list(crf = "GEMM", mort_lvl = NULL), base)
  runs[["gemm-lvlMissing"]] <- c(list(crf = "GEMM", mort_lvl = "nonexistent"),
                                 base)
  runs[["gemm-concCF"]] <- c(
    list(crf = "GEMM", mort_lvl = "location",
         conc_cf = .slice_conc(.attr_data("grid_exposure"), "scenario2030")),
    base
  )
  runs
}

# One branch -> data.frame(column, colsum).
.fp_summarise <- function(args) {
  res <- suppressWarnings(suppressMessages(do.call(mortality, args)))
  num <- res[vapply(res, is.numeric, logical(1))]
  out <- data.frame(
    column = names(num),
    colsum = vapply(num, function(v) sum(v, na.rm = TRUE), numeric(1)),
    stringsAsFactors = FALSE
  )
  out[order(out$column), ]
}

describe("mortality() fingerprints", {
  it("matches the stored per-column sums for every branch", {
    mode <- Sys.getenv("ATTRMORT_FINGERPRINTS", "")
    skip_if(!nzchar(mode),
            "set ATTRMORT_FINGERPRINTS=1 to compare (or =update to rewrite)")

    runs <- .fp_runs()
    for (tag in names(runs)) {
      now  <- .fp_summarise(runs[[tag]])
      path <- file.path(.fp_dir(), paste0(tag, ".csv"))

      if (identical(mode, "update")) {
        utils::write.csv(now, path, row.names = FALSE)
        next
      }

      expect_true(file.exists(path), info = tag)
      ref <- utils::read.csv(path, stringsAsFactors = FALSE)
      ref <- ref[order(ref$column), ]

      expect_equal(now$column, ref$column, info = paste(tag, "- columns"))
      expect_equal(now$colsum, ref$colsum, tolerance = 1e-9,
                   info = paste(tag, "- column sums"))
    }

    if (identical(mode, "update")) {
      succeed(paste("rewrote", length(runs), "fingerprint files"))
    }
  })
})

describe("shipped example data", {
  it("covers every endpoint the built-in models need", {
    mort <- .attr_data("national_mortality")
    expect_setequal(
      unique(mort$endpoint),
      c("ncd+lri", "copd", "ihd", "lc", "lri", "stroke", "dm2", "allcause")
    )
  })

  it("keeps the national population table consistent with the grid", {
    grid_pop  <- .attr_data("grid_pop")
    grid_info <- .attr_data("grid_info")
    national  <- .attr_data("national_population")

    totals <- vapply(national$location, function(k) {
      sum(grid_pop$base2015[grid_info$location == k])
    }, numeric(1))
    expect_equal(unname(totals), national$base2015)
  })

  it("has age proportions that sum to one in every country", {
    age  <- .attr_data("national_age_structure")
    sums <- tapply(age$base2015, age$location, sum)
    expect_true(all(abs(sums - 1) < 0.01))
  })
})
