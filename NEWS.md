# AttrMort 0.3.0

## Breaking changes

* The exported API is snake_case throughout: `Mortality()` is now `mortality()`
  (the established name, lower-cased), `Decomposition()` is `decompose()`,
  `RR_std()` is `rr_std()`, and the wide-to-long helpers are
  `get_conc()`, `get_pop()`, `get_age()` and `get_mort()`. No aliases were
  kept, so scripts, vignettes and bookmarks have to be updated. `decompose()`
  also lost its single-letter arguments (`G`, `D`, `P`, `A`, `M`, `L`, `D_cf`):
  they are now `calc_fild`, `conc_real`, `pop_total`, `age_struc`, `mort_rate`,
  `mort_lvl` and `conc_cf`, the same names `mortality()` uses.
* `domain_summary()` has been removed. It compressed the exposure and the
  population into a domain table so that a second run could be made at that
  grain; the same question is answered by `mortality(aggregate = TRUE)`,
  which sums the grid-level result by domain and reports `conc_pwe` beside
  the deaths. Scripts that called it call `mortality()` with `aggregate =`.
* `get_conc()`, `get_pop()`, `get_age()` and `get_mort()` are no longer
  exported. Narrowing a wide input to one scenario is something `mortality()`
  does with `scenario =` and `decompose()` does with `from`/`to`; the four
  functions are now the internal slicers behind that (`.slice_conc()` and
  friends) and have no user-facing replacement.
* `decompose()` now compares **two groups of inputs** instead of selecting
  two scenario columns of one table. `from` and `to` are lists holding one
  table per role (`conc_real`, `pop_total`, `age_struc`, `mort_rate`, and
  optionally `conc_cf`), exactly the tables `mortality()` takes as a single
  run; an optional `label` element names the group in the printed summary.
  Scenario names, and with them the `serie` argument, are gone.
* `decompose()` returns **all 24 orderings** as a named list of data frames
  (`"PG-PA-EXP-ORF"`, ...), one table per ordering, instead of a single
  table for one `serie`. `res[["PG-PA-EXP-ORF"]]` is what the old
  `serie = 1` returned. The orderings disagree by construction, so the
  order-independent reading is their mean -- see `?decompose`.
* All dose terminology is now concentration terminology: the canonical column
  is `conc` (was `dose`), the arguments are `conc_real`, `conc_cf` and
  `conc_uncert`, the wide-to-long helper is `get_conc()` (was `getDose()`),
  aggregated results carry `conc_pwe`, and the shipped lookup tables as well as
  the `rr_std()` / `build_cr_table()` output expose a `conc` key, and
  `build_cr_table()`'s axis argument is `conc` (was `concentration`). No
  aliases are kept: a data column named `dose` has to be renamed, e.g. with
  `dplyr::rename(conc = dose)`. Data whose header says `concentration` is still
  matched.
* `Mortality_Aggr()` has been merged into `mortality()`. Domain aggregation
  and the uncertainty range are now arguments of the single entry point:
  `aggregate`, `aggregate_by`, `uncertain` and `conc_uncert`.
* The domain-level central estimate is now the **sum of the grid-level
  burdens**, matching `mortality()`'s own grid-level calculation, instead of
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

* Column names are matched on their spelling-normalised form, and coordinate
  columns are renamed onto `x`/`y` on the way in. `mort_rate`, `Mort Rate`
  and `mortrate` are now the same column for `detect_columns()`, and
  `lon`/`lat`, `long`/`lat`, `longitude`/`latitude` (case, separators and
  mixed pairs like `x` with `lat` included) are the same key as `x`/`y`, so
  inputs that spell the grid differently join instead of sharing no key.


* `mort_lvl` follows the column mapping. A caller who wrote the name as it
  appears in the file (`Country`) named a column that no longer exists once
  the inputs are mapped, and the run silently calibrated the whole field as
  one unit. It now resolves to the mapped column, and a name that matches
  nothing falls back to the domain column `mort_rate` carries itself, with a
  warning. **The `gemm-lvlMissing` fingerprint changed with it.**
* Aggregating a result onto `calc_fild` joins on coordinates when both sides
  carry a full pair, instead of preferring a coarser domain column that
  copied a whole domain's rows onto every cell of it; a `calc_fild` that
  repeats a join key is refused rather than multiplying the result.
* The uncertainty range is matched by key. A chain that could not compute a
  cell -- a perturbed concentration outside the lookup, a domain the chain
  does not cover -- used to hand its neighbour's value over, because the
  shorter vector was recycled into `pmin()`/`pmax()`. Each chain is now
  aligned to the grid first, such a cell gets `NA` and the run warns how many
  there are.
* `validate = "off"` is now complete silence: it used to skip the
  validation but still report the branch it took, the resolution it chose,
  the columns it mapped, the boundaries it merged, whether the analysis grid
  came from the exposure, and `decompose()`'s printed summary. `"off"` now
  means "no reporting", and a test asserts silence on messages, warnings and
  stdout separately.
* Data text is no longer interpolated into error messages. An endpoint (or
  any other value read from a file) that contains braces used to be evaluated
  as an expression by the message formatter; such values are now passed as
  values, so `{1+1}` is reported literally. A CR configuration that would
  expand into more than 100 age groups is refused as well.
* A counterfactual raster (`conc_cf`) is aligned onto the lattice the exposure
  and the population resolved, not onto one derived from its own extent: two
  grids that overlap but whose cell centres differ share no key, and the run
  came back empty.
* Refining a population raster now divides each cell between the finer cells
  instead of interpolating it. A 2x2 degree cell holding 100 people used to
  become four cells of 100 (a 300% error, with a warning); the total is
  conserved now.
* `decompose()` matches every state to the analysis grid by key. A state that
  could not compute a cell (no risk from the lookup, no domain label, the
  group does not cover it) reports NA for that cell and warns, instead of
  borrowing the neighbouring cell's value through vector recycling.


* `R/mortality.R` had a duplicated function signature, so the package could
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
* `mortality()` no longer aborts a chunked run when an age block contains no
  row of `age_struc`: a GBD age structure may lack a stratum the CRF and
  `mort_rate` both carry. Such a block is dropped, exactly as the unchunked
  result leaves that age out. The "no rows survived the join" report still
  aborts when no age can contribute at all.
* A non-square input raster is no longer reduced to the average of its x and
  y resolution. `target_res` now takes one number or two, the finest input
  resolution is kept per axis, and a 2.5 x 2 degree grid stays 2.5 x 2 instead
  of silently being resampled onto a different grid. `build_grid_info()`
  reports `res` as `c(res_x, res_y)` for a non-square grid.
* Boundaries are attached to a **tabular** grid by a point-in-polygon join at
  the cell coordinates. Rasterizing them onto a template built from the
  coordinate range could not reproduce rounded cell-centre keys (5.12, 5.38,
  ...), so every label came back NA and the run either reported an unrelated
  join error or, in `build_grid_info()`, returned a table with no domain
  labels. Boundaries that label no cell are now reported instead.
* `scenario =` is a **per-input column selector**, not a contract across
  inputs. An input that does not carry the named column is used as it is when
  it has the canonical column (`conc`, `pop`, `prop`, `mortrate`) or a single
  numeric value column, reported with a message naming the column that was
  used. A long population column called `Pop2017` no longer needs a rename,
  and a wide exposure can be mixed with long auxiliary tables in one call
  (the same rule applies to `decompose()`'s `from` / `to`). The package
  never compares scenario or year across inputs. Several value candidates
  and no canonical column are still an error listing the candidates.
* Internal joins now pass their keys explicitly (`.left_join_common()`), so
  dplyr's one-line-per-join `Joining with \`by = ...\`` message is gone from
  every run; a run's output is its own messages and result.
* `domain_summary()` always names the domain column the way `mortality()`
  does: `location`, or `mort_lvl` when one is given. `admin_col` still selects
  which boundary column carries the labels, but the summary can be handed
  back as `calc_fild =` without an extra rename.
* The package now declares its own imports; `library(AttrMort)` no longer
  needs a separate `library(tidyverse)`.
* `mortality(aggregate = TRUE, mort_lvl = NULL, uncertain = TRUE)` aborted with
  "no applicable method for 'rename' applied to an object of class ...": with
  no grouping keys the whole-field range came back as a bare number and could
  not be attached to the single result row. It is now attached like any other
  aggregate, so the combination returns one row with `total`, `CI_LOW` and
  `CI_UP`.
* `build_cr_table()` no longer requires `model =`: the documented default is
  `"IER"`, and the previous default (the length-2 vector `c("IER", "GEMM")`)
  made every call without an explicit `model` fail with "`model` must be a
  single character string".
* `calc_fild = NULL` now also works for a **tabular** `conc_real`: the
  analysis grid is the exposure's own cells, as it already was for a raster
  one, and the choice is reported in a message. Nothing else changes -- a
  skeleton built that way holds coordinates only, so a run that needs a
  domain column still takes it from `admin =`, and an exposure that has
  already been aggregated to domains is asked for an explicit `calc_fild`.
* `calc_fild` also accepts a spatial vector layer (`sf`, or a path to a
  `.shp`/`.gpkg`/`.geojson`). It is then the boundary source: the grid still
  comes from the exposure, the polygons label the cells, and the run reports
  how many of `mort_rate`'s `mort_lvl` values the labels covered, so a map
  whose names do not match the mortality table is visible up front.
* `admin =` accepts a skeleton whose coordinates are spelled `lon`/`lat` (or
  `longitude`/`latitude`), not only `x`/`y`; the boundary labels are joined
  onto whichever pair the table carries.
* `decompose()` no longer runs `mortality()` once per step. It prepares each
  group once (the same `.prepare_inputs()` stage `mortality()` uses, with the
  second group aligned on the grid the first resolved), builds the
  concentration-response table once and then calls the calculation kernel once
  per **state** -- the set of drivers that have moved -- of which the 24
  orderings share 16. A full decomposition of the shipped example data takes
  about 0.9 s, and validation and the `Analysis grain` note are reported once
  per call instead of once per step.
* `decompose()` misattributed one step for the four orderings that start
  `PG-EXP` (series 3, 4, 13 and 14): its second step read the population table
  at `from` and the age structure at `to`, so the share belonging to the age
  structure was reported under the column of the driver that had just moved.
  Each step now moves exactly the driver it is named after. A decomposition's
  endpoints and total do not change -- the two affected columns shift by equal
  and opposite amounts -- but the split between those two drivers does; on the
  shipped example data the shift is about 0.09 deaths per cell-age stratum.
* `decompose(serie = 2.5)` used to be accepted and truncated to the second
  ordering; `serie` is now checked to be a whole number, which is what the
  error message has always said. Non-integers are an error from here on.

## New features

* `mortality()` accepts a raster-only call: when `conc_real` is a raster (a
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
* `mortality()` gained `chunk_ages`, the number of age strata computed per
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
  extraction and boundary rasterization steps of `mortality()` and takes the
  weighted mean from the same internal helper the aggregated result uses, so
  `conc_pwe` and `mortality(aggregate = TRUE)$conc_pwe` cannot disagree. It
  writes `.rds`/`.csv`/`.xlsx` like `build_grid_info()`, and without a domain
  column to summarise by it stops and says how to supply one.
* `mortality()` prints one `Analysis grain:` line per run: how many cells and
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
  `mortality()` itself, so the table describes exactly the grid a run on the
  same inputs uses; that is what makes one grid reusable across scenarios.
  `mortality()` now checks a supplied `calc_fild` against the raster grid when
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
* `write_mortality_xlsx()` is exported to write a `mortality()` /
  `aggregate_mortality()` result to a workbook whose location the caller
  defines: either a full file path, or an existing directory together with an
  explicit `suffix`. The former fallback name `mortality_aggregate.xlsx` was
  removed, so the package never invents an output file name.
* `cr_models()` lists the accepted model names; `rr_std()` gained a `dgt`
  argument and accepts `"UPPER"`/`"LOWER"` aliases.
* Input validation (`validate =`), all-problems-at-once input errors, a
  non-interactive resolution fallback and numeric-age coercion.
* Numeric coordinate columns are rendered as character keys at `dgt_coord`
  during ingestion, so tabular and raster inputs always share one key type;
  when `dgt_coord` cannot keep the coordinates distinct the column is left
  numeric with a warning instead of silently merging grid cells.
* `decompose()` no longer depends on `combinat`, and `serie` now follows
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
  per-column sums of every `mortality()` branch
  (`ATTRMORT_FINGERPRINTS=1`; `=update` rewrites the references).
* Manual scripts moved to `data-raw/`; `README.rmd` removed.
* Errors, warnings and progress messages now go through `cli`
  (`cli::cli_warn()`, `cli::cli_inform()`, and a package-local `.abort()`
  wrapper around `cli::cli_abort()`, so the message is not prefixed with the
  internal helper that raised it). `cli` is a new Imports dependency;
  `dplyr (>= 1.1.0)` and `purrr (>= 1.0.0)` now carry the versions the code
  already relies on (`pick()`, `.by =`, `list_rbind()`).
* `mort_lvl = NULL` (the uncalibrated grid-level mode) is reported as a message
  rather than a warning, and the branch notice is emitted once per run instead
  of once per uncertainty pass.
* Dependencies are imported by name (`@importFrom`) instead of as whole
  namespaces, so `library(AttrMort)` no longer attaches all of dplyr, tidyr,
  purrr and stringr; the unused imports of `rlang::.data` and
  `readxl::excel_sheets` are gone.
* `align_to_target()` lost its `conc_names` argument: it was documented but
  never read, and a raster that is not a population raster already takes the
  resampling branch.
* Dataset documentation gained `@source` entries; `R/data.R` no longer carries
  a second, redundant `globalVariables()` call at the top level.
* `mortality()` is now an orchestrator: each stage is one named call
  (`.check_mortality_args()`, `.map_input_columns()`, `.default_national_admin()`,
  `.report_boundary_match()`, `.uncertainty_frames()`, `.aggregate_keys()`,
  `.aggregate_result()`), and the uncertainty sides are assembled with `map()`
  instead of growing a list in a loop.
* `.calc_attributable()` was reduced to the shared pre-checks plus a dispatch:
  the three branches are `.attributable_grid()`, `.attributable_by_domain()`
  (with `.pwrr_by_domain()`) and `.attributable_one_field()`. The wide
  `{endpoint}_{age}` shape is built by `.widen_mort()` and the per-100,000
  conversion uses the `.PER_100K` constant.
* `decompose()` no longer spells out one `mortality()` call per branch:
  the 16 hand-written calls became the rule "a driver that has moved reads
  `to`" (`at()` and `run()` inside the function). The output is column-for-column
  identical to the previous implementation for all 24 orderings (checked
  against a golden capture of the shipped code).
* `.resolve_target_res()` was split into detection (`.raster_resolutions()`,
  `.grid_size()`), the decision, and the interactive menu
  (`.prompt_resolution()`); the cell-count thresholds are named constants
  (`.RES_AUTO_CONFIRM_CELLS`, `.RES_PROMPT_CELLS`, `.RES_MAX_CELLS`,
  `.RES_FALLBACK`, `.RES_SUGGESTIONS`) instead of literals in the flow.
* `.permutations()` preallocates its result, and `globalVariables()` no longer
  lists `mort_0` ... `mort_4`: the decomposition reads its step columns by name.

# AttrMort 0.2.0

* Removed the S4 OOP layer; pure functional API with the native pipe.
* Added `scenario`, `admin` and `target_res`, `Mortality_batch()` and
  `combine_batch()`, schema detection and raster I/O.

# AttrMort 0.1.0

* Initial release.