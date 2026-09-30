# Shared test fixtures ---------------------------------------------------
#
# Two kinds of fixture:
#   * .attr_small() / .attr_small_long() — tiny synthetic inputs with hand
#     computable numbers, used for the fast unit tests.
#   * .attr_data() — the shipped example workbooks, loaded once and cached,
#     used for the end-to-end scenarios.

.attr_extdata_dir <- function() {
  d <- system.file("extdata", package = "AttrMort")
  if (identical(d, "")) {
    d <- file.path("inst", "extdata")
  }
  d
}

.attr_fixture_cache <- new.env(parent = emptyenv())

# Load one of the shipped example workbooks (cached across tests).
.attr_data <- function(name) {
  if (!exists(name, envir = .attr_fixture_cache, inherits = FALSE)) {
    path <- file.path(.attr_extdata_dir(), paste0(name, ".xlsx"))
    if (!file.exists(path)) {
      testthat::skip(paste("example data not found:", path))
    }
    assign(name, readxl::read_excel(path), envir = .attr_fixture_cache)
  }
  get(name, envir = .attr_fixture_cache, inherits = FALSE)
}

# Four grid cells in one domain, two age groups, one endpoint.
.attr_small <- function() {
  fld  <- data.frame(
    x = c("0", "1", "0", "1"),
    y = c("0", "0", "1", "1"),
    location = "A"
  )
  keys <- fld[, c("x", "y")]

  list(
    calc_fild = fld,
    conc_real = data.frame(keys, base2015 = c(10, 20, 30, 40)),
    conc_cf   = data.frame(keys, base2015 = c(5, 5, 5, 5)),
    pop_total = data.frame(keys, base2015 = c(100, 200, 300, 400)),
    age_struc = data.frame(
      location = "A", age = c("25", "30"), base2015 = c(0.5, 0.5)
    ),
    mort_rate = data.frame(
      location = "A", age = c("25", "30"), endpoint = "ncd+lri",
      base2015 = c(1000, 2000)
    )
  )
}

# Same fixture, already reduced to the standard column names. The synthetic
# age structure only has two groups, so the completeness check is disabled.
.attr_small_long <- function() {
  s <- .attr_small()
  list(
    calc_fild = s$calc_fild,
    conc_real = getConc(s$conc_real, "base2015"),
    conc_cf   = getConc(s$conc_cf, "base2015"),
    pop_total = getPop(s$pop_total, "base2015"),
    age_struc = getAge(s$age_struc, "base2015", min_age_groups = 0),
    mort_rate = getMort(s$mort_rate, "base2015")
  )
}

# Run Mortality() on either fixture with sensible defaults.
#
# `conc_cf` is only passed when explicitly requested: in the PWRR branch the
# counterfactual exposure drives the risk term while `conc_real` drives the
# population-weighted RR, so the two are not interchangeable.
.attr_run <- function(CRF = "GEMM", mort_lvl = "location", long = TRUE,
                      scenario = NULL, conc_cf = NULL, validate = "off", ...) {
  d <- if (long) .attr_small_long() else .attr_small()
  args <- list(
    CRF       = CRF,
    calc_fild = d$calc_fild,
    conc_real = d$conc_real,
    pop_total = d$pop_total,
    age_struc = d$age_struc,
    mort_rate = d$mort_rate,
    mort_lvl  = mort_lvl,
    scenario  = scenario,
    validate  = validate,
    ...
  )
  if (!is.null(conc_cf)) {
    args$conc_cf <- conc_cf
  }
  do.call(Mortality, args)
}
