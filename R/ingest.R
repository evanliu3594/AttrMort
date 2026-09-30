# ── Input ingestion ─────────────────────────────────────────────────────
#
# Everything that turns *user input* (file paths, rasters, wide tables with
# arbitrary column names) into the standardised data.frames consumed by
# .calc_attributable(). Split out of Mortality.R so that the computation
# itself stays readable.

# Every character input must name an existing file. Checked up front so the
# user gets a precise message instead of whatever terra/readxl reports.
.check_input_files <- function(...) {
  inputs <- list(...)
  for (nm in names(inputs)) {
    x <- inputs[[nm]]
    if (is.character(x) && length(x) == 1 && !file.exists(x)) {
      stop("File not found: ", x, " (input `", nm, "`)", call. = FALSE)
    }
  }
  invisible(TRUE)
}

# Ingest one input: data.frame passes through; a character path is loaded
# according to its extension. Raster paths are handled by the caller
# (.align_raster_inputs) so that they can be aligned first.
.ingest_single_input <- function(x, dgt_coord = 1) {
  if (is.data.frame(x)) {
    return(x)
  }
  if (!is.character(x)) {
    stop(
      "Each data input must be a data.frame or a file path (character). ",
      "Got: ", paste(class(x), collapse = "/"), ".",
      call. = FALSE
    )
  }
  if (length(x) != 1) {
    stop("A file path must be a single character string.", call. = FALSE)
  }
  if (!file.exists(x)) {
    stop("File not found: ", x, call. = FALSE)
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
    stop(
      "Unsupported file format: .", ext, ". ",
      "Supported rasters: .tif .tiff .nc .grd .asc .img .vrt .bil .hdf; ",
      "tables: .csv .txt .xls .xlsx.",
      call. = FALSE
    )
  )
}

# Render numeric coordinate columns as character keys, as the data contract
# requires. Raster input already arrives as character keys; tabular input often
# carries plain numbers, and mixing the two would break the join. When
# `dgt_coord` is too coarse to keep the coordinates distinct the column is left
# numeric, with a warning, rather than silently collapsing grid cells.
.normalise_coord_keys <- function(df, dgt_coord) {
  for (col in intersect(.COORD_VARIANTS, names(df))) {
    v <- df[[col]]
    if (!is.numeric(v)) {
      next
    }
    key <- matchable(v, dgt = dgt_coord)
    if (length(unique(key)) == length(unique(v))) {
      df[[col]] <- key
    } else {
      warning(
        "Coordinate column `", col, "` needs more decimals than ",
        "`dgt_coord = ", dgt_coord, "` to stay unique; keeping it numeric. ",
        "Set `dgt_coord` to match the grid resolution.",
        call. = FALSE
      )
    }
  }
  df
}

# Ingest an input, rename its columns to the canonical schema, and render its
# numeric coordinate keys as strings.
.ingest_and_map <- function(x, schema, dgt_coord = 1, label = NULL) {
  df <- .ingest_single_input(x, dgt_coord)

  mapping <- detect_columns(df, schema = schema, quiet = TRUE)
  if (length(mapping) > 0) {
    # detect_columns() returns c(semantic = "<actual column>"); the pipeline
    # expects the canonical names (.COLUMN_TARGET), so rename actual ->
    # canonical. A rename is skipped when it would duplicate a canonical column
    # that already exists under a different name: the existing column wins.
    target <- .COLUMN_TARGET[names(mapping)]
    keep   <- !is.na(target) &
      (target == unname(mapping) | !target %in% names(df))
    mapping <- mapping[keep]
    target  <- .COLUMN_TARGET[names(mapping)]

    if (length(mapping) > 0) {
      renamed <- setNames(unname(mapping), target)
      changed <- renamed[names(renamed) != renamed]
      if (length(changed) > 0) {
        message(
          if (is.null(label)) "Column mapping: " else paste0("`", label, "`: "),
          paste(sprintf("%s -> %s", changed, names(changed)), collapse = ", ")
        )
      }
      df <- df |> rename(!!!renamed)
    }
  }

  .normalise_coord_keys(df, dgt_coord)
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
.rename_single_band <- function(df, scenario, what) {
  if (is.null(df)) {
    return(NULL)
  }
  val_cols <- setdiff(names(df), c("x", "y"))
  if (length(val_cols) != 1) {
    return(df)
  }
  if (!is.null(scenario) && !grepl("^band", val_cols[1])) {
    return(df)
  }
  target <- if (is.null(scenario)) what else scenario
  if (identical(val_cols[1], target)) {
    return(df)
  }
  names(df)[names(df) == val_cols[1]] <- target
  message("Single-band ", what, " raster renamed: ", val_cols[1],
          " -> ", target)
  df
}

# Detect raster inputs, align them all onto one grid, and return plain
# data.frames plus the aligned template raster (used later for admin
# rasterization). Non-raster inputs are returned untouched.
.align_raster_inputs <- function(conc_real, pop_total, conc_cf, scenario,
                                 target_res, dgt_coord) {
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

  final_res <- .resolve_target_res(conc_rast, pop_rast, target_res)

  if (conc_is_rast || pop_is_rast) {
    rast_list <- list()
    if (conc_is_rast) rast_list$conc <- conc_rast
    if (pop_is_rast)  rast_list$pop  <- pop_rast

    aligned <- align_to_target(
      rast_list,
      target_res = final_res,
      pop_names  = if (pop_is_rast) "pop" else NULL
    )

    if (conc_is_rast) {
      out$conc_real <- raster_to_grid(aligned$conc, dgt = dgt_coord)
      out$template  <- aligned$conc
    }
    if (pop_is_rast) {
      out$pop_total <- raster_to_grid(aligned$pop, dgt = dgt_coord)
      if (is.null(out$template)) out$template <- aligned$pop
    }
  }

  if (cf_is_rast) {
    cf_rast    <- .as_spatraster(conc_cf)
    cf_aligned <- align_to_target(list(cf = cf_rast), target_res = final_res)
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
.attach_admin <- function(calc_fild, admin, admin_col, mort_lvl, mort_rate,
                          template = NULL, target_res = NULL, dgt_coord = 2) {
  if (is.null(admin)) {
    return(calc_fild)
  }

  if (is.null(template)) {
    xy <- intersect(c("x", "y"), names(calc_fild))
    if (length(xy) != 2) {
      stop(
        "`admin` requires gridded `calc_fild` (columns x and y) when no ",
        "raster input defines the target grid.",
        call. = FALSE
      )
    }
    template <- terra::rast(
      terra::ext(range(as.numeric(calc_fild$x)), range(as.numeric(calc_fild$y))),
      resolution = if (is.null(target_res)) 0.1 else target_res
    )
    terra::crs(template) <- "EPSG:4326"
  }

  admin_df <- shapefile_to_grid(admin, template,
                                admin_col = admin_col, dgt = dgt_coord)

  admin_val_col <- setdiff(names(admin_df), c("x", "y"))
  if (!is.null(mort_lvl) && admin_col != mort_lvl) {
    names(admin_df)[names(admin_df) == admin_col] <- mort_lvl
    message("Admin column renamed: ", admin_col, " -> ", mort_lvl)
    admin_val_col <- mort_lvl
  }

  admin_vals <- unique(admin_df[[admin_val_col]])
  if (!is.null(mort_lvl) && mort_lvl %in% names(mort_rate)) {
    mort_vals <- unique(mort_rate[[mort_lvl]])
    overlap   <- intersect(admin_vals, mort_vals)
    if (length(overlap) == 0) {
      warning(
        "No overlap between admin boundary values and mort_rate$", mort_lvl,
        " values. Admin sample: ",
        paste(head(admin_vals, 5), collapse = ", "),
        "; Mort rate sample: ",
        paste(head(mort_vals, 5), collapse = ", "),
        call. = FALSE
      )
    } else if (length(overlap) < length(admin_vals)) {
      missing <- setdiff(admin_vals, mort_vals)
      message("Note: ", length(missing), " admin unit(s) have no matching ",
              "mortality data (e.g. ",
              paste(head(missing, 3), collapse = ", "), ")")
    }
  }

  joined <- left_join(calc_fild, admin_df, by = c("x", "y"))
  message("Merged admin boundary into calc_fild: ", length(admin_vals),
          " unique ", admin_val_col, " value(s).")
  joined
}

# Extract the column (or raster band) named `scenario` from each wide input.
.extract_scenario <- function(conc_real, pop_total, age_struc, mort_rate,
                              conc_cf, scenario, dgt_conc) {
  if (is.null(scenario)) {
    # Nothing to extract, but the concentration key still has to follow the
    # data contract: a single-band raster or an already-long table hands the
    # value over as a plain number, while the lookup table keys are strings.
    as_key <- function(df) {
      if (is.data.frame(df) && is.numeric(df$conc)) {
        df$conc <- matchable(df$conc, dgt = dgt_conc)
      }
      df
    }
    return(list(conc_real = as_key(conc_real), pop_total = pop_total,
                age_struc = age_struc, mort_rate = mort_rate,
                conc_cf = as_key(conc_cf)))
  }
  # Every input is extracted only when it is present: `conc_cf` is optional in
  # Mortality() and the domain summary carries no age structure or mortality
  # table at all, so NULL stays NULL instead of being handed to getAge().
  list(
    conc_real = getConc(conc_real, scenario, dgt = dgt_conc),
    pop_total = getPop(pop_total, scenario),
    age_struc = if (is.null(age_struc)) NULL else getAge(age_struc, scenario),
    mort_rate = if (is.null(mort_rate)) NULL else getMort(mort_rate, scenario),
    conc_cf   = if (is.null(conc_cf)) NULL else getConc(conc_cf, scenario,
                                                        dgt = dgt_conc)
  )
}
