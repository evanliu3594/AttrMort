# 两个入口：参数、流程、输出

重构后（261001）的实测记录，依据是源码调用顺序与真实返回值，不是设计意图。

## 一、参数

### 共用的一组（15 个，两边同名同义）

| 组 | 参数 | 默认 | 说明 |
|---|---|---|---|
| 输入数据 | `calc_fild` | `mortality()` 为 `NULL`；`decompose()` 必填 | 归因场。给定后是所有连接键的来源；`mort_lvl` 指向的列必须在这里 |
| | `conc_real` | 必填 | 实际暴露。栅格路径下它同时定义分析网格 |
| | `conc_cf` | `NULL` | 反事实暴露；不给时用 `conc_real`。`decompose()` 里只有第 0 步用它 |
| | `pop_total` | 必填 | 人口 |
| | `age_struc` | 必填 | 年龄结构，列名规范化为 `prop`，域内归一化到 1 |
| | `mort_rate` | 必填 | 基线死亡率，列名规范化为 `mortrate` |
| 模型与查表 | `CRF` / `crf` | 必填 | 模型名（进配置）或查表 `data.frame` |
| | `CI` / `ci` | `"MEAN"` | `MEAN`/`UP`/`LOW` |
| | `cr_config` | `NULL` | 模型配置；`NULL` 用 `inst/extdata/cr_models.json` |
| 空间与键 | `admin` | `NULL` | 边界。`NULL` + 栅格输入 + 需要域校准时回落到 rnaturalearth 国界 |
| | `admin_col` | `"admin"` | 边界标签列 |
| | `target_res` | `NULL` | 目标分辨率；`NULL` 时探测 + 交互确认（非交互直接回退） |
| | `dgt_coord` | `2` | 坐标键小数位 |
| | `dgt_conc` | `1` | 浓度键小数位，必须与查表一致 |
| 运行控制 | `validate` | `c("warn","stop","off")` | `off` 同时关掉校验、网格一致性检查和 `Analysis grain` 提示 |

### 各自特有

| 函数 | 参数 | 默认 | 作用 |
|---|---|---|---|
| `mortality()` | `mort_lvl` | `NULL` | PWRR 校准的域列名。`NULL` = 网格级不校准；不是 `mort_rate` 的列 = 全域一个单位（告警） |
| | `scenario` | `NULL` | **单组**的情景选择器：命中列名 > 规范列 > 唯一数值非键列 |
| | `chunk_ages` | `NULL` | 按年龄分块计算，降峰值内存 |
| | `aggregate` | `NULL` | `TRUE` 按 `mort_lvl` 聚；也可给列名向量 |
| | `aggregate_by` | `"total"` | `total`/`endpoint`/`age`/`all` |
| | `uncertain` | `FALSE` | 输出 `CI_LOW`/`CI_UP` |
| | `conc_uncert` | `0` | 暴露不确定度百分比，进入区间链 |
| `decompose()` | `mort_lvl` | **必填** | 同上（无 `NULL` 默认，与 `mortality()` 不一致，待统一） |
| | `from`, `to` | 必填 | **两组**的两个情景名，逐输入列选择器 |
| | `serie` | 必填 | 1..24，驱动顺序（PG/PA/EXP/ORF 的排列） |

命名不一致处（本次重构未动，建议后续统一）：`CRF`/`CI` 对 `crf`/`ci`；`mort_lvl` 一边必填一边可省。

## 二、流程

### 共用段：`.prepare_inputs()`

```
.mortality()/.decompose() 都先走这一段，只走一次
  1. CRF → 配置 + 模型名（.as_cr_config / .match_cr_model）
  2. 栅格识别（conc_real / pop_total 是否 SpatRaster）
  3. .check_input_files()      字符输入必须是存在的文件
  4. .align_raster_inputs()    目标分辨率、重投影/重采样、栅格→表（template 留用）
  5. .map_input_columns()      逐输入读文件 + detect_columns() 列名映射
  6. .check_grid_match()       手供骨架 vs 栅格网格：0 命中报错、部分命中告警
  7. .default_national_admin() + .attach_admin() + .report_boundary_match()
                               边界并入 calc_fild；国界回落时报告匹配域数
  → 返回 canonical 表 + template + config + crf_name
```

### `mortality()`（126 行，实测调用顺序）

```
.match_ci → .check_mortality_args                 参数/CI 先失败，不等到读完文件
.prepare_inputs                                   共用段（上面 1–7）
.extract_scenario(scenario)                       每个输入取一列，命名规范化
conc_cf 缺省 → conc_real
validate_mortality_input                          validate != "off"：报告；"stop" 时报错
.check_inputs                                     连接键检查（同键类型、共享键）
cli_inform(.grain_message(...))                   "Analysis grain: …" 每次调用一次
compute() = .calc_attributable_ages(CI)           中心估计（内部按 chunk_ages 分块，
                                                   内部再分派 .calc_attributable 的三条分支）
  ├─ uncertain: .uncertainty_frames()             CRF 分位 + conc_uncert 链，共用同一 compute()
  ├─ aggregate: .aggregate_keys() → .aggregate_result()
  └─ 否则 uncertain: .range_sum() → CI_LOW / CI_UP
返回 data.frame
```

### `decompose()`（134 行，实测调用顺序）

```
.match_ci → serie 校验 → .permutations(.DRIVER_ORDER)[[serie]]
.prepare_inputs                                   与 mortality() 同一段，只走一次
.extract_scenario(from)                          第 1 组
.extract_scenario(to)                            第 2 组
validate_mortality_input + .grain_message         每次调用一次（旧实现是每步一次）
.check_inputs                                     用 from 侧的表检查一次
rr_std(crf, ci)                                   五种步共用同一张 C-R 表
map(0:4, run)                                     run() = .calc_attributable(...)
    pick(name, driver, step)                      唯一变化点：
        PG  → pop_total      （已移动取 to，否则 from）
        PA  → age_struc
        EXP → conc_real 充当 conc_cf（第 0 步用 conc_cf 输入）
        ORF → conc_real 与 mort_rate
    每步传入 RR_tbl，不重建查表
组装：每步宽表按「每格铺满各年龄层」拉直 → 相邻两步相减 → Start/驱动列/End
cat("Drivers Between from and to: …")             摘要
返回 data.frame（长表）
```

**两边的分工边界**：文件、栅格、边界、列名、连接键只在一处发生（`.prepare_inputs()`）；`.calc_attributable()` 只接受已经规范的 `data.frame`，不做 I/O、不猜列名。

## 三、输出

### `mortality()`：一行一个网格（或一个域）

| 模式 | 形状 | 列 |
|---|---|---|
| 默认（网格级） | 4 格 × 5 列（小 fixture） | 键列（`x`, `y`, `location`）+ 每个「端点×年龄」一列（`ncd+lri_25`, `ncd+lri_30`） |
| `uncertain = TRUE` | 同上 + 2 列 | 末尾加 `CI_LOW`, `CI_UP` |
| `aggregate = TRUE`（`aggregate_by="total"`） | 一行一个域 | `location`, `total`, `conc_pwe` |
| `aggregate_by = "endpoint"` | 一行一个域 | `location`, `total`, `ncd+lri_all`, `conc_pwe` |
| `aggregate_by = "age"` | 一行一个域 | `location`, `total`, `all_25`, `all_30`, `conc_pwe` |
| `aggregate_by = "all"` | 一行一个域 | `location`, `total`, `ncd+lri_25`, `ncd+lri_30`, `conc_pwe` |
| 聚合并 `uncertain = TRUE` | 上行 + 2 列 | 末尾加 `CI_LOW`, `CI_UP` |

`total` 是该域归因死亡合计，`conc_pwe` 是人口加权暴露。键列随 `calc_fild`/`mort_lvl` 而变（域校准时是域列）。

### `decompose()`：一行一个「格子 × 年龄层」

| 列 | 含义 |
|---|---|
| 键列（`x`, `y`, `location`） | 来自 `calc_fild` |
| `Cause_Age` | `端点_年龄`，如 `ncd+lri_25` |
| `Start` | 两组的起点（`from` 情景全跑） |
| 四个驱动列（按 `serie` 顺序命名，如 `PG`, `PA`, `EXP`, `ORF`） | 该驱动这一步的贡献 |
| `End` | 两组的终点（`to` 情景全跑） |

不变量：`Start + Σ驱动列 = End`（逐行成立），且**每一步只移动它名字里的那个驱动**（24 种序列由测试覆盖）。
