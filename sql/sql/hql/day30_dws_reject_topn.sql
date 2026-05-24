WITH reject_stats AS (
    SELECT
        dt,
        COALESCE(reject_reason, 'UNKNOW') AS reason_code,
        COUNT(*) AS reject_cnt
        FROM dwd_decision_latest
        WHERE decision = 'REJECT'
        AND dt = '2024-01-15'
        GROUP BY dt, reject_reason
),
total_reject AS (
    SELECT SUM(reject_cnt) AS total
    FROM reject_stats
)
SELECT
    r.dt,
    r.reason_code,
    rr.reason_desc,
    rr.reason_category,
    r,reject_cnt,
    ROUND(100.0 * r.reject_cnt / t.total, 2) AS pct,
    ROW_NUMBER() OVER (ORDER BY r.reject_cnt DESC) AS rn
FROM reject_stats r
LEFT JOIN dim_reject_reason rr ON r.reason_code = rr.reason_code
CROSS JOIN total_reject t
ORDER BY r.reject_cnt DESC
LIMIT 10;

-- dws_channel_reject_topn.sql
-- 功能：按渠道统计拒绝原因 TopN（每个渠道取前5）
WITH channel_reject AS (
    SELECT
        a.channel_id,
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS reject_cnt,
    FROM dwd_decision_latest d
    JOIN dwd_apply_latest a ON d.apply_id = a.apply_id
    WHERE d.decision = 'REJECT'
        AND d.dt = '2024-01-15'
        GROUP BY a.channel_id, d.reject_reason
),
ranked AS (
    SELECT
        cr.channel_id,
        c.channel_name,
        cr.reason_code,
        rr.reason_desc,
        cr.reject_cnt,
        ROW_NUMBER() OVER (PARTITION BY cr.channel_id ORDER BY cr.reject_cnt DESC) AS
        rn
    FROM channel_reject cr
    LEFT JOIN dim_channel c ON cr.channel_id = c.channel_id
    LEFT JOIN dim_reject_reason rr ON cr.reason_code = rr.reason_code
)
SELECT
    channel_id,
    channel_name,
    reason_code,
    reason_desc,
    reject_cnt,
    rn
FROM ranked
WHERE rn <= 5
ORDER BY channel_id, rn;

-- dws_reject_stability.sql
-- 功能：对比今日与7天前的拒绝原因占比，计算差值
WITH today AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '2024-01-15'
    GROUP BY reject_reason
),
prev AS (
    SELECT
        COALESCE(reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '2024-01-08'
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