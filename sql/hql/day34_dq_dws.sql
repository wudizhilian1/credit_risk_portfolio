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
--监控 dws_channel_daily 表行数变化
INSERT INTO dq_dws_monitor
WITH today AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = '2024-01-15'
),
yesterday AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = CAST('2024-01-15'::DATE - INTERVAL '1 day' AS VARCHAR)
)
SELECT
    '2024-01-15' AS monitor_date,
    'dws_channel_daily' AS table_name,
    today.row_cnt AS row_cnt,
    yesterday.row_cnt AS row_count_prev_day,
    ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF (yesterday.row_cnt, 0), 2)
    AS row_count_pct_change,
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
--监控 dws_strategy_daily 表 strategy_name 空值率
INSERT INTO dq_dws_monitor
WITH stats AS (
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN strategy_name IS NULL OR strategy_name = '' THEN 1 ELSE 0 END) AS null_cnt
    FROM dws_strategy_daily
    WHERE dt='2024-01-15'
)
SELECT
    '2024-01-15' AS monitor_date,
    'dws_strategy_daily' AS table_name,
    NULL AS row_count,
    NULL AS row_count_prev_day,
    NULL AS row_count_pct_change,
    'strategy_name' AS null_field,
    null_cnt AS null_cnt,
    ROUND(100.0 * null_cnt / total, 4) AS null_rate,
    NULL AS negative_amount_cnt,
    NULL AS negative_amount_rate,
    CASE
        WHEN null_cnt > 0 THEN 'WARN'
        ELSE 'OK'
    END AS alert_level,
    current_date()
FROM stats;
SELECT
    '2024-01-15' AS monitor_date,
    'dws_channel_daily' AS table_name,
    COUNT(*) AS negative_cnt
FROM dws_channel_daily
WHERE dt = '2024-01-15' AND apply_cnt < 0;
--计算今日与7天前的拒绝原因分布 PSI
WITH today AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt,
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '2024-01-15'
    GROUP BY reject_reason
),
prev AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '2024-01-08'
    GROUP BY reject_reason
),
total_today AS (SELECT SUM(cnt) AS total FROM today),
total_prev AS (SELECT SUM(cnt) AS total FROM prev),
joined AS (
    SELECT
        COALESCE(t.reason, p.reason) AS reason,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(p.cnt, 0) AS cnt_prev,
        tt.total AS total_today,
        tp.total AS total_prev
    FROM today t
    FULL OUTER JOIN prev p ON t.reason = p.reason
    CROSS JOIN total_today tt
    CROSS JOIN total_prev tp
),
eps AS (SELECT 1e-6 AS e)
SELECT
    ROUND(SUM( ( (cnt_today + e) / (total_today + e) - (cnt_prev + e) / (total_prev + e) ) *
               LN( ((cnt_today + e) / (total_today + e)) / ((cnt_prev + e) / (total_prev + e)) ) ), 6) AS psi
    FROM joined, eps;