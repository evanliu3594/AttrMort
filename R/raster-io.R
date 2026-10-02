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

  # round and coerce coordinates to character (matchable-compatible). A grid
  # finer than `dgt` can express loses cells right here: two distinct cell
  # centres render to one key, and the collapse only shows up much later. The
  # rendering and the report of it belong together, so both are in
  # `.render_cell_keys()`.
  keys   <- .render_cell_keys(grid$x, grid$y, dgt = dgt, res = terra::res(r))
  grid$x <- keys$x
  grid$y <- keys$y

  grid
}

# Decimals a coordinate vector needs so that its distinct values stay distinct
# as rendered keys. Searched upwards from the caller's `dgt` (never below it:
# that is the user's floor) and bounded, so a pathological vector cannot make
# the search unbounded.
.min_key_digits <- function(v, dgt, max_extra = 6L) {
  v <- unique(v)
  if (length(v) < 2L) {
    return(dgt)
  }
  for (d in seq.int(dgt, dgt + max_extra)) {
    if (anyDuplicated(matchable(v, dgt = d)) == 0L) {
      return(d)
    }
  }
  NA_integer_
}

# Render raster cell centres as matchable() keys, reporting a `dgt` too coarse
# to keep the grid's cells apart.
#
# Two distinct centres rendering to one key is not cosmetic: the grid skeleton
# loses a cell and the value table fans out on the duplicated key, so the run
# ends in a wrong total or a list-column result, far from the cause. The tabular
# path reports the same condition in `.normalise_coord_keys()`, but a raster
# reaches that check with its keys already rendered as character and is skipped,
# so the test has to live where the rendering does.
#
# An axis is tested before the cells: rounding merges two cells only by merging
# their centres, so one collapsed axis is enough to know the grid collapsed --
# and a global 0.1 deg raster has 3600 + 1300 centres against 4.68e6 cells, so
# the cheap test is the one that runs on every ingest. The cell-level count is
# computed only once the axis test fires.
.render_cell_keys <- function(x, y, dgt, res = NULL) {
  raw    <- list(x = x, y = y)
  keys   <- map(raw, matchable, dgt = dgt)
  needed <- map_int(raw, .min_key_digits, dgt = dgt)

  if (!any(is.na(needed) | needed > dgt)) {
    return(keys)
  }

  n_cells <- length(x)
  n_keys  <- length(unique(paste(keys$x, keys$y, sep = "\r")))
  axis_txt <- paste0(
    map_chr(names(raw), function(nm) {
      sprintf("%s: %d centre(s) -> %d key(s)",
              nm, length(unique(raw[[nm]])), length(unique(keys[[nm]])))
    }),
    collapse = "; "
  )
  res_txt <- if (is.null(res)) "" else paste0(" on a ", .fmt_res(res), " deg grid")
  fix_dgt <- suppressWarnings(
    min(needed[is.na(needed) | needed > dgt], na.rm = TRUE)
  )
  fix <- if (is.finite(fix_dgt)) {
    paste0("Set `dgt_coord = ", fix_dgt, "` to keep this grid apart.")
  } else {
    "Even six more decimals do not separate the cell centres."
  }

  cli::cli_warn(str_c(
    "Rounding cell centres to `dgt = {dgt}` decimal place(s) merges raster cells",
    "{res_txt}: {format(n_cells, big.mark = \",\")} cell(s) collapse into ",
    "{format(n_keys, big.mark = \",\")} coordinate key(s) ({axis_txt}). The ",
    "analysis grid would lose {format(n_cells - n_keys, big.mark = \",\")} cell(s) ",
    "and the value table would fan out on the duplicated key, which surfaces as a ",
    "wrong total or a list-column result rather than as an error here. {fix}"
  ))

  keys
}

# Negative values in a table a raster was ingested into.
#
# Concentrations and populations are non-negative quantities, and terra maps a
# *declared* missing-value flag (`_FillValue`, `missing_value`, `NAflag`) to NA
# while reading, so a negative number that reaches this point was never declared
# missing. Gridded products routinely spell no-data as -999 without declaring
# it, and `raster_to_grid()` keeps every non-NA cell, so those values enter the
# analysis table as if they were measurements.
#
# The report is diagnostic only. Nothing is dropped, rescaled or converted to
# NA, because making a sentinel mean "missing" is a data-contract decision: it
# decides which cells the analysis covers and what every total means. The
# caller passes `quiet = TRUE` for `validate = "off"`, the documented silence
# mode.
#
# Returns its counts invisibly, so a test can assert on the numbers instead of
# on the wording.
.report_raster_fill <- function(data, label, quiet = FALSE) {
  if (!is.data.frame(data) || nrow(data) == 0L) {
    return(invisible(NULL))
  }
  value_cols <- setdiff(names(data), c("x", "y"))
  if (length(value_cols) == 0L) {
    return(invisible(NULL))
  }

  vals   <- suppressWarnings(as.numeric(unlist(data[value_cols], use.names = FALSE)))
  neg    <- vals[!is.na(vals) & vals < 0]
  report <- list(label = label, n_value = length(vals), n_neg = length(neg),
                 n_cells = nrow(data))
  if (length(neg) == 0L) {
    return(invisible(report))
  }

  counts <- sort(table(round(neg, 6L)), decreasing = TRUE)
  top    <- utils::head(counts, 3L)
  top_txt <- paste0(
    sprintf("%s x %s",
            format(as.numeric(names(top)), trim = TRUE, scientific = FALSE),
            format(as.integer(top), big.mark = ",")),
    collapse = ", "
  )
  report$top <- top

  if (!quiet) {
    cli::cli_warn(str_c(
      "`{label}`: {format(length(neg), big.mark = \",\")} of ",
      "{format(length(vals), big.mark = \",\")} raster value(s) are negative ",
      "(most frequent: {top_txt}). A raster reader maps a declared missing-value ",
      "flag to NA, so these were not declared missing: they are data errors or an ",
      "undeclared fill/no-data sentinel. Nothing is dropped, rescaled or converted ",
      "to NA here, and the values enter the analysis as they are. If this is a fill ",
      "code, declare it in the file (`_FillValue` / `missing_value` / `NAflag`) or ",
      "set it to NA before running: the package does not clean sentinels for you."
    ))
  }

  invisible(report)
}

# Aggregate a count raster onto a coarser template without losing totals.
#
# terra::resample(method = "sum") is not a conservative aggregation, so when
# the target resolution is an exact multiple of the source resolution we
# aggregate first (which conserves the sum) and only then resample onto the
# template grid. Totals before and after are compared, and a warning is
# issued when more than `tol` of the total is lost.
#
# Only the part of the source the output actually covers is read: aggregating
# the globe to serve one country reads 9.33e8 cells for a 6699-cell window
# (16 s measured on the shipped LandScan and 0.1 deg Lao template). The crop is
# taken on whole aggregation blocks, so the blocks -- and therefore every
# output value -- are the ones the uncropped path would produce.
.aggregate_pop <- function(r, template, tol = 0.001) {
  res_r <- terra::res(r)
  res_t <- terra::res(template)
  fact  <- res_t / res_r

  # ── which alignment the source and the target are in ────────────────
  # The three cases of the old flow, named once: an exact multiple goes
  # through terra::aggregate(), a finer target is split between the sub-cells,
  # and anything else can only be resampled.
  mode <- if (all(fact >= 1 - 1e-6) && all(abs(fact - round(fact)) < 1e-6)) {
    "aggregate"
  } else if (all(fact < 1 - 1e-6)) {
    "disaggregate"
  } else {
    "plain"
  }

  # The block size the crop has to respect: the aggregation block where there
  # is one, a whole source cell otherwise. Both `terra::aggregate()` and
  # `terra::disagg()` start from the raster origin, so a window that is a whole
  # number of blocks away from it leaves the alignment untouched.
  step <- if (identical(mode, "aggregate")) res_r * round(fact) else res_r

  # ── the part of the source the output covers ────────────────────────
  # NULL when the template reaches outside the source, in which case nothing is
  # cropped and there is no like-for-like total to compare against.
  win   <- .pop_window(r, template, step)
  r_src <- .pop_crop(r, win, template)

  # ── the total the output has to preserve ────────────────────────────
  # It is the source's total over the footprint the output *has*, not over the
  # (deliberately larger) window that was read and certainly not the source
  # overall: a windowed output can never hold the globe, so comparing the two
  # reports the window as a loss (the shipped LandScan summed to 7,981,969,726
  # globally against 90,758,858 for a Lao window, reported as "changed the
  # total by 98.8630%" although the transfer was exact to 0.000000% against a
  # hand-computed area-weighted reference). `NULL` means the footprint cannot be
  # isolated -- the template reaches outside the source, or its edges do not sit
  # on the source lattice -- and two different footprints are not comparable.
  total_before <- .pop_footprint(r, template)
  total_before <- if (is.null(total_before)) {
    NULL
  } else {
    terra::global(total_before, fun = "sum", na.rm = TRUE)[[1]]
  }

  out <- if (identical(mode, "aggregate")) {
    # terra::aggregate() takes the factor as (rows, columns); `fact` is
    # (x, y), so the two axes are reversed here. They may need different
    # factors on a non-square target grid. A factor of one means nothing to
    # aggregate, and terra would warn about the no-op.
    agg <- if (any(round(fact) > 1L)) {
      terra::aggregate(r_src, fact = rev(round(fact)), fun = "sum", na.rm = TRUE)
    } else {
      r_src
    }
    terra::resample(agg, template, method = "sum")
  } else if (identical(mode, "disaggregate")) {
    # Target is finer: a population count has to be *divided* between the finer
    # cells, not interpolated. Bilinear hands every sub-cell the source value,
    # which multiplies the total by the subdivision factor (2x2 deg holding 100
    # people becomes four 1x1 deg cells holding 100 each).
    n    <- ceiling(1 / fact)
    fine <- terra::disagg(r_src, fact = rev(n), method = "near") / prod(n)
    terra::resample(fine, template, method = "sum")
  } else {
    cli::cli_warn(str_c(
      "Population raster resolution ({paste(round(res_r, 6), collapse = \" x \")}) is not ",
      "an exact multiple of the target ({paste(round(res_t, 6), collapse = \" x \")}); ",
      "falling back to plain resampling, which may not preserve totals."
    ))
    terra::resample(r_src, template, method = "sum")
  }

  # One number per layer: a multi-band source reports the layer that moved most,
  # where a scalar comparison would have stopped with "length = 2" in coercion.
  total_after <- terra::global(out, fun = "sum", na.rm = TRUE)[[1]]
  if (!is.null(total_before) && length(total_before) == length(total_after)) {
    usable <- is.finite(total_before) & is.finite(total_after) & total_before != 0
    if (any(usable)) {
      lost <- abs(total_after[usable] - total_before[usable]) /
        abs(total_before[usable])
      if (max(lost) > tol) {
        idx    <- which(usable)[which.max(lost)]
        layer  <- if (length(total_before) > 1L) sprintf(" (layer %d)", idx) else ""
        cli::cli_warn(str_c(
          "Aggregating the population raster changed the total by ",
          "{sprintf(\"%.4f%%\", 100 * max(lost))}{layer} ",
          "({format(total_before[idx], big.mark = \",\")} -> ",
          "{format(total_after[idx], big.mark = \",\")})."
        ))
      }
    }
  }
  out
}

# The source restricted to the footprint the output covers: the cells the
# template's own edges fall on, kept only when those edges *are* cell
# boundaries. When an edge falls between two cells the footprint cannot be
# isolated, and comparing the source's total against the output's would be the
# old mistake in miniature -- two different areas. The tolerance is a thousandth
# of a source cell, which is where the float round-trips through terra live, not
# where a real offset lives.
#
# Like `.pop_crop()` the extent is shrunk by a thousandth of a cell before the
# snap, for the same reason: `terra::crop()` expands to the next cell boundary,
# and without the shrink a template a billionth of a degree off the lattice
# would come back one whole cell wider and no longer be the footprint it claims
# to be.
#
# Returns NULL when the template reaches outside the source, or when one of its
# edges falls between two source cells.
.pop_footprint <- function(r, template, tol_cell = 1e-3) {
  res_r <- terra::res(r)
  e_r   <- as.vector(terra::ext(r))
  e_t   <- as.vector(terra::ext(template))

  tol <- tol_cell * res_r
  covered <- e_t[1] >= e_r[1] - tol[1] && e_t[2] <= e_r[2] + tol[1] &&
    e_t[3] >= e_r[3] - tol[2] && e_t[4] <= e_r[4] + tol[2]
  if (!covered) {
    return(NULL)
  }

  pad <- res_r / 1000
  cut <- terra::crop(r,
                     terra::ext(e_t[1] + pad[1], e_t[2] - pad[1],
                                e_t[3] + pad[2], e_t[4] - pad[2]),
                     snap = "out")
  e_c <- as.vector(terra::ext(cut))
  if (any(abs(e_c - e_t) > tol[c(1, 1, 2, 2)])) {
    return(NULL)
  }
  cut
}

# The window of `r` that covers `template`, rounded outwards to whole `step`
# blocks. `step` is the block size in degrees (`c(res_x, res_y)`), so the window
# starts and ends on the lattice the aggregation and the disaggregation are
# aligned to.
#
# Rounding is outwards, never inwards: the window has to contain the template,
# because `terra::resample()` reads every source cell that overlaps a target
# cell and a missing sliver at the edge would change the edge values. A window
# one block larger than needed costs a little reading and changes nothing.
#
# The window is a range of *cell indices*, never a pair of coordinates.
# `res()` is routinely a hair off the nominal cell size -- the shipped LandScan
# reports 0.0083333333329999992 -- and `terra::crop()` snaps an extent outwards
# to the next cell boundary, so a window computed in degrees lands a billionth
# of a degree below a boundary, comes back one whole cell wider, and moves every
# aggregation block with it. Measured on the Lao window: 88 of 6699 cells
# differed from the uncropped path that way. `r[rows, cols]` has no such
# round-trip: the subset keeps the source's own lattice.
#
# Returns NULL when the template reaches outside the source: then there is no
# window that both covers the template and stays inside the source, and the
# caller has to keep reading the whole raster.
.pop_window <- function(r, template, step) {
  res_r <- terra::res(r)
  e_r   <- as.vector(terra::ext(r))
  e_t   <- as.vector(terra::ext(template))

  # `ext()` returns (xmin, xmax, ymin, ymax); the tolerance absorbs the
  # round-trip through terra's cell-centre arithmetic.
  tol <- 1e-3 * res_r
  covered <- e_t[1] >= e_r[1] - tol[1] && e_t[2] <= e_r[2] + tol[1] &&
    e_t[3] >= e_r[3] - tol[2] && e_t[4] <= e_r[4] + tol[2]
  if (!covered) {
    return(NULL)
  }

  # whole source cells per block; a block size below one cell is one cell
  block <- pmax(1, round(step / res_r))

  # The enclosing block, in cell indices. Rows are numbered from the top, so the
  # y side counts down from ymax; the boundaries themselves are degrees, and
  # `.pop_crop()` is what keeps them on terra's lattice.
  col0 <- max(1L, floor((e_t[1] - e_r[1]) / (res_r[1] * block[1])) * block[1] + 1)
  col1 <- min(terra::ncol(r),
              ceiling((e_t[2] - e_r[1]) / (res_r[1] * block[1])) * block[1])
  row0 <- max(1L, floor((e_r[4] - e_t[4]) / (res_r[2] * block[2])) * block[2] + 1)
  row1 <- min(terra::nrow(r),
              ceiling((e_r[4] - e_t[3]) / (res_r[2] * block[2])) * block[2])

  lower <- e_r[1] + (col0 - 1) * res_r[1]
  upper <- e_r[1] + col1 * res_r[1]
  right <- e_r[4] - (row0 - 1) * res_r[2]
  left  <- e_r[4] - row1 * res_r[2]
  terra::ext(lower, upper, left, right)
}

# The window as a raster.
#
# `terra::crop()` snaps an extent outwards to the next cell boundary, and a
# window's coordinates are only ever as exact as the degree arithmetic that
# produced them (the shipped LandScan reports `res()` as 0.0083333333329999992).
# A window that is nominally block-aligned therefore comes back one whole cell
# wider -- with every aggregation block moved along with it, which changes values
# in the last digits (measured on the Lao window: 88 of 6699 cells differed from
# the uncropped path). Shrinking the request by a thousandth of a cell makes the
# snap land on the boundary the window meant rather than on the one next to it.
#
# The result is checked against the template: if the shrink ever cut into it, the
# caller reads the whole raster rather than a window that is too small.
.pop_crop <- function(r, window, template) {
  if (is.null(window)) {
    return(r)
  }
  pad <- terra::res(r) / 1000
  cut <- terra::crop(r,
                     terra::ext(window[1] + pad[1], window[2] - pad[1],
                                window[3] + pad[2], window[4] - pad[2]),
                     snap = "out")

  e_c <- as.vector(terra::ext(cut))
  e_t <- as.vector(terra::ext(template))
  if (e_c[1] > e_t[1] || e_c[2] < e_t[2] || e_c[3] > e_t[3] || e_c[4] < e_t[4]) {
    return(r)
  }
  cut
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

    # reproject to WGS84 if needed. The comparison is left to terra: the CRS
    # strings of "EPSG:4326" and "OGC:CRS84" differ while the grids are the
    # same, and a string comparison projected the whole raster for nothing
    # (measured: bit-identical values, one "Reprojecting ..." warning, and the
    # warp's cost). A CRS that really does need the warp still gets it, and
    # still gets the warning.
    if (!is.na(terra::crs(r)) && !terra::same.crs(r, template)) {
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
