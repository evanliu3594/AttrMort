# 独立验证（T5）：四道门槛、交叉核对与反例抽检

> 负责人：`verify-gates`（T5，独立验证者，不参与实现、不改他人文件）。
> 本文件只写**我亲手跑出来的**数字；凡是引用他人实测而我没有复跑的，一律标注"未独立复核"。
> 验收门槛的权威做法见仓库根 `AGENTS.md` 第五节，测试装置见 `R/AGENTS.md` 第六节。

## 〇、一句话结论

**四道门槛全部通过**：`devtools::test()` = `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1038 ]`（139.8 s）；指纹 = `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 42 ]`（14.9 s，参照文件自 `05f538c` 起未被改动）；`R CMD build` + `R CMD check --no-manual`（带 vignette）= `Status: OK`（0 error / 0 warning / 0 note）；仓库洁净、临时产物全部在仓库外。全部门槛跑在**同一个冻结代码面**上（`R/*.R` 的 MD5 前后一致，见第一节）。

我的反例抽检（5 组 P1–P5、共 54 条断言：49 通过 / 5 失败，全部由我自己写代码、独立于作者）**发现 1 个此前四份报告都没有记录的真实缺陷**：T2 的年龄标签归一在年龄列含 `NA` 时以 `missing value where TRUE/FALSE needed` 崩溃（单元与端到端都复现，5 条失败断言全是这一个根因，见第五节）。这条不在四道门槛的覆盖范围内（门槛全绿），但会让含缺失年龄的真实表从一个"静默丢行"变成"cryptic 崩溃"。

---

## 一、冻结状态与"是否作废"的判定

门槛必须跑在一个**冻结且已提交**的代码面上，否则验的是混合状态。实际时间线：

| 时刻 | 事件 | 出处 |
|---|---|---|
| 15:19 | 我开始核对：`git rev-parse HEAD` = `96b762dd842c56e641db4aff4e01c4bff6d9e6ce`，`git diff HEAD --stat` 为空，`git status --short` 只有两个未跟踪的 diagnosis 报告 | 我实测 |
| 15:19:57 | 启动 `devtools::test()`；15:20 启动 `R CMD build` | 后台作业 |
| 15:21:05 | tarball 生成（`AttrMort_0.3.0.tar.gz`，8,882,404 B） | 文件 mtime |
| 15:23:44 | `f1dee26 docs(diagnosis): 规模与性能验证报告…`，**只动 `diagnosis/validate_scale_perf_261002.md`（1 file changed, 511 insertions）** | `git show --stat f1dee26` |
| 15:2x | 三项门槛先后完成 | 见第二节 |
| 稍后 | `a20d736 docs(diagnosis): 真实数据校验的任务书、判定队列与 Lead 独立复核`，**只动 `diagnosis/validate_real_data_scope_261002.md`（1 file changed, 122 insertions）** | `git show --stat a20d736` |

**判定：没有任何门槛被作废。** 依据三条，都可复核：

1. `f1dee26` 与 `a20d736` 都只改 `diagnosis/`，而 `.Rbuildignore` 含 `^diagnosis$` —— 我实测 `tar -tf AttrMort_0.3.0.tar.gz` 里 `diagnosis` 与 `validate-data` 的条目数均为 **0**，故这两个提交在原理上无法改变构建产物。
2. **自冻结代码面以来，包内一个文件都没被改过**（这条是最直接的证明，跑在收官时刻）：

   ```powershell
   git diff --stat 96b762d HEAD -- . ':(exclude)diagnosis'   # 输出为空
   ```

3. 代码面 MD5 前后逐位相同（15:20 记录 vs 门槛跑完后复取，收官时刻再次复核仍相同）：

| 文件 | MD5（15:20 记录、门槛结束后、收官时刻三次一致） |
|---|---|
| `R/raster-io.R` | `2E85A19C48D86241CBF6A96D99655AAD` |
| `R/prepare-inputs.R` | `B550F5F803A17B2773BC31C7845B05B3` |
| `R/mortality.R` | `9C47EF63189B7F0D2610BB67AF9BDD18` |
| `R/schema-detect.R` | `70B0C866BBDCF0199E66A9AA034ADD68` |
| `R/ingest.R` | `A5287B9780973B999F79F49C782442F5` |

### 交接简报里两条已被推翻的说法（供留档）

1. **"T4 还有一批未提交的 F3 改动在 `R/raster-io.R`"** —— 不成立。`git log -S 'same.crs' -- R/raster-io.R` 只命中 `0113201`，且 `0113201` 是 `96b762d` 的父提交；`git status` 对 `R/` 干净。Lead 随后已自我更正。
2. **"`validate = "warn"` 会因负浓度直接阻断"** —— 不成立。`validate = "warn"` 下带 2 个 `-999` 的栅格**运行成功并返回结果，只发警告**；只有 `"stop"` 才阻断。我的 P1g 实测支持 T1 §2.1 与 T2 §2a 的说法（详见第四节的矛盾清单第 1 条）。

---

## 二、四道门槛的原始输出

### (a) `devtools::test()` 全绿

```
HEAD_AT_START=96b762dd842c56e641db4aff4e01c4bff6d9e6ce
ℹ Testing AttrMort
✔ | F W  S  OK | Context
...
══ Results ═════════════════════════════════════════════════════════════════════
Duration: 139.8 s

── Skipped tests (1) ───────────────────────────────────────────────────────────
• set ATTRMORT_FINGERPRINTS=1 to compare (or =update to rewrite) (1):
  'test-fingerprints.R:60:5'

[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1038 ]
TESTS_EXIT=0
```

- **用例总数 1038，失败 0，警告 0，跳过 1**，退出码 0。
- 唯一跳过项是默认关闭的指纹比对（`test-fingerprints.R:60:5`），**预期**：它在 (b) 里单独打开。
- 逐文件 OK 数（我自己加总，等于 1038）：aggregate 73、build-cr 42、cr-config 72、decompose 156、fingerprints 3（+ 1 skip）、grid-info 55、grid-path 32、mortality 35、prepare-inputs 36、raster-io 50、review-fixes 26、rr_std 199、schema-detect 24、uncertainty 37、utils 39、validate-contract 57、validate-ingest 25、validate-numeric 41、validate-pop-conservation 36。

### (b) 指纹不漂移（13 条分支）

```
HEAD_AT_START=96b762dd842c56e641db4aff4e01c4bff6d9e6ce
✔ |         42 | fingerprints [14.9s]

══ Results ═════════════════════════════════════════════════════════════════════
Duration: 14.9 s

[ FAIL 0 | WARN 0 | SKIP 0 | PASS 42 ]
FP_EXIT=0
```

**参照文件没被本次改过 —— 用 git 证明（三条独立证据）：**

| 证据 | 命令 | 结果 |
|---|---|---|
| 该目录最后一次改动 | `git log -1 --format='%h %ad %s' --date=short -- tests/testthat/fixtures/fingerprints/` | `05f538c 2026-10-02 refactor(structure): 抽出共同前置模块…` |
| 本次校验区间内无改动 | `git diff --stat 9e85713 HEAD -- tests/testthat/fixtures/` | 空 |
| 工作区干净 | `git status --short -- tests/testthat/fixtures/` | 空 |

参照目录 13 个文件（`crf-5COD.csv`、`crf-GEMM.csv`、`crf-IER.csv`、`crf-IER2015.csv`、`crf-IER2017.csv`、`crf-MRBRT.csv`、`crf-MRBRT2019.csv`、`crf-NCD+LRI.csv`、`crf-NO2.csv`、`crf-O3.csv`、`gemm-concCF.csv`、`gemm-lvlMissing.csv`、`gemm-lvlNULL.csv`），与 `R/AGENTS.md` 第六节记的 13 条分支对应。

### (c) `R CMD check` = `Status: OK`

两步法、带 vignette、产物在 `%TEMP%\attrmort-check`：

```
* creating vignettes ... OK
* checking for empty or unneeded directories
Removed empty directory 'AttrMort/vignettes/.quarto'
* building 'AttrMort_0.3.0.tar.gz'

BUILD_EXIT=0
* using log directory 'C:/Users/Evan/AppData/Local/Temp/dsh-ScshDe/attrmort-check/AttrMort.Rcheck'
* this is package 'AttrMort' version '0.3.0'
...
* checking tests ...
  Running 'testthat.R'
 OK
* checking for unstated dependencies in vignettes ... OK
* checking package vignettes ... OK
* checking re-building of vignette outputs ... OK
* DONE

Status: OK

CHECK_EXIT=0
```

**0 error / 0 warning / 0 note 的直接证据**：对整份 check 日志做 `Select-String -Pattern '^\*.*(WARNING|NOTE)'`，**命中 0 行**；`^Status:` 只有一行，值为 `OK`。

vignette 确实参与了构建：日志有 `* creating vignettes ... OK`，且 `tar -tf` 里 `inst/doc` 条目数为 **4**（若用 `--no-build-vignettes` 这里会是 0，并必然报那 2 个 WARNING）。

**一个必须说明的坑（否则会误读日志）**：日志里出现了大量 `Warning:` 行，但它们**不是** `R CMD check` 的 WARNING，而是沙箱环境造成的 R 层警告，且都在 `* checking` 状态行之外：

```
Warning: unable to access index for repository https://CRAN.R-project.org/src/contrib: ...
Warning in system2("du", "-k", TRUE, TRUE) : running command '"du" -k' had status 322
Warning in Sys.junction(from, to) : cannot set reparse point '...RLIBS_.../cli', reason '拒绝访问。'
```

前者是网络被沙箱拦（无法访问 CRAN 索引），后者是沙箱不允许建 junction，`du` 返回 322。它们都没有升级成 `checking ... WARNING/NOTE`，所以 `Status: OK` 成立。这一点值得写进门槛模板，避免下一个人看到满屏 `Warning:` 就以为门槛没过。

### (d) 仓库洁净与"临时产物不出仓库"

```
$ git status --short
?? diagnosis/validate_real_data_scope_261002.md

$ git status --short --ignored
?? diagnosis/validate_real_data_scope_261002.md
!! validate-data/
```

- **没有任何 modified 的已跟踪文件**；`validate-data/` 被 `.gitignore` 忽略（预期）。
- 唯一未跟踪文件是 **Lead 自己的**汇总报告 `diagnosis/validate_real_data_scope_261002.md`（`diagnosis/` 在 `.Rbuildignore` 内、不入构建）。这不是我造的，也不是"仓库不干净"。
- 仓库内搜 `*.tar.gz`、`*.Rcheck`、`*.rds`、`*.log`（排除 `validate-data/`）：**0 命中**。
- 顶层目录只有标准包结构：`data/ data-raw/ diagnosis/ inst/ man/ R/ tests/ validate-data/ vignettes/` + `.gitattributes .gitignore .Rbuildignore AGENTS.md DESCRIPTION LICENSE NAMESPACE NEWS.md README.md`。
- 我的全部临时产物在仓库外：tarball 与 `.Rcheck` 在 `%TEMP%\attrmort-check\`，日志在 `%TEMP%\attrmort-t5-*.log`，抽查脚本在 `%TEMP%\t5-verify\`。

---

## 三、反例抽检（自己写代码，独立于作者）

脚本（包外，可复跑）：

```powershell
C:\Program Files\R\R-4.6.1\bin\Rscript.exe "$env:TEMP\t5-verify\probe-T1.R"
C:\Program Files\R\R-4.6.1\bin\Rscript.exe "$env:TEMP\t5-verify\probe-T2.R"
```

四条抽检针对本次新落地的行为，**每条都用作者之外的方式构造输入**：内部函数直接喂自造 data.frame；端到端用我自己的 4 格合成栅格（写 GeoTIFF 到 `%TEMP%`）与 2 格合成网格；数值参照用我按 `AGENTS.md` 第四节的公式从 `rr_std()` 查表值独立重算。

### 抽检 1：`.report_raster_fill()` 只在真有负值时报（T1）

**结果：PASS 13 / FAIL 0。**

| 用例 | 断言 | 结果 |
|---|---|---|
| 无负值（0、5.5、12） | 0 条警告、`n_neg == 0`、`n_value == 3`、`n_cells == 3` | 全过 |
| 有负值（3 个 `-999` + 1 个 7） | **恰好 1 条**警告、`n_neg == 3`、点名 `-999`、说明"不清洗哨兵值" | 全过 |
| `quiet = TRUE` | 0 条警告，但计数仍返回（`n_neg == 3`） | 过 |
| 含 `NA` | `NA` 不计入负值（`n_neg == 1`，`n_value == 3`） | 过 |
| 多值列（2 列各 2 值、2 个负值） | 合并计数 `n_value == 4`、`n_neg == 2` | 过 |
| 报告是只读的 | 调用后输入仍为 `-999` | 过 |
| 0 行输入 | 返回 `NULL` 且不报 | 过 |

实测警告原文（我自造的 3/4 负值输入）：

```
`conc_real`: 3 of 4 raster value(s) are negative (most frequent: -999 x 3). A
raster reader maps a declared missing-value flag to NA, so these were not
declared missing: they are data errors or an undeclared fill/no-data sentinel.
Nothing is dropped, rescaled or converted to NA here, and the values enter the
analysis as they are. If this is a fill code, declare it in the file
(`_FillValue` / `missing_value` / `NAflag`) or set it to NA before running: the
package does not clean sentinels for you.
```

**端到端接线（P1g，5 条断言全过）**：自造 4x4 GeoTIFF（16 格，其中 2 格 `-999`）+ 自造人口 GeoTIFF + 自造 2 格 `calc_fild`，跑 `mortality(crf = "5COD", …)`：

- `validate = "warn"`：报出 `` `conc_real`: 2 of 16 raster value(s) are negative `` —— **计数与输入里恰有的 2 个 `-999` 一致**（这同时复核了 T1 §2.1"neg 计数没有错"的结论）；
- `validate = "off"`：填充值报告**完全静默**，且整个调用除结果外 **0 warning / 0 message / 0 error**；
- 两种 `validate` 的结果 `all.equal` 为 TRUE —— 报告不影响数值。

### 抽检 2：`.render_cell_keys()` 只在真塌缩时报（T1）

**结果：PASS 10 / FAIL 0。**

| 用例 | 结果 |
|---|---|
| 原生 0.1 度（20x40 = 800 格）`dgt = 2` | **0 条警告**；键数 == 格数；渲染结果与 `matchable()` 逐位一致（`identical()` 为 TRUE） |
| 0.01 度（100x100 = 10,000 格）`dgt = 2` | 恰好 1 条警告；建议 `dgt_coord = 3` |
| 同一网格 `dgt = 3` | 0 条警告，键数 == 格数 |
| 0.001 度（4x4 = 16 格）`dgt = 2` | 1 条警告，**16 格塌成 1 键**（与 T1 报告一致：`0.001°` 的格心都是 `x.xxx5`，两位小数全归零） |
| 塌缩时不丢行 | 返回的键数仍等于格数（T1 的"只告警、不丢行"成立） |

**与 T1 报告的一处数字分歧（不影响其结论）**：T1 §3 缺陷 3 与 §5 的告警原文给出"0.01 度 100x100 + 默认 `dgt_coord = 2` → 10,000 行塌成 **5,037 个键**（x: 100 → 69；y: 100 → 73）"。我用**另一个 extent** 独立构造同一分辨率网格，得到：

```
实测：10000 格 -> 6072 键（x 轴 100 中心 -> 69 键；y 轴 100 中心 -> 88 键）
extent 扫描（只挪窗口原点，100x100 的 0.01 度）：
  xmin=100.0 ymin=10.0  -> x 69 键 / y 88 键 / 合计 6072
  xmin=100.0 ymin=13.9  -> x 69 键 / y 88 键 / 合计 6072
  xmin=  0.0 ymin=10.0  -> x 62 键 / y 88 键 / 合计 5456
```

**x 轴 69 键与 T1 逐位吻合**；y 轴我得 88、T1 得 73，故总键数 6,072 对 5,037。两者都是完整叉积（69x73 = 5037、69x88 = 6072），说明**这是 extent 浮点落点决定的、数据依赖的数，不是普适常数**。T1 的结论（默认 `dgt_coord = 2` 在 0.01 度上大量丢格、应设 `dgt_coord = 3`）**完全成立**，但报告里那三个数应标注"该 extent 下的实测值"，否则读者会把它当成分辨率的固有属性。

### 抽检 3：年龄标签归一（T2）—— 含 `NA` 时崩溃

**结果：PASS 5 / FAIL 3（单元）+ FAIL 2（端到端），全部同一个根因。**

按契约应归一 / 不应改动的两组，**都通过**：

| 组 | 输入 | 实测 |
|---|---|---|
| 应归一（8 项） | `<5 years`、`under 5`、`0-4 years`、`15-19 years`、`95+ years`、`90-94`、`5-9 yrs`、`95+` | 全部归一到分层下界（`0`/`15`/`95`/`90`/`5`…），**8/8** |
| 必须原样（9 项） | `All ages`、`Age-standardized`、`1 year`、`25`、`0`、`95`、`Neonatal`、`Post-neonatal`、`Early neonatal`、空串 | **一个都没被改**，9/9（含空串共 10 个值） |
| 既有数值/字符路径 | 数值 `c(25, 25.4)` → `c("25","25")`；字符 `"25"` → `"25"`；整数 `c(0L,5L,95L)` → `c("0","5","95")` | 3/3 不变 |

**但含 `NA` 的年龄列会崩溃**（见第五节，这是本次抽检最重要的发现）。

**一个观察项（不计入通过/失败，属文档口径）**：归一的 `^\\d+-\\d+$` 规则比"命名了某个 5 岁分层"更宽，下列不命名 5 岁分层的字符串**也会被改写**：

```
'1-4 years'  -> '1'
'12-14 years' -> '12'
'2015-2019'  -> '2015'
```

`1-4`、`12-14` 本就不是查表键，改了也不会 join 上，**数值上无回归**；`2015-2019` 这种"年份区间被当成年龄区间取了下界"的形态值得留意，但真实年龄列里几乎不会出现。建议把 `R/mortality.R` 的注释（"names some 5-year stratum"）与实际正则的范围对齐，或在文档里写明"任何 `数字-数字` 都取小写界"。

### 抽检 4：多余列不许误伤合法输入（T2）

**结果：PASS 14 / FAIL 0。**

| 用例 | 断言 | 结果 |
|---|---|---|
| **4 列合法输入**（`location, age, endpoint, mortrate`） | 不被拒；结果 2 行（= 格数）；值列无 `NA`；**数值与包外手算一致** | 全过 |
| 每行同值的常量载荷列（`note = "ok"`） | **不被拒**；仍 2 行；值列无 `NA`；数值与 4 列输入一致；有告警说明它会成为宽表 id 列 | 全过 |
| 随端点变化的载荷列（`cause_name` 每端点不同） | **被拒**，且报错点名 `cause_name` | 过 |
| 同上 + `validate = "off"` | **仍然被拒**（错误不是"报告"），且 0 warning 泄漏 | 过 |
| 4 列 + `validate = "off"` | 正常返回 2 行，完全静默 | 过 |

手算与包算**逐位一致**（我按 `M = pop × prop × mortrate / 1e5`、`PWRR = weighted.mean(RR(conc_real), pop)`、`attr = M × (RR(conc_cf) − 1) / PWRR` 独立重算，RR 只从 `rr_std("5COD","MEAN")` 查表取）：

```
手算：copd_25 = 73.7594976600，ihd_25 = 340.6727883251
包算：copd_25 = 73.7594976600，ihd_25 = 340.6727883251
```

这条同时**独立复核了 T3 §六"每 10 万只除一次"**那条闭式锚点：我在另一个输入（2 格、1 个年龄层、2 个端点、浓度 10/40）上重建，得到同样的恒等式。

### 抽检 5（附加）：CRS 比较只修了一半（T4 的 F3）

**结果：PASS 2 / FAIL 0（发现一处未覆盖）。**

我造了一个 `OGC:CRS84` 的多边形，对照 `EPSG:4326` 的模板栅格：

```
terra::same.crs()     = TRUE
字符串比较相等        = FALSE
CRS84 -> EPSG:4326 坐标最大变化 = 0.000e+00 度
```

`R/raster-io.R:525` 已按 `terra::same.crs()` 判定（T4 的 F3 落地），但**同一文件 `:603` 的形状文件路径仍是字符串比较**：

```r
if (!is.na(terra::crs(shp)) && terra::crs(shp) != terra::crs(template_raster)) {
  shp <- sf::st_transform(shp, terra::crs(template_raster))
}
```

即：CRS84 的边界文件仍会走一次多余的 `sf::st_transform`。**我实测这一步在数值上是恒等（0.000e+00 度）**，所以是 Info 级的一致性问题，不是数值缺陷；但 T4 §10 Q6 的"F3 已落地"应写明"仅栅格路径"。

---

## 四、交叉核对 T1–T4 的报告

四份报告（最终版本）：`validate_raster_ingest_261002.md`（T1，294 行）、`validate_table_contract_261002.md`（T2，488 行）、`validate_numeric_anchors_261002.md`（T3，446 行）、`validate_scale_perf_261002.md`（T4，511 行）。T4 那份在我读第一遍之后又长了 39 行（Lead 的 21 人对账入册），下面按**最终版**核对。

### 4.1 把 harness 的 bug 记成包缺陷的条目

**0 条。** 我逐个搜了四份报告里与那条已知陷阱相关的措辞（`89,768,019`、`harness`、`预聚合`、`floor()`），结论：

- T3 §2.4 是**最正确的一份**：把 `-4.914%` 逐步定位到 harness 自己的 `floor()` 窗口错位（`x0 = 99.899999989`，比曝光窗口西移整一格）+ 自己那一次 `resample`，并明确"定位与包内路径无关"；包内路径只差 `-2.27e-7`。
- Lead 的 `validate_real_data_scope_261002.md` §三把它明确标为"**不是**包缺陷"。
- T4 只在测量方法里提到"包外 harness"（用 `ps` 测内存），没有把它算成包缺陷。
- **没有任何报告把它记到包头上。** 这条可以销案。

### 4.2 互相矛盾的结论

| # | 冲突 | 谁对 | 我的证据 |
|---|---|---|---|
| 1 | 开工简报/工单起点事实称 `validate = "warn"` 下负浓度"直接阻断"；T1 §2.1 与 T2 §2a 说只告警、继续算 | **T1/T2** | 我的 P1g：`validate = "warn"` + 2 个 `-999` 的栅格**成功返回结果**，只发警告；只有 `"stop"` 阻断 |
| 2 | 同一起点事实称 `validate = "off"` 下"neg 计数错误"；T1 §2.1 称未能复现、计数正确 | **T1** | 我的 P1g 实到 `` `conc_real`: 2 of 16 raster value(s) are negative ``，与输入里恰有的 2 个 `-999` 一致 |
| 3 | 交接称 F3 未提交、工作区与 HEAD 不一致；T4 §9、`git log -S` 显示已在 `0113201` | **T4 / git** | `git log -S 'same.crs'` 只命中 `0113201`；`0113201` 是 `96b762d` 的祖先；当时 `git diff HEAD` 为空 |
| 4 | T2 §12 称其全量测试跑在"T4 正在修改的 `R/raster-io.R`（工作区未提交）之上"；实际 `0113201` 是 `96b762d` 的**父提交** | **属陈述过时**（不影响结论） | `git log --oneline`：`96b762d` → `0113201` → `db918f8`… |
| 5 | T4 §9.4 标注 `0113201` 上的全量测试为 1038 项、又说冻结 HEAD 上重跑"数字相同"；而 T2 §12 自述本批把 `validate-contract` 从 37 增到 **57**（+20） | **两件事不能同时成立**；属出处标注问题 | 我在 `96b762d` 实测：总数 **1038**、`validate-contract` = **57**。若 0113201 真是 1038，则那一次测量时工作区已含 T2 的改动 |
| 6 | T4 §10 Q6 称"F3 已落地" | **只对栅格路径成立** | 我的 P5：`R/raster-io.R:603` 的形状文件路径仍是字符串比较（`same.crs() = TRUE` 而字符串比较 `= FALSE`） |

### 4.3 证据强度不足 / 表述不完整的断言

| 出处 | 断言 | 问题 |
|---|---|---|
| T2 §5.1、§5.4 | 贴了"基线全量测试通过""改动后全量测试通过"的原始输出，但**只有 Skipped 段与文件列表，没有 PASS 总数与耗时** | 门槛证据不完整（结论本身被我这次的全量门槛覆盖，成立） |
| T1 §3 缺陷 3、§5 | "0.01 度 10,000 格 → 5,037 键（x 69 / y 73）"写成普遍量 | 我独立构造得 6,072 键（x 69 / y 88）；这是 extent 依赖的数，不是分辨率常数（见抽检 2） |
| T1 §八证据索引 | 行号如 `R/raster-io.R:349`（浓度用 bilinear）、`:60-75` | 相对当前 HEAD 已漂移（bilinear 现为 `:535`）；T1 文首已声明"行号以提交时为准"，故属已知代价，但引用时必须按符号名核对 |
| T4 §8.2 第 4 条 | "这会让结果行数与现引擎不同（现引擎结果里不含无标签格，倒是一致）" | 括号内自相矛盾，读者无法判断到底一不一致 |
| T4 §10 Q7/Q8 | 21 人差异的成因（模板自身格网偏移 dx = −1.68e-6、dy = −2.07e-6） | 引的是"Lead 实测"，我**未独立复核**（见第八节） |

### 4.4 我核对通过的关键断言（抽样）

| 断言 | 出处 | 我怎么核的 |
|---|---|---|
| `.normalise_coord_keys()` 在 `R/ingest.R:69-102`，对非数值列直接 `next`（`:87-89`），故栅格渲染好的字符键跳过唯一性检查 | T1 §3 缺陷 3 | 读源码，**行号与当前 HEAD 逐位吻合** |
| `.as_res()` 在 `R/utils.R:286-293` 把两轴在 0.1% 内折叠为均值 | T3 §3.1 | 读源码，函数体与描述一致（阈值 `1e-3 * max(abs(res))`） |
| 每个输入每条路由都有给定-当-则登记（`.INPUT_ROUTES`），`2b` 步对栅格来源调 `.report_raster_fill()` 且 `validate != "off"` 才报 | T1 §5 | 读 `R/prepare-inputs.R:521-544`，与 T1 描述一致 |
| `rr_std("5COD","MEAN")` 是长表（`conc, endpoint, age, RR`），我实测 225,075 行 | T3/T4（T4 报 GEMM 45,015 行） | 我的抽检脚本打印列名与行数，可直接对照 |

---

## 五、我发现的**新**缺陷（四份报告都没有记录）

### D1（Must-fix）：年龄列含 `NA` 时，T2 新增的标签归一以 cryptic 文案崩溃

**最小复现（单元，包外一行）：**

```r
AttrMort:::.canonical_age_label(c("25", NA_character_))
# Error in `if (any(under)) ...`: missing value where TRUE/FALSE needed
AttrMort:::.standardize_age_key(c("25", NA_character_))
# 同一个错
AttrMort:::.canonical_age_label(c("<5 years", NA_character_))
# 同一个错（走赋值分支也一样：logical 下标含 NA）
```

**端到端复现（我自造的 2 格网格 + 自造表）：**

```
mort_rate$age = c('25', NA)  -> error = missing value where TRUE/FALSE needed
age_struc$age = c('25', NA)  -> error = missing value where TRUE/FALSE needed
```

**机制**（`R/mortality.R:30-46` 新增的 `.canonical_age_label()`）：

```r
under <- str_detect(x, .AGE_LABEL_UNDER)   # NA 元素 -> NA
if (any(under)) {                          # any(c(FALSE, NA)) 是 NA，不是 FALSE
  out[under] <- "0"                        # 即便进来，logical 下标含 NA 也不允许赋值
}
```

`any(c(FALSE, NA))` 在 R 里返回 `NA`，`if (NA)` 直接抛 `missing value where TRUE/FALSE needed`。**只要年龄列里有一个 `NA` 且没有元素命中该模式，就必然触发**；若命中了，则在赋值处触发（NA 下标不允许）。我实测三种组合全部报错。

**可达性（不是理论风险）** —— `.standardize_age_key()` 在 6 处被调用，其中多处直接吃**原始输入表**的年龄列：

| 位置 | 语义 |
|---|---|
| `R/mortality.R:668` | `intersect(.standardize_age_key(mort_rate$age), unique(RR_tbl$age))` —— 计算前置检查 |
| `R/mortality.R:780-781` | 年龄分块的 `filter()` |
| `R/mortality.R:948-950` | 分支内的键规范化 |
| `R/schema-detect.R:273`、`:305`、`:313`、`:459` | **校验期**：`mort_rate` 的非标准层、`age_struc` 的完整性检查 |

即：**含缺失年龄的真实表会在校验期就崩**，报的是与"年龄标签"毫无关系的 `missing value where TRUE/FALSE needed`。

**为什么四道门槛抓不到**：全量 1038 条断言里没有一条喂 `NA` 年龄给这两个函数；`R CMD check` 也不构造这种输入。这是"门槛全绿但仍有真缺陷"的典型样本，也正是独立反例抽检存在的理由。

**性质判定：这是本轮引入的行为回归，不是自有缺陷。** 改动前 `.standardize_age_key()` 对字符型就是 `as.character(x)`，`NA` 原样留下、在 join 时被静默丢弃（T2 自己在报告里也是这么描述旧行为的）。改动后从"静默丢一行"变成"整单 cryptic 崩溃"。按 T2 本轮的目标（把静默丢失变成可见），把 `NA` 变成可见是合理的，但**必须是可读的报错或告警，不能是 `if (NA)` 崩溃**。

**建议的最小修法（只做加法，我不动手，留给作者/Lead 定）**：在 `R/mortality.R:33/39` 的两个判定上把 `NA` 显式排除，例如 `under <- !is.na(x) & str_detect(x, .AGE_LABEL_UNDER)`、`hit <- !is.na(x) & str_detect(x, pattern)`，并在函数头注释里写明"`NA` 原样返回、由下游 join 丢弃"或"由调用方报一次缺失年龄计数"。加一条 `expect_error(..., NA)` 的回归测试（喂 `c("25", NA)`）即可钉住。

**边界**：我只测了 `mortality()` 与两个内部函数。`decompose()` 走同一套 `.standardize_age_key()`，按代码必然同病，但我**没有实跑**（见第八节）。

---

## 六、我判定"可直接交付"的清单

以下每一项都有我亲手跑出来的证据（门槛或抽检），且**没有改变计算口径**：

1. **四道门槛的通过状态本身** —— `devtools::test()` 1038/0、指纹 42/0 不漂移、`R CMD check` `Status: OK`、仓库洁净，全部落在同一个冻结代码面（MD5 前后一致）。
2. **T1 的加法改动**（`R/raster-io.R` 的 `.render_cell_keys()` / `.report_raster_fill()`、`R/prepare-inputs.R` 的 2b 步）：`_report_raster_fill()` 只在真有负值时报、计数正确、`NA` 不计入、`quiet = TRUE` 沉默但保留计数、不改数据；`.render_cell_keys()` 在原生 0.1 度网格上不误报、真塌缩时报且不丢行；端到端 `validate = "off"` 除结果外完全静默、`warn` 与 `off` 结果 `all.equal`。**13 条（P1）+ 5 条（P1g）+ 10 条（P2）断言全过。**
3. **T2 的重复键阻断与多余列拒绝**：4 列合法输入不被误拒，数值与我的包外手算**逐位一致**；每行同值的常量列只告警不拒；随端点变化的列被拒且点名，`validate = "off"` 下拒绝仍生效。**14 条断言全过。**
4. **T2 的年龄标签归一（主体）**：8 个 GBD 拼写全部归一到分层下界；9 个非分层标签与空串**一个都没被改**；数值/字符/整数三条既有路径不变；13 条指纹分支数值不漂移。
5. **T2 §八 F1 与 §九 F2 的"静默污染"修复方向**：`scenario = NULL` 下多余列要么被拒绝、要么只告警，不再返回 `sum()` 为 `NA` 的宽表；我抽检 4 的第三、四行独立确认了拒绝行为。
6. **T4 的 `.aggregate_pop()` 同支撑集守恒校验 + 前置裁剪（`0113201`）**：代码面、测试面由 T4 的 36 项断言钉住；我做的是**静态核对**（裁剪点、`fact` 判定与告警文案未动、测试覆盖了区域输出不虚报与 `res()` 非精确时聚合块不移动）。**真实 LandScan 上的时延与逐格等价我未复跑**（见第八节）。
7. **T3 的数值锚点（口径层面）**：我用自己的 2 格输入独立重建了 `100 × (RR − 1)/PWRR` 恒等式与 1e5 只除一次，与 T3 §六一致。

---

## 七、必须由用户拍板（口径 / 数据契约）

这些是"要不要改行为"的决定，**本次一律未实现**。除了注明来源的条目，全部来自 Lead 的判定队列 `validate_real_data_scope_261002.md` 第五节（Q1–Q19），我按"影响面"重排了优先级，不改变内容：

**第一优先（会改变结果数值或分析范围，必须先定）**

1. **Q1 栅格填充值清洗**：`-999` 现在只报告、值原样进管线（在查表 join 处被丢）。备选是"非物理值一律置 NA"（改变分析网格与所有总量）或新增 `na_value=` 参数（改公开 API）。来源 T1 §6。
2. **Q9 模板不在人口聚合块网格上时人口被块内抹平**：逐格中位误差 16.6%、最大 119%、窗口总量 +3.94%（T4 的手算基准实测）。改法是"加告警"还是"改用细格面积加权"，后者是口径变更。来源 T4 §7.3。
3. **Q10 无域标签格在 join 之前剔除**：数值等价，但省 806 倍行数、省掉 2,606 万行的 PWRR join；代价是改变"N 格进入计算"的可见性。来源 T4 §6.2。
4. **Q16 / Q17 网格与域口径**：单波段栅格 `NA` 格静默缩小网格；域归属是 `touches`（格方块相交）而非格心（LAO 194 格、ROU 150 格因此纳入）。来源 T3 F4/F7。
5. **Q11 1 公里成对栅格在非交互会话静默回退 0.1 度**，且 `validate = "off"` 下完全无声 —— 这条我认为最接近"缺陷"而非"口径"，但仍改结果定义。来源 T4 §7.1。

**第二优先（输入契约 / 可用性）**

6. **Q7 `detect_columns()` 的同义字段优先级**：`age_id`/`cause_id`/`location_id` 因列序靠前被选中，管线拿到 IHME 数字编码；建议"命中多列优先字符列 + 选中数值 ID 列时告警"。来源 T2 §四 Q1。
7. **Q8 是否内置 GBD 全称 → 查表短码别名表**（T2 建议维持"只给可照做的报错"）。
8. **Q13 `age_struc` 的 Number 是否自动折算成 `prop`**（T2 建议报错并提示）。
9. **Q14 年龄标签归一的**范围**：现在归一 `<5 years` / `15-19 years` / `95+ years`（含无后缀、`under 5`）。**附带我的一条观察**：正则实际覆盖"任意 `数字-数字`"，`1-4 years` → `1`、`2015-2019` → `2015`（数值无回归，但与注释的措辞不一致）。来源 T2 §四 Q5 + 我的抽检 3。
10. **Q15 `max_rate = 5e4` 默认阈值**：真实 GBD 95+ 岁 `All causes` 达 99,880/10 万，触发 69 条误报（`warn` 非阻断）。来源 T2 §三。
11. **Q12 跨输入年份/情景一致性校验**：现状明文不判断，要做须先定义"年份列"这个新契约。
12. **Q2 / Q18 / Q19 / Q3–Q6**：对齐把填充值插值成新负值（T1 §6 Q4）、`validate = "off"` 是否也报填充值、负浓度是告警还是阻断、两张栅格半格偏移是否加提示、`conc_pwe` 是否排除范围外浓度、CRF 不覆盖层是否在结果里显式标记、是否按 GEMM 5COD 曲线调整查表（**外部逐国 PAF 锚点未取得**）。来源 T1 §6、T3 §八、Lead 队列。

**我建议**：Q1、Q9、Q10、Q11 先定，因为它们决定"用户拿到的总量代表什么"；Q7 次之（它决定最自然的 GBD 用法能不能跑通）。

---

## 八、我**没有**验证的东西（明说，不许含糊）

1. **`validate-data/` 真实数据上的任何数字我都没有复跑**：包括 T4 的 482.5 s / 8.27 GB 峰值 / 806 倍 / 26,060,703 行 PWRR join / `.aggregate_pop()` 16.14 s → 0.16 s / 90,758,858，T3 的 90,758,837 / 手算偏差 3.80e-4 / PAF 42.06%，T2 的 30,192 个重复键 / 69.8% 静默丢失。这些是 T3/T4 的实测，我只核对了它们的内部一致性与相关代码，**没有独立复现**。
2. **21 人差异的成因（模板自身格网偏移 dx = −1.68e-6 / dy = −2.07e-6）我没有独立复核**：T4 §10 Q8 与 Lead 都标为"Lead 实测"。我只确认这部分在 T4 的最终版报告里已入册、措辞是"已对清"而非"待对账"。
3. **T1 的 5,037 键（y 轴 73）我没有复现**，我得到 6,072 键（y 轴 88），已在抽检 2 里给出 x 轴逐位吻合与 extent 扫描结果。
4. **`.aggregate_pop()` 前置裁剪在真实 LandScan 上的逐格等价性我没有复跑**：T4 的 36 项测试通过（属于门槛 (a) 的 1038 项之内），但"读少不改数"这条我只做了静态核对。
5. **指纹 13 条分支的期望数值我没有独立重算**：我验证的是"参照文件没被改过"（git）+ "比对全过"（42 项）。若参照本身在 `05f538c` 之前就错了，我这套证据抓不到。
6. **`decompose()` 路径上的 NA 崩溃我没有实跑**：按代码它共用 `.standardize_age_key()`，必然同病，但这是推断不是实测。
7. **T2 的重复键阻断在真实 GBD 表上的行为我没有复跑**：我只在合成 2 格输入上核对了拒绝/告警/`validate = "off"` 三条边界。
8. **T3 的外部逐国 PAF 锚点**：T3 自述未取得（检索被拦），我也没有取得。所以 Q19 的证据等级仍是"量级检查"。

---

## 九、我的门槛证据落盘位置（包外）

| 内容 | 路径 |
|---|---|
| 全量测试日志 | `%TEMP%\attrmort-t5-tests.log` |
| 指纹日志 | `%TEMP%\attrmort-t5-fingerprints.log` |
| 构建日志 | `%TEMP%\attrmort-t5-build.log` |
| check 日志 | `%TEMP%\attrmort-t5-check.log` |
| tarball 与 `.Rcheck` | `%TEMP%\attrmort-check\` |
| 反例抽检脚本与日志 | `%TEMP%\t5-verify\probe-T1.R`、`probe-T2.R`、`%TEMP%\attrmort-t5-probeT1.log`、`%TEMP%\attrmort-t5-probeT2.log` |

复跑（PowerShell，产物全部在临时目录）：

```powershell
$R = 'C:\Program Files\R\R-4.6.1\bin\R.exe'
$Rscript = 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe'
Set-Location 'D:\GitDir\AttrMort'

# 门槛 a
& $Rscript -e "devtools::test()"

# 门槛 b
$env:ATTRMORT_FINGERPRINTS = '1'
& $Rscript -e "devtools::test(filter = 'fingerprints')"
Remove-Item Env:ATTRMORT_FINGERPRINTS

# 门槛 c（必须带 vignette）
$tmp = Join-Path $env:TEMP 'attrmort-check'
Set-Location (New-Item -ItemType Directory -Force $tmp)
& $R CMD build 'D:\GitDir\AttrMort'
& $R CMD check AttrMort_0.3.0.tar.gz --no-manual

# 反例抽检
& $Rscript (Join-Path $env:TEMP 't5-verify\probe-T1.R')
& $Rscript (Join-Path $env:TEMP 't5-verify\probe-T2.R')
```
