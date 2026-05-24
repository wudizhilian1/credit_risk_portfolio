# Day 26 实践报告：对账 v0：raw vs ODS vs DWD 行数&关键字段一致性

## 1. 练习目标

- 理解数据对账（Reconciliation）在数仓多层级间的必要性：确保数据在抽取、转换、加载过程中没有丢失、重复或错误。
- 掌握使用 SQL 进行三层对账（原始视图 → ODS 表 → DWD 表）的方法，包括行数对比、关键字段值分布对比、差异样本抽取。
- 明确对账口径：主键、关联方式、差异容忍度。
- 学习识别常见不一致原因（ETL逻辑错误、迟到数据、重复、空值等）。
- 将对账结果可视化或记录为报告，为后续自动化监控提供基础。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 数据范围：2024-01-01 至 2024-01-30（含迟到数据）
- 涉及表/视图：
  - raw：`v_apply`（基于分区 Parquet 实时读取）
  - ODS：`ods_apply`（已通过 Day 22 ETL 加载）
  - DWD：`dwd_apply_latest`（已通过 Day 23 去重 ETL 生成）
- 项目目录：

credit_risk_portfolio/
├── sql/
│   └── reconcile/
│       └── reconcile_diff_samples.sql
│   └── hql/
│       └── day26_reconcile_counts.sql
├── docs/
└── reports/
    └── reconcile_2024-01-01.md

## 3. 核心任务执行

### 3.1 三层行数与关键字段对比

**脚本：`sql/hql/day26_reconcile_counts.sql`**

```sql
-- 功能：对比 raw、ODS、DWD 三层申请表的行数与关键字段
WITH
raw_stats AS (
    SELECT
        'raw' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::decimal) AS amount_sum,
        AVG(amount::decimal) AS amount_avg
    FROM v_apply
    WHERE dt = '2024-01-01'
),
ods_stats AS (
    SELECT
        'ods' AS layer,
        COUNT(*) as row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::decimal) AS amount_sum,
        AVG(amount::decimal) AS amount_avg
    FROM ods_apply
    WHERE dt = '2024-01-01'
),
dwd_stats AS (
    SELECT
        'dwd' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::decimal) AS amount_sum,
        AVG(amount::decimal) AS amount_avg
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT * FROM raw_stats,
UNION ALL
SELECT * FROM ods_stats
UNION ALL
SELECT * FROM dwd_stats;
```

**执行结果**：

```
+---------+-----------+--------------------+--------------+--------------+
| layer   |   row_cnt |   unique_apply_cnt |   amount_sum |   amount_avg |
|---------+-----------+--------------------+--------------+--------------|
| raw     |      5000 |               5000 |  1.25788e+08 |      25157.7 |
| ods     |      5000 |               5000 |  1.25788e+08 |      25157.7 |
| dwd     |      5000 |               5000 |  1.25788e+08 |      25157.7 |
+---------+-----------+--------------------+--------------+--------------+
```

### 3.2 差异样本提取

**脚本：`sql/reconcile/reconcile_diff_samples.sql`**

```sql
-- ODS 与 DWD 差异
SELECT 'ods_not_in_dwd' AS diff_type, o.apply_id
FROM ods_apply o
LEFT JOIN dwd_apply_latest d ON o.apply_id = d.apply_id AND o.dt = d.dt
WHERE o.dt = '2024-01-01' AND d.apply_id IS NULL
UNION ALL
SELECT 'dwd_not_in_ods', d.apply_id
FROM dwd_apply_latest d
LEFT JOIN ods_apply o ON d.apply_id = o.apply_id AND d.dt = o.dt
WHERE d.dt = '2024-01-01' AND o.apply_id IS NULL;
```

```
+-------------+------------+
| diff_type   | apply_id   |
|-------------+------------|
+-------------+------------+
```

```sql
-- ODS 与 DWD 差异
SELECT 'ods_not_in_dwd' AS diff_type, o.apply_id
FROM ods_apply o
LEFT JOIN dwd_apply_latest d ON o.apply_id = d.apply_id AND o.dt = d.dt
WHERE o.dt = '2024-01-01' AND d.apply_id IS NULL
UNION ALL
SELECT 'dwd_not_in_ods', d.apply_id
FROM dwd_apply_latest d
LEFT JOIN ods_apply o ON d.apply_id = o.apply_id AND d.dt = o.dt
WHERE d.dt = '2024-01-01' AND o.apply_id IS NULL;
```

```
+-------------+------------+
| diff_type   | apply_id   |
|-------------+------------|
+-------------+------------+
```

### 3.3 创建对账汇总表并插入记录

```sql
CREATE TABLE IF NOT EXISTS reconcile_summary (
    check_date DATE,
    layer1 VARCHAR,
    layer2 VARCHAR,
    rows_layer1 INT,
    rows_layer2 INT,
    diff_count INT,
    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO reconcile_summary (check_date, layer1, layer2, rows_layer1, rows_layer2, diff_count)
VALUES (
    '2024-01-01',
    'ods',
    'dwd',
    (SELECT COUNT(*) FROM ods_apply WHERE dt = '2024-01-01'),
    (SELECT COUNT(*) FROM dwd_apply_latest WHERE dt = '2024-01-01'),
    (SELECT COUNT(*) FROM (
        SELECT apply_id FROM ods_apply WHERE dt = '2024-01-01'
        EXCEPT
        SELECT apply_id FROM dwd_apply_latest WHERE dt = '2024-01-01'
    ) t)
);
```

```sql
SELECT * FROM reconcile_summary;
```

```
+---------------------+----------+----------+---------------+---------------+--------------+----------------------------+
| check_date          | layer1   | layer2   |   rows_layer1 |   rows_layer2 |   diff_count | check_time                 |
|---------------------+----------+----------+---------------+---------------+--------------+----------------------------|
| 2024-01-01 00:00:00 | raw      | ods      |          5000 |          5000 |            0 | 2026-03-14 17:44:21.623290 |
+---------------------+----------+----------+---------------+---------------+--------------+----------------------------+
```

## 4. 口径与边界说明

| 要素           | 说明                                                         |
| :------------- | :----------------------------------------------------------- |
| **对账范围**   | 按 `dt` 分区进行，确保日期对齐。若涉及迟到数据，需约定对账时间口径（本例按加载日）。 |
| **主键定义**   | `apply_id` 为申请唯一标识，对账时以此关联。                  |
| **差异类型**   | 行数差异、主键差异、字段值差异（如金额总和）。               |
| **差异容忍度** | 对于去重导致的差异，需在文档中说明；业务上应明确预期行数范围。 |
| **样本抽取**   | 差异样本应包含缺失行（一方存在另一方不存在）和值不一致行，便于人工排查。 |

## 5. 性能点

- 对账查询务必指定 `dt` 过滤，利用分区裁剪，避免全表扫描。
- 列裁剪：只选取关联和对比所需的字段（`apply_id`, `amount` 等）。
- 对于大表，可先抽样再对比，或使用 `COUNT(*)` 近似。
- 将对账结果存入汇总表，避免重复计算。

## 10. 思考题

- 如果发现 raw 与 ODS 行数不一致，可能的原因有哪些？（ETL 过滤错误、重复数据、分区遗漏、迟到数据未正确处理）
- 如何将对账任务自动化并设置告警？（可每天运行脚本，将结果写入监控表，若差异超阈值则发送邮件或触发告警）
- 对账过程中，如果字段值差异（如金额总和）超过 1%，应如何进一步定位？（可对比金额分布直方图，或抽样查看具体记录，找出异常值）