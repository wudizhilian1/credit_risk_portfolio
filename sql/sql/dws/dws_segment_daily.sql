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
-- dws_segment_daily.sql
-- 功能：按客群分层统计每日核心指标
-- 使用方式：通过 run_sql.py 执行（全量刷新）

BEGIN TRANSACTION;

DELETE FROM dws_segment_daily;
INSERT INTO dws_segment_daily
WITH
-- 获取客户注册日期（若 dim_customer 存在）
customer_reg AS (
    SELECT user_id, registration_date
    FROM dim_customer
),
-- 基础事实：关联申请、决策、客户、渠道
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
    WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30'  -- 可调整范围
),
-- 定义分层字段
segmented AS (
    SELECT
        dt,
        CASE
            WHEN registration_date IS NULL THEN '未知'
            WHEN DATE_PART('day', a.dt - registration_date) <= 30 THEN '新客'
            ELSE '老客'
        END AS customer_type,
        CASE
            WHEN amount < 5000 THEN '小额'
            WHEN amount BETWEEN 5000 AND 20000 THEN '中额'
            ELSE '大额'
        END AS amount_bucket,
        COALESCE(channel_group, '其他') AS channel_group,
        apply_id,
        decision
    FROM base a
)
-- 聚合统计
SELECT
    dt,
    customer_type,
    amount_bucket,
    channel_group,
    COUNT(DISTINCT apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) AS reject_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END) AS review_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS reject_rate
FROM segmented
GROUP BY dt, customer_type, amount_bucket, channel_group
ORDER BY dt, customer_type, amount_bucket, channel_group;

COMMIT;