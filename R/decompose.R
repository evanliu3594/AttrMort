# All permutations of the four decomposition drivers, in lexicographic order
# of .DRIVER_ORDER. Series 1..24 documented below correspond to this order.
.DRIVER_ORDER <- c("PG", "PA", "EXP", "ORF")

.permutations <- function(x) {
  if (length(x) <= 1) {
    return(list(x))
  }
  out <- vector("list", length(x))
  for (i in seq_along(x)) {
    out[[i]] <- map(.permutations(x[-i]), function(p) c(x[i], p))
  }
  list_flatten(out)
}

#' Decompose attributed deaths between two sets of inputs
#'
#' Compares two complete sets of inputs -- two groups -- and splits the change
#' in attributable deaths among the four drivers, for every ordering of them.
#' Each group is a list holding one table per role (`conc_real`, `pop_total`,
#' `age_struc`, `mort_rate`, and optionally `conc_cf`); nothing is selected by
#' scenario name, because the comparison is between two datasets, not between
#' two columns of one table.
#'
#' The four drivers are not independent: moving them in a different order
#' attributes part of the same change to a different driver, which is why all
#' 24 orderings are returned rather than one. A step reads each role from `from`
#' or from `to`: a driver that has already moved reads `to`. Its column
#' therefore isolates the driver it is named after -- `Start` is the `from`
#' group, `End` the `to` group, and the four driver columns add up to
#' `End - Start` per cell and age stratum.
#'
#' The 24 orderings pass through 16 states between them (one per subset of
#' drivers that has moved), the inputs are prepared once per group, and the
#' concentration-response table is built once, so a full decomposition costs
#' sixteen calculations rather than 24 x 5.
#'
#' @param crf refers to `crf` in [mortality()]
#' @param ci refers to `ci` in [mortality()], by default `"MEAN"`
#' @param from,to The two groups to compare, as lists of input tables: one per
#'   role, in the same form [mortality()] accepts as a single run (`conc_real`,
#'   `pop_total`, `age_struc`, `mort_rate`, and optionally `conc_cf`; each may
#'   be a `data.frame` or a file path). `conc_cf` is the group's counterfactual
#'   exposure and defaults to its own `conc_real`. An optional `label` element
#'   names the group in the printed summary. Both groups are read onto the same
#'   grid: the second is aligned on the template the first resolved, and the
#'   join keys of both are checked against one `calc_fild`.
#' @inheritParams mortality
#'
#' @return A named list of 24 data frames, one per ordering of the four drivers
#'   (`"PG-PA-EXP-ORF"`, `"PG-PA-ORF-EXP"`, ... in the documented order). Each
#'   has one row per grid cell and age stratum: the key columns, `Cause_Age`,
#'   `Start`, one column per driver in the order that ordering moves them, and
#'   `End`.
#' @export
#'
#' @examples
#' \dontrun{
#'   extdata <- system.file("extdata", package = "AttrMort")
#'   read_sheet <- function(f) readxl::read_excel(file.path(extdata, f))
#'
#'   res <- decompose(
#'     crf       = "GEMM",
#'     calc_fild = read_sheet("grid_info.xlsx"),
#'     mort_lvl  = "location",
#'     from = list(
#'       label     = "base2015",
#'       conc_real = read_sheet("exposure_2015.xlsx"),
#'       pop_total = read_sheet("pop_2015.xlsx"),
#'       age_struc = read_sheet("age_2015.xlsx"),
#'       mort_rate = read_sheet("mort_2015.xlsx")
#'     ),
#'     to = list(
#'       label     = "SSP1_2030",
#'       conc_real = read_sheet("exposure_2030.xlsx"),
#'       pop_total = read_sheet("pop_2030.xlsx"),
#'       age_struc = read_sheet("age_2030.xlsx"),
#'       mort_rate = read_sheet("mort_2030.xlsx")
#'     )
#'   )
#'
#'   res[["PG-PA-EXP-ORF"]]           # one ordering
#'   # the order-independent reading: the mean contribution of each driver
#'   drivers <- c("PG", "PA", "EXP", "ORF")
#'   Reduce(`+`, lapply(res, function(x) x[drivers])) / length(res)
#' }
#'
decompose <- function(crf, ci = "MEAN", calc_fild = NULL, from, to,
                      mort_lvl = NULL, admin = NULL, admin_col = "admin",
                      target_res = NULL, dgt_coord = 2, dgt_conc = 1,
                      validate = c("warn", "stop", "off"), cr_config = NULL) {
  validate <- match.arg(validate)
  ci       <- .match_ci(ci)

  # ── two groups, each a complete set of inputs ──────────────────────
  # `label` is cosmetic (the printed summary), the rest are the roles a run
  # needs -- the same names `mortality()` takes as arguments.
  roles <- c("conc_real", "pop_total", "age_struc", "mort_rate", "conc_cf")
  as_group <- function(x, arg) {
    if (!is.list(x) || is.data.frame(x)) {
      .abort(str_c("`", arg, "` must be a list of input tables: ",
                   "{paste(roles, collapse = ', ')}."))
    }
    unknown <- setdiff(names(x), c(roles, "label"))
    if (length(unknown) > 0) {
      .abort(str_c("Unknown element(s) in `", arg, "`: ",
                   "{paste(unknown, collapse = ', ')}. Known: ",
                   "{paste(roles, collapse = ', ')}."))
    }
    missing <- setdiff(roles[roles != "conc_cf"], names(x))
    if (length(missing) > 0) {
      .abort(str_c("`", arg, "` is missing: {paste(missing, collapse = ', ')}."))
    }
    x
  }
  from <- as_group(from, "from")
  to   <- as_group(to, "to")

  # ── each group, prepared once; the second on the first's grid ───────
  # Reading, aligning, mapping columns and attaching boundaries happen here and
  # nowhere else, so the two groups cannot drift apart.
  # No scenario is selected here: each group carries one value per role, and
  # `.prepare_inputs()` hands back canonical tables either way.
  prep <- function(g, template) {
    args <- list(crf, calc_fild, g$conc_real, g$conc_cf, g$pop_total,
                 g$age_struc, g$mort_rate, scenario = NULL, admin, admin_col,
                 target_res, dgt_coord, dgt_conc, validate, cr_config, mort_lvl,
                 template = template)
    if (validate == "off") {
      suppressWarnings(suppressMessages(do.call(.prepare_inputs, args)))
    } else {
      do.call(.prepare_inputs, args)
    }
  }
  quiet    <- validate == "off"
  g_from   <- prep(from, NULL)
  g_to     <- prep(to, g_from$template)
  # the name the tables actually carry, after column mapping
  mort_lvl <- g_from$mort_lvl

  # ── validation of both groups, once per call ───────────────────────
  if (validate != "off") {
    for (grp in list(list(g = g_from, label = "from"),
                     list(g = g_to, label = "to"))) {
      report <- validate_mortality_input(
        list(conc = grp$g$conc_real, pop = grp$g$pop_total,
             age_struc = grp$g$age_struc, mort_rate = grp$g$mort_rate),
        cr_model = g_from$crf_name, dgt_conc = dgt_conc,
        config   = g_from$config
      )
      if (!report$valid && validate == "stop") {
        issues_txt <- paste(report$issues, collapse = "\n  - ")
        .abort("Input validation failed ({grp$label}):\n  - {issues_txt}")
      }
    }
    cli::cli_inform(.grain_message(g_from$calc_fild, mort_lvl, g_from$mort_rate,
                                   res = .grain_res(g_from$calc_fild,
                                                    g_from$template)))
  }

  for (grp in list(list(g = g_from, label = "from"),
                   list(g = g_to, label = "to"))) {
    .check_inputs(
      list(conc_real = grp$g$conc_real, conc_cf = grp$g$conc_cf,
           pop_total = grp$g$pop_total, age_struc = grp$g$age_struc,
           mort_rate = grp$g$mort_rate),
      g_from$calc_fild, group = grp$label
    )
  }

  rr_tbl <- if (is.data.frame(crf)) {
    crf
  } else {
    rr_std(g_from$crf_name, ci, dgt = dgt_conc, config = g_from$config)
  }

  # ── one calculation per state ──────────────────────────────────────
  # A step's inputs are fixed by the *set* of drivers that has moved -- the
  # order they moved in does not enter the calculation -- so the 24 orderings
  # share 16 states, and each is computed once here.
  #
  # Which role each driver moves: PG population, PA age structure, EXP the
  # counterfactual exposure, ORF the real exposure together with the baseline
  # mortality rate.
  states <- new.env(parent = emptyenv())
  state <- function(moved) {
    key <- str_c(as.integer(.DRIVER_ORDER %in% moved), collapse = "")
    if (is.null(states[[key]])) {
      pick <- function(role, driver) {
        if (driver %in% moved) g_to[[role]] else g_from[[role]]
      }
      states[[key]] <- .calc_attributable(
        calc_fild = g_from$calc_fild,
        conc_real = pick("conc_real", "ORF"),
        conc_cf   = if ("EXP" %in% moved) g_to$conc_cf else g_from$conc_cf,
        pop_total = pick("pop_total", "PG"),
        age_struc = pick("age_struc", "PA"),
        mort_rate = pick("mort_rate", "ORF"),
        mort_lvl  = mort_lvl,
        crf       = rr_tbl,
        ci        = ci,
        # The branch notice and the out-of-range report belong to the call,
        # not to each of the sixteen states.
        warn      = length(moved) == 0L,
        config    = g_from$config,
        dgt_conc  = dgt_conc,
        RR_tbl    = rr_tbl,
        crf_label = g_from$crf_name
      )
    }
    states[[key]]
  }

  # ── Start, one column per driver, End; one table per ordering ──────
  # The strata are the `{endpoint}_{age}` columns the C-R table defines; each
  # result is long, one row per cell and stratum, which is the shape the
  # contribution of one driver is read in.
  value_cols <- rr_tbl |>
    distinct(endpoint, age) |>
    mutate(col = paste(endpoint, age, sep = "_")) |>
    pull(col) |>
    intersect(names(state(character(0))))

  if (length(value_cols) == 0) {
    .abort(str_c(
      "Could not identify any `endpoint_age` columns in the decomposition ",
      "output; is `crf` the model actually used?"
    ))
  }

  # One row per cell and stratum, with the strata varying fastest within a
  # cell: the order a wide result is read in when its value columns are
  # stacked, and the order the rest of the package's long tables use.
  base      <- state(character(0))
  keys      <- setdiff(names(base), value_cols)
  strata    <- length(value_cols)
  cells     <- nrow(base)
  long_index <- bind_cols(
    base[keys][rep(seq_len(cells), each = strata), , drop = FALSE],
    tibble(Cause_Age = rep(value_cols, times = cells))
  )

  # A state is the same grid computed from a different mix of the two groups,
  # so its cells are matched to the index by key -- never by position. A cell a
  # state could not compute (no risk from the lookup, no domain label, the
  # group does not cover it) comes back as NA instead of silently borrowing the
  # neighbouring cell's value, which is what subtracting the raw columns would
  # do as soon as one state is short.
  long_cache <- new.env(parent = emptyenv())
  long_of <- function(moved) {
    key <- str_c(as.integer(.DRIVER_ORDER %in% moved), collapse = "")
    if (is.null(long_cache[[key]])) {
      st      <- state(moved)
      present <- intersect(value_cols, names(st))
      long    <- tidyr::pivot_longer(st[unique(c(keys, present))],
                                     all_of(present),
                                     names_to = "Cause_Age",
                                     values_to = "value")
      long_cache[[key]] <- left_join(long_index, long,
                                     by = c(keys, "Cause_Age"))$value
    }
    long_cache[[key]]
  }

  build <- function(step) {
    per   <- map(0:4, function(k) long_of(step[seq_len(k)]))
    parts <- c(
      list(Start = per[[1L]]),
      map(1:4, function(k) per[[k + 1L]] - per[[k]]) |> set_names(step),
      list(End = per[[5L]])
    )
    bind_cols(long_index, tibble(!!!parts))
  }

  # Everything the run compares lives on one grid, so a state is expected
  # to cover every cell: say so when one does not, rather than letting the
  # difference be taken against a gap.
  holes <- sum(is.na(long_of(.DRIVER_ORDER)))
  if (holes > 0 && validate != "off") {
    if (validate == "stop") {
      .abort(str_c(
        holes, " cell/stratum combination(s) could not be computed in every ",
        "state of the decomposition; the affected contributions are NA."
      ))
    }
    cli::cli_warn(str_c(
      holes, " cell/stratum combination(s) are missing from at least one ",
      "state (no risk from the C-R table, no domain label, or the group ",
      "does not cover them); their contribution is NA."
    ))
  }

  perms <- .permutations(.DRIVER_ORDER)
  out   <- map(perms, build) |>
    set_names(map_chr(perms, str_c, collapse = "-"))

  # Print Result ----
  # The orderings disagree by construction, so the summary is what they agree
  # on: each driver's mean contribution over the 24.
  means <- .DRIVER_ORDER |>
    map(function(driver) {
      mean(map_dbl(out, function(x) sum(x[[driver]])))
    }) |>
    set_names(.DRIVER_ORDER)
  label_of <- function(g, default) if (is.null(g$label)) default else g$label
  if (validate != "off") {
    cat("Drivers Between", label_of(from, "group 1"), "and",
        label_of(to, "group 2"), "(mean over", length(out), "orderings):\n",
        sep = " ")
    for (driver in .DRIVER_ORDER) {
      cat(driver, ":\t", round(means[[driver]]), "\n", sep = " ")
    }
  }

  out
}
