# Day 18 实践报告：维表建模与维度关联

## 1. 练习目标
- 深入理解 **维度建模** 中维表的作用：提供业务实体（渠道、客户、策略、拒绝原因等）的丰富属性。
- 完善已有维表结构，添加更多有意义的属性字段（如渠道分组、客户等级、策略类型等）。
- 掌握使用维表与事实表进行关联查询，获取可读的维度名称。
- 编写维表管理的 DDL 脚本，并插入更多样例数据。
- 了解缓慢变化维度（SCD）的基本概念及处理策略。

## 2. 实验环境
- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 已有表：
  - 事实表：`dwd_apply_latest`、`dwd_decision_latest`
  - 基础维表：`dim_channel`、`dim_customer`、`dim_strategy`、`dim_reject_reason`（已含样例数据）
- 项目目录结构：

credit_risk_portfolio/
├── data/raw/
├── scripts/
├── sql/
│ ├── ddl/
│ │ ├── ods_tables.sql
│ │ ├── dim_sample_data.sql
│ │ ├── dwd_tables.sql
│ │ └── dim_tables_enhance.sql
│ └── queries/
│ └── day18_dim_join_examples.sql
├── docs/
└── reports/

## 3. 核心任务：维表增强与关联查询

### 3.1 维表结构增强
执行 `sql/ddl/dim_tables_enhance.sql`，为每个维表增加新字段并更新数据：

```sql
-- 渠道维表增强
ALTER TABLE dim_channel ADD COLUMN IF NOT EXISTS channel_group VARCHAR;
ALTER TABLE dim_channel ADD COLUMN IF NOT EXISTS priority INT;
UPDATE dim_channel SET channel_group = '自有', priority = 1 WHERE channel_id = 'APP';
UPDATE dim_channel SET channel_group = '自有', priority = 2 WHERE channel_id = 'WEB';
UPDATE dim_channel SET channel_group = '自有', priority = 3 WHERE channel_id = 'H5';
UPDATE dim_channel SET channel_group = '外部', priority = 4 WHERE channel_id = 'API';

-- 客户维表增强
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS gender VARCHAR;
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS city VARCHAR;
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS credit_score INT;
UPDATE dim_customer SET gender = '男', city = '北京', credit_score = 720 WHERE user_id = 'user_1';
-- ...（省略中间更新语句，脚本完整）

-- 策略维表增强
ALTER TABLE dim_strategy ADD COLUMN IF NOT EXISTS strategy_type VARCHAR;
ALTER TABLE dim_strategy ADD COLUMN IF NOT EXISTS owner_team VARCHAR;
UPDATE dim_strategy SET strategy_type = '准入', owner_team = '风控策略组' WHERE strategy_version = 'v1.0';
UPDATE dim_strategy SET strategy_type = '准入', owner_team = '风控策略组' WHERE strategy_version = 'v1.1';
UPDATE dim_strategy SET strategy_type = '额度', owner_team = '额度管理组' WHERE strategy_version = 'v2.0';

-- 拒绝原因维表增强
ALTER TABLE dim_reject_reason ADD COLUMN IF NOT EXISTS reason_category VARCHAR;
UPDATE dim_reject_reason SET reason_category = '欺诈' WHERE reason_code = 'FRAUD';
UPDATE dim_reject_reason SET reason_category = '信用' WHERE reason_code IN ('RISK_SCORE','OVER_LIMIT','INCOME_LOW');
UPDATE dim_reject_reason SET reason_category = '黑名单' WHERE reason_code = 'BLACKLIST';
UPDATE dim_reject_reason SET reason_category = '规则' WHERE reason_code IN ('AGE_LIMIT','DUPLICATE_APPLY');
```

### 3.2 维表与事实表关联查询示例

**文件：`sql/queries/day18_dim_join_examples.sql`**

```sql
-- 示例1：申请事实关联渠道名称和客户属性
SELECT
    a.apply_id,
    a.amount,
    c.channel_name,
    c.channel_group,
    cust.gender,
    cust.city,
    cust.risk_level
FROM dwd_apply_latest a
LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
LEFT JOIN dim_customer cust ON a.user_id = cust.user_id
WHERE a.dt = '2024-01-01'
LIMIT 10;
```

```
+-----------------+----------+----------------+--------------+----------+--------+
| apply_id        |   amount | channel_name   | risk_level   | gender   | city   |
|-----------------+----------+----------------+--------------+----------+--------|
| 2024-01-01_1000 |    24127 | API接口        |              |          |        |
| 2024-01-01_1016 |     9664 | API接口        |              |          |        |
| 2024-01-01_1021 |     3846 | H5页面         |              |          |        |
| 2024-01-01_1030 |    45604 | H5页面         |              |          |        |
| 2024-01-01_1033 |    49220 | API接口        |              |          |        |
| 2024-01-01_104  |    10656 | 网页端         |              |          |        |
| 2024-01-01_1074 |    22327 | 手机应用       |              |          |        |
| 2024-01-01_1076 |    24981 | H5页面         |              |          |        |
| 2024-01-01_1079 |     7545 | 网页端         |              |          |        |
| 2024-01-01_1114 |    40125 | H5页面         |              |          |        |
+-----------------+----------+----------------+--------------+----------+--------+
```

```sql
-- 示例2：统计各渠道分组（自有/外部）的申请量和通过率
WITH apply_with_channel AS (
    SELECT
        a.apply_id,
        d.decision,
        ch.channel_group
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    WHERE a.dt = '2024-01-01'
)
SELECT
    channel_group,
    COUNT(*) AS apply_cnt,
    SUM(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_cnt,
    ROUND(100.0 * SUM(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_rate
FROM apply_with_channel
GROUP BY channel_group;
```

```
+-----------------+-------------+------------+-------------+
| channel_group   |   apply_cnt |   pass_cnt |   pass_rate |
|-----------------+-------------+------------+-------------|
| 外部            |        1263 |        417 |       33.02 |
| 自有            |        3737 |       1262 |       33.77 |
+-----------------+-------------+------------+-------------+
```

```sql
-- 示例3：拒绝原因分类统计
SELECT
    rr.reason_category,
    COUNT(*) AS reject_cnt
FROM dwd_decision_latest d
LEFT JOIN dim_reject_reason rr ON d.reject_reason = rr.reason_code
WHERE d.decision = 'REJECT' AND d.dt = '2024-01-01'
GROUP BY rr.reason_category
ORDER BY reject_cnt DESC;
```

```
+-------------------+--------------+
| reason_category   |   reject_cnt |
|-------------------+--------------|
| 信用              |          681 |
| 欺诈              |          337 |
|                   |          336 |
| 黑名单            |          333 |
+-------------------+--------------+
```

## 4. 口径与边界说明

| 要素         | 说明                                                         |
| :----------- | :----------------------------------------------------------- |
| **维表主键** | 业务主键（如`channel_id`）应唯一，用于与事实表关联。         |
| **新增属性** | 新增字段（如`channel_group`、`gender`）为静态模拟数据，实际业务中可能随时间变化，需考虑SCD策略。 |
| **关联方式** | 事实表与维表关联使用 `LEFT JOIN`，保留事实表所有记录，维表属性缺失时显示为NULL。 |
| **NULL处理** | 若事实表的关联键（如`channel_id`）为NULL，关联后维表字段为NULL，可在分析时定义为“未知”。 |

## 5. 性能点

- 维表通常较小（几十到几百行），关联时DuckDB会优化为哈希连接，性能良好。
- 事实表的关联键（如`channel_id`）无需建立索引，DuckDB在内存中处理足够快。
- 避免在关联条件中使用函数（如`UPPER(channel_id)`），以免影响优化。

## 10. 思考题（可选）

- 如果客户风险等级每天更新，如何设计维表以支持历史回溯？
  → 采用SCD类型2，增加 `effective_date`、`expiry_date` 和 `current_flag` 字段，每次变化插入新行。
- 在关联查询中，如果事实表的`channel_id`为NULL，关联结果中渠道相关字段会怎样？应如何处理？
  → 显示为NULL，可在业务逻辑中定义为“未知渠道”，或通过 `COALESCE` 赋予默认值。
- 维表设计中，用代理键（自增ID）好还是业务主键好？各自的优缺点是什么？
  → 代理键便于管理变化（如业务主键可能重复或变化），且节省存储；业务主键便于理解和直接关联，但应对变化时需要SCD策略。本项目因数据量小直接使用业务主键。