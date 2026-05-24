# Day 14 实践报告：数据对账（Reconciliation）

## 1. 练习目标
- 理解数据对账（Reconciliation）在数据仓库中的重要性：确保数据在各层（ODS → DWD → DWS）之间的一致性。
- 掌握使用 SQL 进行行数对账、关键字段分布对比、差异样本抽取。
- 明确对账口径：主键、关联方式、差异容忍度。
- 学会识别常见数据不一致原因（迟到数据、重复、逻辑错误）。

## 2. 实验环境
- DuckDB 版本：0.x.x
- 数据路径：`data/raw/apply/` 和 `data/raw/decision/` 按 `dt` 分区（2024-01-01 至 2024-01-10，共 10 天）
- 视图：
  - `v_apply`：ODS 层申请数据（原始，可能存在重复）
  - `v_decision`：ODS 层决策数据（原始）
  - `dwd_apply_latest`：DWD 层申请数据（按 `apply_id` 去重，取 `update_time` 最新）
  - `dwd_decision_latest`：DWD 层决策数据（按 `apply_id` 去重，取 `decision_time` 最新）
- 数据规模：每天约 5,000 条申请记录，决策记录与申请基本对应。

## 3. 核心 SQL 及结果

### 3.1 创建 DWD 视图（若未创建）
```sql
-- DWD 申请：按 apply_id 去重取最新
CREATE OR REPLACE VIEW dwd_apply_latest AS
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM v_apply
) t
WHERE rn = 1;

-- DWD 决策：按 apply_id 去重取最新
CREATE OR REPLACE VIEW dwd_decision_latest AS
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC) AS rn
    FROM v_decision
) t
WHERE rn = 1;
```

### 3.2 行数与主键数对账

```sql
WITH ods_stats AS (
    SELECT
        COUNT(*) AS ods_rows,
        COUNT(DISTINCT apply_id) as ods_unique_apply
    FROM v_apply
    WHERE dt = '2024-01-01'
),
dwd_stats AS (
    SELECT
        COUNT(*) AS dwd_rows,
        COUNT(DISTINCT apply_id) AS dwd_unique_apply
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT
    ods_rows,
    ods_unique_apply,
    dwd_rows,
    dwd_unique_apply,
    ods_rows - dwd_rows AS row_diff,
    ods_unique_apply - dwd_unique_apply AS unique_diff
FROM ods_stats, dwd_stats;
```

```

+------------+--------------------+------------+--------------------+------------+---------------+
|   ods_rows |   ods_unique_apply |   dwd_rows |   dwd_unique_apply |   row_diff |   unique_diff |
|------------+--------------------+------------+--------------------+------------+---------------|
|       5000 |               5000 |       5000 |               5000 |          0 |             0 |
+------------+--------------------+------------+--------------------+------------+---------------+
```

### 3.3 关键字段分布对比（决策结果）

```sql
WITH ods_dec AS (
    SELECT
        decision,
        COUNT(*) AS cnt
    FROM v_decision
    WHERE dt = '2024-01-01'
    GROUP BY decision
),
dwd_dec AS (
    SELECT
        decision,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE dt = '2024-01-01'
    GROUP BY decision
)
SELECT
    COALESCE(o.decision, d.decision) as decision,
    COALESCE(o.cnt, 0) as ods_cnt,
    COALESCE(d.cnt, 0) as dwd_dnt,
    COALESCE(o.cnt, 0) - COALESCE(d.cnt, 0) as diff
FROM ods_dec o
FULL OUTER JOIN dwd_dec d ON o.decision = d.decision
ORDER BY decision;
```

```

+------------+-----------+-----------+--------+
| decision   |   ods_cnt |   dwd_dnt |   diff |
|------------+-----------+-----------+--------|
| PASS       |      1679 |      1679 |      0 |
| REJECT     |      1687 |      1687 |      0 |
| REVIEW     |      1634 |      1634 |      0 |
+------------+-----------+-----------+--------+
```

**分析**：差异源于同一申请在 ODS 中可能有多次决策（如初审、复审），DWD 只保留最新一条，导致计数减少。

### 3.4 差异样本抽取（金额不一致）

```sql
WITH compare AS (
    SELECT
        COALESCE(o.apply_id, d.apply_id) as apply_id,
        o.amount AS ods_amount,
        d.amount AS dwd_amount
    FROM v_apply o
    FULL OUTER JOIN dwd_apply_latest d ON o.apply_id = d.apply_id AND o.dt = d.dt
    WHERE o.dt = '2024-01-01' or d.dt = '2024-01-01'
)
SELECT * 
FROM compare
WHERE ods_amount IS NULL OR dwd_amount IS NULL OR ods_amount != dwd_amount
limit 10;
```

```
+------------+--------------+--------------+
| apply_id   | ods_amount   | dwd_amount   |
|------------+--------------+--------------|
+------------+--------------+--------------+
```

**说明**：实际应只显示差异行，这里仅作示例结构。

### 3.5 综合对账报表（一次扫描）

```sql
WITH ods AS (
    SELECT 
        COUNT(*) AS ods_rows,
        COUNT(DISTINCT apply_id) AS ods_unique,
        SUM(amount::INT) AS ods_amount_sum
    FROM v_apply
    WHERE dt = '2024-01-01'
),
dwd AS (
    SELECT 
        COUNT(*) AS dwd_rows,
        COUNT(DISTINCT apply_id) as dwd_unique,
        SUM(amount::INT) AS dwd_amount_sum
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT
    ods_rows,dwd_rows, ods_rows - dwd_rows AS row_diff,
    ods_unique, dwd_unique, ods_unique - dwd_unique as unique_diff,
    ods_amount_sum, dwd_amount_sum, ods_amount_sum - dwd_amount_sum AS amount_sum_diff
FROM ods,dwd;
```

```
+------------+------------+------------+--------------+--------------+---------------+------------------+------------------+-------------------+
|   ods_rows |   dwd_rows |   row_diff |   ods_unique |   dwd_unique |   unique_diff |   ods_amount_sum |   dwd_amount_sum |   amount_sum_diff |
|------------+------------+------------+--------------+--------------+---------------+------------------+------------------+-------------------|
|       5000 |       5000 |          0 |         5000 |         5000 |             0 |      1.25788e+08 |      1.25788e+08 |                 0 |
+------------+------------+------------+--------------+--------------+---------------+------------------+------------------+-------------------+
```

**分析**：金额总和差异 可能是因为重复记录导致金额被多次计算。

## 4. 口径与边界说明

| 口径要素       | 说明                                                         |
| :------------- | :----------------------------------------------------------- |
| **对账范围**   | 按 `dt` 分区进行，确保日期对齐。若涉及迟到数据，需约定对账时间口径（事件日 vs 加载日）。 |
| **主键定义**   | `apply_id` 为申请唯一标识，对账时以此关联。若存在一对多，需先对 DWD 层去重。 |
| **差异类型**   | 行数差异、主键差异、字段值差异。                             |
| **差异容忍度** | 可设定阈值（如行数差异 < 10），超过阈值需告警。              |
| **样本抽取**   | 差异样本应包含缺失行（一方存在另一方不存在）和值不一致行。   |
| **空值处理**   | 字段对比时需考虑 NULL 相等性（NULL = NULL 视为相等？通常认为 NULL 不等于 NULL，需根据业务定义）。 |

## 5. 性能点

- **分区裁剪**：对账查询务必指定 `dt`，避免全表扫描。
- **列裁剪**：只选取关联和对比所需的字段（`apply_id`, `amount`, `decision` 等）。
- **提前去重**：若 DWD 层未预先物化，可在对账 CTE 中先做窗口去重，但会增加计算量。建议预先创建 DWD 视图或表。
- **FULL OUTER JOIN**：用于找出双方不匹配的记录，但需注意性能，可先过滤后再 JOIN。

### FULL OUTER JOIN vs 其他连接（核心对比）

| 连接类型         | 保留的记录            | 典型场景                             |
| :--------------- | :-------------------- | :----------------------------------- |
| FULL OUTER JOIN  | A 所有行 + B 所有行   | 需完整展示两表所有数据（如对账）     |
| INNER JOIN       | 仅 A、B 匹配的行      | 只关注两表交集（如已支付的订单）     |
| LEFT OUTER JOIN  | A 所有行 + B 匹配的行 | 保留左表全部（如所有订单，含未支付） |
| RIGHT OUTER JOIN | B 所有行 + A 匹配的行 | 保留右表全部（如所有支付，含无订单） |



# 数据对账工具（Apache Griffin/Deequ）学习笔记

## 一、核心对账工具概述

### 1. Apache Griffin

- **定位**：Apache 基金会开源的一站式数据质量平台，聚焦企业级数据对账与全维度质量监控，支持批处理 / 流式数据场景。

- 核心原理

  ：

  - 核心能力覆盖**数据对账**（如源表与目标表数据一致性校验）、准确性、完整性、唯一性、及时性等多维度质量规则；
  - 支持多种对账模式：全量对账、增量对账、字段级对账（如金额、数量匹配）、记录级对账（如主键存在性）；
  - 提供可视化监控面板、规则配置中心、告警模块（支持邮件 / 钉钉 / Slack），可集成到大数据调度体系（如 Airflow、Azkaban）。

  

- **典型应用**：数仓分层数据对账、跨系统数据一致性校验、业务指标口径统一验证。

### 2. Deequ

- **定位**：AWS 开源的基于 Spark 的数据质量库，以 “约束校验” 为核心，适配大规模分布式数据对账场景。

- 核心原理

  ：

  - 基于 Spark 分布式计算能力，支持 PB 级数据的高效对账，通过定义「Constraint（约束）」实现对账规则（如 “源表与目标表同一主键的金额相等”“字段非空”“行数匹配”）；
  - 对账流程：定义校验规则 → 执行分布式计算 → 生成对账报告（含差异数据、不一致率、规则通过率）；
  - 无原生可视化面板，需结合 Spark UI 或自定义报表工具展示结果，可通过 API 输出告警信息。

  

- **典型应用**：大数据平台跨表对账、流式数据实时一致性校验、数据仓库 ETL 后对账。

## 二、工具核心价值与对比

### 1. 与手动编写对账 SQL 的对比

| 维度         | 手动对账 SQL                 | Apache Griffin/Deequ                                         |
| :----------- | :--------------------------- | :----------------------------------------------------------- |
| 自动化程度   | 需手动编写 / 执行 / 核对结果 | 规则配置化，支持定时调度、自动执行                           |
| 可视化能力   | 无原生可视化，需手动整理结果 | Apache Griffin 提供可视化面板，Deequ 可对接第三方报表        |
| 告警能力     | 无原生告警，需额外开发       | 内置 / 可扩展告警机制，支持异常实时通知                      |
| 适配数据规模 | 适合中小规模数据             | Apache Griffin 适配企业级全量数据，Deequ 适配大规模分布式数据 |
| 可复用性     | 脚本复用性低，改规则需重写   | 规则配置化存储，支持版本管理、一键复用                       |

### 2. 核心逻辑一致性

两类工具的底层对账逻辑与手动编写的 SQL 本质一致：

- 核心流程均为「定义对账规则 → 执行数据比对 → 输出差异结果」；
- 常见对账规则（主键一致性、字段值匹配、非空校验、行数相等）可完全覆盖手动 SQL 的对账场景；
- 差异在于工具封装了标准化的规则引擎、分布式计算能力、自动化调度与告警，避免重复开发基础对账逻辑。

## 三、落地实践建议

### 1. 短期落地方向

- 梳理现有手动对账 SQL，提炼通用对账规则（如主键存在性、金额一致性、字段非空）；
- 将高频对账 SQL 封装为可重用脚本，规范入参（如对账日期、表名）、输出（如差异数据文件、对账报告）；
- 测试脚本的通用性与稳定性，为后续集成到调度系统做准备。

### 2. 长期扩展方向

- 小规模对账场景：优先评估 Apache Griffin，快速搭建可视化对账平台，覆盖规则配置、自动执行、告警需求；
- 大规模分布式数据场景：基于 Deequ + Spark 构建对账引擎，适配 PB 级数据的高效对账；
- 集成调度系统：将封装后的对账脚本 / 工具规则集成到 Airflow 等调度平台，实现 “定时对账 → 自动告警 → 差异复盘” 的闭环。

## 四、核心总结

1. Apache Griffin 是企业级数据质量平台，主打全维度对账、可视化与告警；Deequ 是轻量级 Spark 库，聚焦大规模数据的约束式对账；
2. 工具核心逻辑与手动对账 SQL 一致，核心优势是自动化、可视化、可扩展，减少重复开发成本；
3. 落地优先级：先封装现有对账 SQL 为可重用脚本，再根据数据规模选择适配的工具集成到调度系统。

# Apache Griffin 学习资料汇总（官方 + 实战 + 进阶）

## 一、官方核心资料（权威首选）

### 1. 官网文档（中英文）

- **英文快速入门**：https://griffin.apache.org/docs/quickstart.htmlApache Griffin

- 中文快速入门：

  https://griffin.apache.org/docs/quickstart-cn.html

  Apache Griffin

  - 含环境依赖、源码编译、Measure 模块部署、数据准备、任务提交全流程

- 用户指南（UI 操作）：

  https://github.com/apache/griffin/blob/master/griffin-doc/ui/user-guide.md

  - 讲解 Measure 创建、质量维度配置、可视化面板、DQ 指标查看

- Measure 模块文档：

  https://github.com/apache/griffin/blob/master/griffin-doc/measure/griffin-tool.md

  - 命令行工具使用、环境配置文件、DQ 规则文件编写规范

### 2. GitHub 项目仓库

- 主仓库：

  https://github.com/apache/griffin

  - 源码、完整文档、Issue、PR、版本发布记录

- 文档仓库：

  https://github.com/apache/griffin-site

  - 官网静态文档源码，可本地编译查看