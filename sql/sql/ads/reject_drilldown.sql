CREATE TABLE IF NOT EXISTS ads_reject_drilldown (
    dt              DATE NOT NULL,
    reason_code     VARCHAR NOT NULL,
    reason_desc     VARCHAR,
    apply_id        VARCHAR NOT NULL,
    user_id         VARCHAR,
    channel_name    VARCHAR,
    amount          DECIMAL(18,2),
    strategy_version VARCHAR,
    decision_time   TIMESTAMP
);

-- reject_drilldown.sql
-- 功能：抽取每日每个拒绝原因下的申请样本（每个原因取前 5 条）
-- 执行方式：全量刷新，先删后插

BEGIN TRANSACTION;

DELETE FROM ads_reject_drilldown;

INSERT INTO ads_reject_drilldown
WITH ranked_samples AS (
    SELECT
        a.dt,
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason_code,
        d.apply_id,
        a.user_id,
        ch.channel_name,
        a.amount,
        d.strategy_version,
        d.decision_time,
        ROW_NUMBER() OVER (PARTITION BY a.dt, d.reject_reason ORDER BY d.decision_time DESC) AS rn
    FROM dwd_decision_latest d
    JOIN dwd_apply_latest a ON d.apply_id = a.apply_id AND d.dt = a.dt
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    WHERE d.decision = 'REJECT'
)
SELECT
    dt,
    reason_code,
    rr.reason_desc,
    apply_id,
    user_id,
    channel_name,
    amount,
    strategy_version,
    decision_time
FROM ranked_samples
LEFT JOIN dim_reject_reason rr ON ranked_samples.reason_code = rr.reason_code
WHERE rn <= 5  -- 每个原因每天最多 5 个样本
ORDER BY dt, reason_code, rn;

COMMIT;