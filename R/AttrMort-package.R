#' AttrMort: attributable mortality from air pollution exposure
#'
#' @description
#' `AttrMort` estimates the health burden attributable to ambient air
#' pollution exposure. It combines gridded or tabular exposure data with
#' population, age structure and cause-specific mortality rates, and returns
#' attributable deaths per exposure scenario, per administrative domain, or
#' per grid cell.
#'
#' The package is deliberately *pollutant-agnostic*: PM<sub>2.5</sub>,
#' O<sub>3</sub> and NO<sub>2</sub> are supplied through the built-in
#' concentration-response tables, and any other pollutant/endpoint combination
#' can be supplied as a custom lookup table through the `CRF` argument of
#' [Mortality()].
#'
#' @section Entry points:
#' * [Mortality()] — attributable deaths per scenario, per grid cell or per
#'   domain, with an optional uncertainty range
#' * [Decomposition()] — driving-factor decomposition
#' * [aggregate_mortality()], [aggregate_ci()] — post-hoc aggregation
#' * [cr_config()], [build_cr_table()], [RR_std()], [cr_models()] —
#'   concentration-response configuration and tables
#' * [getConc()], [getPop()], [getAge()], [getMort()] — wide-to-long helpers
#' * [matchable()] — join-key rounding helper
#'
#' @keywords internal
"_PACKAGE"

#' @import dplyr
#' @import tidyr
#' @import purrr
#' @import stringr
#' @importFrom rlang := .data
#' @importFrom readxl read_excel excel_sheets
#' @importFrom readr read_csv
#' @importFrom stats na.omit setNames weighted.mean
#' @importFrom utils head globalVariables str
#' @importFrom tools file_ext
NULL

## Columns referenced inside tidy-evaluation verbs (keeps R CMD check quiet).
utils::globalVariables(c(
  ".", ".total", "age", "AttrMort", "cause", "col", "column",
  "conc", "conc_mean", "conc_pwe", "endpoint", "M",
  "Mort_0", "Mort_1", "Mort_2", "Mort_3", "Mort_4",
  "mortrate", "n_cells", "PAF", "pop", "prop", "RR", "value", "x", "y"
))
