-- refresh_ads.sql
-- 功能：刷新 ADS 层表（每日总览、渠道质量榜）
-- 执行方式：在 DuckDB CLI 中执行 .read sql/ads/refresh_ads.sql
-- 或通过 python scripts/run_sql.py --sql sql/ads/refresh_ads.sql

BEGIN TRANSACTION;

-- ============================================================
-- 1. 刷新每日总览表 ads_overview_daily
-- ============================================================
DELETE FROM ads_overview_daily;

INSERT INTO ads_overview_daily
WITH daily_stats AS (
    SELECT
        dt,
        SUM(apply_cnt) AS apply_cnt,
        SUM(pass_cnt) AS pass_cnt,
        SUM(reject_cnt) AS reject_cnt,
        SUM(review_cnt) AS review_cnt
    FROM dws_channel_daily
    GROUP BY dt
)
SELECT
    d.dt,
    d.apply_cnt,
    d.pass_cnt,
    d.reject_cnt,
    d.review_cnt,
    ROUND(100.0 * d.pass_cnt / NULLIF(d.apply_cnt, 0), 2) AS pass_rate,
    ROUND(100.0 * d.reject_cnt / NULLIF(d.apply_cnt, 0), 2) AS reject_rate,
    ROUND(100.0 * d.review_cnt / NULLIF(d.apply_cnt, 0), 2) AS review_rate,
    (SELECT AVG(amount) FROM dwd_apply_latest WHERE dt = d.dt) AS avg_amount,
    (SELECT COUNT(DISTINCT user_id) FROM dwd_apply_latest WHERE dt = d.dt) AS unique_user_cnt
FROM daily_stats d
ORDER BY d.dt;

-- ============================================================
-- 2. 刷新渠道质量榜（按月统计）
-- ============================================================
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
    WHERE dt BETWEEN (SELECT MIN(dt) FROM dws_channel_daily) AND (SELECT MAX(dt) FROM dws_channel_daily)
    GROUP BY stat_date, channel_id, channel_name
),
max_apply AS (
    SELECT stat_date, MAX(apply_cnt) AS max_apply
    FROM monthly_stats
    GROUP BY stat_date
)
INSERT INTO ads_channel_quality
SELECT
    m.stat_date,
    m.channel_id,
    m.channel_name,
    m.apply_cnt,
    m.pass_rate,
    m.reject_rate,
    NULL AS ps_30d,  -- 可后续计算
    ROUND(
        m.pass_rate * 0.6 + (m.apply_cnt * 1.0 / ma.max_apply) * 0.4,
        2
    ) AS quality_score,
    ROW_NUMBER() OVER (PARTITION BY m.stat_date ORDER BY quality_score DESC) AS rank
FROM monthly_stats m
JOIN max_apply ma ON m.stat_date = ma.stat_date
ORDER BY m.stat_date, rank;

COMMIT;

-- 可选：输出统计信息
SELECT 'ads_overview_daily' AS table_name, COUNT(*) AS row_count FROM ads_overview_daily
UNION ALL
SELECT 'ads_channel_quality', COUNT(*) FROM ads_channel_quality;