# code_review_260930 — C-R JSON 迁移分支代码审查（2026-09-30）

- **审核范围**：分支 `refactor/json-crf-migration` 的迁移代码与接线——`R/cr-config.R`、`R/RR_std.R`、`R/Mortality.R`（分块核）、`R/schema-detect.R`、`tests/testthat/test-cr-config.R`；对照物为 0.3.0 冻结的 39 个 `RR_std()` 输出与 13 条指纹参照。
- **方法**：静态通读 + 运行时探针（`RR_std()` 调用计数与计时、静默 NA 探针）+ 对照锚点。探针手法：在 `load_all()` 会话里 `unlockBinding("RR_std", asNamespace("AttrMort"))` 换成计数包装，跑 `Mortality(chunk_ages = 1 / 15)`，与不换实现的耗时对照；数值一律用 39 表 `all.equal` 与指纹收口。
- **结论**：**通过**。修掉 1 处性能冗余、3 处静默失败风险与若干配置校验缺口；另有 1 个“看似更干净”的重构被指纹锚点否决并回退（保留 `fill()` 的年龄继承语义）。

## 一、已修问题

| # | 类别 | 事实（改前） | 处置 | 证据（改后） |
|---|---|---|---|---|
| F1 | 性能冗余 | `.calc_attributable_ages()` 先建 `RR_tbl`，每个年龄块又让 `.calc_attributable()` 重建一次 `RR_std()`：`chunk_ages = 1` 时 **16 次**重建，8.0 s；整段也要 2 次，1.1 s | 把 `RR_tbl` 与 `crf_label` 作为参数从分块核传入计算核；计算核保留自建路径以兼容直接调用 | 调用数 **16 → 1**（整段 2 → 1）；`chunk_ages = 1` 8.0 s → **4.5 s**，整段 1.1 s → **0.8 s**；两档总量与指纹逐位不变 |
| F2 | 静默失败 | 配置里的端点在前缀缺失时，`RR_std()` 返回全 NA（实测 6002 行 RR 全 NA），join 阶段无声丢光 | 装载期校验“端点的首个年龄列或 `_ALL` 列至少存在一个”，错误报出模型、端点与可用列；`RR_std()` 末尾保留 NA 守卫 | 新测试：`BAD`/`xyz` 报 `no columns for endpoint`；守卫覆盖漏网场景 |
| F3 | 静默失败 | MEAN/LOW/UP 三个分支列集不一致时，三个 CI 各自给出不同的端点/年龄表，中心估计与区间口径漂移 | `.cr_lookup_check()` 要求三分支列名集合完全一致，否则报错 | 新测试 `SPLIT` 报 `share the same columns` |
| F4 | 语义澄清（重构被否） | 试把 `fill()` 换成 `age 列 + _ALL coalesce`（“更确定性”）；实测 **18/39** 个表输出改变——GEMM 的 85/90/95 本来就按“继承前一列（80）”定义，MRBRT 的 `_ALL` 表才全继承 ALL | 回退到 `fill()`，把继承语义写进 `RR_std.R` 文件注释、roxygen 与 `R/AGENTS.md` 内部契约；装载校验只要求“有锚点” | 39 表 `all.equal` **18 → 0** 差异；指纹 42 不变 |
| F5 | 配置安全 | `sheets` 的值类型/键名未校验；`rda` 也接受无用的 `sheets`；同一模型内重复 alias 可通过；把目录当配置文件时只会得到 jsonlite 解析错 | 逐项校验：值须为单个非空字符串、键只能 `MEAN/LOW/UP`、`rda` 禁用 `sheets`、alias 内部去重、目录路径显式报错 | 新增 6 条配置校验测试全过 |
| F6 | 路径安全 | 绝对路径识别只覆盖 `/`、`C:/`、`C:\`，UNC `\\server\share` 会被当成相对路径拼到配置目录下 | 正则加入 `\\\\` 与 `//` 前导 | 静态核对；无新增依赖 |
| F7 | 清理 | `.cr_normalise(raw, path)` 的 `path` 从未使用 | 删参 | 无行为变化 |

## 二、评估后不改（记录理由）

| # | 事项 | 实测/理由 |
|---|---|---|
| N1 | 每次 `cr_config()` 解析 JSON 的开销 | `jsonlite::fromJSON` + 校验 20 次共 0.11 s（≈5.5 ms/次）。`Mortality()` 每次运行只解析一次并显式下传；公开的 `RR_std()` 单次调用可接受，**不加缓存**（包内缓存会引入全局状态，违反硬约束 3） |
| N2 | 分块固有的逐块 filter/join 开销 | 单年龄块 4.5 s 中约 1.7 s 是 RR 重建以外无法共享的分块本身（filter、连接、宽表拼回）；分块本就是用时间换内存（32 GB 护栏），只有用户显式给小 `chunk_ages` 才触发 |
| N3 | `.cr_model_entry()` 线性扫描 models+aliases | 13 个名字，扫描成本可忽略；改为哈希需引入命名环境（全局状态） |
| N4 | `RR_std()` 每次 pivot 小表（≤45k 行） | 单次 0.19 s 且分块路径已复用结果，无进一步空间 |

## 三、验收（改后）

| 检查 | 结果 |
|---|---|
| `devtools::test()` | `FAIL 0 / WARN 0 / SKIP 1 / PASS 683`（+9 条安全校验测试） |
| 指纹回归 | `FAIL 0 / WARN 0 / SKIP 0 / PASS 42`，参照未动 |
| 39 表 `RR_std()` 对照 | 与 0.3.0 冻结输出 `all.equal` 0 差异（NO₂ 改名除外） |
| `R CMD build` + `R CMD check` | `Status: OK`（0 ERROR / 0 WARNING / 0 NOTE；check 内 683 PASS） |
| 分块性能探针 | `chunk_ages = 1`：16 → 1 次 `RR_std()`，8.0 → 4.5 s；整段 1.1 → 0.8 s；总量两档一致 |

## 四、给后续的提醒

- **`fill()` 的年龄继承是契约**：改任何“最近年龄缺失怎么补”的逻辑前，先跑 39 表对照与指纹（本轮已用一次否决证明其必要性）。
- 新增查表载体/模型时，`.cr_lookup_check()` 的三条要求（conc 可数值化、三分支同列、端点有锚点）是准入线。
- 性能上如果再要提分块速度，方向是“块间共享的连接键预排序/整数索引”（R/AGENTS.md 待办 1 的网格引擎已规划），不是继续在 R 列表层做微优化。
