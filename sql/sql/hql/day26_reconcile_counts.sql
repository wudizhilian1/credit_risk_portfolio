-- sql/reconcile/reconcile_3layer_apply.sql
-- 功能：对比 raw、ODS、DWD 三层申请表的行数与关键字段

WITH
raw_stats AS (
    SELECT
        'raw' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount) AS amount_sum,
        AVG(amount) AS amount_avg
    FROM v_apply
    WHERE dt = '2024-01-01'
),
ods_stats AS (
    SELECT
        'ods' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount) AS amount_sum,
        AVG(amount) AS amount_avg
    FROM ods_apply
    WHERE dt = '2024-01-01'
),
dwd_stats AS (
    SELECT
        'dwd' AS layer,
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT apply_id) AS unique_apply_cnt,
        SUM(amount) AS amount_sum,
        AVG(amount) AS amount_avg
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT * FROM raw_stats
UNION ALL
SELECT * FROM ods_stats
UNION ALL
SELECT * FROM dwd_stats;

-- raw 与 ODS 差异
SELECT 'raw_not_in_ods' AS diff_type, r.apply_id
FROM v_apply r
LEFT JOIN ods_apply o ON r.apply_id = o.apply_id AND r.dt = o.dt
WHERE r.dt = '2024-01-01' AND o.apply_id IS NULL
UNION ALL
SELECT 'ods_not_in_raw', o.apply_id
FROM ods_apply o
LEFT JOIN v_apply r ON o.apply_id = r.apply_id AND o.dt = r.dt
WHERE o.dt = '2024-01-01' AND r.apply_id IS NULL;

