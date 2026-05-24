# Day 13 实践报告：数据质量基础 SQL

## 1. 练习目标
- 理解数据质量监控的核心指标：**缺失率**、**重复率**、**范围异常**。
- 掌握使用一次扫描计算多项 DQ 指标的优化技巧。
- 明确各指标的口径定义（主键、阈值、异常分类）。
- 输出标准化的 DQ 报告，为后续监控告警打基础。

## 2. 实验环境
- DuckDB 版本：0.x.x
- 数据路径：`data/raw/apply/` 按 `dt` 分区（2024-01-01 至 2024-01-10，共 10 天）
- 视图：`v_apply`（基于分区 Parquet 文件创建，`hive_partitioning=1`）
- 数据规模：每天约 5,000 条申请记录，用户 ID 随机。

## 3. 核心 SQL 及结果

### 3.1 基础统计：总行数、唯一主键数、重复率
```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT apply_id) AS unique_apply,
    ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT apply_id)) / COUNT(*), 2) AS duplicate_rate_pct
FROM v_apply
WHERE dt = '2024-01-01';
```

```
+--------------+----------------+----------------------+
|   total_rows |   unique_apply |   duplicate_rate_pct |
|--------------+----------------+----------------------|
|         5000 |           5000 |                    0 |
+--------------+----------------+----------------------+
```

### 3.2 缺失率统计（关键字段）

```sql
SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN user_id IS NULL OR user_id = '' THEN 1 ELSE 0 END) AS user_id_missing,
    ROUND(100.0 * sum(case when user_id is null or user_id = '' then 1 else 0 end) / count(*), 2)
    as user_id_missing_pct,
    SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) as amount_missing,
    ROUND(100.0 * SUM(CASE WHEN amount is null then 1 else 0 end) / count(*), 2) as amount_missing_pct,
    SUM(CASE WHEN channel_id IS NULL OR channel_id = '' then 1 else 0 end) as channel_missing,
    ROUND(100.0 * SUM(CASE WHEN channel_id IS NULL OR channel_id = '' THEN 1 ELSE 0 END) / COUNT(*), 2) AS 
    channel_missing_pct
    from v_apply
    where dt = '2024-01-01';
```

```
+--------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------+
|   total_rows |   user_id_missing |   user_id_missing_pct |   amount_missing |   amount_missing_pct |   channel_missing |   channel_missing_pct |
|--------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------|
|         5000 |                 0 |                     0 |                0 |                    0 |                 0 |                     0 |
+--------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------+
```

### 3.3 范围异常检测（以 `amount` 为例）

假设正常金额应在 1000～50000 之间，超出此范围视为异常。

```sql
SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN amount < '1000' OR amount > '50000' THEN 1 ELSE 0 END) AS amount_outlier,
    ROUND(100.0 * SUM(CASE WHEN amount < '1000' OR amount > '50000' THEN 1 ELSE 0 END)/ 
    COUNT(*), 2) AS amount_outlier_pct
FROM v_apply
where dt = '2024-01-01'
```

```
+--------------+------------------+----------------------+
|   total_rows |   amount_outlier |   amount_outlier_pct |
|--------------+------------------+----------------------|
|         5000 |              550 |                   11 |
+--------------+------------------+----------------------+
```

### 3.4 综合 DQ 报表（一次扫描）

将上述所有指标合并为一个查询，避免多次扫描同一张表：

```sql
WITH dq_apply AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(DISTINCT apply_id) as unique_apply,
        SUM(CASE WHEN user_id IS NULL OR user_id = '' THEN 1 ELSE 0 END) AS user_id_missing,
        SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) AS amount_missing,
        SUM(CASE WHEN channel_id IS NULL OR channel_id = '' THEN 1 ELSE 0 END) AS channel_missing,
        SUM(CASE WHEN amount < '1000' or amount > '50000' then 1 else 0 end) as amount_outlier
    FROM v_apply
    WHERE dt = '2024-01-01'
)
SELECT
    total_rows,
    unique_apply,
    ROUND(100.0 * (total_rows - unique_apply) / total_rows, 2) AS duplicate_rate_pct,
    user_id_missing,
    ROUND(100.0 * user_id_missing / total_rows, 2) AS user_id_missing_pct,
    amount_missing,
    ROUND(100.0 * amount_missing / total_rows, 2) AS amount_missing_pct,
    channel_missing,
    ROUND(100.0 * channel_missing / total_rows, 2) AS channel_missing_pct,
    amount_outlier,
    ROUND(100.0 * amount_outlier / total_rows, 2) AS amount_outlier_pct
FROM dq_apply;
```

```

+--------------+----------------+----------------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------+------------------+----------------------+
|   total_rows |   unique_apply |   duplicate_rate_pct |   user_id_missing |   user_id_missing_pct |   amount_missing |   amount_missing_pct |   channel_missing |   channel_missing_pct |   amount_outlier |   amount_outlier_pct |
|--------------+----------------+----------------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------+------------------+----------------------|
|         5000 |           5000 |                    0 |                 0 |                     0 |                0 |                    0 |                 0 |                     0 |              550 |                   11 |
+--------------+----------------+----------------------+-------------------+-----------------------+------------------+----------------------+-------------------+-----------------------+------------------+----------------------+
```

### 3.5 按日期范围统计 DQ（可选）

若要监控多日趋势，可以按 `dt` 分组：

```sql
SELECT 
    dt,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT apply_id) AS unique_apply,
    ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT apply_id)) / count(*), 2) AS duplicate_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS amount_missing_pct,
    ROUND(100.0 * SUM(CASE WHEN amount < '1000' or amount > '50000' THEN 1 ELSE 0 END) / COUNT(*), 2) AS amount_outlier_pct
FROM v_apply
WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
GROUP BY dt
ORDER BY dt;
```

```
+---------------------+--------------+----------------+----------------------+----------------------+----------------------+
| dt                  |   total_rows |   unique_apply |   duplicate_rate_pct |   amount_missing_pct |   amount_outlier_pct |
|---------------------+--------------+----------------+----------------------+----------------------+----------------------|
| 2024-01-01 00:00:00 |         5000 |           5000 |                    0 |                    0 |                11    |
| 2024-01-02 00:00:00 |         5000 |           5000 |                    0 |                    0 |                 9.52 |
| 2024-01-03 00:00:00 |         5000 |           5000 |                    0 |                    0 |                10.2  |
| 2024-01-04 00:00:00 |         5000 |           5000 |                    0 |                    0 |                11.2  |
| 2024-01-05 00:00:00 |         5000 |           5000 |                    0 |                    0 |                10.02 |
| 2024-01-06 00:00:00 |         5000 |           5000 |                    0 |                    0 |                10.02 |
| 2024-01-07 00:00:00 |         5000 |           5000 |                    0 |                    0 |                10.5  |
| 2024-01-08 00:00:00 |         5000 |           5000 |                    0 |                    0 |                10.48 |
| 2024-01-09 00:00:00 |         5000 |           5000 |                    0 |                    0 |                 9.8  |
| 2024-01-10 00:00:00 |         5000 |           5000 |                    0 |                    0 |                 9.76 |
+---------------------+--------------+----------------+----------------------+----------------------+----------------------+
```

## 4. 口径与边界说明

| 口径要素     | 说明                                                         |
| :----------- | :----------------------------------------------------------- |
| **主键定义** | `apply_id` 为申请单唯一标识，理论上不应重复。若出现重复，说明源系统存在重复上报或逻辑错误。 |
| **缺失定义** | 字段值为 NULL 或空字符串（根据业务判断）视为缺失。           |
| **异常阈值** | 金额 `amount` 正常范围定为 1000～50000（可根据实际业务调整）。超出此范围视为异常值。 |
| **计算方式** | 所有指标均基于当日分区数据计算，确保统计范围清晰。           |
| **重复率**   | `(总行数 - 唯一主键数) / 总行数 * 100%`，反映数据冗余程度。  |
| **缺失率**   | `缺失行数 / 总行数 * 100%`，反映字段完整性。                 |
| **异常率**   | `异常行数 / 总行数 * 100%`，反映数据质量风险。               |

## 5. 性能点

- **一次扫描计算多项**：使用 `SUM(CASE ...)` 在单次表扫描中计算多个指标，避免多次读取同一份数据。
- **分区裁剪**：通过 `dt` 过滤，只扫描所需分区，减少 I/O。
- **列裁剪**：虽然用了 `*` 但实际只访问了 `apply_id`, `user_id`, `amount`, `channel_id`, `dt`，DuckDB 会自动列裁剪，无需担心。
- **结果小**：最终输出只有一行或按天分组的小表，后续处理轻量。



# 数据质量监控工具（Great Expectations/Deequ）学习报告

## 一、核心工具概述

### 1. Great Expectations

- **定位**：开源数据质量监控工具（Python 生态），无强依赖计算框架，适配中小规模 / 本地数据场景。

- 核心原理

  ：

  - 核心概念为「Expectation（数据期望）」：通过代码 / 配置定义数据应满足的规则（如 “列值非空”“数值范围在 0-100”“字段唯一”“符合正则格式” 等）；
  - 支持批量 / 流式数据验证，自动生成可视化数据文档（Data Docs）和验证报告；
  - 可集成到数据流水线（如 Airflow），实现数据质量问题的实时告警。

  

- **典型应用**：本地数据集质量校验、结构化数据规则验证、数据文档自动生成。

### 2. Deequ

- **定位**：AWS 开源的基于 Spark 的数据质量库，专为大规模、分布式数据场景设计。

- 核心原理：

  - 基于 Spark 分布式计算能力，支持 PB 级数据的质量校验；
  - 通过「Check」定义质量规则（如 “均值范围”“缺失率≤5%”“唯一值数量”），「Constraint」细化规则约束；
  - 输出质量校验结果和指标统计，适配大数据平台（如 EMR、Spark 集群）。

  

- **典型应用**：大数据平台数据质量监控、流式数据实时校验、分布式数据仓库规则检查。

## 二、工具核心价值

### 1. 与手动编写 DQ SQL 的对比

| 维度         | 手动 DQ SQL                | Great Expectations/Deequ                                     |
| :----------- | :------------------------- | :----------------------------------------------------------- |
| 自动化程度   | 需手动编写 / 维护 SQL 脚本 | 规则配置化，支持一键执行、定时调度                           |
| 可视化能力   | 无原生可视化，需额外加工   | 自动生成数据文档、校验报告、问题看板                         |
| 扩展性       | 新增规则需重新编写 SQL     | 支持自定义 Expectation/Constraint，插件化扩展                |
| 适配数据规模 | 适合中小规模数据           | Great Expectations 适配本地 / 中小数据，Deequ 适配大规模分布式数据 |
| 可维护性     | 规则分散在 SQL 中，难管理  | 规则集中配置，版本化管理，可追溯                             |

### 2. 核心思想一致性

两类工具的底层逻辑与手动编写 DQ SQL 本质一致：

- 核心均为「定义规则 → 执行校验 → 输出结果」；
- 常见校验规则（非空、唯一、值域、格式、完整性）可完全覆盖手动 DQ SQL 的检查场景；
- 差异仅在于工具提供了标准化、自动化、可视化的封装，避免重复编写基础校验逻辑。

## 三、落地建议

### 1. 短期尝试方向

- 优先基于 Great Expectations 对本地数据集执行质量检查：
  1. 定义基础 Expectation（如字段非空、数值范围、格式校验）；
  2. 生成数据文档，对比手动 DQ SQL 的校验结果；
  3. 验证工具的自动化能力与本地数据场景的适配性。

### 2. 长期扩展方向

- 若涉及大规模分布式数据，可评估 Deequ + Spark 集群的落地方案；
- 将数据质量规则与现有数据流水线集成，实现 “数据入库 → 质量校验 → 异常告警” 的自动化流程；
- 基于工具的可视化报告，建立数据质量监控看板，降低问题定位成本。

## 四、核心总结

1. Great Expectations 适配本地 / 中小规模数据，主打规则配置化、文档自动化；Deequ 适配大规模分布式数据，依托 Spark 实现高效校验；
2. 工具核心逻辑与手动 DQ SQL 一致，核心优势是自动化、可视化、可扩展，减少重复开发；
3. 落地优先级：先通过 Great Expectations 验证本地数据质量检查，再根据数据规模评估 Deequ 的应用场景。

## 一、Great Expectations 官方文档

### 1. 主入口（权威）

- **官网文档**：https://docs.greatexpectations.io/
- **GitHub 仓库**：https://github.com/great-expectations/great_expectations
- **示例项目**：https://github.com/great-expectations/great_expectations/tree/develop/examples

## 二、Deequ 官方文档

### 1. 主入口（权威）

- **GitHub 主页（含文档）**：https://github.com/awslabs/deequ
- **AWS 官方博客（入门）**：https://aws.amazon.com/blogs/big-data/test-data-quality-at-scale-with-deequ/
- **PyDeequ（Python 接口）**：https://github.com/awslabs/python-deequ