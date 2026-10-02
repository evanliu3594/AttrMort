# 未归类 hunk 清单（会话前既有改动）

总计 534 个 hunk，2939 行（+1733 / -1206）。按文件汇总，括号内为 hunk 数。

## R/mortality.R  (569 行 / 63 hunks)

- `-3 +3`  +1/-1  — # mortality() orchestrates: spatial alignment -> ingestion -> column
- `-26 +26`  +1/-1  — .check_inputs <- function(datasets, calc_fild, group = NULL) {
- `-32 +32,6`  +6/-1  — if (is.null(ds)) {
- `-38 +43`  +1/-1  — what, paste0("`", missing_val, "`", collapse = ", ")
- `-44 +49`  +1/-1  — what, paste0("`", key_cols, "`", collapse = ", "), what,
- `-65,4 +70,2`  +2/-4  — problems_txt <- paste(problems, collapse = "\n  - ")
- `-75,2 +78,2`  +2/-2  — .grid_keys <- function(grid) {
- `-83 +86`  +1/-1  — unique(paste(grid[[xy[1]]], grid[[xy[2]]]))
- `-86,48 +88,0`  +0/-48  — # Check a `calc_fild` against the raster grid, at two levels of severity.
- `-137 +92`  +1/-1  — # mortality() is grain-agnostic: `calc_fild` decides whether the analysis is
- `-149,2 +104,3`  +3/-2  — # defines the grid, otherwise the spacing of the tabular cell centres. One
- `-153 +109`  +1/-1  — return(.as_res(terra::res(template)))
- `-176,3 +132,2`  +2/-3  — res_txt <- if (all(is.finite(res)) && length(res) > 0) {
- `-227 +182`  +1/-1  — #' @param crf Character. Concentration-response model name (see
- `-229,2 +184,2`  +2/-2  — #'   same structure as [rr_std()] output (`conc`, `endpoint`, `age`, `RR`).
- `-232 +187`  +1/-1  — #'   `crf` is a data.frame.
- `-233,0 +189,6`  +6/-0  — #'   that all other inputs are joined onto. A **spatial vector layer**
- `-238,5 +199,12`  +12/-5  — #'   Optional whenever `conc_real` carries coordinates: for a **raster** (a
- `-256,0 +225,5`  +5/-0  — #'   A `mort_lvl` that names no column of `mort_rate` falls back to the
- `-262,2 +235,6`  +6/-2  — #'   from wide-format inputs (one value column per role). It is a per-input
- `-275,3 +252,6`  +6/-3  — #' @param target_res Numeric. Target grid resolution in degrees: one number,
- `-314,2 +294,2`  +2/-2  — #'   JSON config, used when `crf` is a model name. `NULL` (default) uses the
- `-341,0 +322`  +1/-0  — #' Reads the shipped example workbooks and runs the whole pipeline.
- `-350,2 +331,2`  +2/-2  — #' mortality(
- `-357,2 +338,2`  +2/-2  — #' mortality(
- `-366,3 +347,3`  +3/-3  — mortality <- function(
- `-560,2 +415,2`  +2/-2  — issues_txt <- paste(report$issues, collapse = "\n  - ")
- `-574 +429`  +1/-1  — # message belongs to mortality(), not to the age-chunked kernel, which is
- `-577,2 +432,2`  +2/-2  — cli::cli_inform(.grain_message(calc_fild, mort_lvl, mort_rate,
- `-587,2 +445,3`  +3/-2  — mort_rate, mort_lvl, crf, ci, chunk_ages,
- `-593,26 +452,3`  +3/-26  — ranges   <- if (uncertain) {
- `-623,11 +459,4`  +4/-11  — at <- .aggregate_keys(aggregate, mort_lvl)
- `-641,6 +476`  +1/-6  — # ── Stages of mortality(), each one call in the orchestrator ────────────
- `-648,6 +478`  +1/-6  — # ── the stage both entry points share ───────────────────────────────────
- `-655,4 +480,20`  +20/-4  
- `-659,0 +501,2`  +2/-0  — invisible(NULL)
- `-667 +518,55`  +55/-1  — factors <- c(1 - conc_uncert / 100, 1 + conc_uncert / 100)
- `-681,4 +586,8`  +8/-4  — # notice that goes with it (or NULL when there is nothing to say). The two
- `-686,2 +595,7`  +7/-2  — return(list(
- `-692,2 +606,7`  +7/-2  — list(
- `-709 +628`  +1/-1  — map(starts, function(s) ages[s:min(s + size - 1L, length(ages))])
- `-775 +694`  +1/-1  — age_struc, mort_rate, mort_lvl, crf, ci,
- `-777 +696`  +1/-1  — dgt_conc = 1, notify = FALSE) {
- `-780 +699`  +1/-1  — crf_label <- if (is.data.frame(crf)) {
- `-785,2 +704,2`  +2/-2  — RR_tbl <- if (is.data.frame(crf)) {
- `-788 +707`  +1/-1  — rr_std(crf_label, ci, dgt = dgt_conc, config = config)
- `-795,2 +714,3`  +3/-2  — age_struc, mort_rate, mort_lvl, crf, ci,
- `-804,3 +724,6`  +6/-3  — # The branch notice is a property of the whole run, so only the first
- `-812,2 +735,3`  +3/-2  — mort_lvl, crf, ci, warn = notify && i == 1L, config = config,
- `-816,0 +741,14`  +14/-0  — empty <- map_lgl(parts, function(part) nrow(part) == 0L)
- `-833 +771`  +1/-1  — parts <- map(seq_along(blocks), function(i) {
- `-846,8 +784,22`  +22/-8  — # for the whole run. `allow_empty` makes an empty join return the (0-row, key
- `-862,2 +814,2`  +2/-2  — RR_tbl <- if (is.data.frame(crf)) {
- `-865 +817`  +1/-1  — rr_std(crf_label, ci, dgt = dgt_conc, config = config)
- `-867,0 +820,2`  +2/-0  — list(RR_tbl = RR_tbl, crf_label = crf_label)
- `-869,20 +823,26`  +26/-20  — # Out-of-range exposures simply never join the lookup key. Say how many values
- `-890,0 +851,2`  +2/-0  — invisible(NULL)
- `-892,6 +854,11`  +11/-6  — # Endpoints and ages are joined as characters, so the user's tables have to
- `-899,2 +866,3`  +3/-2  — # A CRF whose endpoints are absent from `mort_rate` can only produce an empty
- `-913,3 +983,7`  +7/-3  — keys       <- .standardize_join_keys(mort_rate, age_struc)
- `-918,10 +992,3`  +3/-10  — out <- if (is.null(mort_lvl)) {
- `-929,19 +996,2`  +2/-19  — .attributable_by_domain(calc_fild, conc_real, conc_cf, pop_total, RR_tbl,
- `-949,20 +999,2`  +2/-20  — .attributable_one_field(calc_fild, conc_real, pop_total, RR_tbl,

## R/raster-io.R  (390 行 / 59 hunks)

- `-7 +7`  +1/-1  — #' suitable for joining with other inputs in the mortality() pipeline.
- `-28,4 +27,0`  +0/-4  — #' @examples
- `-42 +38`  +1/-1  — all(str_detect(nm, "^lyr\\.?[0-9]*$"))
- `-47,5 +43,4`  +4/-5  — .abort(str_c(
- `-59 +54`  +1/-1  — grid <- terra::as.data.frame(r, xy = TRUE, na.rm = FALSE)
- `-62,2 +57,2`  +2/-2  — value_cols <- setdiff(names(grid), c("x", "y"))
- `-65 +60`  +1/-1  — n_na <- rowSums(is.na(grid[band_names]))
- `-68,2 +63`  +1/-2  — missing <- map_int(band_names, function(b) sum(is.na(grid[[b]][incomplete])))
- `-71,9 +65,9`  +9/-9  — if (length(lines) > 5) {
- `-81 +75`  +1/-1  — grid <- filter(grid, n_na == 0)
- `-84,2 +78,2`  +2/-2  — grid$x <- matchable(grid$x, dgt = dgt)
- `-87 +81`  +1/-1  — grid
- `-104,3 +98,10`  +10/-3  — if (all(fact >= 1 - 1e-6) && all(abs(fact - round(fact)) < 1e-6)) {
- `-112,7 +118,5`  +5/-7  — cli::cli_warn(str_c(
- `-126 +130`  +1/-1  — cli::cli_warn(str_c(
- `-128,5 +132,3`  +3/-5  — "{sprintf(\"%.4f%%\", 100 * lost)} ({format(total_before, big.mark = \",\")} -> 
- `-142 +144`  +1/-1  — #' joins in the mortality() pipeline.
- `-145 +147,2`  +2/-1  — #' @param target_res Numeric. Target resolution in degrees (e.g. 0.1), one
- `-151,3 +154,2`  +2/-3  — #'   total counts. \code{NULL} guesses from the raster names: those matching
- `-157,3 +159`  +1/-3  — #' raster in \code{raster_list} is used as the reference.
- `-165,8 +164,0`  +0/-8  — #' @examples
- `-176,2 +168`  +1/-2  — pop_names     = NULL) {
- `-191 +182`  +1/-1  — resolutions <- map_dbl(raster_list, function(r) mean(terra::res(r)))
- `-194,4 +185,4`  +4/-4  — cli::cli_inform(str_c(
- `-201 +192`  +1/-1  — if (is.null(pop_names)) {
- `-203,6 +194`  +1/-6  — pop_names <- names(raster_list)[str_detect(all_names, "pop")]
- `-212 +198`  +1/-1  — aligned <- map(names(raster_list), function(nm) {
- `-217 +203`  +1/-1  — cli::cli_warn("Reprojecting '{nm}' to EPSG:4326.")
- `-231 +217`  +1/-1  — aligned
- `-241,2 +227,3`  +3/-2  — #'   or \code{NULL}. If \code{NULL}, the world country boundaries supplied by
- `-256,5 +242,0`  +0/-5  — #' @examples
- `-269 +251`  +1/-1  — .abort(str_c(
- `-272 +254`  +1/-1  — ))
- `-280 +262`  +1/-1  — .abort("shp_path must be a file path, an sf object, or NULL.")
- `-285 +267`  +1/-1  — char_cols <- names(shp)[map_lgl(shp, is.character)]
- `-288,3 +270,2`  +2/-3  — cli::cli_warn(
- `-294 +275`  +1/-1  — .abort("No character columns found in shapefile attributes.")
- `-311,2 +292`  +1/-2  — admin_df <- terra::as.data.frame(admin_raster, xy = TRUE, na.rm = TRUE)
- `-314,2 +294,2`  +2/-2  — admin_df$x <- matchable(admin_df$x, dgt = dgt)
- `-317 +297`  +1/-1  — admin_df
- `-322,0 +303,9`  +9/-0  — # Cell counts at which the resolution decision changes gear, plus the fallback
- `-332 +321,2`  +2/-1  — #' @param target_res Numeric or NULL. Explicit target resolution in degrees:
- `-334 +324,2`  +2/-1  — #' @return Numeric. The confirmed target resolution in degrees: one number for
- `-338,2 +329,9`  +9/-2  — if (!is.numeric(target_res) || !length(target_res) %in% c(1L, 2L) ||
- `-343,5 +341,4`  +4/-5  — resolutions <- .raster_resolutions(conc_rast, pop_rast)
- `-349,4 +346,3`  +3/-4  — cli::cli_inform(
- `-354,2 +350,6`  +6/-2  — # The two axes are kept apart: averaging them (the old behaviour) silently
- `-358,4 +358,6`  +6/-4  — if (n_cells < .RES_AUTO_CONFIRM_CELLS) {
- `-365,8 +367,6`  +6/-8  — if (n_cells > .RES_MAX_CELLS) {
- `-377,6 +377,5`  +5/-6  — if (n_cells > .RES_PROMPT_CELLS) {
- `-384 +383`  +1/-1  — ))
- `-387,6 +386,5`  +5/-6  — cli::cli_inform(str_c(
- `-396 +394,31`  +31/-1  — .prompt_resolution(candidate, n_cells, conc_rast, pop_rast)
- `-398,6 +426,8`  +8/-6  — cat(bar, "\n")
- `-406,11 +436,3`  +3/-11  — # ── a grid the machine can probably still handle: yes/no ───────────
- `-418,9 +440,2`  +2/-9  — if (tolower(ans) %in% c("y", "yes")) {
- `-428,3 +443,27`  +27/-3  — .abort("Aborted by user. Set target_res explicitly to skip this prompt.")
- `-432,8 +471,9`  +9/-8  — return(custom)
- `-440,0 +481`  +1/-0  — .abort("Invalid selection: {ans}")

## R/aggregate.R  (292 行 / 76 hunks)

- `-1 +1`  +1/-1  — # ── Aggregation & export of mortality() results ───────────────────────────
- `-3 +3`  +1/-1  — # Aggregation and export of mortality() results. Three rules are deliberate:
- `-22 +21,0`  +0/-1  — #   write_mortality_xlsx()     — writexl export (Suggests-guarded)
- `-48 +47,3`  +3/-1  — if (is.na(age[i])) {
- `-50 +51,3`  +3/-1  — if (cut < 1L) {
- `-53,4 +56`  +1/-4  — tibble(name = nm, endpoint = endpoint, age = age, ci = ci)
- `-61 +61`  +1/-1  — #' `mortality(ci = ...)` accepts `"MEAN"`, `"UPPER"` and `"LOWER"`
- `-79 +79`  +1/-1  — stem = if_else(is.na(token), nm, str_remove(nm, "_(MEAN|UP|UPPER|LOW|LOWER)$"))
- `-91 +91`  +1/-1  — #' mortality (value) column names of a data.frame
- `-115 +115`  +1/-1  — .abort("`at` must be \"grid\", \"geo\", or a character vector of column names.")
- `-129 +129`  +1/-1  — .abort(str_c(
- `-131,2 +131,2`  +2/-2  — "Got: {paste(utils::capture.output(str(at)), collapse = \" \")}"
- `-137 +137`  +1/-1  — .abort(str_c(
- `-139,4 +139,3`  +3/-4  — "{paste0(\"`\", missing_cols, \"`\") |> paste(collapse = \", \")}. Available col
- `-154,4 +153,4`  +4/-4  — .abort(str_c(
- `-189 +188`  +1/-1  — .abort("Internal error: `keep` must have one flag per element of `value_cols`.")
- `-193 +192`  +1/-1  — .abort("Internal error: no mortality columns selected for `{total_name}`.")
- `-200,2 +199,2`  +2/-2  — .abort(str_c(
- `-203 +202`  +1/-1  — ))
- `-219,2 +218,2`  +2/-2  — .abort(str_c(
- `-222 +221`  +1/-1  — ))
- `-297 +296`  +1/-1  — #' Takes the wide grid-level output of [mortality()] — one row per grid cell,
- `-315 +314`  +1/-1  — #' @param x A data.frame from [mortality()], or a named list of them (one per
- `-338 +337`  +1/-1  — #'   `na.rm`). Default `TRUE`, matching [mortality()]'s use of `na.rm = TRUE`.
- `-343,2 +342,2`  +2/-2  — #' @seealso [aggregate_ci()] for CI-branch (`mortality(ci = ...)`) output,
- `-376 +376`  +1/-1  — .abort("`na_rm` must be TRUE or FALSE.")
- `-382,7 +382,7`  +7/-7  — found_txt <- paste0("`", utils::head(value_names[ci_suffixed], 3L), "`") |>
- `-391 +391`  +1/-1  — .abort(str_c(
- `-393 +393`  +1/-1  — "`{{endpoint}}_{{age}}` (e.g. `ncd+lri_50`, `ihd_25`). A result carrying CI ",
- `-395 +395`  +1/-1  — ))
- `-398 +398`  +1/-1  — value_cols <- set_names(value_names)
- `-406 +406,2`  +2/-1  — x = result, value_cols = value_cols,
- `-409 +410`  +1/-1  — parse = .split_mort_names(names(result))
- `-418 +419`  +1/-1  — #' Aggregate mortality() output carrying CI branches
- `-422 +423`  +1/-1  — #' with `ci` in `MEAN`/`UP`/`LOW` — the three CI branches of [mortality()]
- `-429 +430`  +1/-1  — #' [mortality()] itself does not append the `ci` suffix, so build the input by
- `-431,2 +432,2`  +2/-2  — #' `paste0(names(x), "_MEAN")` for the `ci = "MEAN"` run.  `_UPPER` / `_LOWER`
- `-466 +468`  +1/-1  — #'   # mortality() does not add the CI suffix — paste it on per branch
- `-487 +489`  +1/-1  — .abort(str_c(
- `-489 +491`  +1/-1  — "named `{{endpoint}}_{{age}}_{{CI}}` with CI in MEAN/UP/LOW ",
- `-491 +493`  +1/-1  — "runs of mortality() side by side. For plain `{{endpoint}}_{{age}}` output ",
- `-493 +495`  +1/-1  — ))
- `-499,5 +501,5`  +5/-5  — .abort(str_c(
- `-508 +510`  +1/-1  — .abort(str_c(
- `-510,3 +512,3`  +3/-3  — "{paste0(\"`\", unparsed, \"`\") |> paste(collapse = \", \")}. ",
- `-515 +517`  +1/-1  — value_cols <- set_names(ci_cols)
- `-525,2 +527,2`  +2/-2  — col_branch <- set_names(
- `-532 +534`  +1/-1  — x = result, value_cols = value_cols, keep = col_branch == ci,
- `-534 +536`  +1/-1  — total_name = "total", na_rm = TRUE, parse = result_parse
- `-575 +577`  +1/-1  — .abort(str_c(
- `-577,2 +579,2`  +2/-2  — "{class(x)[1L]}"
- `-582 +584`  +1/-1  — .abort(str_c(
- `-584,2 +586,2`  +2/-2  — "{paste0(\"`\", names(x)[bad], \"`\") |> paste(collapse = \", \")}"
- `-588 +590`  +1/-1  — .abort(str_c(
- `-591 +593`  +1/-1  — ))
- `-598 +600`  +1/-1  — #' @param result A grid-level result.
- `-601 +603`  +1/-1  — #' @return `result`, with the missing domain columns added from `calc_fild`.
- `-608 +610`  +1/-1  — .abort("`calc_fild` must be a data.frame or NULL.")
- `-611,4 +613,12`  +12/-4  — # Coordinates first: `result` is one row per grid cell, so joining it on a
- `-616 +626,4`  +4/-1  — shared <- intersect(
- `-619 +632`  +1/-1  — .abort(str_c(
- `-627 +652`  +1/-1  — joined <- left_join(result, calc_fild, by = shared)
- `-630,2 +655,3`  +3/-2  — .abort(str_c(
- `-633 +659`  +1/-1  — ))
- `-649 +675`  +1/-1  — imap(function(result, nm) mutate(result, scenario = nm, .before = 1L)) |>
- `-653 +679`  +1/-1  — # ── export helper ────────────────────────────────────────────────────────
- `-655 +681,6`  +6/-1  — #' Write mortality results to an xlsx workbook
- `-657,4 +688,4`  +4/-4  — #' Where the file goes is always the caller's decision: `path` is either the
- `-663,6 +694,4`  +4/-6  — #' @param path Character. Full output file path, or an existing directory when
- `-671 +700,11`  +11/-1  — #' @export
- `-674,5 +713,7`  +7/-5  — .abort(
- `-687,3 +728,5`  +5/-3  — .abort(
- `-698 +741,3`  +3/-1  — .abort(
- `-701,2 +746,4`  +4/-2  — if (!is.character(suffix) || length(suffix) != 1L || is.na(suffix) || !nzchar(su
- `-706 +753,6`  +6/-1  — .abort(
- `-712,3 +764,5`  +5/-3  — .abort(

## R/utils.R  (288 行 / 16 hunks)

- `-26,3 +43,6`  +6/-3  — .abort(
- `-40,2 +60,3`  +3/-2  — cli::cli_inform(str_c(
- `-45,4 +66,5`  +5/-4  — .abort(
- `-74,6 +104,92`  +92/-6  — if (cause) {
- `-81 +197,4`  +4/-1  — .abort(str_c(
- `-118,0 +238`  +1/-0  — # ── one input, one scenario ─────────────────────────────────────────────
- `-120,27 +239,0`  +0/-27  — #' Extract one scenario of gridded exposure data
- `-148,17 +240,0`  +0/-17  — #' Extract one scenario of population data
- `-166,2 +241,0`  +0/-2  — .data |> select(all_of(keys), pop = !!case)
- `-169,30 +242,0`  +0/-30  — #' Extract one scenario of population age structure
- `-200,5 +244,8`  +8/-5  — # Write a table to `path`, chosen by extension: `.rds` (saveRDS()), `.csv`
- `-217,5 +277,2`  +2/-5  — cli::cli_inform("{label} written to: {normalizePath(path, mustWork = FALSE)}")
- `-224,35 +281,10`  +10/-35  — # Cell size as it is reported: the x and y values when the axes differ, one
- `-259,0 +292,2`  +2/-0  — res
- `-261,7 +295,3`  +3/-7  — # Cell size for a message: "2.5", "0.25" or "2.5 x 2".
- `-268,0 +299,8`  +8/-0  

## R/ingest.R  (177 行 / 38 hunks)

- `-15 +15`  +1/-1  — .abort("File not found: {x} (input `{nm}`)")
- `-29 +29`  +1/-1  — .abort(str_c(
- `-31,3 +31,2`  +2/-3  — "Got: {paste(class(x), collapse = \"/\")}."
- `-36 +35`  +1/-1  — .abort("A file path must be a single character string.")
- `-39 +38`  +1/-1  — .abort("File not found: {x}")
- `-58,6 +57,4`  +4/-6  — .abort(str_c(
- `-80 +92`  +1/-1  — data[[col]] <- key
- `-82,6 +94,5`  +5/-6  — cli::cli_warn(str_c(
- `-90 +101`  +1/-1  — data
- `-96 +107`  +1/-1  — data <- .ingest_single_input(x, dgt_coord)
- `-106 +117`  +1/-1  — (target == unname(mapping) | !target %in% names(data))
- `-111 +122`  +1/-1  — renamed <- set_names(unname(mapping), target)
- `-114 +125,3`  +3/-1  — # Interpolated as a value: a column name may contain braces, and glue
- `-117,0 +131`  +1/-0  — cli::cli_inform("{mapping_txt}")
- `-119 +133`  +1/-1  — data <- data |> rename(!!!renamed)
- `-123 +137`  +1/-1  — .normalise_coord_keys(data, dgt_coord)
- `-157,2 +182,2`  +2/-2  — .rename_single_band <- function(data, scenario, what) {
- `-161 +186`  +1/-1  — val_cols <- setdiff(names(data), c("x", "y"))
- `-163 +188`  +1/-1  — return(data)
- `-165,2 +190,2`  +2/-2  — if (!is.null(scenario) && !str_detect(val_cols[1], "^band")) {
- `-170 +195`  +1/-1  — return(data)
- `-172,4 +197,3`  +3/-4  — names(data)[names(data) == val_cols[1]] <- target
- `-180,0 +205,6`  +6/-0  — #
- `-182 +212`  +1/-1  — target_res, dgt_coord, template = NULL) {
- `-196 +226,5`  +5/-1  — final_res <- if (is.null(template)) {
- `-200,2 +234,6`  +6/-2  — if (conc_is_rast) {
- `-205,2 +243,3`  +3/-2  — target_res    = final_res,
- `-215 +254,3`  +3/-1  — if (is.null(out$template)) {
- `-243,0 +291,8`  +8/-0  — #
- `-245 +300`  +1/-1  — template = NULL, dgt_coord = 2) {
- `-250,14 +305,5`  +5/-14  — admin_df <- if (is.null(template)) {
- `-266,3 +311,0`  +0/-3  — admin_df <- shapefile_to_grid(admin, template,
- `-272 +315`  +1/-1  — cli::cli_inform("Admin column renamed: {admin_col} -> {mort_lvl}")
- `-276 +319`  +1/-1  — admin_vals <- unique(stats::na.omit(admin_df[[admin_val_col]]))
- `-281,8 +324,5`  +5/-8  — cli::cli_warn(str_c(
- `-294,0 +369,5`  +5/-0  — .abort(str_c(
- `-297,3 +376,3`  +3/-3  — cli::cli_inform(
- `-337,0 +448,12`  +12/-0  — hit <- sf::st_join(pts, shp[, admin_col, drop = FALSE],

## R/decompose.R  (137 行 / 12 hunks)

- `-9 +9`  +1/-1  — out <- vector("list", length(x))
- `-13 +13`  +1/-1  — list_flatten(out)
- `-16 +16,21`  +21/-1  — #' Decompose attributed deaths between two sets of inputs
- `-55 +50,5`  +5/-1  — #' @return A named list of 24 data frames, one per ordering of the four drivers
- `-60 +59,2`  +2/-1  — #'   extdata <- system.file("extdata", package = "AttrMort")
- `-78,0 +81,5`  +5/-0  — #'
- `-283,12 +151,17`  +17/-12  — if (!report$valid && validate == "stop") {
- `-296 +169,44`  +44/-1  — }
- `-298,5 +214,5`  +5/-5  — # ── Start, one column per driver, End; one table per ordering ──────
- `-306 +222`  +1/-1  — intersect(names(state(character(0))))
- `-309,5 +225,4`  +4/-5  — .abort(str_c(
- `-367 +315`  +1/-1  — out

## R/rr_std.R  (119 行 / 24 hunks)

- `-18 +18`  +1/-1  — .abort("`ci` must be a single character string.")
- `-23,4 +23,5`  +5/-4  — .abort(
- `-44 +44`  +1/-1  — if (str_detect(path, "^(/|[A-Za-z]:[\\\\/]|\\\\\\\\|//)")) {
- `-54,3 +54,2`  +2/-3  — .abort(
- `-62,4 +61,3`  +3/-4  — branch_tbl <- tab[[branch]]
- `-67,6 +65,6`  +6/-6  — if (!entry$conc_col %in% names(branch_tbl)) {
- `-75,4 +73,5`  +5/-4  — branch_tbl <- rename(branch_tbl, conc = all_of(entry$conc_col))
- `-80 +79`  +1/-1  — cols <- setdiff(names(branch_tbl), "conc")
- `-82,2 +81,3`  +3/-2  — .abort(str_c(
- `-88,3 +88,4`  +4/-3  — .abort(str_c(
- `-92 +93`  +1/-1  — tab[[branch]] <- branch_tbl
- `-106,6 +107,6`  +6/-6  — .abort(
- `-128 +129`  +1/-1  — .abort("Lookup table not found in AttrMort: {lk$table}.")
- `-137 +138`  +1/-1  — .abort("Lookup file not found: {path}")
- `-140,2 +141,4`  +4/-2  — .abort(str_c(
- `-148,2 +151,3`  +3/-2  — .abort(str_c(
- `-155,2 +159,3`  +3/-2  — .abort(str_c(
- `-166 +171`  +1/-1  — .abort("Lookup csv not found: {file}")
- `-172,2 +177,2`  +2/-2  — tab <- set_names(
- `-192 +197`  +1/-1  — #' @param ci Character. Which table to use: `"MEAN"` (default), `"UP"` or
- `-196 +201`  +1/-1  — #'   [mortality()]). Default 1.
- `-228 +233`  +1/-1  — grid <- map(entry$endpoints, function(ep) {
- `-256,5 +261,6`  +6/-5  — .abort(
- `-265 +271`  +1/-1  — ep_names <- tolower(map_chr(entry$endpoints, "name"))

## tests/testthat/test-mortality.R  (108 行 / 21 hunks)

- `-1 +1`  +1/-1  — # Tests for mortality() — the core attributable-mortality calculation
- `-3 +3`  +1/-1  — describe("mortality() on the small fixture", {
- `-15 +15`  +1/-1  — rr   <- rr_std("GEMM", "MEAN")
- `-32,2 +32,2`  +2/-2  — doubled <- mortality(
- `-48 +48,3`  +3/-1  — # The uncalibrated mode is reported with a message, not a warning.
- `-53,4 +55,36`  +36/-4  — it("falls back to the domain column mort_rate carries itself", {
- `-62 +96,2`  +2/-1  — warns <- new.env(parent = emptyenv())
- `-64,2 +99,2`  +2/-2  — mortality(
- `-67 +102`  +1/-1  — mort_rate = d$mort_rate, mort_lvl = "location", validate = "warn"
- `-70 +105`  +1/-1  — warns$msg <- c(warns$msg, conditionMessage(w))
- `-74,2 +109,2`  +2/-2  — expect_true(any(grepl("outside the CRF lookup range", warns$msg)))
- `-95,3 +130,3`  +3/-3  — rr <- rr_std("GEMM", "MEAN")
- `-105 +140`  +1/-1  — describe("mortality() input checks", {
- `-109,2 +144,2`  +2/-2  — mortality(
- `-125,2 +207,2`  +2/-2  — expect_error(.attr_run(crf = "NOPE"), "Unknown CR model")
- `-130 +212`  +1/-1  — msg <- tryCatch(.attr_run(crf = "NO2"), error = function(e) conditionMessage(e))
- `-142,2 +224,2`  +2/-2  — mortality(
- `-155,2 +237,2`  +2/-2  — mortality(
- `-162,0 +245,7`  +7/-0  
- `-165 +254`  +1/-1  — describe("mortality() on the shipped example data", {
- `-167,2 +256,2`  +2/-2  — out <- suppressWarnings(suppressMessages(mortality(

## R/data.R  (106 行 / 26 hunks)

- `-3,2 +15,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-5,0 +18,2`  +2/-0  — #' @source Burnett et al. (2014), \emph{Environmental Health Perspectives}
- `-8 +22,5`  +5/-1  — #' IER concentration-response lookup table (GBD 2010)
- `-10,2 +28,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-12,0 +31,2`  +2/-0  — #' @source Global Burden of Disease Study 2010 comparative risk assessment
- `-15 +35,5`  +5/-1  — #' IER concentration-response lookup table (GBD 2013)
- `-17,2 +41,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-19,0 +44,2`  +2/-0  — #' @source Global Burden of Disease Study 2013 comparative risk assessment
- `-22 +48,5`  +5/-1  — #' IER concentration-response lookup table (GBD 2015)
- `-24,2 +54,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-26,0 +57,2`  +2/-0  — #' @source Global Burden of Disease Study 2015 comparative risk assessment
- `-29 +61,5`  +5/-1  — #' IER concentration-response lookup table (GBD 2017)
- `-31,2 +67,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-33,0 +70,2`  +2/-0  — #' @source Global Burden of Disease Study 2017 comparative risk assessment
- `-36 +74,6`  +6/-1  — #' MR-BRT concentration-response lookup table (GBD 2019)
- `-38,2 +81,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-40,0 +84,2`  +2/-0  — #' @source Global Burden of Disease Study 2019 risk-factor analysis (Institute
- `-43 +88,6`  +6/-1  — #' MR-BRT concentration-response lookup table (GBD 2021)
- `-45,2 +95,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-47,0 +98,2`  +2/-0  — #' @source Global Burden of Disease Study 2021 risk-factor analysis (Institute
- `-50 +102,5`  +5/-1  — #' NO2 concentration-response lookup table
- `-52,2 +108,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-54,0 +111,3`  +3/-0  — #' @source The NO<sub>2</sub> relative-risk curve of the Global Burden of
- `-57 +116,5`  +5/-1  — #' O3 concentration-response lookup table
- `-59,2 +122,2`  +2/-2  — #'   wide data.frame: a character \code{conc} column rendered at one decimal
- `-61,0 +125,3`  +3/-0  — #' @source Carey et al. (2013), "mortality associations with long-term exposure

## tests/testthat/test-cr-config.R  (95 行 / 25 hunks)

- `-37,3 +37,4`  +4/-3  — f <- .cfg_with_model(paste0(
- `-59 +60`  +1/-1  — it("describes exactly the endpoints and ages rr_std() produces", {
- `-63 +64`  +1/-1  — produced <- unique(rr_std(model, "MEAN")[, c("endpoint", "age")])
- `-104,3 +105,4`  +4/-3  — f <- .cfg_with_model(paste0(
- `-109,3 +111,4`  +4/-3  — f <- .cfg_with_model(paste0(
- `-124 +127,3`  +3/-1  — f <- .cfg_with_model(
- `-135 +140,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-138 +146,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-141 +152,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-156,3 +170,4`  +4/-3  — f <- .cfg_with_model(paste0(
- `-163 +178,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-168 +186,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-171 +192,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-174 +198,4`  +4/-1  — f <- .cfg_with_model(paste0(
- `-199 +226`  +1/-1  — expect_error(rr_std("BAD", config = f), "no columns for endpoint")
- `-221 +248`  +1/-1  — out <- rr_std("HOLED", config = f)
- `-243 +270`  +1/-1  — expect_error(rr_std("SPLIT", config = f), "share the same columns")
- `-295 +322`  +1/-1  — out <- rr_std("MYX", "MEAN", config = cfg)
- `-302 +329`  +1/-1  — up <- rr_std("MYX", "UP", config = cfg)
- `-312 +339`  +1/-1  — out <- rr_std("MYX", "MEAN", config = cfg)
- `-317 +344`  +1/-1  — it("runs through mortality() with cr_config =", {
- `-329,2 +356,2`  +2/-2  — out <- mortality(
- `-347 +374`  +1/-1  — expect_error(rr_std("MYX", config = bad_sheet))
- `-356 +383`  +1/-1  — expect_error(rr_std("MYX", config = bad_path), "not found")
- `-366 +393`  +1/-1  — expect_error(rr_std("MYX", config = no_conc), "nope")

## R/build-cr.R  (86 行 / 27 hunks)

- `-5 +5`  +1/-1  — # the result is exactly what rr_std() consumes:
- `-24,2 +24`  +1/-2  — .abort("`parameters` must be a data.frame or a single file path.")
- `-28 +27`  +1/-1  — .abort("File not found: {parameters}")
- `-36,2 +35,4`  +4/-2  — .abort(str_c(
- `-50 +51`  +1/-1  — coefs <- rename_with(coefs, ~ target, all_of(hit[1]))
- `-58 +59`  +1/-1  — if_else(tolower(x) == "alri", "LRI", x)
- `-64,2 +65,2`  +2/-2  — x <- if_else(str_detect(x, regex("^(A|a)ll ?(A|a)ge", ignore_case = TRUE)),
- `-88,4 +89,5`  +5/-4  — .abort(str_c(
- `-94 +96`  +1/-1  — .abort("Coefficient table is empty.")
- `-101 +103`  +1/-1  — bad <- map_lgl(numeric_cols, function(col) anyNA(coefs[[col]]))
- `-103,2 +105,4`  +4/-2  — .abort(str_c(
- `-133 +137`  +1/-1  — out[[i]] <- tibble(
- `-141,2 +145`  +1/-2  — names = FALSE)
- `-145 +148`  +1/-1  — list_rbind(out)
- `-164 +167`  +1/-1  — tibble(
- `-170,2 +173`  +1/-2  — UP    = exp((theta + zfac * se) * base)
- `-179 +181`  +1/-1  — .abort("`model` must be a single character string.")
- `-188,2 +190,4`  +4/-2  — .abort(str_c(
- `-195 +199`  +1/-1  — #' `list(MEAN, LOW, UP)` structure that [rr_std()] consumes and that the
- `-198 +202`  +1/-1  — #' get a table that can be handed to `mortality(crf = )` — either directly as
- `-209 +213,2`  +2/-1  — #' @param model Character. Which functional form to use: `"IER"` (default) or
- `-213 +218`  +1/-1  — #'   matching `dgt_conc` in [mortality()]. Default 1.
- `-234 +239`  +1/-1  — model         = "IER",
- `-242,2 +247`  +1/-2  — .abort("`level` must be a single number strictly between 0 and 1.")
- `-249 +253`  +1/-1  — .abort("`conc` must be a non-empty numeric vector.")
- `-263 +267`  +1/-1  — tabs <- map(c("MEAN", "LOW", "UP"), function(index) {
- `-273,3 +277,5`  +5/-3  — .abort(str_c(

## R/grid-info.R  (72 行 / 24 hunks)

- `-10 +10`  +1/-1  — # phases 1, 2 and 4 of the mortality() pipeline do all the work
- `-12 +12`  +1/-1  — # .attach_admin()), so the table describes exactly the grid a mortality() run
- `-45 +44,2`  +2/-1  — # tabular grid carries no CRS -- plain coordinates do not name one. `res` is
- `-49 +49`  +1/-1  — res = .as_res(terra::res(template)),
- `-58,2 +58,6`  +6/-2  — if (all(is.na(res))) {
- `-62,2 +66,3`  +3/-2  — res = .as_res(res),
- `-71 +76`  +1/-1  — #' Describes the grid a [mortality()] run uses, as a table: one row per grid
- `-75 +80`  +1/-1  — #' The grid is defined by `conc_real`, exactly as in [mortality()] -- a raster
- `-78 +83`  +1/-1  — #' [mortality()] reads them, so the target resolution resolved here is the one
- `-85 +90`  +1/-1  — #' that says which. Hand it back as `calc_fild =` and [mortality()] checks the
- `-93 +98`  +1/-1  — #'   way [mortality()] aligns it. It does not define the grid's extent, but a
- `-95 +100`  +1/-1  — #'   resolution -- the same interaction [mortality()] has.
- `-97 +102`  +1/-1  — #'   [mortality()] so that one argument list can be reused; it is aligned like
- `-101 +106`  +1/-1  — #'   in, exactly as `admin =` does in [mortality()].
- `-103 +108`  +1/-1  — #'   label. `NULL` (default) uses `"admin"`, the default of [mortality()]; an
- `-106,2 +111,3`  +3/-2  — #' @param target_res Numeric. Target grid resolution in degrees: one number,
- `-125 +131,2`  +2/-1  — #'     resolution, or the spacing of a tabular grid's cell centres. One number
- `-134 +141`  +1/-1  — #' @seealso [mortality()]
- `-150,0 +158`  +1/-0  — #'   # Needs raster files on disk.
- `-158 +166`  +1/-1  — #'     mortality(crf = "GEMM", calc_fild = gi, scenario = s,
- `-170 +178`  +1/-1  — # ── phase 1-2: alignment, exactly as mortality() does it ───────────
- `-186,6 +194,7`  +7/-6  — .abort(
- `-213 +222`  +1/-1  — template = spatial$template,
- `-236 +245`  +1/-1  — # return value, in the formats the package reads back.

## tests/testthat/test-grid-path.R  (63 行 / 16 hunks)

- `-11 +11`  +1/-1  — # When   - mortality() is called on the raster inputs
- `-87,2 +87,2`  +2/-2  — suppressWarnings(suppressMessages(mortality(
- `-102,2 +102,2`  +2/-2  — suppressWarnings(suppressMessages(mortality(
- `-112 +112`  +1/-1  — describe("mortality() on raster inputs without calc_fild", {
- `-136,2 +136,2`  +2/-2  — blank <- suppressWarnings(suppressMessages(mortality(
- `-155,2 +155,2`  +2/-2  — grid <- suppressWarnings(suppressMessages(mortality(
- `-170 +170,5`  +5/-1  — it("takes the grid from a tabular exposure, then asks for the domains", {
- `-173,2 +177,15`  +15/-2  — suppressWarnings(suppressMessages(mortality(
- `-178 +195`  +1/-1  — "needs a `conc_real` that carries coordinates"
- `-185,2 +202,2`  +2/-2  — suppressWarnings(mortality(
- `-196 +213`  +1/-1  — describe("mortality() national boundary default", {
- `-224,2 +241,2`  +2/-2  — suppressWarnings(suppressMessages(mortality(
- `-252 +342`  +1/-1  — suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
- `-269 +402`  +1/-1  — suppressWarnings(suppressMessages(do.call(mortality, c(base, list(...)))))
- `-289 +422`  +1/-1  — mortality(crf = "GEMM", conc_real = 1, pop_total = 1, age_struc = 1,
- `-296 +429`  +1/-1  — describe("mortality() on netCDF exposure", {

## tests/testthat/test-decompose.R  (61 行 / 8 hunks)

- `-1 +1`  +1/-1  — # Tests for decompose() — driving-factor decomposition
- `-6 +6`  +1/-1  — # every column must reproduce a mortality() run with a specific prefix of the
- `-50 +76`  +1/-1  — # order decompose() itself uses.
- `-59 +85`  +1/-1  — describe("decompose() permutations", {
- `-72,2 +118,43`  +43/-2  — groups <- .attr_groups(d)
- `-77 +164`  +1/-1  — describe("decompose() on the small fixture", {
- `-137,2 +267,3`  +3/-2  — d      <- .attr_two_scenario()
- `-147,0 +277`  +1/-0  — low   <- low[[1]]

## R/schema-detect.R  (55 行 / 18 hunks)

- `-3 +3`  +1/-1  — # Both functions are internal: mortality() calls them on every invocation, so
- `-41 +41`  +1/-1  — # per-field warnings and the mapping report, which is what mortality() wants
- `-43 +43`  +1/-1  — detect_columns <- function(data,
- `-47,2 +47,2`  +2/-2  — stopifnot(is.data.frame(data))
- `-56 +56,3`  +3/-1  — if (is.null(variants)) {
- `-60 +62`  +1/-1  — # exact match on the normalised name first (`Mort Rate` finds mortrate)
- `-72 +74`  +1/-1  — idx <- which(str_detect(col_lower, fixed(tolower(v))))
- `-85,2 +87`  +1/-2  — cli::cli_warn("detect_columns: no column found for '{semantic}'")
- `-91,2 +92,4`  +4/-2  — cli::cli_inform(str_c(
- `-100 +103`  +1/-1  — # mortality()).
- `-111,2 +114,3`  +3/-2  — state <- new.env(parent = emptyenv())
- `-116,2 +120,2`  +2/-2  — state$issues <- c(state$issues, msg)
- `-121,2 +125,2`  +2/-2  — state$issues   <- c(state$issues, msg)
- `-145 +149`  +1/-1  — nums <- names(mort)[map_lgl(mort, is.numeric)]
- `-171 +175`  +1/-1  — expected_ep <- map_chr(entry$endpoints, "name")
- `-228 +235`  +1/-1  — nums <- names(conc_df)[map_lgl(conc_df, is.numeric)]
- `-244 +251,3`  +3/-1  — if (is.factor(raw)) {
- `-274 +283,2`  +2/-1  — list(valid = length(state$blocking) == 0, issues = state$issues,

## tests/testthat/test-grid-info.R  (53 行 / 8 hunks)

- `-3,2 +3,2`  +2/-2  — # `build_grid_info()` renders the grid a `mortality()` run uses as a table, and
- `-112 +112`  +1/-1  — crf = "GEMM", conc_real = tifs$conc, pop_total = tifs$pop,
- `-122 +122`  +1/-1  — suppressWarnings(suppressMessages(do.call(mortality, args)))
- `-127,2 +127,2`  +2/-2  — suppressWarnings(suppressMessages(mortality(
- `-138 +138`  +1/-1  — describe("build_grid_info() feeding mortality()", {
- `-174,0 +175,31`  +31/-0  — it("keeps a non-square tabular grid's resolution per axis", {
- `-189,2 +220,2`  +2/-2  — suppressMessages(mortality(
- `-224,2 +255,2`  +2/-2  — warned <- capture_warnings(kept <- suppressMessages(mortality(

## tests/testthat/test-rr_std.R  (38 行 / 15 hunks)

- `-1 +1`  +1/-1  — # Tests for rr_std() — concentration-response lookup standardisation
- `-3 +3`  +1/-1  — describe("rr_std()", {
- `-5 +5`  +1/-1  — out <- rr_std("GEMM", "MEAN")
- `-14 +14`  +1/-1  — d1 <- rr_std("GEMM", "MEAN", dgt = 1)$conc
- `-16 +16`  +1/-1  — expect_equal(rr_std("GEMM", "MEAN", dgt = 0)$conc,
- `-18 +18`  +1/-1  — expect_equal(rr_std("GEMM", "MEAN", dgt = 2)$conc,
- `-23 +23`  +1/-1  — expect_equal(rr_std("gemm", "MEAN"), rr_std("GEMM", "MEAN"))
- `-27,3 +27,3`  +3/-3  — expect_equal(rr_std("GEMM", "UPPER"), rr_std("GEMM", "UP"))
- `-33,2 +33,2`  +2/-2  — expect_error(rr_std("UNKNOWN_MODEL"), "Unknown CR model")
- `-38 +38`  +1/-1  — out <- rr_std("NCD+LRI", "MEAN")
- `-45 +45`  +1/-1  — out <- rr_std("5COD", "MEAN")
- `-50 +50`  +1/-1  — out <- rr_std("IER", "MEAN")
- `-58,2 +58,2`  +2/-2  — expect_equal(unique(rr_std("O3", "MEAN")$endpoint), "copd")
- `-65 +65`  +1/-1  — out <- rr_std(model, index)
- `-82 +82`  +1/-1  — # what rr_std() renders: NO2 used to be a double column with ~1e-12

## tests/testthat/test-uncertainty.R  (35 行 / 9 hunks)

- `-1 +1`  +1/-1  — # Tests for the aggregation and uncertainty arguments of mortality()
- `-3 +3`  +1/-1  — describe("mortality(aggregate = ...)", {
- `-18,2 +18,2`  +2/-2  — agg <- mortality(
- `-51,0 +52,2`  +2/-0  — # An uncalibrated run is a documented mode, not a fault: it is reported
- `-53,2 +55`  +1/-2  — agg <- suppressWarnings(.attr_run(aggregate = TRUE, mort_lvl = NULL, validate = 
- `-56,0 +58,4`  +4/-0  — expect_message(
- `-60,0 +66,12`  +12/-0  — it("reports a whole-field range when aggregate = TRUE and mort_lvl is NULL", {
- `-74 +91`  +1/-1  — describe("mortality(uncertain = TRUE)", {
- `-77,2 +94,2`  +2/-2  — mortality(

## R/cr-config.R  (31 行 / 10 hunks)

- `-20 +24`  +1/-1  — .abort("CR config `{field}`: {msg}")
- `-33 +37`  +1/-1  — .abort(str_c(
- `-35,3 +39,2`  +2/-3  — "Got: {paste(class(config), collapse = \"/\")}."
- `-280 +301`  +1/-1  — .abort("`path` must be NULL or a single file path.")
- `-283 +304`  +1/-1  — .abort("CR config not found: {path}")
- `-286 +307`  +1/-1  — .abort("CR config path is a directory, not a file: {path}")
- `-293,2 +314`  +1/-2  — .abort("Cannot parse CR config {path}: {conditionMessage(e)}")
- `-310 +330`  +1/-1  — key <- toupper(trimws(crf))
- `-343,0 +363,9`  +9/-0  — #' Print a concentration-response model configuration
- `-344,0 +373,2`  +2/-0  — #' @examples

## tests/testthat/fixtures/fingerprints/gemm-lvlMissing.csv  (30 行 / 1 hunks)

- `-2,15 +2,15`  +15/-15  — "ncd+lri_25",741.187376506934

## R/AttrMort-package.R  (25 行 / 5 hunks)

- `-13,2 +13,2`  +2/-2  — #' can be supplied as a custom lookup table through the `crf` argument of
- `-17 +17`  +1/-1  — #' * [mortality()] — attributable deaths per scenario, per grid cell or per
- `-19 +19`  +1/-1  — #' * [decompose()] — driving-factor decomposition
- `-40,0 +45,9`  +9/-0  — # Report an error the user can act on, without the calling frame: almost every
- `-43,4 +56,4`  +4/-4  — ".", ".total", "age", "attr_mort", "cause", "col", "column",

## tests/testthat/test-schema-detect.R  (23 行 / 5 hunks)

- `-141,2 +141,3`  +3/-2  — validate_with_warnings <- function(data_list) {
- `-148 +149`  +1/-1  — state$warns <- c(state$warns, conditionMessage(w))
- `-152 +153`  +1/-1  — list(report = report, warns = state$warns)
- `-157,3 +158,4`  +4/-3  — res <- validate_with_warnings(list(
- `-164,3 +166,4`  +4/-3  — res <- validate_with_warnings(list(

## tests/testthat/test-aggregate.R  (21 行 / 4 hunks)

- `-257 +257`  +1/-1  — # GIVEN a result suffixed with the UPPER/LOWER spellings that mortality()'s
- `-299 +299`  +1/-1  — # GIVEN a plain (no CI suffix) mortality() result,
- `-327 +327`  +1/-1  — describe("write_mortality_xlsx()", {
- `-375,0 +376,15`  +15/-0  

## R/uncertainty.R  (20 行 / 8 hunks)

- `-3 +3`  +1/-1  — # The interval reported by mortality(uncertain = TRUE) is a *range* built from
- `-23 +23`  +1/-1  — # Sum over the value columns of each row of a mortality() result.
- `-26 +26`  +1/-1  — vals <- vals[map_lgl(x[vals], is.numeric)]
- `-58,0 +88,4`  +4/-0  
- `-60 +93`  +1/-1  — return(tibble(.total = sum(totals, na.rm = TRUE)))
- `-72,0 +109,2`  +2/-0  — # No baseline is passed: the chains are grid-level while `out` is already
- `-90,2 +128,2`  +2/-2  — reduce(.left_join_common) |>
- `-94 +132`  +1/-1  — return(tibble(conc_pwe = weighted.mean(as.numeric(pwe$conc), pwe$pop)))

## tests/testthat/test-fingerprints.R  (12 行 / 5 hunks)

- `-1 +1`  +1/-1  — # Fingerprint regression: pins the per-column sums of every mortality() branch.
- `-31 +31`  +1/-1  — runs[[paste0("crf-", model)]] <- c(list(crf = model, mort_lvl = "location"),
- `-34,2 +34,2`  +2/-2  — runs[["gemm-lvlNULL"]] <- c(list(crf = "GEMM", mort_lvl = NULL), base)
- `-47 +47`  +1/-1  — res <- suppressWarnings(suppressMessages(do.call(mortality, args)))
- `-57 +57`  +1/-1  — describe("mortality() fingerprints", {

## tests/testthat/test-build-cr.R  (11 行 / 2 hunks)

- `-20,0 +21,9`  +9/-0  — it("defaults to the IER form when `model` is omitted", {
- `-101 +110`  +1/-1  — it("produces columns that rr_std() can reshape", {

## tests/testthat/test-raster-io.R  (8 行 / 3 hunks)

- `-195 +251`  +1/-1  — describe("mortality() from gridded GeoTIFF inputs", {
- `-218,2 +274,2`  +2/-2  — out <- suppressMessages(mortality(
- `-230 +286`  +1/-1  — rr_all <- rr_std("GEMM", "MEAN")

## tests/testthat/helper-data.R  (6 行 / 3 hunks)

- `-69 +69`  +1/-1  — # Run mortality() on either fixture with sensible defaults.
- `-74 +74`  +1/-1  — .attr_run <- function(crf = "GEMM", mort_lvl = "location", long = TRUE,
- `-78 +78`  +1/-1  — crf       = crf,

## DESCRIPTION  (5 行 / 2 hunks)

- `-26 +26,2`  +2/-1  — cli,
- `-28 +29`  +1/-1  — purrr (>= 1.0.0),

## NAMESPACE  (3 行 / 1 hunks)

- `-4,3 +3,0`  +0/-3  — export(Decomposition)

