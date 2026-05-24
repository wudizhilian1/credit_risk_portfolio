-- dws_channel_reject_topn.sql
-- 功能：按渠道统计拒绝原因 TopN（每个渠道取前5）
-- 使用方式：传入 dt 参数

WITH channel_reject AS (
    SELECT
        a.channel_id,
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS reject_cnt
    FROM dwd_decision_latest d
    JOIN dwd_apply_latest a ON d.apply_id = a.apply_id
    WHERE d.decision = 'REJECT'
      AND d.dt = '{{dt}}'
    GROUP BY a.channel_id, d.reject_reason
),
ranked AS (
    SELECT
        cr.channel_id,
        c.channel_name,
        cr.reason_code,
        rr.reason_desc,
        cr.reject_cnt,
        ROW_NUMBER() OVER (PARTITION BY cr.channel_id ORDER BY cr.reject_cnt DESC) AS rn
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
WHERE rn <= 5  -- 每个渠道取前5
ORDER BY channel_id, rn;