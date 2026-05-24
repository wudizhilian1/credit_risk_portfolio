-- 针对特定渠道的拒绝原因贡献拆解
WITH curr_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '{{dt}}' AND a.channel_id = 'APP' AND d.decision = 'REJECT'
    GROUP BY d.reject_reason
),
base_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '{{dt_baseline}}' AND a.channel_id = 'APP' AND d.decision = 'REJECT'
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