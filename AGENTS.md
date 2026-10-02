# AGENTS.md

本文件是本仓库（`AttrMort`，R 包）的**项目级顶层约定**，约束所有在此仓库工作的 agent。
实现层细则见 `R/AGENTS.md`。

> ⛔ **本文件只放约定，不放进度**：不得在此记录“已完成 / 阶段 N / 待办”一类内容。
> 进度属于 git 提交，发布说明属于 `NEWS.md`，前向计划属于 `R/AGENTS.md`。
> 用户级全局约定（`~/.dsh/AGENTS.md`）优先于本文件。

## 一、项目定位

`AttrMort` 是一个**自包含的通用归因死亡计算包**：不指向、不依赖任何外部项目、私有路径或非公开数据。

本仓库的目标是一个通用归因死亡计算包，三条性质不可退让：

1. **污染物无关** —— PM<sub>2.5</sub>、O<sub>3</sub>、NO<sub>2</sub> 与用户自带查表走同一条代码路径；
2. **输入无关** —— data.frame、CSV/Excel、GeoTIFF 一律自动对齐、映射、连接；
3. **状态无关** —— 无全局变量、无 `assign()`、不假设工作目录，路径一律由参数传入。

任何新增或改写的代码都要满足这三条。

## 二、硬约束

1. **临时产物不得落在仓库内**：日志、tarball、`.Rcheck`、备份一律放 `$env:TEMP` 或包外目录；仓库顶层只保留标准 R 包结构。
2. **`tests/` 下只能放 testthat**：`R CMD check` 会执行 `tests/` 里每个 `.R`；手工脚本与开发工具放 `data-raw/`（该目录不进构建）。
3. **原生管道 `|>`**，管道右侧必须是函数调用（`x |> sum()`，不是 `x |> sum`）。
4. **数据目录必须小写 `data/`**：git 索引里大小写错误在 Windows 上不可见，但在 Linux/CRAN 上会得到一个没有 `data/` 的包。
5. **依赖成对声明**：`DESCRIPTION` 与 `R/AttrMort-package.R` 的 roxygen 导入必须在同一次改动里；可选依赖放 `Suggests` 并用 `requireNamespace()` 守卫。
6. **导出面收敛**：只有公开 API 出现在 `man/`，内部函数用 `@noRd`；新增导出必须跑 `devtools::document()` 并确认 `man/` 只多出该函数一页。
7. **不得引入需要全局状态的新依赖**（全局变量、`options()` 副作用、写用户目录的包）。
8. **一次改动一个主题**，提交信息写清“为什么”。
9. **自包含**：示例数据与测试数据一律由仓库内脚本生成（`data-raw/make-example-data.R` → `inst/extdata/`）；除 `data/` 下内置的浓度-反应查表外，不引入任何外部数据源、路径或受许可限制的文件。

## 三、数据契约（对外接口）

| 维度 | 约定 |
|---|---|
| 规范列名 | `conc`、`pop`、`age`、`prop`、`endpoint`、`mortrate`、`location` |
| 连接键 | 坐标列（`x`/`y`、`lon`/`lat`）与/或域列；一律经 `matchable()` 渲染成定精度字符串 |
| 场景列 | 宽表每场景一列（或栅格一个 band），`scenario=` 经 `.slice_conc()`/`.slice_pop()`/`.slice_age()`/`.slice_mort()` 抽取 |
| 值列选择 | `scenario=` 是**逐输入**的列选择器，不是跨输入契约：输入无该列时用规范列（`conc`/`pop`/`prop`/`mortrate`）或唯一数值列并 `message()` 说明；多候选且无规范列必须报错列出候选，**不得猜**；不判断跨输入情景/年份是否一致 |
| 运行输出 | 内部 join 一律显式传键（`.left_join_common()`），不得打印 dplyr 自然 join 的 `Joining with ...` 提示；`validate = "off"` 下运行除自身结果外不输出 |
| 浓度键 | 字符，两侧同为 `dgt_conc` 位（默认 1）：暴露数据与查表都必须遵守；字符键须是 `matchable(conc, dgt_conc)` 的规范形式，否则校验期告警（`validate = "off"` 关闭） |
| 浓度栅格存储 | 用 Float64（或已按 `dgt_conc` 取整的值）：Float32 的约 1e-6 相对误差足以把值推过取整边界，导致查不到表 |
| 多情景栅格掩膜 | 各波段（情景）必须共享同一有效掩膜：某格只在部分波段有值时 `raster_to_grid()` **告警**并列出各层缺测数，该格从分析网格剔除；不允许逐情景缺测后静默改变网格 |
| 非方形栅格 | 目标分辨率按轴保留（`target_res` 可传长度 1 或 2，自动检测取每轴最细），**不得**把 `resx`/`resy` 取均值后重采样；`build_grid_info()` 的 `res` 在非方形时为 `c(res_x, res_y)` |
| 分块与空年龄块 | `age_struc` 缺档时，只含缺档年龄的块必须跳过，分块结果与不分块一致；全部块为空时走不分块路径报"无行存活"，不得中止于空块 |
| 坐标键 | 字符，`dgt_coord` 位（默认 2） |
| 年龄 | 字符型 5 岁分层（`"25"`、`"30"`…）；数值型年龄会被规范成整年 |
| 死亡率单位 | 每 10 万，计算中除以 1e5 |
| 结果列 | `{endpoint}_{age}` 宽表；端点可能含 `+`、`.`、`_`，解析时从右往左切 |
| CI 标签 | `"MEAN"`、`"UP"`、`"LOW"`（接受 `"UPPER"`/`"LOWER"` 别名） |

### 域级表 → 网格的匹配（数据工作流）

输入分两类，**以域名为唯一接口**对接：网格化输入（浓度 tif/nc、人口总量 tif）逐格；域级输入（死亡率：域×年龄×端点；年龄结构：域×年龄占比）每域若干行。

1. **域标签来自边界**：`admin=`（shp/geojson/gpkg/sf）栅格化到目标网格，每格得到一个 `location`；栅格路径下 `admin = NULL` 时默认用 `rnaturalearth` 国界（国家级），表格路径的域标签可来自 `calc_fild` 自带的域列。这是唯一把地理信息落到格上的一步。
2. **广播，不是插值**：`left_join` 只以 `location`（+ `age`、`endpoint`）为键，把 `prop`、`mortrate` 复制到该域的每一格。
3. **逐格负担**：`M_格 = pop_格 × prop_域,年龄 × mortrate_域,年龄,端点 / 1e5`（每 10 万只在这里除一次）；PWRR 分支再乘校准项，其中 `PWRR = weighted.mean(RR(conc), pop)` 按 `(域, 年龄, 端点)` 在域内按人口加权求得，逐格用 `M_格 × (RR(conc_cf) − 1) / PWRR`。
4. **`mort_lvl` 指定校准域**：它是 `mort_rate` 的列时按该列分组校准；不是其列时全域视为一个单位（告警）；`mort_lvl = NULL` 退化为逐格 PAF（RR 取实际浓度）。

推论（改代码或换数据前必须知道）：

- **网格上的空间差异只来自 `pop` 与 `conc`**：同一域内每格的人均归因死亡率相同，死亡数的空间格局完全由人口分布决定。这是域级数据可得性决定的，不是近似误差。
- **接口只有域名**：网格里的 `location` 取值必须与域级表的 `location` 完全一致（建议用 ISO3，并以 `admin_col=` 选出对应列）。不一致的表现是匹配到 0 个域或空结果；栅格路径会回报匹配到的域数。
- **与分辨率无关**：国级表配 0.1° 还是 1 km 是同一套键连接；网格变细只是让 `pop`/`conc` 的分布与域内校准量更细。换成省、市级只需提供对应级别的边界并设 `admin_col` 与 `mort_lvl`。

```r
mortality(
  crf       = "GEMM",
  conc_real = "pm25_2015.tif",              # 网格：定义分析网格
  pop_total = "pop_2015.tif",               # 网格：按网格聚合
  age_struc = "gbd_age_structure.csv",      # 域级：location, age, prop
  mort_rate = "gbd_mortality.csv",          # 域级：location, age, endpoint, mortrate
  admin     = "world_admin0.shp",           # 域标签来源；NULL 时为 rnaturalearth 国界
  admin_col = "iso_a3",                     # 边界里代表域名的列
  mort_lvl  = "iso_a3"                      # 校准域（与 admin_col 同一套命名）
)
```

### 网格定义（grid_info）

分析网格由 `conc_real`（栅格）或 `calc_fild`（表格）唯一确定。需要复用网格、留档或交给别的工具时，用 `build_grid_info()` 生成一份 info 表（`x, y, <域名…>`）并可落盘。

- **单一事实来源**：同一次分析的所有情景必须跑在同一张网格上；info 表就是这张网格的物证（带 `res`/`ext`/`crs`/`n_cells`）。
- **交回时必须对得上**：`mortality(calc_fild = <info 表>)` 在同时存在栅格输入时做网格一致性检查——坐标键必须落在栅格网格上：**0 个键命中即报错**（两张网格根本不同，绝不继续算）；**部分命中则告警**并给出未命中计数。两种检查都受 `validate = "off"` 关闭，**不得静默按旧网格计算**。
- **网格定义只由两类东西产生**：栅格输入（`conc_real` 定义网格）或用户给的 `calc_fild`；边界只提供域标签，不改变网格。

## 四、口径（未经用户确认不得更改）

- **不确定性是 range，不是抽样区间**：逐格取查表 LOW/UP 再求和（共模），`CI_LOW`/`CI_UP` 为总量区间；`conc_uncert` 是**百分数**，会重跑一遍并取两条链的并集。
- **域级中心估计 = 网格级结果按域求和**，与 `mortality()` 自身计算自洽。
- **PWRR 分支**：`mort_lvl` 决定校准域，`conc_cf` 决定风险项 —— 两者不可互换。
- 上述口径若必须变更：在同一次改动里同步 `tests/` 与 `NEWS.md`，并向用户说明数值影响与涉及的函数。

## 五、构建与验收

```bash
Rscript -e 'devtools::test()'                      # 全量测试
Rscript -e 'devtools::test(filter = "mortality")'  # 单个测试文件
Rscript -e 'devtools::document()'                  # 改 roxygen 后
Rscript -e 'devtools::check()'                     # 完整检查
```

- **验收门槛**：`devtools::test()` 全绿 **且** `R CMD check` 为 `Status: OK`（0 error / 0 warning / 0 note）。
- 沙箱下 `devtools::check()` 会因为要开管道拉起 `Rcmd.exe` 而被拒；改为直调两步，产物放临时目录。
- **必须让 vignette 参与构建**：`--no-build-vignettes` 不会生成 `inst/doc/`，`R CMD check` 会因此报 2 个 WARNING（`no files in 'inst/doc'`、`Directory 'inst/doc' does not exist`），永远拿不到 `Status: OK`。该参数只适合不关心 vignette 的快速检查。

```powershell
$R = 'C:\Program Files\R\R-4.6.1\bin\R.exe'
Set-Location (New-Item -ItemType Directory -Force (Join-Path $env:TEMP 'attrmort-check'))
& $R CMD build 'D:\GitDir\AttrMort'
& $R CMD check AttrMort_0.3.0.tar.gz --no-manual
```

## 六、协作约定

- **口径不明确先问用户**，不要替用户拍板；涉及既有行为时先读代码与测试确认现状，再动手并给出证据。
- **破坏性 API 变更**必须单独列出，说明改了什么、谁会受影响。
- 数值路径改动前后各跑一次指纹回归：设 `ATTRMORT_FINGERPRINTS=1` 跑 `devtools::test(filter = "fingerprints")`（`=update` 重写参照）。
- 讨论与结论写进代码注释、`NEWS.md` 或提交信息；**不要写进本文件**。