--整体数据范围检查
SELECT MIN(dt) AS min_dt, MAX(dt) AS max_dt FROM v_apply;
--每日申请量分布
SELECT dt, COUNT(*) AS apply_cnt
FROM v_apply
WHERE dt BETWEEN '2024-01-01' AND '2024-01-30'
GROUP BY dt
ORDER BY dt;
--异常金额检查（负数）
SELECT dt, COUNT(*) AS negative_amount_cnt
FROM v_apply
WHERE dt = '2024-01-25' AND CAST(amount AS decimal) < 0
GROUP BY dt;
--每日通过率监控（突出异常日）
WITH decision_stats AS (
    SELECT d.dt,
           COUNT(*) AS total,
           SUM(CASE WHEN d.decision = 'PASS' THEN 1 ELSE 0 END) AS pass_cnt,
           SUM(CASE WHEN d.decision = 'REJECT' THEN 1 ELSE 0 END) AS reject_cnt
    FROM v_decision d
    WHERE d.dt BETWEEN '2024-01-01' AND '2024-01-30'
    GROUP BY d.dt
)
SELECT dt, total, pass_cnt, reject_cnt,
       ROUND(100.0 * pass_cnt / total, 2) AS pass_rate,
       ROUND(100.0 * reject_cnt / total, 2) AS reject_rate
FROM decision_stats
ORDER BY dt;
--渠道数据缺失验证（2024-01-18 API渠道）
SELECT dt, channel_id, COUNT(*) AS apply_cnt
FROM v_apply
WHERE dt = '2024-01-18'
GROUP BY dt, channel_id
ORDER BY channel_id;