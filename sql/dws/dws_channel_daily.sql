-- dws_channel_daily.sql
-- 按渠道统计每日申请、通过、拒绝等指标
CREATE TABLE IF NOT EXISTS dws_channel_daily (
    dt              DATE NOT NULL,
    channel_id      VARCHAR,
    channel_name    VARCHAR,
    apply_cnt       INT,
    pass_cnt        INT,
    reject_cnt      INT,
    review_cnt      INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2)
);
BEGIN TRANSACTION;

-- 清空目标表（全量刷新）
DELETE FROM dws_channel_daily;

-- 插入新数据
INSERT INTO dws_channel_daily (dt, channel_id, channel_name, apply_cnt, pass_cnt, reject_cnt, review_cnt, pass_rate, reject_rate)
WITH daily_stats AS (
    SELECT
        a.dt,
        a.channel_id,
        c.channel_name,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REVIEW' THEN a.apply_id END) AS review_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
    GROUP BY a.dt, a.channel_id, c.channel_name
)
SELECT
    dt,
    channel_id,
    channel_name,
    apply_cnt,
    pass_cnt,
    reject_cnt,
    review_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
    ROUND(100.0 * reject_cnt / NULLIF(apply_cnt, 0), 2) AS reject_rate
FROM daily_stats
WHERE apply_cnt > 0  -- 仅保留有申请的日子
ORDER BY dt, channel_id;

COMMIT;

-- 可选：输出统计
SELECT dt, COUNT(*) AS channel_cnt, SUM(apply_cnt) AS total_apply FROM dws_channel_daily GROUP BY dt ORDER BY dt;