-- 计算今日与7天前的拒绝原因分布 PSI
WITH today AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt}}'
    GROUP BY reject_reason
),
prev AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt_minus7}}'
    GROUP BY reject_reason
),
total_today AS (SELECT SUM(cnt) AS total FROM today),
total_prev AS (SELECT SUM(cnt) AS total FROM prev),
joined AS (
    SELECT
        COALESCE(t.reason, p.reason) AS reason,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(p.cnt, 0) AS cnt_prev,
        tt.total AS total_today,
        tp.total AS total_prev
    FROM today t
    FULL OUTER JOIN prev p ON t.reason = p.reason
    CROSS JOIN total_today tt
    CROSS JOIN total_prev tp
),
eps AS (SELECT 1e-6 AS e)  -- 避免 log(0)
SELECT
    ROUND(SUM( ( (cnt_today + e) / (total_today + e) - (cnt_prev + e) / (total_prev + e) ) *
               LN( ((cnt_today + e) / (total_today + e)) / ((cnt_prev + e) / (total_prev + e)) ) ), 6) AS psi
FROM joined, eps;