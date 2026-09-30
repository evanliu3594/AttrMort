# audit_code_vs_design_260930 — AttrMort 0.3.0 代码 ↔ 设计审计

> 本文件只增不改：归档后不放回改写；复审另立新文件，或在文末追加“补记”章节（注明日期与触发原因）。文末补记追加于同日（2026-09-30），触发原因见该节。

- **审核日期 / 范围**：2026-09-30，只读审计。对象为本地工作树 `main` @ `cd3a374`（AttrMort 0.3.0）：`R/` 下 15 个文件、`tests/testthat/` 12 个测试文件 + `helper-data.R`、`AGENTS.md`、`R/AGENTS.md`、`DESCRIPTION`、`NEWS.md`、`README.md`、`data/` 下 9 张内置查表、`inst/extdata/` 下 6 个示例文件。审计期间未修改仓库（`git status --porcelain` 为空）。
- **方法**：静态通读（职责表、七阶段、三分支、数据契约逐条对照）；重跑验证（`devtools::test()`、指纹回归、`R CMD build` + `R CMD check`）；微型 V1 复算（自建 2 波段栅格 NA 探针、13 模型 × 3 CI 查表探针、181 处原生管道 AST 检查、示例数据包外复现并逐单元格比对）；独立对照（后台子代理独立重跑同一套验收，分歧项另行复测）。
- **对照基准**：仓库根 `AGENTS.md` 与 `R/AGENTS.md`（HEAD `cd3a374` 版本，2026-09-30 读取）；`DESCRIPTION` 0.3.0；`NEWS.md` 0.3.0；`README.md`。基准自身即为本次审计的对象之一，版本以本行日期为准。
- **结论**：**通过但有条件**。三条不可退让性质（污染物无关、输入无关、状态无关）与数据契约均有实现和测试证据；验收门槛达标（测试 0 失败；`R CMD check` 为 `Status: OK`，0 error / 0 warning / 0 note）。**无 Blocker**；4 项 Must-fix、12 项 Info。另有仓库分叉（本地 `main` 与 `origin/main` 无共同祖先）需用户决策，属仓库状态问题而非代码问题。
- **复现脚本**：`diagnosis/tmp_audit_checks.R`（本次审计的全部微型复算，包外运行、不写仓库）。原始日志：`%TEMP%\attrmort-audit\`（含 `01_full_test.log`、`02_fingerprints.log`、`build.log`、`check.log`、`AttrMort.Rcheck/`）。

## 一、验收证据锚点（V1，均可复算）

| 检查 | 命令 | 实测值 |
|---|---|---|
| 全量测试 | `Rscript -e "devtools::test()"` | `[ FAIL 0 \| WARN 11 \| SKIP 1 \| PASS 491 ]`，90.0 s；11 条 WARN 全部为未捕获的刻意提示（小 fixture 年龄组不足、`mort_lvl = NULL` 等），非断言失败 |
| 指纹回归 | `ATTRMORT_FINGERPRINTS=1` + `devtools::test(filter = "fingerprints")` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 42 ]`；13 条分支 × 3 断言 + 示例数据自洽 3 条 |
| 构建 + 检查 | `R CMD build` → `R CMD check --no-manual --no-build-vignettes`（包外临时目录） | `Status: OK`；0 ERROR / 0 WARNING / 0 NOTE；唯一 INFO 为安装体积 8.7 MB（`data/` 8.0 MB） |
| 文档同步 | 包外副本 `roxygen2::roxygenise()` 后 diff | `NAMESPACE`、`man/` 与仓库逐字节一致 |
| 示例数据自包含 | 包外重跑 `data-raw/make-example-data.R` 后与 `inst/extdata/` 逐单元格比对 | 6 个 xlsx 的 dim / names / values 全部一致；国级人口 = 网格合计 = 80,192,440 |
| 构建排除 | `tar -tzf AttrMort_0.3.0.tar.gz` | `AGENTS.md`、`R/AGENTS.md`、`data-raw/` 均不在包内 |
| 仓库完整性 | 验收前后文件清单 + `git status` | 626 项清单一致；工作区干净 |
| 运行环境 | `R.version` | R 4.6.1 (2026-06-24 ucrt) x86_64-w64-mingw32；roxygen2 8.1.0；testthat 3.3.2；terra 1.9.50 |

## 二、设计目标落实情况（逐条对照）

### 1. 污染物无关 —— 落实

- 注册表 13 个模型名映射 9 张查表：`R/RR_std.R:10-24`。
- 计算核 `.calc_attributable()` 不区分模型/污染物，只消费 `RR_std()` 或用户 `data.frame`：`R/Mortality.R:819-916`；用户自带 CRF 有测试：`tests/testthat/test-Mortality.R:73`。
- `.CR_ENDPOINTS` 13 项与 `RR_std()` 的 reshape 分支一一对应，由 `tests/testthat/test-schema-detect.R:86` 钉住。

### 2. 输入无关 —— 落实

- data.frame / CSV / Excel / GeoTIFF / netCDF / `SpatRaster` 同一套摄取路径：`R/ingest.R:43-64`；`SpatRaster` 直传有守卫：`R/raster-io.R:30`。
- 单波段栅格自动命名 `conc`/`pop`：`R/ingest.R:157-176`；宽表按 `scenario=` 转长表：`R/ingest.R:304-331`；数值坐标键按 `dgt_coord` 规范化：`R/ingest.R:72-91`。
- 覆盖测试：`test-grid-path.R`（栅格可省 `calc_fild`、单波段、netCDF）、`test-raster-io.R`、`test-Mortality.R:40`（宽/长等价）。

### 3. 状态无关 —— 落实

- `R/` 中无 `assign()`、无 `setwd()`、无 `options()` 副作用；唯一的 `<<-` 为 `validate_mortality_input()` 内部闭包对局部收集向量的追加：`R/schema-detect.R:127-136`，不构成全局状态。
- 非交互会话不 `readline()`：`R/raster-io.R:352-368`；>1e9 格直接拒绝：`R/raster-io.R:333`。
- 路径一律参数传入；`DESCRIPTION` 的 Imports 与 roxygen 导入成对，`NAMESPACE` 由 roxygen 重生成逐字节一致。

### 4. 数据契约 —— 落实，一处原始表例外（见 MF-2）

- 浓度键：`RR_std()` 强制字符 + `dgt`：`R/RR_std.R:198-200`；暴露侧数值转字符：`R/utils.R:141`、`R/ingest.R:310-318`。
- 坐标键、年龄、1e5 单位、`{endpoint}_{age}` 从右切、CI 标签：`R/utils.R:113-115`、`R/Mortality.R:20-22`、`R/aggregate.R:41-57`、`R/RR_std.R:36-51`。
- 实测 9 张内置表：8 张 `conc` 为 character 且固定 1 位小数；NO<sub>2</sub> 原始表为 double（见 MF-2）。

### 5. 口径 —— 落实

- `mort_lvl` 决定校准域、`conc_cf` 决定风险项：`R/Mortality.R:861-880`。
- 域级中心估计 = 网格级结果按域求和：`R/Mortality.R:628-644`；PWRR 经 `.domain_pwe()` 与域汇总共用：`R/domain-summary.R:241-255`。
- 不确定性为 range（逐格共模求和）：`R/uncertainty.R:48-68`；`conc_uncert` 重跑两条链取并集：`R/Mortality.R:582-606`。
- 年龄分块数值精确等价（含列序还原）：`R/Mortality.R:755-813`；测试：`test-grid-path.R:241-294`。
- 网格一致性检查（0 命中报错 / 部分命中告警 / `validate = "off"` 静默）：`R/Mortality.R:96-133`；测试：`test-grid-info.R:175-243`。

### 6. 文档与发布一致性 —— 落实

- 16 个导出 = 16 个 `man/` 函数页；内部函数无页面（roxygen 重生成零差异）。
- 示例数据仅来源于仓库内脚本，内置查表为唯一外部发表内容，符合自包含约定。

## 三、问题清单与修复落点

分级依据：Blocker = 结果口径错误/违反契约、下游不得采信；Must-fix = 不改数值但误导解读或有验证缺口；Info = 记录在案。

### Blocker

无。

### Must-fix

| 编号 | 位置（文件:行号） | 事实（看到什么） | 依据与影响 | 修复落点 |
|---|---|---|---|---|
| MF-1 | `R/raster-io.R:50`（配合 `R/ingest.R:181-237`） | 多波段栅格走 `terra::as.data.frame(..., na.rm = TRUE)`，terra 对多层栅格按“任一层 NA 即删行”。实测 2×2 两波段、第 2 波段仅缺 1 格 → `raster_to_grid()` 返回 3 行；单波段同数据返回 4 行 | 与 `AGENTS.md` 数据契约“网格由 `conc_real` 唯一确定”、多情景同一网格的口径冲突；基准情景会因另一情景缺测而丢格，且与表格路径（逐情景保留 NA）行为不一致 | 先拍板：保留共同掩膜则在 `AGENTS.md` 数据契约写明并补测试；逐情景保留则改 `R/raster-io.R:50` 的 NA 策略并在抽取/计算层处理。测试落点 `tests/testthat/test-raster-io.R` |
| MF-2 | `data/NO2_CR_Lookup_Table.rda`（契约见 `AGENTS.md` 第三节） | 实测 NO<sub>2</sub> 原始表 `MEAN$conc` 为 double，范围 2–80、步长 0.1、带 1e-12 级浮点尾差（最大 \|conc×10 − round(conc×10)\| = 3.07e-12）；其余 8 张表均为 character、1 位小数、无噪声 | 契约要求“暴露数据与查表都必须遵守”字符键；用户侧因 `R/RR_std.R:198-200` 统一归一而不受影响，但原始对象不满足契约字面要求 | 重存 NO<sub>2</sub> 表为字符键，或在 `AGENTS.md` 契约中限定“经 `RR_std()` 渲染后的键”；同步 `tests/testthat/test-RR_std.R`（原始表契约断言） |
| MF-3 | `R/DrivingFactors.R:81`，`tests/` 全域 | `Decomposition()` 是 16 个导出 API 之一、README 核心函数，但 `grep -rn "Decomposition" tests/` 为 0；`R/AGENTS.md` 第六节测试矩阵也无它 | 24 种排列的分解无任何回归装置，数值路径变更无法被发现 | 新建 `tests/testthat/test-Decomposition.R`（手算小 fixture：排列顺序 + 单驱动差分）、`R/AGENTS.md` 第六节同步 |
| MF-4 | `R/AGENTS.md:13` | 职责表把 `.standardize_age_key()` 记在 `utils.R`，实际定义于 `R/Mortality.R:20` | 实现层顶层约定与代码不符，后续 agent 按表找函数会找错文件 | 更正表项 |

### Info

| 编号 | 位置 | 事实 | 处置建议 |
|---|---|---|---|
| I-1 | 测试套件 | 11 条 WARN 为未用 `expect_warning()`/`suppressWarnings()` 收干净的刻意提示，长期会掩盖新增真实警告 | 顺手收口，保持“全绿”信号干净 |
| I-2 | git 状态（非代码） | 本地 `main`（单条 squash 提交 `cd3a374`）与 `origin/main`（Phase 1–7 共 14 条提交）无共同祖先（`git merge-base` 为空）；`origin/master` 停在 `b73d75f`；本地 0.3.0 未推送。基于本地 tracking refs，未联网 fetch | 发布/协作前与用户确认推送策略（force push 新历史 vs 在远端历史之上重建） |
| I-3 | `R/utils.R:45` | 错误提示写死“`xy` argument”，但 `getAge()`/`getMort()` 的参数名是 `loc`（实测两者报错都提示 `xy`） | 按调用者参数名提示，或改为“键列参数” |
| I-4 | `R/utils.R:4-8` | `.COORD_VARIANTS` 中 `"lat"` 重复出现 | 去重 |
| I-5 | `R/ingest.R:24`、`R/ingest.R:95` | 内部默认 `dgt_coord = 1` 与包默认 2 不一致（公开 API 均显式传值，不可达） | 统一默认值或去掉默认 |
| I-6 | `tests/testthat/fixtures/fingerprints/` | 13 条指纹分支未含 IER2010、IER2013、MRBRT2021 的端到端跑（`RR_std()` 层已覆盖） | 视需要补齐端到端分支 |
| I-7 | `tests/testthat/_snaps/` | 未受控空目录残留（`R CMD build` 自动剔除，不进构建） | 删除该空目录 |
| I-8 | `R/batch.R:12-13,43` | 文档要求先设 `future::plan()`，`future` 未列 Suggests（示例在 `\dontrun{}` 内，`R CMD check` 无碍） | 在 DESCRIPTION 补 Suggests 或在文档注明为 furrr 的运行前提 |
| I-9 | `R/ingest.R:310-318` | 字符型 `conc` 列被原样信任、不按 `dgt_conc` 重渲染（数值型会渲染） | 符合契约字面（精度由用户保证），建议 README 明说 |
| I-10 | `data/IER2010/2013/2015/2017_*_Lookup_Table.rda` | 四张表的 `conc` 按字符串字典序存储而非数值序（形如 `"1.9", "10", "10.1", …`）。实测相邻降序步 18/18/18/27（IER2017 断点索引 130, 240, 350, …）；后台代理按另一计数口径得 38/38/38/57，口径不同、定性一致 | 主管线一律按键 join，数值结果不受影响；任何按行序/数值区间取行的下游消费会错位。建议重排为数值序存储，或在 `R/data.R` 文档写明“行序为字典序，请按键连接” |
| I-11 | `data/MRBRT2021_Lookup_Table.rda` | 顶层类为 `vctrs_list_of/vctrs_vctr/list`，对其取不存在的字段（如 `tab$conc`）直接抛错而非返回 `NULL`；`tab$MEAN` 读取正常 | 在 `R/data.R` 的 `@format` 写明结构为 `list(MEAN, LOW, UP)`，各元素为 wide tibble |
| I-12 | 构建信息 | `R CMD check` 唯一 INFO：安装体积 8.7 MB（`data/` 8.0 MB） | 记录在案；若未来要求更小安装体积可压缩查表 |

## 四、审计自身的验证与限制

- **反向复核**：全量测试与指纹回归由后台代理独立重跑，结果一致（491 PASS / 42 PASS / Status: OK）。
- **分歧项复测**：IER 四表排序断点数两方口径不同（18/18/18/27 vs 38/38/38/57），以本报告可复算的“相邻降序步”为准；两方均确认字典序存储这一事实。
- **探针纠错**：后台代理第一次查表探针把 `list(MEAN/LOW/UP)` 当扁表用而失败，已改用 `tab$MEAN$conc` 复测（并在 `tmp_audit_checks.R` 中保留正确写法）。
- **限制**：未联网 fetch，仓库分叉结论基于本地 remote-tracking refs；未在 Linux/CRAN 环境跑 `--as-cran`；未做真实大数据量（0.1° 全球）内存实测，chunk 设计的容量声明只经代码静态核对。

## 补记（2026-09-30，触发原因：后台验收最终报告回传与两处新事实）

- 确认最终验收：`FAIL 0 / WARN 11 / SKIP 1 / PASS 491`；指纹 `PASS 42`；`R CMD check` `Status: OK`（0/0/0，唯一 INFO 为 `data/` 8.0 MB）；check 内测试结果与独立运行一致。
- 新增 I-10（IER 四表字典序存储）与 I-11（MRBRT2021 的 `vctrs_list_of` 结构）；MF-2 补充浮点尾差量化（3.07e-12）。
- 本次落盘同时新增 `diagnosis/` 目录与 `diagnosis/tmp_audit_checks.R`，并在 `.Rbuildignore` 增加 `^diagnosis$`，保证包构建与 `R CMD check` 的 0/0/0 不受影响；该改动后重新跑过完整验收（见 `HISTORY` 无、以本补记与 git 工作树为准）。
- **归档过程事故与恢复（如实留痕）**：`tmp_audit_checks.R` 首次运行时，D 段子进程继承了仓库工作目录，`make-example-data.R` 的相对路径把 `inst/extdata/` 6 个 xlsx 重写了一遍（数值逐位相同，字节因 zip 元数据不同而变化）。已用 `git restore -- inst/extdata` 从 HEAD 恢复并确认无差异；脚本已修为在 `setwd(tempdir())` 下运行生成器。此后完整复跑脚本 5 项检查全过（0 failure），未再触碰仓库。

## 补记二（2026-09-30，触发原因：用户指示推进 M1–M4 修复）

**拍板与范围。** M1 由用户裁定：理论上不应存在只在部分情景有值的网格，遇到应告警。实现取“保持同一网格 + 部分缺测格剔除 + 告警列出各层缺测数”，并把该契约写入 `AGENTS.md`（数据契约新增“多情景栅格掩膜”行）与 `R/AGENTS.md`（内部契约）。版本与 `NEWS.md` 按用户选择**未动**——这与 `R/AGENTS.md` 第五节“改口径或数据契约须同步 `tests/` 与 `NEWS.md`”的既有约定存在偏差，后续发布前需补记一条修复说明。

**修复明细**（原问题条目保留，状态由本补记更新）：

| 编号 | 状态 | 修复落点 | 内容 |
|---|---|---|---|
| MF-1 | 已修 | `R/raster-io.R`（`raster_to_grid()`） | 改为读入全部像元后检测“只在部分层有值”的格：有则告警（含层名与各层缺测数），完整格才进分析网格；单波段 NA 行为不变。契约与 3 个测试（告警+剔除、共同掩膜静默、单波段静默）落 `AGENTS.md`、`R/AGENTS.md`、`tests/testthat/test-raster-io.R` |
| MF-2 | 已修 | `data-raw/normalise-lookup-keys.R`、`data/NO2_CR_Lookup_Table.rda` | 新增幂等脚本把 `conc` 规范为 `dgt = 1` 字符键并重存 NO<sub>2</sub> 表（xz / version 3 不变）；原始表实测 `"2","2.1",…`。`tests/testthat/test-RR_std.R` 新增“原始表字符键与 1 位小数”契约测试（9 表 × 3 分支） |
| MF-3 | 已修 | `tests/testthat/test-Decomposition.R`（新增，6 用例） | 24 种排列映射、起止点与单情景 `Mortality()` 逐行一致、单驱动差分等于前缀运行之差、望远镜加和跨排列不变、CI 分支透传、非法 `serie` 报错；`R/AGENTS.md` 测试矩阵同步 |
| MF-4 | 已修 | `R/AGENTS.md:13` | `.standardize_age_key()` 从 `utils.R` 行移到 `Mortality.R` 行（定义处 `R/Mortality.R:20`） |

**修复后验收（V1）。**

| 检查 | 结果 |
|---|---|
| `devtools::test()` | `FAIL 0 / WARN 11 / SKIP 1 / PASS 575`（WARN 数与修复前相同，未新增噪声；PASS +84） |
| 指纹回归 | `FAIL 0 / PASS 42`，参照未变 |
| `R CMD build` + `R CMD check` | `Status: OK`（0 ERROR / 0 WARNING / 0 NOTE；唯一 INFO 为安装体积 8.7 MB） |
| `RR_std("NO2", MEAN/UP/LOW)` 修复前后 | `all.equal` 三者均 `TRUE`（数据表示改变、输出逐位不变） |
| `diagnosis/tmp_audit_checks.R` 复跑 | 5 项全过（0 failure），其中 B 断言 9 张原始表均为字符键、C 断言掩膜不一致告警且单波段不告警 |

**仍未处理**：I-1 至 I-12（含 I-3 报错文案、I-10 IER 四表字典序存储、I-11 `MRBRT2021` 的 `vctrs_list_of` 结构、I-2 仓库分叉）；不在本次 M1–M4 范围。改动尚未提交，git 工作树见本次会话记录。

## 补记三（2026-09-30，触发原因：Info 逐条拍板 + 用户澄清重构意图）

**背景澄清。** 用户说明本轮工作的本意是**基于 `D:\GitDir\PM2.5-attr-mort` 重新设计的 JSON C-R 配置做根本重构**。经核对，本轮改动触及 CRF 层的仅限**查表存储与键契约**（MF-2/I-10/I-11 的 `data/*.rda`、I-9 的键校验），核心符号 `.CR_TABLE_REGISTRY`、`RR_std()` 的 reshape 分支、`.CR_ENDPOINTS`、`build_cr_table()` 均未改动。用户选择先收口 0.3.x、再启动迁移设计；MF-2/I-10/I-11 保留但**标注为过渡**，迁移后其存储实现将被 “JSON + xlsx” 替换（契约应继承：字符键、数值升序、普通 list）。

**Info 拍板（面板确认）。**

| 条目 | 决定 | 实施 |
|---|---|---|
| I-1 | B+A | `.extract_scenario()` 调 `getAge(min_age_groups = 0)`（validate 阶段已查年龄，不再重复告警）；其余测试按期望警告收口 |
| I-2 | A | 本地 `archive/pre-0.3` 标签存档 `origin/main`；推送/改远端见提交后的操作记录 |
| I-3 | A | `.resolve_key_cols(key_arg=)`：getConc/getPop 提示 `xy`，getAge/getMort 提示 `loc` |
| I-4 | A | `.COORD_VARIANTS` 去重（删多余 `"lat"`） |
| I-5 | A | `.ingest_single_input()`/`.ingest_and_map()`/`raster_to_grid()`/`shapefile_to_grid()` 的坐标默认统一为 `dgt = 2` |
| I-6 | C | 不动（不补 IER2010/2013 指纹分支） |
| I-7 | A | 删除空目录 `tests/testthat/_snaps/` |
| I-8 | D | **破坏性**：删除 `R/batch.R`（`Mortality_batch()`、`combine_batch()`），移除 `furrr` Suggests、导出、man 页、README/DESCRIPTION 引用；`NEWS.md` 与版本按用户既有指示未动 |
| I-9 | A（暂缓 ×10 整数键） | 新增字符 `conc` 非规范键校验告警（`validate_mortality_input(dgt_conc=)`，受 `validate="off"` 控制）；×10 整数键方案实测 2.8% 暴露值舍入节点变化、约 35 处触点、失去 < 0.1 步长支持，登记为迁移设计议题 |
| I-10 | A | `normalise-lookup-keys.R` 增加数值升序重排；IER 四表重存（排序后逐行与旧表一致，`RR_std()` 行序变化、数值不变） |
| I-11 | A | MRBRT2021 重存为普通 `list`；`R/data.R` 九张表补 `@format` 结构说明 |
| I-12 | A | 记录不动（安装体积 8.7 MB，data 8.0 MB） |

**收口验收（V1）。**

| 检查 | 结果 |
|---|---|
| `devtools::test()` | `FAIL 0 / WARN 0 / SKIP 1 / PASS 621`（WARN 清零；I-6 决定不补分支） |
| 指纹回归 | `FAIL 0 / WARN 0 / SKIP 0 / PASS 42` |
| `R CMD build` + `R CMD check` | `Status: OK`（0 ERROR / 0 WARNING / 0 NOTE；check 内测试 621 PASS） |
| `diagnosis/tmp_audit_checks.R` | 6 组检查 0 failure（A 管道、B 查表契约、C 掩膜、D 示例数据复现、E 报错文案、F 非规范键告警） |
| I-10/I-11 数据前后对比 | 排序后逐行 `all.equal` 全 TRUE；`RR_std()` 数值不变（IER 行序变化、MRBRT2021 完全不变） |

**破坏性变更（单独列出）**：移除 `Mortality_batch()` 与 `combine_batch()`。受影响者：0.2.0 起使用这两个函数、或依赖 `furrr` 并行批处理的调用方；替代方式为对 `scenario` 逐个调用 `Mortality()` 后自行合并。按用户指示未写 `NEWS.md`，发布前需补记。

**下一步**：在迁移设计分支中输出《PM2.5-attr-mort v5 → AttrMort 迁移设计》，覆盖 JSON schema、状态/路径去全局化、`RR_std()` 接口适配、口径保留清单（range、PWRR、分解 serie）、废弃清单（`.CR_TABLE_REGISTRY`/reshape 分支/`.CR_ENDPOINTS`/`data/*.rda` 与 I-9 的整数键提案）。
