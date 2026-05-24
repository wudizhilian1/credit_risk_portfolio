CREATE TABLE IF NOT EXISTS dws_segment_daily (
    dt              DATE NOT NULL,
    customer_type   VARCHAR,      -- '新客', '老客', '未知'
    amount_bucket   VARCHAR,      -- '小额', '中额', '大额'
    channel_group   VARCHAR,      -- '自有', '外部', '其他'
    apply_cnt       INT,
    pass_cnt        INT,
    reject_cnt      INT,
    review_cnt      INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2)
);
DELETE FROM dws_segment_daily;

-- 功能：按客群分层统计每日核心指标
-- 使用方式：通过 run_sql.py 执行（全量刷新）
INSERT INTO dws_segment_daily
WITH customer_reg AS (
    SELECT user_id, registration_date
    FROM dim_customer
),
base AS (
    SELECT
        a.dt,
        a.apply_id,
        a.amount,
        c.registration_date,
        ch.channel_group,
        d.decision
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    LEFT JOIN customer_reg c ON a.user_id = c.user_id
    WHERE a.dt BETWEEN '2024-01-01' and '2024-01-30'
),
segmented AS (
    SELECT
        dt,
        CASE WHEN registration_date IS NULL THEN '未知'
        WHEN (a.dt - registration_date) <= 30 THEN '新客'
        ELSE '老客'
        END AS customer_type,
        CASE WHEN amount < 5000 THEN '小额'
        WHEN amount BETWEEN 5000 and 20000 THEN '中额'
        ELSE '大额'
        END AS amount_bucket,
        COALESCE(channel_group, '其他') AS channel_group,
        apply_id,
        decision
    FROM base a
)
SELECT
    dt,
    customer_type,
    amount_bucket,
    channel_group,
    COUNT(DISTINCT apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) AS reject_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END) AS review_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) /
    NULLIF(COUNT(DISTINCT apply_id), 0), 2) as pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END)/
    NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS reject_rate
    FROM segmented
    GROUP BY dt,customer_type,amount_bucket, channel_group
    ORDER BY dt,customer_type,amount_bucket, channel_group;

CREATE TABLE IF NOT EXISTS dws_strategy_hit_daily (
    dt                  DATE NOT NULL,
    strategy_version    VARCHAR,
    strategy_name       VARCHAR,
    apply_cnt           INT,
    pass_cnt            INT,
    hit_cnt             INT,        -- 命中量（拒绝+人工）
    pass_rate           DECIMAL(5,2),
    hit_rate            DECIMAL(5,2)
);
DELETE FROM dws_strategy_hit_daily;

INSERT INTO dws_strategy_hit_daily
SELECT
    a.dt,
    d.strategy_version,
    s.strategy_name,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN d.decision IN ('REJECT', 'REVIEW') THEN a.apply_id END) AS hit_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) /
    NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision IN ('REJECT', 'REVIEW') THEN a.apply_id END)/
     NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS hit_rate
     FROM dwd_apply_latest a
     LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
     LEFT JOIN dim_strategy s ON d.strategy_version = s.strategy_version
     WHERE a.dt BETWEEN '2024-01-01' and '2024-01-30'
     GROUP BY a.dt, d.strategy_version, s.strategy_name;
SELECT * FROM dws_strategy_hit_daily WHERE dt = '2024-01-15' ORDER BY apply_cnt DESC;
SELECT * FROM dws_segment_daily
WHERE dt = '2024-01-15'
ORDER BY apply_cnt DESC
LIMIT 10;
