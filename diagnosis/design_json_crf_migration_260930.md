# design_json_crf_migration_260930 — PM2.5-attr-mort v5 → AttrMort 迁移设计

> 状态：**设计稿，待口径拍板**（分支 `refactor/json-crf-migration`）。本文档描述“把 PM2.5-attr-mort v5 的 JSON 浓度-反应（C-R）配置机制移植进 AttrMort”的目标架构、接口、数据契约与分阶段计划；末尾“待拍板口径”全部确认前不进入实现。
>
> 参考物：`D:\GitDir\PM2.5-attr-mort` @ `ca48c50`（v5.0，2026-06-18）；`D:\GitDir\AttrMort` @ `a967f0f`（0.3.0 收口后）。

## 0. 一页摘要

- **移植对象只有一层**：PM2.5 v5 的“模型名 → JSON 配置 → 查表文件 → 标准长表”机制（`Code/model.R` 的 `set_Model()`/`RR_std()` + `Data/RR_std_config.json`）。
- **不移植**：v5 的全局状态（`assign(globalenv())`、`.RR_std_tbl`）、硬编码 `./Data/...` 路径、运行时回写 JSON、`read_files()` 全局读入、`Uncertainty()` 的一阶 sigma 口径（与 AttrMort 已锁定的 range 口径冲突）。
- **最大收益**：新增污染物/端点集只需写一份 JSON 配置 + 查表文件，不再改代码；`RR_std()` 的 6 个硬编码 reshape 分支、`.CR_ENDPOINTS` 与“两处同步”测试随之退役。
- **兼容底线**：`RR_std(model, index, dgt)` 的返回形状（`conc/endpoint/age/RR` 字符键长表）与 `Mortality()` 数值不变 → 13 条指纹参照保持不变是迁移的验收锚点。
- **拍板项**：见 §9（查表载体、越界浓度、LRI 年龄口径、NO2 端点名、PWRR 粒度等）。

## 1. 问题与目标

### 1.1 问题

AttrMort 0.3.0 的 C-R 层是**代码内置**的：`.CR_TABLE_REGISTRY`（模型名 → `data/*.rda`）在 `R/RR_std.R:10`，端点/年龄集合在每个模型的 `if/else` reshape 分支里硬编码（`R/RR_std.R:109-196`），同一信息又在 `.CR_ENDPOINTS`（`R/schema-detect.R:10-24`）重复一遍，靠一个测试钉住两者一致。结果是：

- 新增一个模型/端点集 = 改 2 处代码 + 加数据 + 改测试；
- 内置表与用户自带表的处理路径不同（用户表必须自己整理成 `conc/endpoint/age/RR`）；
- 端点年龄集合只能通过读代码知道。

PM2.5-attr-mort v5 已把这一层数据化：`Data/RR_std_config.json` 按模型声明 `conc_col`、`label`、`lookup` 文件与 `endpoints[].ages`，`RR_std()` 据此把 MEAN/LOW/UP 三个 sheet 变成统一长表。

### 1.2 目标（本轮迁移的产出）

1. **配置驱动**：AttrMort 内置模型与用户自定义模型走同一个配置机制；新增模型零代码。
2. **接口不变**：`RR_std()`、`Mortality()`、`cr_models()` 的既有调用与返回形状不变；13 条指纹不变。
3. **不引入全局状态**：配置对象显式传入（默认取包内配置），兼容 `Mortality()` 的 `CRF=` 入口。
4. **不违反既有硬约束**：无 `assign()`、不假设工作目录、不隐式写用户文件、可选的 xlsx 解析仍受依赖守卫。
5. **可迁移**：保留 `data/*.rda` 与 `build_cr_table()` 作为“资产侧”，JSON 只做元数据；未来换载体（xlsx/csv）不改计算核。

### 1.3 非目标

- 不移植 v5 的 `read_files()`/`build_instance.R`（AttrMort 的 ingest 层已优于它）；
- 不移植 `Uncertainty()` 的一阶 sigma 与 `aggregate_sigma()`（违背 AttrMort 已锁定的 range 口径）；
- 不把 `Decomposition()` 改成 v5 的“24 排列取平均”（AttrMort 是 `serie` 选单排列，口径不同，另议）；
- 不在此轮解决 ×10 整数键提案（见 §9-U9，已登记为独立设计题）。

## 2. 目标架构

新增/改造后的分层（★ 为新增，▲ 为改造）：

```
配置层
  inst/extdata/cr_models.json          ★ 随包默认配置（模型 → 元数据）
  cr_config(path = NULL)               ★ 读取 + 校验配置（NULL = 随包默认）
  用户配置：cr_config = "my_cr.json"    ★ 参数化，路径相对配置文件解析

查表资产层（不变）
  data/*.rda                           = list(MEAN, LOW, UP)，字符 conc 键
  build_cr_table()                     = 系数 → 上述资产（IER/GEMM 曲线）
  自定义查表：查表文件（xlsx/csv）+ 配置项  ★ 由配置声明

标准表层（改造）
  RR_std(CR_Model, index, dgt, config) ▲ 输出形状不变，实现改为配置驱动
  cr_models(config)                    ▲ 名字列表来自配置（含 alias）
  .CR_ENDPOINTS / .CR_TABLE_REGISTRY   ✗ 删除（信息进配置）

计算层（不变）
  .calc_attributable() / .chunkable_ages() / range 区间 / aggregate_* 
```

设计要点：

- **配置只做元数据**，不搬数值。内置 8 MB 查表仍以 `data/*.rda` 随包（速度、无运行时解析风险）；配置里用 `{"kind": "rda", "table": "GEMM_Lookup_Table"}` 引用。用户自定义查表用 `{"kind": "xlsx", "path": "..."}`。
- **单一事实来源**：端点×年龄集合只存在于配置；`.CR_ENDPOINTS` 删除，`validate_mortality_input()` 从配置取该模型的端点集。
- **默认配置随包**：`inst/extdata/cr_models.json` 经 `system.file()` 解析，不依赖工作目录；用户配置的相对路径**相对配置文件目录**解析（不是 cwd），保持“路径由参数传入”的既有硬约束。
- **不做隐式写**：用户配置只读；不提供 v5 那种运行期 auto-append。

## 3. JSON 配置规范（AttrMort 版）

### 3.1 Schema

```json
{
  "schema_version": 1,
  "models": {
    "GEMM": {
      "label": "PM2.5_GEMM_NCD+LRI",
      "aliases": ["NCD+LRI"],
      "lookup": { "kind": "rda", "table": "GEMM_Lookup_Table" },
      "conc_col": "conc",
      "endpoints": [
        { "name": "ncd+lri", "ages": ["25","30","35","40","45","50","55","60","65","70","75","80","85","90","95"] }
      ]
    },
    "IER2017": {
      "label": "PM2.5_IER2017",
      "aliases": ["IER"],
      "lookup": { "kind": "rda", "table": "IER2017_Lookup_Table" },
      "conc_col": "conc",
      "endpoints": [
        { "name": "copd", "ages": ["25","30","35","40","45","50","55","60","65","70","75","80","85","90","95"] },
        { "name": "lri",  "ages": ["0"] }
      ]
    },
    "O3": {
      "lookup": { "kind": "rda", "table": "O3_CR_Lookup_Table" },
      "conc_col": "conc",
      "endpoints": [ { "name": "copd", "ages": ["25","30","35","40","45","50","55","60","65","70","75","80","85","90","95"] } ]
    },
    "CUSTOM_X": {
      "lookup": { "kind": "xlsx", "path": "lookups/my_cr.xlsx", "sheets": { "MEAN": "MEAN", "LOW": "LOW", "UP": "UP" } },
      "conc_col": "concentration",
      "endpoints": [ { "name": "ihd", "ages": ["25", "30"] } ]
    }
  }
}
```

### 3.2 字段语义

| 字段 | 必填 | 语义 |
|---|---|---|
| `schema_version` | 是 | 整数；装载器不认识的版本直接报错 |
| `models` | 是 | 对象；键为 `CRF=` 接受的名字（**别名也列在一级键也可**，见下） |
| `models[].label` | 否 | 输出/filename 用的人类可读名；`tell_Model()` 语义（AttrMort 直接暴露为配置读取） |
| `models[].aliases` | 否 | 等价模型名（如 `IER→IER2017`、`NCD+LRI→GEMM`、`MRBRT→MRBRT2021`），大小写不敏感匹配 |
| `models[].lookup.kind` | 是 | `"rda"`（包内对象）或 `"xlsx"` / `"csv"`（用户文件） |
| `models[].lookup.table` | kind=rda 必填 | `data/*.rda` 的对象名 |
| `models[].lookup.path` | kind=文件必填 | 相对**配置文件**的路径；也接受绝对路径 |
| `models[].lookup.sheets` | 否 | xlsx sheet 名映射；默认 `MEAN/LOW/UP` |
| `models[].conc_col` | 否 | 查表侧的浓度列名；默认 `conc`；装载后统一改名 `conc` |
| `models[].endpoints[].name` | 是 | 规范化端点名（小写，AttrMort 契约） |
| `models[].endpoints[].lookup` | 否 | 查表里的列前缀；默认等于 `name`。用于暴露名与查表前缀不同名（如 `allcause` <- `CAUSE`） |
| `models[].endpoints[].ages` | 是 | 该端点适用的年龄字符向量（5 岁分层，不含 `ALL`）；支持数组或 `{from,to,by}` 范围对象 |

### 3.3 校验规则（装载期硬报错）

1. `schema_version` 已知；`models` 非空。
2. 每个模型至少一个 endpoint；endpoint 名非空、小写后唯一。
3. ages 非空、可转数值、升序、且都在查表实际存在的列里（装载查表后核对 `{endpoint}_{age}` 列或 `{endpoint}_ALL` 存在，否则报“某模型某端点的年龄区间在查表中无列”）。
4. rda 对象存在且为 `list(MEAN/LOW/UP)`；三支的 `conc` 为字符且列名集合一致。
5. 文件型查表存在（相对配置目录解析）、sheets 存在、含 `conc_col` 列。
6. 重名/alias 冲突（alias 与一级键、与其它 alias 冲突）报错。
7. 不认识的字段：报错（避免拼写错误静默忽略）。

## 4. 与 PM2.5 v5 的逐项对照与裁决建议

| 维度 | PM2.5 v5 | AttrMort 0.3.0（现状/锁定口径） | 迁移裁决（建议） |
|---|---|---|---|
| 配置来源 | `./Data/RR_std_config.json` 硬编码相对路径 | 无 | 参数化 + 随包默认（`system.file`），相对路径按配置文件目录解析 |
| 全局状态 | `assign(.CR_Model/.RR_std_tbl, globalenv())`，getter 隐式读全局 | 无全局状态（硬约束 3） | **不移植**；模型名经 `CRF=`，配置经参数 |
| 配置写回 | `set_Model(path=)` 运行期向 JSON 追加条目 | 禁止隐式写 | **不移植**；自定义走“编辑好的配置文件” |
| 端点/年龄元数据 | JSON `endpoints[].ages`（整数，含 `ALL` 语义） | 硬编码 reshape 分支 + `.CR_ENDPOINTS` | 进 JSON（**字符串年龄**，不含 ALL）；删除两处代码 |
| 查表载体 | `Data/RR_index/*.xlsx`，运行时 readxl | `data/*.rda`（xz） | 默认保持 rda；配置支持 xlsx/csv 供自定义（§9-U1） |
| 浓度列名 | 每模型 `conc_col`（MRBRT 用 `"dose"`） | 统一 `conc` | 配置声明 + 装载后统一改 `conc`（保留该字段） |
| 浓度键 | `matchable(x, 1)` 硬编码 | `matchable(x, dgt_conc)`，`dgt_conc` 可配 | 保持 AttrMort 契约；装载输出按 `dgt` 渲染 |
| 越界浓度 | 钳到查表范围并 WARN（`mortality.R:200-247`） | 不钳；键不命中即丢行（join 失败） | **待拍板 U2**：建议保留“丢行 + 明确告警”，或引入钳制为显式参数（见 §9） |
| PWRR 粒度 | `group_by(domain)` 一域一个（跨 endpoint/age 混合加权，`mortality.R:328-330`） | 按 `(域, 端点, 年龄)`（AGENTS 已锁） | **保留 AttrMort 粒度**；PM2.5 现状登记为差异（疑似其口径问题） |
| CI 输出 | `Mortality(CI=)` 给列名加 `_MEAN/_UP/_LOW` 后缀；`CI="RANGE"` 三支并排 | 无后缀；`uncertain=TRUE` 附加 `CI_LOW/CI_UP`（逐格 range 求和） | **保留 AttrMort**；不采用 v5 的列名约定 |
| 不确定性 | `Uncertainty()` 一阶误差传播 `σ²=Σ Sensi²`；`aggregate_sigma()` | 已删除一阶法，锁定“逐格 LOW/UP 求和 + conc_uncert 并集” range | **保留 AttrMort**；v5 的 sigma 不移植 |
| 端点命名 | NO2 用 `allcause`；O3/NO2 无 label | NO2 用 `cause`（测试/示例数据依赖） | **待拍板 U4**：建议保留 `cause`（兼容），配置里写明 |
| LRI 年龄 | 配置 IER/IER2017/MRBRT/MRBRT2019/MRBRT2021 的 lri ages 0–95（靠 ALL 列 fill，实际全年龄同值） | IER 族 lri 仅 age 0；MRBRT2019 lri 仅 age 0；MRBRT/MRBRT2021 lri ≥25（见 `R/RR_std.R:147-177`） | **待拍板 U3**：建议按 AttrMort 语义写配置（lri 的 ages 精确列出现有集合），维持既有结果与指纹 |
| 分解 | 24 排列取平均（Dietzenbacher） | `serie=1..24` 选单排列 | 另议，不在本轮 |
| 人口/年龄输入 | `read_files()` 全局读入 | 参数传入 + 自动映射 | 保留 AttrMort |

## 5. 接口设计

### 5.1 新增

```r
# 读取并校验配置；NULL = 随包默认 inst/extdata/cr_models.json
# 返回带 class "attr_cr_config" 的 list(schema_version, models, path)
cr_config(path = NULL)

# 列出配置中的模型名（含 alias）与其 label
cr_models(config = NULL) -> character            # 保持现有返回：名字向量
```

### 5.2 改造（签名向后兼容）

```r
RR_std(CR_Model, index = "MEAN", dgt = 1, config = NULL)
# 返回契约不变：data.frame(conc[chr], endpoint[chr], age[chr], RR[num])
# 内部步骤：config → 取 model 条目 → 装载查表 → pivot_longer(sheets/branches)
#          → 按 endpoints[].ages 展开 → fill(ALL) → 过滤 → tolower(endpoint)
#          → conc 统一命名 → matchable(dgt)

Mortality(..., CRF, cr_config = NULL, ...)
# CRF 仍接受：模型名（配置查）、data.frame（原样，兼容）、
#            list(MEAN/LOW/UP)（新增，等价于自带查表 + 内置元数据）
# 新增 cr_config= 传给 RR_std；其它参数不动
```

### 5.3 删除

| 对象 | 位置 | 替代 |
|---|---|---|
| `.CR_TABLE_REGISTRY` | `R/RR_std.R:10-24` | 配置 `models[].lookup` |
| 6 个 reshape 分支 | `R/RR_std.R:109-196` | 配置 `endpoints[].ages` + 通用 pivot/fill |
| `.CR_ENDPOINTS` | `R/schema-detect.R:10-24` | 配置 |
| “两处同步”测试 | `tests/testthat/test-schema-detect.R:86` | 配置校验测试（§3.3） |

保留：`build_cr_table()`（系数 → 查表资产；输出即 `list(MEAN/LOW/UP)`，可写 xlsx 供自定义配置引用）、`data/*.rda`、`matchable()`、`RR_std()` 返回形状。

## 6. 公式链（四栏）

C-R 侧不引入新公式，只是“同一公式、元数据外置”。沿用 AttrMort 已锁定公式，编号与现文档一致：

| # | 方法描述 | 公式 | 管线 | 落点 |
|---|---|---|---|---|
| F1 | 查表渲染 | 键 `K(x)=as.character(round(x, dgt))` | 配置装载 → 查表 pivot → 按 `ages` 展开 → fill(ALL) → filter | 目标 `R/RR_std.R`（现 `:95-202`） |
| F2 | 域内人口加权 RR | `PWRR_{d,e,a} = Σ_g pop_g·RR(K(conc_real_g),e,a) / Σ_g pop_g` | 逐格长表 → 按 `(域,端点,年龄)` 分组 | `R/Mortality.R:861-867`（不动） |
| F3 | 逐格归因死亡 | `M_{g,e,a} = pop_g·prop_{d,a}·mortrate_{d,e,a}·(RR(K(conc_cf_g),e,a)−1)/PWRR_{d,e,a}/1e5` | 宽→长→计算→宽 | `R/Mortality.R:869-880`（不动） |
| F4 | 区间（range） | `CI_LOW=Σ_g M_g(LOW; conc·(1−p%))`，`CI_UP` 对称；与中心估计同链 | `compute("LOW"/"UP")` + `conc_uncert` 两链并集 | `R/Mortality.R:578-606`、`R/uncertainty.R`（不动） |

迁移对 F1 的**唯一要求**：配置必须精确复现现有 reshape 语义，否则 F2–F4 数值漂移。

## 7. 符号 ↔ 代码变量映射

| 设计符号 | PM2.5 v5 | AttrMort 现状/目标 |
|---|---|---|
| `K(·)` 浓度键 | `matchable(x, 1)` | `matchable(x, dgt_conc)`（`R/utils.R:113`） |
| `concentration` | 长表列名 | `conc`（契约规范列名） |
| `agegroup` | 整数/`"ALL"` | `age` 字符 5 岁分层（数值年龄取整） |
| `CI` | 长表一列 `MEAN/UP/LOW` | `RR_std(index=)` 单支返回；配置驱动装载三支 |
| `RR` | 同 | 同 |
| `PWRR_domain` | 域级单值 | `PWRR_{域,端点,年龄}`（`R/Mortality.R:865`） |
| `Mort` | 宽表列 `{endpoint}_{age}_{CI}` | `{endpoint}_{age}`（CI 经 `uncertain` 附加列） |
| model entry | `cfg[[.CR_Model]]` | `config$models[[CRF]]` + alias 解析 |

## 8. 数据契约（迁移新增，编号 DC）

在根 `AGENTS.md` 既有契约之外，迁移新增以下硬约束（实现与测试必须逐条落实）：

1. **DC-M1 配置是模型元数据的唯一来源**：端点×年龄×查表位置×浓度列名只能写在 JSON；代码里不得再出现按模型名分支的端点/年龄常量。
2. **DC-M2 输出形状不变**：`RR_std()` 仍返回 `conc/endpoint/age/RR`，`conc` 字符且为 `dgt` 位规范形式，`endpoint` 小写，`age` 字符。
3. **DC-M3 指纹锚点**：迁移前后 13 条指纹参照逐位不变（除非口径项被显式拍板变更并同步参照）。
4. **DC-M4 路径解析**：包内配置用 `system.file`；用户配置里的相对路径相对**配置文件所在目录**，绝不相对 cwd。
5. **DC-M5 只读**：装载与计算不得写任何配置或查表文件。
6. **DC-M6 无全局状态**：配置对象与查表内容只经返回值/参数传递。
7. **DC-M7 校验失败必须报出模型名与字段路径**（如 `models.IER2017.endpoints[1].ages`），不得只报“invalid config”。
8. **DC-M8 兼容面**：`CRF=<data.frame>` 语义不变；`cr_models()` 返回值只增不减（别名变化属破坏性变更，需单独列出）。

## 9. 待拍板口径（未确认前不进入实现）

| # | 决策点 | 选项 | 建议 | 影响 |
|---|---|---|---|---|
| U1 | 内置查表载体 | A. 保持 `data/*.rda` + JSON 元数据；B. 改为 `inst/extdata/*.xlsx`（对齐 v5）；C. 双格式并存 | **A** | B 增加运行时 readxl 解析与装卸成本、体积可能更大；A 保住 8 MB xz 与现有测试 |
| U2 | 越界浓度 | A. 现状：键不命中即丢行（无告警）；B. v5 式：钳到查表范围 + WARN；C. 钳制但作为显式参数（默认关） | **C**（默认与现状一致，需要时显式开）或 **A+明确告警** | 直接改变边界格结果的风险高，需指纹重算 |
| U3 | LRI 年龄口径 | A. 按 AttrMort 现状（IER 族与 MRBRT2019 的 lri 仅 age 0；MRBRT/MRBRT2021 的 lri ≥25）；B. 按 v5 配置（上述模型 lri 全年龄 0–95 同值） | **A** | B 会让 lri 的适用年龄显著扩大，数值大幅变化、指纹全变 |
| U4 | NO2 端点名 | A. 保留 `cause`；B. 改为 `allcause`（对齐 v5）；C. 两者都接受为别名 | **A**（配置内可加 `"aliases": ["allcause"]`） | 端点名是用户数据契约（mort_rate/示例数据依赖），改名破坏兼容 |
| U5 | PWRR 粒度 | A. 保留 `(域, 端点, 年龄)`；B. 域级单值（v5 现状） | **A** | B 与 AGENTS 已锁口径冲突且跨病种混合加权 |
| U6 | 自定义模型入口 | A. 只接受“编辑好的 JSON 路径 + 查表文件”；B. 运行时自动生成配置并写回（v5 `set_Model(path=)`） | **A** | B 违反只读/不隐式写约束 |
| U7 | `cr_config` 参数名与位置 | A. `Mortality(..., cr_config = NULL)` 新增参数；B. 复用 `CRF` 接受 JSON 路径 | **A** | A 语义清晰；B 会把“模型名”和“配置文件”混在一个参数里 |
| U8 | `label` 的暴露方式 | A. 只进配置，加 `cr_label(model, config)` 帮助函数；B. 不暴露（暂不需要） | **A** | v5 用 label 命名输出文件；AttrMort 当前无此需求，可先只存不暴露 |
| U9 | ×10 整数键 | 暂缓（已登记）；若做，与本迁移分开评审 | — | 独立设计题，见审计报告 I-9 |

## 10. 缺口与风险

| 类型 | 条目 | 量化/处置 |
|---|---|---|
| 待实现 | 默认配置需逐模型复刻现有 reshape 语义（含 IER/MRBRT 的年龄限制、5COD 的 5 端点、NO2 15–95、O3 25–95） | 以 13 条指纹为验收锚点；先写配置→跑指纹→再删分支 |
| 待实现 | 用户自定义模型只有 xlsx/csv 查表 + JSON 一条路；用户 `data.frame` CRF 仍保留 | 文档 + 测试 |
| 待实现 | 配置校验错误信息与 schema 版本策略 | §3.3 逐条测试 |
| 固有 | 内置查表 8 MB 随包（U1-A 下不变） | 记录；如需瘦身另立议题 |
| 固有 | 查表键是“网格节点 + 取整”，非插值：暴露值落在两节点之间时取整到最近节点（半边界受浮点表示影响） | 记录进 README/契约；×10 整数键不解决半边界问题（已实测） |
| 风险 | 迁移引入的 pivot/fill 通用路径必须与原分支持续等价 | 指纹 + 对每个模型逐列 diff（`RR_std()` 输出 `all.equal`） |
| 风险 | PM2.5 配置与 AttrMort 语义不同的字段（lri ages、NO2 名、PWRR 粒度）如被“照抄”会静默改变结果 | §4 裁决表 + §9 拍板；配置评审清单 |

## 11. 分阶段计划（每阶段可独立验收）

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0 | `cr_config()` + schema 校验 + 随包 `inst/extdata/cr_models.json`（仅覆盖现有 13 个模型名） | 配置校验单测；`cr_models()` 与现列表一致 |
| P1 | 配置驱动的通用 `RR_std()`（保留旧实现于分支内对照），逐模型 `all.equal` 对齐旧输出 | 13 模型 × 3 CI `all.equal` 全 TRUE |
| P2 | 切换 `RR_std()` 到新实现，删除 `.CR_TABLE_REGISTRY`、reshape 分支、`.CR_ENDPOINTS` 与同步测试；`validate_mortality_input()` 改读配置 | 全量测试 + 指纹 0 变化 + `R CMD check` 0/0/0 |
| P3 | 自定义模型路径（文件型查表 + 用户配置）、`cr_config=`/`Mortality()` 接线、错误信息与文档 | 新测试：自定义 xlsx/csv 模型端到端；路径相对配置文件解析 |
| P4 | 文档与收尾：README/AGENTS/R/AGENTS 更新，`NEWS.md` 补记，审计报告补记 | 验收同 P2 |

每阶段结束跑：`devtools::test()`、`ATTRMORT_FINGERPRINTS=1` 指纹、`R CMD check`。

## 12. 验收标准

1. 13 条指纹 `FAIL 0 / WARN 0 / SKIP 0`，参照文件不改（除显式拍板的口径项）。
2. `RR_std()` 对每个模型每个 CI 与 0.3.0 输出 `all.equal`（列名、列序、行集合）。
3. 全量测试 0 失败；`R CMD check` `Status: OK`（0/0/0）。
4. 配置错误路径有单测：未知 schema、缺字段、alias 冲突、查表缺列、文件不存在、路径相对配置文件解析。
5. 自定义模型端到端：一份 JSON + 一个 xlsx/csv，`Mortality()` 可跑通且不触碰包内数据。

## 13. 设计自身的验证

- 反向复核：本设计的关键现状断言（reshape 分支行为、PWRR 粒度差异、v5 sigma 口径）逐条引用了双方代码行；实现前会先用脚本对“配置语义 = 现输出”做逐模型 diff。
- 基准版本：PM2.5-attr-mort `ca48c50`、AttrMort `a967f0f`；两仓库后续变动需回看本设计是否过期。
- 范围限制：未评估迁移对 `Decomposition()`（其调用 `Mortality()`）的间接影响；未评估自定义查表的内存/时间成本。

## 附录 A：现语义清单（配置必须逐字复刻，实测于 `a967f0f`）

模型名（alias）→ 查表对象 → 端点:年龄集合（`RR_std()` 实际输出，脚本：对每个模型取 `unique(endpoint, age)`）：

| 模型（alias） | 查表（rda 对象） | 端点:年龄 |
|---|---|---|
| `GEMM`, `NCD+LRI` | `GEMM_Lookup_Table` | `ncd+lri`: 25–95 |
| `5COD` | `GEMM_Lookup_Table` | `copd/ihd/lc/lri/stroke`: 25–95 |
| `IER`, `IER2017` | `IER2017_Lookup_Table` | `copd/ihd/lc/stroke`: 25–95；`lri`: 0 |
| `IER2015` | `IER2015_Lookup_Table` | 同上 |
| `IER2013` | `IER2013_Lookup_Table` | 同上 |
| `IER2010` | `IER2010_Lookup_Table` | 同上 |
| `MRBRT`, `MRBRT2021` | `MRBRT2021_Lookup_Table` | `copd/dm2/ihd/lc/lri/stroke`: 25–95 |
| `MRBRT2019` | `MRBRT2019_Lookup_Table` | 同上，但 `lri`: 0 |
| `O3` | `O3_CR_Lookup_Table` | `copd`: 25–95 |
| `NO2` | `NO2_CR_Lookup_Table` | `cause`: 15–95 |

注：`MRBRT` 与 `MRBRT2021` 共用同一张表，`IER` 是 `IER2017` 的别名；`NCD+LRI` 共用 GEMM 表。P0 写默认配置时直接以本表为准（年龄升序、5 岁步长、端点小写）。

## 补记一（2026-09-30，P0–P2 实施记录）

**拍板结果。** U1=A（内置保持 rda + JSON 元数据）；U2=A（不钳制，丢行但明确告警）；U3=A（配置逐字复刻 AttrMort 现状语义）；**U4=B（NO₂ 端点由 `cause` 改为 `allcause`，属破坏性变更）**；U5=A（PWRR 保持域×端点×年龄）；U6/U7/U8 按建议（只读配置；`Mortality(..., cr_config=)`；label 先只进配置）。U9 仍暂缓。

**相对设计稿的实现补充。**

- endpoint 级新增可选 `lookup` 字段（暴露名 ↔ 查表列前缀映射），NO₂ 用 `allcause` <- `CAUSE`；查表资产无需改名。
- `csv` 载体的语义定为“目录”：`lookup.path` 指向目录，默认读 `MEAN.csv/LOW.csv/UP.csv`，`sheets` 可覆盖文件名；`xlsx` 的 `sheets` 覆盖 sheet 名。
- 校验分两段：`cr_config()` 做结构与取值校验（§3.3 前 4、6、7 条）；“查表文件/对象存在、列齐全、conc 可数值化”在装载期（`RR_std()` 调用时）检查，错误带查表来源与分支名。
- U2 落地：核内新增“N 个值超出查表范围 [a,b]，将被 join 丢弃”的告警（`conc_real`/`conc_cf` 同值时只报一次），默认行为与 0.3.0 一致；同时修复 `dgt_conc` 未传入 `RR_std()` 的旧缺口（`dgt_conc ≠ 1` 时两侧键精度会不一致）。
- `Mortality()` 的 `cr_config=` 追加在参数表末尾，既有位置参数不受影响；`validate_mortality_input()` 新增 `config=`。

**已完成阶段。**

| 阶段 | 产出 | 验收 |
|---|---|---|
| P0 | `inst/extdata/cr_models.json`（10 个规范模型 + 3 个别名，复刻附录 A）；`R/cr-config.R`（`cr_config()`/`cr_models()`/`print` + 校验）；`tests/testthat/test-cr-config.R` | 结构校验逐类报错（schema 版本、未知字段、空端点、非法 ages、alias 冲突、重复端点、字段路径） |
| P1 | 配置驱动的通用 `RR_std()`（`R/RR_std.R`：pivot → 按配置展开 → fill(ALL) → 过滤；`.cr_lookup_load()` 支持 rda/xlsx/csv） | 39 个模型×CI 与冻结的 0.3.0 输出逐行 `all.equal` 全 TRUE（NO₂ 端点改名除外） |
| P2 | 删除 `.CR_TABLE_REGISTRY`、6 个 reshape 分支、`.CR_ENDPOINTS` 与同步测试；`validate_mortality_input()` 读配置；NO₂ 端点改名并同步示例数据的 `national_mortality.xlsx` 与 `crf-NO2.csv` 指纹（列名前缀变化、数值逐位不变） | 全量测试 `FAIL 0 / WARN 0`；指纹 42 全过；`R CMD check` `Status: OK`（0/0/0） |

**待做（P3–P4）。** 自定义 xlsx/csv 查表的端到端测试（配置相对路径解析、缺 sheet/缺列错误）；`Mortality(cr_config=)` 端到端；README/vignette 收尾；`NEWS.md` 与版本号按用户既有指示未动，发布前需补记破坏性变更（NO₂ 端点改名、`cr_models()` 现在含别名且来自配置）。
