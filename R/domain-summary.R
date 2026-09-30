# ── The domain-level view of a gridded analysis ─────────────────────────
#
# Mortality() is grain-agnostic: the analysis grain is the grain of
# `calc_fild`, one row per grid cell or one row per domain. A domain-only
# skeleton is a legitimate input -- one population-weighted concentration per
# country is the national workflow -- but the two grains do not give the same
# number. On a grid, a domain's PWRR is the population-weighted mean of the
# relative risks of its cells; on a domain-only skeleton it is the relative
# risk at the domain's population-weighted mean concentration. That is a
# Jensen gap (mean of RR vs RR of mean), not a rounding difference, so it has
# to stay visible instead of being dispatched silently: domain_summary() is
# the table that makes the domain grain explicit, and Mortality() reports the
# grain it resolved in one line per run.
#
# Like build_grid_info(), this is a wrapper and not a second implementation:
# the alignment, ingestion, scenario extraction and boundary rasterization of
# the Mortality() pipeline do the work (.check_input_files(),
# .align_raster_inputs(), .ingest_and_map(), .attach_admin(),
# .extract_scenario()), and the population-weighted mean comes from
# .domain_pwe(), the same helper the aggregated Mortality() result uses. A
# second aggregation path would be free to drift from the one the analysis
# runs on.

#' Summarise exposure and population by domain
#'
#' @description
#' Reduces gridded or tabular inputs to **one row per domain**: the
#' population-weighted mean concentration, the unweighted mean next to it, the
#' domain population and the number of cells behind the row.
#'
#' The table exists to make the domain grain of an analysis explicit. Passing
#' one row per domain back to [Mortality()] as `calc_fild` (with `conc_pwe` as
#' the exposure and `pop_total` as the population) runs the **national**
#' workflow: one relative risk evaluation per domain. That is a different
#' calculation from the grid path, where a domain's PWRR is the
#' population-weighted mean of the relative risks of its cells -- mean of RR
#' against RR of mean, a Jensen gap. The two are never dispatched into each
#' other silently; [Mortality()] reports the grain it resolved, and the
#' `conc_mean` column is here to show how far the domain mean sits from the
#' population-weighted one.
#'
#' The domain labels come from the boundaries (`admin` rasterized onto the
#' grid, as in [Mortality()]) or from a domain column the exposure data
#' already carries. `conc_real`, `pop_total` and `admin` are read exactly the
#' way [Mortality()] reads them, so the cells counted here are the cells that
#' run would use.
#'
#' @param conc_real Real-world exposure data: a raster path (`.tif`, `.nc`,
#'   ...), a `SpatRaster`, or a data.frame / table path. A wide table (or a
#'   multi-band raster) is narrowed with `scenario =` first.
#' @param pop_total Population counts, aligned and ingested the way
#'   [Mortality()] does it.
#' @param admin Administrative boundaries: a shapefile path, an `sf` object,
#'   or `NULL` (default) when the exposure data carries its own domain column.
#'   Rasterized onto the grid and joined in, exactly as `admin =` does in
#'   [Mortality()]: the boundaries supply the domain labels, and they are
#'   rasterized onto the grid a raster `conc_real` brings with it. A tabular
#'   `conc_real` that already names its domains needs no `admin`.
#' @param admin_col Character. Attribute column of `admin` holding the domain
#'   label. `NULL` (default) uses `"admin"`.
#' @param mort_lvl Character. Name to give the domain column (and the column
#'   `admin` is renamed to, as in [Mortality()]). `NULL` (default) keeps the
#'   name the boundaries or the exposure table provide.
#' @param target_res Numeric. Target grid resolution in degrees, resolved and
#'   applied as in [Mortality()]: it aligns the raster inputs and it is the
#'   grid `admin` is rasterized onto when no raster defines one. `NULL`
#'   (default) auto-detects it from the rasters.
#' @param dgt_coord Integer. Decimal places used to render the coordinate keys.
#'   Default 2.
#' @param scenario Character. Scenario column (or raster band) to extract from
#'   wide inputs via [getConc()] and [getPop()]. `NULL` (default) uses the
#'   inputs as given.
#' @param path Character or `NULL` (default). When given, the table is written
#'   there according to its extension: `.rds` ([saveRDS()]), `.csv`
#'   ([readr::write_csv()]) or `.xlsx` (`writexl`, a suggested package). The
#'   resolved path is reported with a message. The table is returned either
#'   way; any other extension is an error.
#'
#' @return A data.frame with one row per domain and the columns:
#'   * the domain column -- named after the `admin` / `admin_col` boundary
#'     column, after `mort_lvl` when one is given, or after the domain column
#'     the exposure data carries (`location` and friends);
#'   * `conc_pwe` -- population-weighted mean concentration of the domain, from
#'     the pipeline's own `.domain_pwe()`. Concentration keys are rendered at
#'     the package default `dgt_conc = 1` before anything is computed, so this
#'     is the same weighted mean `Mortality(aggregate = TRUE)` reports as
#'     `conc_pwe` for the same inputs;
#'   * `conc_mean` -- unweighted mean concentration of the domain's cells, kept
#'     as the contrast to `conc_pwe`;
#'   * `pop_total` -- sum of the domain's cell populations;
#'   * `n_cells` -- number of cells behind the row, i.e. of the cells that
#'     carry an exposure value, a population and a domain label (cells outside
#'     every boundary carry no label and are not summarised).
#'
#'   Rows follow the domain column in ascending order.
#'
#' @seealso [Mortality()], [build_grid_info()]
#'
#' @export
#'
#' @examples
#' extdata <- system.file("extdata", package = "AttrMort")
#' sheet   <- function(f) readxl::read_excel(file.path(extdata, f))
#'
#' # The shipped example keeps its grid skeleton and its exposure in separate
#' # files; the summary needs the domain column on the exposure table
#' grid <- merge(sheet("grid_info.xlsx"), sheet("grid_exposure.xlsx"),
#'               by = c("x", "y"))
#'
#' ds <- domain_summary(
#'   conc_real = grid,
#'   pop_total = sheet("grid_pop.xlsx"),
#'   scenario  = "base2015"
#' )
#' ds
#'
#' # The national workflow: hand the three domains back to Mortality() and the
#' # burden is computed once per domain, at its population-weighted mean
#' # concentration -- a different grain from the 6000-cell grid run
#' \dontrun{
#'   Mortality(
#'     CRF = "GEMM", scenario = "base2015", mort_lvl = "location",
#'     calc_fild = data.frame(location = ds$location),
#'     conc_real = data.frame(location = ds$location, base2015 = ds$conc_pwe),
#'     pop_total = data.frame(location = ds$location, base2015 = ds$pop_total),
#'     age_struc = sheet("national_age_structure.xlsx"),
#'     mort_rate = sheet("national_mortality.xlsx")
#'   )
#' }
domain_summary <- function(conc_real, pop_total, admin = NULL, admin_col = NULL,
                           mort_lvl = NULL, target_res = NULL, dgt_coord = 2,
                           scenario = NULL, path = NULL) {
  .check_input_files(conc_real = conc_real, pop_total = pop_total,
                     admin = admin)

  # ── phases 1-3: alignment, ingestion and column mapping ────────────
  spatial   <- .align_raster_inputs(conc_real, pop_total, NULL, scenario,
                                    target_res, dgt_coord)
  conc_real <- .ingest_and_map(spatial$conc_real, schema = "location",
                               dgt_coord = dgt_coord, label = "conc_real")
  pop_total <- .ingest_and_map(spatial$pop_total, schema = "location",
                               dgt_coord = dgt_coord, label = "pop_total")

  # ── the domain label, read before the scenario is extracted ────────
  # .extract_scenario() reduces each table to its key columns, and a
  # coordinate key beats a domain key there, so a coordinate-bearing wide
  # exposure table loses its domain column. The domain label is what this
  # function reports on, so the skeleton -- the label plus the coordinates
  # `admin` rasterizes onto -- is taken from the ingested table.
  #
  # Which of the two supplies the labels follows Mortality(): boundaries win,
  # because that is the only step that puts geography on a cell; a `conc_real`
  # that carries a domain column already names its own domains.
  named_dom <- if (is.null(mort_lvl)) admin_col else mort_lvl
  xy_cols   <- .grid_xy(conc_real)
  if (is.null(admin)) {
    dom_col <- .domain_col_of(conc_real, named_dom)
    keep    <- unique(c(xy_cols, dom_col))
  } else {
    if (length(xy_cols) != 2) {
      stop(
        "`admin` needs gridded `conc_real` (coordinate columns, or a raster ",
        "that carries them) to rasterize the boundaries onto; a domain-only ",
        "`conc_real` already names its own domains.",
        call. = FALSE
      )
    }
    dom_col <- NULL
    keep    <- xy_cols
  }
  calc_fild <- if (length(keep) > 0) {
    conc_real[, keep, drop = FALSE] |> distinct()
  } else {
    conc_real[0, ]
  }

  # ── phase 5: scenario extraction, exactly as Mortality() does it ───
  extracted <- .extract_scenario(conc_real, pop_total, NULL, NULL, NULL,
                                 scenario, dgt_conc = 1)
  conc_real <- extracted$conc_real
  pop_total <- extracted$pop_total

  # ── phase 4: domain labels from the boundaries ─────────────────────
  if (!is.null(admin)) {
    calc_fild <- .attach_admin(
      calc_fild, admin,
      admin_col = if (is.null(admin_col)) "admin" else admin_col,
      mort_lvl = mort_lvl, mort_rate = NULL,
      template = spatial$template, target_res = target_res,
      dgt_coord = dgt_coord
    )
    # Whatever the boundary rasterization added is the domain column; the
    # name follows the admin column, or `mort_lvl` when one was named.
    dom_col <- .domain_col_of(calc_fild, c(named_dom,
                                           setdiff(names(calc_fild), keep)))
    # A rasterization that lands on another set of cell centres than the
    # grid leaves every label NA -- a tabular grid gets a template built from
    # its coordinate range, whose cell centres need not coincide with its own
    # keys. That is not a domain column, so it is reported rather than
    # summarised as one huge unnamed domain.
    if (is.null(dom_col) || all(is.na(calc_fild[[dom_col]]))) {
      stop(
        "`admin` labelled no cell of `conc_real`: after rasterizing the ",
        "boundaries onto the grid the domain column is missing or NA ",
        "everywhere, so there is nothing to summarise by. Boundaries are ",
        "rasterized onto the grid of a raster `conc_real`; pass one (a ",
        "GeoTIFF/netCDF path or a `SpatRaster`), or drop `admin=` and let ",
        "the exposure table carry the domain column itself.",
        call. = FALSE
      )
    }
  }

  if (is.null(dom_col)) {
    stop(
      "No domain column in `conc_real`, so there is nothing to summarise by: ",
      "a domain summary is one row per domain. Pass `admin=` (a shapefile ",
      "path or an sf object) with `admin_col=` to rasterize boundaries onto ",
      "the grid, name the column with `mort_lvl =`, or supply a `conc_real` ",
      "that carries a domain column of its own (e.g. `location`). Columns ",
      "available: ", paste(names(conc_real), collapse = ", "), ".",
      call. = FALSE
    )
  }

  if (nrow(calc_fild) == 0) {
    stop("`conc_real` carries no rows to summarise.", call. = FALSE)
  }

  # The same all-problems-at-once key check Mortality() applies to the same
  # inputs, so a domain table that cannot be joined is reported the same way.
  .check_inputs(
    list(conc_real = conc_real, pop_total = pop_total),
    calc_fild
  )

  # ── one row per domain ─────────────────────────────────────────────
  # `n_cells` counts the cells that carry both values, which is the set the
  # weighted mean is taken over; `conc_pwe` is the pipeline's own helper, so
  # this column and `Mortality(aggregate = TRUE)` cannot disagree.
  cells <- list(calc_fild, conc_real, pop_total) |>
    reduce(left_join) |>
    na.omit()

  out <- cells |>
    group_by(pick(all_of(dom_col))) |>
    summarise(
      conc_mean = mean(as.numeric(conc)),
      pop_total = sum(pop),
      n_cells   = n(),
      .groups   = "drop"
    ) |>
    left_join(.domain_pwe(calc_fild, conc_real, pop_total, dom_col),
              by = dom_col) |>
    select(all_of(dom_col), conc_pwe, conc_mean, pop_total, n_cells)

  if (!is.null(path)) {
    .write_domain_summary(out, path)
  }

  out
}

# Write the summary table to `path`, chosen by extension. Kept next to
# domain_summary() because the set of supported formats is part of its
# documentation -- the same three build_grid_info() accepts. The write is a
# side effect, never a replacement for the return value.
.write_domain_summary <- function(x, path) {
  if (!is.character(path) || length(path) != 1 || is.na(path)) {
    stop("`path` must be a single file path.", call. = FALSE)
  }

  ext <- tolower(file_ext(path))
  if (identical(ext, "rds")) {
    saveRDS(x, path)
  } else if (identical(ext, "csv")) {
    readr::write_csv(x, path)
  } else if (identical(ext, "xlsx")) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop(
        "Writing `.xlsx` needs the `writexl` package (a suggested ",
        "dependency). Install it with install.packages(\"writexl\"), or ",
        "write `.rds` / `.csv`, which need nothing extra.",
        call. = FALSE
      )
    }
    writexl::write_xlsx(x, path)
  } else {
    stop(
      "Unsupported `path` extension: \".", ext, "\". Supported: \".rds\", ",
      "\".csv\", \".xlsx\".",
      call. = FALSE
    )
  }

  message("Domain summary written to: ", normalizePath(path, mustWork = FALSE))
  invisible(path)
}
