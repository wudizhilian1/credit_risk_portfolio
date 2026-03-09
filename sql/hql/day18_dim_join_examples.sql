-- 示例1：查询申请事实，关联渠道名称和客户风险等级
SELECT
    a.apply_id,
    a.amount,
    c.channel_name,
    cust.risk_level,
    cust.gender,
    cust.city
FROM dwd_apply_latest a
LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
LEFT JOIN dim_customer cust ON a.user_id = cust.user_id
WHERE a.dt = '2024-01-01'
LIMIT 10;

-- 示例2：统计各渠道分组（自有/外部）的申请量、通过率
WITH apply_with_channel AS (
    SELECT
        a.apply_id,
        a.amount,
        d.decision,
        ch.channel_group
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    WHERE a.dt = '2024-01-01'
)
SELECT
    channel_group,
    COUNT(*) AS apply_cnt,
    SUM(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_cnt,
    ROUND(100.0 * SUM(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_rate
FROM apply_with_channel
GROUP BY channel_group;

-- 示例3：拒绝原因分类统计（关联维表获取类别）
SELECT
    rr.reason_category,
    COUNT(*) AS reject_cnt
FROM dwd_decision_latest d
LEFT JOIN dim_reject_reason rr ON d.reject_reason = rr.reason_code
WHERE d.decision = 'REJECT' AND d.dt = '2024-01-01'
GROUP BY rr.reason_category
ORDER BY reject_cnt DESC;