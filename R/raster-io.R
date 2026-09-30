# ── Geospatial ingestion layer ─────────────────────────────────

#' Convert a raster to a grid data.frame
#'
#' Reads a single or multi-band GeoTIFF (or any raster format supported by
#' terra), extracts cell coordinates and values, and returns a data.frame
#' suitable for joining with other inputs in the Mortality() pipeline.
#'
#' @param path Character. Path to a raster file (GeoTIFF or other
#'   terra-supported format).
#' @param band_names Character vector. Names for each band. If NULL, band
#'   names are taken from the file metadata; if metadata is empty, defaults
#'   to "band_1", "band_2", ...
#' @param dgt Integer. Number of decimal places for coordinate rounding.
#'   Must match the target grid resolution (e.g. dgt = 1 for 0.1 deg grids).
#'   Coordinates are returned as character strings for matchable()-style
#'   joins.
#'
#' @return A data.frame with columns \code{x}, \code{y} (character) and one
#'   column per raster band (numeric).
#'
#' @noRd
#' @examples
#' \dontrun{
#'   grid_df <- raster_to_grid("path/to/pm25.tif", dgt = 1)
#' }
raster_to_grid <- function(path, band_names = NULL, dgt = 1) {
  # Accept a SpatRaster as well as a path: terra::rast() on an existing
  # SpatRaster would return an empty *template* rather than the data.
  r <- if (inherits(path, "SpatRaster")) path else terra::rast(path)
  n_lyr <- terra::nlyr(r)

  # detect band names: file metadata first, then band_1, band_2, ...
  if (is.null(band_names)) {
    nm <- names(r)
    default_names <- length(nm) != n_lyr || all(nm == "") ||
      all(grepl("^lyr\\.?[0-9]*$", nm))
    band_names <- if (default_names) paste0("band_", seq_len(n_lyr)) else nm
  }

  if (length(band_names) != n_lyr) {
    stop(
      "band_names length (", length(band_names),
      ") does not match number of raster layers (", n_lyr, ").",
      call. = FALSE
    )
  }

  # convert to data.frame
  df <- terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)

  # rename value columns
  value_cols <- setdiff(names(df), c("x", "y"))
  names(df)[names(df) %in% value_cols] <- band_names

  # round and coerce coordinates to character (matchable-compatible)
  df$x <- matchable(df$x, dgt = dgt)
  df$y <- matchable(df$y, dgt = dgt)

  return(df)
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

  if (all(fact >= 1 - 1e-6) && all(abs(fact - round(fact)) < 1e-6) &&
      length(unique(round(fact))) == 1L) {
    agg <- terra::aggregate(r, fact = round(fact[1]), fun = "sum", na.rm = TRUE)
    out <- terra::resample(agg, template, method = "sum")
  } else if (all(fact < 1 - 1e-6)) {
    # Target is finer than the source: nothing to conserve, interpolate.
    out <- terra::resample(r, template, method = "bilinear")
  } else {
    warning(
      "Population raster resolution (", paste(round(res_r, 6), collapse = " x "),
      ") is not an exact multiple of the target (",
      paste(round(res_t, 6), collapse = " x "),
      "); falling back to plain resampling, which may not preserve totals.",
      call. = FALSE
    )
    out <- terra::resample(r, template, method = "sum")
  }

  total_after <- terra::global(out, fun = "sum", na.rm = TRUE)[[1]]
  if (is.finite(total_before) && is.finite(total_after) && total_before != 0) {
    lost <- abs(total_after - total_before) / abs(total_before)
    if (lost > tol) {
      warning(
        "Aggregating the population raster changed the total by ",
        sprintf("%.4f%%", 100 * lost), " (",
        format(total_before, big.mark = ","), " -> ",
        format(total_after, big.mark = ","), ").",
        call. = FALSE
      )
    }
  }
  out
}

#' Align multiple rasters to a common target grid
#'
#' Resamples or aggregates a list of SpatRaster objects so they all share
#' the same resolution, extent, and CRS - a prerequisite for pixel-level
#' joins in the Mortality() pipeline.
#'
#' @param raster_list Named list of SpatRaster objects.
#' @param target_res Numeric. Target resolution in degrees (e.g. 0.1).
#'   If NULL, determined from \code{target_raster} or auto-detected.
#' @param target_raster SpatRaster to use as the template grid.
#'   Overrides \code{target_res}.
#' @param pop_names Character vector. Names (in \code{raster_list}) of
#'   population rasters - these are aggregated by \strong{sum} to preserve
#'   total counts.
#' @param conc_names Character vector. Names of concentration/exposure
#'   rasters - these are resampled by bilinear interpolation.
#'
#' @details
#' If both \code{target_res} and \code{target_raster} are NULL, the coarsest
#' raster in \code{raster_list} is used as the reference. When \code{pop_names}
#' and \code{conc_names} are both NULL, the function guesses raster type from
#' names: those matching \code{"pop"} are summed; all others are bilinear.
#'
#' @return A named list of SpatRaster objects, all with identical resolution,
#'   extent, and CRS (WGS84 / EPSG:4326).
#'
#' @noRd
#' @examples
#' \dontrun{
#'   rasters <- list(
#'     conc = terra::rast("pm25.tif"),
#'     pop  = terra::rast("population.tif")
#'   )
#'   aligned <- align_to_target(rasters, pop_names = "pop")
#' }
align_to_target <- function(raster_list,
                             target_res    = NULL,
                             target_raster = NULL,
                             pop_names     = NULL,
                             conc_names    = NULL) {

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
    resolutions <- vapply(raster_list, function(r) mean(terra::res(r)), numeric(1))
    coarsest    <- which.max(resolutions)
    template    <- raster_list[[coarsest]]
    message(
      "Auto-detected target resolution: ", round(mean(terra::res(template)), 4),
      " deg (from raster '", names(raster_list)[coarsest], "')"
    )
  }

  # ---- classify raster types if not provided -----------------------------
  if (is.null(pop_names) && is.null(conc_names)) {
    all_names <- tolower(names(raster_list))
    pop_names  <- names(raster_list)[grepl("pop", all_names)]
    conc_names <- setdiff(names(raster_list), pop_names)
  } else if (is.null(pop_names)) {
    pop_names <- character(0)
  } else if (is.null(conc_names)) {
    conc_names <- setdiff(names(raster_list), pop_names)
  }

  # ---- align each raster -------------------------------------------------
  aligned <- lapply(names(raster_list), function(nm) {
    r <- raster_list[[nm]]

    # reproject to WGS84 if needed
    if (!is.na(terra::crs(r)) && terra::crs(r) != terra::crs(template)) {
      warning("Reprojecting '", nm, "' to EPSG:4326.", call. = FALSE)
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
  return(aligned)
}

#' Rasterize an administrative boundary shapefile
#'
#' Converts a polygon shapefile (country, province, etc.) to a grid
#' data.frame matching the coordinate system and resolution of a template
#' raster. Each pixel gets the value of the admin unit it falls in.
#'
#' @param shp_path Character path to a shapefile (.shp), an \code{sf} object,
#'   or \code{NULL}. If \code{NULL}, world country boundaries are downloaded
#'   automatically via \code{rnaturalearth::ne_countries()}.
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
#' @examples
#' \dontrun{
#'   template <- terra::rast("pm25.tif")
#'   admin_df <- shapefile_to_grid(NULL, template, admin_col = "admin")
#' }
shapefile_to_grid <- function(shp_path        = NULL,
                               template_raster,
                               admin_col       = "admin",
                               dgt             = 1) {

  # ---- load shapefile ----------------------------------------------------
  if (is.null(shp_path)) {
    if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
      stop(
        "Package 'rnaturalearth' is required for automatic world boundaries. ",
        "Install it with: install.packages('rnaturalearth')"
      )
    }
    shp <- rnaturalearth::ne_countries(scale = 110, returnclass = "sf")
  } else if (inherits(shp_path, "sf")) {
    shp <- shp_path
  } else if (is.character(shp_path)) {
    shp <- sf::st_read(shp_path, quiet = TRUE)
  } else {
    stop("shp_path must be a file path, an sf object, or NULL.")
  }

  # ---- resolve admin column ----------------------------------------------
  if (!admin_col %in% names(shp)) {
    char_cols <- names(shp)[vapply(shp, is.character, logical(1))]
    char_cols <- setdiff(char_cols, "geometry")
    if (length(char_cols) > 0) {
      warning(
        "admin_col '", admin_col, "' not found in shapefile. ",
        "Using '", char_cols[1], "' instead."
      )
      admin_col <- char_cols[1]
    } else {
      stop("No character columns found in shapefile attributes.")
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
  df <- terra::as.data.frame(admin_raster, xy = TRUE, na.rm = TRUE)
  names(df)[names(df) == admin_col] <- admin_col

  df$x <- matchable(df$x, dgt = dgt)
  df$y <- matchable(df$y, dgt = dgt)

  return(df)
}


# ── Resolution selection and interactive confirmation ──────────

#' Resolve target resolution for spatial alignment
#'
#' When multiple rasters at different resolutions are provided, determines
#' the output grid resolution. If \code{target_res} is provided it is used
#' directly. If \code{NULL}, the finest input resolution is auto-detected
#' and the user is prompted to confirm based on estimated cell counts.
#'
#' @param conc_rast SpatRaster or NULL. The concentration/exposure raster.
#' @param pop_rast SpatRaster or NULL. The population raster.
#' @param target_res Numeric or NULL. Explicit target resolution in degrees.
#'
#' @return Numeric. The confirmed target resolution in degrees.
#' @noRd
.resolve_target_res <- function(conc_rast, pop_rast, target_res) {
  if (!is.null(target_res)) {
    message("Using specified target resolution: ", target_res, " deg")
    if (target_res <= 0) stop("target_res must be positive.")
    return(target_res)
  }

  resolutions <- numeric(0)
  if (!is.null(conc_rast)) resolutions <- c(resolutions, mean(terra::res(conc_rast)))
  if (!is.null(pop_rast))  resolutions <- c(resolutions, mean(terra::res(pop_rast)))

  if (length(resolutions) == 0) return(NULL)

  candidate    <- min(resolutions)
  n_lon        <- 360 / candidate
  n_lat        <- 180 / candidate
  n_cells      <- n_lon * n_lat

  message("Detected raster resolutions: ",
          paste(sprintf("%.5f deg", resolutions), collapse = ", "))

  # ── auto-confirm for small grids ──────────────────────────────────
  if (n_cells < 5e6) {
    message(sprintf("Target resolution: %.5f deg (~%.0f cells) - auto-confirmed.",
                    candidate, n_cells))
    return(candidate)
  }

  # ── refuse for impossibly large grids ─────────────────────────────
  if (n_cells > 1e9) {
    stop(
      "Auto-detected resolution ", sprintf("%.5f", candidate),
      " would produce ~", format(n_cells, big.mark = ","),
      " global cells, which is computationally infeasible. ",
      "Set `target_res` explicitly (e.g. target_res = 0.1).",
      call. = FALSE
    )
  }

  # ── non-interactive sessions cannot answer a prompt ────────────────
  if (!interactive()) {
    if (n_cells > 5e7) {
      fallback <- 0.1
      message(
        "Non-interactive session: ", sprintf("%.5f deg", candidate),
        " would need ~", format(n_cells, big.mark = ","),
        " cells. Falling back to ", fallback, " deg. ",
        "Set `target_res` explicitly to override."
      )
      return(fallback)
    }
    message(
      "Non-interactive session: auto-confirming target resolution ",
      sprintf("%.5f deg", candidate), " (~", format(n_cells, big.mark = ","),
      " cells). Set `target_res` explicitly to override."
    )
    return(candidate)
  }

  # ── prompt user ───────────────────────────────────────────────────
  cat("\n", paste0(rep("-", 50), collapse = ""), "\n")
  cat("  Resolution selection\n")
  cat(paste0(rep("-", 50), collapse = ""), "\n")
  if (!is.null(conc_rast))
    cat(sprintf("  Exposure raster:      %.5f deg\n", mean(terra::res(conc_rast))))
  if (!is.null(pop_rast))
    cat(sprintf("  Population raster:    %.5f deg\n", mean(terra::res(pop_rast))))
  cat(sprintf("  Target (finest):      %.5f deg\n", candidate))
  cat(sprintf("  Est. global cells:    ~%.0f\n", n_cells))

  if (n_cells > 5e7) {
    suggestions <- c(0.1, 0.05, 0.01)
    cat("\n  Suggested alternatives:\n")
    for (i in seq_along(suggestions)) {
      s  <- suggestions[i]
      sc <- (360 / s) * (180 / s)
      cat(sprintf("    [%d] %.2f deg  (~%.0f cells)\n", i, s, sc))
    }
    cat("    [4] Custom resolution\n")
    cat("    [5] Proceed anyway (may crash)\n")
    cat("\n  Enter choice [1-5] or target_res value: ")
    ans <- trimws(readline())

    if (ans == "1") return(suggestions[1])
    if (ans == "2") return(suggestions[2])
    if (ans == "3") return(suggestions[3])
    if (ans == "4") {
      cat("  Enter custom resolution (degrees): ")
      custom <- as.numeric(readline())
      if (is.na(custom) || custom <= 0) stop("Invalid resolution.")
      return(custom)
    }
    if (ans == "5") {
      warning("Proceeding with very fine resolution - may crash or exhaust memory.")
      return(candidate)
    }
    custom <- suppressWarnings(as.numeric(ans))
    if (!is.na(custom) && custom > 0) return(custom)
    stop("Invalid selection: ", ans)
  } else {
    cat("  Proceed with this resolution? [y/n]: ")
    ans <- trimws(readline())
    if (tolower(ans) %in% c("y", "yes")) return(candidate)
    stop("Aborted by user. Set target_res explicitly to skip this prompt.")
  }
}
