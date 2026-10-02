# 真实栅格摄取校验（T1）：未声明填充值、键塌缩与对齐插值

> 数据：`validate-data/` 下两个真实栅格（只读）。本文只写**亲手跑过**的数字，命令见第七节。
> 行号以本文件提交时的 `R/` 为准；另有线在并行改 `R/schema-detect.R`、`R/mortality.R`、`R/ingest.R`，那些文件的行号会随后续提交移动。

## 一、结论摘要

| # | 现象 | 性质 | 本次是否已修 |
|---|---|---|---|
| 1 | netCDF 的 `-999`（294 万格，62.88%）未声明为缺测，摄取层只按 NA 丢格；`validate = "stop"` 整单拒绝、`"warn"` 继续算、`"off"` 全静默 | 真实缺陷（可见性缺口） | 是：摄取期点名报告，不改变数值 |
| 2 | 浓度栅格对齐用 `bilinear`，填充值在 terra 眼里是数不是 NA，被插值**新造**出 1,961 个不同负值（0.15° 海岸窗） | 真实缺陷（本次新发现） | 报告里给出建议，未实现（见第六节） |
| 3 | `dgt_coord` 过粗时栅格坐标键静默塌缩（0.01° 默认设置丢 49.6% 格子；0.001° 塌成 1 格并返回 list 列结果） | 真实缺陷（表格路径有检查、栅格路径没有） | 是：摄取期告警并给出所需位数 |
| 4 | 表格曝光 + 栅格人口时，边界被栅格化到**人口**的格子上，骨架却来自曝光表；差异以一个指错对象的报错暴露 | 真实缺陷（报错可读性） | 未实现（`R/ingest.R` 属 T2 写域），见第六节 |

题面问的「什么情况下会静默错位」，判定见第三节之三：**两张栅格之间不会发生键错位**；错位只出现在「骨架不由栅格产生」的两条路（表格骨架、`dgt_coord` 过粗）。

## 二、复核 Lead 的三条起点事实

### 事实 1：`-999` 是未声明的填充值 —— 通过，但「neg 计数错误」不成立

```
terra::NAflag(rast(nc))        -> NaN        # 没有任何声明
terra::values(nc)              -> 4,680,000 个值里 0 个 NA
                                  2,942,617 个等于 -999（62.88%）
                                  1,737,383 个 > 0
```

`AttrMort:::raster_to_grid(nc, dgt = 2)` 之后：4,680,000 行、**0 个 NA**、2,942,617 个 `-999`、0 个重复 `(x, y)` 键；`.rename_single_band()` 正常把 `PM25` 改名成 `conc`。

`validate_mortality_input()` 的判定是：

```
valid    = FALSE
blocking = "conc: 2,942,617 negative value(s) in 'conc'"
```

**2,942,617 与真实 `-999` 的格数完全一致**，`sum(conc_vals < 0, na.rm = TRUE)` 没有数错。机制：`.slice_conc()` 把数值渲染成字符键 `"-999"`（`R/prepare-inputs.R:378`），校验期 `as.numeric()` 又还原回来（`R/schema-detect.R:377-378`），所以计数正确。工单里「neg 计数错误」这一条**未能复现**；如果 Lead 看到的是别的数，请给出当时的输入形态，我再核。

`validate = "off"` 下确实什么都不报——这是既有契约（`R/mortality.R:385` 的 `quiet`），不是计数问题。

### 事实 2：`raster_to_grid()` 只按 NA 丢格 —— 通过

见上：2,942,617 个 `-999` 全部留在表里，`n_na == 0` 之后没有任何基于取值的过滤（`R/raster-io.R:60-75`）。

### 事实 3：坐标键一致 —— 通过，并补充判定

Lao PDR 窗（100–107.7°E / 13.9–22.6°N）：

| 量 | 值 |
|---|---|
| netCDF 窗 dim / res | 87 × 77 / 0.099999998304 |
| 模板 `terra::rast(ext(nc_w), resolution = res(nc_w))` | `ext(tmpl) == ext(nc_w)` 为 TRUE，dim 87 × 77 |
| LandScan 窗 dim → `.aggregate_pop()` 后 | 1044 × 924 → 87 × 77 |
| x 键 | 77 / 77，共享 **77** |
| y 键 | 87 / 87，共享 **87** |
| 键样例 | 两侧都是 `100.05, 100.15, 100.25, …` |

包内确实没有任何「格心是否落在网格上」的检查；只有针对**用户自供** `calc_fild` 的 `.check_grid_match()`（`R/prepare-inputs.R:78-115`，触发条件见 `R/prepare-inputs.R:537-547`，要求 `own_skeleton`）。判定见下。

## 三、真实缺陷

### 缺陷 1：未声明的填充值在摄取层无感知，三种 `validate` 各有各的坏

**现象。** 62.88% 的格带着 `-999` 进入分析表，速率上它就是一根普通数值。

**影响（三条路都实测或按代码可判定）：**

- `validate = "stop"`：`blocking` 非空 → `.abort("Input validation failed: …")`。一个只覆盖陆地、用 `-999` 表示海洋的正常卫星产品，被整单拒绝。
- `validate = "warn"`（默认）：继续算。`-999` 渲染成键 `"-999"`，落在 GEMM 查表范围 `[0, 300]` 之外（`rr_std("GEMM", "MEAN")$conc` 实测范围 0–300），在 `.warn_conc_out_of_range()`（`R/mortality.R:863`）处被 join 丢掉。按范围逐格比对：**2,942,620 格落在范围外**（2,942,617 个填充格 + 3 个真实超范围格），留下 **1,737,380 格 = 输入网格的 37.12%**。两条告警互不指认：「有 294 万个负浓度」和「有 294 万个值落在查表范围外」说的是一件事，但没有一处说「这是填充值」。
- `validate = "off"`：一个字都不输出，网格同样从 468 万格变成 173.7 万格。

**数值影响（本例很小，机制不小）。** 把 LandScan 经 `.aggregate_pop()` 聚合到 netCDF 自己的 0.1° 格子上（26.6 s）：

| 量 | 值 |
|---|---|
| 全球人口 | 7,981,857,133 |
| 2,942,617 个填充格上的人口 | **2,739.663（0.000034%）** |
| 填充格中 `pop > 0` 的格数 | 3,676（最大 1,047.959） |

也就是说本数据里 `-999` 就是海洋，人口加权量几乎不受影响（2,739.663 会带小数，是因为 LandScan 的 1/120° 格子与 netCDF 格子相差约 3e-6°，`.aggregate_pop()` 的 resample 把计数按面积切开，总量守恒）。

**但机制本身会污染报告列。** 最小复现（表格路径，同一条聚合代码，不依赖 `validate-data/`）：4 个格、人口各 100、浓度 `c(5, 5, 5, -999)`：

```
clean  conc_pwe: 5.0000     fill  conc_pwe: -246.0000
clean  total   : 0.3663     fill  total   : 0.2748
```

`.domain_pwe()`（`R/uncertainty.R:126-137`）只按人口加权，**不过查表**，所以填充值直接进 `conc_pwe`——换成「区域掩膜外 `-999` + 全国人口」的输入，这一列就会被拉成负数。

**修复。** 摄取期报告（已落地，见第五节），不改数值、不改口径。

### 缺陷 2（本次新发现）：`bilinear` 把填充值摊成新的负值

**现象。** `align_to_target()` 对浓度一律 `method = "bilinear"`（`R/raster-io.R:349`）。填充值对 terra 来说是数不是 NA，于是像观测值一样被插值：一个 `-999` 与邻格的真实浓度按权重混合，得到 `-497.0`、`-244.75` 这类**源数据里不存在的取值**。

**最小复现（合成）。**

```r
src <- terra::rast(nrows = 3, ncols = 3, xmin = 0, xmax = 0.6, ymin = 0, ymax = 0.6)
terra::values(src) <- matrix(c(-999, 5, 10, 5, 10, 20, 10, 20, 30), nrow = 3)
tgt <- terra::rast(nrows = 3, ncols = 3, xmin = 0.1, xmax = 0.7, ymin = 0.1, ymax = 0.7)
round(terra::values(terra::resample(src, tgt, method = "bilinear")), 3)
#  -497.00     7.50      NaN
#  -244.75    11.25      NaN
#    11.25    20.00      NaN
```

**真实数据上的量级。** 海岸窗口 100–125°E / 0–25°N，62,500 格，其中 20,979 格是 `-999`（33.57%）：

| `target_res` | 负值格数 | 其中恰为 `-999` | 插值新造的负值 | 唯一负值个数 |
|---|---|---|---|---|
| 0.10° | 20,979 | 20,979 | 0 | 1 |
| 0.15° | 10,241 | 8,277 | **1,964** | **1,961** |
| 0.20° | 5,957 | 4,350 | 1,607 | 1,535 |
| 0.25° | 3,885 | 2,593 | 1,292 | 1,244 |

0.15° 下最常见的插值负值是 `-997.49`（4 格）、`-817.65`（3 格）。**这些格有人口**：负值格合计承载 3,745,932 人 = 该窗口人口的 **0.6592%**，其中 337 格 `pop > 0`——它们会在查表 join 处被静默丢掉。

同一次 0.15° 运行里，人口侧 `.aggregate_pop()` **会**报 “not an exact multiple … falling back to plain resampling”（因为 LandScan 的 0.008333° 不是 0.1497° 的整数倍），暴露侧一声不响。

**建议（未实现）。** 要么在重采样前把「可疑填充」当缺测处理（属数据契约，见第六节 Q1），要么在 `.report_raster_fill()` 的报告里补一句「对齐到别的分辨率会把填充值插值成新的取值」。后者是纯文案，留给后续。

### 缺陷 3：`dgt_coord` 过粗时栅格坐标键静默塌缩

**现象。** 表格路径有这道检查，栅格路径没有。

- 表格路径：`.normalise_coord_keys()`（`R/ingest.R:69-102`）渲染后比对唯一键数，退化时告警并**保留数值列**。实测 `x = 100.005 + 0.01k` 十个值、`dgt_coord = 2`：
  `[warning] Coordinate column 'x' needs more decimals than 'dgt_coord = 2' to stay unique; keeping it numeric.` → 10/10 键保留。
- 栅格路径：`raster_to_grid()` 直接把格心渲染成字符（改动前 `R/raster-io.R:78-79`）。随后 `.ingest_and_map()` 还是会调 `.normalise_coord_keys()`，但它见到的是**字符列**，`if (!is.numeric(v)) next` 直接跳过（`R/ingest.R:87-89`）——唯一一次机会被跳过。

**实测（栅格路径）：**

| 输入 | 结果 |
|---|---|
| 0.001° 4×4 栅格 + `dgt = 2` | 16 行 → **1 个**不同键；`mortality()` 返回 1 行，`ncd+lri_25` 是 **list 列**（tidyr 报 “not uniquely identified; output will contain list-cols”），`sum()` 抛 `invalid 'type' (list) of argument` |
| 同上 + `dgt_coord = 4` | 16 行，`ncd+lri_25` 合计 0.490052 |
| 0.01°（约 1.1 km）100×100 + 默认 `dgt_coord = 2` | 10,000 行 → **5,037 个键**（丢 4,963 格 = 49.6%） |
| 0.01° 200×200 + `dgt = 2` | 40,000 → 19,865 |
| 0.01° 10×10 + `dgt = 2` | 100 → 81 |
| 0.01° 三种尺寸 + `dgt = 3` | 键数与行数一致 |

0.01° 是常见分辨率，默认设置直接丢一半格子，而症状不是报错，是「总数不对」或「结果是 list 列」。

**修复。** 已落地（第五节第 1 条）。

### 缺陷 4：表格曝光 + 栅格人口时，边界被栅格化到人口的格子上

**最小复现。** 暴露是一个坐标表（格心 `0.05 + 0.1k`），人口是 0.1° 栅格但 extent 平移半格（格心 `0.1 + 0.1k`），`calc_fild = NULL`：

```
暴露表键样例 : 0.05, 0.15, 0.25, 0.35
人口栅格键   : 0.1, 0.2, 0.3, 0.4
共享键       : 0
[ERROR] `admin` labelled no cell of the analysis grid (grid resolution 0.1 x 0.1 deg):
        the domain column is missing or NA everywhere, so there is nothing to join.
        The boundaries have to overlap the grid the analysis runs on.
```

`.map_input_columns()` 用曝光自己的坐标做骨架（`R/prepare-inputs.R:203`），`spatial$template` 却来自人口栅格（`R/ingest.R:254-256`），`.attach_admin()` 用这个 template 栅格化边界（`R/ingest.R:309`）→ 标签落在 0.1/0.2 的格上 → 与骨架 0 键相交。**报错是真的，但它指的对象是错的**：问题不在边界，在「曝光表与人口栅格的格心相差半格」。

`.check_grid_match()` 覆盖不到这一路：它的条件是 `own_skeleton && (conc_raster || pop_raster)`（`R/prepare-inputs.R:563`），而这里的骨架派生自表格曝光，`own_skeleton = FALSE`。键对齐时（人口栅格 ext 0..1）同一条路跑通：100 行，合计 9.158521。

**建议（未实现）。** 把步骤 4 的触发条件从「用户自供骨架」放宽到「骨架不是由栅格产生」（即 `own_skeleton || !conc_raster`）：这样 `calc_fild` 与栅格网格 0 键相交时会得到 `.check_grid_match()` 那句准确的 “shares no coordinate key with the raster grid”，部分相交时得到告警而不是静默丢格。改动只有一行，但落在 `R/prepare-inputs.R` 与 `R/ingest.R` 的边界上，且会影响 `decompose()` 的第二组，故只给建议、留给 Lead 分派。

## 四、本次数据特有的性质（不是缺陷）

1. **两张真实栅格的键完全一致**（第二节事实 3）。原因是模板由 netCDF 自己的 extent 造出：`terra::rast(ext(nc_w), resolution = res(nc_w))` 的 ext 与 `nc_w` 逐位相同。
2. **填充格几乎没有人**：0.000034% 的全球人口落在 2,942,617 个填充格上（0.1° 原生分辨率）。本数据里 `-999` 就是海洋，所以缺陷 1 的数值后果极小；它在「陆地掩膜 + 全国人口」这类输入上才会像第三节的最小复现那样把 `conc_pwe` 拉成负数。
3. **栅格 × 栅格相差半格：键不散，值被摊平。** 曝光 0.1° ext 0..2 与人口 0.1° ext 0.05..2.05：

   | 量 | 结果 |
   |---|---|
   | 共享键 | 400 / 400（不报「不同网格」） |
   | 人口总量 | `.aggregate_pop()` 报 “Aggregating the population raster changed the total by 4.9375% (40,000 -> 38,025)” |
   | 人口取值范围 | 源的唯一值 `{100}` → 目标 `{25, 50, 100}` |

   每个目标格取到 4 个相邻源格的均值：**总量变化报了警，空间摊平没有**。总守恒不等于分布正确，而没有任何一处说「两张栅格的格心相差半格」。这不是键错位，是「部分可见」。

### 判定：什么情况下会静默错位

- **不会错位**：两张栅格之间。模板永远取自第一张栅格的 extent（`align_to_target()` 的 `target_raster`，或 `raster_list[[1]]` 加 `target_res`），其余输入一律重采样/聚合到它上面，键由模板唯一产生。偏移表现为**值被摊平 + 总量变化告警**，不表现为键错位。
- **会错位**（都属「骨架不由栅格产生」）：
  1. `dgt_coord` 过粗（缺陷 3），丢格且症状远离原因；
  2. 表格曝光或表格 `calc_fild` 与栅格网格的格心相差半个格（缺陷 4），或部分相交——0 命中会报错（消息可能指错对象），部分命中在 `own_skeleton = FALSE` 时**没有任何检查**。

## 五、已落地的修复（只做加法）

| 文件 | 改动 | 是否改变数值 |
|---|---|---|
| `R/raster-io.R` | `raster_to_grid()` 的坐标渲染移入新的 `.render_cell_keys()`：键塌缩时告警，报出塌缩前后的格数/键数、每轴的「格心数 → 键数」、保住网格所需的 `dgt_coord`。不丢行、不改值 | 否 |
| `R/raster-io.R` | 新增 `.min_key_digits()`（算所需位数）与 `.report_raster_fill()`（数负值并点名最常见取值），后者返回计数供测试断言 | 否 |
| `R/prepare-inputs.R` | `.prepare_inputs()` 新增 2b 步：计算前对栅格来源的 `conc_real` / `pop_total` / `conc_cf` 调用 `.report_raster_fill()`；`validate = "off"` 时静默，守住「off 即无输出」的既有契约。`.INPUT_ROUTES` 相应加两行 | 否 |
| `tests/testthat/test-validate-ingest.R` | 25 条断言，含「填充值仍原样留在表里」的钉子（将来若静默清洗，这条会失败并迫使重新拍板） | 否 |
| `NEWS.md` | 追加一段 | 否 |

真实 netCDF 上跑出来的新告警（复跑命令见第七节）：

```
`conc_real`: 2,942,617 of 4,680,000 raster value(s) are negative (most frequent:
-999 x 2,942,617). A raster reader maps a declared missing-value flag to NA, so
these were not declared missing: they are data errors or an undeclared
fill/no-data sentinel. Nothing is dropped, rescaled or converted to NA here, and
the values enter the analysis as they are. If this is a fill code, declare it in
the file (`_FillValue` / `missing_value` / `NAflag`) or set it to NA before
running: the package does not clean sentinels for you.
```

0.01° 近失上的新告警：

```
Rounding cell centres to `dgt = 2` decimal place(s) merges raster cells on a 0.01
x 0.01 deg grid: 10,000 cell(s) collapse into 5,037 coordinate key(s) (x: 100
centre(s) -> 69 key(s); y: 100 centre(s) -> 73 key(s)). The analysis grid would
lose 4,963 cell(s) and the value table would fan out on the duplicated key, which
surfaces as a wrong total or a list-column result rather than as an error here.
Set `dgt_coord = 3` to keep this grid apart.
```

**未覆盖的地方（如实说明）：** `build_grid_info()` 直接调 `.align_raster_inputs()`，不经过 `.prepare_inputs()`，所以它的产物没有填充值报告；`validate = "off"` 下也不会出现（这是契约要求）。

## 六、需用户拍板（未实现）

| # | 事项 | 现状 | 备选与代价 |
|---|---|---|---|
| Q1 | 填充值清洗 | 只报告，值原样进管线（`-999` 在查表 join 处被丢） | A. 保持只报告（本次落地）；B. 把非物理值（`conc < 0`，或 `conc <= 0`）一律置 NA——改变分析网格与所有总量；C. 加 `na_value=` 参数由用户显式指定哨兵（改公开 API） |
| Q2 | `validate = "off"` 是否也该报填充值 | 静默（守既有契约） | A. 保持静默；B. 例外地在 off 下也报一次（破坏「off 即无输出」契约） |
| Q3 | 负浓度是告警还是阻断 | `warn` 继续、`stop` 阻断 | A. 保持；B. 无论 `validate` 取值一律阻断（会让只覆盖陆地的正常产品无法运行） |
| Q4 | 对齐把填充值插值成新负值 | 无任何提示 | A. 在报告里补一句；B. 对齐前先把可疑填充当缺测（同 Q1-B） |
| Q5 | 两张栅格格心相差半格时的空间摊平 | 只报总量变化 | A. 保持；B. 额外报「格心不对齐」 |
| Q6 | `conc_pwe` 是否排除查表范围外的浓度 | 只按人口加权，填充值直接进这一列 | A. 保持；B. 只对落在 CRF 查询范围内的格做人口加权（改变报告列口径） |

## 七、可复跑命令

```powershell
$R = 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe'
$T = 'C:\Users\Evan\AppData\Local\Temp\attrmort-recon'

# 1) 真实文件的元数据、-999 计数、模板与坐标键（第二节事实 1/3、第四节性质 1）
& $R "$T\recon-01-facts.R"

# 2) 摄取层行为：raster_to_grid / validate / 坐标键 / 半格错位 / conc_pwe（第三节缺陷 1）
& $R "$T\recon-02-ingest.R"

# 3) 窗口数字与 dgt 塌缩端到端（第三节缺陷 3）
& $R "$T\recon-03-numbers.R"

# 4) 全球填充格人口、海岸窗插值污染（第三节缺陷 1/2）
& $R "$T\recon-04-global.R"

# 5) 0.01 度近失 + 0.1 度原生分辨率的填充格人口（第三节缺陷 1/3）
& $R "$T\recon-05-nearmiss-global.R"

# 6) 半格错位的三种组合（第三节缺陷 4、第四节性质 3）
& $R "$T\recon-06-offset.R"

# 7) 新代码的行为（第五节的告警原文）
& $R "$T\smoke-01.R"

# 8) 本次改动的验收
& $R -e "devtools::test(filter = 'validate-ingest')"
$env:ATTRMORT_FINGERPRINTS = '1'
& $R -e "devtools::test(filter = 'fingerprints')"
& $R -e "devtools::test()"
```

### 本次验收的原始结果

| 门槛 | 命令 | 结果 |
|---|---|---|
| 新测试文件 | `devtools::test(filter = "validate-ingest")` | FAIL 0 / WARN 0 / SKIP 0 / PASS 25，1.6 s |
| 指纹不漂移 | `ATTRMORT_FINGERPRINTS=1 devtools::test(filter = "fingerprints")` | FAIL 0 / WARN 0 / SKIP 0 / PASS 42，13.5 s |
| 全量测试 | `devtools::test()`（同一进程内也跑了指纹，同样 42 条全过） | FAIL 0 / WARN 0 / SKIP 0 / PASS 980，140.3 s |

三次运行都在同一棵工作区上（含其他线当时未提交的改动）；本次提交只含第五节表格里的 5 个文件。

## 八、证据索引

| 结论 | 证据位置 |
|---|---|
| 只按 NA 丢格 | `R/raster-io.R:60-75`（`n_na` 判定与 `filter(grid, n_na == 0)`） |
| 键在摄取期渲染 | `R/raster-io.R:77-84`（本次改为调用 `.render_cell_keys()`） |
| 表格路径的唯一性检查（栅格路径到不了） | `R/ingest.R:69-102`，跳过点在 `R/ingest.R:87-89` |
| 浓度重采样用 bilinear | `R/raster-io.R:349` |
| 人口聚合与守恒核对 | `R/raster-io.R:228-275` |
| 负浓度阻断 | `R/schema-detect.R:376-382` |
| 查表范围外观测被丢 | `R/mortality.R:863-889` |
| `conc_pwe` 只按人口加权 | `R/uncertainty.R:126-137` |
| 骨架由表格曝光坐标产生 | `R/prepare-inputs.R:187-206`（`calc_fild <- conc_real[...] \|> distinct()` 在 `:203`） |
| 网格一致性检查及其触发条件 | `R/prepare-inputs.R:83-120`、`R/prepare-inputs.R:563` |
| 边界栅格化用的是 `spatial$template` | `R/prepare-inputs.R:578`、`R/ingest.R:309` |
| 浓度渲染成字符键（校验期再还原） | `R/prepare-inputs.R:378` |
| 本次修复 | `R/raster-io.R:77-84`、`R/raster-io.R:89-231`（`.min_key_digits()` `:93`、`.render_cell_keys()` `:121`、`.report_raster_fill()` `:178`）、`R/prepare-inputs.R:18-20`、`:46`、`:57`、`:534-544` |
| 本次测试 | `tests/testthat/test-validate-ingest.R`（25 条） |
