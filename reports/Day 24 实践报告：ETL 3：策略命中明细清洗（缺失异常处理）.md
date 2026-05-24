# Day 24 实践报告：ETL 3：策略命中明细清洗（缺失/异常处理）

## 1. 练习目标

- 掌握数据清洗的核心操作：处理缺失值、异常值、标准化映射。
- 理解在风控场景中，策略命中明细数据的常见质量问题（如空值、非法值、格式不一）。
- 编写 SQL 实现清洗规则，并写入新的清洗表（`dwd_rule_hit_cleaned`）。
- 学习使用 `CASE WHEN`、`COALESCE`、`TRY_CAST` 等函数处理脏数据。
- 记录数据质量规则文档，为后续监控告警提供依据。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 已有 ODS 表：`ods_apply`、`ods_decision`、`ods_rule_hit`（模拟脏数据）
- 目标 DWD 表：`dwd_rule_hit_cleaned`
- 审计表：`etl_audit`（需包含 `description` 列）
- 项目目录：

credit_risk_portfolio/
├── sql/
│   └── etl/
│       └── create_ods_rule_hit.sql（可选）

│   └── hql/

│       └── day24_clean_mapping.sql

├── docs/
│   └── data_quality_rules.md
└── reports/
    └── day24_cleaning_report.md

## 3. 核心任务执行

### 3.1 创建模拟脏数据表 `ods_rule_hit`

执行以下 SQL 创建包含脏数据的原始表：

```sql
CREATE TABLE IF NOT EXISTS ods_rule_hit (
    apply_id          VARCHAR,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_flag          VARCHAR,
    hit_time          VARCHAR,
    dt                DATE
);

INSERT INTO ods_rule_hit VALUES
    ('2024-01-01_100', 'R001', '欺诈规则', '1', '2024-01-01 10:15:23', '2024-01-01'),
    ('2024-01-01_100', 'R002', '多头借贷', '0', '2024-01-01 10:16:10', '2024-01-01'),
    ('2024-01-01_101', 'R001', '欺诈规则', 'TRUE', '2024-01-01 11:20:00', '2024-01-01'),
    ('2024-01-01_101', 'R003', '黑名单', 'false', '2024-01-01 11:21:30', '2024-01-01'),
    ('2024-01-01_102', 'R001', '欺诈规则', '', NULL, '2024-01-01'),
    ('2024-01-01_102', 'R004', NULL, 'Yes', '2024-01-01 12:00:00', '2024-01-01'),
    ('2024-01-01_103', 'R002', '多头借贷', '2', '2024-01-01 13:00:00', '2024-01-01'),
    ('2024-01-01_104', NULL, '未知规则', '1', '2024-01-01 14:00:00', '2024-01-01'),
    ('2024-01-01_105', 'R005', '收入验证', '1', '2024-01-01 15:30:00', '2024-01-01');
```

原始数据统计：

```sql
SELECT COUNT(*) FROM ods_rule_hit;  -- 9 行
```

### 3.2 编写清洗 ETL 脚本 `ods_rule_hit_clean.sql`

```sql
-- sql/etl/ods_rule_hit_clean.sql
-- 功能：清洗 ods_rule_hit 表，写入 dwd_rule_hit_cleaned

BEGIN TRANSACTION;

-- 1. 创建目标清洗表（如果不存在）
CREATE TABLE IF NOT EXISTS dwd_rule_hit_cleaned (
    apply_id          VARCHAR NOT NULL,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_flag          BOOLEAN,
    hit_time          TIMESTAMP,
    dt                DATE NOT NULL
);

-- 2. 清空目标表（幂等）
DELETE FROM dwd_rule_hit_cleaned;

-- 3. 清洗并插入数据
INSERT INTO dwd_rule_hit_cleaned (apply_id, rule_id, rule_name, hit_flag, hit_time, dt)
SELECT
    apply_id,
    rule_id,
    rule_name,
    CASE
        WHEN LOWER(TRIM(hit_flag)) IN ('1', 'true', 'yes') THEN TRUE
        WHEN LOWER(TRIM(hit_flag)) IN ('0', 'false', 'no') THEN FALSE
        ELSE NULL
    END AS hit_flag,
    CASE
        WHEN hit_time IS NULL OR hit_time = '' THEN NULL
        ELSE TRY_CAST(hit_time AS TIMESTAMP)
    END AS hit_time,
    dt
FROM ods_rule_hit
WHERE apply_id IS NOT NULL AND apply_id != '';

-- 4. 确保审计表有 description 列（如无则添加）
ALTER TABLE etl_audit ADD COLUMN IF NOT EXISTS description VARCHAR;  -- DuckDB 不支持 IF NOT EXISTS，需手动执行一次

-- 5. 记录审计信息
INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_rule_hit_cleaned', 'CLEAN', COUNT(*), '清洗 ods_rule_hit'
FROM dwd_rule_hit_cleaned;

COMMIT;

-- 6. 输出统计信息
SELECT '清洗前原始行数' AS stage, COUNT(*) FROM ods_rule_hit
UNION ALL
SELECT '清洗后有效行数', COUNT(*) FROM dwd_rule_hit_cleaned
UNION ALL
SELECT 'hit_flag 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_flag IS NULL
UNION ALL
SELECT 'hit_time 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_time IS NULL;
```



**注意**：`ALTER TABLE etl_audit ADD COLUMN description VARCHAR;` 需事先手动执行一次，或在脚本中先检查，但 DuckDB 无 `IF NOT EXISTS` 语法。我们手动执行了该命令。

### 3.3 执行清洗脚本

在 DuckDB CLI 中运行：

```bash
duckdb dev.duckdb
.read sql/hql/day24_clean_mapping.sql
```



**执行输出**：

text

```
┌──────────────────────────┬───────────┐
│          stage           │ count(*)  │
│         varchar          │   int64   │
├──────────────────────────┼───────────┤
│ 清洗前原始行数           │         9 │
│ 清洗后有效行数           │         9 │
│ hit_flag 为 NULL 行数     │         2 │
│ hit_time 为 NULL 行数     │         1 │
└──────────────────────────┴───────────┘
```

### 3.4 验证清洗结果

#### 查看清洗后数据（前5行）

sql

```sql
SELECT * FROM dwd_rule_hit_cleaned LIMIT 10;
```

```
+----------------+-----------+-------------+------------+---------------------+---------------------+
| apply_id       | rule_id   | rule_name   | hit_flag   | hit_time            | dt                  |
|----------------+-----------+-------------+------------+---------------------+---------------------|
| 2024-01-01_100 | R001      | 欺诈规则    | True       | 2024-01-01 10:15:23 | 2024-01-01 00:00:00 |
| 2024-01-01_100 | R002      | 多头借贷    | False      | 2024-01-01 10:16:10 | 2024-01-01 00:00:00 |
| 2024-01-01_101 | R001      | 欺诈规则    | True       | 2024-01-01 11:20:00 | 2024-01-01 00:00:00 |
| 2024-01-01_101 | R003      | 黑名单      | False      | 2024-01-01 11:21:30 | 2024-01-01 00:00:00 |
| 2024-01-01_102 | R001      | 欺诈规则    | <NA>       | NaT                 | 2024-01-01 00:00:00 |
| 2024-01-01_102 | R004      |             | True       | 2024-01-01 12:00:00 | 2024-01-01 00:00:00 |
| 2024-01-01_103 | R002      | 多头借贷    | <NA>       | 2024-01-01 13:00:00 | 2024-01-01 00:00:00 |
| 2024-01-01_104 |           | 未知规则    | True       | 2024-01-01 14:00:00 | 2024-01-01 00:00:00 |
| 2024-01-01_105 | R005      | 收入验证    | True       | 2024-01-01 15:30:00 | 2024-01-01 00:00:00 |
+----------------+-----------+-------------+------------+---------------------+---------------------+
```

#### 分组统计 hit_flag

sql

```sql
SELECT hit_flag, COUNT(*) FROM dwd_rule_hit_cleaned GROUP BY hit_flag;
```

```
+------------+----------------+
| hit_flag   |   count_star() |
|------------+----------------|
| False      |              2 |
| NULL       |              2 |
| True       |              5 |
+------------+----------------+
```

#### 检查时间转换

sql

```sql
SELECT hit_time, COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_time IS NOT NULL GROUP BY hit_time;
```

```
+---------------------+----------------+
| hit_time            |   count_star() |
|---------------------+----------------|
| 2024-01-01 11:20:00 |              1 |
| 2024-01-01 11:21:30 |              1 |
| 2024-01-01 12:00:00 |              1 |
| 2024-01-01 10:15:23 |              1 |
| 2024-01-01 15:30:00 |              1 |
| 2024-01-01 13:00:00 |              1 |
| 2024-01-01 10:16:10 |              1 |
| 2024-01-01 14:00:00 |              1 |
+---------------------+----------------+
```

### 3.5 更新数据质量规则文档

 `docs/data_quality_rules.md` 

## 4. 口径与边界说明

| 要素           | 说明                                                         |
| :------------- | :----------------------------------------------------------- |
| **清洗原则**   | 尽量保留原始信息，仅对明确错误的字段进行标准化；无法修复的置 NULL，不丢弃整行（除非主键缺失）。 |
| **布尔标准化** | 支持多种常见表示形式，统一为 `BOOLEAN` 类型，便于后续分析。  |
| **时间转换**   | 使用 `TRY_CAST` 避免转换失败导致整个插入失败，无效值置 NULL。 |
| **幂等性**     | 通过先清空目标表再插入实现，多次执行结果一致。               |
| **审计**       | 记录清洗前后的行数及 NULL 统计，便于监控数据质量。           |

## 5. 性能点

- 清洗逻辑在插入时逐行计算，对小型表性能无影响。
- 若数据量巨大，可考虑分批处理，但当前模拟数据量小，直接全量处理即可。
- 可在清洗后对常用查询字段（如 `apply_id`）建立索引，但 DuckDB 会自动优化。

## 10. 思考题

- 如果 `hit_flag` 的非法值比例超过 5%，应触发告警。如何设计这样的监控？
  → 可每日统计非法值比例（`COUNT(CASE WHEN hit_flag IS NULL THEN 1 END)/COUNT(*)`），与阈值比较，超过则写入告警表。
- 清洗后的数据中，`hit_flag` 为 NULL 的行对后续分析有何影响？
  → 分析时应排除或单独处理，例如在计算规则命中率时，NULL 表示未知，不应计入分母或分子。
- 如何将清洗规则参数化，以便适应不同数据源的映射规则？
  → 可维护映射表 `ref_hit_flag_mapping`，将源值映射为目标布尔值，通过 JOIN 实现，避免硬编码。