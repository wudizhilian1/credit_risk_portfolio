-- apply_rate_change_contrib.sql
-- 功能：计算当前日与基准日通过率变化的维度贡献（以渠道为例）
-- 使用方式：通过 run_sql.py 传入 dt 和 dt_baseline 参数
WITH
curr AS (
    SELECT
        a.channel_id,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END ) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '{{dt}}'
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
    WHERE a.dt = '{{dt_baseline}}'
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