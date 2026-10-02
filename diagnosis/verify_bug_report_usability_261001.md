# 外部可用性缺陷清单核实报告（261001）

- **审核日期 / 范围**：2026-10-01。对象为 `diagnosis/bug_report_usability_261001.md` 全文（B1–B8 与附录结论），对照 `README.md`、`AGENTS.md`（数据契约）、`NEWS.md` 0.3.0 与 `R/` 源码。
- **核实基线**：源码 HEAD `319269f`（工作区无未提交源码改动）；另以安装版 AttrMort 0.3.0 复核 B1。环境：R 4.6.1、terra 1.9.50、sf 1.1.3、dplyr 1.2.1、readxl 1.5.0.1、testthat 3.3.2、devtools 2.5.2。
- **方法**：静态通读 + 运行时重跑（V1）。B1/B4/B5/B6/B7/B8 用包自带 `inst/extdata` 合成数据直接复现；B2/B3 另建最小非方形 GeoTIFF、坐标表格、sf 边界与 `domain_summary()`/`Mortality()` 组合复现。外部生产数据（`202508 食品生产与公平` 项目）不在本仓库、本机未找到该项目目录，**涉及生产数据的绝对计数（3,707 格、154 行日志）无法逐位复算**，仅确认代码路径与合成数据下的机制、量级；此类条目逐条标注。
- **结论**：**8 项全部成立或成立但表述需修正，无一项被证伪。** 其中 B1、B2、B3 认定为阻断级；B4、B5、B6 需修；B7、B8 信息级。原报告有 3 处需要修正（§三），另有 2 项原报告未覆盖的同源问题（§二）。
- **证据锚点**：`chunk_ages=1L/2L` 复现同一条 join 报错、`chunk_ages=5L` 与默认 `max|diff| = 0`；res=(2.5, 2) 栅格被解成 2.25 后网格 30→28 格；`domain_summary()` 表格浓度 + `admin=` 复现原错；`build_grid_info()` 同输入静默返回 4/4 全 NA 域标签；`Pop2017` 复现原错、改名后 6000×18 通过；单列辅助表复现 scenario 报错；自带测试 217 项 / 0 失败 / 0 警告 / 1 跳过（683 个断言通过），与原报告一致。

---

## 一、逐项核实

### 1.1 总表

| 条目 | 判定 | 证据等级 | 分级（本报告认定） |
|---|---|---|---|
| B1 空年龄块中止分块运行 | 成立（V1，安装版与源码均复现） | 阻断级 | Blocker |
| B2 非方形栅格被压成单值分辨率并重采样 | 成立（V1 机制；生产数据格数未复算） | 阻断级 | Blocker |
| B3 表格浓度 + `admin=` 的 `domain_summary()` 报错 | 成立（V1），且影响面大于原报告 | 阻断级 | Blocker |
| B4 `Pop2017` 不被识别 | 成立（V1） | 需修 | Must-fix |
| B5 `scenario=` 要求辅助表同名情景列 | 成立（V1） | 需修 | Must-fix |
| B6 join 提示刷屏、`validate="off"` 不静默 | 机制成立（V1）；150+ 行未复算 | 需修 | Must-fix |
| B7 `domain_summary()` 域列名不统一 | 成立但需加前提（V1） | 一致性 | Info |
| B8 README 对 `mort_lvl = NULL` 的说明 | 成立（V1），属文档补充 | 文档 | Info |

### 1.2 分项证据

#### B1 空块中止——成立（Blocker）

复现（包自带数据，`age_struc` 去掉 95 档）：

```r
ag2 <- ag |> filter(age != "95")
Mortality(..., age_struc = ag2, ..., chunk_ages = 1L)   # ERROR
Mortality(..., age_struc = ag2, ..., chunk_ages = 2L)   # ERROR（末块只剩 95）
Mortality(..., age_struc = ag2, ...)                    # OK 6000×17
Mortality(..., age_struc = ag2, ..., chunk_ages = 5L)   # OK 6000×17
```

- 实测：`chunk_ages = 1L`、`2L` 给出与报告完全一致的 "No rows survived the join..."；`chunk_ages = 5L` 与不分块的列名、数值全等，`max |diff| = 0`。安装版 0.3.0 与源码 HEAD 行为一致。
- 根因核对：`R/Mortality.R:790-817`（`.chunkable_ages()` → 逐块 `filter(age %in% block)` → `.calc_attributable()`）与 `R/Mortality.R:971-980`（空结果即 `stop()`）确如报告所述；块内**所有**年龄都不在 `age_struc` 时才为空，报告举的"缺档被单独分到一块"是其中一类触发。
- README `README.md:97` 承诺 "a chunked run is identical to an unchunked one"，当前在缺档数据上不成立；错误信息与真实原因（空块）无关，属误导。
- 附带确认：不分块时缺档年龄只是在宽表结果里自然缺席（本例无 95 档列），不是"补 0"。

#### B2 非方形栅格——成立（Blocker）

用 `terra` 造 res=(2.5, 2)、EPSG:4326 的浓度/人口栅格：

- `.resolve_target_res()` 实测输出与报告逐字一致：`Detected raster resolutions: 2.25000 deg, 2.25000 deg`、`Target resolution: 2.25000 deg (~12800 cells) - auto-confirmed.`，返回 2.25。根因即 `R/raster-io.R:344-345` 的 `mean(terra::res(...))`（报告引用的行号准确）。
- 对齐结果：模板分辨率实测 `2.142857 x 2.5`（`terra::rast(ext, resolution=2.25)` 按整数格拟合），**30 格输入变 28 格**；同坐标的表格路径保持 30 行。即"结果网格被修改"成立。
- `build_grid_info()` 对同一表格网格：`attr(gi, "res") = 2.25`（x 间距 2.5、y 间距 2.0 的均值，`R/grid-info.R:56-58`），确认报告描述。
- 补充：`target_res = c(2.5, 2)` 目前不可用——先打印 `Using specified target resolution: 2.52 deg`（向量被直接拼接），随后在 `if (target_res <= 0)` 处报 `condition has length > 1`。修复建议里"支持长度 2"需求真实存在；实测 `terra::rast(ext, resolution = c(2.5, 2))` 本身支持向量，技术上可行。
- 未复算项：生产数据 3,634 → 3,707 的具体格数（外部数据不可得）；机制、方向（重采样改变网格与格数）与合成结果一致。

#### B3 表格浓度 + `admin=`——成立（Blocker），且影响面更大

用坐标表格 + sf 多边形（`name_long` 列）复现：

- `domain_summary(conc_real = <x/y/conc 表>, pop_total = <x/y/pop 表>, admin = <shp>, admin_col = "name_long")` → 复现报告中的 `admin labelled no cell of conc_real ...` 错误；换成栅格 `conc_real` 后同一调用返回 `1×5`（`name_long, conc_pwe, conc_mean, pop_total, n_cells`），确认"栅格可用、表格不可用"。
- 根因核对：`R/domain-summary.R:149-210` 决定模板来源；无栅格时落到 `R/ingest.R:254-263` 的兜底模板：`terra::rast(ext(range(x), range(y)), resolution = 0.1)`，其格心（min+0.05+0.1k）与表格坐标键（2 位小数的格心）几乎不可能相等，`left_join(by = c("x","y"))` 后域列全 NA，于是触发 `R/domain-summary.R:201-209` 的报错。README 的 "National-only workflow"（`README.md:100-128`）正是表格浓度 + `admin=`，示例当前跑不通。
- **需修正之处**：报告称"同一对输入 `build_grid_info()` 可用"不准确。实测同一对表格输入 + `admin=` 会返回 `n=4、域列 4/4 全 NA` 且**不报错**（`build_grid_info()` 没有 `domain_summary()` 的 NA 检查）。这不是"可用"，而是静默产出无域标签的表。
- **影响面修正**：同一兜底模板也用于 `Mortality()` 的表格路径。实测 `Mortality(calc_fild=<x/y 表>, conc_real=<表>, admin=<shp>, mort_lvl="location")` 报的正是 B1 那条误导性的 "No rows survived the join..."（域标签全 NA → 与 `mort_rate$location` 无法连接）。因此这不是 `domain_summary()` 独有，凡"坐标表格 + `admin=`"都受影响；建议把 `R/ingest.R:254-263` 的兜底模板改为由表格坐标自身推断（间距与原点对齐，复用 `.grid_spacing()` 思路），或在无法对齐时明确报错，而不是让下游 join 擦除域列。

#### B4 `Pop2017`——成立（Must-fix）

- 复现（仅人口列名为 `Pop2017`、其余输入规范名、`scenario = NULL`）：`ERROR: Invalid input data: - \`pop_total\` is missing required column(s): \`pop\`.`；改名 `Pop2017 -> pop` 后同一调用 `OK 6000×18`。
- 根因位置准确：`R/schema-detect.R:263` 的 `intersect(c("pop", "Pop", "population"), ...)`（该处是体检/校验的识别分支；正式报错由 `R/Mortality.R:8-14` 的 `.REQUIRED_VALUE_COLS` 与 `:29-70` 的 `.check_inputs()` 给出）。
- 报告建议的正则（`^pop([0-9]{4})?$` 等，并 `message()` 告知命中列）可行；核心诉求是"年份后缀列名不该让最常规的组合直接失败"。

#### B5 `scenario=` 单列辅助表——成立（Must-fix）

- 复现：宽表浓度（`baseline` 列）+ 单列人口 `x, y, Pop2017`，`scenario = "baseline"` → `ERROR: Scenario column "baseline" not found in the data. Available columns: x, y, Pop2017.`（与报告一致）；年龄/死亡表同样要复制列，否则下一轮同样报错。把各辅助表的值列复制/改名为 `baseline` 后运行通过。
- 机制：`R/ingest.R:304-336` 对每个非空输入统一调用 `getConc()/getPop()/getAge()/getMort()`，四者在 `R/utils.R:70-81` 一律先查情景列名，没有"唯一数值列按情景无关处理"的分支。
- 注意一个偶然例外：若单列列名恰好等于 `scenario`（如列名 `base2015`、`scenario = "base2015"`），可以跑通——这不影响报告结论，但复现时要保证列名与情景名不同才能看到该错误。
- 建议方向合理（唯一数值列按情景无关处理并提示，或报错文本给出"复制列 / 改单列 + `scenario = NULL`"两种改法）。

#### B6 join 提示刷屏——机制成立（Must-fix）

- 源码确认：`R/Mortality.R:920/930/938/950/957/961` 全部为无 `by=` 的自然 join（`reduce(left_join)` 与 `left_join(PWRR)`）；`R/domain-summary.R:242/253` 同。dplyr 因而每次 join 输出一行 `Joining with \`by = ...\``。
- 实测：自带数据的单次运行 9 行；`uncertain=TRUE, conc_uncert=10` 的 5 条计算链共 45 行；`validate = "off"` 只压掉 grain 等 message，join 提示仍为 9 行（**不能静默，成立**）。连 `devtools::test()` 的完整输出里都有 497 行 `Joining with`。
- 未复算项：生产数据 154 行的绝对值（需要外部 log）；按"每链 9 行 × 调用链数"的量级推算合理。
- 修复建议（显式 `by=` 或内部统一 `suppressMessages()`，或加 `quiet=`）成立；显式 `by=` 还能消除键推断歧义，建议优先。

#### B7 域列名不统一——成立（需加前提，Info）

- 实测：`domain_summary(..., admin_col = "name_long")` 不传 `mort_lvl` 时返回列 `name_long`；传 `mort_lvl = "location"` 时返回 `location`。`Mortality()` 则在 `.attach_admin()`（`R/ingest.R:269-273`）把边界列改名为 `mort_lvl`（README 国家流程里即 `location`）。README 示例没给 `domain_summary()` 传 `mort_lvl`，所以串联时确需手工 `data.frame(location = ds$iso3, ...)`。
- 修正表述：差异不是"`domain_summary()` 永远保留原名"，而是"默认保留 `admin_col` 原名；`Mortality()` 一律改名为 `mort_lvl`，仅当调用者给 `domain_summary()` 也传了同名 `mort_lvl` 时才一致"。统一为 `location` 或文档示例传 `mort_lvl = "location"` 都可行。

#### B8 README `mort_lvl = NULL`——成立（文档，Info）

- 复现（栅格浓度 + 栅格人口、域级 `age_struc`/`mort_rate`、`mort_lvl = NULL`、无 `admin`）：报错与报告引用逐字一致：
  `- \`age_struc\` shares no join key with \`calc_fild\` (keys available: \`x\`, \`y\`; \`age_struc\` has: \`location\`, \`age\`, \`prop\`).`
- `README.md:93` 的 "`mort_lvl = NULL` still means 'no domains at all'" 本身描述的是校准口径，不算错；缺的是前提说明（域级表仍需 `admin=` 或 `calc_fild` 自带域列）。错误信息里已含可操作提示（"Pass `admin =` ... or supply a `calc_fild` that carries a domain column"），所以这只是文档补一句的问题，不涉及代码行为。

## 二、原报告未覆盖、核实中发现的同源问题

1. **`build_grid_info()` 静默产出全 NA 域标签**（B3 同源）。同一对"坐标表格 + `admin=`"输入，`build_grid_info()` 不报错、返回 4/4 全 NA 的域列。建议给 `R/grid-info.R:206-215` 的 `admin` 分支补与 `domain_summary()` 相同的"零命中/全 NA"检查；否则用户会把一张无域标签的表当作网格物证（违反 AGENTS.md"边界提供域标签"与"交回时必须对得上"的精神）。
2. **`Mortality()` 表格路径 + `admin=` 失败并给出误导性错误**（B1/B3 交叉）。域标签全 NA 后，`mort_rate` 的域键接不上，最终报 "No rows survived the join ... Check that `mort_rate` covers the same domains ..."，把用户引向检查死亡率数据，而真实原因是边界栅格化没有落在表格网格上。修复 B3 兜底模板时建议同时覆盖此路径。

## 三、对原报告本身的修正（只增不改，原报告不改动）

1. B3"同一对输入 `build_grid_info()` 可用"→ 实测为"不报错但域列全 NA"；`Mortality()` 表格路径同样受影响（§二.2）。
2. B2"被静默平均为方形分辨率"→ 精确说法是 `mean(terra::res())` 把 (resx, resy) 压成一个标量作为目标分辨率；模板经 terra 整数格拟合后不一定严格方形（实测 2.142857 × 2.5），但"静默改变分析网格"的判定成立。
3. B6 的 154 行与 B2 的 3,707 格属于外部生产数据实测值，本仓库无法逐位复核，只能确认机制与量级；建议在原报告或项目方保留 `diag`/log 作为可追溯锚点。
4. B7、B8 的措辞按 §1.2 对应小节加上前提后更准确。

## 四、建议的回归验收用例（在原报告 6 条基础上修订）

1. `age_struc` 缺档（95 或 90）× `chunk_ages = 1L/2L`：与 `chunk_ages = NULL` 全等（B1）。
2. res=(2.5, 2) 栅格、不给 `target_res`：应报警/保留非方形；`target_res = c(2.5, 2)` 应可用；`build_grid_info()` 的 `res` 属性为两个值（B2）。
3. 坐标表格 + `admin=`：`Mortality()` 与 `domain_summary()` 要么可跑、要么报"网格无法对齐"的可操作错误；`build_grid_info()` 不得静默返回全 NA 域列（B3、§二.1）。
4. `pop_total` 列名 `Pop2017` / `Pop` / `population` / `pop` 均可识别，且 `message()` 说明命中列（B4）。
5. 宽表浓度 + 单列辅助输入（列名与情景名不同）：可跑或报错给出"复制列 / 单列 + `scenario = NULL`"示例（B5）。
6. `validate = "off"` 下输出中不含 `Joining with ...`（B6）。
7. `domain_summary()` 域列名与 README 串联示例一致（或 README 传 `mort_lvl = "location"`）（B7）。
8. README `mort_lvl = NULL` 句补前提（B8）。

## 五、复算环境与脚本

- 复算脚本在仓库外 `%TEMP%/attrmort-verify/`（B1/B4/B5：`b1.R`、`b1_installed.R`、`b45.R`、`b45b.R`、`b1eq.R`；B2：`b2b.R`、`b2dbg.R`、`b2full.R`、`ax.R`；B3：`b3.R`、`b3m.R`；B7/B8：`b78.R`、`b8.R`），均从 `D:/GitDir/AttrMort` 以 `devtools::load_all()` 加载当前源码运行；本报告未改动任何源码。
- 测试基线：`devtools::test("D:/GitDir/AttrMort")` → 217 项断言、0 失败、0 警告、1 跳过（fingerprint 需 `ATTRMORT_FINGERPRINTS=1`）、683 个通过，与原报告"217/0/0/1"一致。

## 六、处置建议（待用户拍板，本次不代改）

- 建议按 B1 → B2 → B3（含 §二 两项）顺序修复：三者都影响对外承诺/结果口径，且 B1/B3 的报错信息会误导用户；B4–B6 可作为同一轮低风险 UX 修复；B7/B8 随 README 一并修订。
- B2 的 `target_res` 向量化、B3 的表格网格模板推断、B1 的空块容忍都会改动内部行为，落地前需按 AGENTS.md 补 `tests/` 回归与 `NEWS.md` 条目，并跑指纹回归。

---

## 补记：真 BUG 修复（2026-10-01，取代 §六 的执行状态）

用户指示先修"真 BUG"（B1、B2、B3 及 §二 两项），B4–B8 待下一轮商榷。本节只追加，不改上文结论。

**修复内容**

| 条目 | 落点 | 做法 |
|---|---|---|
| B1 空年龄块中止分块 | `R/Mortality.R`（`.calc_attributable_ages()`、`.calc_attributable(allow_empty=)`） | 空块跳过；全部块为空时回落到不分块路径，报错文本与不分块完全一致 |
| B2 非方形分辨率被取均值 | `R/raster-io.R`（`.resolve_target_res()`、`align_to_target()`、`.aggregate_pop()`）、`R/grid-info.R`、`R/utils.R` | 按轴取每轴最细；`target_res` 支持长度 1/2；`.aggregate_pop()` 用 `rev(fact)` 的逐轴因子（并跳过 factor=1 的 no-op 聚合）；方形时保持原有单值返回；`res` 属性非方形时为 `c(res_x,res_y)` |
| B3 表格网格 + `admin=` | `R/ingest.R`（`.attach_admin()` + `.read_admin_sf()`/`.resolve_admin_col()`/`.admin_points_to_grid()`） | 表格网格改为按坐标 point-in-polygon 贴标签（四舍五入键无法用规则栅格复现）；标签全 NA 一律 `stop("labelled no cell ...")`，覆盖 `domain_summary()`/`Mortality()`/`build_grid_info()` 三个入口；`calc_fild` 已带同名域列时用临时列名 join，边界标签优先 |
| 附带 | `R/raster-io.R` | 源/目标分辨率相同时不再调用 `terra::aggregate(fact=1)`（消除 "nothing to do" 警告） |

**回归测试（新增）**：缺档 `age_struc` × `chunk_ages = 1/2/5` 与不分块全等、全空时报错与不分块一致（`test-grid-path.R`）；非方形自动分辨率/向量 `target_res`/非方形对齐与人口守恒（`test-raster-io.R`）；非方形表格 `res` 属性、四舍五入键的表格 + 边界标签逐一比对（`test-grid-info.R`）；表格网格 + 边界 `domain_summary()` 与表格自带标签全等（`test-domain-summary.R`，原"钉死旧行为"的用例按注释预期改为通过用例）；表格 + 边界 `Mortality()` 与表格口径总量全等、不覆盖边界的报错（`test-grid-path.R`）。

**运行证据**

- `devtools::test()`：231 项断言、0 失败、0 警告、1 跳过、713 通过；`ATTRMORT_FINGERPRINTS=1` 下指纹 6/6 通过（数值路径未动）。
- `R CMD build` + `R CMD check --no-manual`（含 vignette 构建）：**Status: OK**（0 error / 0 warning / 0 note）。
- 复核脚本复跑：B1 `chunk1/2` 与默认列名数值全等（`max|diff|=0`）；B2 res=(2.5,2) 对齐后仍 30 格、`res` 属性 `c(2.5,2)`；B3 表格 + 边界 `domain_summary()`/`Mortality()`/`build_grid_info()` 全部通过，且示例数据的 6000 格标签与表格自带 `location` 0 错配。
- 同步更新：`NEWS.md`、`README.md`、`AGENTS.md`（数据契约新增"非方形栅格""分块与空年龄块"两行）、`R/AGENTS.md`（阶段 4 与内部契约）、`man/`（`document()` 重生成）。

**风格改动扫描结论（本轮开工前用户改动的 part）**：全量测试绿，未发现功能性回归；变量/函数名变化已按当前工作树适配。一条观察：`lapply` → `purrr::map` 后，块内真实错误的 `conditionMessage()` 首行变为 `ℹ In index: N.`，原因仍在 `Caused by error:` 中完整保留；B1 修复后该包装只在真正的错误上出现。`write_mortality_xlsx()`（风格改动顺带新增的导出）测试齐全。

**仍待下一轮（按用户指示）**：B4（`Pop2017` 识别策略）、B5（单列辅助表情景语义）、B6（join 提示刷屏与 `validate="off"`）、B7（域列命名）、B8（README `mort_lvl=NULL` 前提）。

---

## 补记 2：B4 现状探查（2026-10-01，修正 §一.2 B4 的根因定位）

当前工作树实测（`scenario = NULL`、人口表除键列外只有一列、其余输入用规范名）：

| 人口列名 | 结果 |
|---|---|
| `pop` | OK（6000×18） |
| `Pop` / `POP` / `population` / `Population2017` / `Pop2017` / `pop2017` / `pop_2017` / `total_pop` / `pop_count` | 全部 `Invalid input data: \`pop_total\` is missing required column(s): \`pop\`` |

结论修正：原报告把根因定位在 `R/schema-detect.R:263` 的 `c("pop", "Pop", "population")` 白名单并不准确——该白名单只服务 `validate_mortality_input()` 的**负值体检**，不参与重命名。真正的缺口是：**`pop` 与 `conc` 这两个值列在表格路径上没有别名映射**。列名规范化的三条既有路径是（a）`scenario =`：`getPop()`/`getConc()` 抽取时把列改名为 `pop`/`conc`；（b）栅格单波段：`.rename_single_band()` 改名；（c）域级表的语义字段：`detect_columns()` 的 `.COLUMN_VARIANTS`（`age`/`cause`/`mortrate`/`prop`/`location` 五个，**没有 `pop`/`conc`**）。"表格 + `scenario = NULL`"恰好三条都不覆盖，所以连 `Pop`、`population` 也认不出。

因此 B4 不是"补一个年份后缀正则"的小改，而是"长表值列如何认名"的策略拍板，与 B5（`scenario =` 要求各表同名）是同一枚硬币的两面；选项与决策点见下方对话记录（或下一轮的策略说明）。

---

## 补记 3：B4/B5 按"值列选择"契约修复（2026-10-01，取代补记 2 的"待拍板"状态）

用户口径：包只管"一组输入 → 归因负担 / 两组输入 → 分解"，不应判断输入是否属于同一情景/年份，`scenario=` 不应成为跨输入契约。

**新契约（已实现）**

- `scenario=`（以及 `Decomposition()` 的 `from`/`to`）是**逐输入的列选择器**；
- 输入命中该列 → 按原名抽取并规范化；未命中 → 用规范列（`conc`/`pop`/`prop`/`mortrate`）→ 否则用该输入**唯一**的数值非键列并 `message()` 说明用了哪列；`conc` 允许"全部可解析为数字"的字符键列；
- 候选 ≥2 且无规范列 → 报错列出候选（可执行时给 `scenario=` 提示），**绝不猜**；
- 全流程不比较跨输入的情景名/年份，也不做年份一致性告警。

**落点**：`R/utils.R`（`.resolve_case_col()`、`.value_key_cols()`；四个导出的 getter 改用该选择器）、`R/ingest.R`（`.extract_scenario(NULL)` 对每个输入规范化；多问题汇总仍由 `.check_inputs()` 负责，故该路径用 `strict = FALSE`）。

**效果（复核脚本实测）**

- `scenario = NULL`：`Pop2017` / `pop2017` / `pop_2017` / `Population2017` / `total_pop` / `pop_count` / `Pop` / `POP` / `population` 全部可用，结果与规范名列逐值一致；
- 宽表浓度 + 单列 `Pop2017` 人口的混合调用在 `scenario = "baseline"` 下可用（B5）；
- 两列候选（`Pop2015`+`Pop2017`）报 `Value candidates: ...`；
- `Decomposition()` 的辅助表只有单列时，`from`/`to` 两端都用该列，结果与"辅助表两个情景相同"的参照分解全等（新增测试）。

**回归证据**：`devtools::test()` 241 项断言 / 0 失败 / 0 警告 / 1 跳过 / 731 通过；指纹 0 失败；`R CMD check --no-manual` **Status: OK**。文档同步：`NEWS.md`、`README.md`、`AGENTS.md`（数据契约新增"值列选择"行）、`R/AGENTS.md`、`man/`（`getConc`/`getPop`/`getAge`/`getMort`/`Mortality`/`domain_summary`/`Decomposition` 重生成）。

**仍待下一轮**：B6（join 提示刷屏与 `validate="off"`）、B7（域列命名）、B8（README `mort_lvl=NULL` 前提）。

---

## 补记 4：B6/B7 修复（2026-10-01）

- **B6 关闭 join 提示**：新增 `R/utils.R::.left_join_common()`，把「自然 join」的语义写成显式键（`by = intersect(names(x), names(y))`），所有内部自然 join 改走它：`R/Mortality.R` 5 处 `reduce(left_join)` + 1 处 `left_join(PWRR)`、`R/domain-summary.R` 1 处、`R/uncertainty.R::.domain_pwe()` 1 处。实测单次运行、`uncertain + conc_uncert` 链、整包测试输出中的 `Joining with` 行数均为 **0**（修复前测试日志 187+ 行）。
- **B7 统一 `domain_summary()` 域列名**：输出域列固定为 `location`（给定 `mort_lvl` 时用该名）。标签来源不变——`admin_col`/暴露表自己的域列只决定"从哪列取标签"；重命名时连同 `conc_real`/`pop_total` 中同名的键列一起改，并在 message 中说明（`Domain column renamed: iso3 -> location`）。README 国家流程示例已改为直接使用 `ds$location`（去掉手工 `data.frame(location = ds$iso3, ...)`）。
- **新增测试**：`Mortality()` 运行无 `Joining with` 消息（`test-Mortality.R`）；栅格 + `admin_col="iso3"` 不传 `mort_lvl` 时输出列名为 `location`、数值与表格口径一致；暴露表自带 `iso3` 时输出改名为 `location`（`test-domain-summary.R`）。
- **文档同步**：`NEWS.md`（两条 Repair 条目）、`README.md`（安静输出一句 + 国家流程去掉手工改名）、`AGENTS.md` 数据契约新增"域级汇总列名""运行输出"两行、`R/AGENTS.md` 内部契约新增"运行输出洁净""域级汇总列名"两条、`man/domain_summary.Rd` 重生成。

**回归证据**：`devtools::test()` 244 项断言 / 0 失败 / 0 警告 / 1 跳过 / 739 通过；`ATTRMORT_FINGERPRINTS=1` 指纹 0 失败；`R CMD build` + `R CMD check --no-manual` **Status: OK**，且 check 的测试输出中 `Joining with` 行数为 0。

**仅剩**：B8（README `mort_lvl = NULL` 句补前提），按用户安排下一轮处理。
