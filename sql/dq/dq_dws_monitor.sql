CREATE TABLE IF NOT EXISTS dq_dws_monitor (
    monitor_date        DATE NOT NULL,
    table_name          VARCHAR NOT NULL,
    row_count           INT,
    row_count_prev_day  INT,
    row_count_pct_change DECIMAL(10,2),
    null_field          VARCHAR,   -- 监控的具体字段名
    null_count          INT,
    null_rate           DECIMAL(10,4),
    negative_amount_cnt INT,        -- 针对包含金额的字段
    negative_amount_rate DECIMAL(10,4),
    alert_level         VARCHAR,    -- 'WARN', 'ERROR', 'INFO'
    check_time          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
DELETE FROM dq_dws_monitor;

-- 监控 dws_channel_daily 表行数变化
INSERT INTO dq_dws_monitor
WITH today AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = '{{dt}}'
),
yesterday AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = CAST('2024-01-15'::DATE - INTERVAL '1 day' AS VARCHAR)
)
SELECT
    '{{dt}}' AS monitor_date,
    'dws_channel_daily' AS table_name,
    today.row_cnt AS row_count,
    yesterday.row_cnt AS row_count_prev_day,
    ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF(yesterday.row_cnt, 0), 2) AS row_count_pct_change,
    NULL AS null_field,
    NULL AS null_count,
    NULL AS null_rate,
    NULL AS negative_amount_cnt,
    NULL AS negative_amount_rate,
    CASE
        WHEN yesterday.row_cnt IS NULL THEN 'INFO'   -- 首日无对比
        WHEN ABS(ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF(yesterday.row_cnt, 0), 2)) > 20 THEN 'ERROR'
        WHEN ABS(ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF(yesterday.row_cnt, 0), 2)) > 10 THEN 'WARN'
        ELSE 'OK'
    END AS alert_level,
    current_date()
FROM today, yesterday;

-- 监控 dws_strategy_daily 表 strategy_name 空值率
INSERT INTO dq_dws_monitor
WITH stats AS (
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN strategy_name IS NULL OR strategy_name = '' THEN 1 ELSE 0 END) AS null_cnt
    FROM dws_strategy_daily
    WHERE dt = '{{dt}}'
)
SELECT
    '{{dt}}' AS monitor_date,
    'dws_strategy_daily' AS table_name,
    NULL AS row_count,
    NULL AS row_count_prev_day,
    NULL AS row_count_pct_change,
    'strategy_name' AS null_field,
    null_cnt AS null_count,
    ROUND(100.0 * null_cnt / total, 4) AS null_rate,
    NULL AS negative_amount_cnt,
    NULL AS negative_amount_rate,
    CASE
        WHEN null_cnt > 0 THEN 'WARN'   -- 只要有空值就告警（可调整阈值）
        ELSE 'OK'
    END AS alert_level,
    current_date()
FROM stats;