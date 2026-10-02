# 表侧数据契约校验：真实 GBD 表（261002）

> 主题：把 `validate-data/` 的真实 GBD 死亡表与人口表喂进 `mortality()`，查表侧数据契约
> （列名映射、端点键、年龄键、键唯一性）里没考虑到的情形。
> 本报告的证据全部由本文档末尾的命令在本机复跑得到；未亲手跑过的不写成结论。
> 结论性一句话见第一节；已落地的修复是第二节的 a/b/c 三项**加法**改动，其余进第四节的「需用户拍板」。
> 实现层约定见根 `AGENTS.md` 第三节与 `R/AGENTS.md` 第四节。

## 一、结论摘要

真实 GBD 表在这条管线上一共有四处对不上，其中**两处会静默出错**，一处给出无法照做的报错：

| # | 事实 | 后果 | 本次处理 |
|---|---|---|---|
| F1 | 原始 CSV 的 `age_id` / `cause_id` / `location_id` 抢在 `age_name` / `cause_name` / `location_name` 前面被选中 | 管线拿到的是 IHME 数字编码（age 8、cause 509、location 12），域键也变成数字 ID | **只报告**（列名映射优先级属数据契约，见第四节 Q1） |
| F2 | GBD `cause_name` 是全称，查表端点是短码；8 个 cause 里只有 `Stroke` 能小写命中 `stroke` | 只对上一部分时只 `warn`，运行照常返回**只含 stroke 一列组**的结果：8 个 cause 里 7 个静默不贡献，占六种具体死因负担的 **69.8%** | 落地 c（报错可照做） |
| F3 | `age_name` 是 `"15-19 years"` 这种标签，`.standardize_age_key()` 对字符型原样返回，20 个分层全部穿不过去 | 全是标签时硬 abort 且报错不提"标签"；**混合列时静默丢行**——实测 20 行只活 2 行，丢掉的 18 行占 **99.6%** 死亡数 | 落地 b（标签归一）+ 新增丢弃告警 |
| F4 | GBD 每个 `(location, age, cause)` 每年一行，`mortality()` 没有 year 维度 | many-to-many 扇出 → `pivot_wider()` 出 list-col → 最后在 `sum()` 处以 `invalid 'type' (list) of argument` 崩溃；year 列留着时则静默变成"一格多行" | 落地 a（校验期阻断） |

一句话：**F2 与 F3 的"静默丢失"是这次校验最该记住的两件事**——它们不报错、不警告，用户拿到的是一个看起来正常的宽表，只是少了几列或几行。

## 二、已落地的加法修复（a/b/c）

改动文件：`R/mortality.R`、`R/schema-detect.R`；测试：`tests/testthat/test-validate-contract.R`；
`R/ingest.R`、`R/prepare-inputs.R`、`R/raster-io.R`、`R/decompose.R` 未改。

### a) 键唯一性：校验期阻断（`R/schema-detect.R` 的 `.mort_key_cols()` / `.duplicate_key_problem()`）

判定为**应当阻断**，不是 warn。理由：合法输入不应有重复键——`.left_join_common()`
（`R/utils.R:314-315`）按 `intersect(names(x), names(y))` 做 many-to-many join，重复键必然把骨架扇出；
扇出后 `pivot_wider()`（`R/mortality.R` 的 `.widen_mort()`）要么出 list-col，要么把"一格一行"悄悄变成"一格多行"。
两种后果都不是数据特征，是输入缺陷。

- 键 = `intersect(names(mort_rate), c(names(calc_fild), "endpoint", "age"))`：`mortality()` 把
  `calc_fild` 的列名显式传进 `validate_mortality_input(key_cols =)`，所以"哪几列是键"用的是骨架自己的答案，
  不是猜的。直接调用该函数（测试、`decompose()`）时退化为文档化的域别名，别名一个都没有时用该表全部非值列，
  避免把合法键误判成重复。
- 报错给出四样东西：重复**键数**（不是行数）、涉及**行数**、最多 3 个**样例键**、以及**键内取值不同的列**
  （即用户真正要过滤的那一列，如 `year`）。值列本身不计入"取值不同的列"——它不同是症状，不是过滤依据。
- 实测报错（`validate = "stop"`，China + Stroke + 三年）：

```
mort_rate: 20 duplicated key(s) over (location, age, endpoint): 60 row(s) share a key with another row.
  example key(s): location = China, age = <5 years, endpoint = Stroke | ...
  column(s) that differ inside a duplicated key: none (the rows differ only in
  `mortrate`: the table carries several values per key)
  `mort_rate` must hold one row per key: filter the table to a single year / sex / scenario first.
```

- 边界：`validate = "warn"`（默认）仍只告警、继续算，与既有的 blocking 语义一致（负死亡率、端点全缺也一样）；
  `validate = "off"` 下不报也不拦，这是文档化的逃生口，测试里钉住了这一条。

### b) 年龄标签归一（`R/mortality.R` 的 `.canonical_age_label()` / `.standardize_age_key()`）

只翻译"命名了某个 5 岁分层"的标签：`"<5 years"`/`"under 5"` → `"0"`，`"15-19 years"` → `"15"`，
`"95+ years"` → `"95"`（区间取**下界**，与查表键的定义一致）。严格加法：

- 数值型年龄走原路径（`matchable(x, dgt = 0)`），`25` → `"25"`；字符型 `"25"` 原样返回；
- 不命名 5 岁分层的标签原样返回：`"All ages"`、`"Age-standardized"`、`"1 year"`（单岁标签映射到哪个分层都是猜）；
- 真实 GBD 的 20 个标签**全部**落进查表键：`<5`→0、`5-9`→5、`10-14`→10、…、`90-94`→90、`95+`→95。

同步改了两处使用点，避免"算的时候认、校验的时候不认"：
`validate_mortality_input()` 的 `age_struc` 完整性检查改用同一个归一函数（否则修完仍报
"20 non-standard age group(s)"）。

### c) 端点报错可照做（`R/schema-detect.R` + `R/mortality.R` 的 `.check_endpoint_overlap()`）

改后的 blocking 报错把两侧都摆出来，并说清"改名"是用户的动作：

```
mort_rate: none of the endpoints the model `MRBRT2021` needs (copd, dm2, ihd, lc, lri, stroke)
is present in `endpoint`.
  `endpoint` holds: 509, 294, 322, 493, 494, 976, 426, 409
  AttrMort does not translate disease names: rename the values in `endpoint` to the CRF spelling.
```

部分对上时（更危险的那一半）同样列出"缺哪个查表端点"与"表里现在有什么"；多出来的值仍走 `cli_inform`，
但补上了"若它指的是模型覆盖的疾病，请改成查表拼写"。**没有加任何自动别名表**（见第四节 Q2）。

### 顺带补的一个"不静默"告警

`mort_rate` 里无法归一成标准分层的年龄值，现在会报出来（`"All ages"`、`"Age-standardized"` 这类）：
"unless the CRF defines them, those rows are dropped by the join and contribute nothing"。
这条严格来说是**新增报告**而非修复，但不加它，F3 就仍然只能靠用户自己发现。

## 三、事实与证据

### 数据

| 文件 | 规模 | 关键事实 |
|---|---|---|
| `IHME-GBD_2023_DATA-2cd1e2b2-1.csv` | 90,576 行 × 18 列 | `measure_name` 全为 Deaths、`metric_name` 全为 Rate（即每 10 万）；2018–2020；204 个 location；8 个 `cause_name`；20 个 `age_name` |
| `IHME-GBD_2023_DATA-55b4304b-1.csv` | 90,576 行 | 同上，2021–2023 |
| `IHME-GBD_2021_DATA-cde7454a-1.csv` | 36,720 行 × 14 列 | Population / Number；2013–2021；同 20 个年龄组（204 × 9 × 20） |

原始表头（第 1 行）的列序是 F1 的成因：

```
population_group_id,population_group_name,measure_id,measure_name,
location_id,location_name,sex_id,sex_name,age_id,age_name,
cause_id,cause_name,metric_id,metric_name,year,val,upper,lower
```

`*_id` 列**始终排在** `*_name` 列前面。

### F1 列名映射选中 `*_id`（未修，见 Q1）

```
detect_columns(d, schema = c("age", "cause", "mortrate", "location"))
#          age         cause      location
#     "age_id"    "cause_id" "location_id"
```

去掉 `*_id` 列后同一份表给出 `age_name` / `cause_name` / `location_name`。
成因在 `R/schema-detect.R:71-82` 的 substring 循环：`idx <- which(str_detect(col_lower, fixed(v)))`
命中多列时直接取 `idx[1]`（`R/schema-detect.R:74`、`:77`），于是列序决定语义。

端到端影响（`mortality(mort_rate = <原始 csv 路径>, scenario = "val")`）：

```
[msg]  `mort_rate`: age_id -> age, cause_id -> endpoint, location_id -> location
[warn] mort_rate: 16 age value(s) are not a standard 5-year stratum (1, 11, 12, 13, 14, 16, 17, 18)
[warn] mort_rate: 30,192 duplicated key(s) over (location, age, endpoint): 90,576 row(s) share a key
!! ERROR: Input validation failed: ... - mort_rate: none of the endpoints the model `MRBRT2021`
   needs (copd, dm2, ihd, lc, lri, stroke) is present in `endpoint`. `endpoint` holds: 509, 294, ...
```

值得注意：现在这串报错至少把"表里是 509/294/…"摆了出来；但**管线用错了列**这件事本身，
用户只能从 `Column mapping detected` 那一行里看出来。

### F2 端点：8 个 cause 只有 1 个能进（已修 c）

`cause_name`（8 个）与 `MRBRT2021` 端点（6 个，来自 `inst/extdata/cr_models.json`）：

```
GBD : All causes / Chronic obstructive pulmonary disease / Diabetes mellitus type 2 /
      Ischemic heart disease / Lower respiratory infections / Non-communicable diseases /
      Stroke / Tracheal, bronchus, and lung cancer
CRF : copd / dm2 / ihd / lc / lri / stroke
小写后能对上的： "stroke"   （1 / 8）
```

`validate_mortality_input()` 的判定是"一个都对不上才 blocking"（`R/schema-detect.R:179`，基线行号），
所以这里**只 warn**；`.check_endpoint_overlap()`（`R/mortality.R:870`，基线行号）同理放行。
结果是一个 2 x 18 的宽表，值列只有 `stroke_25 … stroke_95`——**8 个 cause 里 7 个不见踪影，
而这是"成功返回"**。

负担量化（China + India，2018–2020，按 `val / 1e5 × Population` 折算，888 行成功 join）：

| cause_name | 死亡数 | 是否进结果 |
|---|---:|---|
| Ischemic heart disease | 8,770,089 | 否 |
| Stroke | 8,354,737 | **是** |
| Chronic obstructive pulmonary disease | 4,865,327 | 否 |
| Tracheal, bronchus, and lung cancer | 2,110,733 | 否 |
| Diabetes mellitus type 2 | 1,833,119 | 否 |
| Lower respiratory infections | 1,707,741 | 否 |

六种具体死因合计 27,641,746；能进的只有 Stroke 的 30.2%，**被静默丢掉的占 69.8%**。
（同表里 `All causes` 54,707,633 与 `Non-communicable diseases` 42,276,861 是聚合口径，与上面六项重叠，不可相加。）

### F3 年龄标签：20 个分层全部穿不过去（已修 b）

`.standardize_age_key()`（基线 `R/mortality.R:20-22`）对字符型是 `as.character(x)`，实测：

```
.standardize_age_key(unique(d$age_name))
#  <5 years  10-14 years  15-19 years ... 90-94 years   95+ years
# "<5 years" "10-14 years" "15-19 years" ... "90-94 years" "95+ years"   （20/20 原样返回）
```

两条不同的后果，必须分开说：

1. **全是标签时不是静默，是硬 abort**：`.chunkable_ages()`（基线 `R/mortality.R:622-625`）与查表年龄交集为空，
   走不分块路径（`R/mortality.R:713`），最后以
   `No rows survived the join ... and that \`age\` values match the CRF age strata (e.g. 25, 30, 35, 40, 45, ...)`
   结束。报错**没有**提示"你的年龄列是标签、查表要的是下界"。
2. **混合列时是真静默**：把 China 2019 Stroke 表的两个分层手工写成键（`"25"`、`"30"`），其余 18 个保持标签：

```
rows: 20; kept: 2; dropped: 18
deaths carried by kept rows   : 7,789.07
deaths carried by dropped rows: 1,752,615
share silently dropped        : 99.6%
```

   2/20 行进入计算，丢掉的 18 行占 99.6% 死亡数，**全程零告警**——`.validate_mortality_input()`
   只检查 `age_struc` 的年龄（基线 `R/schema-detect.R:206`），从不检查 `mort_rate` 的年龄。

修完后的实测（同一份 China 2019 表）：20/20 标签落进查表键，`No rows survived` 的 abort 消失。

### F4 多年份重复键（已修 a）

两份 2023 文件各含 3 个年份。`scenario = NULL` 时 `.extract_scenario()` 只重命名值列、保留全部列；
`scenario = <列名>` 时 `.slice_mort()`（基线 `R/prepare-inputs.R:431`、`:461`）只留
"键列 + age + endpoint + mortrate"，**year 列被丢掉后三行在键上完全一样**。

最小复现（合成骨架 2 格，见附录命令）：

```
[warn] Values from `attr_mort` are not uniquely identified; output will contain list-cols.
-> returned 2 x 18, 18 列全是 list  （stroke_25: <dbl [3]> ...）
```

`aggregate = "location"` 再往下走一步即崩：

```
!! ERROR: Caused by error in `sum()`: ! invalid 'type' (list) of argument
```

若用户把 year 列留在表里当普通列，`pivot_wider()` 会把它当 id 列：**2 格的骨架返回 6 行**
（3 年各一行），"一格一行"的契约静默失效，且没有任何 list-col 警告。

修完后（`validate = "stop"`）：20 个重复键 / 60 行被阻断并给出样例；
整份原始文件（不按 location 过滤、不按年过滤）会报 30,192 个重复键 / 90,576 行。

### 顺带记录：`max_rate = 5e4` 的默认阈值在真实 GBD 上误报

原始 CSV 会触发 `69 value(s) above 50,000 per 100,000`。这 69 行全部是
`All causes`(41) + `Non-communicable diseases`(22) 的 `95+ years` 与少数 `90-94 years`，
最大值 99,880.58 / 10 万 = 95 岁以上年死亡率 99.9%——**真实且合理**。
阈值本身是告警不是阻断，此处只作记录，不建议改（改它属于口径）。

## 四、需用户拍板（本次**未**实现）

| # | 事项 | 现状 | 备选 | 我的建议 |
|---|---|---|---|---|
| Q1 | `detect_columns()` 对同义字段的优先级 | `age_id`/`cause_id`/`location_id` 因列序靠前被选中（`R/schema-detect.R:71-82` 取 `idx[1]`）；同一份 GBD 表能选到数字编码 | A. 命中多列时**优先字符列**（或 `*_name`/更长名字），并列时再按列序；B. 保持现状，只在选中数值列且存在同义字符列时**告警**；C. 不改 | **A + B**：优先级改动会改变既有输入选到哪一列，必须拍板；无论选哪个，都建议在"选了数值 ID 列"时发一次告警 |
| Q2 | 内置 GBD 全称 → 查表短码别名表 | 用户自己改名，报错只给"需要的查表端点"（本次已改成可照做） | A. 维持"只给指引"（本次已落地）；B. 内置别名表（`Ischemic heart disease`→`ihd` 等 6～7 条） | A。别名表是外部数据的口径，一旦内置就要跟 IHME 的命名走；B 的代价是包开始"认识 GBD" |
| Q3 | 跨输入年份/情景一致性校验 | `scenario=` 是逐输入列选择器，**不判断**跨输入年份是否一致（`AGENTS.md` 第三节明文） | A. 维持现状（本次在 F4 上只阻断"同一输入内的重复键"）；B. 新增"各输入年份列一致"校验 | A。跨输入年份一致性一旦要做，先要定义"年份列"这个新契约 |
| Q4 | `age_struc` 的人口数（Number）自动折算成 `prop` | 现在必须是 `prop`（和≈1），否则告警 | A. 报错并提示"除以合计"；B. 自动折算 | A。自动折算会让"人口数"与"占比"两种含义都合法，静默改变分母 |
| Q5 | 年龄标签归一的范围 | 本次归一了 `"<5 years"` / `"15-19 years"` / `"95+ years"`（含无后缀的 `"15-19"`、`"95+"`、`"under 5"`） | A. 就到这里；B. 再认 `"0-4"`（本次的区间规则已覆盖）、WHO 的 `"0-4 years"`（同样已覆盖）；C. 收窄为只认带 `years` 后缀的形式 | A。当前规则只翻"命名了某个 5 岁分层"的标签，`"All ages"` 一类原样返回并有告警 |
| Q6 | `max_rate = 5e4` 默认阈值 | 真实 GBD 的 95+ 岁 `All causes` 达 99,880 / 10 万，触发误报 | A. 维持；B. 提高阈值或按年龄分层判定 | A。它是 `warn` 不是阻断，且确实抓得住录错单位（例如把 Rate 当 Deaths） |

## 五、门槛与回归证据

全部在本机跑过，原始输出如下（`R = C:\Program Files\R\R-4.6.1\bin\Rscript.exe`）。

1. 基线（改动前、工作区只有 `validate-data/` 未跟踪）：全量测试通过，只有 1 条指纹 skip。

```
$ Rscript -e "devtools::test('D:/GitDir/AttrMort', reporter='summary')"
...
══ Skipped ═══
1. mortality() fingerprints / ... - Reason: set ATTRMORT_FINGERPRINTS=1 to compare (or =update to rewrite)
══ DONE ═══    （exit code 0）
```

2. 指纹不漂移：

```
$ $env:ATTRMORT_FINGERPRINTS=1; Rscript -e "devtools::test('D:/GitDir/AttrMort', filter='fingerprints', reporter='summary')"
fingerprints: ..........................................
══ DONE ═══    （exit code 0，无 F 无 W）
```

3. 新增测试文件：

```
$ Rscript -e "devtools::test('D:/GitDir/AttrMort', filter='validate-contract', reporter='summary')"
validate-contract: ......................Analysis grain: ...
...............
══ DONE ═══    （exit code 0）
```

4. 改动后全量测试（含队友 T1 的栅格线改动）：

```
$ Rscript -e "devtools::test('D:/GitDir/AttrMort', reporter='summary')"
aggregate: ... build-cr: ... cr-config: ... decompose: ... fingerprints: S...
grid-info: ... grid-path: ... mortality: ... prepare-inputs: ... raster-io: ...
review-fixes: ... rr_std: ... schema-detect: ... uncertainty: ... utils: ...
validate-contract: ... validate-ingest: ...
══ Skipped ═══ 1. （指纹，预期）    ══ DONE ══    （exit code 0）
```

数值不变的两条硬证据：
- 指纹测试 42 项全绿，13 条分支的逐列求和与 `tests/testthat/fixtures/fingerprints/` 完全一致；
- `test-validate-contract.R` 里"标签列 vs 键列两次运行结果 `expect_equal`"这条，直接把"归一不改变数值"钉住。

## 六、复跑命令（报告内自足，不依赖临时脚本）

```powershell
$R = 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe'
$env:ATTRMORT_FINGERPRINTS = 1
& $R -e "devtools::test('D:/GitDir/AttrMort', filter='fingerprints', reporter='summary')"
Remove-Item Env:ATTRMORT_FINGERPRINTS
& $R -e "devtools::test('D:/GitDir/AttrMort', reporter='summary')"
```

```r
# F1：列名映射选中 *_id
d <- readr::read_csv("D:/GitDir/AttrMort/validate-data/IHME-GBD_2023_DATA-2cd1e2b2-1.csv",
                     show_col_types = FALSE)
AttrMort:::detect_columns(d, schema = c("age", "cause", "mortrate", "location"), quiet = TRUE)
#   age -> age_id, cause -> cause_id, location -> location_id

# F3：年龄标签
AttrMort:::.standardize_age_key(sort(unique(d$age_name)))   # 修后：0,5,...,95

# F2 + F4：真实表端到端（骨架 2 格）
devtools::load_all("D:/GitDir/AttrMort", quiet = TRUE)
cells <- data.frame(x = c("0", "1"), y = c("0", "0"), location = "China")
conc  <- data.frame(x = c("0", "1"), y = c("0", "0"), conc = c(10, 40))
popg  <- data.frame(x = c("0", "1"), y = c("0", "0"), pop = c(1e5, 2e5))
pop <- readr::read_csv("D:/GitDir/AttrMort/validate-data/IHME-GBD_2021_DATA-cde7454a-1.csv",
                       show_col_types = FALSE)
age_struc <- dplyr::filter(pop, location_name == "China", year == 2019) |>
  dplyr::transmute(location = "China", age = age_name, prop = val / sum(val))
mort <- dplyr::filter(d, location_name == "China") |>
  dplyr::transmute(location = location_name, age = age_name,
                   endpoint = cause_name, mortrate = val)
mortality(crf = "MRBRT2021", calc_fild = cells, conc_real = conc, pop_total = popg,
          age_struc = age_struc, mort_rate = mort, mort_lvl = "location",
          validate = "warn")   # 修前：No rows survived the join（年龄标签）
```

## 七、残余风险与未覆盖

- `decompose()` 没有把 `calc_fild` 列名传进 `validate_mortality_input()`（它不在本线写域内），
  走的是 `.mort_key_cols()` 的退化分支：域别名一个都认不出时用该表全部非值列，因此
  `NAME` / `iso_a3` 这类自定义域列不会被误判成重复；但没有 `mortality()` 那条路径精确。
- `age_struc` 在 `(域, 年龄)` 上重复时同样会扇出，本次**没有**加检查（工单只要求 `mort_rate`）。
  它是同一类缺陷，建议并入 Q1 之后的下一批。
- F1 未修，所以"把原始 GBD 导出的路径直接交给 `mort_rate =`"这条最自然的用法目前仍是失败的；
  可用绕过方式：删掉 `*_id` 列，或把 `age_name` / `cause_name` / `location_name` 改名成规范列名。
