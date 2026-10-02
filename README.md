# AttrMort

`AttrMort` estimates the mortality attributable to ambient air pollution
exposure. It is **pollutant-agnostic** -- PM<sub>2.5</sub>, O<sub>3</sub> and
NO<sub>2</sub> curves are built in, and any other pollutant or endpoint set can
be supplied as a lookup table or as a JSON configuration -- and
**input-agnostic**: data frames, CSV/Excel files, gridded GeoTIFF/netCDF
rasters and spatial vector layers are read, aligned and joined automatically.

The package is **self-contained**: the only bundled curves are the
concentration-response (C-R) lookup tables in `data/`, and every file in
`inst/extdata/` is synthetic.

Requires R >= 4.1 (native pipe `|>`).

## Installation

```r
# from GitHub; needs internet and devtools
# install.packages("devtools")
devtools::install_github("evanliu3594/AttrMort")
library(AttrMort)
```

The examples below read the example workbooks with `readxl` (an `Imports`
dependency of the package). Writing xlsx output additionally needs `writexl`,
which is a `Suggests` dependency.

## Quick start: one attribution run

The shipped example is three fictional countries on a 0.25 degree grid
(`grid_info`, `grid_exposure`, `grid_pop`) plus national tables
(`national_age_structure`, `national_mortality`). Wide tables carry one column
per scenario (`base2015`, `scenario2030`); `scenario =` narrows each input to
one of them:

```r
library(AttrMort)

extdata <- system.file("extdata", package = "AttrMort")
sheet <- function(f) readxl::read_excel(file.path(extdata, f))

deaths <- mortality(
  crf       = "GEMM",
  calc_fild = sheet("grid_info.xlsx"),
  conc_real = sheet("grid_exposure.xlsx"),
  pop_total = sheet("grid_pop.xlsx"),
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",
  mort_lvl  = "location"
)

# one row per grid cell, one `{endpoint}_{age}` column per stratum
deaths[1:3, c("x", "y", "location", "ncd+lri_25")]
```

What the call does, argument by argument:

* `crf = "GEMM"` selects the C-R model. `cr_models()` lists every accepted
  name, aliases included; a data.frame is accepted instead (see
  *Custom concentration-response functions*).
* `calc_fild` is the attribution field, the spatial skeleton every other input
  is joined onto. Here it is the `x`/`y`/`location` table of the example grid.
* `conc_real`, `pop_total`, `age_struc`, `mort_rate` are the four value inputs:
  exposure, population, age structure (proportion in `prop`) and baseline
  cause-specific mortality in **deaths per 100,000**.
* `scenario = "base2015"` is a **per-input column selector**, not a contract
  across inputs: an input without that column is used as it is when it has its
  canonical value column (`conc`, `pop`, `prop`, `mortrate`) or a single
  numeric value column. The package never judges whether the inputs belong to
  the same scenario or year. When several value columns are possible and none
  is canonical, the call stops and lists them instead of picking one.
* `mort_lvl = "location"` is the domain used to calibrate the
  population-weighted relative risk (PWRR). `mort_lvl = NULL` skips
  calibration and computes at the finest available level -- a different
  quantity, not a numerically identical shortcut.

The run prints one `Analysis grain:` line saying where the analysis lives (how
many cells, how many domains, at which resolution) and which calibration
branch it took, so the grain is never dispatched silently:

```r
# Analysis grain: <n> cell(s) in <m> domain(s) on a <res> deg grid;
# PWRR calibrated per domain.
```

It also reports inputs that contribute nothing, e.g. endpoints of `mort_rate`
that the chosen C-R model does not use.

## Decomposing a change between two groups

`decompose()` compares **two complete sets of inputs** -- two groups, `from`
and `to` -- and splits the change in attributable deaths among four drivers:
population growth (`PG`), ageing (`PA`), exposure (`EXP`) and the
other risk factors `ORF` (real exposure and baseline mortality rate). Each
group is a list holding one table per role, so **the scenario is selected
before the call**: `decompose()` compares two datasets and has no argument
that picks a column for you.

```r
grid_info <- sheet("grid_info.xlsx")
age_struc <- sheet("national_age_structure.xlsx")
mort_rate <- sheet("national_mortality.xlsx")
exposure  <- sheet("grid_exposure.xlsx")
pop       <- sheet("grid_pop.xlsx")

# one value column per role; `label` only names the group in the summary
as_group <- function(scenario, label) {
  list(
    label     = label,
    conc_real = data.frame(exposure[c("x", "y")],
                           conc = exposure[[scenario]]),
    pop_total = data.frame(pop[c("x", "y")],
                           pop = pop[[scenario]]),
    age_struc = data.frame(age_struc[c("location", "age")],
                           prop = age_struc[[scenario]]),
    mort_rate = data.frame(mort_rate[c("location", "age", "endpoint")],
                           mortrate = mort_rate[[scenario]])
  )
}

res <- decompose(
  crf       = "GEMM",
  calc_fild = grid_info,
  mort_lvl  = "location",
  from      = as_group("base2015", "base2015"),
  to        = as_group("scenario2030", "scenario2030")
)
```

A group accepts `conc_real`, `pop_total`, `age_struc`, `mort_rate` (each a
data.frame or a file path) and optionally `conc_cf`, its counterfactual
exposure, which defaults to that group's own `conc_real`. `label` is cosmetic.

The return value is a **named list of 24 data frames**, one per ordering of
the four drivers (`"PG-PA-EXP-ORF"`, `"PG-PA-ORF-EXP"`, ...). Each table holds
the key columns, `Cause_Age`, `Start`, the four driver columns **in the order
that ordering moves them**, and `End` -- one row per grid cell and age
stratum:

```r
res[["PG-PA-EXP-ORF"]][1:3, c("x", "y", "Cause_Age", "Start", "End")]

# per row: Start + PG + PA + EXP + ORF == End
```

A driver that has already moved reads the `to` group, so each driver column
isolates the driver it is named after, `Start` is the `from` group and `End`
the `to` group. The 24 orderings share **16 states** (one per subset of the
four drivers), so a full decomposition is 16 calculations, not 24 x 5, and the
concentration-response table is built once. `Start` and `End` are identical in
all 24 tables.

The orderings disagree by construction -- moving the same drivers in a
different order attributes part of the change to a different one. The
order-independent reading is therefore their **mean**:

```r
drivers     <- c("PG", "PA", "EXP", "ORF")
mean_driver <- Reduce(`+`, lapply(res, function(x) x[drivers])) / length(res)

# one row per cell x age stratum, one column per driver
head(mean_driver, 3)
```

A cell and stratum that some state cannot compute (no risk in the C-R table,
no domain label, or the group does not cover it) is reported as `NA` with a
warning rather than silently borrowing a neighbour's value. With
`validate = "stop"` that warning becomes an error.

## Domain-level results

`aggregate = TRUE` sums the grid-level burdens per domain, keeps the exposure
metric `conc_pwe` (population-weighted concentration) and attaches the
uncertainty range when one was asked for:

```r
by_location <- mortality(
  crf          = "GEMM",
  calc_fild    = sheet("grid_info.xlsx"),
  conc_real    = sheet("grid_exposure.xlsx"),
  pop_total    = sheet("grid_pop.xlsx"),
  age_struc    = sheet("national_age_structure.xlsx"),
  mort_rate    = sheet("national_mortality.xlsx"),
  scenario     = "base2015",
  mort_lvl     = "location",
  aggregate    = TRUE,
  uncertain    = TRUE,
  conc_uncert  = 12
)

by_location[, c("location", "total", "CI_LOW", "CI_UP", "conc_pwe")]
```

* `aggregate = TRUE` groups by `mort_lvl`; a character vector, e.g.
  `aggregate = "location"`, groups by exactly those columns of the result.
  With `mort_lvl = NULL` the whole field is aggregated into a single row.
* `aggregate_by` chooses the breakdown kept in the output: `"total"` (default,
  one `total` column), `"endpoint"` (`{endpoint}_all` columns), `"age"`
  (`all_{age}` columns) or `"all"`.
* `uncertain = TRUE` adds `CI_LOW`/`CI_UP`.
* `conc_uncert = 12` re-runs the analysis with every concentration scaled by
  `1 +/- 12%` and widens the interval to cover that range as well.

Grid-level results can also be aggregated after the fact, which is the route
to take when several scenarios are compared side by side:

```r
# sum the grid-level result within each location
aggregate_mortality(deaths, at = "location", by = "total")

# keep the endpoint breakdown
aggregate_mortality(deaths, at = "location", by = "endpoint")

# several scenarios at once: a named list in, a `scenario` column out
# (each element is one scenario's result; shown here with the same table)
scenarios <- list(base2015 = deaths, scenario2030 = deaths)
aggregate_mortality(scenarios, at = "location", by = "total")
```

`aggregate_ci()` does the same for a result whose columns carry a CI suffix
(`_MEAN`, `_UP`, `_LOW`), keeping the three branches side by side:

```r
run_branch <- function(ci) {
  mortality(
    crf = "GEMM", ci = ci,
    calc_fild = sheet("grid_info.xlsx"),
    conc_real = sheet("grid_exposure.xlsx"),
    pop_total = sheet("grid_pop.xlsx"),
    age_struc = sheet("national_age_structure.xlsx"),
    mort_rate = sheet("national_mortality.xlsx"),
    scenario = "base2015", mort_lvl = "location", validate = "off"
  )
}

append_ci <- function(x, suffix) {
  values <- setdiff(names(x), c("x", "y", "location"))
  names(x)[names(x) %in% values] <- paste0(values, suffix)
  x
}

grid_ci <- append_ci(run_branch("MEAN"), "_MEAN")
grid_ci <- dplyr::left_join(
  grid_ci, append_ci(run_branch("UPPER"), "_UP"),
  by = c("x", "y", "location")
)
grid_ci <- dplyr::left_join(
  grid_ci, append_ci(run_branch("LOWER"), "_LOW"),
  by = c("x", "y", "location")
)

aggregate_ci(grid_ci, at = "location", by = "total")
```

`write_mortality_xlsx()` writes a data.frame, or a named list of them (one
sheet each), to a caller-supplied `path`; it needs `writexl`:

```r
# path is the full file name, or a directory plus an explicit suffix
write_mortality_xlsx(by_location, path = tempdir(),
                     suffix = "location_total_2015")
```

## Inputs you can hand over

Every data argument accepts a **data.frame**, a **file path** (tables as
`.csv`, `.txt`, `.xls`, `.xlsx`; rasters as `.tif`, `.tiff`, `.nc`, ...) or,
for the gridded inputs, a `SpatRaster`. Files are read and their columns
mapped onto the canonical schema automatically:

```r
mortality(
  crf       = "GEMM",
  calc_fild = file.path(extdata, "grid_info.xlsx"),
  conc_real = file.path(extdata, "grid_exposure.xlsx"),
  pop_total = file.path(extdata, "grid_pop.xlsx"),
  age_struc = file.path(extdata, "national_age_structure.xlsx"),
  mort_rate = file.path(extdata, "national_mortality.xlsx"),
  scenario  = "base2015",
  mort_lvl  = "location"
)
```

### Column names

Column names are compared after lowercasing and dropping separators, so
`mort_rate`, `Mort Rate` and `mortrate` are the same column; a recognised
variant is renamed to the canonical name before anything else happens
(`age_group` -> `age`, `mortality_rate` -> `mortrate`, `Endpoint` ->
`endpoint`, ...). Coordinate columns are renamed to `x`/`y`, and
`lon`/`lat`, `long`/`lat`, `longitude`/`latitude` are all the same pair --
including a table that mixes spellings, such as `x` with `lat`. That is what
makes two tables that spell their keys differently join.

### Rasters

A raster exposure product already carries the analysis grid, so `calc_fild`
can be left out. `conc_real` defines the grid, `pop_total` is aggregated onto
it with the total preserved, and boundaries are rasterized onto it. This
block turns the example grid into two GeoTIFFs in a temporary directory and
runs the raster path:

```r
template <- terra::rast(xmin = 5, xmax = 30, ymin = 35, ymax = 50,
                        resolution = 0.25)
centres <- terra::xyFromCell(template, seq_len(terra::ncell(template)))
keys <- paste(round(centres[, 1], 2), round(centres[, 2], 2))

to_raster <- function(df, value) {
  r <- template
  terra::values(r) <- df[[value]][
    match(keys, paste(round(df$x, 2), round(df$y, 2)))
  ]
  r
}

conc_tif <- tempfile(fileext = ".tif")
pop_tif  <- tempfile(fileext = ".tif")
terra::writeRaster(to_raster(exposure, "base2015"), conc_tif)
terra::writeRaster(to_raster(pop, "base2015"), pop_tif)

boundary <- sf::st_sf(
  admin = c("Aland", "Borduria", "Cyrenia"),
  geometry = sf::st_sfc(
    sf::st_polygon(list(rbind(c(5, 35), c(13, 35), c(13, 50),
                              c(5, 50), c(5, 35)))),
    sf::st_polygon(list(rbind(c(13, 35), c(21, 35), c(21, 50),
                              c(13, 50), c(13, 35)))),
    sf::st_polygon(list(rbind(c(21, 35), c(30, 35), c(30, 50),
                              c(21, 50), c(21, 35)))),
    crs = 4326
  )
)

deaths_raster <- mortality(
  crf       = "GEMM",
  conc_real = conc_tif,          # defines the target grid
  pop_total = pop_tif,           # aggregated onto that grid
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",
  admin     = boundary,          # rasterized onto the grid
  mort_lvl  = "location"
)
```

`target_res` pins the resolution in degrees: one number for a square grid, or
`c(res_x, res_y)` when the axes differ. `NULL` (default) auto-detects the
finest input resolution: grids of up to 5e6 cells are confirmed silently,
larger ones interactively, and in a non-interactive session a grid above 5e7
cells falls back to 0.1 degree with a message. Non-square grids keep their
resolution **per axis** -- the two numbers are never averaged.

### A vector map as `calc_fild`

A spatial vector layer (`sf`, or a path to a `.shp`/`.gpkg`/`.geojson`) passed
as `calc_fild` is treated as a **boundary source**: the grid still comes from
the exposure, and the map's polygons label the cells. `admin_col` says which
column of the map holds the names; the default is `"admin"`, and when that
column is absent the first character column is used with a warning. The label
column is renamed to the resolved `mort_lvl` (usually `location`):

```r
deaths_map <- mortality(
  crf       = "GEMM",
  calc_fild = boundary,          # the grid comes from the exposure
  conc_real = exposure,
  pop_total = pop,
  age_struc = age_struc,
  mort_rate = mort_rate,
  scenario  = "base2015",
  mort_lvl  = "location"
)

# the map's `admin` column labels the cells and is renamed to `location`
```

Passing the boundaries both as `calc_fild` and as `admin` is an error: they
are two boundary sources for one grid.

### `calc_fild = NULL`

For a **raster** `conc_real` the skeleton is the raster grid itself, so
`calc_fild` is optional. For a **table** with coordinate columns the skeleton
is the exposure's own cells, and the run reports how many coordinate pairs it
used:

```r
# the run reports how many coordinate pair(s) of `conc_real` became the grid
deaths_table <- mortality(
  crf       = "GEMM",
  conc_real = exposure,
  pop_total = pop,
  age_struc = age_struc,
  mort_rate = mort_rate,
  scenario  = "base2015",
  admin     = boundary,          # supplies the domain labels
  mort_lvl  = "location"
)
```

The skeleton built that way holds coordinates only. The domain-keyed inputs
(`age_struc`, `mort_rate`) therefore need a domain column, which comes from
`admin` (boundaries) or from a `calc_fild` that carries one. If the exposure
has already been aggregated to domains it has no coordinates at all, and
`calc_fild` -- `build_grid_info()` writes one -- must be supplied.

### `admin` and the national fallback

`admin` takes an `sf` object, a vector path, or `NULL`. When it is supplied it
is rasterized onto the analysis grid (or matched to the cell centres of a
tabular skeleton) and joined into `calc_fild`.

`admin = NULL` normally means "no domain column". There is one exception: a
**raster** run whose `mort_lvl` is a column of `mort_rate` but not of
`calc_fild` asks for domain calibration without boundaries, so national
boundaries are taken from `rnaturalearth::ne_countries(scale = 110)` and
rasterized onto the grid; the number of `mort_lvl` values of `mort_rate` that
matched the gridded labels is reported. This needs the `rnaturalearth` package
(a `Suggests` dependency) and country names that match your `mort_lvl` values
exactly; with the synthetic example data no name matches, so the example stops
with an empty join. Pass `admin =` (and `admin_col =`) to choose the level
yourself. Tabular runs are untouched by the fallback.

## Custom concentration-response functions

There are three ways to bring your own curve.

**1. A data.frame.** Pass a long table with the columns `conc` (character
keys at `dgt_conc` decimals), `endpoint`, `age` and `RR`. The `ci` argument is
ignored for a data.frame `crf`:

```r
crf_custom <- data.frame(
  conc     = matchable(seq(0, 60, 1), 1),
  endpoint = "ncd+lri",
  age      = "25",
  RR       = 1 + 0.01 * seq(0, 60, 1)
)

deaths_custom <- mortality(
  crf       = crf_custom,
  calc_fild = sheet("grid_info.xlsx"),
  conc_real = sheet("grid_exposure.xlsx"),
  pop_total = sheet("grid_pop.xlsx"),
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",
  mort_lvl  = "location"
)

# only the cells whose concentration is inside the lookup survive
nrow(deaths_custom)
```

The lookup has to cover the exposure range: values outside it are dropped by
the join and reported ("`n` value(s) ... fall outside the CRF lookup range
..."), and if nothing survives the call stops. Only the endpoints and ages the
table lists are computed; missing combinations are absent from the result.

**2. A JSON configuration** read by `cr_config()`. A config names the models,
their aliases, their lookup and their endpoint x age metadata:

```json
{
  "schema_version": 1,
  "models": {
    "MYMODEL": {
      "label": "PM2.5_my_model",
      "aliases": ["MYCURVE"],
      "lookup": { "kind": "xlsx", "path": "my_cr.xlsx",
                  "sheets": { "MEAN": "MEAN", "LOW": "LOW", "UP": "UP" } },
      "conc_col": "conc",
      "endpoints": [
        { "name": "ihd", "ages": { "from": 25, "to": 95, "by": 5 } }
      ]
    }
  }
}
```

* `lookup.kind` is `"rda"` (with `table`, the name of an object in `AttrMort`,
  such as a shipped lookup), `"xlsx"` (with `path` and optionally `sheets`),
  or `"csv"` (with `path`, a directory holding `MEAN.csv`/`LOW.csv`/
  `UP.csv`). Relative paths resolve against the directory of the config file,
  never the working directory.
* `conc_col` names the concentration column of the lookup sheets.
* `endpoints[].ages` is either a range object (`{from, to, by}`) or an
  explicit numeric vector; a range may ask for at most 100 ages, and more is
  an error.
* `aliases` are accepted wherever a model name is.

```r
# the lookup the config points at, built from published coefficients
coefs <- data.frame(
  cause = "IHD", age = "25", alpha = 5, beta = 0.01,
  gamma = 0.5, tmrel = 3
)
build_cr_table(coefs, model = "IER", conc = seq(0, 300, 0.1),
               path = file.path(tempdir(), "my_cr.xlsx"))

# the config: a named list written as JSON, or the JSON file above
cfg <- list(
  schema_version = 1,
  models = list(
    MYMODEL = list(
      label = "PM2.5_my_model",
      aliases = "MYCURVE",
      lookup = list(kind = "xlsx", path = "my_cr.xlsx",
                    sheets = list(MEAN = "MEAN", LOW = "LOW", UP = "UP")),
      conc_col = "conc",
      endpoints = list(list(name = "ihd",
                            ages = list(from = 25, to = 95, by = 5)))
    )
  )
)
cfg_path <- file.path(tempdir(), "cr_models_my.json")
jsonlite::write_json(cfg, cfg_path, auto_unbox = TRUE, pretty = TRUE)

cr_models(cfg_path)                  # names, aliases included

# one model's lookup as a long table: conc, endpoint, age, RR
user_lookup <- rr_std("MYCURVE", "MEAN", config = cfg_path)
head(user_lookup, 3)

deaths_my <- mortality(
  crf       = "MYCURVE",             # a name or an alias of the config
  cr_config = cfg_path,
  calc_fild = sheet("grid_info.xlsx"),
  conc_real = sheet("grid_exposure.xlsx"),
  pop_total = sheet("grid_pop.xlsx"),
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",
  mort_lvl  = "location"
)

# the user model's endpoint and ages are in the result columns
names(deaths_my)[1:5]
```

**3. Coefficients.** `build_cr_table()` turns published coefficients into the
wide `MEAN`/`LOW`/`UP` structure the package consumes, and can write the three
sheets to an xlsx file that a config then points at:

```r
coefs <- data.frame(
  cause = "IHD", age = "25",
  alpha = 5, beta = 0.01, gamma = 0.5, tmrel = 3
)
ier <- build_cr_table(coefs, model = "IER", conc = seq(0, 20, 0.1))
names(ier)
head(ier$MEAN)

# or straight to a workbook: build_cr_table(coefs, path = "my_cr.xlsx")
```

`model` is `"IER"` (or an IER variant such as `"IER2017"`) or `"GEMM"`; the
required coefficient columns are `cause`, `age`, `alpha`, `beta`, `gamma`,
`tmrel` for IER and `cause`, `age`, `theta`, `SE.theta`, `alpha`, `mu`, `gama`
for GEMM. `level` sets the confidence level of the `LOW`/`UP` sheets.

The shipped models are:

| Name | Alias | Curve | Endpoints |
|---|---|---|---|
| `GEMM` | `NCD+LRI` | PM<sub>2.5</sub>, GEMM | `ncd+lri` |
| `5COD` | | PM<sub>2.5</sub>, GEMM | `copd`, `ihd`, `lc`, `lri`, `stroke` |
| `IER2017` | `IER` | PM<sub>2.5</sub>, IER (GBD 2017) | `copd`, `ihd`, `lc`, `lri`, `stroke` |
| `IER2015` | | PM<sub>2.5</sub>, IER (GBD 2015) | as `IER2017` |
| `IER2013` | | PM<sub>2.5</sub>, IER (GBD 2013) | as `IER2017` |
| `IER2010` | | PM<sub>2.5</sub>, IER (GBD 2010) | as `IER2017` |
| `MRBRT2021` | `MRBRT` | PM<sub>2.5</sub>, MR-BRT (GBD 2021) | `copd`, `dm2`, `ihd`, `lc`, `lri`, `stroke` |
| `MRBRT2019` | | PM<sub>2.5</sub>, MR-BRT (GBD 2019) | as `MRBRT2021` |
| `O3` | | O<sub>3</sub> | `copd` |
| `NO2` | | NO<sub>2</sub>, all-cause | `allcause` |

The endpoint x age coverage of each model comes from the configuration, not
from the code: `cr_config()` shows which ages each endpoint really has (for
instance, some IER endpoints are defined at age 0 only), and a run computes
the intersection of the C-R table's ages with the ages present in `mort_rate`.

## Uncertainty

`uncertain = TRUE` reports `CI_LOW`/`CI_UP` beside the central estimate. The
interval is a **range, not a sampling interval**: the published low/high C-R
tables are applied to every grid cell and the per-cell burdens are summed. A
CRF is one curve shared by every cell, so its uncertainty is common-mode and
does not average out as a domain grows; with one shared parameter the
quantiles of the total are exactly the total evaluated at the parameter
quantiles. An earlier version propagated first-order sensitivities as
`sigma^2 = sum(Sensi^2)`, which assumes independent perturbations per cell and
shrinks the CRF term roughly like `1/sqrt(n_cells)`; it has been removed.

`conc_uncert = <percent>` adds a second chain: the whole analysis is re-run
with every concentration scaled by `1 +/- percent / 100`, and the reported
interval is the union of the C-R range and that exposure range (summed
common-mode as well, not an independent-error sum). A cell that at least one
chain cannot compute gets `NA` and a warning -- the interval is undefined
there, not copied from a neighbour.

## Core functions

| Function | Purpose |
|---|---|
| `mortality()` | attributable deaths per scenario, per grid cell or per domain; `aggregate`, `aggregate_by`, `uncertain`, `conc_uncert` and `chunk_ages` are arguments |
| `decompose()` | two-group decomposition of the change into `PG`/`PA`/`EXP`/`ORF` for all 24 orderings (16 shared states) |
| `aggregate_mortality()`, `aggregate_ci()` | post hoc aggregation of an existing result by domain and by endpoint/age, keeping MEAN/UP/LOW side by side |
| `write_mortality_xlsx()` | write a result (or a named list of them) to a caller-supplied xlsx path |
| `build_grid_info()` | the analysis grid as a table (coordinates, domain labels; `res`/`ext`/`crs`/`n_cells` as attributes), writable to `.rds`/`.csv`/`.xlsx` |
| `cr_config()`, `cr_models()` | the C-R model configuration (JSON: lookup, concentration column, endpoints x ages) and the list of accepted names |
| `rr_std()` | one model's lookup as a join-ready long table (`conc`, `endpoint`, `age`, `RR`) |
| `build_cr_table()` | build a `MEAN`/`LOW`/`UP` lookup from published coefficients |
| `matchable()` | render a numeric key as a fixed-precision string |

### `mortality()` arguments

| Argument | Meaning |
|---|---|
| `crf` | C-R model name (see `cr_models()`), or a data.frame with `conc`, `endpoint`, `age`, `RR` |
| `ci` | which lookup branch to use: `"MEAN"` (default), `"UP"`, `"LOW"` (`"UPPER"`/`"LOWER"` accepted) |
| `calc_fild` | attribution field: a table, a file path, a vector map (boundary source), or `NULL` when the exposure supplies the grid |
| `conc_real`, `conc_cf` | real and counterfactual exposure; `conc_cf = NULL` reuses `conc_real` |
| `pop_total` | population counts |
| `age_struc` | one row per domain and age group, proportion in `prop` |
| `mort_rate` | baseline cause-specific mortality, deaths per 100,000 |
| `mort_lvl` | domain column used to calibrate the PWRR; `NULL` skips calibration |
| `scenario` | per-input column (or raster band) selector for wide inputs |
| `admin`, `admin_col` | boundaries and the column holding their domain names |
| `target_res` | target grid resolution in degrees, one number or `c(res_x, res_y)` |
| `dgt_coord`, `dgt_conc` | decimal places of the coordinate keys (default 2) and of the concentration keys (default 1) |
| `validate` | `"warn"` (default), `"stop"` or `"off"` for a silent run |
| `aggregate`, `aggregate_by` | domain aggregation and the breakdown kept (`"total"`, `"endpoint"`, `"age"`, `"all"`) |
| `uncertain`, `conc_uncert` | C-R range, and an added exposure-perturbation chain in percent |
| `chunk_ages` | age strata computed per pass; `NULL` sizes the pass from the problem (roughly 2 GB) |
| `cr_config` | a `cr_config()` object or a JSON path, used when `crf` is a model name |

`decompose()` takes `crf`, `ci`, `calc_fild`, `from`, `to`, `mort_lvl`,
`admin`, `admin_col`, `target_res`, `dgt_coord`, `dgt_conc`, `validate` and
`cr_config`; see `?decompose`.

## Data contract

| Dimension | Convention |
|---|---|
| canonical columns | `conc`, `pop`, `age`, `prop`, `endpoint`, `mortrate`, `location` |
| join keys | coordinate columns (`x`/`y`, `lon`/`lat`) and/or domain columns; all rendered as fixed-precision strings by `matchable()` |
| coordinate keys | character, `dgt_coord` decimals (default 2) |
| concentration keys | character, `dgt_conc` decimals (default 1), on **both** the exposure side and the lookup side |
| concentration raster storage | write Float64, or values already rounded to `dgt_conc`: Float32 carries about 1e-6 relative error, enough to push a value across the rounding boundary and make it miss the lookup table |
| ages | character 5-year strata (`"25"`, `"30"`, ...); numeric ages are rounded to whole years, so a user table and a lookup table join either way |
| mortality units | deaths per 100,000 (the calculation divides by 1e5 once) |
| result columns | wide `{endpoint}_{age}`; endpoints may contain `+`, `.` or `_`, so the name is parsed from the right at the last underscore |
| CI labels | `"MEAN"`, `"UP"`, `"LOW"` (`"UPPER"`/`"LOWER"` accepted) as an argument, `_MEAN`/`_UP`/`_LOW` as a column suffix |
| scenario columns | one column per scenario in a wide table, one band per scenario in a raster; selected per input by `scenario =` |
| multi-band rasters | all bands (scenarios) must share one validity mask; a cell missing from some bands is reported and dropped from the analysis grid |

## Common questions

**How do I know which calibration branch ran?** The `Analysis grain:` line
reports it: `PWRR calibrated per domain` (`mort_lvl` is a column of
`mort_rate`), `grid-level PAF without calibration` (`mort_lvl = NULL`), or the
one-unit fallback below. The grid-level and domain-level grains are not
numerically identical: a grid run takes the population-weighted mean of a
domain's cell-level relative risks, a domain-only run the relative risk at the
domain's population-weighted mean concentration.

**My `mort_lvl` names a column my table does not have.** The calibration level
is resolved after column mapping; a name that matches a recognised domain
variant is mapped to the canonical `location`, otherwise the run falls back to
whatever domain column `mort_rate` carries itself, with a warning. A
`mort_rate` with no domain column at all calibrates the whole field as one
unit -- also with a warning -- and the counterfactual exposure does not enter
that fallback.

**A supplied `calc_fild` does not match the raster grid.** Zero coordinate
keys in common with the raster grid is an error -- the two are different grids
-- while a partial overlap is a warning with the number of unmatched keys. The
usual cause is a table written for another resolution; regenerate it with
`build_grid_info()` or set `target_res =` so both land on one grid.

**How do I make a run silent?** `validate = "off"` is complete silence:
preparation messages, mapping notes, validation warnings, the `Analysis grain:`
line, the branch notice and `decompose()`'s printed summary are all suppressed,
and it does not change a single number. `decompose()` still returns its 24
tables and `mortality()` its result -- there is just nothing on the console.

**Some cells contribute nothing.** Check, in order: concentrations outside the
C-R lookup range (reported and dropped by the join), domain labels that do not
match `mort_rate` (0 matched domains is an error; a partial match is reported),
and cells missing from some bands of a multi-band raster (reported and removed
from the grid).

**How do I pick a scenario?** For `mortality()`, `scenario =` does it per
input. For `decompose()`, select each role's column yourself before the call
-- the function compares two complete datasets and knows nothing about
scenario names.

**How do I keep memory in check?** `chunk_ages =` sets how many age strata are
computed per pass. Splitting by age is numerically exact -- the run is
identical to an unchunked one -- and `NULL` (default) sizes the pass from the
number of cells, ages and endpoints so that one pass stays around 2 GB.

**Which files are written?** Only the ones you ask for:
`write_mortality_xlsx()` and `build_grid_info(path =)` write what you point
them at. No output file name is ever invented by the package.

## Methodology references

The attributable-burden approach implemented here was applied in:

1. XING Z#, **LIU Y**#, CHEPELIEV M, et al. Global food trade can mitigate
   substantial health burdens attributed to ambient PM<sub>2.5</sub> pollution.
   *Nature Food*, 2026, 7(3): 223-233.
2. Tang R, Zhao J, **LIU Y**, et al. Air quality and health co-benefits of
   China's carbon dioxide emissions peaking before 2030.
   *Nature Communications*, 2022, 13(1): 1008.
3. **LIU Y**, Zhu G, Zhao Z, et al. Population aging might have delayed the
   alleviation of China's PM<sub>2.5</sub> health burden.
   *Atmospheric Environment*, 2022, 270: 118895.
4. Wang H, He X, Liang X, et al. Health benefits of on-road transportation
   pollution control programs in China.
   *PNAS*, 2020, 117(41): 25370-25377.

## Changelog

See [NEWS.md](NEWS.md) for release notes.
