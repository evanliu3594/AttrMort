# AttrMort 0.3.0

## Breaking changes

* All dose terminology is now concentration terminology: the canonical column
  is `conc` (was `dose`), the arguments are `conc_real`, `conc_cf` and
  `conc_uncert`, the wide-to-long helper is `getConc()` (was `getDose()`),
  aggregated results carry `conc_pwe`, and the shipped lookup tables as well as
  the `RR_std()` / `build_cr_table()` output expose a `conc` key, and
  `build_cr_table()`'s axis argument is `conc` (was `concentration`). No
  aliases are kept: a data column named `dose` has to be renamed, e.g. with
  `dplyr::rename(conc = dose)`. Data whose header says `concentration` is still
  matched.
* `Mortality_Aggr()` has been merged into `Mortality()`. Domain aggregation
  and the uncertainty range are now arguments of the single entry point:
  `aggregate`, `aggregate_by`, `uncertain` and `conc_uncert`.
* The domain-level central estimate is now the **sum of the grid-level
  burdens**, matching `Mortality()`'s own grid-level calculation, instead of
  the previous domain-level PAF x M estimator. Domain totals therefore change.
* The uncertainty interval is now a **range**: the low/high
  concentration-response tables are applied per grid cell and the results are
  summed. The former first-order propagation (`sigma^2 = sum(Sensi^2)`) was
  removed, because it assumes independent perturbations per cell and
  understates the uncertainty of a globally shared concentration-response
  function.
* `Mortality_Aggr()`'s `write` and `conc_cf` arguments are gone; they were
  declared but never used.

## Repairs

* `R/Mortality.R` had a duplicated function signature, so the package could
  not be loaded at all.
* Column mapping was applied in the wrong direction (`endpoint` was renamed to
  `cause`), which aborted every run.
* `raster_to_grid()` passed an aligned `SpatRaster` back through
  `terra::rast()`, producing an empty template, so no raster input ever
  produced a result.
* A raster run without `scenario =` kept the layer's own column name and left
  the concentration numeric, so the call failed on a missing or unjoinable
  `conc` key. A single-band raster is now named `conc` / `pop` and its key is
  rendered at `dgt_conc`, exactly as a named scenario's would be.
* Concentration-response tables now always return character `conc` keys, so
  NO2 no longer fails to join; a CRF whose endpoints are absent from
  `mort_rate` reports that instead of returning zero rows.
* Population rasters are aggregated with `terra::aggregate(fun = "sum")`
  before resampling, and the total is verified afterwards.
* The package now declares its own imports; `library(AttrMort)` no longer
  needs a separate `library(tidyverse)`.

## New features

* `Mortality()` accepts a raster-only call: when `conc_real` is a raster (a
  GeoTIFF/netCDF path or a `SpatRaster`), `calc_fild` may be omitted
  (`calc_fild = NULL`, now the default) and the grid skeleton is taken from
  the ingested exposure data. Tabular exposure still requires `calc_fild` and
  is told so. A single-band raster also needs no `scenario =`.
* A raster run that names a `mort_lvl` column of `mort_rate` while `calc_fild`
  carries no such domain column -- domain calibration without a boundary file
  -- is now rasterized onto national boundaries from
  `rnaturalearth::ne_countries(scale = 110)` (Suggests-guarded). The number of
  matched domains is reported, because mismatched country names are the usual
  failure; `admin =` still overrides the level, and tabular runs keep
  `admin = NULL` meaning "no domain column".
* `Mortality()` gained `chunk_ages`, the number of age strata computed per
  pass (`NULL` sizes it from the problem, aiming below ~2 GB per pass). The
  population-weighted relative risk is computed per (domain, endpoint, age)
  and the per-cell burden is element-wise, so the split is numerically exact
  and the assembled result is identical to a single pass, column order
  included; it applies to the central estimate and to the
  `uncertain`/`conc_uncert` chains alike. This is what keeps a 0.1 degree
  global run inside 32 GB, where the intermediate long table grows like
  cells x ages x endpoints.
* `build_cr_table()` turns published coefficients into a `MEAN`/`LOW`/`UP`
  lookup table for any pollutant or endpoint set, so a new pollutant or
  endpoint set needs coefficients rather than new code.
* `domain_summary()` reduces gridded or tabular inputs to **one row per
  domain**: the domain column (named after the boundary, `mort_lvl`, or the
  column the exposure data carries), `conc_pwe` (population-weighted mean
  concentration), `conc_mean` next to it as the unweighted contrast,
  `pop_total` and `n_cells`. It runs the alignment, ingestion, scenario
  extraction and boundary rasterization steps of `Mortality()` and takes the
  weighted mean from the same internal helper the aggregated result uses, so
  `conc_pwe` and `Mortality(aggregate = TRUE)$conc_pwe` cannot disagree. It
  writes `.rds`/`.csv`/`.xlsx` like `build_grid_info()`, and without a domain
  column to summarise by it stops and says how to supply one.
* `Mortality()` prints one `Analysis grain:` line per run: how many cells and
  domains the resolved skeleton holds, the grid resolution, and the branch
  `mort_lvl` selected (`PWRR calibrated per domain`, `PWRR calibrated on the
  whole field`, or `grid-level PAF without calibration`). The analysis grain
  is the grain of `calc_fild`, and a domain-only skeleton is a legitimate
  input -- the national workflow, one relative risk evaluation per domain --
  but the two grains are a different 口径, not a shortcut through each other:
  the grid takes the population-weighted mean of a domain's per-cell relative
  risks, the domain skeleton the relative risk at the domain's
  population-weighted mean concentration (a Jensen gap). The line keeps that
  visible instead of letting the grain be dispatched silently;
  `validate = "off"` is the quiet mode and prints nothing.
* `build_grid_info()` renders the analysis grid as a table -- coordinate keys
  plus the domain column when `admin =` supplies one, and `res`, `ext`, `crs`,
  `n_cells` and `dgt_coord` as attributes -- and writes it to `.rds`, `.csv` or
  `.xlsx`. It runs the alignment, ingestion and boundary rasterization steps of
  `Mortality()` itself, so the table describes exactly the grid a run on the
  same inputs uses; that is what makes one grid reusable across scenarios.
  `Mortality()` now checks a supplied `calc_fild` against the raster grid when
  a raster input is present, at two levels: a skeleton sharing **no**
  coordinate key with that grid is an error -- the two are different grids, so
  nothing can be joined -- while a **partial** match only warns, with the
  unmatched count and the grid resolution, and what to do about it
  (`build_grid_info()` on the same rasters, or a shared `target_res=`) instead
  of being joined silently. A warning rather than a stop for the partial case,
  because a deliberately coarser table is legal; `validate = "off"` turns both
  levels off.
* `aggregate_mortality()` and `aggregate_ci()` aggregate a result by domain
  and by endpoint/age, keeping `MEAN`/`UP`/`LOW` side by side, with optional
  xlsx export.
* `cr_models()` lists the accepted model names; `RR_std()` gained a `dgt`
  argument and accepts `"UPPER"`/`"LOWER"` aliases.
* Input validation (`validate =`), all-problems-at-once input errors, a
  non-interactive resolution fallback and numeric-age coercion.
* Numeric coordinate columns are rendered as character keys at `dgt_coord`
  during ingestion, so tabular and raster inputs always share one key type;
  when `dgt_coord` cannot keep the coordinates distinct the column is left
  numeric with a warning instead of silently merging grid cells.
* `Decomposition()` no longer depends on `combinat`, and `serie` now follows
  the ordering documented in its help page.

## Data

* Every example file in `inst/extdata/` is now synthetic -- three fictional
  countries on a 0.25 degree grid plus national population, age-structure and
  mortality tables -- generated by `data-raw/make-example-data.R`. The package
  no longer ships externally sourced instance data; the only bundled
  published content is the concentration-response curves in `data/`.
* The example mortality table covers every endpoint the built-in models need
  (`ncd+lri`, `copd`, `ihd`, `lc`, `lri`, `stroke`, `dm2`, `cause`), so all
  thirteen branches -- including O3 and NO2 -- are exercised end to end.

## Internal

* `R/` split by responsibility: `ingest.R`, `aggregate.R`, `build-cr.R`,
  `uncertainty.R`; internal helpers are no longer documented.
* `.extract_scenario()` leaves an absent `age_struc` / `mort_rate` alone, as
  it already did for `conc_cf`, so a caller that has neither (the domain
  summary) reuses the same scenario extraction instead of a second one.
* testthat 3e suite built on a hand-computable four-cell fixture, the shipped
  example workbooks, and an opt-in fingerprint regression that pins the
  per-column sums of every `Mortality()` branch
  (`ATTRMORT_FINGERPRINTS=1`; `=update` rewrites the references).
* Manual scripts moved to `data-raw/`; `README.rmd` removed.

# AttrMort 0.2.0

* Removed the S4 OOP layer; pure functional API with the native pipe.
* Added `scenario`, `admin` and `target_res`, `Mortality_batch()` and
  `combine_batch()`, schema detection and raster I/O.

# AttrMort 0.1.0

* Initial release.
