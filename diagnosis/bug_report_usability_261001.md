# AttrMort 0.3.0 外部可用性测试发现的缺陷清单（261001）

> 来源：在「202508 食品生产与公平」项目真实数据上的可用性测试（用户要求："基于本项目测试这个 R 包的可用性"）。
> 被测版本：AttrMort 0.3.0（安装于 R 4.6.1 用户库，构建 2026-09-30 15:58；源码 `D:/GitDir/AttrMort`）。
> 外部测试材料：`202508 食品生产与公平/diagnosis/attrmort_usability_261001.md`、`diagnosis/deprecated/verify_attrmort_261001.{R,log}`。
> 测试数据：食品贸易研究 GBD/MRBRT2019 输入（网格 5,622 行/170 地点；浓度宽表；`Pop2017`；年龄结构 204 地点 × 19 档，**缺 90 档**；死亡率 204 地点 × 20 档 × 6 端点）+ 本项目死亡网格（3,634 格 × 57 case）。
> 结论：包整体可用（自带测试 217/0/0/1 跳过；本项目两情景 4 s 跑通），下列 8 项建议检修。**B1、B2 为高优先级。**

## B1（高）分年龄分块遇到"空块"直接中止整次运行

**症状**：`chunk_ages = 1` 时报
```
Error: No rows survived the join between the inputs and the concentration-response table.
Check that `mort_rate` covers the same domains and age groups as `calc_fild`, and that
`age` values match the CRF age strata ...
```
同一份输入不指定 `chunk_ages`（或 `chunk_ages = 2/5`，视年龄档分布）则正常运行。

**根因（已定位）**：`.calc_attributable_ages()` 按年龄块逐块调用 `.calc_attributable()`；`.calc_attributable()` 末尾有
`if (nrow(out) == 0) stop("No rows survived the join ...")`（`R/Mortality.R:971-979`）。
当某个块里的年龄在 `age_struc` 中**完全没有行**时（例如 `mort_rate` 与 CRF 都有的年龄、但年龄结构缺该档），该块必然 0 行，于是整次运行被中止；而未分块时这些年龄只是自然缺席，结果正常。
触发条件：`ages = intersect(mort_rate$age, RR_tbl$age)` 里存在任一"在 age_struc 中无行"的年龄，且该年龄被单独分到一块。

**最小复现（只用包自带合成数据）**：
```r
library(AttrMort); library(readxl); library(dplyr)
ed <- system.file("extdata", package = "AttrMort"); sheet <- function(f) read_excel(file.path(ed, f))
gi <- sheet("grid_info.xlsx"); ce <- sheet("grid_exposure.xlsx"); gp <- sheet("grid_pop.xlsx")
ag <- sheet("national_age_structure.xlsx"); mr <- sheet("national_mortality.xlsx")
ag2 <- ag |> filter(age != "95")          # 模拟真实 GBD 年龄结构缺档
Mortality(CRF="GEMM", calc_fild=gi, conc_real=ce, pop_total=gp, age_struc=ag2, mort_rate=mr,
          scenario="base2015", mort_lvl="location")                     # OK：6000×17
Mortality(CRF="GEMM", calc_fild=gi, conc_real=ce, pop_total=gp, age_struc=ag2, mort_rate=mr,
          scenario="base2015", mort_lvl="location", chunk_ages = 1L)     # ERROR（同上）
Mortality(CRF="GEMM", calc_fild=gi, conc_real=ce, pop_total=gp, age_struc=ag2, mort_rate=mr,
          scenario="base2015", mort_lvl="location", chunk_ages = 2L)     # ERROR（末块只剩 95 档）
```
本项目真实数据同样复现：`chunk_ages = 1` 报错，`2`、`5` 与默认逐列 `max|diff| = 0`。

**期望**：空块应被安全跳过（该年龄不出现在结果里，或在按 key 合并时记为 NA），而不是中止；README 承诺"任意 `chunk_ages` 与不分块数值一致"。

**建议修复**：在 `.calc_attributable_ages()` 里允许空块（`.calc_attributable(..., allow_empty = TRUE)` 返回带 key 列的空表并跳过），或把空块的判断提前到 `ages`/`blocks` 层面；补回归测试：`age_struc` 缺档 × `chunk_ages = 1`，断言与不分块结果等价。

**影响**：内存优化路径（大网格必须按年龄分块）在常见 GBD 年龄结构（缺 90 档）下不可用；用户若显式设置 `chunk_ages = 1` 会得到与数据无关的误导性报错。

## B2（高）非方形栅格被静默平均为方形分辨率并重采样

**症状**：本项目网格为 2.5°经 × 2°纬（表格口径 3,634 格）。栅格路径打印
```
Detected raster resolutions: 2.25000 deg, 2.25000 deg
Target resolution: 2.25000 deg (~12800 cells) - auto-confirmed.
```
随后结果网格变为 **3,707 格**（与表格口径 3,634 不一致）；`build_grid_info()` 对同一表格网格返回属性 `res = 2.25`。

**根因**：`R/raster-io.R:344-345` 用 `mean(terra::res(x))` 把 (resx, resy) 压成一个数：
```r
if (!is.null(conc_rast)) resolutions <- c(resolutions, mean(terra::res(conc_rast)))
if (!is.null(pop_rast))  resolutions <- c(resolutions, mean(terra::res(pop_rast)))
candidate <- min(resolutions)
```
对 (2.5, 2.0) 得到 2.25，再据此 `align_to_target()` 重采样 → 网格被改。

**最小复现**：任取一个 res = (2.5, 2) 的 GeoTIFF（如本项目的 2.5° 浓度/人口子集）调用
`Mortality(CRF="MRBRT2019", conc_real=<tif>, pop_total=<tif>, age_struc=..., mort_rate=..., mort_lvl="location")`，
观察分辨率提示与结果格数。

**期望**：非方形栅格要么保留 (resx, resy) 各自精度，要么显式报警/拒绝（或要求 `target_res` 传长度 2）；不允许静默改变分析网格。

**建议修复**：`target_res` 支持长度 2 或列表；`.resolve_target_res()` 在 `abs(resx-resy) > tol` 时 `warning`/`stop` 并提示传 `target_res = c(resx, resy)`；`build_grid_info()` 的 `res` 属性同步为两个值。

**影响**：所有非方形网格（本项目 S–R/GBD 2.5°×2°、不少排放/健康网格）在栅格路径上的结果网格与表格路径不一致；本项目的 0.1° 方形产品不受影响。

## B3（中）`domain_summary()` 的表格浓度 + `admin=` 组合报错，与 README 示例冲突

**症状**：
```r
domain_summary(conc_real = <表格，含 x/y/conc>, pop_total = <表格，含 x/y/pop>,
               admin = "worldmap_...shp", admin_col = "name_long")
# Error: `admin` labelled no cell of `conc_real`: after rasterizing the boundaries onto the grid
#        the domain column is missing or NA everywhere ...
```
同一对输入 `build_grid_info()` 可用；把 `conc_real` 换成栅格后 `domain_summary()` 可用（158×5）。

**冲突点**：README「National-only workflow」示例正是表格浓度 + `admin = "boundaries.shp"`（`conc_real = sheet("grid_exposure.xlsx")`）。

**根因**：`R/domain-summary.R:149-210` 需要"栅格模板"来栅格化边界；仅坐标表格时无法给出与表格坐标一致的模板（而 `Mortality()` 表格路径能直接从坐标推断网格）。

**建议**：要么让表格路径用自身坐标 + 推断分辨率建模板（与 `Mortality()` 表格路径行为一致），要么把 README 示例改为栅格浓度，或在报错中给出可直接照做的修法。

## B4（中）人口列名带年份后缀（`Pop2017`）不被识别

**症状**：`scenario = NULL` 时
```
Error: Invalid input data:
  - `pop_total` is missing required column(s): `pop`.
```
把 `Pop2017` 改名为 `pop` 即恢复正常。

**根因**：`R/schema-detect.R:263` 白名单只有 `c("pop", "Pop", "population")`，不含 `Pop2017` 这类年份后缀写法（本项目与多个外部数据源都用这种列名）。

**建议**：改为大小写不敏感的正则（如 `^pop([0-9]{4})?$` / `^population`），命中时 `message()` 说明把哪一列当作 `pop`；或在报错信息里列出候选列名与改名示例。

## B5（中）`scenario=` 要求所有输入都带同名列，单列辅助表必须复制列

**症状**：一个宽表浓度 + 单列人口/年龄/死亡（最常见组合）时
```
Error: Scenario column "baseline" not found in the data. Available columns: x, y, Pop2017.
```
用户只能复制情景列（外生项目 `health/R/step8_run_m6.R` 的 `dup_scen()` 就是这么绕的），或改用单列 `conc` + `scenario = NULL`。

**建议**：对"没有该情景列、但除键列外只有唯一数值列"的辅助输入，按情景无关处理并提示（与 `getPop()/getAge()/getMort()` 的语义一致）；至少在报错里给出两种修法（复制列 / 改单列 + `scenario = NULL`）的示例代码。

## B6（低）内部 join 的 dplyr 提示刷屏，`validate = "off"` 不能静默

**症状**：一次真实数据运行打印 **154 行** `Joining with \`by = join_by(x, y)\``；`validate = "off"` 无效。

**根因**：内部使用自然 join（`R/Mortality.R:920/930/938/950/957/961` 的 `reduce(left_join)`、`left_join(PWRR)` 等），dplyr 推断键时逐次提示。

**建议**：内部 join 显式传 `by=`（也避免键推断歧义），或在内部统一 `suppressMessages()`；如需保留诊断信息，可加 `quiet =`/`verbose =` 选项。

## B7（低，一致性）`domain_summary()` 输出域列名不统一

`domain_summary()` 保留边界列原名（如 `name_long`），而 `Mortality()` 会把 `admin` 重命名为 `location`；README 示例也要用户手工 `data.frame(location = ds$iso3, ...)`。建议统一为 `location`（或加 `domain_col =` 参数），否则"domain_summary → Mortality"串联时需要额外改名。

## B8（低，文档）README 对栅格路径 `mort_lvl = NULL` 的说明与实际不符

README 写"`mort_lvl = NULL` still means 'no domains at all'"，但当 `mort_rate`/`age_struc` 是域级表、又没有 `admin`/域列时，实际报错（报错信息本身清楚、可操作）：
```
`age_struc` shares no join key with `calc_fild` (keys available: `x`, `y`; `age_struc` has: `location`, `age`, `prop`).
```
建议在 README 该句后补前提（域级输入仍需 `admin` 或 `calc_fild` 带域列）。

## 附：测试中表现良好、建议保留的部分

- 自带测试套件 217 项 / 0 失败 / 0 警告 / 1 跳过（fingerprint 需环境变量）。
- 数据体检信息清楚：未使用端点（`ncd`）、CRF 用到但缺失的端点（`dm2`）、年龄结构缺档（`90`）、死亡率异常值（>5 万/10 万）、地名匹配数（140/204）、grain 与 PWRR 分支说明。
- PWRR 按 (域, 年龄, 端点) 归一的口径与 `AGENTS.md` 数据契约一致；用手写公式复算与新包结果比值 1.0000（可作为交叉校验锚点）。
- `aggregate + uncertain`（168×5，含 `total/conc_pwe/CI_LOW/CI_UP`）、`conc_uncert`、`chunk_ages = 2/5` 的等价性、栅格 + `rnaturalearth` 自动边界、非法 CRF 的报错均正常。

## 附：建议的验收用例（回归测试）

1. `age_struc` 缺档（如 95 或 90）× `chunk_ages = 1`：与 `chunk_ages = NULL` 结果等价（B1）。
2. res = (2.5, 2) 栅格：`target_res` 未给时应报警或保留非方形；`build_grid_info()` 的 res 属性正确（B2）。
3. 表格浓度 + `admin=` 的 `domain_summary()`：可跑或 README 改口（B3）。
4. `pop_total` 列名 `Pop2017` / `Pop` / `population` 均可识别（B4）。
5. 宽表浓度 + 单列辅助输入：可跑或给出可操作的报错（B5）。
6. `validate = "off"` 下无 `Joining with ...` 输出（B6）。
