--生成连续日期日历表（确保日期连续）
WITH calendar AS (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
)
SELECT * FROM calendar;
--计算每日申请量，并填充缺失日期
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) as apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt=d.dt
)
SELECT * FROM daily_full ORDER BY dt;
--#计算 7 日移动平均申请量（ROWS 方式）
--#ROWS BETWEEN 6 PRECEDING AND CURRENT ROW 表示取当前行及前 6 行（共 7 行）参与计算，严格按行数，与日期间隔无关。
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) as apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt=d.dt
)
SELECT
    dt,
    apply_cnt,
    AVG(apply_cnt) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7d_rows
FROM daily_full
ORDER BY dt;
--计算 7 日移动平均申请量（RANGE 方式，需日期连续）
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) as apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt=d.dt
)
SELECT
    dt,
    apply_cnt,
    AVG(apply_cnt) OVER (ORDER BY dt RANGE BETWEEN INTERVAL 6 DAYS PRECEDING AND CURRENT
    ROW ) AS avg_7d_range
FROM daily_full
ORDER BY dt;
--计算通过率的 7 日移动平均
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_metrics AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) as apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) as pass_cnt
    FROM v_apply a
    LEFT JOIN v_decision d on a.apply_id = d.apply_id and a.dt=d.dt
    WHERE a.dt BETWEEN '2024-01-01' and '2024-01-10'
    GROUP BY a.dt
),
daily_full AS (
        SELECT
            c.dt,
            COALESCE(m.apply_cnt, 0) as apply_cnt,
            COALESCE(m.pass_cnt, 0) as pass_cnt
        FROM calendar c
        LEFT JOIN daily_metrics m ON c.dt=m.dt
),
daily_rate AS (
    SELECT
        dt,
        apply_cnt,
        pass_cnt,
        CASE WHEN apply_cnt = 0 THEN NULL ELSE ROUND(100.0 * pass_cnt / apply_cnt,2)
        END AS pass_rate
    FROM daily_full
)
SELECT
    dt,
    apply_cnt,
    pass_cnt,
    pass_rate,
    AVG(pass_rate) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS pass_rate_ma_7d
    FROM daily_rate
    ORDER BY dt;