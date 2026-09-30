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
})
