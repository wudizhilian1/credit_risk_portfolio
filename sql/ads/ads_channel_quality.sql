CREATE TABLE IF NOT EXISTS ads_channel_quality (
    stat_date       DATE NOT NULL,      -- 统计日期（可设为每月1日或每日）
    channel_id      VARCHAR NOT NULL,
    channel_name    VARCHAR,
    apply_cnt       INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2),
    ps_30d          DECIMAL(10,6),      -- 近30天PSI（与整体分布对比）
    quality_score   DECIMAL(5,2),       -- 综合得分
    rank            INT
);
-- ads_channel_quality_monthly.sql
BEGIN TRANSACTION;
DELETE FROM ads_channel_quality;

WITH monthly_stats AS (
    SELECT
        DATE_TRUNC('month', dt) AS stat_date,
        channel_id,
        channel_name,
        SUM(apply_cnt) AS apply_cnt,
        ROUND(100.0 * SUM(pass_cnt) / NULLIF(SUM(apply_cnt), 0), 2) AS pass_rate,
        ROUND(100.0 * SUM(reject_cnt) / NULLIF(SUM(apply_cnt), 0), 2) AS reject_rate
    FROM dws_channel_daily
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-31'  -- 可参数化
    GROUP BY stat_date, channel_id, channel_name
),
max_apply AS (SELECT MAX(apply_cnt) AS max_apply FROM monthly_stats)
SELECT
    stat_date,
    channel_id,
    channel_name,
    apply_cnt,
    pass_rate,
    reject_rate,
    NULL AS ps_30d,  -- 可后续计算
    ROUND(pass_rate * 0.6 + (apply_cnt * 1.0 / max_apply) * 0.4, 2) AS quality_score,
    ROW_NUMBER() OVER (ORDER BY quality_score DESC) AS rank
FROM monthly_stats, max_apply
ORDER BY stat_date, rank;

COMMIT;