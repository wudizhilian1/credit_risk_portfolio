CREATE TABLE IF NOT EXISTS dws_segment_strategy_daily (
    dt                  DATE NOT NULL,
    customer_type       VARCHAR,      -- 新客/老客/未知
    amount_bucket       VARCHAR,      -- 小额/中额/大额
    strategy_version    VARCHAR,      -- 策略版本
    strategy_name       VARCHAR,      -- 策略名称
    apply_cnt           INT,
    pass_cnt            INT,
    reject_cnt          INT,
    review_cnt          INT,
    pass_rate           DECIMAL(5,2),
    reject_rate         DECIMAL(5,2)
);
-- dws_segment_strategy_daily.sql
-- 功能：按日期、客户类型、额度区间、策略版本统计核心指标
-- 使用方式：通过 run_sql.py 执行（全量刷新）

BEGIN TRANSACTION;

DELETE FROM dws_segment_strategy_daily;

WITH
-- 客户注册信息
customer_reg AS (
    SELECT user_id, registration_date
    FROM dim_customer
),
-- 基础事实：关联申请、决策、客户、策略
base AS (
    SELECT
        a.dt,
        a.apply_id,
        a.amount,
        c.registration_date,
        d.decision,
        d.strategy_version,
        s.strategy_name
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_strategy s ON d.strategy_version = s.strategy_version
    LEFT JOIN customer_reg c ON a.user_id = c.user_id
    WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30'   -- 可调整范围
),
-- 定义分层字段
segmented AS (
    SELECT
        dt,
        CASE
            WHEN registration_date IS NULL THEN '未知'
            WHEN (dt - registration_date) <= 30 THEN '新客'
            ELSE '老客'
        END AS customer_type,
        CASE
            WHEN amount < 5000 THEN '小额'
            WHEN amount BETWEEN 5000 AND 20000 THEN '中额'
            ELSE '大额'
        END AS amount_bucket,
        COALESCE(strategy_version, '未知策略') AS strategy_version,
        COALESCE(strategy_name, '未知') AS strategy_name,
        apply_id,
        decision
    FROM base
)
-- 聚合统计
SELECT
    dt,
    customer_type,
    amount_bucket,
    strategy_version,
    strategy_name,
    COUNT(DISTINCT apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) AS reject_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END) AS review_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS reject_rate
FROM segmented
GROUP BY dt, customer_type, amount_bucket, strategy_version, strategy_name
ORDER BY dt, customer_type, amount_bucket, strategy_version;

COMMIT;

-- 查看 2024-01-15 的数据
SELECT * FROM dws_segment_strategy_daily
WHERE dt = '2024-01-15'
ORDER BY apply_cnt DESC
LIMIT 10;