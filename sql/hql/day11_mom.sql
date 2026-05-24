--基础日聚合（每日申请量）
WITH
 daily_apply AS (
     SELECT
         dt,
         COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt between '2024-01-01' and '2024-01-10'
    GROUP BY dt
 )
SELECT * FROM daily_apply order by dt;
--使用 LAG 计算环比
WITH daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
        FROM v_apply
        where dt between '2024-01-01' and '2024-01-10'
        GROUP BY dt
)
SELECT
    dt,
    apply_cnt,
    LAG(apply_cnt) OVER (ORDER BY dt) as prev_apply_cnt,
    CASE
        WHEN LAG(apply_cnt) OVER (ORDER BY dt) IS NULL OR LAG(apply_cnt) OVER (ORDER BY dt) = 0 THEN NULL
        ELSE ROUND(100.0 * (apply_cnt - LAG(apply_cnt) OVER (ORDER BY dt)) / LAG(apply_cnt) OVER (order by dt), 2)
        END AS mom_growth_pct
    FROM daily_apply
    ORDER BY dt
--计算同比（与7天前对比）
WITH daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
        FROM v_apply
        where dt between '2024-01-01' and '2024-01-10'
        GROUP BY dt
)
SELECT
    dt,
    apply_cnt,
    LAG(apply_cnt, 7) OVER(ORDER BY dt) as same_day_last_week,
    CASE
        WHEN LAG(apply_cnt, 7) OVER (ORDER BY dt) IS NULL OR LAG(apply_cnt, 7) OVER
        (ORDER BY dt) = 0 THEN NULL
        ELSE ROUND(100.0 * (apply_cnt - LAG(apply_cnt, 7) OVER (ORDER BY dt)) /
        LAG(apply_cnt, 7) OVER (ORDER BY dt), 2)
        END AS yoy_growth_pct
        from daily_apply
        order by dt;
--结合风控指标（通过率环比）
WITH daily_metrics AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT d.apply_id) AS decision_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS pass_cnt
    FROM v_apply a
    LEFT JOIN v_decision d ON a.apply_id = d.apply_id AND d.dt = a.dt
    WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY a.dt
)
SELECT
    dt,
    apply_cnt,
    pass_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
    LAG(ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2)) OVER (ORDER BY dt) AS prev_pass_rate,
    ROUND(
        100.0 * (
            ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2)
            - LAG(ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2)) OVER (ORDER BY dt)
        ) / NULLIF(LAG(ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2)) OVER (ORDER BY dt), 0),
        2
    ) AS pass_rate_mom_pct
FROM daily_metrics
ORDER BY dt;
--处理日期缺失（使用日历表）
WITH calendar AS (
    SELECT (range)::DATE AS dt
    FROM range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) AS apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) AS apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt = d.dt
)
SELECT
    dt,
    apply_cnt,
    LAG(apply_cnt) OVER (ORDER BY dt) AS prev_apply_cnt,
    CASE
        WHEN LAG(apply_cnt) OVER (ORDER BY dt) IS NULL OR LAG(apply_cnt) OVER (ORDER BY dt) = 0 THEN NULL
        ELSE ROUND(100.0 * (apply_cnt - LAG(apply_cnt) OVER (ORDER BY dt)) / LAG(apply_cnt) OVER (ORDER BY dt), 2)
    END AS mom_growth_pct
FROM daily_full
ORDER BY dt;