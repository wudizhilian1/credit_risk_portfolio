--- 语句 1 ---
```sql
-- ads_vs_dws_reconcile.sql
-- 功能：对比 ads_overview_daily 与 dws_channel_daily 的每日申请量、通过量等
CREATE TABLE IF NOT EXISTS reconcile_ads_log (
    check_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dt              DATE,
    metric          VARCHAR,
    ads_value       INT,
    dws_value       INT,
    diff            INT,
    alert_level     VARCHAR  -- 'OK', 'WARN', 'ERROR'
)
```

行数: 0

(空结果集)

--- 语句 2 ---
```sql
WITH dws_summary AS (
    SELECT
        dt,
        SUM(apply_cnt) AS apply_cnt_dws,
        SUM(pass_cnt) AS pass_cnt_dws,
        SUM(reject_cnt) AS reject_cnt_dws,
        SUM(review_cnt) AS review_cnt_dws
    FROM dws_channel_daily
    GROUP BY dt
)
SELECT
    a.dt,
    a.apply_cnt AS apply_cnt_ads,
    d.apply_cnt_dws,
    a.apply_cnt - d.apply_cnt_dws AS apply_diff,
    a.pass_cnt AS pass_cnt_ads,
    d.pass_cnt_dws,
    a.pass_cnt - d.pass_cnt_dws AS pass_diff,
    a.reject_cnt AS reject_cnt_ads,
    d.reject_cnt_dws,
    a.reject_cnt - d.reject_cnt_dws AS reject_diff
FROM ads_overview_daily a
LEFT JOIN dws_summary d ON a.dt = d.dt
WHERE a.apply_cnt != d.apply_cnt_dws
   OR a.pass_cnt != d.pass_cnt_dws
   OR a.reject_cnt != d.reject_cnt_dws
ORDER BY a.dt
```

行数: 1

| dt                  |   apply_cnt_ads |   apply_cnt_dws |   apply_diff |   pass_cnt_ads |   pass_cnt_dws |   pass_diff |   reject_cnt_ads |   reject_cnt_dws |   reject_diff |
|:--------------------|----------------:|----------------:|-------------:|---------------:|---------------:|------------:|-----------------:|-----------------:|--------------:|
| 2024-01-20 00:00:00 |            5000 |            5000 |            0 |           1610 |           1511 |          99 |             1715 |             2457 |          -742 |
