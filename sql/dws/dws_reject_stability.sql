-- dws_reject_stability.sql
-- 功能：对比今日与7天前的拒绝原因占比，计算差值
WITH today AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt}}'
    GROUP BY reject_reason
),
prev AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt_minus7}}'
    GROUP BY reject_reason
),
total_today AS (SELECT SUM(cnt) AS total FROM today),
total_prev AS (SELECT SUM(cnt) AS toal FROM prev),
combined AS (
    SELECT
        COALESCE(t.reason_code, p.reason_code) as reason_code,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(p.cnt, 0) AS cnt_prev,
        tt.total AS total_today,
        tt.total AS total_prev
    FROM today t
    FULL OUTER JOIN prev p ON t.reason_code = p.reason_code
    CROSS JOIN total_today tt
    CROSS JOIN total_prev tp
)
SELECT
    rr.reason_code,
    rr.reason_desc,
    cnt_today,
    cnt_prev,
    ROUND(100.0 * cnt_today / total_today, 2) AS pct_today,
    ROUND(100.0 * cnt_prev / total_prev, 2) as pct_prev,
    ROUND(100.0 * cnt_today / total_today - 100.0 * cnt_prev / total_prev, 2) AS diff_pct
FROM combined
LEFT JOIN dim_reject_reason rr ON combined.reason_code = rr.reason_code
WHERE cnt_today > 0 OR cnt_prev > 0
ORDER BY ABS(diff_pct) DESC
LIMIT 20;