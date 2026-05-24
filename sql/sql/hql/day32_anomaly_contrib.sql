WITH
curr AS (
    SELECT
        a.channel_id,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END ) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-20'
    GROUP BY a.channel_id
),
curr_total AS (
    SELECT SUM(apply_cnt) AS total_apply FROM curr
),
curr_rate AS (
    SELECT
        channel_id,
        apply_cnt,
        pass_cnt,
        ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) as pass_rate,
        ROUND(100.0 * apply_cnt / (SELECT total_apply FROM curr_total), 4) AS apply_weight
    FROM curr
),
base AS (
    SELECT
        a.channel_id,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-13'
    GROUP BY a.channel_id
),
base_total AS (
    SELECT SUM(apply_cnt) AS total_apply FROM base
),
base_rate AS (
    SELECT
        channel_id,
        apply_cnt,
        pass_cnt,
        ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
        ROUND(100.0 * apply_cnt / (SELECT total_apply FROM base_total), 4) AS apply_weight
    FROM base
)
SELECT
    COALESCE(c.channel_id, b.channel_id) AS channel_id,
    COALESCE(c.apply_cnt, 0) AS curr_apply,
    COALESCE(b.apply_cnt, 0) AS base_apply,
    COALESCE(c.pass_rate, 0) AS curr_rate,
    COALESCE(b.pass_rate, 0) AS base_rate,
    COALESCE(c.pass_rate, 0) - COALESCE(b.pass_rate, 0) AS rate_diff,
    COALESCE(c.apply_weight, 0) AS curr_weight,
    COALESCE(b.apply_weight, 0) AS base_weight,
     ROUND((COALESCE(c.pass_rate, 0) * COALESCE(c.apply_weight, 0) -
         COALESCE(b.pass_rate, 0) * COALESCE(b.apply_weight, 0)) / 100.0, 4) AS contrib
FROM curr_rate c
FULL OUTER JOIN base_rate b ON c.channel_id = b.channel_id
ORDER BY ABS(contrib) DESC
LIMIT 10;

WITH curr_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-20' AND a.channel_id = 'APP' AND d.decision = 'REJECT'
    GROUP BY d.reject_reason
),
base_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-13' AND a.channel_id = 'APP' AND d.decision = 'REJECT'
    GROUP BY d.reject_reason
),
total_curr AS (SELECT SUM(cnt) AS total FROM curr_reason),
total_base AS (SELECT SUM(cnt) AS total FROM base_reason)
SELECT
    COALESCE(c.reason, b.reason) AS reason,
    COALESCE(c.cnt, 0) AS curr_cnt,
    COALESCE(b.cnt, 0) AS base_cnt,
    ROUND(100.0 * COALESCE(c.cnt, 0) / (SELECT total FROM total_curr), 2) AS curr_pct,
    ROUND(100.0 * COALESCE(b.cnt, 0) / (SELECT total FROM total_base), 2) as base_pct,
    ROUND(100.0 * COALESCE(c.cnt, 0) / tc.total - 100.0 * COALESCE(b.cnt, 0) / tb.total, 2) AS diff_pct
FROM curr_reason c
FULL OUTER JOIN base_reason b ON c.reason = b.reason
CROSS JOIN total_curr tc
CROSS JOIN total_base tb
ORDER BY ABS(diff_pct) DESC
LIMIT 10;

SELECT a.apply_id, a.user_id, a.amount, d.decision, d.reject_reason, d.strategy_version
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
WHERE a.dt = '2024-01-20' AND a.channel_id = 'APP' AND d.decision = 'REJECT' LIMIT 20;