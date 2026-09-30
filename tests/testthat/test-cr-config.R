# Tests for the C-R model configuration (cr_config / cr_models)

.write_cfg <- function(lines) {
  f <- tempfile(fileext = ".json")
  writeLines(lines, f)
  f
}

# Minimal valid model body, for the validation tests.
.cfg_with_model <- function(model_body) {
  .write_cfg(c(
    '{"schema_version": 1, "models": {',
    paste0('"X": ', model_body),
    '}}'
  ))
}

describe("cr_config()", {
  it("loads the shipped default config", {
    cfg <- cr_config()
    expect_s3_class(cfg, "attr_cr_config")
    expect_equal(cfg$schema_version, 1L)
    expect_true(all(c("GEMM", "IER2017", "MRBRT2021", "O3", "NO2") %in%
                      names(cfg$models)))
    expect_match(cfg$path, "cr_models[.]json$")
  })

  it("expands both ages forms", {
    cfg  <- cr_config()
    gemm <- cfg$models$GEMM$endpoints[[1]]
    expect_equal(gemm$ages, as.character(seq(25, 95, 5)))

    lri <- cfg$models$IER2017$endpoints[[5]]
    expect_equal(lri$name, "lri")
    expect_equal(lri$ages, "0")

    f <- .cfg_with_model(
      '{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": {"from": 25, "to": 35}}]}'
    )
    expect_equal(cr_config(f)$models$X$endpoints[[1]]$ages,
                 c("25", "30", "35"))
  })

  it("keeps the NO2 endpoint rename separate from its lookup prefix", {
    no2 <- cr_config()$models$NO2$endpoints[[1]]
    expect_equal(no2$name, "allcause")
    expect_equal(no2$lookup, "cause")
    expect_equal(no2$ages, as.character(seq(15, 95, 5)))
  })

  it("resolves aliases case-insensitively", {
    cfg <- cr_config()
    expect_equal(AttrMort:::.cr_model_entry(cfg, "ier")$name, "IER2017")
    expect_equal(AttrMort:::.cr_model_entry(cfg, "  MRBRT ")$name, "MRBRT2021")
    expect_equal(AttrMort:::.cr_model_entry(cfg, "ncd+lri")$name, "GEMM")
    expect_error(AttrMort:::.cr_model_entry(cfg, "nope"), "Unknown CR model")
  })

  it("describes exactly the endpoints and ages RR_std() produces", {
    cfg <- cr_config()
    for (model in cr_models(cfg)) {
      entry <- AttrMort:::.cr_model_entry(cfg, model)
      produced <- unique(RR_std(model, "MEAN")[, c("endpoint", "age")])
      declared <- do.call(rbind, lapply(entry$endpoints, function(ep) {
        data.frame(endpoint = tolower(ep$name), age = ep$ages,
                   stringsAsFactors = FALSE)
      }))
      key <- function(d) paste(d$endpoint, d$age, sep = "@")
      expect_setequal(key(produced), key(declared))
    }
  })

  it("reads a user config and keeps its lookup specification", {
    f <- .write_cfg(c(
      '{"schema_version": 1, "models": {',
      '  "X": { "lookup": {"kind": "xlsx", "path": "lookups/x.xlsx"},',
      '         "conc_col": "concentration", "label": "my model",',
      '         "endpoints": [{"name": "ihd", "ages": [25, 30]}] }',
      '}}'
    ))
    cfg <- cr_config(f)
    expect_equal(names(cfg$models), "X")
    expect_equal(cfg$models$X$label, "my model")
    expect_equal(cfg$models$X$lookup$kind, "xlsx")
    expect_equal(cfg$models$X$lookup$path, "lookups/x.xlsx")
    expect_equal(cfg$models$X$conc_col, "concentration")
    expect_equal(cfg$models$X$endpoints[[1]]$ages, c("25", "30"))
    expect_equal(cfg$models$X$endpoints[[1]]$lookup, "ihd")
  })
})

describe("cr_config() validation", {
  it("rejects an unknown schema version", {
    f <- .write_cfg('{"schema_version": 2, "models": {"X": {}}}')
    expect_error(cr_config(f), "schema_version")
  })

  it("rejects unknown fields at every level", {
    f <- .write_cfg(
      '{"schema_version": 1, "extra": 1, "models": {"X": {}}}'
    )
    expect_error(cr_config(f), "unknown field")

    f <- .cfg_with_model(
      '{"lookup": {"kind": "rda", "table": "T", "bogus": 1}, "endpoints": [{"name": "x", "ages": [1]}]}'
    )
    expect_error(cr_config(f), "unknown field")

    f <- .cfg_with_model(
      '{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": [1], "bogus": 1}]}'
    )
    expect_error(cr_config(f), "unknown field")
  })

  it("rejects empty models and empty endpoints", {
    f <- .write_cfg('{"schema_version": 1, "models": {}}')
    expect_error(cr_config(f), "non-empty object")

    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T"}, "endpoints": []}')
    expect_error(cr_config(f), "non-empty array")
  })

  it("rejects bad lookup specifications", {
    f <- .cfg_with_model('{"lookup": {"kind": "parquet"}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "kind")

    f <- .cfg_with_model('{"lookup": {"kind": "rda"}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "table")

    f <- .cfg_with_model('{"lookup": {"kind": "xlsx"}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "path")
  })

  it("rejects bad ages", {
    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": [30, 25]}]}')
    expect_error(cr_config(f), "strictly increasing")

    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": ["a"]}]}')
    expect_error(cr_config(f), "numeric")

    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": {"from": 25, "to": 90, "by": 10}}]}')
    expect_error(cr_config(f), "exact multiple")
  })

  it("rejects alias collisions and duplicate endpoints", {
    f <- .write_cfg(c(
      '{"schema_version": 1, "models": {',
      '"A": {"aliases": ["B"], "lookup": {"kind": "rda", "table": "T"},',
      '      "endpoints": [{"name": "x", "ages": [1]}]},',
      '"B": {"lookup": {"kind": "rda", "table": "T"},',
      '      "endpoints": [{"name": "x", "ages": [1]}]}',
      '}}'
    ))
    expect_error(cr_config(f), "already in use")

    f <- .cfg_with_model(
      '{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": [1]}, {"name": "X", "ages": [2]}]}'
    )
    expect_error(cr_config(f), "duplicate endpoint")
  })

  it("reports the offending field path", {
    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T"}, "endpoints": [{"name": "x", "ages": [30, 25]}]}')
    expect_error(cr_config(f), "models.X.endpoints\\[1\\].ages")
  })

  it("rejects bad sheets and duplicate aliases", {
    f <- .cfg_with_model('{"lookup": {"kind": "xlsx", "path": "x.xlsx", "sheets": {"MEAN": 1}}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "sheets")

    f <- .cfg_with_model('{"lookup": {"kind": "xlsx", "path": "x.xlsx", "sheets": {"NOPE": "S"}}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "unknown branch")

    f <- .cfg_with_model('{"lookup": {"kind": "rda", "table": "T", "sheets": {"MEAN": "S"}}, "endpoints": [{"name": "x", "ages": [1]}]}')
    expect_error(cr_config(f), "only used for xlsx/csv")

    f <- .write_cfg(c(
      '{"schema_version": 1, "models": {',
      '"A": {"aliases": ["X", "x"], "lookup": {"kind": "rda", "table": "T"},',
      '      "endpoints": [{"name": "e", "ages": [1]}]}',
      '}}'
    ))
    expect_error(cr_config(f), "duplicates")
  })

  it("rejects a directory as the config path", {
    expect_error(cr_config(tempdir()), "directory")
  })
})

describe("lookup coverage", {
  it("errors when a configured endpoint is absent from the lookup", {
    f <- .write_cfg(c(
      '{"schema_version": 1, "models": {',
      '"BAD": {"lookup": {"kind": "rda", "table": "GEMM_Lookup_Table"},',
      ' "endpoints": [{"name": "xyz", "ages": [25, 30]}]}',
      '}}'
    ))
    expect_error(RR_std("BAD", config = f), "no columns for endpoint")
  })

  it("carries the nearest previous age forward when a later age has no column", {
    dir <- file.path(tempdir(), "attrmort-cr-hole")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    tab <- data.frame(concentration = c("10", "20"), ihd_25 = c(1.1, 1.2))
    readr::write_csv(tab, file.path(dir, "MEAN.csv"))
    readr::write_csv(tab, file.path(dir, "LOW.csv"))
    readr::write_csv(tab, file.path(dir, "UP.csv"))
    f <- file.path(dir, "cr_config.json")
    writeLines(c(
      '{"schema_version": 1, "models": {',
      '"HOLED": {"lookup": {"kind": "csv", "path": "."},',
      ' "conc_col": "concentration",',
      ' "endpoints": [{"name": "ihd", "ages": [25, 30]}]}',
      '}}'
    ), f)

    # Legacy semantics, pinned by the GEMM 85/90/95 columns: age 30 inherits
    # age 25. The lookup-coverage check only requires an anchor (first age or
    # `_ALL`), and the NA guard catches a lookup with no anchor at all.
    out <- RR_std("HOLED", config = f)
    expect_equal(out$RR[out$conc == "10" & out$age == "30"], 1.1)
    expect_equal(out$RR[out$conc == "20" & out$age == "30"], 1.2)
  })

  it("errors when the CI branches do not carry the same columns", {
    dir <- file.path(tempdir(), "attrmort-cr-branches")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    readr::write_csv(data.frame(concentration = "10", ihd_25 = 1.1),
                     file.path(dir, "MEAN.csv"))
    readr::write_csv(data.frame(concentration = "10", ihd_30 = 1.2),
                     file.path(dir, "LOW.csv"))
    readr::write_csv(data.frame(concentration = "10", ihd_25 = 1.0),
                     file.path(dir, "UP.csv"))
    f <- file.path(dir, "cr_config.json")
    writeLines(c(
      '{"schema_version": 1, "models": {',
      '"SPLIT": {"lookup": {"kind": "csv", "path": "."},',
      ' "conc_col": "concentration",',
      ' "endpoints": [{"name": "ihd", "ages": [25]}]}',
      '}}'
    ), f)
    expect_error(RR_std("SPLIT", config = f), "share the same columns")
  })
})

# Custom-model end-to-end: user config + file lookup, no package data touched.
.write_custom_lookup <- function(dir) {
  tab <- data.frame(
    concentration = c("10", "20"),
    ihd_25 = c(1.10, 1.20),
    ihd_30 = c(1.30, 1.40)
  )
  low <- tab; low[2:3] <- tab[2:3] - 0.05
  up  <- tab; up[2:3]  <- tab[2:3] + 0.05
  lookup_dir <- file.path(dir, "lookups")
  dir.create(lookup_dir, showWarnings = FALSE, recursive = TRUE)
  writexl::write_xlsx(list(MEAN = tab, LOW = low, UP = up),
                      file.path(lookup_dir, "x.xlsx"))

  csv_dir <- file.path(dir, "csvdir")
  dir.create(csv_dir, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(tab, file.path(csv_dir, "MEAN.csv"))
  readr::write_csv(low, file.path(csv_dir, "LOW.csv"))
  readr::write_csv(up,  file.path(csv_dir, "UP.csv"))
  invisible(dir)
}

.custom_config <- function(dir, kind = "xlsx", sheets = NULL) {
  lookup <- if (kind == "xlsx") {
    sprintf('{"kind": "xlsx", "path": "lookups/x.xlsx"%s}', sheets %||% "")
  } else {
    sprintf('{"kind": "csv", "path": "csvdir"%s}', sheets %||% "")
  }
  # The config must live in `dir` for its relative lookup paths to resolve
  # against the config directory (which is exactly what we are testing).
  f <- file.path(dir, "cr_config.json")
  writeLines(c(
    '{"schema_version": 1, "models": {',
    paste0('"MYX": {"lookup": ', lookup, ', "conc_col": "concentration",',
           ' "endpoints": [{"name": "ihd", "ages": [25, 30]}]}'),
    '}}'
  ), f)
  f
}

describe("custom models from file lookups", {
  it("builds the standard long table from a user xlsx", {
    dir <- file.path(tempdir(), "attrmort-cr-xlsx")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    .write_custom_lookup(dir)
    cfg <- cr_config(.custom_config(dir))

    out <- RR_std("MYX", "MEAN", config = cfg)
    expect_equal(names(out), c("conc", "endpoint", "age", "RR"))
    expect_equal(unique(out$endpoint), "ihd")
    expect_equal(sort(unique(out$age)), c("25", "30"))
    expect_equal(out$RR[out$conc == "10" & out$age == "25"], 1.10)
    expect_equal(out$RR[out$conc == "20" & out$age == "30"], 1.40)

    up <- RR_std("MYX", "UP", config = cfg)
    expect_equal(up$RR[up$conc == "10" & up$age == "25"], 1.15)
  })

  it("builds the same table from a csv directory", {
    dir <- file.path(tempdir(), "attrmort-cr-csv")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    .write_custom_lookup(dir)
    cfg <- cr_config(.custom_config(dir, kind = "csv"))

    out <- RR_std("MYX", "MEAN", config = cfg)
    expect_equal(nrow(out), 4)
    expect_equal(out$RR[out$conc == "20" & out$age == "30"], 1.40)
  })

  it("runs through Mortality() with cr_config =", {
    dir <- file.path(tempdir(), "attrmort-cr-run")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    .write_custom_lookup(dir)
    cfg_path <- .custom_config(dir)

    d <- .attr_small_long()
    d$conc_real$conc <- c("10", "20", "10", "20")
    d$mort_rate <- data.frame(
      location = "A", age = c("25", "30"), endpoint = "ihd",
      mortrate = c(1000, 2000)
    )
    out <- Mortality(
      CRF = "MYX", cr_config = cfg_path, calc_fild = d$calc_fild,
      conc_real = d$conc_real, pop_total = d$pop_total,
      age_struc = d$age_struc, mort_rate = d$mort_rate,
      mort_lvl = "location", validate = "off"
    )
    expect_equal(nrow(out), 4)
    expect_true(all(c("ihd_25", "ihd_30") %in% names(out)))
  })

  it("reports missing sheets, missing concentration columns and bad paths", {
    dir <- file.path(tempdir(), "attrmort-cr-errors")
    unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
    .write_custom_lookup(dir)

    bad_sheet <- .custom_config(
      dir, sheets = ', "sheets": {"MEAN": "NOPE", "LOW": "LOW", "UP": "UP"}'
    )
    expect_error(RR_std("MYX", config = bad_sheet))

    bad_path <- file.path(dir, "bad_path.json")
    writeLines(c(
      '{"schema_version": 1, "models": {',
      '"MYX": {"lookup": {"kind": "xlsx", "path": "missing.xlsx"},',
      ' "endpoints": [{"name": "ihd", "ages": [25]}]}',
      '}}'
    ), bad_path)
    expect_error(RR_std("MYX", config = bad_path), "not found")

    no_conc <- file.path(dir, "no_conc.json")
    writeLines(c(
      '{"schema_version": 1, "models": {',
      '"MYX": {"lookup": {"kind": "csv", "path": "csvdir"},',
      ' "conc_col": "nope",',
      ' "endpoints": [{"name": "ihd", "ages": [25]}]}',
      '}}'
    ), no_conc)
    expect_error(RR_std("MYX", config = no_conc), "nope")
  })
})
