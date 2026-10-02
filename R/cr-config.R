# An age list nobody would write on purpose: a guard against a configuration
# that expands into a huge sequence (the file may come from somewhere else).
.MAX_CR_AGES <- 100

# ── C-R model configuration ─────────────────────────────────────────────
#
# The metadata of every concentration-response model -- which lookup table,
# which concentration column, which endpoints apply to which ages -- lives in
# a JSON config, not in code. The shipped default is
# `inst/extdata/cr_models.json`; `cr_config(path =)` reads a user config and
# resolves its relative lookup paths against the config file's own directory,
# never the working directory.
#
# Design: diagnosis/design_json_crf_migration_260930.md (section 3). The
# config is metadata only -- the tables themselves stay in data/*.rda, and
# nothing is ever written back.

.cr_schema_version <- 1L
.cr_default_path <- function() {
  system.file("extdata", "cr_models.json", package = "AttrMort")
}

.cr_field_error <- function(field, msg) {
  .abort("CR config `{field}`: {msg}")
}

.cr_or <- function(x, y) if (is.null(x)) y else x

# Accept either an already-parsed config or a path (or NULL for the default).
.as_cr_config <- function(config) {
  if (inherits(config, "attr_cr_config")) {
    return(config)
  }
  if (is.null(config) || is.character(config)) {
    return(cr_config(config))
  }
  .abort(str_c(
    "`config` must be NULL, a path to a JSON config, or a `cr_config()` object. ",
    "Got: {paste(class(config), collapse = \"/\")}."
  ))
}

# `ages` accepts a range object ({from,to,by}) or an explicit vector; both are
# normalised to a strictly increasing character vector.
.cr_ages <- function(ages, field) {
  if (is.list(ages) && !is.null(ages$from)) {
    from <- ages$from
    to   <- .cr_or(ages$to, from)
    by   <- .cr_or(ages$by, 5)
    extra <- setdiff(names(ages), c("from", "to", "by"))
    if (length(extra) > 0) {
      .cr_field_error(field, paste0("unknown age field(s): ",
                                    paste(extra, collapse = ", ")))
    }
    if (!is.numeric(from) || !is.numeric(to) || !is.numeric(by) ||
        length(from) != 1 || length(to) != 1 || length(by) != 1 ||
        anyNA(c(from, to, by)) || by <= 0 || to < from) {
      .cr_field_error(field, "age range needs numeric from <= to and by > 0")
    }
    if ((to - from) %% by > 1e-8) {
      .cr_field_error(field, "age range is not an exact multiple of `by`")
    }
    # The range comes from a file the caller may not have written: check how
    # many ages it asks for before allocating them.
    n_ages <- (to - from) / by + 1
    if (n_ages > .MAX_CR_AGES) {
      .abort(str_c(
        "Age range in the CR configuration looks wrong: `from = ", from,
        "`, `to = ", to, "`, `by = ", by, "` asks for ", n_ages,
        " age groups, more than the ", .MAX_CR_AGES, " allowed. ",
        "Check the `ages` field of the model."
      ))
    }
    return(as.character(seq(from, to, by)))
  }

  v <- unlist(ages, use.names = FALSE)
  if (length(v) == 0) {
    .cr_field_error(field, "ages must not be empty")
  }
  if (length(v) > .MAX_CR_AGES) {
    .abort(str_c(
      "The CR configuration lists ", length(v), " age groups for `", field,
      "`, more than the ", .MAX_CR_AGES, " allowed. Check the `ages` field ",
      "of the model."
    ))
  }
  a <- suppressWarnings(as.numeric(v))
  if (anyNA(a)) {
    .cr_field_error(field, "ages must all be numeric")
  }
  if (is.unsorted(a, strictly = TRUE)) {
    .cr_field_error(field, "ages must be strictly increasing")
  }
  as.character(a)
}

.cr_lookup <- function(lookup, field) {
  if (!is.list(lookup)) {
    .cr_field_error(field, "must be an object")
  }
  known <- c("kind", "table", "path", "sheets")
  extra <- setdiff(names(lookup), known)
  if (length(extra) > 0) {
    .cr_field_error(field, paste0("unknown field(s): ", paste(extra, collapse = ", ")))
  }
  kind <- lookup$kind
  if (!is.character(kind) || length(kind) != 1 ||
      !kind %in% c("rda", "xlsx", "csv")) {
    .cr_field_error(paste0(field, ".kind"),
                    "must be one of \"rda\", \"xlsx\", \"csv\"")
  }
  if (kind == "rda") {
    if (!is.character(lookup$table) || length(lookup$table) != 1 ||
        !nzchar(lookup$table)) {
      .cr_field_error(paste0(field, ".table"), "is required when kind = \"rda\"")
    }
    if (!is.null(lookup$path)) {
      .cr_field_error(paste0(field, ".path"), "is not used when kind = \"rda\"")
    }
  } else {
    if (!is.character(lookup$path) || length(lookup$path) != 1 ||
        !nzchar(lookup$path)) {
      .cr_field_error(paste0(field, ".path"),
                      paste0("is required when kind = \"", kind, "\""))
    }
    if (!is.null(lookup$table)) {
      .cr_field_error(paste0(field, ".table"), "is not used for file lookups")
    }
  }
  if (!is.null(lookup$sheets)) {
    if (!is.list(lookup$sheets) || length(lookup$sheets) < 1) {
      .cr_field_error(paste0(field, ".sheets"), "must be a non-empty object")
    }
    if (kind == "rda") {
      .cr_field_error(paste0(field, ".sheets"),
                      "is only used for xlsx/csv lookups")
    }
    bad_keys <- setdiff(names(lookup$sheets), c("MEAN", "LOW", "UP"))
    if (length(bad_keys) > 0) {
      .cr_field_error(paste0(field, ".sheets"),
                      paste0("unknown branch(es): ", paste(bad_keys, collapse = ", ")))
    }
    for (branch in names(lookup$sheets)) {
      v <- lookup$sheets[[branch]]
      if (!is.character(v) || length(v) != 1 || !nzchar(v)) {
        .cr_field_error(paste0(field, ".sheets.", branch),
                        "must be a single non-empty string")
      }
    }
  }
  list(kind = kind, table = lookup$table, path = lookup$path,
       sheets = lookup$sheets)
}

.cr_endpoints <- function(endpoints, model, field) {
  if (!is.list(endpoints) || length(endpoints) == 0) {
    .cr_field_error(field, "must be a non-empty array")
  }
  out <- vector("list", length(endpoints))
  seen <- character(0)
  for (i in seq_along(endpoints)) {
    ep <- endpoints[[i]]
    f  <- sprintf("%s[%d]", field, i)
    if (!is.list(ep)) {
      .cr_field_error(f, "must be an object")
    }
    extra <- setdiff(names(ep), c("name", "lookup", "ages"))
    if (length(extra) > 0) {
      .cr_field_error(f, paste0("unknown field(s): ", paste(extra, collapse = ", ")))
    }
    name <- ep$name
    if (!is.character(name) || length(name) != 1 || !nzchar(name)) {
      .cr_field_error(paste0(f, ".name"), "must be a non-empty string")
    }
    key <- tolower(name)
    if (key %in% seen) {
      .cr_field_error(paste0(f, ".name"),
                      paste0("duplicate endpoint \"", name, "\" in model ", model))
    }
    seen <- c(seen, key)
    src <- .cr_or(ep$lookup, name)
    if (!is.character(src) || length(src) != 1 || !nzchar(src)) {
      .cr_field_error(paste0(f, ".lookup"), "must be a non-empty string")
    }
    out[[i]] <- list(
      name   = name,
      lookup = src,
      ages   = .cr_ages(ep$ages, paste0(f, ".ages"))
    )
  }
  out
}

.cr_normalise <- function(raw) {
  if (!is.list(raw)) {
    .cr_field_error("root", "must be a JSON object")
  }
  extra <- setdiff(names(raw), c("schema_version", "models"))
  if (length(extra) > 0) {
    .cr_field_error("root", paste0("unknown field(s): ", paste(extra, collapse = ", ")))
  }
  if (!identical(as.integer(raw$schema_version), .cr_schema_version)) {
    .cr_field_error(
      "schema_version",
      paste0("expected ", .cr_schema_version, ", got ",
             paste(raw$schema_version, collapse = ", "))
    )
  }
  models <- raw$models
  if (!is.list(models) || length(models) == 0) {
    .cr_field_error("models", "must be a non-empty object")
  }
  if (any(!nzchar(names(models)))) {
    .cr_field_error("models", "every model needs a name")
  }

  out <- list()
  alias_owner <- character(0)
  for (nm in names(models)) {
    m  <- models[[nm]]
    f  <- paste0("models.", nm)
    if (!is.list(m)) {
      .cr_field_error(f, "must be an object")
    }
    extra <- setdiff(names(m), c("label", "aliases", "lookup", "conc_col", "endpoints"))
    if (length(extra) > 0) {
      .cr_field_error(f, paste0("unknown field(s): ", paste(extra, collapse = ", ")))
    }
    aliases <- unlist(m$aliases, use.names = FALSE)
    if (length(aliases) > 0) {
      if (!is.character(aliases) || any(!nzchar(aliases))) {
        .cr_field_error(paste0(f, ".aliases"), "must be non-empty strings")
      }
      if (anyDuplicated(toupper(aliases)) > 0) {
        .cr_field_error(paste0(f, ".aliases"), "contains duplicates")
      }
      clash <- aliases[toupper(aliases) %in% c(toupper(names(models)),
                                               toupper(alias_owner))]
      if (length(clash) > 0) {
        .cr_field_error(paste0(f, ".aliases"),
                        paste0("name(s) already in use: ", paste(clash, collapse = ", ")))
      }
      alias_owner <- c(alias_owner, aliases)
    }
    label <- .cr_or(m$label, NA_character_)
    if (!is.character(label) || length(label) != 1) {
      .cr_field_error(paste0(f, ".label"), "must be a single string")
    }
    conc_col <- .cr_or(m$conc_col, "conc")
    if (!is.character(conc_col) || length(conc_col) != 1 || !nzchar(conc_col)) {
      .cr_field_error(paste0(f, ".conc_col"), "must be a non-empty string")
    }
    out[[nm]] <- list(
      name      = nm,
      label     = label,
      aliases   = as.character(aliases),
      lookup    = .cr_lookup(m$lookup, paste0(f, ".lookup")),
      conc_col  = conc_col,
      endpoints = .cr_endpoints(m$endpoints, nm, paste0(f, ".endpoints"))
    )
  }
  out
}

#' Read a concentration-response model configuration
#'
#' Loads and validates the JSON metadata that describes the built-in and
#' user-supplied concentration-response models: which lookup table a model
#' uses, which column carries the concentration axis, and which endpoints
#' apply to which ages. The shipped default lives in
#' `inst/extdata/cr_models.json`.
#'
#' A user config is read from `path`; relative lookup paths inside it are
#' resolved against the directory of the config file, never against the
#' working directory. Nothing is ever written back.
#'
#' @param path Character path to a JSON config, or `NULL` (default) for the
#'   shipped `cr_models.json`.
#'
#' @return An object of class `attr_cr_config`: a list with the parsed
#'   `schema_version`, the normalised `models`, and the resolved config
#'   `path`.
#'
#' @seealso [cr_models()], [rr_std()]
#'
#' @export
#'
#' @examples
#' cfg <- cr_config()
#' names(cfg$models)
#' str(cfg$models$NO2, max.level = 1)
cr_config <- function(path = NULL) {
  if (is.null(path)) {
    path <- .cr_default_path()
    if (!nzchar(path)) {
      .abort("The shipped `cr_models.json` could not be found.")
    }
  } else {
    if (!is.character(path) || length(path) != 1 || is.na(path)) {
      .abort("`path` must be NULL or a single file path.")
    }
    if (!file.exists(path)) {
      .abort("CR config not found: {path}")
    }
    if (dir.exists(path)) {
      .abort("CR config path is a directory, not a file: {path}")
    }
  }

  raw <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      .abort("Cannot parse CR config {path}: {conditionMessage(e)}")
    }
  )
  models <- .cr_normalise(raw)
  structure(
    list(schema_version = .cr_schema_version, models = models,
         path = normalizePath(path, mustWork = FALSE)),
    class = "attr_cr_config"
  )
}

# Resolve a CRF name (or alias, case-insensitively) to its config entry.
.cr_model_entry <- function(config, crf) {
  if (!is.character(crf) || length(crf) != 1 || is.na(crf)) {
    .abort("`crf` must be a single character string.")
  }
  key <- toupper(trimws(crf))
  for (nm in names(config$models)) {
    entry <- config$models[[nm]]
    if (key == toupper(nm) || key %in% toupper(entry$aliases)) {
      return(entry)
    }
  }
  .abort(str_c(
    "Unknown CR model \"{crf}\". Valid models: ",
    "{paste(cr_models(config), collapse = \", \")}."
  ))
}

#' Valid CR model names
#'
#' @param config Optional configuration object from [cr_config()], or a path
#'   to a config file. `NULL` (default) uses the shipped config.
#'
#' @return Character vector of accepted `crf`/`cr_model` values, including
#'   aliases.
#'
#' @export
#' @examples
#' cr_models()
cr_models <- function(config = NULL) {
  config <- .as_cr_config(config)
  out <- character(0)
  for (nm in names(config$models)) {
    out <- c(out, nm, config$models[[nm]]$aliases)
  }
  out
}

#' Print a concentration-response model configuration
#'
#' Shows the schema version, the number of models and where the configuration
#' was read from.
#'
#' @param x An `attr_cr_config` object, as returned by [cr_config()].
#' @param ... Ignored, for compatibility with the `print()` generic.
#'
#' @return `x`, invisibly.
#' @export
#' @examples
#' print(cr_config())
print.attr_cr_config <- function(x, ...) {
  cat("<attr_cr_config> schema ", x$schema_version, ", ",
      length(x$models), " model(s): ", paste(names(x$models), collapse = ", "),
      "\n", sep = "")
  cat("config: ", x$path, "\n", sep = "")
  invisible(x)
}
