# data-raw

开发期脚本。本目录**不参与构建**（`.Rbuildignore` 里有 `^data-raw$`），`R CMD check` 不会执行其中任何脚本。

| 脚本 | 作用 |
|---|---|
| `make-example-data.R` | 生成 `inst/extdata/` 下的六个示例文件：网格地理信息、网格化暴露、网格化人口、国家级人口、国家级年龄结构、国家级死亡率。全部是合成数据，固定随机种子，可重复运行。 |

约定：

- **示例数据一律自造**：包内不引入任何外部数据源、私有路径或受许可限制的文件。`data/` 下内置的九张浓度-反应查表是唯一的真实曲线，其内容是公开发表的 C-R 参数化结果（见 `?RR_std` 与 `?build_cr_table`）。
- 改动生成脚本后要重跑它，并重写指纹参照：设 `ATTRMORT_FINGERPRINTS=update` 跑 `devtools::test(filter = "fingerprints")`。
- **手工冒烟与回归装置不放这里**：数值回归已收进 `tests/testthat/test-fingerprints.R`（设 `ATTRMORT_FINGERPRINTS=1` 比对，参照指纹在 `tests/testthat/fixtures/fingerprints/`）。
- `tests/` 下每个 `.R` 都会被 `R CMD check` 执行，因此手工脚本不要放回 `tests/`。
