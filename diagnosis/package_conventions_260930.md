# package_conventions_260930 — R 包一般规范审计（2026-09-30）

- **范围**：仓库 `D:/GitDir/AttrMort` 分支 `refactor/json-crf-migration`（含新增 vignette 后的状态）。
- **方法**：结构/字段逐项核对 + `R CMD build`（**带 vignette 构建**）+ `R CMD check --no-manual` + `lintr::lint_dir("R")` 摘要 + 低版本/状态性构造的静态扫描。
- **结论**：**满足 R 包一般规范**；本轮补齐了唯一缺口（vignette）并修掉一处声明兼容性漏洞（测试使用了 R ≥ 4.4 的 `%||%`，DESCRIPTION 声明 R ≥ 4.1）。`R CMD check` `Status: OK`（0 ERROR / 0 WARNING / 0 NOTE）。

## 一、逐项核对

| 维度 | 要求 | 实测证据 | 判定 |
|---|---|---|---|
| DESCRIPTION 元数据 | Package/Type/Title/Version/Authors@R/License/Encoding | `Authors@R` 含 ORCID；`License: MIT + file LICENSE`，`LICENSE` 含 YEAR/COPYRIGHT HOLDER | 通过 |
| 描述字段 | `Description:` 完整句、写清能力 | 已含 C-R 配置、栅格/表格输入、分解与不确定性 | 通过 |
| 依赖声明 | `Depends: R (>= 4.1)`；Imports 均被使用 | 扫描确认无 R ≥ 4.4 构造（已修测试中的 `%||%`）；`jsonlite` 等全部实际调用；Suggests（rnaturalearth/writexl/knitr/rmarkdown）使用处有守卫或由 VignetteBuilder 使用 | 通过 |
| 非标准目录 | 必须 `.Rbuildignore` | `AGENTS.md`、`R/AGENTS.md`、`data-raw`、`diagnosis`、`.github` 均已排除；tarball 实测不含 | 通过 |
| 文档 | 每个导出有 man 页、示例可跑 | `checking for missing documentation entries ... OK`；`checking examples ... OK`；roxygen 重生成后 `NAMESPACE`/`man/` 一致 | 通过 |
| 数据 | `data/` 小写、LazyData、压缩 | 9 张 xz/version 3 表；`checking LazyData ... OK`、`checking data for ASCII and uncompressed saves ... OK` | 通过 |
| 测试 | 仅 testthat；可独立复现 | `tests/` 只有 `testthat.R` + `testthat/`；683 条断言 0 失败 0 警告；指纹 42 全过（含示例数据自洽） | 通过 |
| **vignette** | 有 index entry/engine、可构建、随包安装 | 新增 `vignettes/AttrMort.Rmd`；`R CMD build` 生成 `inst/doc/{R,Rmd,html}`；`checking package vignettes ... OK`、`checking re-building of vignette outputs ... OK` | 通过（本轮补齐） |
| 可移植性 | LF、无绝对路径、不依赖工作目录 | 构建无行尾问题；代码无 `setwd()`/`assign()`/`globalenv()`（`R/DrivingFactors.R` 的 `assign` 仅出现在 `\dontrun` 文档示例里）；路径全部参数化或 `system.file()` | 通过 |
| 仓库卫生 | 无构建残留、无大文件误入库 | `git status` 干净；构建/检查产物均在 `%TEMP%`；`.Rbuildignore` 排除诊断目录 | 通过 |
| 完整检查 | `R CMD check` 0/0/0 | 带 vignette 构建：退出码 0，`Status: OK`；唯一 INFO 为安装体积 8.7 MB（`data/` 8.0 MB）；check 内测试 `FAIL 0 / WARN 0 / PASS 683` | 通过 |

## 二、lintr 摘要（信息级，不作为门槛）

`lintr::lint_dir("R")` 共 626 条，按 linter：`object_usage_linter` 457、`line_length_linter` 51、`object_name_linter` 48、`quotes_linter` 44、`indentation_linter` 13、其余 ≤ 4。

- `object_usage_linter` 的绝大多数是 tidy-eval/NSE 误报（列名通过 `mutate`/`filter` 数据掩码引用，已用 `utils::globalVariables()` 声明），非缺陷。
- 其余为风格偏好（行宽、引号、缩进），与仓库既有 tidy 风格不冲突到需要返工的程度。
- 可选：后续加一个 `.lintr` 配置（关掉 NSE 误报、放宽行宽到 100）并把 lintr 纳入开发流程；本轮未做，避免大面积格式噪音。

## 三、未做/限制

1. **未跑 `R CMD check --as-cran`**：CRAN incoming feasibility 与 URL 检查需要联网，且 GitHub 远程包在 as-cran 下会有既定 NOTE；发布到 CRAN 前应在联网环境补跑。
2. **只在 Windows / R 4.6.1 上验证**：CRAN 还需 Linux/macOS 与旧版本 R 检查。
3. `Config/roxygen2/version` 存在而没有 `RoxygenNote`：两者 roxygen2 8.x 均接受，`R CMD check` 无提示；可按需补 `RoxygenNote: 8.1.0` 以兼容老工具链。

## 四、结论与后续

- 本轮验收链：`devtools::test()` → `FAIL 0 / WARN 0 / PASS 683`；指纹 `PASS 42`；`R CMD build`（带 vignette）退出码 0；`R CMD check --no-manual` `Status: OK`（0/0/0）。
- 发布前仍需（按用户此前决定暂缓）：`NEWS.md` 补记本轮迁移与破坏性变更（NO₂ 端点改名、`cr_models()` 来源变化、batch API 移除）并提升版本号；联网环境补 `--as-cran`。
