# All permutations of the four decomposition drivers, in lexicographic order
# of .DRIVER_ORDER. Series 1..24 documented below correspond to this order.
.DRIVER_ORDER <- c("PG", "PA", "EXP", "ORF")

.permutations <- function(x) {
  if (length(x) <= 1) {
    return(list(x))
  }
  out <- list()
  for (i in seq_along(x)) {
    out <- c(out, lapply(.permutations(x[-i]), function(p) c(x[i], p)))
  }
  out
}

#' Decomposition of attributed deaths
#'
#' @param serie possible cumulative change in input driver series, listed as follows:
#' 1. PG-PA-EXP-ORF
#' 2. PG-PA-ORF-EXP
#' 3. PG-EXP-PA-ORF
#' 4. PG-EXP-ORF-PA
#' 5. PG-ORF-PA-EXP
#' 6. PG-ORF-EXP-PA
#' 7. PA-PG-EXP-ORF
#' 8. PA-PG-ORF-EXP
#' 9. PA-EXP-PG-ORF
#' 10. PA-EXP-ORF-PG
#' 11. PA-ORF-PG-EXP
#' 12. PA-ORF-EXP-PG
#' 13. EXP-PG-PA-ORF
#' 14. EXP-PG-ORF-PA
#' 15. EXP-PA-PG-ORF
#' 16. EXP-PA-ORF-PG
#' 17. EXP-ORF-PA-PG
#' 18. EXP-ORF-PG-PA
#' 19. ORF-PG-PA-EXP
#' 20. ORF-PG-EXP-PA
#' 21. ORF-PA-PG-EXP
#' 22. ORF-PA-EXP-PG
#' 23. ORF-EXP-PG-PA
#' 24. ORF-EXP-PA-PG
#' @param crf refers to `CRF` in `Mortality()`
#' @param ci refers to `CI` in `Mortality()`, by default "MEAN"
#' @param G refers to `calc_fild` in `Mortality()`
#' @param D refers to `conc_real` in `Mortality()`
#' @param D_cf {data.frame}, refers to `conc_cf` in `Mortality()`
#' @param P refers to `pop_total` in `Mortality()`
#' @param A refers to `age_struc` in `Mortality()`
#' @param M refers to `mort_rate` in `Mortality()`
#' @param L refers to `mort_lvl` in `Mortality()`
#' @param from scenario/year when the driving space start
#' @param to scenario/year when the driving space end
#'
#' @return a data.frame of decomposed attributed deaths
#' @export
#'
#' @examples
#' \dontrun{
#'   builtin_data <- list.files(system.file('extdata', package = "AttrMort"), full.names = T)
#'
#'     for (f in builtin_data) {
#'       nm <- basename(f) |> str_extract(".+(?=\\.)")
#'       assign(nm, readxl::read_excel(f))
#'     }
#'
#'   Decomposition(
#'     serie = 1,
#'     crf = "GEMM",
#'     G = grid_info,
#'     D = grid_exposure,
#'     P = grid_pop,
#'     A = national_age_structure,
#'     M = national_mortality,
#'     L = "location",
#'     from = "base2015",
#'     to = "SSP1-Baseline_2030"
#'   )
#' }
#'
Decomposition <- function(serie, crf, ci = "MEAN", G, D, P, A, M, L, D_cf = NULL, from, to) {
  if (!is.numeric(serie) || length(serie) != 1 || serie < 1 || serie > 24) {
    stop("`serie` must be a single integer between 1 and 24.", call. = FALSE)
  }
  serie.step <- .permutations(.DRIVER_ORDER)[[serie]]

  Decomp <- list(
    # Mort.Start ----
    Mort_0 = Mortality(
      calc_fild = G,
      conc_cf = if (is.null(D_cf)) NULL else getConc(D_cf, from),
      pop_total = getPop(P, from),
      age_struc = getAge(A, from, loc = L),
      conc_real = getConc(D, from),
      mort_rate = getMort(M, from, loc = L),
      mort_lvl = L,
      CRF = crf,
      CI = ci
    ),
    # Mort.1----
    Mort_1 = if (serie.step[1] == 'PG') {
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, to),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (serie.step[1] == 'PA') {
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, from),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (serie.step[1] == 'EXP') {
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, from),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (serie.step[1] == 'ORF') {
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, from),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    },
    # Mort.2----
    Mort_2 = if (all(serie.step[1:2] %in% c('PG', 'PA'))) {
      # PG  PA
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, to),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:2] %in% c('PG', 'EXP'))) {
      #  PG  EXP
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, from),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:2] %in% c('PG', 'ORF'))) {
      #  PG  ORF
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, to),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:2] %in% c('PA', 'EXP'))) {
      #  PA  EXP
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, from),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:2] %in% c('PA', 'ORF'))) {
      #  PA  ORF
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, from),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:2] %in% c('EXP', 'ORF'))) {
      #  EXP ORF
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, from),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    },
    # Mort.3----
    Mort_3 = if (all(serie.step[1:3] %in% c('PG', 'PA', 'EXP'))) {
      # PG PA EXP
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, to),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, from),
        mort_rate = getMort(M, from, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:3] %in% c('PG', 'PA', 'ORF'))) {
      # PG  PA ORF
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, from),
        pop_total = getPop(P, to),
        age_struc = getAge(A, to, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:3] %in% c('PG', 'EXP', 'ORF'))) {
      #  PG	EXP	ORF
      Mortality(
        calc_fild = G,
        conc_cf = getConc(D, to),
        pop_total = getPop(P, to),
        age_struc = getAge(A, from, loc = L),
        conc_real = getConc(D, to),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    } else if (all(serie.step[1:3] %in% c('PA', 'EXP', 'ORF'))) {
      #  PA	EXP	ORF
      Mortality(
        calc_fild = G,
        conc_real = getConc(D, to),
        conc_cf = getConc(D, to),
        pop_total = getPop(P, from),
        age_struc = getAge(A, to, loc = L),
        mort_rate = getMort(M, to, loc = L),
        mort_lvl = L,
        CRF = crf,
        CI = ci
      )
    },
    # Mort.End ----
    Mort_4 = Mortality(
      calc_fild = G,
      conc_cf = getConc(D, to),
      pop_total = getPop(P, to),
      age_struc = getAge(A, to, loc = L),
      conc_real = getConc(D, to),
      mort_rate = getMort(M, to, loc = L),
      mort_lvl = L,
      CRF = crf,
      CI = ci
    )
  )

  # Identify the endpoint_age value columns from the CR table instead of
  # guessing from the column names, so any age-group spacing works and the
  # key columns (x, y, domain) are kept as pivot ids.
  rr_ref <- if (is.data.frame(crf)) crf else RR_std(crf, ci)
  value_cols <- rr_ref |>
    distinct(endpoint, age) |>
    mutate(col = paste(endpoint, age, sep = "_")) |>
    pull(col) |>
    intersect(names(Decomp[[1]]))

  if (length(value_cols) == 0) {
    stop(
      "Could not identify any `endpoint_age` columns in the Mortality() ",
      "output; is `crf` the model actually used?",
      call. = FALSE
    )
  }

  Decomp <- Decomp |>
    imap(
      ~ {
        .x |>
          pivot_longer(
            all_of(value_cols),
            names_to = "Cause_Age",
            values_to = 'Mort'
          ) |>
          mutate(Step = .y)
      }
    ) |>
    list_rbind() |>
    pivot_wider(names_from = 'Step', values_from = 'Mort') |>
    mutate(
      Start = Mort_0,
      !!serie.step[1] := Mort_1 - Mort_0,
      !!serie.step[2] := Mort_2 - Mort_1,
      !!serie.step[3] := Mort_3 - Mort_2,
      !!serie.step[4] := Mort_4 - Mort_3,
      End = Mort_4,
      .keep = 'unused'
    )

  # Print Result ----
  cat('Drivers Between', from, 'and', to, ':\n', sep = ' ')
  cat(
    serie.step[1],
    ':\t',
    sum(Decomp |> pull(serie.step[1]) |> sum() |> round()),
    '\n'
  )
  cat(
    serie.step[2],
    ':\t',
    sum(Decomp |> pull(serie.step[2]) |> sum() |> round()),
    '\n'
  )
  cat(
    serie.step[3],
    ':\t',
    sum(Decomp |> pull(serie.step[3]) |> sum() |> round()),
    '\n'
  )
  cat(
    serie.step[4],
    ':\t',
    sum(Decomp |> pull(serie.step[4]) |> sum() |> round()),
    '\n'
  )

  return(Decomp)
}
