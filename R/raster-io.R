# ── Geospatial ingestion layer ─────────────────────────────────

#' Convert a raster to a grid data.frame
#'
#' Reads a single or multi-band GeoTIFF (or any raster format supported by
#' terra), extracts cell coordinates and values, and returns a data.frame
#' suitable for joining with other inputs in the mortality() pipeline.
#'
#' The layers of a multi-band raster are scenarios on one grid, so every
#' scenario is expected to share the same validity mask. A cell that carries
#' a value in only some layers is reported with a warning and dropped from
#' the analysis grid, instead of silently narrowing it for every scenario.
#'
#' @param path Character. Path to a raster file (GeoTIFF or other
#'   terra-supported format).
#' @param band_names Character vector. Names for each band. If NULL, band
#'   names are taken from the file metadata; if metadata is empty, defaults
#'   to "band_1", "band_2", ...
#' @param dgt Integer. Number of decimal places for coordinate rounding.
#'   Must match the `dgt_coord` of the other inputs (default 2).
#'   Coordinates are returned as character strings for matchable()-style
#'   joins.
#'
#' @return A data.frame with columns \code{x}, \code{y} (character) and one
#'   column per raster band (numeric).
#'
#' @noRd
raster_to_grid <- function(path, band_names = NULL, dgt = 2) {
  # Accept a SpatRaster as well as a path: terra::rast() on an existing
  # SpatRaster would return an empty *template* rather than the data.
  r <- if (inherits(path, "SpatRaster")) path else terra::rast(path)
  n_lyr <- terra::nlyr(r)

  # detect band names: file metadata first, then band_1, band_2, ...
  if (is.null(band_names)) {
    nm <- names(r)
    default_names <- length(nm) != n_lyr || all(nm == "") ||
      all(str_detect(nm, "^lyr\\.?[0-9]*$"))
    band_names <- if (default_names) paste0("band_", seq_len(n_lyr)) else nm
  }

  if (length(band_names) != n_lyr) {
    .abort(str_c(
      "band_names length ({length(band_names)}) does not match number of ",
      "raster layers ({n_lyr})."
    ))
  }

  # convert to data.frame. Every cell is read, then only the cells carrying a
  # value in *all* layers are kept. Multi-band rasters are scenarios on one
  # grid, so a cell that some layers carry and others do not means the
  # scenarios do not share one validity mask: report it instead of dropping
  # the cell from the whole analysis grid without a word.
  grid <- terra::as.data.frame(r, xy = TRUE, na.rm = FALSE)

  # rename value columns
  value_cols <- setdiff(names(grid), c("x", "y"))
  grid <- set_names(grid, c(setdiff(names(grid), value_cols), band_names))

  n_na <- rowSums(is.na(grid[band_names]))
  incomplete <- n_na > 0 & n_na < length(band_names)
  if (any(incomplete)) {
    missing <- map_int(band_names, function(b) sum(is.na(grid[[b]][incomplete])))
    lines <- sprintf("%s: %d", band_names[missing > 0], missing[missing > 0])
    if (length(lines) > 5) {
      lines <- c(utils::head(lines, 5), "...")
    }
    cli::cli_warn(str_c(
      "{sum(incomplete)} cell(s) carry values in only some of the {length(band_names)} ",
      "raster layer(s); multi-band rasters are expected to share one validity mask. The ",
      "incomplete cell(s) are dropped from the analysis grid (missing values per layer: ",
      "{paste(lines, collapse = \", \")})."
    ))
  }
  grid <- filter(grid, n_na == 0)

  # round and coerce coordinates to character (matchable-compatible)
  grid$x <- matchable(grid$x, dgt = dgt)
  grid$y <- matchable(grid$y, dgt = dgt)

  grid
}

# Aggregate a count raster onto a coarser template without losing totals.
#
# terra::resample(method = "sum") is not a conservative aggregation, so when
# the target resolution is an exact multiple of the source resolution we
# aggregate first (which conserves the sum) and only then resample onto the
# template grid. Totals before and after are compared, and a warning is
# issued when more than `tol` of the total is lost.
.aggregate_pop <- function(r, template, tol = 0.001) {
  res_r <- terra::res(r)
  res_t <- terra::res(template)
  fact  <- res_t / res_r

  total_before <- terra::global(r, fun = "sum", na.rm = TRUE)[[1]]

  if (all(fact >= 1 - 1e-6) && all(abs(fact - round(fact)) < 1e-6)) {
    # terra::aggregate() takes the factor as (rows, columns); `fact` is
    # (x, y), so the two axes are reversed here. They may need different
    # factors on a non-square target grid. A factor of one means nothing to
    # aggregate, and terra would warn about the no-op.
    agg <- if (any(round(fact) > 1L)) {
      terra::aggregate(r, fact = rev(round(fact)), fun = "sum", na.rm = TRUE)
    } else {
      r
    }
    out <- terra::resample(agg, template, method = "sum")
  } else if (all(fact < 1 - 1e-6)) {
    # Target is finer: a population count has to be *divided* between the finer
    # cells, not interpolated. Bilinear hands every sub-cell the source value,
    # which multiplies the total by the subdivision factor (2x2 deg holding 100
    # people becomes four 1x1 deg cells holding 100 each).
    n    <- ceiling(1 / fact)
    fine <- terra::disagg(r, fact = rev(n), method = "near") / prod(n)
    out  <- terra::resample(fine, template, method = "sum")
  } else {
    cli::cli_warn(str_c(
      "Population raster resolution ({paste(round(res_r, 6), collapse = \" x \")}) is not ",
      "an exact multiple of the target ({paste(round(res_t, 6), collapse = \" x \")}); ",
      "falling back to plain resampling, which may not preserve totals."
    ))
    out <- terra::resample(r, template, method = "sum")
  }

  total_after <- terra::global(out, fun = "sum", na.rm = TRUE)[[1]]
  if (is.finite(total_before) && is.finite(total_after) && total_before != 0) {
    lost <- abs(total_after - total_before) / abs(total_before)
    if (lost > tol) {
      cli::cli_warn(str_c(
        "Aggregating the population raster changed the total by ",
        "{sprintf(\"%.4f%%\", 100 * lost)} ({format(total_before, big.mark = \",\")} -> ",
        "{format(total_after, big.mark = \",\")})."
      ))
    }
  }
  out
}

#' Align multiple rasters to a common target grid
#'
#' Resamples or aggregates a list of SpatRaster objects so they all share
#' the same resolution, extent, and CRS - a prerequisite for pixel-level
#' joins in the mortality() pipeline.
#'
#' @param raster_list Named list of SpatRaster objects.
#' @param target_res Numeric. Target resolution in degrees (e.g. 0.1), one
#'   number or two for the x and y cell size of a non-square grid.
#'   If NULL, determined from \code{target_raster} or auto-detected.
#' @param target_raster SpatRaster to use as the template grid.
#'   Overrides \code{target_res}.
#' @param pop_names Character vector. Names (in \code{raster_list}) of
#'   population rasters - these are aggregated by \strong{sum} to preserve
#'   total counts. \code{NULL} guesses from the raster names: those matching
#'   \code{"pop"} are summed and every other raster is resampled.
#'
#' @details
#' If both \code{target_res} and \code{target_raster} are NULL, the coarsest
#' raster in \code{raster_list} is used as the reference.
#'
#' @return A named list of SpatRaster objects, all with identical resolution,
#'   extent, and CRS (WGS84 / EPSG:4326).
#'
#' @noRd
align_to_target <- function(raster_list,
                             target_res    = NULL,
                             target_raster = NULL,
                             pop_names     = NULL) {

  stopifnot(is.list(raster_list), length(raster_list) > 0)

  # ---- resolve target grid -----------------------------------------------
  if (!is.null(target_raster)) {
    template <- target_raster
  } else if (!is.null(target_res)) {
    # create template from the extent of the first raster
    ref <- raster_list[[1]]
    template <- terra::rast(terra::ext(ref), resolution = target_res)
    terra::crs(template) <- "EPSG:4326"
  } else {
    # auto-detect: use the coarsest raster as reference
    resolutions <- map_dbl(raster_list, function(r) mean(terra::res(r)))
    coarsest    <- which.max(resolutions)
    template    <- raster_list[[coarsest]]
    cli::cli_inform(str_c(
      "Auto-detected target resolution: {(.fmt_res(terra::res(template)))} deg ",
      "(from raster '{names(raster_list)[coarsest]}')"
    ))
  }

  # ---- classify raster types if not provided -----------------------------
  if (is.null(pop_names)) {
    all_names <- tolower(names(raster_list))
    pop_names <- names(raster_list)[str_detect(all_names, "pop")]
  }

  # ---- align each raster -------------------------------------------------
  aligned <- map(names(raster_list), function(nm) {
    r <- raster_list[[nm]]

    # reproject to WGS84 if needed
    if (!is.na(terra::crs(r)) && terra::crs(r) != terra::crs(template)) {
      cli::cli_warn("Reprojecting '{nm}' to EPSG:4326.")
      r <- terra::project(r, template)
    } else if (is.na(terra::crs(r))) {
      terra::crs(r) <- "EPSG:4326"
    }

    if (nm %in% pop_names) {
      .aggregate_pop(r, template)
    } else {
      terra::resample(r, template, method = "bilinear")
    }
  })

  names(aligned) <- names(raster_list)
  aligned
}

#' Rasterize an administrative boundary shapefile
#'
#' Converts a polygon shapefile (country, province, etc.) to a grid
#' data.frame matching the coordinate system and resolution of a template
#' raster. Each pixel gets the value of the admin unit it falls in.
#'
#' @param shp_path Character path to a shapefile (.shp), an \code{sf} object,
#'   or \code{NULL}. If \code{NULL}, the world country boundaries supplied by
#'   the \code{rnaturalearth} package are used
#'   (\code{rnaturalearth::ne_countries()}); nothing is downloaded.
#' @param template_raster SpatRaster. Defines the target grid (resolution,
#'   extent, CRS) onto which the shapefile is rasterized.
#' @param admin_col Character. Name of the attribute column to use as the
#'   admin unit identifier. If not found in the shapefile, the first
#'   character column is used with a warning.
#' @param dgt Integer. Decimal places for coordinate rounding. Passed to
#'   \code{matchable()}.
#'
#' @return A data.frame with columns \code{x}, \code{y} (character) and the
#'   admin column (character or factor). Non-land pixels (oceans) are
#'   excluded via \code{na.rm = TRUE}.
#'
#' @noRd
shapefile_to_grid <- function(shp_path        = NULL,
                               template_raster,
                               admin_col       = "admin",
                               dgt             = 2) {

  # ---- load shapefile ----------------------------------------------------
  if (is.null(shp_path)) {
    if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
      .abort(str_c(
        "Package 'rnaturalearth' is required for automatic world boundaries. ",
        "Install it with: install.packages('rnaturalearth')"
      ))
    }
    shp <- rnaturalearth::ne_countries(scale = 110, returnclass = "sf")
  } else if (inherits(shp_path, "sf")) {
    shp <- shp_path
  } else if (is.character(shp_path)) {
    shp <- sf::st_read(shp_path, quiet = TRUE)
  } else {
    .abort("shp_path must be a file path, an sf object, or NULL.")
  }

  # ---- resolve admin column ----------------------------------------------
  if (!admin_col %in% names(shp)) {
    char_cols <- names(shp)[map_lgl(shp, is.character)]
    char_cols <- setdiff(char_cols, "geometry")
    if (length(char_cols) > 0) {
      cli::cli_warn(
        "admin_col '{admin_col}' not found in shapefile. Using '{char_cols[1]}' instead."
      )
      admin_col <- char_cols[1]
    } else {
      .abort("No character columns found in shapefile attributes.")
    }
  }

  # ---- reproject shapefile to match template -----------------------------
  if (!is.na(terra::crs(shp)) && terra::crs(shp) != terra::crs(template_raster)) {
    shp <- sf::st_transform(shp, terra::crs(template_raster))
  }

  # ---- rasterize ----------------------------------------------------------
  admin_raster <- terra::rasterize(
    shp, template_raster,
    field  = admin_col,
    touches = TRUE
  )

  # ---- convert to data.frame ---------------------------------------------
  admin_df <- terra::as.data.frame(admin_raster, xy = TRUE, na.rm = TRUE)

  admin_df$x <- matchable(admin_df$x, dgt = dgt)
  admin_df$y <- matchable(admin_df$y, dgt = dgt)

  admin_df
}


# ── Resolution selection and interactive confirmation ──────────

# Cell counts at which the resolution decision changes gear, plus the fallback
# a non-interactive session uses for a grid too large to confirm. Named here so
# the thresholds are greppable instead of buried in the flow.
.RES_AUTO_CONFIRM_CELLS <- 5e6
.RES_PROMPT_CELLS       <- 5e7
.RES_MAX_CELLS          <- 1e9
.RES_FALLBACK           <- 0.1
.RES_SUGGESTIONS        <- c(0.1, 0.05, 0.01)

#' Resolve target resolution for spatial alignment
#'
#' When multiple rasters at different resolutions are provided, determines
#' the output grid resolution. If \code{target_res} is provided it is used
#' directly. If \code{NULL}, the finest input resolution is auto-detected
#' and the user is prompted to confirm based on estimated cell counts.
#'
#' @param conc_rast SpatRaster or NULL. The concentration/exposure raster.
#' @param pop_rast SpatRaster or NULL. The population raster.
#' @param target_res Numeric or NULL. Explicit target resolution in degrees:
#'   one number, or two for the x and y cell size of a non-square grid.
#'
#' @return Numeric. The confirmed target resolution in degrees: one number for
#'   a square target, `c(res_x, res_y)` for a non-square one.
#' @noRd
.resolve_target_res <- function(conc_rast, pop_rast, target_res) {
  if (!is.null(target_res)) {
    if (!is.numeric(target_res) || !length(target_res) %in% c(1L, 2L) ||
        anyNA(target_res) || any(target_res <= 0)) {
      .abort(str_c(
        "`target_res` must be positive (one number, or two for the x/y ",
        "cell size in degrees)."
      ))
    }
    target_res <- as.numeric(target_res)
    cli::cli_inform("Using specified target resolution: {(.fmt_res(target_res))} deg")
    return(target_res)
  }

  resolutions <- .raster_resolutions(conc_rast, pop_rast)
  if (length(resolutions) == 0) {
    return(NULL)
  }

  cli::cli_inform(
    "Detected raster resolutions: {paste(map_chr(resolutions, .fmt_res), collapse = \"; \")} deg"
  )

  # The two axes are kept apart: averaging them (the old behaviour) silently
  # turned a 2.5 x 2 deg grid into a 2.25 deg one and moved every cell centre.
  # The target is the finest input per axis, and is collapsed to one number
  # only when the axes agree, so a square grid keeps its old resolution.
  candidate <- do.call(pmin, resolutions)
  n_cells   <- .grid_size(candidate)$n_cells

  # ── auto-confirm for small grids ──────────────────────────────────
  if (n_cells < .RES_AUTO_CONFIRM_CELLS) {
    cli::cli_inform(str_c(
      "Target resolution: {(.fmt_res(candidate))}",
      "{sprintf(\" deg (~%.0f cells) - auto-confirmed.\", n_cells)}"
    ))
    return(.as_res(candidate))
  }

  # ── refuse for impossibly large grids ─────────────────────────────
  if (n_cells > .RES_MAX_CELLS) {
    .abort(str_c(
      "Auto-detected resolution {(.fmt_res(candidate))} would produce ",
      "~{format(n_cells, big.mark = \",\")} global cells, which is computationally ",
      "infeasible. Set `target_res` explicitly (e.g. target_res = 0.1)."
    ))
  }

  # ── non-interactive sessions cannot answer a prompt ────────────────
  if (!interactive()) {
    if (n_cells > .RES_PROMPT_CELLS) {
      fallback <- .RES_FALLBACK
      cli::cli_inform(str_c(
        "Non-interactive session: {(.fmt_res(candidate))} would need ",
        "~{format(n_cells, big.mark = \",\")} cells. Falling back to {fallback} deg. ",
        "Set `target_res` explicitly to override."
      ))
      return(fallback)
    }
    cli::cli_inform(str_c(
      "Non-interactive session: auto-confirming target resolution {(.fmt_res(candidate))} ",
      "(~{format(n_cells, big.mark = \",\")} cells). Set `target_res` explicitly to override."
    ))
    return(.as_res(candidate))
  }

  # ── prompt user ───────────────────────────────────────────────────
  .prompt_resolution(candidate, n_cells, conc_rast, pop_rast)
}

# Resolutions of the rasters that define the grid, keyed by input name; empty
# when the grid comes from a table instead.
.raster_resolutions <- function(conc_rast, pop_rast) {
  resolutions <- list()
  if (!is.null(conc_rast)) {
    resolutions$conc <- terra::res(conc_rast)
  }
  if (!is.null(pop_rast)) {
    resolutions$pop <- terra::res(pop_rast)
  }
  resolutions
}

# Size of the global grid a candidate resolution would produce. The Earth is
# treated as 360 x 180 degrees, which is how the thresholds above are
# calibrated; a resolution is `c(res_x, res_y)` when the axes differ.
.grid_size <- function(candidate) {
  n_lon   <- 360 / candidate[1]
  n_lat   <- 180 / candidate[2]
  list(n_lon = n_lon, n_lat = n_lat, n_cells = n_lon * n_lat)
}

# Ask the user which grid resolution to run on. Only reached in an interactive
# session. The menu goes to stdout with `cat()` rather than `message()` so that
# it is on screen before `readline()` reads the answer.
.prompt_resolution <- function(candidate, n_cells, conc_rast, pop_rast) {
  bar <- paste0(rep("-", 50), collapse = "")
  cat("\n", bar, "\n")
  cat("  Resolution selection\n")
  cat(bar, "\n")
  if (!is.null(conc_rast)) {
    cat(sprintf("  Exposure raster:      %s deg\n", .fmt_res(terra::res(conc_rast))))
  }
  if (!is.null(pop_rast)) {
    cat(sprintf("  Population raster:    %s deg\n", .fmt_res(terra::res(pop_rast))))
  }
  cat(sprintf("  Target (finest):      %s deg\n", .fmt_res(candidate)))
  cat(sprintf("  Est. global cells:    ~%.0f\n", n_cells))

  # ── a grid the machine can probably still handle: yes/no ───────────
  if (n_cells <= .RES_PROMPT_CELLS) {
    cat("  Proceed with this resolution? [y/n]: ")
    ans <- trimws(readline())
    if (tolower(ans) %in% c("y", "yes")) {
      return(.as_res(candidate))
    }
    .abort("Aborted by user. Set target_res explicitly to skip this prompt.")
  }

  # ── a grid this size is worth offering alternatives for ────────────
  suggestions <- .RES_SUGGESTIONS
  custom_idx  <- length(suggestions) + 1L
  proceed_idx <- length(suggestions) + 2L

  cat("\n  Suggested alternatives:\n")
  for (i in seq_along(suggestions)) {
    s  <- suggestions[i]
    sc <- (360 / s) * (180 / s)
    cat(sprintf("    [%d] %.2f deg  (~%.0f cells)\n", i, s, sc))
  }
  cat(sprintf("    [%d] Custom resolution\n", custom_idx))
  cat(sprintf("    [%d] Proceed anyway (may crash)\n", proceed_idx))
  cat(sprintf("\n  Enter choice [1-%d] or target_res value: ", proceed_idx))
  ans <- trimws(readline())

  if (ans %in% as.character(seq_along(suggestions))) {
    return(suggestions[as.integer(ans)])
  }
  if (ans == as.character(custom_idx)) {
    cat("  Enter custom resolution (degrees): ")
    custom <- as.numeric(readline())
    if (is.na(custom) || custom <= 0) {
      .abort("Invalid resolution.")
    }
    return(custom)
  }
  if (ans == as.character(proceed_idx)) {
    cli::cli_warn("Proceeding with very fine resolution - may crash or exhaust memory.")
    return(.as_res(candidate))
  }
  custom <- suppressWarnings(as.numeric(ans))
  if (!is.na(custom) && custom > 0) {
    return(custom)
  }
  .abort("Invalid selection: {ans}")
}
