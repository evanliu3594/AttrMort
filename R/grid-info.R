# ── The analysis grid, made explicit ────────────────────────────────────
#
# An analysis runs on one grid: the one `conc_real` brings with it (a raster),
# or the one the attribution field carries (a table). Everything that is
# compared across scenarios has to sit on that same grid, so the grid itself
# is worth an object -- a table of cell coordinates and domain labels with the
# georeferencing that produced it attached.
#
# build_grid_info() is deliberately a wrapper, not a second implementation:
# phases 1, 2 and 4 of the Mortality() pipeline do all the work
# (.check_input_files(), .align_raster_inputs(), .ingest_and_map(),
# .attach_admin()), so the table describes exactly the grid a Mortality() run
# on the same inputs would use. A second alignment path would be free to
# drift from the one the analysis runs on.

# The coordinate columns of a grid table: `x`/`y` first (what the pipeline
# itself builds from a raster), then the documented `lon`/`lat` spellings.
# character(0) when the table carries no coordinate pair.
.grid_xy <- function(df) {
  low <- tolower(names(df))
  for (pair in list(c("x", "y"), c("lon", "lat"), c("longitude", "latitude"))) {
    hit <- match(pair, low)
    if (!anyNA(hit)) {
      return(names(df)[hit])
    }
  }
  character(0)
}

# Cell size of a coordinate key vector: the mean spacing between the distinct
# coordinates. min(diff()) would report 0.24 for a 0.25 degree grid whose cell
# centres are stored rounded (5.12, 5.38, ...); the mean spacing recovers the
# nominal resolution. NA for a single coordinate.
.grid_spacing <- function(v) {
  u <- sort(unique(as.numeric(v)))
  if (length(u) < 2) {
    return(NA_real_)
  }
  (u[length(u)] - u[1]) / (length(u) - 1)
}

# Georeferencing of the grid, as list(res, ext, crs). With an aligned raster
# it is that raster's own geometry; without one it is derived from the cell
# centres, whose range is widened by half a cell to give the cell edges. A
# tabular grid carries no CRS -- plain coordinates do not name one.
.grid_georef <- function(x, y, template = NULL) {
  if (!is.null(template)) {
    return(list(
      res = mean(terra::res(template)),
      ext = unname(as.vector(terra::ext(template))),
      crs = terra::crs(template)
    ))
  }

  x <- as.numeric(x)
  y <- as.numeric(y)
  res <- c(.grid_spacing(x), .grid_spacing(y))
  res <- if (all(is.na(res))) NA_real_ else mean(res, na.rm = TRUE)
  half <- if (is.na(res)) 0 else res / 2

  list(
    res = res,
    ext = c(min(x) - half, max(x) + half, min(y) - half, max(y) + half),
    crs = NA_character_
  )
}

#' Build the analysis grid info table
#'
#' @description
#' Describes the grid a [Mortality()] run uses, as a table: one row per grid
#' cell with the coordinate keys and the domain labels, plus the georeferencing
#' of that grid as attributes.
#'
#' The grid is defined by `conc_real`, exactly as in [Mortality()] -- a raster
#' through the pipeline's own alignment, a table through its coordinate
#' columns. `pop_total`, `conc_cf` and `target_res` are read the way
#' [Mortality()] reads them, so the target resolution resolved here is the one
#' that run would use. `admin` is rasterized onto the grid by the pipeline's
#' own `.attach_admin()`, which is what turns boundaries into the domain
#' column.
#'
#' The reason to have the table at all is **one grid, reused**: every scenario
#' of an analysis has to run on the same grid, and this table is the object
#' that says which. Hand it back as `calc_fild =` and [Mortality()] checks the
#' keys against the rasters it is given, so a table from another grid is
#' reported instead of being joined silently.
#'
#' @param conc_real Real-world exposure data defining the grid: a raster path
#'   (`.tif`, `.nc`, ...), a `SpatRaster`, or a data.frame / table path with
#'   coordinate columns (`x`/`y`, `lon`/`lat` or `longitude`/`latitude`).
#' @param pop_total Optional population input, aligned onto the target grid the
#'   way [Mortality()] aligns it. It does not define the grid's extent, but a
#'   raster at a finer resolution than `conc_real` does lower the target
#'   resolution -- the same interaction [Mortality()] has.
#' @param conc_cf Optional counterfactual exposure. Accepted for symmetry with
#'   [Mortality()] so that one argument list can be reused; it is aligned like
#'   the other rasters but never defines the grid.
#' @param admin Administrative boundaries: a shapefile path, an `sf` object,
#'   or `NULL` (default, no domain column). Rasterized onto the grid and joined
#'   in, exactly as `admin =` does in [Mortality()].
#' @param admin_col Character. Attribute column of `admin` holding the domain
#'   label. `NULL` (default) uses `"admin"`, the default of [Mortality()]; an
#'   unknown column falls back to the first character column of the
#'   boundaries.
#' @param target_res Numeric. Target grid resolution in degrees, resolved and
#'   applied as in [Mortality()]. `NULL` (default) auto-detects it from the
#'   rasters.
#' @param dgt_coord Integer. Decimal places used to render the coordinate keys.
#'   Default 2, and it has to agree with the `dgt_coord` of the runs the table
#'   is handed back to.
#' @param path Character or `NULL` (default). When given, the table is written
#'   there according to its extension: `.rds` ([saveRDS()]), `.csv`
#'   ([readr::write_csv()]) or `.xlsx` (`writexl`, a suggested package). The
#'   resolved path is reported with a message. The table is returned either
#'   way; any other extension is an error.
#'
#' @return A data.frame with the coordinate keys `x` and `y` (or whatever the
#'   coordinate columns of a tabular `conc_real` are called) followed by the
#'   domain column, when `admin` supplies one or when a tabular `conc_real`
#'   already carries one. Value columns (`conc`, `pop`, scenario columns) are
#'   never included: the table describes the grid, not the data on it. The
#'   georeferencing is attached as attributes:
#'   * `res` -- cell size in degrees (numeric): the aligned raster's
#'     resolution, or the mean spacing of a tabular grid's cell centres;
#'   * `ext` -- `c(xmin, xmax, ymin, ymax)` (numeric, length 4): the raster
#'     extent, or the range of the cell centres widened by half a cell;
#'   * `crs` -- coordinate reference system (character): the raster's CRS, or
#'     `NA_character_` for a tabular grid, whose coordinates name no CRS;
#'   * `n_cells` -- number of grid cells, i.e. rows (integer);
#'   * `dgt_coord` -- the decimal places the coordinate keys were rendered at
#'     (integer).
#'
#' @seealso [Mortality()]
#'
#' @export
#'
#' @examples
#' extdata <- system.file("extdata", package = "AttrMort")
#' grid_info <- readxl::read_excel(file.path(extdata, "grid_info.xlsx"))
#'
#' # Describe the grid of the shipped example instead of assuming it
#' info <- build_grid_info(conc_real = grid_info)
#' head(info)
#' attr(info, "n_cells")   # cells
#' attr(info, "res")       # degrees
#'
#' # One grid, several scenarios: build the table once and hand the same one
#' # to every run, so the scenarios cannot drift apart
#' \dontrun{
#'   scenarios <- c("base2015", "scenario2030")
#'   gi <- build_grid_info(conc_real = "pm25_scenarios.tif",
#'                         pop_total = "population.tif",
#'                         admin = "boundaries.shp", admin_col = "iso_a3",
#'                         path = file.path(tempdir(), "grid_info.rds"))
#'
#'   lapply(scenarios, function(s) {
#'     Mortality(CRF = "GEMM", calc_fild = gi, scenario = s,
#'               conc_real = "pm25_scenarios.tif", pop_total = "population.tif",
#'               age_struc = "age_structure.csv", mort_rate = "mortality.csv",
#'               mort_lvl  = "iso_a3")
#'   })
#' }
build_grid_info <- function(conc_real, pop_total = NULL, conc_cf = NULL,
                            admin = NULL, admin_col = NULL, target_res = NULL,
                            dgt_coord = 2, path = NULL) {
  .check_input_files(conc_real = conc_real, pop_total = pop_total,
                     conc_cf = conc_cf, admin = admin)

  # ── phase 1-2: alignment, exactly as Mortality() does it ───────────
  # Whether the grid comes from a raster decides where `res`/`ext`/`crs` come
  # from: a tabular `conc_real` defines the grid itself, and a raster
  # `pop_total` alongside it only places the boundary rasterization.
  conc_raster <- .is_raster_input(conc_real)

  spatial <- .align_raster_inputs(conc_real, pop_total, conc_cf,
                                  scenario = NULL, target_res = target_res,
                                  dgt_coord = dgt_coord)

  # ── phase 3: ingestion and column mapping ──────────────────────────
  conc_real <- .ingest_and_map(spatial$conc_real, schema = "location",
                               dgt_coord = dgt_coord, label = "conc_real")

  xy <- .grid_xy(conc_real)
  if (length(xy) != 2) {
    stop(
      "No grid coordinates in `conc_real`: the analysis grid is defined by ",
      "its `x`/`y` (or `lon`/`lat`) columns. A raster input supplies them on ",
      "its own; a tabular `conc_real` has to carry them. Columns available: ",
      paste(names(conc_real), collapse = ", "), ".",
      call. = FALSE
    )
  }

  # Coordinate keys, then the domain label. Whatever else `conc_real` carries
  # is data on the grid (a scenario column, a raster band), not the grid
  # itself, so it stays out.
  keep <- xy
  if ("location" %in% names(conc_real)) {
    keep <- c(keep, "location")
  }
  info <- conc_real[, keep] |> distinct()

  # ── phase 4: domain labels from the boundaries ─────────────────────
  # Cells outside every boundary keep an NA label rather than being dropped:
  # they are still grid cells, and this is what the raster-only path puts in
  # `calc_fild`.
  if (!is.null(admin)) {
    info <- .attach_admin(
      info, admin,
      admin_col = if (is.null(admin_col)) "admin" else admin_col,
      mort_lvl = NULL, mort_rate = NULL,
      template = spatial$template, target_res = target_res,
      dgt_coord = dgt_coord
    )
  }

  geo <- .grid_georef(info[[xy[1]]], info[[xy[2]]],
                      if (conc_raster) spatial$template else NULL)
  attr(info, "res")       <- geo$res
  attr(info, "ext")       <- geo$ext
  attr(info, "crs")       <- geo$crs
  attr(info, "n_cells")   <- as.integer(nrow(info))
  attr(info, "dgt_coord") <- as.integer(dgt_coord)

  if (!is.null(path)) {
    .write_grid_info(info, path)
  }

  info
}

# Write the info table to `path`, chosen by extension. Kept next to
# build_grid_info() because the set of supported formats is part of its
# documentation; the write is a side effect, never a replacement for the
# return value.
.write_grid_info <- function(info, path) {
  if (!is.character(path) || length(path) != 1 || is.na(path)) {
    stop("`path` must be a single file path.", call. = FALSE)
  }

  ext <- tolower(file_ext(path))
  if (identical(ext, "rds")) {
    saveRDS(info, path)
  } else if (identical(ext, "csv")) {
    readr::write_csv(info, path)
  } else if (identical(ext, "xlsx")) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop(
        "Writing `.xlsx` needs the `writexl` package (a suggested ",
        "dependency). Install it with install.packages(\"writexl\"), or ",
        "write `.rds` / `.csv`, which need nothing extra.",
        call. = FALSE
      )
    }
    writexl::write_xlsx(info, path)
  } else {
    stop(
      "Unsupported `path` extension: \".", ext, "\". Supported: \".rds\", ",
      "\".csv\", \".xlsx\".",
      call. = FALSE
    )
  }

  message("Grid info written to: ", normalizePath(path, mustWork = FALSE))
  invisible(path)
}
