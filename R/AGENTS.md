# AGENTS.md —— `R/` 实现层约定

> 顶层约束见仓库根目录 `AGENTS.md`。本文件只说明 `R/` 内部怎么改。
> **本文件不记录任何进度、阶段完成情况或历史**：进度属于 git 提交与 `NEWS.md`。

## 一、文件职责

| 文件 | 职责 |
|---|---|
| `AttrMort-package.R` | 包级文档、roxygen 导入声明（按函数具名导入，不用整包 `@import`）、`.abort()`、`globalVariables()`；新增依赖时**先改这里** |
| `mortality.R` | `mortality()` 编排（参数检查 → `.prepare_inputs()` → 校验 → 计算核 → 聚合/区间；阶段函数 `.check_mortality_args()`、`.uncertainty_frames()`、`.aggregate_keys()`、`.aggregate_result()`）、`.calc_attributable_ages()` 分块器、`.calc_attributable()` 计算核及其三个分支函数、`.standardize_age_key()` |
| `prepare-inputs.R` | **两个入口的共同前置模块**：`.prepare_inputs()`（唯一的入口，1 检查文件 → 2 栅格对齐 → 3 读表映射列 → 4 网格一致性 → 5 贴边界 → 6 取一列情景），私有阶段 `.map_input_columns()`、`.check_grid_match()`、`.default_national_admin()`、`.report_boundary_match()`，以及情景层 `.extract_scenario()` + 四个 `.slice_*()`；文件头的注释表列出全部 given-when-then 路由 |
| `utils.R` | `matchable()`、`.resolve_key_cols()`、`.resolve_case_col()`、`.value_key_cols()`、`.pick_column()`、`.left_join_common()`、`.write_table_file()` |
| `rr_std.R` | `.match_ci()`、`.match_cr_model()`、`.cr_lookup_load()`（rda/xlsx/csv 查表装载）、`rr_std()` |
| `cr-config.R` | `cr_config()`、`cr_models()`、JSON 配置校验与 alias 解析（设计见 `diagnosis/design_json_crf_migration_260930.md`） |
| `schema-detect.R` | `.COLUMN_VARIANTS`、`.COLUMN_TARGET`、`detect_columns()`、`validate_mortality_input()` |
| `raster-io.R` | `raster_to_grid()`、`align_to_target()`、`.aggregate_pop()`、`shapefile_to_grid()`、`.resolve_target_res()` |
| `grid-info.R` | `build_grid_info()` —— 把分析网格显式化、可落盘；内部复用 raster-io/ingest 的对齐与栅格化，不另写一套 |
| `uncertainty.R` | `.row_total()`、`.total_frame()`、`.range_sum()`、`.attach_range()`、`.scale_conc()`、`.domain_pwe()` |
| `aggregate.R` | `aggregate_mortality()`、`aggregate_ci()`、`write_mortality_xlsx()`；列名解析（从右往左切最后一个 `_`）在此 |
| `build-cr.R` | `build_cr_table()`、`.cr_model_form()`、各模型的曲线函数 |
| `decompose.R` | `.DRIVER_ORDER`、`.permutations()`、`decompose()` |
| `data.R` | `data/*.rda` 九张内置查表的 roxygen 文档 |

## 二、`mortality()` 的七阶段

阶段 1–6 全部在 `R/prepare-inputs.R` 的 `.prepare_inputs()` 里，`mortality()` 调它一次，
`decompose()` 对**两组输入**各调一次（第二组传 `template =` 第一组的网格，保证同一张格子）。
**不要在 `decompose()` 里重跑 `mortality()`，也不要在任何入口里复制读文件/对齐/贴边界的逻辑**——
那是这次重构消掉的重复；新增输入类型时只改前置模块，并在它的文件头路由表里加一行。

1. `.check_input_files()` —— 字符型输入必须是存在的文件；
2. `.align_raster_inputs()` —— 栅格识别、`.resolve_target_res()`、`align_to_target()`、栅格转 data.frame；
3. `.map_input_columns()` —— 逐输入格式读取 + 列名映射（`detect_columns()`）；`calc_fild = NULL` 时骨架取自曝光**自身的坐标**（栅格天然如此，带坐标的表同样可以，并打印用了多少格）；曝光已聚合到域（无坐标）才报错；`calc_fild` 是矢量地图时按边界来源处理（见 `.is_vector_map()`），此时网格同样来自曝光；
4. `.check_grid_match()` —— 手供骨架必须与栅格网格有交集：0 命中报错、部分命中告警；
5. `.default_national_admin()` + `.attach_admin()` + `.report_boundary_match()` —— 行政区并入 `calc_fild`（栅格路径栅格化；表格路径按坐标 point-in-polygon，因为四舍五入的键无法用规则栅格复现；`admin = NULL` 且栅格路径需要域校准时回落到 rnaturalearth 国界，并报告匹配到的域数）；
6. `.extract_scenario()` —— 每个输入各取一列值并命名规范化：`scenario=` 只是逐输入列选择器，输入缺该列时用规范列或唯一数值列（`message()` 说明），多候选不猜、报错；不校验跨输入情景/年份一致性；`conc_cf` 缺省时回填为该输入的 `conc_real`；
7. 回到入口：`.check_inputs()` + `validate_mortality_input()` + `.calc_attributable()` —— 校验、连接键检查、计算；聚合与区间（`.aggregate_keys()`、`.aggregate_result()`、`.total_frame()`、`.range_sum()`、`.attach_range()`）仅在 `aggregate`/`uncertain` 时执行。

**阶段 1–6 负责 I/O、格式、网格与列名猜测；`.calc_attributable()` 只接受已经规范的 data.frame**，
不得在其中新增文件访问、列名猜测或栅格处理。

## 三、`.calc_attributable()` 的三条分支

`.calc_attributable()` 本身只做前置检查（CR 表缓存 → 超范围浓度告警 → 连接键规范化 → 端点交集 → 分支提示 → 空结果），计算分派给三个函数：

| 条件 | 语义 | 分支函数 |
|---|---|---|
| `mort_lvl = NULL` | 网格级，不做 PWRR 校准，RR 取 `conc_real` | `.attributable_grid()`（无域聚合的快速路径） |
| `mort_lvl` 是 `mort_rate` 的列 | PWRR 校准：`PWRR = weighted.mean(RR, pop)`，风险项取 `conc_cf` | `.attributable_by_domain()`（默认主路径，校准量由 `.pwrr_by_domain()` 求） |
| `mort_lvl` 不是其列 | 先 `.resolve_mort_lvl()`：能对上映射后的列就用它，否则用 `mort_rate` 自己的域列（告警） | 仍不成立（`mort_rate` 无地理列）时：视全域为一个单位，PWRR 全域加权，**风险项取全域均值 RR，不看 `conc_cf`** | `.attributable_one_field()`（退路，需告警） |

三条分支都以 `{endpoint}_{age}` 宽表返回（统一经 `.widen_mort()`），且必须检查端点交集与空结果（不得返回 0 行而不报错）。死亡率单位换算统一用 `.PER_100K`，不要另写 `1e5`。

## 三之二、`decompose()` 的结构

```
as_group(from) / as_group(to)   两组完整输入（conc_real/pop_total/age_struc/mort_rate[/conc_cf]）
.prepare_inputs() × 2           第 1 组定网格，第 2 组对齐到它的 template
.extract_scenario(scenario=NULL) × 2   只做列名规范化，不做情景选择
validate_mortality_input × 2 + .check_inputs × 2 + grain 提示   每次调用各一次
rr_std()                        一次，全部状态共用同一张 C-R 表
state(moved) × 16               按「已移动驱动集合」缓存的计算（16 个子集）
组装                            每个顺序：Start + 相邻状态相减 + End
```

- **两组之间只有数据不同**：`decompose()` 不认识任何情景列名；每组的表就是该组的值（列名可以是规范名，也可以是情景名）。
- `state(moved)` 的映射固定为 `PG→pop_total`、`PA→age_struc`、`EXP→conc_cf`（缺 `conc_cf` 时用该组 `conc_real`）、`ORF→conc_real` 与 `mort_rate`。
- 24 个顺序共用 **16 个状态**（`2^4` 个子集），所以一次完整分解是 16 次计算，不是 24×5；结果按顺序名返回 24 个 data.frame。
- 结果形状：键列 + `Cause_Age` + `Start` + 各驱动（按该顺序的先后）+ `End`，每行一个「格子 × 年龄层」，层在格子内变化最快（`pivot_longer()` 的展开顺序，测试钉住）。
- 不变量：**每一步的驱动列必须等于该前缀的状态减去上一前缀的状态**；`Start`/`End` 在 24 个顺序间必须完全相同。
- 不要在 `decompose()` 里重跑 `mortality()`，也不要复制一份读文件/对齐/贴边界逻辑——两者共用 `.prepare_inputs()`。

## 四、改前必读的内部契约

- **列名映射方向**：`detect_columns()` 返回 `c(语义 = 实际列名)`，重命名必须是「实际 → 规范名」（查 `.COLUMN_TARGET` 表）。方向写反会把 `endpoint` 改成 `cause`，且会以列检查失败的形式暴露。
- **值列解析（scenario 语义）**：`.resolve_case_col()`（`utils.R`）是 `pop`/`conc`/`prop`/`mortrate` 的唯一入口：`scenario=` 命中列名 > 规范列 > 唯一数值非键列（`message()` 说明用了哪列）> 报错列出候选。`scenario=` 只是逐输入列选择器，**不得**要求所有输入都带该列，也不得判断跨输入情景/年份一致性；`.extract_scenario(NULL)` 用 `strict = FALSE` 让 `.check_inputs()` 一次汇总所有问题。
- **运行输出洁净**：内部 join 一律经 `.left_join_common()`（显式取 `intersect(names(x), names(y))` 为键），不得退回会打印 `Joining with ...` 的自然 join；`validate = "off"` 下除结果外不输出。该 helper 同时声明 `relationship = "many-to-many"`：骨架表（格/域）与查表、`mort_rate`、`age_struc` 的扇出是计算本身（每格每端点每年龄一行），不得改回默认而让 dplyr 的 many-to-many 告警淹没运行输出；扇出行数由 `tests/testthat/test-utils.R` 钉住。
- **浓度键类型**：暴露数据与查表两侧都必须是字符、同为 `dgt_conc` 位。查表一律经 `rr_std()` 渲染，新模型必须登记进配置（`inst/extdata/cr_models.json`，`lookup` 指定表/文件与端点年龄），否则数值/字符不一致会在 join 处报错。内置查表的原始 `conc` 列也须是字符键（`tests/testthat/test-rr_std.R` 会比对原始对象）。
- **查表年龄继承**：`rr_std()` 对缺列年龄按“继承前一个年龄”处理（从 `_ALL` 行开始）——GEMM 的 85/90/95 继承 80、MRBRT 的 `_ALL` 表全程继承 ALL，均由指纹钉住；装载校验要求每个端点至少存在“首个年龄列或 `_ALL` 列”（`R/rr_std.R` 的 `.cr_lookup_check()`）。改动该逻辑前先跑 39 表对照与指纹（见 `diagnosis/code_review_260930.md`）。
- **多波段栅格掩膜**：多情景栅格必须共享同一有效掩膜；`raster_to_grid()` 只保留所有层都有值的格子，某格只在部分层有值时**必须告警**并说明各层缺测数，不得静默收窄网格。
- **人口栅格聚合**：`.aggregate_pop()` 先 `terra::aggregate(fun = "sum")` 再 resample，并核对总量；不要退回 `terra::resample(method = "sum")`（不守恒）。
- **分辨率交互**：`.resolve_target_res()` 在非交互会话不得调用 `readline()`；> 1e9 格直接拒绝；非方形栅格按 `c(res_x, res_y)` 保留，不得对两轴取均值（会给整张网格换分辨率）。
- **空年龄块**：`.calc_attributable_ages()` 允许块内年龄全部缺席 `age_struc`——跳过该块，与不分块结果一致；全部块为空时按不分块路径报"无行存活"，不得在空块处中止。
- **表格网格的域标签**：`calc_fild` 为表格时 `.attach_admin()` 用 point-in-polygon 贴标签（键是四舍五入过的字符坐标），不得退回"按坐标范围+固定/推断分辨率建模板再栅格化"；标签全 NA 必须报错，不得静默返回无域列的表。
- **区间口径**：`.range_sum()`/`.attach_range()` 是逐格分位求和（共模），不得改回平方和形式；两端的组装在 `.uncertainty_frames()`（CRF 分位 + 可选的 `conc_uncert` 链），只发一次分支提示。
- **分解口径**：`decompose()` 比较**两组输入**（`from`/`to` 各是一套 `conc_real`/`pop_total`/`age_struc`/`mort_rate`[/`conc_cf`]），不认识任何情景列名。一个步骤的状态只由「已移动驱动集合」决定：`PG→pop_total`、`PA→age_struc`、`EXP→conc_cf`（该组没给就用它的 `conc_real`）、`ORF→conc_real` 与 `mort_rate`；已移动的驱动读 `to` 组，其余读 `from` 组。**每一步只允许移动它名字里的那个驱动**，24 个顺序共用 16 个状态，`test-decompose.R` 对全部顺序都检查这条不变量；0.3.0 之前 `PG EXP` 的第二步读反过 `pop`/`age`（影响序列 3/4/13/14），已按用户决定修正，见 `NEWS.md`。
- **分辨率阈值**：`.RES_AUTO_CONFIRM_CELLS`/`.RES_PROMPT_CELLS`/`.RES_MAX_CELLS`/`.RES_FALLBACK`/`.RES_SUGGESTIONS` 是唯一定义处；交互菜单在 `.prompt_resolution()`（`cat()` 走 stdout，因为要抢在 `readline()` 之前显示），非交互回退逻辑在 `.resolve_target_res()`。
- **`raster_to_grid()` 接受 `SpatRaster`**：内部必须先判断 `inherits(path, "SpatRaster")`，否则 `terra::rast()` 会返回空模板。

## 五、导出面与文档

- 只有公开 API 出现在 `man/`；内部函数用 `@noRd` 保留源码注释即可。
- 新增导出：写 roxygen → `devtools::document()` → 确认 `man/` 只多出该函数一页。
- 改口径或数据契约：**同一次提交内**同步 `tests/` 与 `NEWS.md`。
- 若新增模型：改 `inst/extdata/cr_models.json`（`lookup` + 端点年龄）+ 查表资产；`tests/testthat/test-cr-config.R` 会比对配置与实际 `rr_std()` 输出的端点年龄集合。

## 六、测试与回归装置

| 测试文件 | 覆盖 |
|---|---|
| `test-mortality.R` | 端到端：PWRR 校验、`conc_cf` 语义、三条 `mort_lvl` 分支、场景抽取、输入报错、随包示例数据 |
| `test-rr_std.R` | 全部模型与 CI、年龄过滤、浓度键类型与精度 |
| `test-utils.R` | `matchable()` 与四个 `get*()` |
| `test-schema-detect.R` | 列名映射、阻断/告警校验、自定义配置端点比对 |
| `test-raster-io.R` | 栅格转表、人口聚合守恒、分辨率选择、行政区栅格化、GeoTIFF 端到端 |
| `test-uncertainty.R` | `aggregate`/`aggregate_by` 求和、`CI_LOW`/`CI_UP` range、`conc_uncert` 链 |
| `test-aggregate.R` | `aggregate_mortality()`/`aggregate_ci()` 的列名解析与求和 |
| `test-fingerprints.R` | 13 条分支的逐列求和指纹（默认跳过，`ATTRMORT_FINGERPRINTS=1` 触发；`=update` 重写参照），以及示例数据自身的自洽检查（端点齐全、国级人口与网格合计一致、年龄占比和≈1） |
| `test-build-cr.R` | 两套曲线公式、备选列名归一、输出契约（默认不依赖仓库外文件） |
| `test-grid-path.R` | 栅格路径：`calc_fild` 可省、国家级默认边界、年龄切片、netCDF、单层栅格无 `scenario` |
| `test-grid-info.R` | `build_grid_info()` 产物与三条路径等价、**骨架全错位报错 / 部分错位告警**（`validate = "off"` 全关）、`.rds`/`.csv` 往返、表格输入模式 |
| `test-decompose.R` | 24 种排列映射、起止点与单情景 `mortality()` 逐行一致、单驱动差分等于前缀运行之差、望远镜加和、CI 分支透传、非法 `serie` 报错 |
| `test-cr-config.R` | 默认配置装载、两种 ages 写法、alias 解析、配置↔`rr_std()` 端点年龄一致、非法配置逐类报错 |

- 数值路径改动前后各跑一次指纹回归：设 `ATTRMORT_FINGERPRINTS=1` 跑 `devtools::test(filter = "fingerprints")`（用 `=update` 重写参照）；参照指纹在 `tests/testthat/fixtures/fingerprints/`。
- 测试只放在 `tests/testthat/`；手工脚本放 `data-raw/`，因为 `R CMD check` 会执行 `tests/` 下每个 `.R`。

## 七、待办（前向计划；完成后请删除对应条目）

1. **网格引擎的剩余部分（比 0.1° 更细的尺度）**：0.1° 全球由年龄维切片覆盖（648 万格 × 20 年龄组，单遍峰值只有一个年龄的长表）；再往细走需要按格子维分块：现架构把栅格整体转成单一网格上的 data.frame，内存随「格子数 × 年龄数 × 端点数」增长，全球 1 km（陆地约 2.7–3 亿格 × 20 年龄组）必然爆内存。计划新增分块流式引擎（`R/grid-engine.R` + `R/tiles.R`），**口径与现有引擎完全一致**：
   - **两遍扫描**：第一遍按 `(域, 年龄, 端点)` 累积 `Σpop` 与 `Σpop·RR`（PWRR 校准量）；第二遍逐块算 PAF 与死亡数，累积到域表与（可选）逐格栅格；
   - **不物化长表**：小维（年龄 × 端点）循环、大维（格子）向量化，单块内存只与块内格子数有关，与全球尺度无关；
   - **输入输出磁盘化**：`terra::readValues(win=)` / `writeValues()` 窗口读写；行政区预先生成「域 ID 栅格」并对齐目标网格，避免计算期持有矢量；
   - **块内用整数行列索引 + 数值查表**（`round((conc - c0) / step) + 1` 直接索引 CRF 轴）替代字符键 join；字符键路径只留给表格输入；
   - **不确定性 range 同扫描三联求值**（MEAN/LOW/UP 在同一块上一起算），不增加扫描遍数；
   - **护栏**：块大小 × 并行数的内存预算预检、断点续跑检查点、运行清单（输入指纹 + 口径版本 + 块参数）；
   - **验收锚点**：在随包示例数据上，网格引擎与 `mortality()` 的结果必须逐列一致（复用 `test-fingerprints.R` 的比对方式）。
2. **实例数据构建未进包**：把异构原始数据（netCDF/GeoTIFF 浓度、人口栅格、CSV/Excel 死亡率与年龄结构）整理成标准实例文件的流程，目前只有 `data-raw/make-example-data.R` 这份合成示例可作模板，尚无通用工具函数。
3. **`aggregate_ci()` 与 `mortality(uncertain = TRUE)` 的边界**：前者要求调用方自带 `_MEAN/_UP/_LOW` 后缀，后者直接给区间；若将来让 `mortality()` 一次输出三支并加后缀，需明确两者分工。
4. **独立误差口径**：若需要「每格误差独立」的抽样区间，可增加 `ci_method = "quadrature"`（现有 range 口径为共模假设）。
5. **JSON C-R 配置迁移（P0–P3 已完成，P4 待做）**：内置 13 个模型名已由 `inst/extdata/cr_models.json` 驱动，`.CR_TABLE_REGISTRY`、`rr_std()` 的 reshape 分支与 `.CR_ENDPOINTS` 已删除；自定义模型可经 `cr_config=` + xlsx/csv 查表接入并有端到端测试；NO<sub>2</sub> 端点按拍板改为 `allcause`（对应查表前缀 `cause`，指纹参照已更新、数值不变）。教程见 `vignettes/AttrMort.Rmd`；待做仅剩发布说明（`NEWS.md`/版本号按用户决定暂不动）。设计见 `diagnosis/design_json_crf_migration_260930.md`，完成后删除本条。