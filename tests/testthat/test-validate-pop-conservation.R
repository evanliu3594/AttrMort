# Tests for the population aggregation: what the conservation check compares,
# and that reading less of the source changes no value.
#
# The two properties belong together. `.aggregate_pop()` aggregates the source
# first (which is what conserves the total) and only then resamples onto the
# template, so the total it can report on is the source's total over the
# footprint the *output* has. The overall source total is a different number
# (7,981,969,726 for the globe against 90,758,858 for a Lao window), and
# comparing the two reported a 98.8630% "loss" for a transfer that is exact.
# Cropping to that footprint before reading is the same idea applied to the
# I/O: without it a 6699-cell window aggregates 9.33e8 source cells.

.cons_raster <- function(nrows, ncols, xmin, xmax, ymin, ymax, value) {
  r <- terra::rast(nrows = nrows, ncols = ncols, xmin = xmin, xmax = xmax,
                   ymin = ymin, ymax = ymax)
  terra::values(r) <- value
  terra::crs(r) <- "EPSG:4326"
  r
}

# A 0.05 deg source over 4 x 4 deg, 80 x 80 cells, with a gradient so that a
# different aggregation lattice cannot give the same block sums by accident.
.cons_source <- function() {
  r <- .cons_raster(80, 80, 0, 4, 0, 4, 1)
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- 100 + 10 * xy[, "x"] + 3 * xy[, "y"]
  r
}

.cons_target <- function(xmin = 1, xmax = 3, ymin = 1, ymax = 3, res = 0.1) {
  terra::rast(terra::ext(xmin, xmax, ymin, ymax), resolution = res)
}

# Warnings a call produced, as text, without printing them.
.cons_warnings <- function(expr) {
  out <- character(0)
  withCallingHandlers(
    force(expr),
    warning = function(w) {
      out <<- c(out, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  out
}

describe("population aggregation reads only the footprint it outputs", {
  it("returns a window on whole aggregation blocks that covers the template", {
    src <- .cons_source()
    tpl <- .cons_target(xmin = 1.05, xmax = 2.95, ymin = 1.05, ymax = 2.95)
    step <- terra::res(src) * 2                   # 0.05 -> 0.1 deg blocks
    win  <- AttrMort:::.pop_window(src, tpl, step)

    expect_s4_class(win, "SpatExtent")
    # covers the template ...
    expect_lte(win[1], terra::xmin(tpl))
    expect_gte(win[2], terra::xmax(tpl))
    expect_lte(win[3], terra::ymin(tpl))
    expect_gte(win[4], terra::ymax(tpl))
    # ... and starts on a whole number of blocks from the source origin, or the
    # aggregation would move to another lattice.
    off_x <- (win[1] - terra::xmin(src)) / step[1]
    off_y <- (win[3] - terra::ymin(src)) / step[2]
    expect_equal(off_x, round(off_x))
    expect_equal(off_y, round(off_y))
  })

  it("keeps the aggregation blocks when res() is not exactly representable", {
    # 30 arc-sec is 1/120, which is not a binary fraction: terra reports
    # 0.0083333333329999992, so a window computed in degrees lands a hair below
    # the cell boundary it means and `terra::crop()` snaps one whole cell
    # further out -- moving every aggregation block with it. Measured on the
    # shipped LandScan with a Lao window: 88 of 6699 cells changed. The control
    # is the same window of the *uncropped* aggregation, cell for cell.
    src <- .cons_raster(600, 600, 0, 5, 0, 5, 1)          # res = 1/120
    xy  <- terra::xyFromCell(src, seq_len(terra::ncell(src)))
    terra::values(src) <- 100 + 10 * xy[, "x"] + 3 * xy[, "y"]
    tpl <- .cons_target(xmin = 1, xmax = 2, ymin = 1.3, ymax = 2.3)

    win <- AttrMort:::.pop_window(src, tpl, terra::res(src) * 12)
    cut <- AttrMort:::.pop_crop(src, win, tpl)
    # the window is on the block lattice, and not one cell wider than it has to be
    e_r <- as.vector(terra::ext(src))
    expect_equal((terra::xmin(cut) - e_r[1]) / (terra::res(src)[1] * 12),
                 round((terra::xmin(cut) - e_r[1]) / (terra::res(src)[1] * 12)),
                 tolerance = 1e-9)
    expect_lte(terra::xmin(cut), terra::xmin(tpl))
    expect_gte(terra::xmax(cut), terra::xmax(tpl))

    from_full <- terra::aggregate(src, fact = c(12, 12), fun = "sum", na.rm = TRUE)
    same_window <- terra::crop(from_full,
                               terra::ext(terra::xmin(cut), terra::xmax(cut),
                                          terra::ymin(cut), terra::ymax(cut)),
                               snap = "near")
    from_cut <- terra::aggregate(cut, fact = c(12, 12), fun = "sum", na.rm = TRUE)

    expect_equal(terra::ncell(from_cut), terra::ncell(same_window))
    expect_identical(terra::values(from_cut), terra::values(same_window))
  })

  it("leaves the values untouched, compared with a block-aligned crop", {
    # Reading less of the source is an optimisation, so it has to be exact:
    # the same result from the whole source and from the window it reads. The
    # warning that a block-offset template produces belongs to the check in the
    # next describe() block, not here.
    src <- .cons_source()
    tpl <- .cons_target(xmin = 1.05, xmax = 2.95, ymin = 1.05, ymax = 2.95)
    step <- terra::res(src) * 2
    win  <- AttrMort:::.pop_window(src, tpl, step)

    from_full <- suppressWarnings(AttrMort:::.aggregate_pop(src, tpl))
    from_win  <- suppressWarnings(
      AttrMort:::.aggregate_pop(terra::crop(src, win, snap = "out"), tpl))

    expect_equal(terra::values(from_full), terra::values(from_win), tolerance = 1e-12)
    expect_equal(terra::global(from_full, "sum", na.rm = TRUE)[[1]],
                 terra::global(from_win, "sum", na.rm = TRUE)[[1]],
                 tolerance = 1e-12)
  })

  it("changes the values when the crop is off the aggregation lattice", {
    # The control for the test above: a window half a block off really does give
    # different numbers, which is why the window is rounded to whole blocks
    # rather than taken as the template extent.
    src <- .cons_source()
    tpl <- .cons_target(xmin = 1.05, xmax = 2.95, ymin = 1.05, ymax = 2.95)
    win  <- AttrMort:::.pop_window(src, tpl, terra::res(src) * 2)
    off  <- terra::ext(terra::xmin(win) + 0.05, terra::xmax(win),
                       terra::ymin(win) + 0.05, terra::ymax(win))

    from_full <- suppressWarnings(AttrMort:::.aggregate_pop(src, tpl))
    from_off  <- suppressWarnings(
      AttrMort:::.aggregate_pop(terra::crop(src, off, snap = "out"), tpl))

    expect_false(isTRUE(all.equal(terra::values(from_full), terra::values(from_off))))
  })

  it("keeps the window when the target is finer than the source", {
    # The disaggregation branch has its own lattice (whole source cells), and
    # the equal-values property has to hold there too.
    src <- .cons_source()                       # 0.05 deg
    tpl <- .cons_target(xmin = 1, xmax = 3, ymin = 1, ymax = 3, res = 0.02)
    win <- AttrMort:::.pop_window(src, tpl, terra::res(src))

    from_full <- suppressWarnings(AttrMort:::.aggregate_pop(src, tpl))
    from_win  <- suppressWarnings(
      AttrMort:::.aggregate_pop(terra::crop(src, win, snap = "out"), tpl))

    expect_equal(terra::values(from_full), terra::values(from_win), tolerance = 1e-12)
  })

  it("keeps the window when the resolutions are not an exact multiple", {
    src <- .cons_source()                       # 0.05 deg
    tpl <- .cons_target(xmin = 1, xmax = 3, ymin = 1, ymax = 3, res = 0.12)
    win <- AttrMort:::.pop_window(src, tpl, terra::res(src))

    from_full <- suppressWarnings(AttrMort:::.aggregate_pop(src, tpl))
    from_win  <- suppressWarnings(
      AttrMort:::.aggregate_pop(terra::crop(src, win, snap = "out"), tpl))

    expect_equal(terra::values(from_full), terra::values(from_win), tolerance = 1e-12)
  })

  it("keeps every band of a multi-band source the same", {
    # A multi-band source used to end the comparison in
    # "'length = 2' in coercion to 'logical(1)'": the totals are one number per
    # layer, and both the check and the report have to say which layer moved.
    src <- .cons_source()
    two <- c(src, src * 2)
    tpl <- .cons_target(xmin = 1, xmax = 3, ymin = 1, ymax = 3)
    win <- AttrMort:::.pop_window(src, tpl, terra::res(src) * 2)

    from_full <- AttrMort:::.aggregate_pop(two, tpl)
    from_win  <- AttrMort:::.aggregate_pop(terra::crop(two, win, snap = "out"), tpl)

    expect_equal(terra::nlyr(from_full), 2L)
    expect_equal(terra::values(from_full), terra::values(from_win), tolerance = 1e-12)

    # and a loss in one layer is reported for that layer, not as a length-2 error
    warns <- .cons_warnings(AttrMort:::.aggregate_pop(two, tpl, tol = -1))
    expect_match(paste(warns, collapse = "\n"), "layer 1")
  })

  it("does not crop, and does not compare totals, outside the source", {
    # A template reaching past the source has no window that both covers it and
    # stays inside, so the whole source is read and no total is compared: the
    # two footprints differ, and two footprints cannot be compared.
    src <- .cons_source()
    tpl <- .cons_target(xmin = -1, xmax = 5, ymin = -1, ymax = 5, res = 0.1)

    expect_null(AttrMort:::.pop_window(src, tpl, terra::res(src) * 2))
    warns <- .cons_warnings(out <- AttrMort:::.aggregate_pop(src, tpl))

    expect_false(any(grepl("changed the total", warns)))
    # the covered part is still transferred
    inside <- terra::crop(out, terra::ext(0.5, 3.5, 0.5, 3.5))
    expect_equal(terra::global(inside, "sum", na.rm = TRUE)[[1]],
                 terra::global(terra::crop(src, terra::ext(0.5, 3.5, 0.5, 3.5)),
                               "sum", na.rm = TRUE)[[1]],
                 tolerance = 1e-9)
  })
})

describe("alignment tells the same CRS apart from a different spelling of it", {
  # "EPSG:4326" and "OGC:CRS84" are the same grid with two CRS strings. The old
  # check compared the strings, so the whole raster went through
  # terra::project() and the user got a "Reprojecting ..." warning for a warp
  # that changes no value (measured: bit-identical output). terra::same.crs()
  # asks terra instead. A CRS that really differs still gets both.
  it("does not reproject a CRS84 source onto an EPSG:4326 template", {
    conc <- .cons_raster(4, 4, 0, 12, 0, 12, 30)
    terra::crs(conc) <- "OGC:CRS84"
    tpl <- terra::rast(terra::ext(0, 12, 0, 12), resolution = 3)
    terra::crs(tpl) <- "EPSG:4326"

    warns <- .cons_warnings(
      aligned <- AttrMort:::align_to_target(list(conc = conc), target_raster = tpl))
    expect_false(any(grepl("Reprojecting", warns)))

    # the value of not projecting: the output is the plain resample, with no
    # warp round-trip in between
    ref <- terra::resample(conc, tpl, method = "bilinear")
    expect_equal(terra::values(aligned$conc), terra::values(ref))
  })

  it("does not reproject an EPSG:4326 source onto a CRS84 template", {
    conc <- .cons_raster(4, 4, 0, 12, 0, 12, 30)
    terra::crs(conc) <- "EPSG:4326"
    tpl <- terra::rast(terra::ext(0, 12, 0, 12), resolution = 3)
    terra::crs(tpl) <- "OGC:CRS84"

    warns <- .cons_warnings(
      aligned <- AttrMort:::align_to_target(list(conc = conc), target_raster = tpl))

    expect_false(any(grepl("Reprojecting", warns)))
    expect_equal(terra::values(aligned$conc),
                 terra::values(terra::resample(conc, tpl, method = "bilinear")))
  })

  it("still reprojects a CRS that really is different", {
    conc <- .cons_raster(4, 4, 0, 12, 0, 12, 30)
    terra::crs(conc) <- "EPSG:3857"
    tpl <- terra::rast(terra::ext(0, 12, 0, 12), resolution = 3)
    terra::crs(tpl) <- "EPSG:4326"

    expect_warning(
      AttrMort:::align_to_target(list(conc = conc), target_raster = tpl),
      "Reprojecting")
  })
})

describe("the conservation check compares like with like", {  it("does not report a windowed output as a loss", {
    # Regression: the base of the comparison was the source's *global* total, so
    # every regional run warned -- the shipped LandScan against a Lao window was
    # reported as "changed the total by 98.8630%" although the transfer is exact.
    src <- .cons_source()
    tpl <- .cons_target(xmin = 1, xmax = 3, ymin = 1, ymax = 3)

    warns <- .cons_warnings(out <- AttrMort:::.aggregate_pop(src, tpl))
    expect_false(any(grepl("changed the total", warns)))

    # and it is exact, against the source over the same footprint
    expect_equal(terra::global(out, "sum", na.rm = TRUE)[[1]],
                 terra::global(terra::crop(src, tpl, snap = "out"), "sum", na.rm = TRUE)[[1]],
                 tolerance = 1e-9)
  })

  it("reports the footprint totals, not the read window or the source-wide total", {
    # `tol = -1` forces the report so the message itself can be inspected. The
    # template here is off the *block* lattice, so three different numbers are
    # in play: the source overall, the (larger) window that was read, and the
    # footprint the output covers. The message has to carry the last one.
    src <- .cons_source()
    tpl <- .cons_target(xmin = 1.05, xmax = 2.95, ymin = 1.05, ymax = 2.95)

    warns <- .cons_warnings(AttrMort:::.aggregate_pop(src, tpl, tol = -1))
    msg   <- paste(warns, collapse = "\n")
    expect_match(msg, "changed the total")

    footprint <- terra::global(
      AttrMort:::.pop_footprint(src, tpl), "sum", na.rm = TRUE)[[1]]
    win  <- AttrMort:::.pop_window(src, tpl, terra::res(src) * 2)
    read_window <- terra::global(terra::crop(src, win, snap = "out"),
                                 "sum", na.rm = TRUE)[[1]]
    global_sum  <- terra::global(src, "sum", na.rm = TRUE)[[1]]

    expect_match(msg, format(footprint, big.mark = ","), fixed = TRUE)
    expect_false(grepl(format(read_window, big.mark = ","), msg, fixed = TRUE))
    expect_false(grepl(format(global_sum, big.mark = ","), msg, fixed = TRUE))
  })

  it("compares nothing when the template's edges miss the source lattice", {
    # An off-lattice template has no footprint the crop can isolate, so there is
    # nothing to compare against and the check stays quiet rather than comparing
    # two different areas.
    src <- .cons_raster(80, 80, 0, 4, 0, 4, 1)     # 0.05 deg, on its own lattice
    # 1.9 deg wide, so the resolution stays an exact multiple of the source and
    # the edges still fall between two source cells (1.03 / 0.05 = 20.6)
    tpl <- .cons_target(xmin = 1.03, xmax = 2.93, ymin = 1.03, ymax = 2.93)

    expect_null(AttrMort:::.pop_footprint(src, tpl))
    warns <- .cons_warnings(AttrMort:::.aggregate_pop(src, tpl, tol = -1))
    expect_length(warns, 0)
  })
})
