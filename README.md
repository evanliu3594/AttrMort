# AttrMort

`AttrMort` estimates the mortality attributable to ambient air pollution
exposure. It is **pollutant-agnostic** (PM<sub>2.5</sub>, O<sub>3</sub>,
NO<sub>2</sub> are built in; anything else can be supplied as a lookup table)
and **input-agnostic** (data frames, CSV/Excel files and gridded GeoTIFFs).

The package is **self-contained**: the only bundled curves are the
concentration-response lookup tables in `data/`, and every example file in
`inst/extdata/` is synthetic.

Requires R >= 4.1 (native pipe `|>`).

## Installation

```r
# install.packages("devtools")
devtools::install_github("evanliu3594/AttrMort")
library(AttrMort)
```

## Quick start

One call on wide-format tables, using the example data shipped with the
package:

```r
extdata <- system.file("extdata", package = "AttrMort")
sheet   <- function(f) readxl::read_excel(file.path(extdata, f))

result <- Mortality(
  CRF       = "GEMM",
  calc_fild = sheet("grid_info.xlsx"),
  conc_real = sheet("grid_exposure.xlsx"),          # wide: one column per scenario
  pop_total = sheet("grid_pop.xlsx"),
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",                       # which scenario column to use
  mort_lvl  = "location"                        # PWRR calibration domain
)
```

The shipped example data are synthetic: three fictional countries on a 0.25°
grid (`grid_info`, `grid_exposure`, `grid_pop`) plus national tables
(`national_population`, `national_age_structure`, `national_mortality`). In a
source checkout, `data-raw/make-example-data.R` rebuilds them, so they double
as a template for your own instance files.

Rasters and files can be handed over directly — formats, grids and column
names are resolved internally:

```r
Mortality(
  CRF       = "GEMM",
  scenario  = "base2015",
  calc_fild = "admin_grid.csv",
  conc_real = "pm25_scenarios.tif",   # defines the target grid
  pop_total = "population.tif",       # aggregated onto that grid, totals preserved
  age_struc = "age_structure.csv",
  mort_rate = "mortality_rates.csv",
  admin     = "boundaries.shp",       # rasterized onto the grid
  admin_col = "NAME",
  mort_lvl  = "NAME",
  target_res = 0.1                    # omit to auto-detect and confirm
)
```

## Raster-only runs

A raster exposure product already carries the analysis grid, so `calc_fild`
can be left out: the skeleton is taken from the ingested `conc_real`, and a
run whose `mort_lvl` is a column of `mort_rate` falls back to **national
boundaries** (`rnaturalearth`, scale 110) rasterized onto that grid — no
boundary file needed. GeoTIFF and netCDF (`.nc`) exposure both work:

```r
Mortality(
  CRF       = "GEMM",
  conc_real = "pm25_base2015.tif",    # or .nc; defines the grid
  pop_total = "population.tif",       # aggregated onto that grid
  age_struc = "age_structure.csv",
  mort_rate = "mortality_rates.csv",
  scenario  = "base2015",
  mort_lvl  = "location"              # calibrated per country
)
```

The number of domains that matched the rasterized boundaries is reported, so
a country name that does not match `mort_lvl` is visible rather than silently
dropped. Pass `admin =` (a shapefile path or an `sf` object, with
`admin_col =`) to use provinces, grid cells or any other level instead — the
argument always overrides the default. Tabular `conc_real` still needs
`calc_fild`, and `mort_lvl = NULL` still means "no domains at all".

Age strata are computed in blocks, sized automatically from the number of
cells, age groups and endpoints (roughly 2 GB per pass). The split is
numerically exact and a chunked run is identical to an unchunked one; use
`chunk_ages =` to set the number of strata per pass yourself.

## National-only workflow (domain grain)

When the answer is wanted per country rather than per grid cell, reduce the
exposure to a domain table first:

```r
# One row per country: the population-weighted mean concentration, the
# unweighted mean next to it, the country population and the number of cells
# behind each row. `.rds`, `.csv` or `.xlsx`; the table is returned either way.
ds <- domain_summary(
  conc_real = sheet("grid_exposure.xlsx"),
  pop_total = sheet("grid_pop.xlsx"),
  admin     = "boundaries.shp",       # supplies the domain labels
  admin_col = "iso3",
  scenario  = "base2015",
  path      = "domain_summary.csv"
)

# One row per domain: PWRR has nothing left to average over, so the burden is
# evaluated once per domain, at that domain's population-weighted mean
Mortality(
  CRF       = "GEMM",
  calc_fild = data.frame(location = ds$iso3),         # domain-only skeleton
  conc_real = data.frame(location = ds$iso3, base2015 = ds$conc_pwe),
  pop_total = data.frame(location = ds$iso3, base2015 = ds$pop_total),
  age_struc = sheet("national_age_structure.xlsx"),
  mort_rate = sheet("national_mortality.xlsx"),
  scenario  = "base2015",
  mort_lvl  = "location"
)
```

The domain labels come from `admin =` (rasterized onto the grid the
concentration raster brings with it) or from a domain column the exposure
table already carries; `mort_lvl =` names the resulting column. Without one,
`domain_summary()` stops and says how to supply it rather than inventing a
domain.

This is a **different 口径** from the grid path, not a shortcut through it.
On the grid a domain's PWRR is the population-weighted mean of the relative
risks of its cells; on a domain-only skeleton it is the relative risk at the
domain's population-weighted mean concentration -- mean of RR against RR of
mean, a Jensen gap. On the shipped example the two national totals differ by
under 0.1% per country, and they are never identical, so the grain is never
dispatched silently: every `Mortality()` run prints one line saying which
grain it resolved and which PWRR branch it took,

```
Analysis grain: 6000 cell(s) in 3 domain(s) on a 0.25 deg grid; PWRR calibrated per domain.
Analysis grain: 3 domain(s) with one row each; PWRR reduces to a single RR evaluation per domain (domain-level burden).
Analysis grain: 6000 cell(s) with no domain column; grid-level PAF without calibration.
```

and `domain_summary()` reports `conc_mean` beside `conc_pwe` so that the two
concentrations can be compared directly. `validate = "off"` is the quiet mode
and prints nothing.

## One grid, several scenarios

Every scenario of an analysis has to run on the same grid, so build the grid
once and hand the same table to each run:

```r
# the grid of the analysis, made explicit: coordinate keys, the domain column,
# and res / ext / crs / n_cells as attributes
gi <- build_grid_info(
  conc_real = "pm25_scenarios.tif",   # defines the grid
  pop_total = "population.tif",       # aligned onto it
  admin     = "boundaries.shp",       # rasterized onto it
  admin_col = "iso_a3",
  path      = "grid_info.rds"         # .rds, .csv or .xlsx
)

Mortality(CRF = "GEMM", calc_fild = gi, scenario = "base2015",    ...)
Mortality(CRF = "GEMM", calc_fild = gi, scenario = "scenario2030", ...)
```

`build_grid_info()` runs the same alignment, ingestion and boundary
rasterization steps `Mortality()` runs, so `gi` describes exactly the grid
those calls use, and it carries no `conc`/`pop` values -- only the grid. It also
works on a table (`build_grid_info(conc_real = sheet("grid_info.xlsx"))`) and on
any `SpatRaster`. Handing the table back next to rasters makes `Mortality()`
check it: coordinate keys that match no raster cell are reported with their
count and the grid resolution, the usual cause being a table written for
another resolution, fixed by regenerating it with `build_grid_info()` or by
setting `target_res=` so that both land on one grid. The check warns rather
than stops -- a deliberately coarser table is legal -- and `validate = "off"`
turns it off.

## What you can plug in

| Data | Accepted formats | Notes |
|---|---|---|
| Attribution field (`calc_fild`) | data.frame, CSV, Excel | coordinate columns (`x`/`y`, `lon`/`lat`), domain columns (`location`, `Country`, ...) or both; optional for a raster `conc_real`, which supplies the grid |
| Concentration (`conc_real`, `conc_cf`) | data.frame, CSV, Excel, GeoTIFF, netCDF, `SpatRaster` | wide tables and raster bands are scenarios; `conc_real` defines the grid |
| Population (`pop_total`) | data.frame, CSV, Excel, GeoTIFF | aggregated onto the concentration grid with the total preserved |
| Age structure (`age_struc`) | data.frame, CSV, Excel | one row per domain and age group, proportion in `prop`; renormalised within each domain |
| Mortality (`mort_rate`) | data.frame, CSV, Excel | deaths per 100,000, per domain, age group and endpoint |
| Boundaries (`admin`) | shapefile path, `sf` object, `NULL` | rasterized onto the grid; `NULL` means no domain column, except on a raster run with a domain `mort_lvl`, which uses `rnaturalearth` national boundaries |

Column names are matched heuristically when they are not already canonical
(`age_group` → `age`, `mortality_rate` → `mortrate`, `Endpoint` → `endpoint`,
...), and every problem found is reported at once.

## Core functions

| Function | Purpose |
|---|---|
| `Mortality()` | attributable deaths per scenario, per grid cell or per domain — domain aggregation and the uncertainty range are arguments (`aggregate`, `aggregate_by`, `uncertain`, `conc_uncert`) |
| `build_grid_info()` | the analysis grid as a table (coordinates, domain labels, `res`/`ext`/`crs`/`n_cells`), reusable across scenarios and writable to `.rds`/`.csv`/`.xlsx` |
| `domain_summary()` | the domain grain as a table: one row per domain with `conc_pwe`, `conc_mean`, `pop_total` and `n_cells`, built from the same alignment and boundary rasterization `Mortality()` runs |
| `Decomposition()` | driving-factor decomposition (24 permutations of population growth, ageing, exposure and other risk factors) |
| `aggregate_mortality()`, `aggregate_ci()` | aggregate a result by domain and by endpoint/age, keeping MEAN/UP/LOW side by side |
| `getConc()`, `getPop()`, `getAge()`, `getMort()` | pull one scenario out of a wide table |
| `cr_config()` | the C-R model configuration: which lookup table a model uses, its concentration column and its endpoint×age metadata; shipped as JSON and replaceable by path |
| `RR_std()`, `cr_models()` | concentration-response lookup tables and the list of valid model names (from the config, aliases included) |
| `build_cr_table()` | build a lookup table from published coefficients — the entry point for a pollutant or endpoint set the package does not ship |
| `matchable()` | render a numeric key as a fixed-precision string |

## Data contract

| Dimension | Convention |
|---|---|
| `conc` keys | character, `dgt_conc` decimals (default 1) on both the input side and the lookup table |
| concentration raster storage | write Float64 (or values already rounded to `dgt_conc`): Float32 carries about 1e-6 relative error, enough to push a value across the rounding boundary and make it miss the lookup table |
| coordinate keys | character, `dgt_coord` decimals (default 2) |
| ages | character 5-year strata (`"25"`, ...); numeric ages are coerced |
| wide result columns | `{endpoint}_{age}`; endpoints may contain `+`, `.` or `_`, so parse from the right |
| `CI` labels | `"MEAN"`, `"UP"`, `"LOW"` (`"UPPER"`/`"LOWER"` accepted) |
| mortality units | deaths per 100,000 |

## Aggregation and uncertainty

`Mortality(aggregate = "location")` sums the grid-level burdens within each
domain -- the same calculation `aggregate_mortality()` performs -- keeps the
`endpoint`/`age` breakdown selected by `aggregate_by`, and adds `conc_pwe`,
the population-weighted concentration of the domain.

`uncertain = TRUE` attaches `CI_LOW`/`CI_UP`. The interval is a **range
propagated at grid level and summed**: the low/high concentration-response
tables are applied to every cell and the resulting burdens are added up. A
CRF is a single curve shared by every cell, so its uncertainty is common-mode
and does not average out as a domain grows; with one shared parameter the
quantiles of the total are exactly the total evaluated at the parameter
quantiles. An earlier implementation used a first-order propagation,
`sigma^2 = sum(Sensi^2)`, which assumes independent perturbations per cell and
therefore shrinks the CRF term roughly like `1/sqrt(n_cells)`; it has been
removed.

`conc_uncert = 12` additionally re-runs the analysis with every concentration
scaled by `1 +/- 12%` and widens the interval to cover that range too.

## Decomposition

`Decomposition()` walks the four drivers through all 24 orderings; each step
differs from the previous one by exactly one driver, so `Mort_k - Mort_(k-1)`
isolates that driver's contribution. `serie` 1..24 selects the ordering, in
lexicographic order of `PG, PA, EXP, ORF` (the order documented in `?Decomposition`).

## Supported concentration-response functions

`cr_models()` lists the accepted names: `GEMM`, `NCD+LRI`, `5COD`, `IER`,
`IER2010`, `IER2013`, `IER2015`, `IER2017`, `MRBRT`, `MRBRT2019`,
`MRBRT2021`, `O3`, `NO2`. What each name means — its lookup table,
concentration column and endpoint×age set — comes from
`cr_config()`, the JSON configuration shipped in `inst/extdata/cr_models.json`
and replaceable with `cr_config = "<path>"`; `NO2` is all-cause, so its
`mort_rate` endpoint is `allcause`. Any other pollutant/endpoint combination
can be passed to `Mortality(CRF = <data.frame>)` as long as it has the columns
`conc`, `endpoint`, `age`, `RR`.

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
