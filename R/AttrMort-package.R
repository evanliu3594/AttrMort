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
#' can be supplied as a custom lookup table through the `crf` argument of
#' [mortality()].
#'
#' @section Entry points:
#' * [mortality()] — attributable deaths per scenario, per grid cell or per
#'   domain, with an optional uncertainty range
#' * [decompose()] — driving-factor decomposition
#' * [aggregate_mortality()], [aggregate_ci()] — post-hoc aggregation
#' * [cr_config()], [build_cr_table()], [rr_std()], [cr_models()] —
#'   concentration-response configuration and tables
#' * [.slice_conc()], [.slice_pop()], [.slice_age()], [.slice_mort()] — wide-to-long helpers
#' * [matchable()] — join-key rounding helper
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom dplyr across all_of any_of arrange bind_cols bind_rows distinct
#'   filter full_join group_by if_else left_join mutate n pick pull relocate
#'   rename rename_with select summarise tibble transmute ungroup
#' @importFrom tidyr drop_na expand_grid fill pivot_longer pivot_wider
#' @importFrom purrr imap list_c list_flatten list_rbind map map_chr map_dbl map_int map_lgl
#'   reduce set_names walk
#' @importFrom stringr fixed regex str_c str_detect str_ends str_extract
#'   str_length str_remove str_replace str_sub str_subset
#' @importFrom rlang :=
#' @importFrom readxl read_excel
#' @importFrom readr read_csv
#' @importFrom stats weighted.mean
#' @importFrom utils head str
#' @importFrom tools file_ext
NULL

# Report an error the user can act on, without the calling frame: almost every
# abort in this package is raised from an internal helper, and `cli_abort()`
# would attach that helper's call to the condition ("Error in
# .check_input_files(...)"). The message itself already names the argument, the
# object and the fix, so the call frame adds noise rather than information.
.abort <- function(message, ..., envir = parent.frame()) {
  cli::cli_abort(message, ..., call = NULL, .envir = envir)
}

## Columns referenced inside tidy-evaluation verbs (keeps R CMD check quiet).
utils::globalVariables(c(
  ".", ".total", "age", "attr_mort", "cause", "col", "column",
  "conc", "conc_mean", "conc_pwe", "endpoint", "mort_base",
  "mortrate", "n_cells", "PAF", "pop", "prop", "PWRR", "RR", "src", "value",
  "x", "y"
))
