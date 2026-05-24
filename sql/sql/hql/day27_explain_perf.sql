-- 原始版本：全表扫描 + 窗口排序
WITH ranked AS (
    SELECT *,
        ROW_NUMBER () OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM ods_apply
)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM ranked
WHERE rn = 1 limit 10;
-- 原始版本：直接 COUNT(DISTINCT user_id) 可能未利用索引/分区
SELECT channel_id, COUNT(DISTINCT user_id) AS uv
FROM ods_apply
WHERE dt BETWEEN '2024-01-01' AND '2024-01-30'
GROUP BY channel_id;
-- 原始版本：两表关联 + 条件聚合
SELECT
    a.dt,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT d.apply_id) AS decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
FROM ods_apply a
LEFT JOIN ods_decision d ON a.apply_id = d.apply_id
WHERE a.dt = '2024-01-01'
GROUP BY a.dt;
-- 优化：先取最大时间，再关联回原表
WITH max_time AS (
    SELECT apply_id, MAX(update_time) AS max_update_time
    FROM ods_apply
    GROUP BY apply_id
)
SELECT a.apply_id, a.user_id, a.channel_id, a.amount, a.apply_time, a.update_time,a.dt
FROM ods_apply a
JOIN max_time m on a.apply_id = m.apply_id AND a.update_time = m.max_update_time limit 10;
-- 优化：先去重再聚合
WITH distinct_users AS (
    SELECT DISTINCT channel_id,user_id
    FROM ods_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-30'
)
SELECT channel_id, COUNT(*) AS uv
FROM distinct_users
GROUP BY channel_id;
-- 优化：先对决策表去重，再关联
WITH dedup_decision AS (
    SELECT apply_id, decision, decision_time
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC)
            AS rn
        FROM ods_decision
        WHERE dt = '2024-01-01'
    ) t
    WHERE rn =1
)
SELECT
    a.dt,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT d.apply_id) AS decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
FROM ods_apply a
LEFT JOIN dedup_decision d on a.apply_id = d.apply_id
where a.dt = '2024-01-01'
GROUP BY a.dt;