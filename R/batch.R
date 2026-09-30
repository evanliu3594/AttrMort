# ── Multi-scenario batch processing ─────────────────────────────

#' Run Mortality() across multiple scenarios
#'
#' Wraps \code{Mortality()} to iterate over a vector of scenario names.
#' Each scenario corresponds to one column in wide-format multi-scenario
#' inputs (or one band in a multi-band GeoTIFF). Results are returned as
#' a named list with one data.frame per scenario.
#'
#' When \code{parallel = TRUE}, \code{furrr::future_map()} is used to
#' distribute scenarios across worker processes. The user must set a
#' \code{future::plan()} before calling (e.g.
#' \code{future::plan(future::multisession, workers = 4)}).
#'
#' @param ... Arguments passed through to \code{Mortality()}. The
#'   \code{scenario} parameter must NOT be included here — it is
#'   supplied automatically from \code{scenarios}.
#' @param scenarios Character vector. Scenario names to iterate over.
#' @param parallel Logical. If \code{TRUE}, uses \code{furrr::future_map()}
#'   for parallel execution. Requires the \code{furrr} package.
#'
#' @return A named list of data.frames. Names correspond to the scenario
#'   values. Each element is the output of a single \code{Mortality()}
#'   call for that scenario.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # Sequential: compute mortality for 3 scenarios
#'   results <- Mortality_batch(
#'     CRF        = "GEMM",
#'     calc_fild  = grid_info,
#'     conc_real  = grid_exposure,
#'     pop_total  = grid_pop,
#'     age_struc  = national_age_structure,
#'     mort_rate  = national_mortality,
#'     mort_lvl   = "location",
#'     scenarios  = c("base2015", "SSP1-2030", "SSP2-2030")
#'   )
#'
#'   # Parallel: same computation with 4 workers
#'   future::plan(future::multisession, workers = 4)
#'   results <- Mortality_batch(
#'     CRF        = "GEMM",
#'     calc_fild  = grid_info,
#'     conc_real  = grid_exposure,
#'     pop_total  = grid_pop,
#'     age_struc  = national_age_structure,
#'     mort_rate  = national_mortality,
#'     mort_lvl   = "location",
#'     scenarios  = c("base2015", "SSP1-2030", "SSP2-2030"),
#'     parallel   = TRUE
#'   )
#' }
Mortality_batch <- function(..., scenarios, parallel = FALSE) {

  stopifnot(is.character(scenarios), length(scenarios) > 0)

  if (parallel) {
    if (!requireNamespace("furrr", quietly = TRUE)) {
      stop(
        "Package 'furrr' is required for parallel execution. ",
        "Install it with: install.packages('furrr')"
      )
    }
    message("Running ", length(scenarios), " scenario(s) in parallel.")
    results <- furrr::future_map(scenarios, function(sc) {
      Mortality(..., scenario = sc)
    })
  } else {
    message("Running ", length(scenarios), " scenario(s) sequentially.")
    results <- lapply(scenarios, function(sc) {
      Mortality(..., scenario = sc)
    })
  }

  names(results) <- scenarios
  return(results)
}


#' Aggregate batch results across scenarios
#'
#' Takes the output of \code{Mortality_batch()} and combines results
#' into a single data.frame with a \code{scenario} column. Useful for
#' plotting or exporting multi-scenario analyses.
#'
#' @param batch_results Named list of data.frames, as returned by
#'   \code{Mortality_batch()}.
#' @param by Character vector. Columns to aggregate by in addition to
#'   \code{scenario}. Default \code{NULL} keeps all grid-level detail.
#' @param aggr_fun Function. Aggregation function. Default \code{sum}
#'   (with \code{na.rm = TRUE}).
#'
#' @return A data.frame with a \code{scenario} column and all other
#'   columns from the mortality results.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   results <- Mortality_batch(..., scenarios = c("S1", "S2"))
#'   combined <- combine_batch(results, by = "Country")
#' }
combine_batch <- function(batch_results, by = NULL, aggr_fun = sum) {

  stopifnot(is.list(batch_results), length(batch_results) > 0)

  combined <- batch_results |>
    imap_dfr(~ {
      .x |>
        mutate(scenario = .y, .before = 1)
    })

  if (!is.null(by)) {
    combined <- combined |>
      group_by(pick(all_of(c("scenario", by)))) |>
      summarise(
        across(where(is.numeric), ~ aggr_fun(.x, na.rm = TRUE)),
        .groups = "drop"
      )
  }

  return(combined)
}
