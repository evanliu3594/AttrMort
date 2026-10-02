# ── Input ingestion ─────────────────────────────────────────────────────
#
# The format and raster layer: file readers, column mapping, spatial alignment
# and boundary rasterization. `prepare-inputs.R` orchestrates these into the
# front end both entry points share; `grid-info.R` and `domain-summary.R` call
# them directly. Nothing here knows about the calculation.

# Every character input must name an existing file. Checked up front so the
# user gets a precise message instead of whatever terra/readxl reports.
.check_input_files <- function(...) {
  inputs <- list(...)
  for (nm in names(inputs)) {
    x <- inputs[[nm]]
    if (is.character(x) && length(x) == 1 && !file.exists(x)) {
      .abort("File not found: {x} (input `{nm}`)")
    }
  }
  invisible(TRUE)
}

# Ingest one input: data.frame passes through; a character path is loaded
# according to its extension. Raster paths are handled by the caller
# (.align_raster_inputs) so that they can be aligned first.
.ingest_single_input <- function(x, dgt_coord = 2) {
  if (is.data.frame(x)) {
    return(x)
  }
  if (!is.character(x)) {
    .abort(str_c(
      "Each data input must be a data.frame or a file path (character). ",
      "Got: {paste(class(x), collapse = \"/\")}."
    ))
  }
  if (length(x) != 1) {
    .abort("A file path must be a single character string.")
  }
  if (!file.exists(x)) {
    .abort("File not found: {x}")
  }

  ext <- tolower(file_ext(x))
  switch(ext,
    tif  = ,
    tiff = ,
    nc   = ,
    nc4  = ,
    grd  = ,
    asc  = ,
    img  = ,
    vrt  = ,
    bil  = ,
    hdf  = raster_to_grid(x, dgt = dgt_coord),
    csv  = read_csv(x, show_col_types = FALSE),
    xls  = ,
    xlsx = read_excel(x),
    txt  = read_csv(x, show_col_types = FALSE),
    .abort(str_c(
      "Unsupported file format: .{ext}. Supported rasters: ",
      ".tif .tiff .nc .grd .asc .img .vrt .bil .hdf; tables: .csv .txt .xls .xlsx."
    ))
  )
}

# Render numeric coordinate columns as character keys, as the data contract
# requires. Raster input already arrives as character keys; tabular input often
# carries plain numbers, and mixing the two would break the join. When
# `dgt_coord` is too coarse to keep the coordinates distinct the column is left
# numeric, with a warning, rather than silently collapsing grid cells.
.normalise_coord_keys <- function(data, dgt_coord) {
  # One grid, one spelling: `lon`/`lat` and `longitude`/`latitude` are the same
  # key as `x`/`y`, and two inputs that spell it differently would share no key
  # at all in the joins downstream. Renaming here is what makes `x = lon` and
  # `y = lat` work end to end.
  aliases <- vapply(names(data), .coord_alias, character(1))
  move    <- !is.na(aliases) & aliases != names(data)
  if (any(move) && !anyDuplicated(aliases[!is.na(aliases)])) {
    old <- names(data)[move]
    names(data)[move] <- aliases[move]
    cli::cli_inform(str_c(
      "Coordinate columns renamed: ",
      "{paste(old, aliases[move], sep = \" -> \", collapse = \", \")}"
    ))
  }

  for (col in intersect(.COORD_VARIANTS, names(data))) {
    v <- data[[col]]
    if (!is.numeric(v)) {
      next
    }
    key <- matchable(v, dgt = dgt_coord)
    if (length(unique(key)) == length(unique(v))) {
      data[[col]] <- key
    } else {
      cli::cli_warn(str_c(
        "Coordinate column `{col}` needs more decimals than ",
        "`dgt_coord = {dgt_coord}` to stay unique; keeping it numeric.",
        "Set `dgt_coord` to match the grid resolution."
      ))
    }
  }
  data
}

# Ingest an input, rename its columns to the canonical schema, and render its
# numeric coordinate keys as strings.
.ingest_and_map <- function(x, schema, dgt_coord = 2, label = NULL) {
  data <- .ingest_single_input(x, dgt_coord)

  mapping <- detect_columns(df, schema = schema, quiet = TRUE)
  if (length(mapping) > 0) {
    # detect_columns() returns c(semantic = "<actual column>"); the pipeline
    # expects the canonical names (.COLUMN_TARGET), so rename actual ->
    # canonical. A rename is skipped when it would duplicate a canonical column
    # that already exists under a different name: the existing column wins.
    target <- .COLUMN_TARGET[names(mapping)]
    keep   <- !is.na(target) &
      (target == unname(mapping) | !target %in% names(data))
    mapping <- mapping[keep]
    target  <- .COLUMN_TARGET[names(mapping)]

    if (length(mapping) > 0) {
      renamed <- set_names(unname(mapping), target)
      changed <- renamed[names(renamed) != renamed]
      if (length(changed) > 0) {
        # Interpolated as a value: a column name may contain braces, and glue
        # does not re-parse what a `{...}` expression returns.
        mapping_txt <- paste0(
          if (is.null(label)) "Column mapping: " else paste0("`", label, "`: "),
          paste(sprintf("%s -> %s", changed, names(changed)), collapse = ", ")
        )
        cli::cli_inform("{mapping_txt}")
      }
      data <- data |> rename(!!!renamed)
    }
  }

  .normalise_coord_keys(data, dgt_coord)
}

# Raster formats terra can open directly. Detection decides whether an input
# goes through the spatial alignment layer, so this must cover gridded
# exposure products in the wild: GeoTIFF, netCDF (CMIP / GEOS-Chem / CMAQ),
# ESRI and ASCII grids.
.RASTER_EXTS <- c("tif", "tiff", "nc", "nc4", "grd", "asc", "img", "vrt",
                  "bil", "hdf")

# TRUE for a character path pointing at a raster file.
.is_raster_path <- function(x) {
  is.character(x) && length(x) == 1 &&
    tolower(file_ext(x)) %in% .RASTER_EXTS
}

# TRUE for a raster input in either accepted form: a path terra can open, or
# an in-memory SpatRaster.
.is_raster_input <- function(x) {
  inherits(x, "SpatRaster") || .is_raster_path(x)
}

# A spatial vector layer: polygons that label the grid, not a table of cells.
# Accepted wherever boundaries are expected, including as `calc_fild`, which
# is how a map can stand in for the attribution field of a raster run.
.VECTOR_EXTS <- c("shp", "gpkg", "geojson", "json", "kml", "gml",
                  "sqlite", "tab")

.is_vector_map <- function(x) {
  inherits(x, "sf") ||
    (is.character(x) && length(x) == 1 && !is.na(x) &&
       tolower(file_ext(x)) %in% .VECTOR_EXTS)
}
# Open a raster input without losing an in-memory object: terra::rast() on a
# SpatRaster returns an empty *template*, not the data.
.as_spatraster <- function(x) {
  if (inherits(x, "SpatRaster")) x else terra::rast(x)
}

# A raster-derived grid has one value column per band. When exactly one band is
# present it carries the whole field, so the column is named after the scenario
# when one was requested, and after the canonical `what` (`conc` / `pop`)
# otherwise. A single band with a meaningful name is left alone as soon as a
# scenario was named, so a mismatch surfaces as a missing column rather than as
# silently mislabelled data.
.rename_single_band <- function(data, scenario, what) {
  if (is.null(data)) {
    return(NULL)
  }
  val_cols <- setdiff(names(data), c("x", "y"))
  if (length(val_cols) != 1) {
    return(data)
  }
  if (!is.null(scenario) && !str_detect(val_cols[1], "^band")) {
    return(data)
  }
  target <- if (is.null(scenario)) what else scenario
  if (identical(val_cols[1], target)) {
    return(data)
  }
  names(data)[names(data) == val_cols[1]] <- target
  cli::cli_inform("Single-band {what} raster renamed: {val_cols[1]} -> {target}")
  data
}

# Detect raster inputs, align them all onto one grid, and return plain
# data.frames plus the aligned template raster (used later for admin
# rasterization). Non-raster inputs are returned untouched.
#
# `template` is an already-fixed grid to align onto instead of resolving one
# from `target_res`: `decompose()` prepares its second group that way, so both
# groups are read onto the same lattice even when their rasters do not share an
# extent, and a mismatch shows up as missing join keys rather than as a
# silently narrowed grid.
.align_raster_inputs <- function(conc_real, pop_total, conc_cf, scenario,
                                 target_res, dgt_coord, template = NULL) {
  out <- list(conc_real = conc_real, pop_total = pop_total,
              conc_cf = conc_cf, template = NULL)

  conc_is_rast <- .is_raster_input(conc_real)
  pop_is_rast  <- .is_raster_input(pop_total)
  cf_is_rast   <- .is_raster_input(conc_cf)
  if (!any(conc_is_rast, pop_is_rast, cf_is_rast)) {
    return(out)
  }

  conc_rast <- if (conc_is_rast) .as_spatraster(conc_real) else NULL
  pop_rast  <- if (pop_is_rast)  .as_spatraster(pop_total) else NULL

  final_res <- if (is.null(template)) {
    .resolve_target_res(conc_rast, pop_rast, target_res)
  } else {
    NULL
  }

  if (conc_is_rast || pop_is_rast) {
    rast_list <- list()
    if (conc_is_rast) {
      rast_list$conc <- conc_rast
    }
    if (pop_is_rast) {
      rast_list$pop <- pop_rast
    }

    aligned <- align_to_target(
      rast_list,
      target_res    = final_res,
      target_raster = template,
      pop_names     = if (pop_is_rast) "pop" else NULL
    )

    if (conc_is_rast) {
      out$conc_real <- raster_to_grid(aligned$conc, dgt = dgt_coord)
      out$template  <- aligned$conc
    }
    if (pop_is_rast) {
      out$pop_total <- raster_to_grid(aligned$pop, dgt = dgt_coord)
      if (is.null(out$template)) {
        out$template <- aligned$pop
      }
    }
  }

  if (cf_is_rast) {
    cf_rast <- .as_spatraster(conc_cf)
    # Onto the lattice the exposure and the population resolved, not onto one
    # derived from the counterfactual's own extent: two grids that overlap but
    # whose cell centres differ share no key at all, and the join comes back
    # empty.
    cf_target  <- if (!is.null(template)) template else out$template
    cf_aligned <- align_to_target(list(cf = cf_rast), target_res = final_res,
                                  target_raster = cf_target)
    out$conc_cf <- raster_to_grid(cf_aligned$cf, dgt = dgt_coord)
  }

  # A single-band raster carries the whole field, so its value column can be
  # named outright: after the scenario when one was requested, otherwise after
  # the canonical `conc` / `pop`. Without this the pipeline cannot find the
  # value column and reports it as missing.
  if (conc_is_rast) {
    out$conc_real <- .rename_single_band(out$conc_real, scenario, "conc")
  }
  if (pop_is_rast) {
    out$pop_total <- .rename_single_band(out$pop_total, scenario, "pop")
  }
  if (cf_is_rast) {
    out$conc_cf <- .rename_single_band(out$conc_cf, scenario, "conc")
  }

  out
}

# Rasterize an admin boundary source onto the analysis grid and attach the
# resulting domain column to calc_fild.
#
# With a raster template the boundaries are rasterized onto it. Without one
# the grid is a table of cell centres, and the labels are taken from the
# boundaries directly by point-in-polygon: a table's coordinate keys are
# rounded (5.12, 5.38, ...), so no regular raster lattice reproduces them --
# the old fixed 0.1 deg fallback matched no key at all, and even a lattice
# built from the key spacing drifts away from the rounded centres. The join
# targets one cell per row of `calc_fild`.
.attach_admin <- function(calc_fild, admin, admin_col, mort_lvl, mort_rate,
                          template = NULL, dgt_coord = 2) {
  if (is.null(admin)) {
    return(calc_fild)
  }

  admin_df <- if (is.null(template)) {
    .admin_points_to_grid(calc_fild, admin, admin_col = admin_col,
                          dgt = dgt_coord)
  } else {
    shapefile_to_grid(admin, template, admin_col = admin_col, dgt = dgt_coord)
  }

  admin_val_col <- setdiff(names(admin_df), c("x", "y"))
  if (!is.null(mort_lvl) && admin_col != mort_lvl) {
    names(admin_df)[names(admin_df) == admin_col] <- mort_lvl
    cli::cli_inform("Admin column renamed: {admin_col} -> {mort_lvl}")
    admin_val_col <- mort_lvl
  }

  admin_vals <- unique(stats::na.omit(admin_df[[admin_val_col]]))
  if (!is.null(mort_lvl) && mort_lvl %in% names(mort_rate)) {
    mort_vals <- unique(mort_rate[[mort_lvl]])
    overlap   <- intersect(admin_vals, mort_vals)
    if (length(overlap) == 0) {
      cli::cli_warn(str_c(
        "No overlap between admin boundary values and mort_rate${mort_lvl} values. ",
        "Admin sample: {paste(head(admin_vals, 5), collapse = \", \")}; Mort rate sample: ",
        "{paste(head(mort_vals, 5), collapse = \", \")}"
      ))
    } else if (length(overlap) < length(admin_vals)) {
      missing <- setdiff(admin_vals, mort_vals)
      cli::cli_inform(str_c(
        "Note: {length(missing)} admin unit(s) have no matching mortality data ",
        "(e.g. {paste(head(missing, 3), collapse = \", \")})"
      ))
    }
  }

  # Join on the coordinates under a temporary label name: `calc_fild` may
  # already carry a column with the label's name (a table that names its own
  # domains, handed back with `admin =`), and dplyr would then suffix both
  # sides and the label would look absent. The boundaries win, as they do
  # whenever `admin =` is given.
  #
  # The label table is always keyed `x`/`y` while `calc_fild` may spell its
  # coordinates `lon`/`lat`; the join maps the two spellings.
  xy <- .grid_xy(calc_fild)
  if (length(xy) != 2) {
    .abort(str_c(
      "`admin` needs coordinate columns on `calc_fild` to attach the boundary labels ",
      "to; none of x/y, lon/lat or longitude/latitude is present."
    ))
  }
  label_tmp <- ".admin_label"
  names(admin_df)[names(admin_df) == admin_val_col] <- label_tmp
  joined <- left_join(calc_fild, admin_df,
                      by = stats::setNames(c("x", "y"), xy))
  joined[[admin_val_col]] <- joined[[label_tmp]]
  joined[[label_tmp]] <- NULL

  # Labels that never landed on the grid are not a domain column: dropping
  # them silently would either summarise one huge unnamed domain or fail much
  # later with an unrelated join complaint, so it is reported here.
  if (all(is.na(joined[[admin_val_col]]))) {
    res_txt <- if (is.null(template)) {
      ""
    } else {
      paste0(" (grid resolution ", .fmt_res(terra::res(template)), " deg)")
    }
    .abort(str_c(
      "`admin` labelled no cell of the analysis grid{res_txt}: the domain column is ",
      "missing or NA everywhere, so there is nothing to join. The boundaries have to ",
      "overlap the grid the analysis runs on."
    ))
  }

  cli::cli_inform(
    "Merged admin boundary into calc_fild: {length(admin_vals)} unique {admin_val_col} value(s)."
  )
  joined
}

# Read an `admin` source as an sf object, the way shapefile_to_grid() does.
.read_admin_sf <- function(admin) {
  if (inherits(admin, "sf")) {
    return(admin)
  }
  if (is.character(admin) && length(admin) == 1 && file.exists(admin)) {
    return(sf::st_read(admin, quiet = TRUE))
  }
  if (is.null(admin)) {
    if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
      .abort(str_c(
        "Package 'rnaturalearth' is required for automatic world boundaries. ",
        "Install it with: install.packages('rnaturalearth')"
      ))
    }
    return(rnaturalearth::ne_countries(scale = 110, returnclass = "sf"))
  }
  .abort("Admin boundaries must be a file path, an sf object, or NULL.")
}

# Resolve the domain column of an sf object: `admin_col` when present, the
# first character column otherwise (shapefile_to_grid()'s fallback).
.resolve_admin_col <- function(shp, admin_col) {
  if (admin_col %in% names(shp)) {
    return(admin_col)
  }
  char_cols <- setdiff(names(shp)[map_lgl(shp, is.character)], "geometry")
  if (length(char_cols) == 0) {
    .abort("No character columns found in shapefile attributes.")
  }
  cli::cli_warn("admin_col '{admin_col}' not found in shapefile. Using '{char_cols[1]}' instead.")
  char_cols[1]
}

# Domain labels for a tabular grid: one point per cell row, joined to the
# boundaries by point-in-polygon. Returns the x/y + label data.frame shape
# shapefile_to_grid() produces, keyed at `dgt`. A point on a shared border
# intersects several units; the first match is kept so one cell stays one row.
.admin_points_to_grid <- function(calc_fild, admin, admin_col, dgt) {
  xy <- .grid_xy(calc_fild)
  if (length(xy) != 2) {
    .abort(str_c(
      "`admin` requires gridded `calc_fild` (an x/y, lon/lat or longitude/latitude ",
      "pair) when no raster input defines the target grid."
    ))
  }

  x <- suppressWarnings(as.numeric(calc_fild[[xy[1]]]))
  y <- suppressWarnings(as.numeric(calc_fild[[xy[2]]]))
  if (anyNA(x) || anyNA(y)) {
    .abort(str_c(
      "`admin` needs numeric coordinate columns to place the boundaries; ",
      "`calc_fild` has unparseable values in `{xy[1]}` or `{xy[2]}`."
    ))
  }

  shp <- .read_admin_sf(admin)
  admin_col <- .resolve_admin_col(shp, admin_col)
  if (!is.na(sf::st_crs(shp)) && !identical(sf::st_crs(shp), sf::st_crs(4326))) {
    shp <- sf::st_transform(shp, 4326)
  }

  pts <- sf::st_as_sf(
    data.frame(.row = seq_along(x), x = x, y = y),
    coords = c("x", "y"), crs = 4326
  )
  hit <- sf::st_join(pts, shp[, admin_col, drop = FALSE],
                     join = sf::st_intersects, left = TRUE)
  hit <- hit[!duplicated(hit$.row), , drop = FALSE]

  out <- data.frame(
    x = matchable(x, dgt),
    y = matchable(y, dgt),
    value = as.character(hit[[admin_col]]),
    stringsAsFactors = FALSE
  )
  names(out)[3] <- admin_col
  out
}
