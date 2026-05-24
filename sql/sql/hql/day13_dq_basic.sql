--基础统计：总行数、唯一主键数、重复率
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT apply_id) as unique_apply,
    ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT apply_id)) / COUNT(*), 2) as duplicate_rate_pct
FROM v_apply
where dt = '2024-01-01';
--缺失率统计（关键字段）
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
--范围异常检测
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN amount < '1000' OR amount > '50000' THEN 1 ELSE 0 END) AS amount_outlier,
    ROUND(100.0 * SUM(CASE WHEN amount < '1000' OR amount > '50000' THEN 1 ELSE 0 END)/
    COUNT(*), 2) AS amount_outlier_pct
FROM v_apply
where dt = '2024-01-01';
--综合 DQ 报表
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
--按日期范围统计 DQ（可选）
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