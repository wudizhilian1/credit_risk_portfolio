--申请量（Apply Count）
SELECT dt, COUNT(*) AS apply_cnt
FROM dwd_apply_latest
WHERE dt = '2024-01-01'
GROUP BY dt;
--通过量（Pass Count）
SELECT
    a.dt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
WHERE a.dt = '2024-01-01'
GROUP BY a.dt;
--通过率（Pass Rate）
WITH stats AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt = '2024-01-01'
    GROUP BY a.dt
)
SELECT
    dt,
    apply_cnt,
    pass_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt,0),2) as pass_rate
FROM stats;
--拒绝量（Reject Count）与拒绝率（Reject Rate）
WITH stats AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt = '2024-01-01'
    GROUP BY a.dt
)
SELECT
    dt,
    apply_cnt,
    reject_cnt,
    ROUND(100.0 * reject_cnt  / NULLIF(apply_cnt,0),2) as reject_rate
FROM stats;
--渠道质量指标（示例：渠道通过率）
SELECT
    a.channel_id,
    c.channel_name,
    COUNT(DISTINCT a.apply_id) as apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) /
    NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS pass_rate
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
WHERE a.dt = '2024-01-01'
GROUP BY a.channel_id, c.channel_name
ORDER BY pass_rate DESC;
--策略命中率
SELECT
    d.strategy_version,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) as reject_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) /
    NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) as reject_rate
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
WHERE a.dt = '2024-01-01'
GROUP BY d.strategy_version;