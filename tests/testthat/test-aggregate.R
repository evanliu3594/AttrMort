# Tests for aggregate_mortality() / aggregate_ci() — BDD Given-When-Then (testthat 3e)

# ── Fixtures ─────────────────────────────────────────────────────────────
# Hand-built grid-level mortality results so every expected sum is exact.
# x/y are deliberately large and odd, so any accidental summation of the
# coordinates is impossible to overlook (the known bug of the script-style
# source project, which summed `where(is.numeric)`).
#
#   grid_at()  plain  `{endpoint}_{age}` output, two endpoints spanning
#              different ages, with a real `+` and a `_` in the endpoint names
#   grid_ci()  the same values plus MEAN/UP/LOW branches side by side
grid_at <- function() {
  data.frame(
    location   = c("A", "A", "B", "B"),
    x          = c(0, 1, 0, 1),
    y          = c(0, 0, 9, 9),
    ncd_lri_25 = c(1, 2, 3, 4),
    ncd_lri_50 = c(10, 20, 30, 40),
    ihd_25     = c(100, 200, 300, 400),
    ihd_50     = c(1000, 2000, 3000, 4000)
  )
}

grid_ci <- function() {
  base <- grid_at()
  # value columns only — a CI result never carries the plain branches too
  base$location <- NULL
  base$x <- NULL
  base$y <- NULL
  plain <- grid_at()[c("location", "x", "y")]
  out <- cbind(plain, base, base * 10, base * 0.5)
  names(out) <- c(
    names(plain),
    paste0(names(base), "_MEAN"),
    paste0(names(base), "_UP"),
    paste0(names(base), "_LOW")
  )
  out
}

describe("aggregate_mortality()", {
  # GIVEN a grid-level mortality result with explicit `{endpoint}_{age}` columns,
  # WHEN aggregate_mortality() is called with at = "location", by = "total",
  # THEN one row per location holds the sum of every endpoint x age column, and
  #      the coordinates are NOT part of that sum.
  it("sums all endpoint x age columns per domain, never the coordinates", {
    result <- aggregate_mortality(grid_at(), at = "location", by = "total")

    expect_s3_class(result, "data.frame")
    expect_equal(names(result)[1:2], c("location", "total"))
    expect_equal(nrow(result), 2L)
    expect_equal(result$location, c("A", "B"))
    # A: 1+2+10+20+100+200+1000+2000 = 3333
    # B: 3+4+30+40+300+400+3000+4000 = 7777
    # Broken behaviour would add x/y (0+1+0+1 / 0+1+9+9) on top.
    expect_equal(result$total, c(3333, 7777))
  })

  # GIVEN the same input, WHEN by = "endpoint"/"age"/"all",
  # THEN the requested dimension is kept and the margins are correct.
  it("keeps the requested breakdown dimension", {
    by_endpoint <- aggregate_mortality(grid_at(), at = "location", by = "endpoint")
    by_age <- aggregate_mortality(grid_at(), at = "location", by = "age")
    by_all <- aggregate_mortality(grid_at(), at = "location", by = "all")

    expect_equal(names(by_endpoint), c("location", "total", "ncd_lri_all", "ihd_all"))
    expect_equal(by_endpoint$ncd_lri_all, c(33, 77))
    expect_equal(by_endpoint$ihd_all, c(3300, 7700))

    expect_equal(names(by_age), c("location", "total", "all_25", "all_50"))
    expect_equal(by_age$all_25, c(303, 707))
    expect_equal(by_age$all_50, c(3030, 7070))

    # by = "all" restores the original {endpoint}_{age} column names
    expect_equal(
      names(by_all),
      c("location", "total", "ncd_lri_25", "ncd_lri_50", "ihd_25", "ihd_50")
    )
    expect_equal(by_all$ncd_lri_25, c(3, 7))

    # every breakdown must agree with the total
    expect_equal(by_endpoint$ncd_lri_all + by_endpoint$ihd_all, by_endpoint$total)
    expect_equal(by_age$all_25 + by_age$all_50, by_age$total)
  })

  # GIVEN the same input, WHEN at = "grid",
  # THEN no aggregation happens and only the total column is appended.
  it("returns the input unchanged for at = \"grid\"", {
    result <- aggregate_mortality(grid_at(), at = "grid", by = "total")

    expect_equal(nrow(result), nrow(grid_at()))
    expect_true(all(c("x", "y", "ncd_lri_25", "ihd_50") %in% names(result)))
    expect_equal(result$x, grid_at()$x)
    expect_equal(result$y, grid_at()$y)
    expect_equal(result$total, rowSums(grid_at()[-(1:3)]))
  })

  # GIVEN a result without the domain column but with x/y,
  # WHEN calc_fild carrying the domain columns is supplied,
  # THEN the domain is joined in from calc_fild and aggregation proceeds.
  it("joins the domain columns from calc_fild when they are missing", {
    no_domain <- grid_at() |> dplyr::select(-location)
    expect_error(
      aggregate_mortality(no_domain, at = "location"),
      "not found in `x`"
    )

    result <- aggregate_mortality(
      no_domain,
      calc_fild = grid_at() |> dplyr::select(location, x, y),
      at = "location", by = "total"
    )
    expect_equal(names(result)[1:2], c("location", "total"))
    expect_equal(result$total, c(3333, 7777))
  })

  # GIVEN a result carrying one domain column of the attribution field,
  # WHEN at = "geo",
  # THEN grouping uses every non-coordinate, non-value column present.
  it("aggregates over all domain columns for at = \"geo\"", {
    geo_field <- grid_at()
    geo_field$region <- c("R1", "R1", "R2", "R2")
    result <- aggregate_mortality(geo_field, at = "geo", by = "total")

    expect_equal(names(result)[1:2], c("location", "region"))
    expect_equal(result$total, c(3333, 7777))

    # dropping the location column leaves region as the only geo domain
    result_region <- geo_field |>
      dplyr::select(-location) |>
      aggregate_mortality(at = "geo", by = "total")
    expect_equal(names(result_region)[1:2], c("region", "total"))
    expect_equal(result_region$total, c(3333, 7777))
  })

  # GIVEN several scenarios as a named list,
  # WHEN aggregate_mortality() is called,
  # THEN the output carries a scenario column and one block per scenario.
  it("tags a named list of scenarios with a scenario column", {
    second <- grid_at()
    second[-(1:3)] <- 0
    result <- aggregate_mortality(
      list(base2015 = grid_at(), SSP1_2030 = second),
      at = "location", by = "total"
    )

    expect_equal(names(result)[1], "scenario")
    expect_equal(sort(unique(result$scenario)), c("SSP1_2030", "base2015"))
    expect_equal(result$total[result$scenario == "SSP1_2030"], c(0, 0))
    expect_equal(result$total[result$scenario == "base2015"], c(3333, 7777))
  })

  # GIVEN a single-column domain vector and a two-column one,
  # WHEN at is given as column names,
  # THEN exactly those columns are used as the grouping keys.
  it("accepts an explicit column name vector for at", {
    result <- aggregate_mortality(
      grid_at(), at = c("location", "x"), by = "total"
    )
    expect_equal(names(result)[1:3], c("location", "x", "total"))
    expect_equal(nrow(result), 4L) # one row per grid cell
    expect_equal(
      sort(result$total),
      sort(rowSums(grid_at()[-(1:3)]))
    )
  })

  # ── Edge cases and error paths ─────────────────────────────────────
  # GIVEN an input without any `{endpoint}_{age}` column,
  # WHEN aggregate_mortality() is called,
  # THEN it stops with an actionable message.
  it("stops when no endpoint x age columns are present", {
    bare <- data.frame(location = "A", x = 0, y = 0, conc = 1)
    expect_error(aggregate_mortality(bare), "No endpoints x age columns")
  })

  # GIVEN invalid `by` / `at` / `na_rm` arguments,
  # WHEN aggregate_mortality() is called,
  # THEN it stops with a message naming the accepted values.
  it("validates by, at and na_rm", {
    expect_error(
      aggregate_mortality(grid_at(), by = "endpoint_age"),
      "`by` must be one of"
    )
    expect_error(
      aggregate_mortality(grid_at(), at = "nonexistent"),
      "not found in `x`"
    )
    expect_error(
      aggregate_mortality(grid_at(), na_rm = "yes"),
      "`na_rm` must be TRUE or FALSE"
    )
  })

  # GIVEN an unnamed list of results,
  # WHEN aggregate_mortality() is called,
  # THEN it refuses rather than inventing scenario names.
  it("stops on an unnamed list input", {
    expect_error(
      aggregate_mortality(list(grid_at(), grid_at())),
      "must be a NAMED list"
    )
  })

  # GIVEN a value column that is entirely NA and na_rm = TRUE,
  # WHEN aggregate_mortality() is called,
  # THEN the NA is dropped from the sum instead of poisoning it.
  it("honours na_rm = TRUE when a value column holds NAs", {
    with_na <- grid_at()
    with_na$ihd_50[1] <- NA
    result <- aggregate_mortality(with_na, at = "location", by = "total")
    expect_equal(result$total, c(2333, 7777)) # A loses the NA ihd_50 = 1000
  })
})

describe("aggregate_ci()", {
  # GIVEN a result with `{endpoint}_{age}_{MEAN|UP|LOW}` columns side by side,
  # WHEN aggregate_ci() is called with at = "location", by = "total",
  # THEN every row carries the MEAN/UP/LOW triplets side by side, each summed
  #      from its own branch.
  it("keeps MEAN, UP and LOW side by side per domain", {
    result <- aggregate_ci(grid_ci(), at = "location", by = "total")

    expect_s3_class(result, "data.frame")
    expect_equal(names(result)[1:4], c("location", "total_MEAN", "total_UP", "total_LOW"))
    expect_equal(nrow(result), 2L)
    expect_equal(result$total_MEAN, c(3333, 7777))
    expect_equal(result$total_UP, c(33330, 77770))
    expect_equal(result$total_LOW, c(1666.5, 3888.5))
  })

  # GIVEN the same input, WHEN by = "endpoint",
  # THEN the breakdown columns are suffixed per CI branch.
  it("suffixes the marginals with the CI branch", {
    result <- aggregate_ci(grid_ci(), at = "location", by = "endpoint")

    expect_true(all(
      c("total_MEAN", "total_UP", "total_LOW") %in% names(result)
    ))
    expect_true(all(
      c("ncd_lri_all_MEAN", "ncd_lri_all_UP", "ncd_lri_all_LOW") %in% names(result)
    ))
    expect_equal(result$ncd_lri_all_MEAN, c(33, 77))
    expect_equal(result$ncd_lri_all_UP, c(330, 770))
    expect_equal(result$ncd_lri_all_LOW, c(16.5, 38.5))
  })

  # GIVEN the same input, WHEN by = "all",
  # THEN both dimensions are kept alongside the total triplet.
  it("keeps both dimensions for by = \"all\"", {
    result <- aggregate_ci(grid_ci(), at = "location", by = "all")
    expect_true(all(c("ncd_lri_25_MEAN", "ihd_50_LOW") %in% names(result)))
    expect_equal(result$ihd_50_MEAN, c(3000, 7000))
    expect_equal(result$total_MEAN, c(3333, 7777))
  })

  # GIVEN a result suffixed with the UPPER/LOWER spellings that mortality()'s
  # own CI argument uses, WHEN aggregate_ci() is called,
  # THEN the aliases are normalized to the canonical UP/LOW output columns.
  it("accepts _UPPER/_LOWER aliases and normalizes them to UP/LOW", {
    aliased <- grid_ci()
    names(aliased) <- names(aliased) |>
      sub(pattern = "_UP$", replacement = "_UPPER") |>
      sub(pattern = "_LOW$", replacement = "_LOWER")
    result <- aggregate_ci(aliased, at = "location", by = "total")

    expect_equal(
      names(result), c("location", "total_MEAN", "total_UP", "total_LOW")
    )
    expect_equal(result$total_UP, c(33330, 77770))
    expect_equal(result$total_LOW, c(1666.5, 3888.5))
  })

  # GIVEN a CI result and several scenarios,
  # WHEN aggregate_ci() is called on a named list,
  # THEN the scenario column is carried through.
  it("tags a named list of CI scenarios", {
    result <- aggregate_ci(
      list(base2015 = grid_ci(), SSP1_2030 = grid_ci()),
      at = "location", by = "total"
    )
    expect_equal(names(result)[1], "scenario")
    expect_equal(nrow(result), 4L)
    expect_equal(
      result$total_MEAN[result$scenario == "SSP1_2030"], c(3333, 7777)
    )
  })

  # GIVEN at = "grid" on a CI result,
  # WHEN aggregate_ci() is called,
  # THEN each grid cell keeps its own MEAN/UP/LOW totals.
  it("appends the CI triplet per grid cell for at = \"grid\"", {
    result <- aggregate_ci(grid_ci(), at = "grid", by = "total")
    expect_equal(nrow(result), 4L)
    expect_equal(result$total_MEAN, rowSums(grid_ci()[grepl("_MEAN$", names(grid_ci()))]))
    expect_equal(result$total_UP, rowSums(grid_ci()[grepl("_UP$", names(grid_ci()))]))
  })

  # GIVEN a plain (no CI suffix) mortality() result,
  # WHEN aggregate_ci() is called,
  # THEN it stops with a clear pointer to aggregate_mortality().
  it("stops with a clear message when no CI suffix is present", {
    expect_error(
      aggregate_ci(grid_at()),
      "No CI-suffixed columns found"
    )
  })

  # GIVEN only one CI branch (e.g. a MEAN-only run),
  # WHEN aggregate_ci() is called,
  # THEN it refuses instead of returning half a triplet.
  it("stops when the MEAN/UP/LOW triplet is incomplete", {
    mean_only <- grid_ci() |> dplyr::select(-dplyr::ends_with("_UP"))
    expect_error(aggregate_ci(mean_only), "Incomplete CI triplet")
  })

  # GIVEN a CI-suffixed column whose base name cannot be parsed,
  # WHEN aggregate_ci() is called,
  # THEN it stops and names the offending column.
  it("stops on unparseable CI column names", {
    broken <- grid_ci()
    names(broken)[names(broken) == "ihd_50_MEAN"] <- "ihd_MEAN"
    expect_error(aggregate_ci(broken), "Cannot parse CI column name")
  })
})

describe("write_mortality_xlsx()", {
  # GIVEN an aggregated result and a path inside an existing directory,
  # WHEN write_mortality_xlsx() is called,
  # THEN one xlsx file is written and its path returned invisibly.
  it("writes a data.frame to a single-sheet xlsx", {
    skip_if_not_installed("writexl")
    out_dir <- tempfile("agg")
    dir.create(out_dir)
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    result <- aggregate_mortality(grid_at(), at = "location", by = "total")
    path <- write_mortality_xlsx(result, file.path(out_dir, "loc_total"))

    expect_true(file.exists(path))
    expect_match(basename(path), "^loc_total\\.xlsx$")
    expect_equal(readxl::excel_sheets(path), "Sheet1")
  })

  # GIVEN a named list of results and a suffix,
  # WHEN write_mortality_xlsx() is called,
  # THEN one sheet per element is written under `<suffix>.xlsx`.
  it("writes one sheet per named list element", {
    skip_if_not_installed("writexl")
    out_dir <- tempfile("agg")
    dir.create(out_dir)
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    by_endpoint <- aggregate_mortality(grid_at(), at = "location", by = "endpoint")
    by_age <- aggregate_mortality(grid_at(), at = "location", by = "age")
    path <- write_mortality_xlsx(
      list(endpoint = by_endpoint, age = by_age),
      out_dir, suffix = "scenarios"
    )

    expect_match(basename(path), "^scenarios\\.xlsx$")
    expect_setequal(readxl::excel_sheets(path), c("endpoint", "age"))
  })

  # GIVEN a path whose directory does not exist,
  # WHEN write_mortality_xlsx() is called,
  # THEN it stops instead of silently creating user directories.
  it("refuses to create missing output directories", {
    expect_error(
      write_mortality_xlsx(
        data.frame(a = 1), file.path(tempfile("nope"), "out")
      ),
      "Output directory does not exist"
    )
  })

  # GIVEN a directory but no file name,
  # WHEN write_mortality_xlsx() is called,
  # THEN it stops and asks the caller for the name, because the package never
  # invents an output file name.
  it("refuses to invent a file name for a directory", {
    out_dir <- tempfile("agg")
    dir.create(out_dir)
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

    expect_error(
      write_mortality_xlsx(data.frame(a = 1), out_dir),
      "pass the full file path"
    )
  })
})
