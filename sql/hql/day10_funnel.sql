--计算某一天（如 2024-01-01）的漏斗数据：
WITH
apply_tbl AS (
    SELECT apply_id
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_tbl AS (
    SELECT apply_id, decision
    FROM v_decision
    WHERE dt = '2024-01-01'
)
SELECT
    COUNT(DISTINCT a.apply_id) AS step1_apply_cnt,
    COUNT(DISTINCT d.apply_id) AS step2_decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS step3_pass_cnt,
    -- 假设放款即通过（实际需放款表）
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS step4_loan_cnt
FROM apply_tbl a
LEFT JOIN decision_tbl d ON a.apply_id = d.apply_id;
--在上一步基础上增加比率计算：
WITH
apply_tbl AS (
    SELECT apply_id
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_tbl AS (
    SELECT apply_id, decision
    FROM v_decision
    WHERE dt = '2024-01-01'
),
base AS (
    SELECT
        COUNT(DISTINCT a.apply_id) AS step1,
        COUNT(DISTINCT d.apply_id) AS step2,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS step3
    FROM apply_tbl a
    LEFT JOIN decision_tbl d ON a.apply_id = d.apply_id
)
SELECT
    step1,
    step2,
    step3,
    ROUND(100.0 * step2 / step1, 2) AS pct_apply_to_decision,
    ROUND(100.0 * step3 / step2, 2) AS pct_decision_to_pass,
    ROUND(100.0 * step3 / step1, 2) AS pct_apply_to_pass
FROM base;
--分渠道漏斗
SELECT
    a.channel_id,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT d.apply_id) AS decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS pass_cnt
FROM v_apply a
LEFT JOIN v_decision d ON a.apply_id = d.apply_id AND d.dt = a.dt  -- 注意关联日期一致
WHERE a.dt = '2024-01-01'
GROUP BY a.channel_id
ORDER BY apply_cnt DESC;
--带时间窗口的漏斗
WITH
apply_ts AS (
    SELECT apply_id, channel_id, dt, apply_time::TIMESTAMP AS apply_ts
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_ts AS (
    SELECT apply_id, decision, decision_time::TIMESTAMP AS decision_ts
    FROM v_decision
    WHERE dt = '2024-01-01'
)
SELECT
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision_ts <= a.apply_ts + INTERVAL '7 days' THEN d.apply_id END) AS decision_in_7d_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' AND d.decision_ts <= a.apply_ts + INTERVAL '7 days' THEN d.apply_id END) AS pass_in_7d_cnt
FROM apply_ts a
LEFT JOIN decision_ts d ON a.apply_id = d.apply_id;