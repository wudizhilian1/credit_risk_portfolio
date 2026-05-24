--- 语句 1 ---
```sql
-- reconcile_3layer_apply.sql
-- 功能：对比 raw、ODS、DWD 三层申请表的行数和关键字段
-- 使用方式（通过 run_sql.py）：
--   python scripts/run_sql.py --sql sql/reconcile/reconcile_3layer_apply.sql --vars dt=2024-01-01

WITH
raw_stats AS (
    SELECT
        'raw' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::INT) AS amount_sum,
        AVG(amount::INT) AS amount_avg
    FROM v_apply
    WHERE dt = '2024-01-04'
),
ods_stats AS (
    SELECT
        'ods' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::INT) AS amount_sum,
        AVG(amount::INT) AS amount_avg
    FROM ods_apply
    WHERE dt = '2024-01-04'
),
dwd_stats AS (
    SELECT
        'dwd' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount::INT) AS amount_sum,
        AVG(amount::INT) AS amount_avg
    FROM dwd_apply_latest
    WHERE dt = '2024-01-04'
)
SELECT * FROM raw_stats
UNION ALL
SELECT * FROM ods_stats
UNION ALL
SELECT * FROM dwd_stats
```

行数: 3

| layer   |   row_cnt |   unique_apply_cnt |   amount_sum |   amount_avg |
|:--------|----------:|-------------------:|-------------:|-------------:|
| raw     |      5000 |               5000 |   1.2677e+08 |      25354.1 |
| ods     |      5000 |               5000 |   1.2677e+08 |      25354.1 |
| dwd     |      5000 |               5000 |   1.2677e+08 |      25354.1 |
