# AttrMort 代码审核（yifan-r-code-style v2.4.0）

- 日期：261001
- 审核依据：`~/.agents/skills/yifan-r-code-style/SKILL.md` v2.4.0（新增 §10 R 包开发、§11 Advanced R、§12 反模式黑名单、§13 交付自查）
- 审核对象：工作区当前状态（HEAD = `319269f`，另有 40 个文件未提交改动）
- 审核范围：`R/`（15 个文件、5466 行）、`DESCRIPTION`、`NAMESPACE`、`man/`、`tests/`、`vignettes/`、`data-raw/`、`.Rbuildignore`、git 卫生
- 方法：静态正则扫描 + `lintr` 3.4.0 逐文件检查 + 在临时副本上重跑 `roxygen2::roxygenise()` 对比产物 + `R CMD check` + 端到端复现（R 4.6.1）

## 一、总体结论

**验收状态达标**：`R CMD check`（完整流程，含 vignette 构建）为 `Status: OK`，0 error / 0 warning / 0 note；`devtools::test()` 全绿；`NAMESPACE` 与 `man/` 全部可由 roxygen2 8.1.0 复现（无手改痕迹）；`R/` 中无 `library()`、`source()`、`setwd()`、顶层副作用。

**与 skill 的差距集中在三处**，与代码质量本身无关：

1. 新 §10.4 要求的信号机制（`cli::cli_abort()` / `rlang::abort()`）与依赖引入方式（禁止 `@import pkg`）**完全未落地**——全文 0 次 `cli::`，`NAMESPACE` 有 4 条整包 `import()`。
2. 新 §11.2 / §11.7 的结构要求（函数短小、数据驱动而非代码分支）触及若干超长函数，其中 `Decomposition()` 的 210 行是 16 份手写调用块。
3. §12 黑名单仍有残留：`ifelse()` ×1、`apply()` ×2、`tapply()` ×1、`paste0()` 共 77 处、`str_c()` 0 处。

**另发现 2 个与风格无关、但已端到端复现的真缺陷**（P0），建议优先修。

格式层（§2/§3/§4）质量很高：全项目无 `=` 赋值、无 `%>%`、无 `1:length()`、无行尾大段注释、无 tab（仅 2 处注释内 tab）、无超过 100 字符的行、管道一行一个、注释全部写在代码上方、`drop = FALSE` 与 `[[` 该用的地方都用了。

## 二、P0：已复现的缺陷（先修）

### P0-1 `Mortality(aggregate = TRUE, mort_lvl = NULL, uncertain = TRUE)` 必报错

- 位置：`R/uncertainty.R:57-58`（`.range_sum()`）与 `R/uncertainty.R:70-77`（`.attach_range()`）
- 现象：`at = character(0)`（整域汇总）时 `.range_sum()` 返回**裸数值** `sum(totals)`，而 `.attach_range()` 立刻把它管道进 `rename(CI_LOW = .total)`：

```
ERROR: no applicable method for 'rename' applied to an object of class "c('double', 'numeric')"
```

- 可达性：`Mortality()` 在 `aggregate = TRUE` 且 `mort_lvl = NULL` 时以 `at = character(0)` 调 `.attach_range()`（`R/Mortality.R:636`、`664-665`）；同一调用在 `uncertain = FALSE` 时正常返回（已实测）。
- 复现：

```r
pkgload::load_all("."); source("tests/testthat/helper-data.R"); d <- .attr_small_long()
Mortality(CRF = "GEMM", calc_fild = d$calc_fild, conc_real = d$conc_real,
          pop_total = d$pop_total, age_struc = d$age_struc, mort_rate = d$mort_rate,
          mort_lvl = NULL, aggregate = TRUE, uncertain = TRUE, validate = "off")
```

- 建议：`R/uncertainty.R:58` 改为 `return(tibble(.total = sum(totals, na.rm = TRUE)))`，让 `.attach_range()` 的空键分支（74-77 行）真正可达。
- 测试缺口：`tests/testthat/test-uncertainty.R` 只覆盖了 `aggregate + mort_lvl = "location" + uncertain`，未覆盖 `mort_lvl = NULL` 的交叉组合；请补一条回归用例。

### P0-2 `build_cr_table()` 的默认参数必报错

- 位置：`R/build-cr.R:232`（`model = c("IER", "GEMM")`）与 `R/build-cr.R:176`（`.cr_model_form()` 要求 `length(model) == 1`）
- 现象：文档化的默认调用直接失败：

```r
ier <- data.frame(cause = "IHD", age = "25", alpha = 5, beta = 0.01, gamma = 0.5, tmrel = 3)
build_cr_table(ier)
# ERROR: `model` must be a single character string.
build_cr_table(ier, model = "IER")   # OK
```

- 根因：默认值是长度 2 的向量，而 `.cr_model_form()` 只接受长度 1；仓库内所有调用（`tests/testthat/test-build-cr.R:8`、`vignettes/AttrMort.Rmd:193`）都显式传了 `model=`，因此掩盖了问题。
- 建议：默认值改为 `model = "IER"`（不要用 `match.arg()`：`model` 还接受 `"IER2017"` 一类变体，`match.arg()` 会把它们判为非法），并在 `@param model` 写明默认值；补一条不传 `model` 的测试。

## 三、P1：与 skill 新章节的规范冲突

### 3.1 §10.3 依赖引入方式（整包 `@import`）

`R/AttrMort-package.R:29-32` 用 `@import dplyr` / `tidyr` / `purrr` / `stringr`，`NAMESPACE` 生成 `import(dplyr)` 等 4 条整包导入；skill 明确要求「不要 `@import pkg`（会把整包命名空间拉进来）」，并提倡 `pkg::fun()`。这也是 `R CMD check` 的 `Imports never ::-used` 现象（dplyr/purrr/stringr/tidyr/tools）的来源。

- 规模：`R/` 中未加前缀的 dplyr/purrr 动词调用约 127 处（`mutate` 15、`map` 13、`left_join` 13、`reduce` 11、`summarise` 10、`select` 10 …）。
- 建议（二选一，建议前者）：改成 `@importFrom`（保留裸动词，改动小、符合 skill 的 `@importFrom` 许可）；或全部 `dplyr::` 前缀化（严格但改动大）。无论哪种，都要按项目 AGENTS.md 二.5「依赖成对声明」同步 `DESCRIPTION`。
- 顺带清理死导入：`@importFrom rlang := .data` 中的 `.data` 从未使用（全文无 `.data$` / `.data[[`）；`@importFrom readxl read_excel excel_sheets` 中的 `excel_sheets` 从未使用。

### 3.2 §10.4 / §11.3 错误与消息机制

`R/` 中 `stop()` 117 处、`warning()` 15 处、`message()` 22 处，`cli::` / `rlang::abort` 0 处。skill 要求改用 `cli::cli_abort()` / `cli::cli_inform()`（或 `rlang::abort()`），且消息里带出错对象与可行做法。

- 另有 28 处 `stop()` / `warning()` 缺 `call. = FALSE`，其中 `R/aggregate.R` 约 20 处（115、129、137、154、189、200、219、376、391、488 …），`R/raster-io.R` 8 处（278、289、297、303、461、466、473、480，例如 `stop("Invalid resolution.")` 既无调用上下文也无可操作建议），其余文件基本一致地带了 `call. = FALSE`。
- 建议：引入 `cli` 到 `Imports`（无全局状态，符合项目硬约束 7），逐文件替换；`cli` 的 `{.field}` / `{.path}` / `{.val}` 语法可同时消掉 9 处手工反引号拼接（见 3.6）。若暂不引入 `cli`，至少把 `aggregate.R`、`raster-io.R` 的 `call. = FALSE` 补齐。
- 其它信号问题：`R/Mortality.R:693-703` 对 `mort_lvl = NULL`（文档化的正常模式）用词像故障（`"The `mort_lvl` is set NULL, calculation will ignore calibration of mort_rate."`），且不确定性链下会重复 3 次；`R/schema-detect.R:168-171` 的 `tryCatch(..., error = function(e) NULL)` 静默吞掉配置错误，违反「不要掩盖问题」（§11.3）。

### 3.3 §11.2 / §11.7 函数过长与「数据驱动而非代码分支」

实测（`parse()` + `srcref`，全包 107 个函数，中位数 17 行）：

| 函数 | 位置 | 行数 | 判断 |
|---|---|---|---|
| `Mortality()` | `R/Mortality.R:375-677` | 303 | 拆分：`.resolve_national_admin()`（505-538）、`.run_uncertainty_chains()`（608-636，并把 `lower_frames <- c(lower_frames, ...)` 改为 `map2()` + `list_rbind()`）、`.aggregate_output()`（630-668） |
| `Decomposition()` | `R/DrivingFactors.R:80-348` | 269 | 重写（见下） |
| `validate_mortality_input()` | `R/schema-detect.R:107-281` | 175 | 拆成 age / exposure / population / mortality 四个校验器 |
| `domain_summary()` | `R/domain-summary.R:135-286` | 152 | 标签解析段（149-233，含 4 处 `stop()` 与三个互斥分支）抽成 `.resolve_domain_labels()` |
| `.calc_attributable()` | `R/Mortality.R:876-1020` | 145 | `pivot_wider(names_from = c("endpoint","age"), ...)` 写了 3 次、`reduce(.left_join_common)` 5 次、`/ 1e5` 4 次；抽 `.widen_mort()`、`.pwrr_table()`，并定义 `.PER_100K <- 1e5` |
| `.resolve_target_res()` | `R/raster-io.R:346-482` | 137 | 纯决策与交互 UI 混在一起（`cat()` 423、`readline()` 446/476，阈值 5e6/5e7/1e9/0.1/0.05/0.01 硬编码）；拆 `.select_target_res()` + `.prompt_resolution()`，阈值提为具名常量 |
| `.aggregate_mortality_one()` | `R/aggregate.R:186-290` | 105 | 边界；三个 margin 分支（245-278）合成 `.pivot_margin()` |

`Decomposition()` 是最典型的一处：`R/DrivingFactors.R:86-295` 的 210 行是 16 份手写 `Mortality()` 调用，包在四层 `if (all(serie_step[1:2] %in% c("PG","PA"))) ... else if (...)` 里，每次只有 5 份会执行；且 271-274 行的参数顺序已与其它 15 份漂移（`calc_fild, conc_real, conc_cf` vs `calc_fild, conc_cf, …, conc_real`）。按 §11.7「情景与参数组合写成表」重构，210 行可降到约 10 行：

```r
sc  <- function(driver, step) if (driver %in% serie_step[seq_len(step)]) to else from
run <- function(step) {
  Mortality(calc_fild = G, conc_cf = getConc(D, sc("EXP", step)),
            pop_total = getPop(P, sc("PG", step)),
            age_struc = getAge(A, sc("PA", step), loc = L),
            conc_real = getConc(D, sc("ORF", step)),
            mort_rate = getMort(M, sc("ORF", step), loc = L),
            mort_lvl = L, CRF = crf, CI = ci)
}
runs <- map(0:4, run)   # 再按 .DRIVER_ORDER 组装 Start/各步增量/End
```

附带收益：`mort_0` … `mort_4` 这类 NSE 列名会消失，`R/AttrMort-package.R:42-47` 的 `globalVariables()` 可以同步瘦身。

### 3.4 §2 / §10.4 命名

- 导出 API 混用驼峰与 snake_case（`getConc` / `getPop` / `getAge` / `getMort`，见 `R/utils.R:230,256,292,343`），skill 只豁免 S3 方法的 `generic.class`。**这是破坏性变更，需要你拍板**：项目 `AGENTS.md` 三把 `getConc()` 等写成了对外契约，若改名须新增 `get_conc()` 等并走 `lifecycle::deprecate_warn()` 过渡，同时进 `NEWS.md`。
- `Decomposition()` 的形参是公式代号 `G/D/P/A/M/L/D_cf`（`R/DrivingFactors.R:80`），与 §2「严禁单双字母乱用」直接冲突；建议改用与 `Mortality()` 一致的名字（`calc_fild` / `conc_real` / `conc_cf` / `pop_total` / `age_struc` / `mort_rate` / `mort_lvl`），同样属于破坏性变更。
- 布尔局部变量缺 `is_` / `has_` 前缀：`conc_is_rast`、`pop_is_rast`、`cf_is_rast`（`R/ingest.R:186-194`）、`own_skeleton`、`national_admin`（`R/Mortality.R:436,505`）。
- 建议：新 API 一律动词 + snake_case；旧名保留并在文档中记录豁免，或按上述弃用路径迁移。

### 3.5 §12 黑名单残留

| 位置 | 现状 | 建议 |
|---|---|---|
| `R/grid-info.R:63` | `half <- ifelse(is.na(res), 0, res / 2)`（全包唯一 1 处） | `if_else(is.na(res), 0, res / 2)` 或 `half <- res / 2; half[is.na(half)] <- 0` |
| `R/build-cr.R:138,140` | `apply(curves, 2, stats::quantile, ...)` ×2 | 一次 `vapply(seq_len(ncol(curves)), function(j) stats::quantile(curves[, j], probs = probs, names = FALSE), numeric(length(probs)))`，再 `qs[1, ]` / `qs[2, ]` |
| `R/schema-detect.R:216` | `tapply(...)` 分组求和 | `summarise(prop_sum = sum(...), .by = all_of(loc_col))` |
| 8 个文件共 **77 处** `paste0()`，`str_c()` 0 处（`cr-config.R` 31、`aggregate.R` 17、`Mortality.R` 16、`utils.R` 4、`RR_std.R` 3、`raster-io.R` 3、`ingest.R` 2、`schema-detect.R` 1） | §4.3 / §12 要求 `str_c()` / `str_glue()` | 机械替换；**注意语义差异**：`str_c(NA, "x")` 返回 `NA`，`paste0(NA, "x")` 返回 `"NAx"`，报错消息里若可能含 `NA` 需单独处理 |
| `R/DrivingFactors.R:257,270` | 注释内 2 处字面 tab | 用空格重排（§4 缩进禁 tab） |
| `R/utils.R:231,257,293,344` | 同一段 `if (!is.data.frame(.data)) stop(...)` 粘贴 4 次；age/cause 列选择块再各重复 2 次 | 抽 `.check_wide_input()` / `.pick_age_col()` / `.pick_cause_col()`（§8 出现 ≥2 次即抽函数） |

### 3.6 重复代码（≥2 次，§8）

- 反引号列名拼接惯用法 9 处（`aggregate.R` 139/141/511/585/622/624/632、`domain-summary.R:226`、`grid-info.R:198`）→ 一个 `fmt_cols()` 或 `cli` 的 `{.field}`。
- CI 词表 4 份拷贝（`aggregate.R:67,68,76,79,557`）→ 由 `.ci_aliases` 派生正则与列名。
- 坐标列正则 2 份（`aggregate.R:29-31` 与 `121-125`）→ `setdiff(names(x), .is_coord_cols(x))`。
- 域名改名块 3 份（`domain-summary.R:243,245,248`）→ `map(rename_dom)`。
- `rnaturalearth` 守卫 3 份（`ingest.R:341-347`、`raster-io.R:277-282`、`Mortality.R:508-514`）→ 一个 `.ne_countries_or_abort()`。
- `stop("Column ... already exists")` 2 份（`aggregate.R:200-203, 219-222`）；`.write_grid_info()` 与 `.write_domain_summary()` 是无附加价值的 3 行同体包装。

### 3.7 §4.1 / §4.2 / §4.4 数据操作细节

- `R/aggregate.R:604-628`：`.join_calc_fild()` 用列名交集猜 join 键且不校验唯一性；建议 `left_join(..., by = shared, relationship = "many-to-one")`（dplyr ≥ 1.1 会在违反时报错）或 join 前 `count(pick(all_of(shared))) |> filter(n > 1L)` 断言（§4.1「join 前检查键唯一性」）。
- `R/aggregate.R:547-553`：三个 CI 分支用 `str_remove(names(...), "_MEAN$")` 反推键再 `full_join`，字面量 `"_MEAN$"` 是分支标签的第三份拷贝；建议直接用已知的值列名求键，并加 `relationship = "one-to-one"`。
- `R/aggregate.R:710`：`str_sub(names(results), 1L, 31L)` 截断 sheet 名无碰撞检查（实测重名时 writexl 会把第二张改名为 `<name>_1`，与调用方传入的元素名不一致）→ 截断后 `anyDuplicated()` 报错。
- `R/utils.R:322-326`：`mutate(prop = prop.table(prop))` 对缺失值不显式（一个 `NA` 会让整域比例变 `NA`）→ 改为 `prop / sum(prop, na.rm = TRUE)` 并写明缺失策略（§4.2）。
- `R/ingest.R:54,57` 与 `R/RR_std.R:168`、`R/build-cr.R:33`：`read_csv(..., show_col_types = FALSE)` 且无 `col_types=`、无 `problems()` 检查（§4.4）；`conc` 是精度敏感的 join 键，建议显式声明类型并检查 `problems()`。
- `R/domain-summary.R:269-276` 用 `group_by(pick(...)) + summarise(.groups=)`，与 `aggregate.R` 的 `summarise(.by = )` 不统一（§4.1 偏好后者）。

### 3.8 `suppressWarnings()` 审计（§11.3）

全包 12 处：`utils.R:126`、`RR_std.R:76`、`build-cr.R:99`、`cr-config.R:67`、`Mortality.R:712,909`、`ingest.R:383,384`、`raster-io.R:469`、`schema-detect.R:152,235,270`。
其中前四类都有「紧接的 NA 检查 / 报错」或注释说明，属于合法的强制转换守卫，保留即可（建议统一包一个 `as_numeric_quiet()` 并写明理由）。**`schema-detect.R:152/235/270` 三处需要改**：解析失败的值变成 `NA` 后被 `sum(..., na.rm = TRUE)` 或 `!is.na()` 静默忽略，字符列如 `"1,234"` 不会触发任何提示，问题会拖到很后面的 join 才暴露；因子列更糟（`as.numeric(factor)` 返回水平码且不告警）。建议改为 `as.numeric(as.character(x))` 并在 `is.na(结果) & !is.na(原值)` 时报错。

## 四、P2：工程卫生与文档

1. **40 个文件未提交**（`+1438 / -582`），其中包含 `man/write_mortality_xlsx.Rd`、`vignettes/AttrMort.html`、`vignettes/.gitignore` 等未跟踪文件。skill §11.7 要求小步提交、用 `git diff` 自查——当前工作区无法用 diff 划出「这次改了什么」。
2. **换行符不一致**：17 个文件是 CRLF、其余 LF，而 `core.autocrlf=true`，`git diff` 已开始刷 `LF will be replaced by CRLF` 告警。建议在 `.gitattributes` 加 `* text=auto eol=lf`（`*.rda`、`*.tif` 等二进制另设 `-text`）。
3. **无 CI**：没有 `.github/`（`.Rbuildignore` 里已有 `^\.github$` 却无该目录），也没有 `codecov.yml`。§10.7 建议 `usethis::use_github_action("check-standard")` 与 `"test-coverage"`。
4. **README 无源文件**：只有手写的 `README.md`，没有 `README.Rmd`（`.Rbuildignore` 里 `^README\.Rmd$` 已是空指向）。§10.6 要求 README 由 `README.Rmd` 渲染（`devtools::build_readme()`）。
5. **DESCRIPTION 未声明最低版本**：代码用了 `pick()`、`.by =`（dplyr ≥ 1.1.0）与 `list_rbind()`（purrr ≥ 1.0.0），但 `Imports` 只写包名。建议 `dplyr (>= 1.1.0)`、`purrr (>= 1.0.0)`。
6. **AGENTS.md 的验收命令拿不到 `Status: OK`**：文档里的两步走带 `--no-build-vignettes`，我实测得到 2 个 vignette WARNING（`no files in 'inst/doc'`、`Directory 'inst/doc' does not exist`）；去掉该参数（保留 `--no-manual`）后为 `Status: OK`。建议更新 `AGENTS.md` 五中的命令，或说明该参数只用于快速检查。
7. **`.Rbuildignore` 残留** `^README\.Rmd$`（文件不存在）；`vignettes/AttrMort.html` 未忽略（`vignettes/.gitignore` 只忽略了 `/.quarto/`），若 `git add .` 会把构建产物入库；`tests/testthat/_snaps` 是空目录（`R CMD build` 会打印 `Removed empty directory`）。
8. **`R/data.R` 尾部**：`## quiets concerns of R CMD check` + `if (getRversion() >= "3.1.0") utils::globalVariables(".")` 属 R/ 顶层副作用代码（§10.3），版本判断已无意义（`Depends: R (>= 4.1)`），且与 `R/AttrMort-package.R:42-47` 的声明重复；直接删掉这一段即可。
9. **数据集文档缺来源**：`R/data.R` 九个数据集都只有 `@format` + 一行小写标题，没有 `@source`（§10.6 明确要求结构与来源，且 `data-raw/README.md` 里应已有出处信息可引）。
10. **S3 方法无文档**：`R/cr-config.R:344` 的 `print.attr_cr_config` 只有 `#' @export`，没有标题 / `@param` / `@return` / `@examples`，也不生成 `man/` 页（§10.3）。建议改 `@exportS3Method base::print` 并补全块。
11. **`@noRd` 函数上挂着 `@examples \dontrun{}`**（`raster-io.R:27-31,173-181,264-268`；`Mortality.R:283-286,349-350`）：不生成 `.Rd`，例子永不运行，反而是死代码。
12. **文档与行为不符**（§10.4 文档契约）：
    - `align_to_target()` 的 `conc_names`（`raster-io.R:161-163`）有参数、有 `@details`，但函数体内从未读取（只按 `pop_names` 分支），传了也没有任何效果 → 要么落实，要么删除参数与文档。
    - `@param shp_path ... world country boundaries are downloaded automatically`（`raster-io.R:249-250`）不实：数据由 `rnaturalearth` 随包提供，不下载。
    - `@param target_res` 未写非交互会话下 > 5e7 格会**静默回退到 0.1°**（`raster-io.R:405`），脚本用户看不到网格变化。
    - `R/ingest.R:373-380` 与 `306` 硬编码 `intersect(c("x","y"), names(calc_fild))`，与 `calc_fild` 文档中的「(x/y, lon/lat)」契约不符：`lon`/`lat` 骨架会报「requires gridded calc_fild (columns x and y)」。建议改用已有的 `.grid_xy()`。
13. **循环内 `c()` 增长**（§11.6，规模小但属于黑名单写法）：`.permutations()`（`DrivingFactors.R:9-13`）、`cr_models()`（`cr-config.R:337-340`）、`.cr_endpoints()`（`cr-config.R:160`）、`.cr_normalise()`（`cr-config.R:223`）、`.check_inputs()`（`Mortality.R:38,44`）、`Mortality()` 的 `lower_frames`（`Mortality.R:608-636`）→ 用 `map()` + `unlist()` / `list_rbind()` 替代。
14. **魔数与常量**：`Decomposition()` 里 `serie > 24` 硬编码（应 `length(.permutations(.DRIVER_ORDER))`）；`serie = 2.5` 会被 `[[` 静默截断成第 2 种（报错文案却写 "single integer"），建议 `rlang::is_scalar_integerish()`。
15. **`matchable()` / `RR_std()` / `build_cr_table()` 的 `dgt` 未校验**（入口校验缺失，§11.3）。

## 五、建议的下一步（按批次推进）

**批次 1（P0，1 个提交，含回归测试）**
1. `R/uncertainty.R:58` 返回 `tibble(.total = ...)`；在 `test-uncertainty.R` 补 `mort_lvl = NULL + aggregate + uncertain` 用例。
2. `R/build-cr.R:232` 默认 `model = "IER"`；补一条不传 `model` 的测试。

**批次 2（文档与信号机制，机械改动，适合一次完成）**
3. 引入 `cli`，替换 `stop()`/`warning()`/`message()`；先补 `aggregate.R` 与 `raster-io.R` 的 `call. = FALSE`。
4. 清理死导入（`rlang::.data`、`readxl::excel_sheets`）；`@import` 改 `@importFrom`。
5. 补 `R/data.R` 的 `@source`；补 `print.attr_cr_config` 文档；删 `R/data.R` 尾部 `globalVariables` 块；把 `@noRd` 上的 `@examples \dontrun{}` 移进测试。
6. 对齐 `conc_names`、`rnaturalearth` 措辞、`target_res` 非交互回退、`ingest.R` 的 x/y 硬编码这四处文档与行为。
7. 更新 `AGENTS.md` 五的验收命令（去掉 `--no-build-vignettes`）。

**批次 3（结构重构，逐个提交、跑指纹回归）**
8. `Decomposition()` 数据驱动化（210 行 → 约 10 行），同步瘦身 `globalVariables()`。
9. 拆 `Mortality()`（303 行）为薄编排 + `.resolve_national_admin()` / `.run_uncertainty_chains()` / `.aggregate_output()`。
10. 拆 `.calc_attributable()`（145 行）、`.resolve_target_res()`（137 行）、`domain_summary()`（152 行）、`validate_mortality_input()`（175 行）。

**批次 4（风格统一，可脚本化 + 人工复核）**
11. `paste0()` → `str_c()`（77 处，注意 `NA` 语义差异）；`ifelse()` → `if_else()`；`apply()`/`tapply()` → purrr/dplyr。
12. 抽公共小函数（`fmt_cols()`、`.check_wide_input()`、`.ne_countries_or_abort()`、CI 常量单一来源、`.join_calc_fild()` 加 `relationship =` 断言）。
13. `R/utils.R` 的 `prop.table()` 缺失值策略、`aggregate.R` 的 sheet 名截断碰撞检查。

**批次 5（工程）**
14. 先把现有 40 个文件的改动按主题拆成若干提交（现在是「一个大 diff」状态）。
15. `.gitattributes` 固定 `eol=lf`；清理 `.Rbuildignore` / `vignettes/.gitignore` / 空 `_snaps`；补 `README.Rmd`；加 CI（check-standard + test-coverage）；DESCRIPTION 补最低版本。

**需要你拍板的决策项**
- A. 导出 API 是否从驼峰迁到 snake_case（`getConc` → `get_conc` 等，破坏性，需 `lifecycle` 过渡 + `NEWS.md`）；若不改，建议在项目 `AGENTS.md` 显式记录「对外 API 命名豁免 §2」。
- B. `Decomposition()` 的 `G/D/P/A/M/L` 是否改成语义名（同样是破坏性变更）。
- C. 是否把 `cli` 加入 `Imports`（我建议加：无全局状态、消息质量提升明显）。

## 六、已核实无问题（避免重复返工）

- `R CMD check`（完整）：`Status: OK`；`devtools::test()` 全绿；例子全部可运行。
- `roxygen2::roxygenise()` 在临时副本上重跑，`NAMESPACE` / `man/` / `DESCRIPTION`（含 `Config/roxygen2/version: 8.1.0`）三者与仓库**逐字节一致**，说明文档产物无手改、roxygen2 8.x 不写 `RoxygenNote` 属正常。
- 全项目无 `library()` / `require()` / `source()` / `setwd()` / `<<-` / `print()` 进度输出 / 顶层副作用；无 `%>%`、无 `=` 赋值、无 `1:length()`、无 `read.csv()` / `write.csv()` / `gsub()` / `substr()`；无超过 100 字符的行（按字符计，中文注释同样是 100 字符以内）；管道一行一个；`drop = FALSE`（`RR_std.R:267`、`aggregate.R:195`、`domain-summary.R:177`、`ingest.R:403,405`）与 `[[` 该用的地方都用了。
- `getPop` / `getMort` 的 `@inheritParams` 是有效文档（`man/getPop.Rd` / `man/getMort.Rd` 已含全部形参），不需要补 `@param`。
- `build-cr.R:125` 的 `vapply()`、`utils.R:132` 的 `vapply()` 是 skill 认可的 `sapply()` 替代，不算黑名单。
- 内部函数用普通 `#` 注释、不生成 `man/` 页，`tools::undoc()` 为空——可接受（R/AGENTS.md 五建议显式 `@noRd`，非必需）。
- `utils.R:126`、`RR_std.R:76`、`build-cr.R:99`、`cr-config.R:67` 的 `suppressWarnings()` 是带检查的合法守卫。
- `R/utils.R`、`build-cr.R`、`cr-config.R`、`uncertainty.R`、`schema-detect.R` 的文件名与主函数不同名，但 R/AGENTS.md 一已如此规定，属项目约定优先。
- 指纹回归装置（`ATTRMORT_FINGERPRINTS=1` + `tests/testthat/fixtures/fingerprints/` 13 份参照）是很好的做法，重构批次请务必沿用。

## 附：本次审核用到的命令

```bash
# 完整验收（去掉 --no-build-vignettes 才能得到 Status: OK）
R CMD build D:/GitDir/AttrMort && R CMD check AttrMort_0.3.0.tar.gz --no-manual

# 静态检查
Rscript -e 'lintr::lint("R/<file>.R", linters = lintr::linters_with_defaults(line_length_linter = lintr::line_length_linter(100L)))'

# 文档产物复现（在副本上跑，勿动仓库）
roxygen2::roxygenise(".", roclets = c("rd", "namespace"))
```

---

# 附：批次 1–2 执行记录（261001 当天完成）

## 一、批次 1（P0）

| 项 | 改动 | 回归测试 |
|---|---|---|
| P0-1 整域 + 不确定性报错 | `R/uncertainty.R` `.range_sum()` 空键时返回 `tibble(.total = ...)`，不再返回裸数值 | `test-uncertainty.R` 新增「reports a whole-field range when aggregate = TRUE and mort_lvl is NULL」 |
| P0-2 `build_cr_table()` 默认参数报错 | `R/build-cr.R` 默认值 `c("IER","GEMM")` → `"IER"`，并写明文档 | `test-build-cr.R` 新增「defaults to the IER form when `model` is omitted」 |

## 二、批次 2（文档与信号机制）

- **信号机制**：全包 156 处 `stop()/warning()/message()` → 本地 `.abort()`（=`cli::cli_abort(message, call = NULL)`）/ `cli::cli_warn()` / `cli::cli_inform()`。用 `.abort()` 而非直接 `cli::cli_abort()`，是为了保住原 `call. = FALSE` 的语义：报错不附内部辅助函数的调用帧（`Error in .check_input_files(...)`）。`R/AttrMort-package.R` 里有一段注释说明该取舍。
- **依赖引入**：`@import dplyr/tidyr/purrr/stringr` → 具名 `@importFrom`（`dplyr::n`、`src` 列补进 `globalVariables()`）；删除死导入 `rlang::.data`、`readxl::excel_sheets`；`DESCRIPTION` 增加 `cli`、`dplyr (>= 1.1.0)`、`purrr (>= 1.0.0)`。
- **文档**：九张内置查表补 `@source` 与描述（GEMM = Burnett et al. 2014, EHP 122(4):397-403；O3 = Carey et al. 2013, PMID 23590261，均已核实；其余按 GBD 轮次写明）；补 `print.attr_cr_config` 的 roxygen；7 处 `\dontrun{}` 补上不运行的理由；`@noRd` 函数上永不执行的 `@examples` 删除（覆盖已在测试中）。
- **文档与行为对齐**：删掉从不生效的 `conc_names` 参数；`rnaturalearth` 措辞改为「随包提供、不下载」；`@param target_res` 写明非交互会话 > 5e7 格会回退 0.1 度。
- **行为对齐**：`admin =` 现在接受 `lon`/`lat`（或 `longitude`/`latitude`）骨架（`R/ingest.R` 改用 `.grid_xy()` 并把 x/y 映射到该表的坐标列名），新增测试「accepts a lon/lat coordinate pair instead of x/y」。
- **提示措辞**：`mort_lvl = NULL`（文档化的未校准模式）由 warning 改为消息，措辞改准确，且每次运行只报一次（此前不确定性链会重复三次）。
- **仓库约定**：`AGENTS.md` 五的验收命令去掉 `--no-build-vignettes`（保留该参数永远拿不到 `Status: OK`），并补了原因说明。
- **`NEWS.md`**：以上用户可见改动全部记入 0.3.0 的 Repairs / Internal 两节。

## 三、验证证据（全部在改动后的工作区实测）

- 测试：`247 用例 / 747 断言，0 失败、0 错误、1 跳过`（跳过的是需要环境变量的指纹测试）。
- 指纹回归：`ATTRMORT_FINGERPRINTS=1` → 42 断言全过，**数值路径未变**。
- 包检查：`R CMD build` + `R CMD check --no-manual`（含 vignette 构建）→ `Status: OK`（0 error / 0 warning / 0 note）。
- 消息文本回归：以改造前快照为基准，逐条渲染比对了全部信号的文本。除以下两类外逐字一致：
  1. 有意的措辞变更（`mort_lvl` 提示、lon/lat 报错、新增两条报错）；
  2. cli 固有的空白归一化——连续空格与内嵌换行会被压成一个空格（如 `str()` 输出前的双空格、`writexl` 提示里的 `\n`）。若将来要保留这些空白，只能退出 cli 的单串消息。
- 格式：全包无 `stop()/warning()/message()` 残留、无跨行字符串字面量、无被拆开的 glue 表达式、无超过 100 字符的行、全部文件可 `parse()`。
- 新增的开发期检查脚本（在 `$TEMP`，不入库）：`multiline.R`（跨行字面量）、`braces.R`（glue 花括号平衡）、`msgcompare2.R`（新旧消息渲染比对）、`runtests.R`（测试汇总）。批次 3 重构前后建议复用 `msgcompare2.R` 的思路。

## 四、仍未做（批次 3–5，按原报告执行）

- 批次 3：`Decomposition()` 数据驱动化（210 行 → 约 10 行）、`Mortality()`（303 行）、`.calc_attributable()`（145 行）、`.resolve_target_res()`（137 行）、`domain_summary()`（152 行）、`validate_mortality_input()`（175 行）拆分。
- 批次 4：`paste0()` → `str_c()`（注意 `str_c(NA)` 与 `paste0(NA)` 语义不同）、`ifelse()`/`apply()`/`tapply()` 残留、重复块抽函数、`join` 的 `relationship =` 断言、`.join_calc_fild()` 键唯一性检查。
- 批次 5：`.gitattributes` 固定 `eol=lf`（当前 CRLF/LF 混杂）、`README.Rmd`、CI（check-standard + test-coverage）、`.Rbuildignore`/`vignettes/.gitignore`/空 `_snaps` 清理。
- **决策项**（仍待你拍板）：导出 API 是否从驼峰迁到 snake_case（`getConc` → `get_conc`）；`Decomposition()` 的 `G/D/P/A/M/L` 是否改语义名；是否引入 `cli` 之外的其它改动（`cli` 已加入）。
- **提交**：本批改动未提交；工作区在你原有的未提交改动之上叠加（合计 53 个文件相对 HEAD 有差异），建议按主题拆成若干提交。

---

# 附：批次 3 执行记录（结构重构）

## 一、拆了什么

| 目标 | 结果 |
|---|---|
| `Decomposition()`（269 行） | 16 份手写 `Mortality()` 调用 → 一条规则（`at()` 决定每个驱动读 `from` 还是 `to`）+ `run(step)` 闭包；函数降到 99 行（含 24 行的 roxygen）。分支列改为按名取列，`globalVariables()` 里的 `mort_0`…`mort_4` 一并删除 |
| `Mortality()`（312 行） | 拆成 7 个阶段函数：`.check_mortality_args()`、`.map_input_columns()`、`.default_national_admin()`、`.report_boundary_match()`、`.uncertainty_frames()`、`.aggregate_keys()`、`.aggregate_result()`；函数降到 175 行，读起来就是七个阶段的调用序列 |
| `.calc_attributable()`（145 行） | 只留公共前置检查（CR 表缓存 → 超范围浓度告警 → 连接键规范化 → 端点交集 → 分支提示 → 空结果）；三条分支分别是 `.attributable_grid()`、`.attributable_by_domain()`（配 `.pwrr_by_domain()`）、`.attributable_one_field()`；宽表化统一 `.widen_mort()`，死亡率换算统一 `.PER_100K`；函数降到 48 行 |
| `.resolve_target_res()`（137 行） | 拆成 `.raster_resolutions()`（探测）、`.grid_size()`（判定）、`.prompt_resolution()`（交互菜单）；阈值提为 `.RES_AUTO_CONFIRM_CELLS`/`.RES_PROMPT_CELLS`/`.RES_MAX_CELLS`/`.RES_FALLBACK`/`.RES_SUGGESTIONS` 具名常量，不再散落在流程里 |
| 顺带 | `.permutations()` 改为预分配 + `list_flatten()`（原先是循环内 `c()` 增长） |

`R/AGENTS.md` 的文件职责表、七阶段说明、三条分支表与内部契约已同步更新（含新增的 `.PER_100K`、`.RES_*`、`.widen_mort()`、`.uncertainty_frames()` 等约定）。

## 二、发现的一处口径异常（**已按用户决定修正**）

重构 `Decomposition()` 时把 16 个分支反推成一条规则，结果发现**其中 1 个分支不服从该规则**：

- 规则（其余 15 个分支都满足）：某驱动"已移动"时读 `to`，否则读 `from`；其中 `PG→pop`、`PA→age`、`EXP→conc_cf`、`ORF→conc_real` 与 `mort_rate`。
- 例外：**前缀为 PG+EXP 的第二步**（`mort_2` 的 `PG EXP` 分支）读的是 `pop = from`、`age = to` —— 与"PG 已移动 → pop 取 `to`"正好相反，看起来是当年从 `PG PA` 分支复制后漏改。
- 影响面：24 种序列中的 **3、4、13、14** 四种（`PG-EXP-PA-ORF`、`PG-EXP-ORF-PA`、`EXP-PG-PA-ORF`、`EXP-PG-ORF-PA`），差异只出现在该步对应的驱动列上。

处理过程：重构阶段**先逐字保留现状**（在 `at()` 里写成显式例外并注明原因），用全 24 种序列的金标准比对确认重构前后逐列一致（`mismatching series: 0`）；随后把影响量化（只动 3/4/13/14 的两种驱动列、等额反号、起止点与总量不变）并提交用户决策。

**用户决定：改成规则。** 已执行：

1. `R/DrivingFactors.R` 的 `at()` 删掉例外，`Decomposition()` 每一步只移动它名字里的那个驱动；
2. `test-Decomposition.R` 用一条**覆盖全部 24 种序列**的不变量测试替换原先的"钉住现状"测试：每一步的驱动列必须等于「该前缀的运行 − 上前缀的运行」（96 条断言）——这条测试正是原先缺失的（旧测试只覆盖序列 1 和 24，所以这个 bug 一直潜伏）；
3. `NEWS.md` 记入 Repairs（说明受影响的序列、变化方式与量级），`R/AGENTS.md` 的分解口径条目改写为规则本身 + 该不变量；
4. 复验：与金标准比对，**只有** 3/4/13/14 变化，且每种序列恰有两条驱动列位移 +0.08945 / −0.08945（`Start`/`End`/总量逐位不变，望远镜加和仍成立）；测试 248 用例 / 843 断言全过（断言数因新不变量测试增加），指纹 42 条全过，`R CMD check` 重新验收。

## 三、验证证据

- 测试：`248 用例 / 750 断言，0 失败、0 错误、1 跳过`。
- 指纹回归：`ATTRMORT_FINGERPRINTS=1` → 42 断言全过。
- `Decomposition()` 金标准：重构前先保存 24 种序列的完整输出，重构后逐列比对 → **0 处不一致**（含上述例外分支）。
- 消息文本：按文件做"旧调用文本必须仍能在新文件里渲染出来"的比对，`Mortality.R` 剩余的 6 处差异经逐条人工核对全部是校验器哨兵造成的假阳性（文本片段在新文件中逐字存在，已 grep 验证）；其余文件差异同前两批的已知类别。
- 格式：全包 `parse()` 通过、行宽 ≤ 100、无 base 信号残留、无跨行字符串字面量、无失衡 glue 花括号。
- `R CMD check`（含 vignette 构建）：`Status: OK`（0 error / 0 warning / 0 note）。中途曾因 `PWRR` 从局部变量变成数据掩码列而出现 1 个 NOTE，已加入 `globalVariables()` 解决。

---

# 附：导出 API 命名统一（261001，用户拍板后执行）

按用户决定，把不符合 skill §2/§10.4 的历史命名一次性改掉，**不留兼容别名**。命名风格最终定为：主入口保留用户习惯的名词 `mortality()`（只把首字母小写，满足 snake_case；§2 的"函数用动词"是通则偏好而非硬规则），分解入口取动词 `decompose()`，其余历史命名一律小写化：

| 旧 | 新 |
|---|---|
| `Mortality()` | `mortality()` |
| `Decomposition()` | `decompose()` |
| `RR_std()` | `rr_std()` |
| `getConc()` / `getPop()` / `getAge()` / `getMort()` | `get_conc()` / `get_pop()` / `get_age()` / `get_mort()` |
| `decompose()` 形参 `G`/`D`/`P`/`A`/`M`/`L`/`D_cf` | `calc_fild` / `conc_real` / `pop_total` / `age_struc` / `mort_rate` / `mort_lvl` / `conc_cf` |

连带动作：

- 文件随主函数改名：`R/Mortality.R` → `mortality.R`、`R/DrivingFactors.R` → `decompose.R`、`R/RR_std.R` → `rr_std.R`；对应测试文件同步为 `test-mortality.R` / `test-decompose.R` / `test-rr_std.R`（用 `git mv` 保留历史）。
- README、vignette、项目与实现层 AGENTS.md、`data-raw/`、`NEWS.md` 的 0.3.0 段同步改名；`NEWS.md` 的 0.2.0/0.1.0 历史段保持原样（那是当时的 API）。
- `man/` 全量由 roxygen 重新生成（旧页自动删除），`decompose()` 的七个数据参数改用 `@inheritParams mortality`，不再逐条写“refers to ...”。

**顺手修掉一个被掩盖的问题**：批次 3 插入阶段函数时，roxygen 块与主函数之间被插进了一层注释，文档因此挂到了 `.check_mortality_args()` 上（`R CMD check` 只校验已有的 `man/`，不重跑 roxygen，所以当时仍显示 `Status: OK`）。已把阶段函数移到主函数之后，并新增一个检查脚本（roxygen 块必须紧贴其对象，否则报告）扫全包确认再无同类问题。

验证：测试 248 用例 / 843 断言全过，指纹 42 条全过，`R CMD check` 重新验收；全仓用户可见文件（R/、tests/、vignettes/、README、两个 AGENTS.md、data-raw/、NAMESPACE）已确认无旧名残留。

---

# 附：`decompose()` 架构改造（261001，按"大幅减少冗余和依赖"执行）

## 问题

- 旧 `decompose()` 每一步都完整跑一遍 `mortality()`（5 次）：每次都重读/重映射输入、重贴边界、重建 C-R 查表（GEMM 表 192 ms/次）。单次 `decompose()` 实测 **1767 ms**，其中约 55% 是同一张表建了五遍。
- 依赖链 `decompose → mortality → get_*`：`get_*` 在包内只被 `.extract_scenario()` 调用。

## 做法

1. 抽出 **`.prepare_inputs()`**：文件检查、栅格对齐、列名映射、网格一致性、边界并入，`mortality()` 与 `decompose()` 共用（两个调用者，不再各写一份）。`mortality()` 因此再瘦身一截。
2. **重写 `decompose()`**：`.prepare_inputs()` 一次 → `.extract_scenario(from)` / `(to)` 各一次 → `rr_std()` 一次 → `.calc_attributable()` 五次（`RR_tbl` 传入，不再重建）→ **直接组装**（去掉原先 `pivot_longer()`/`pivot_wider()` 的往返，改为按「每格铺满各层」拉直后相邻两步相减）。不再调用 `mortality()`，也不再调用 `get_*`。
3. **`get_*` 撤出公开 API**：改为内部切片器 `.slice_conc()`/`.slice_pop()`/`.slice_age()`/`.slice_mort()`，唯一调用者 `.extract_scenario()`。公开 API 17 → 12 个，`man/` 27 → 23 页。

## 结果

| 指标 | 前 | 后 |
|---|---|---|
| 单次 `decompose()` | 1767 ms | **573 ms**（3.1×） |
| 测试套件 | 180 s | **114 s** |
| `test-decompose.R` | 95.1 s | **23.7 s** |
| 公开 API / `man/` | 17 / 27 | **12 / 23** |

- **24 种序列金标准**：除已确认修正口径的 3/4/13/14 外，逐列一致（`unexpected differences: 0`）。
- 测试 248 用例 / 843 断言全过，指纹 42 条全过，`R CMD check` 重新验收。
- 行为差别（已记入 `NEWS.md`）：输入校验与 `Analysis grain` 提示从"每步一次"变为"每次调用一次"。
- `test-decompose.R` 的不变量测试改为按"已移动驱动集合"缓存参考运行（24 种序列共用 15 个前缀），断言数不变、耗时降一半以上。

## 单次依赖组件盘点（对应"清理只被单次依赖的未暴露组件"）

用调用图扫全包，**未导出且只有一个调用者**的组件实际只有两个：

| 组件 | 行数 | 唯一调用者 | 建议 |
|---|---|---|---|
| `align_to_target()` | 54 | `.align_raster_inputs()` | 保留：完整的一次重采样/重投影操作，内联会把调用者撑到 100 行以上 |
| `shapefile_to_grid()` | 56 | `.attach_admin()` | 保留：面→网格栅格化，同上 |

"导出但包内只被调用一次"的清单里，`get_*` 已按本次改造撤出；`cr_models()`、`build_grid_info()`、`aggregate_ci()` 经逐个 grep 核实只是**文档提及**而非真实调用，属于面向用户的功能，是否裁掉见 style_review 正文的"平行工具"表。
