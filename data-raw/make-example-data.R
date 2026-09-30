# 生成 inst/extdata/ 下的全部示例数据。
#
# 本脚本**不依赖任何外部数据源**：所有数值都是合成的（含固定的随机种子），
# 只有 data/ 下的浓度-反应查表是真实发表的曲线。重新运行即可复现同样的文件；
# tests/testthat/test-fingerprints.R 会把这些数据推过每条分支并锁定结果。
#
#   Rscript data-raw/make-example-data.R
#
# 需要 writexl（在 DESCRIPTION 的 Suggests 中）。

set.seed(20260930)

out_dir <- file.path("inst", "extdata")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

countries  <- c("Aland", "Borduria", "Cyrenia")
scenarios  <- c("base2015", "scenario2030")
ages       <- as.character(seq(0, 95, 5))
endpoints  <- c("ncd+lri", "copd", "ihd", "lc", "lri", "stroke", "dm2", "allcause")

## ── 网格与地理信息 ──────────────────────────────────────────────────────
res  <- 0.25
lon  <- seq(5, 30 - res, by = res)
lat  <- seq(35, 50 - res, by = res)
cell <- expand.grid(x = round(lon + res / 2, 2), y = round(lat + res / 2, 2))
n    <- nrow(cell)

cell$location <- ifelse(cell$x < 13, countries[1],
                        ifelse(cell$x < 21, countries[2], countries[3]))

grid_info <- data.frame(x = cell$x, y = cell$y, location = cell$location)

## ── 网格化暴露（两个情景） ──────────────────────────────────────────────
exposure_field <- function(shift) {
  v <- 12 + 30 * exp(-((cell$x - 20)^2 + (cell$y - 42)^2) / 150) +
    stats::rnorm(n, 0, 1.2) + shift
  round(pmax(v, 0.5), 2)
}

grid_exposure <- data.frame(
  x = cell$x, y = cell$y,
  base2015     = exposure_field(0),
  scenario2030 = exposure_field(-4)
)

## ── 网格化人口（两个情景） ──────────────────────────────────────────────
density_weight <- c(Aland = 1.0, Borduria = 1.6, Cyrenia = 0.8)[cell$location]
pop_base <- round(exp(stats::rnorm(n, 9.2, 0.6)) * density_weight)

grid_pop <- data.frame(
  x = cell$x, y = cell$y,
  base2015     = pop_base,
  scenario2030 = round(pop_base * stats::runif(n, 0.95, 1.15))
)

## ── 国家级人口（与网格合计一致） ────────────────────────────────────────
national_population <- data.frame(
  location = countries,
  base2015     = vapply(countries, function(k) sum(grid_pop$base2015[cell$location == k]), numeric(1)),
  scenario2030 = vapply(countries, function(k) sum(grid_pop$scenario2030[cell$location == k]), numeric(1))
)

## ── 国家级年龄结构（每个国家各年龄组占比之和为 1） ──────────────────────
age_profile <- function() {
  p <- exp(-seq_along(ages) * 0.07) + 0.02 + stats::runif(length(ages), 0, 0.02)
  p / sum(p)
}

national_age_structure <- do.call(rbind, lapply(countries, function(k) {
  data.frame(location = k, age = ages,
             base2015     = round(age_profile(), 6),
             scenario2030 = round(age_profile(), 6))
}))

## ── 国家级死亡率（每 10 万，随年龄指数上升） ────────────────────────────
ep_factor      <- c(`ncd+lri` = 0.9, copd = 0.08, ihd = 0.26, lc = 0.11,
                    lri = 0.30, stroke = 0.20, dm2 = 0.03, cause = 2.2)
country_factor <- c(Aland = 1.0, Borduria = 0.85, Cyrenia = 1.2)
age_risk       <- function(a) 18 * exp(0.055 * a)

national_mortality <- expand.grid(location = countries, age = ages,
                                  endpoint = endpoints,
                                  stringsAsFactors = FALSE)
national_mortality$base2015 <- round(
  age_risk(as.integer(national_mortality$age)) *
    ep_factor[national_mortality$endpoint] *
    country_factor[national_mortality$location] *
    stats::runif(nrow(national_mortality), 0.9, 1.1), 2)
national_mortality$scenario2030 <- round(
  national_mortality$base2015 * stats::runif(nrow(national_mortality), 0.7, 0.95), 2)

## ── 写盘 ────────────────────────────────────────────────────────────────
files <- list(
  "grid_info.xlsx"              = list(grid = grid_info),
  "grid_exposure.xlsx"          = list(grid = grid_exposure),
  "grid_pop.xlsx"               = list(grid = grid_pop),
  "national_population.xlsx"    = list(national = national_population),
  "national_age_structure.xlsx" = list(national = national_age_structure),
  "national_mortality.xlsx"     = list(national = national_mortality)
)

for (f in names(files)) {
  writexl::write_xlsx(files[[f]], path = file.path(out_dir, f))
  cat(sprintf("%-30s %5d rows\n", f, nrow(files[[f]][[1]])))
}

cat("\n-- invariants --\n")
cat("grid cells            :", n, "| countries:", paste(countries, collapse = ", "), "\n")
cat("exposure range        :", paste(range(c(grid_exposure$base2015, grid_exposure$scenario2030)), collapse = " .. "), "\n")
cat("population total      :", format(sum(grid_pop$base2015), big.mark = ","),
    "(national table:", format(sum(national_population$base2015), big.mark = ","), ")\n")
cat("age proportions sum   :",
    paste(round(vapply(countries, function(k)
      sum(national_age_structure$base2015[national_age_structure$location == k]),
      numeric(1)), 6), collapse = ", "), "\n")
cat("mortality rate range  :", paste(range(national_mortality$base2015), collapse = " .. "), "per 100k\n")
cat("endpoints             :", paste(endpoints, collapse = ", "), "\n")
