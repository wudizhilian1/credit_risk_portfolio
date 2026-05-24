--UV（独立访客）
SELECT COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01';
--按渠道统计 UV
SELECT
    channel_id,
    COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01'
GROUP BY channel_id
ORDER BY uv DESC;
--查看某个高频用户的申请记录
SELECT apply_id, channel_id, amount, apply_time
FROM v_apply
WHERE dt = '2024-01-01' AND user_id = 'user_123';
--总申请数 vs UV
SELECT
    COUNT(*) AS total_applies,
    COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01';
SELECT channel_id, COUNT(DISTINCT user_id) AS uv
FROM (
    SELECT channel_id, user_id
    FROM v_apply
    WHERE dt = '2024-01-01'
) t
GROUP BY channel_id;
--统计“7天滚动 UV”
WITH dates AS (
    SELECT DISTINCT dt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
)
SELECT
    d.dt,
    (SELECT COUNT(DISTINCT user_id)
     FROM v_apply
     WHERE dt BETWEEN d.dt - 6 AND d.dt) AS rolling_uv_7d
FROM dates d
ORDER BY d.dt;