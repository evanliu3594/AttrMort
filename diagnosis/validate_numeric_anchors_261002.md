# 真实数据数值锚点校验（T3）

> 本文件是 T3 线的交付报告，只增不改。结论性证据全部来自包外脚本的实测输出，脚本与原始日志在
> `%TEMP%\attrmort-recon\t3\`（本次会话为 `C:\Users\Evan\AppData\Local\Temp\dsh-0I9Gc1\attrmort-recon\t3\`）。
> 口径依据：仓库根 `AGENTS.md` 第四节、`R/AGENTS.md` 第三/四节。

## 〇、结论先行

把**裁剪后的原分辨率** LandScan 直接交给 `pop_total=`，本包在真实数据上的**算术是对的**：

| 断言 | 实测 | 判定 |
|---|---|---|
| 人口守恒（LAO） | 90,758,858 → 90,758,837.39，相对差 −2.27e-7 | 守恒 |
| 人口守恒（ROU） | 35,251,129 → 35,251,112.16，相对差 −4.78e-7 | 守恒 |
| 包外手算 vs `mortality()`（LAO，2155 格 × 75 层） | 逐格最大绝对偏差 3.80e-4 例，逐列最大相对总量偏差 1.23e-6 | 一致 |
| 包外手算 vs `mortality()`（ROU，2917 格 × 75 层） | 逐格最大绝对偏差 2.00e-3 例，逐列最大相对总量偏差 5.27e-6 | 一致 |
| 每 10 万只除一次 | 网格基线死亡 / GBD 基线死亡 = 1.002198（ROU）、1.238966（LAO），与人口比逐位相同 | 正确 |
| 域级中心估计 = 网格求和 | 随包示例上 3 个域逐列相等（容差 1e-12） | 正确 |

真正的问题不在算术，在**输入与报告层**：`scenario = NULL`（默认）时死亡率表的多余列会静默进入宽表，
把结果撑成大面积 NA（§七 F1，Blocker 级，属 T2 写域）。其次是三条报告级问题（§七 F2–F4）。

## 一、环境、切片与复跑

- R 4.6.1（ucrt）/ terra 1.9-50 / sf 1.1-3 / dplyr 1.2.1。
- 数值取数时的仓库基线 `9e85713`；最小复现复核于 `b062e88`（T1/T2 的改动都复核过，两条复现均仍在）。
- 主切片 **ROU（Romania）** 20.0–30.0E / 43.0–48.6N；次切片 **LAO** 100.0–107.7E / 13.9–22.6N。
  取舍：ROU 与 Lead 的 LAO 独立（不同洲、人口约 4 倍、窗口内含未声明的 `-999` 填充值 37 格、含黑海无值格），
  LAO 用来逐位复现 Lead 的既有基线（90,758,858）。
- 两个 bbox 的角点都落在曝光栅格的 0.1 度格线上，裁剪后一格曝光格 = 12 × 12 个 LandScan 格
  （`abs(res_t / res_r - 12)` = 2.03e-7 / 2.11e-7，落在包内 1e-6 的整数判定内）。
- 脚本（全部包外，自包含，用 `Sys.getenv("TEMP")` 定路径）：

| 脚本 | 作用 |
|---|---|
| `step0_common.R` | 公共前置：切片定义、GBD 读取与列映射、栅格窗口、键渲染 |
| `step1_conservation.R` | 核对 1：人口守恒三步对账 + 键契约 + GBD 人口对照 |
| `step1b_followup.R` / `step1c_followup2.R` | 栅格格数账目、CRS 字符串比较、Lead harness 陷阱逐步复现 |
| `step2_gridinfo.R` / `step13_gridmatch.R` | 核对 2：`build_grid_info()` 产物与交回、三条网格一致性分支 |
| `step3_runs.R` | 两个切片的 `mortality(5COD)` 逐格结果 |
| `step4_handcalc.R` | 核对 3/4/5：包外手算 + PAF 量级 + 单位与年龄 |
| `step5_paf.R` / `08_tmrel.R` | RR 曲线取值、TMREL 平坦区、PWRR 隐含 PAF |
| `step9_closing.R` / `step10_minrepro.R` / `step11_extracols.R` / `step12_rawgbd.R` | 最小复现（填充值、多余列泄漏、端点列不一致） |
| `step2b_endpoint_col.R` | `endpoint` / `cause` 两列并存时的列选择路线 |

## 二、核对 1：人口守恒

外部锚点：LandScan 窗口的合计用**基 R** `sum(terra::values())` 算，并与 `terra::global()` 对账（差 0）。

| 量 | ROU | LAO |
|---|---|---|
| 曝光窗口（行 × 列） | 56 × 100 | 87 × 77 |
| 人口窗口（30 arc-sec 原生，行 × 列） | 672 × 1200 | 1044 × 924 |
| `res_t / res_r` | 11.999999796973 / 11.999999789042 | 同 |
| **A0 原始窗口合计**（基 R = terra） | **35,251,129** | **90,758,858** |
| 包内 `.align_raster_inputs()` 的 `pop_total` 合计 | 35,251,112.156829 | 90,758,837.394688 |
| A1 − A0 绝对 / 相对 | −16.84 / **−4.78e-7** | −20.61 / **−2.27e-7** |
| 单独 `terra::aggregate(fact = 12)` 后合计 | 35,251,129（**精确守恒**） | 90,758,858（**精确守恒**） |
| 单独 `terra::resample(method = "sum")` 到模板后 | 35,251,112.156829 | 90,758,837.394688 |
| 包内 0.001 损耗告警 | 未触发 | 未触发 |

**判定**：守恒。全部损耗发生在 `resample(method = "sum")` 一步，`aggregate()` 精确守恒。
损耗的物理来源是两个全球栅格的**原点相差约 3e-7 度**（LandScan 以 -180/-90 起算，曝光 netCDF 以
-179.999996947 起算），这级偏移下 terra 的 `sum` 重采样在窗口边缘不是严格保守的。相对量级 1e-7，
远低于包内告警阈值 1e-3。

LAO 的 90,758,837 与 Lead 复核的基线**逐位一致**。

### 2.1 栅格格数账目（顺带发现，见 F4）

- 包内 `pop_total` 表行数：ROU 5369 / LAO 6248；模板格数 5600 / 6699。
- 差额 231 / 451 是**值为 NA 的格**：`raster_to_grid()` 末尾的 `filter(n_na == 0)` 对单波段栅格同样生效
  （`R/raster-io.R:75`），把 NA 格整行丢掉。对人口是丢掉总量（本例那 231/451 格本就无人口），
  对浓度是**缩小分析网格**（ROU 有 37 格 `-999` 被掩成 NA，5600 → 5563）。

### 2.2 坐标键契约（附带验证）

我的 `sprintf("%.2f")` 渲染与包内 `matchable()`（`as.character(round(x, 2))`）在同样的栅格上：
包独有键 **0** 个，我独有的恰好是上面那 231 / 451 个 NA 格。键渲染一致。

### 2.3 与 GBD 2021 人口对账（只做量级，不做等式）

| | 网格域内人口（LandScan 2023） | GBD 2021 全国 | 相对差 |
|---|---|---|---|
| ROU | 19,305,603 | 18,938,555 | **+1.9%** |
| LAO | 8,896,919 | 7,377,552 | **+20.6%** |

ROU 同量级。LAO 差 20.6%，**超出年份差能解释的范围**（老挝 2021→2023 年增长约 1.4%/年）。
LandScan 是环境人口分布产品（含昼夜再分配与建筑区权重），GBD 人口来自 WPP；两者在低收入国家差异更大。
**登记为数据源口径差，不是包缺陷**：跨源对账时不要把两者当等式，也不要据此判断包算错。

### 2.4 harness 陷阱的逐步复现（LAO）

Lead 报的 89,768,019 完全复现，但**定位与「包内路径」无关**：

| 步骤 | 合计 |
|---|---|
| harness 的 `floor()` 窗口对齐算术 | `x0 = 99.899999989`（比曝光窗口西移 **0.0999983 度**，即整一格），`y0 = 13.800000003` |
| harness 窗口合计（含邻国人口） | 94,407,343 |
| harness 自己 `aggregate(fact = 12)` | 94,407,343（守恒） |
| harness 自己 `resample(r_pop_c, tpl, method = "sum")` | **89,768,019**，−4.914% |
| 把这幅已预聚合栅格交给包 | `fact = res(template)/res(source) = 1.0000000000` → 不再聚合，直接重采样，**总量不变** |

即：**−4.914%（相对正确窗口 −1.09%）全部来自 harness 自己的窗口错位 + 自己那一次 resample**；
包内路径只差 −2.27e-7。用一个**对齐**窗口预聚合再交包，结果与不预聚合完全相同（我实测 A3 = A1）。

**但这里暴露一条真实边界**：只要交给包的栅格格边与曝光网格差一个整格，`resample(method = "sum")`
就会丢掉边缘一整列/行（约 5%）。此时包内 `.aggregate_pop()` 的 `lost > 0.001` 判断**会发告警**
（`R/raster-io.R:127-136`）——本例告警发生在包外，所以用户看不到。建议文档里明确：
`pop_total` 交**原生分辨率**栅格，不要自己先聚合。

## 三、核对 2：网格口径与域标签

### 3.1 `build_grid_info()` 的产物

| 量 | ROU | LAO |
|---|---|---|
| `n_cells`（行数） | 5563 | 6699 |
| `ncell(conc_real)` | 5600 | 6699 |
| `ext` 与栅格一致（≤1e-9） | 是 | 是 |
| `res` 属性 | 0.099999998271 | 0.099999998271 |
| 栅格分轴 `res` | 0.099999998304 / 0.099999998238 | 同 |
| `crs` | 与栅格一致 | 一致 |
| `.rds` 往返行数 / 属性保留 | 5563，保留 | 6699，保留 |

- ROU 的 `n_cells` = 5563 < 5600：曝光里 37 格 `-999` 被掩成 NA，`raster_to_grid()` 直接丢格，
  网格随之缩小。**这是正确行为**（无效曝光格不是分析格），但要注意 `ext` / `res` 描述的仍是整幅栅格。
- `res` 属性 0.099999998271 是两轴 0.099999998304 与 0.099999998238 的**均值**，来自 `.as_res()`
  的 0.1% 折叠（`R/utils.R:286-293`）。该属性只用于显示与消息，**不参与任何重采样**（网格本体是栅格自己的
  几何），因此与 `AGENTS.md` “非方形栅格不得取均值重采样”不冲突；但报告值与栅格本体不同，容易被误读。

### 3.2 交回 `calc_fild = <info>`（LAO，6699 格）

| 用例 | 结果 |
|---|---|
| 原样交回 | **接受**，2155 行，无网格一致性消息（全部键命中） |
| 整表平移 +40 度（0 键命中） | **报错**：`` `calc_fild` shares no coordinate key with the raster grid: 0 of 6699 coordinate key(s) match a raster cell `` |
| 半数行平移（部分命中） | **告警**：`` `calc_fild` is not on the raster grid: 3350 of 6699 coordinate key(s) match no raster cell ``，继续算，1077 行 |
| 同上 + `validate = "off"` | 无任何消息，仍算 1077 行 |

三条分支与文档一致。**给后续做用例的人一个坑**：`x + 5` 这类平移会把窗口西半平移到东半上、半数键仍然命中，
看起来像“部分命中”；要构造 0 键用例必须平移到完全不重叠的区域（如 `x + 40`）。

### 3.3 Lead 的问题：第 2 个域标签是什么

**答案：是 `NA`。**

`table(info$iso_a3, useNA = "ifany")`：

| | 有标签 | NA |
|---|---|---|
| ROU | `ROU: 2917` | `NA: 2646` |
| LAO | `LAO: 2155` | `NA: 4544` |

`.grain_message()`（`R/mortality.R:121-140`）用 `length(unique(calc_fild[[dcol]]))`，**不丢 NA**，
于是 NA 被数成一个域，输出 “2 domain(s)”。

- **数值影响：零。** 核心里 `drop_na()`（`R/mortality.R:942`）把 NA 域的格全丢掉；结果行数恰好等于
  有标签的格数（ROU 2917、LAO 2155），逐列总量与只喂国界内格完全一致。
- **影响面**：只圈一个国家的用户会看到 “2 domain(s)”，容易误判有第二个域参与；另外 2646 / 4544 格
  仍进入 join 后被丢弃，是纯浪费（性能面属 T4）。
- **建议（只做加法）**：`.grain_message()` 里对域列 `unique()` 时丢掉 NA，或在域数后用括号补一句
  “另有 N 格无域标签”。

### 3.4 域的归属法则是 touches，不是格心

包用 `terra::rasterize(..., touches = TRUE)`（`R/raster-io.R:285-289`）给格贴标签，即
**格方块与多边形相交**就算在内。我用两条独立几何路线对账：

| | 格心在多边形内（严格） | 格方块相交（对应 touches） | 包 |
|---|---|---|---|
| ROU | 2768 | 2918 | 2917 |
| LAO | 1961 | 2155 | 2155 |

LAO 完全一致；ROU 差 1 格（sf 与 terra 在多边形-格边界上的浮点判定差）。**被 touches 纳入而严格法排除的
边缘格：LAO 194 格（占域内 9.0%）、ROU 150 格（5.1%）**。这会把边缘格的人口/死亡计入国家
（ROU：多算 1 格 = +1.93 例死亡）。这是口径选择不是缺陷，但**建议在 `admin=` 文档里写明**：
`location` 的法则等于 `touches = TRUE`，不是格心包含。

## 四、核对 3：包外手算对账（核心锚点）

**独立实现**（除查表外不碰包内任何中间量）：

1. **人口**：用 `terra::rowColFromCell()` 取权威行列索引，基 R `tapply()` 做 12 × 12 块和；
   另用 `terra::crop()` 在 49 个抽样格上三方对账（含四个角、边缘格、全 NA 格），**`|Δ| = 0`**。
   每一格的细格数都是 144（5600 × 144 = 806,400 = 细栅格格数），无遗漏无重复。
2. **浓度**：直接读裁剪后的窗口像元，自己做 2 位键。
3. **域标签**：`sf` 点入多边形与格方块相交两条路线（见 §3.4）。
4. **join**：基 R `merge()`，不比包内多一步。
5. **公式**：照 `AGENTS.md` 第四节写死 —— `M = pop × prop × mortrate / 1e5`；
   `PWRR = weighted.mean(RR(conc_real), pop)`；`attr = M × (RR(conc_cf) − 1) / PWRR`。
6. **RR**：只从 `rr_std("5COD", "MEAN")` 取查表（这是查表不是自证），join 自己做。

结果（只比对**双方都判定在域内**的格）：

| | ROU | LAO |
|---|---|---|
| 共同格数 | 2917 | 2155 |
| 比对列数（端点 × 年龄） | 75 | 75 |
| 逐格最大绝对偏差 | **2.00e-3**（`ihd_80`，该列总量 1740.79） | **3.80e-4**（`lri_80`，总量 432.81） |
| 逐列最大相对总量偏差 | **5.27e-6**（`lri_35`） | **1.23e-6**（`ihd_25`） |
| 我的手算总量 | 18,607.906337 | 8,903.028993 |
| 包的总量 | 18,607.852794 | 8,903.039282 |

**残差来源已定位**：唯一有差异的输入是人口栅格。

| | ROU | LAO |
|---|---|---|
| 浓度逐格 `max|Δ|` | **0**（5563 格） | **0**（6699 格） |
| 人口逐格 `max|Δ|` | 19.06 人 | 38.63 人 |
| 人口总量（我 = 精确块和） | 35,251,129 | 90,758,858 |
| 人口总量（包 = aggregate + resample） | 35,251,111.02 | 90,758,814.73 |

即：**公式本身逐格精确一致，残差全部来自 `resample` 在 1e-7 度网格偏移下的边缘再分配**
（包侧总量相对差 5.1e-7，经 PWRR 的加权部分抵消后放大到 5.3e-6）。这属于固有精度，不是实现错误。

## 五、核对 4：量级合理性（量级检查，不是锚点）

| | ROU | LAO |
|---|---|---|
| 域内人口 | 19,305,603 | 8,896,919 |
| 曝光 min / mean / max（未加权） | 5.88 / 11.86 / 17.70 | 15.83 / 30.04 / 42.62 |
| 曝光的**人口加权**均值 | **12.83** | **31.89** |
| 归因死亡（5COD，CRF 年龄层，2019） | **18,607.85** | **8,903.04** |
| GBD 同五因、同年龄层死亡（2019） | 141,263.2 | 21,165.6 |
| **PAF（CRF 年龄层）** | **13.17%** | **42.06%** |
| PAF（全部年龄） | 13.13% | 37.67% |
| 隐含 `PWRR = 1/(1 − PAF)` | 1.152 | 1.726 |

**算术自洽性是恒等式，不是巧合**：PWRR 分支下每个 (域, 端点, 年龄) 层的 PAF 恒等于 `1 − 1/PWRR`
（因为 `Σ_cell M_cell (RR_cell − 1)/PWRR = M_total (PWRR − 1)/PWRR`）。逐层 PWRR 隐含 PAF
（age 60）：

| 端点 | ROU | LAO |
|---|---|---|
| copd | 0.126 | 0.259 |
| ihd | 0.234 | 0.392 |
| lc | 0.137 | 0.289 |
| lri | 0.241 | 0.515 |
| stroke | 0.105 | 0.250 |

按基线死亡份额加权的端点构成：ROU `ihd 57.0% / stroke 19.6% / lri 11.1% / lc 7.9% / copd 4.5%`；
LAO `lri 38.6% / ihd 26.1% / stroke 25.8% / copd 6.3% / lc 3.3%`。与两国 GBD 死因结构相符。

**曲线本身的口径（正面确认）**：`rr_std("5COD")` 的 RR 在 conc ≤ 2.4 处恒为 1，从 2.5 起上升
（age 60 的 ihd：0/5/10/20/30/40 µg/m³ → 1.000/1.118/1.249/1.438/1.611/1.785）。
即这张表是**相对 TMREL ≈ 2.5 µg/m³** 的曲线，与 GEMM 的口径一致；`conc_cf` 缺省回填 `conc_real` 时，
反事实就是 TMREL 水平，这是正确用法。

**判定**：
- 内部自洽、跨切片方向正确（LAO/ROU 的 PWRR 比 1.50，曝光比 2.49；RR 是凸函数，PAF 对曝光的超线性响应方向对）。
- **但 42% 的绝对水平偏高**，属于高端。这是"曲线在 32 µg/m³ 处就是这个 RR"的直接后果，
  **不是本包算错**；要动只能动查表数据（`data/` 不在本次任何人的写域）。
- **本次没有拿到可引用的逐国 PAF 外部数值**（PubMed / ScienceDirect 抓取被拦，见 §八），
  所以这一项只做到"内部自洽 + 跨切片一致 + 全球量级参照"，**明确标注为量级检查而不是锚点**。

## 六、核对 5：单位与年龄口径

### 6.1 每 10 万只除一次 —— 两条独立证据

**(a) 闭式锚点**（固化进 `tests/testthat/test-validate-numeric.R`）：两格、1 个年龄层、5 个端点，
`pop = 1e5`、`prop = 0.5`、`mortrate = 200`，手算基线死亡 = `1e5 × 0.5 × 200 / 1e5 = 100` 例/格。
实测与 `100 × (RR − 1)/PWRR` 逐格相等（容差 1e-12）。**若多除一次 1e5 会得到 1e-3 而不是 36。**

**(b) 真实数据的单位闭环**：用网格自身重建基线死亡（`Σ_cell pop × prop_age × mortrate/1e5`），
与 GBD 自己的基线死亡（`GBD人口 × mortrate/1e5`）比：

| | 网格基线死亡 | GBD 基线死亡 | 比值 | 人口比（LandScan域内 / GBD） |
|---|---|---|---|---|
| ROU | 141,573.7 | 141,263.2 | **1.002198** | 19,305,603 / 19,263,265 = **1.002196** |
| LAO | 26,223.47 | 21,165.61 | **1.238966** | 8,896,919 / 7,180,921 = **1.238966** |

两个切片的比值**与人口比逐位相同**（5 位有效数字）。这同时证明了：单位换算只做了一次、
`prop` 按域正确广播、年龄层没有重复计数。

### 6.2 prop 与年龄层

- `age_struc` 的 20 层 `sum(prop) = 1.000000`；`_slice_age()` 的按域重归一在本例是恒等变换。
- 参与计算的 15 层合计：ROU **0.7359**、LAO **0.4893**。
- GBD 20 个年龄层 → CRF（5COD）15 层（25…95），**被丢弃的是 0、5、10、15、20 五层**：

| | 丢弃人口占全国 | 丢弃的 GBD 死亡（同五因） | 占五因全部死亡 |
|---|---|---|---|
| ROU | **26.41%** | 484.08 | 0.34% |
| LAO | **51.07%** | 2,467.96 | 10.44% |

- **包内没有任何消息提到这五层**。实测（`step9_closing.R` §4）：喂进 20 层的 `mort_rate` 与 `age_struc`
  跑 GEMM，结果只有 `ncd+lri_25 … ncd+lri_95` 共 15 列，消息里只有 `Analysis grain` 一行。
  `validate_mortality_input()` 的年龄检查是拿**标准 20 层**比（`"age_struc: 19 standard age group(s) absent"`），
  不检查"表里有、CRF 没有"的那些层。所以用户拿到的是一个**只覆盖 15 层、且没有告知**的结果。
  （T2 已在本轮加了"非标准 5 岁层"的告警，但那检查的是*不标准*的标签，不是*标准但 CRF 没有*的标签。）

## 七、发现清单

分级：**Blocker**（会产生错结果且无提示）/ **Must-fix**（契约或报告错误）/ **Info**（口径、可读性、性能）。

### F1 [Blocker，T2 写域] `scenario = NULL` 时死亡率表的多余列静默进入宽表，把结果撑成大面积 NA

**最小复现**（`step12_rawgbd.R`，91 行 × 11 列的 GBD 形状表）：

```r
mortality(crf = "5COD", calc_fild = fld, conc_real = conc, pop_total = pop,
          age_struc = age_tab, mort_rate = raw_gbd_shaped_table,
          mort_lvl = "location", validate = "warn")
```

实测：

| 输入 | 结果 | 值列 NA 数 |
|---|---|---|
| 只留 4 个规范列 | 2 行 × 8 列 | 0 / 50 |
| 原始 11 列（含 `upper`/`lower`/`year`/`cause_name`/…） | **10 行 × 15 列** | **40 / 50** |

结果列变成 `x, y, location, upper, lower, metric_name, sex_name, year, cause_name,
measure_name, copd_60, …, stroke_60` —— 多余的列全部成了宽表的 id 列。用户对结果 `sum()` 得到 `NA`，
而**没有任何 error 或 warning**。

**机理**：`scenario = NULL` 时 `.extract_scenario()` 走 `canon()` 分支，**不调用 `.slice_mort()`**
（`R/prepare-inputs.R:284-328`），表里所有非键列都进了 `.attributable_by_domain()` 的 join，
再被 `.widen_mort()` 当成 id 列。

**两个变体**（`step11_extracols.R`）：

| 多余列 | 结果 |
|---|---|
| 常量列（`note`、`metric_name`、`year`，每行同值） | 行数正确，只是结果多出这些列（污染输出契约） |
| 随端点变化的列（`cause`） | 2 格 → **10 行**，值列 40/50 为 NA，`sum()` = NA |

**影响面**：`scenario = NULL` 是默认与最常见调用。真实 GBD CSV 有 18 列，用户按 location/cause 过滤后
直接传 `mort_rate=` 就会踩中；这也解释了 Lead 早先看到的
`invalid 'type' (list) of argument` 崩溃（同类扇出 + 重复键叠加）。本轮我自己的 harness 预先只取了
4 列，所以 §二～§六 的数值未被污染。

**建议**：`scenario = NULL` 时也把 `mort_rate`/`age_struc` 收敛到规范列（等价于 `.slice_mort()` 的
`select()`），或对多余列显式报错/告警。任何修复都不应改变 4 列输入下的数值。

### F2 [Must-fix，T2 写域] `validate_mortality_input()` 读 `cause`，计算核读 `endpoint`

`R/schema-detect.R:283` 取 `intersect(c("cause", "endpoint"), mort_cols)[1]` —— 有 `cause` 就用 `cause`；
而计算一路用字面 `endpoint`（`R/mortality.R:861` 的 `.standardize_join_keys()`）。两列并存时，
校验报告描述的是**计算不会用的那一列**。

**最小复现**（`step10_minrepro.R` A）：`mort_rate` 同时带 `endpoint = c("copd","ihd",…)` 与
`cause = c("Chronic obstructive pulmonary disease", …)`：

- 结果列正确使用了端点短码：`copd_60, ihd_60, lc_60, lri_60, stroke_60`
- 但消息说：`mort_rate: 4 of the 5 endpoint(s) the model '5COD' needs are absent from 'cause'
  (copd, ihd, lc, lri); those strata cannot be computed. 'cause' holds: Chronic obstructive
  pulmonary disease, …`
- 去掉 `cause` 列后同样输入总死亡 3.683556；带 `cause` 时结果表被 F1 撑成 10 行、总量 NA

即校验说"4 个端点缺失"，实际一个都不缺。**修正方向**：两处用同一个解析函数决定"端点列是哪一列"。

### F3 [Info，T1 写域] CRS 字符串比较把 OGC CRS84 与 EPSG:4326 判为不同 → 多余重投影

`R/raster-io.R:202-207` 用 `terra::crs(r) != terra::crs(template)` 比较字符串。本用例的 netCDF 报
`GEOGCRS["WGS 84 (CRS84)"]`（OGC CRS84），模板报 `GEOGCRS["WGS 84" ... ID["EPSG",4326]]`，
字面不同 → 触发 `terra::project(conc, template)` 并打印 `Reprojecting 'conc' to EPSG:4326.`。

**数值影响实测为零**：`project()` 与 `resample(conc, template, "bilinear")` 在 LAO 窗口上
**逐格 bit-identical**（5563 / 6699 格 `max|Δ| = 0`，`sum` 相同，0.1 位键集合完全相同，无值变化行）。
**成本影响非零**：整幅栅格走一次投影。**建议**：用 `terra::same.crs()` 或 CRS 的地理基准判断，而不是字符串。

### F4 [Info，T1 写域] 单波段栅格的 NA 格被静默丢弃，网格随之缩小

`R/raster-io.R:75` 的 `filter(grid, n_na == 0)` 对单波段同样生效。ROU 曝光窗口 37 格 `-999`
被 harness 掩成 NA 后，`nrow(calc_fild)` 从 5600 落到 5563，`build_grid_info()$n_cells` 也随之变小，
`ext`/`res` 仍描述整幅栅格。建议在文档或消息里说明"无效曝光格不进分析网格"。

### F5 [Info，T2 写域] `Analysis grain` 把 NA 计为一个域

见 §3.3。数值影响为零，但会误导只圈一个国家的用户。

### F6 [Info，口径建议] 静默丢弃 CRF 不覆盖的年龄层

见 §6.2。`LAO` 有 **51.07%** 的人口落在被丢弃的 5 个年龄层里，结果**只覆盖 49% 的人口**且无任何提示。
属 `AGENTS.md` 判定队列 Q3/Q4 的同一族问题；本轮只登记，不实现。

### F7 [Info，口径建议] 域归属法则是 `touches`，不是格心

见 §3.4。建议写进 `admin=` 的文档。

### F8 [Info，T1/文档] `-999` 未声明填充值在中等纬度国家切片上同样出现

- LAO 窗口：**0** 格。
- ROU 窗口：**37 / 5600** 格恰为 `-999`（不是"负值"，就是填充值本身）。

影响（`step10_minrepro.R` B/C）：那 37 格的人口与域标签都是 0（黑海海面），
所以掩与不掩的总死亡**逐位相同**（18,607.852794）。但：

- `validate = "stop"` 下**直接中止**（实测 ROU 中止、LAO 通过）；
- `validate = "warn"` 下有两条消息：负值提示 + "37 value(s) in `conc_real` fall outside the
  CRF lookup range [0, 300] and are dropped by the join"。

即**填充值的后果是"严格模式下硬失败"，不是"数值错"**。这修正了"63% 全球格带填充值 = 一定会算错"的直觉：
在国家切片上，海面格没有人口，数值影响为 0；真正的风险是 `validate = "stop"` 下的可用性。

## 八、需拍板 / 遗留

1. **PAF 绝对水平（LAO 42.06%）**：算术自洽，但绝对水平偏高。这是查表曲线 + TMREL 口径的性质，
   不是包的计算错误。是否调整 `data/` 下的 GEMM 5COD 曲线（或补一个"相对零浓度"的替代曲线）
   需要用户拍板；本次不实现。**外部逐国 PAF 参照值没拿到**（PubMed / ScienceDirect 抓取被拦），
   所以这一项的证据等级是 V3（部分闭合），已在 §五 标注为量级检查。
2. **F1 的修法**：收敛到规范列 vs 显式报错。前者对 4 列输入零影响、对多列输入"静默丢弃"；
   后者让用户改脚本。属 T2 写域，请 Lead 定。
3. **F4 的消息文案**：无效曝光格是否要单独报一行（类似多波段掩膜那条告警）。
4. **LandScan 与 GBD 的人口口径差（LAO +20.6%）**：跨源对账要不要在文档里给一条"不要当等式"的说明。

## 九、验收与复跑

### 9.1 本轮跑过的门槛

| 门槛 | 命令 | 结果 |
|---|---|---|
| 全量测试 | `Rscript -e 'devtools::test()'` | `FAIL 0 / WARN 0 / SKIP 1 / PASS 982`，147.9 s（跳过项是默认关闭的指纹） |
| 指纹回归 | `$env:ATTRMORT_FINGERPRINTS=1; Rscript -e 'devtools::test(filter = "fingerprints")'` | `FAIL 0 / WARN 0 / SKIP 0 / PASS 42`，16.3 s，**无漂移** |
| 新增测试文件 | `Rscript -e 'devtools::test(filter = "validate-numeric")'` | `FAIL 0 / PASS 41`，10.6 s |

### 9.2 新增回归测试

`tests/testthat/test-validate-numeric.R`（41 条，只用随包示例数据，不依赖 `validate-data/`）：

1. **独立重建**：用基 R `merge()` + 显式公式，在随包示例网格（6000 格、3 个虚构国家、20 个年龄层）上
   逐格逐列重建 `mortality()` 的 PWRR 分支，容差 1e-10；并断言重建里 `PWRR > 1`（否则比较会在退化情形下假通过）。
2. **两个曝光角色不混用**：`conc_cf` 全设为 5 µg/m³ 后逐格重建，验证校准用 `conc_real`、风险项用 `conc_cf`。
3. **域级中心估计 = 网格求和**：`aggregate = TRUE` 的 `total` 与按域逐格求和逐列相等（容差 1e-12）。
4. **闭式锚点**：两格闭式值 `100 × (RR − 1)/PWRR`，钉住 1e5 只除一次与 PWRR 是人口加权均值。
5. **线性**：`mortrate` × 7 → 结果 × 7。
6. **无校准分支**：`mort_lvl = NULL` 时 `attr = 100 × (RR − 1)/RR`。

### 9.3 复跑

```powershell
$R = 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe'
$T3 = Join-Path $env:TEMP 'attrmort-recon\t3'
# 前置：none（脚本自包含，只读 D:\GitDir\AttrMort\validate-data）
& $R (Join-Path $T3 'step1_conservation.R')   # 核对 1
& $R (Join-Path $T3 'step13_gridmatch.R')     # 核对 2 的三条分支
& $R (Join-Path $T3 'step3_runs.R')           # 两个切片的逐格结果
& $R (Join-Path $T3 'step4_handcalc.R')       # 核对 3/4/5
& $R (Join-Path $T3 'step12_rawgbd.R')        # F1 最小复现
& $R (Join-Path $T3 'step2b_endpoint_col.R')  # F2 的列选择路线
```

产物（`%TEMP%\attrmort-recon\t3\`）：`run_ROU.rds`、`run_LAO.rds`、`grid_info_ROU.rds`、
`grid_info_LAO.rds`、`step1_conservation.rds`、`step4_handcalc.rds`。
