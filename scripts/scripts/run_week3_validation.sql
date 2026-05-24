-- week3_validation.sql
-- 纯 SQL 版本，用于通过 run_sql.py 执行

SELECT '=== 1. 检查 ODS 表 ===' AS msg;

SELECT 'ods_apply' AS table_name, COUNT(*) AS row_count FROM ods_apply;
SELECT 'ods_decision' AS table_name, COUNT(*) AS row_count FROM ods_decision;

SELECT '=== 2. 检查 DWD 表 ===' AS msg;

SELECT 'dwd_apply_latest' AS table_name, COUNT(*) AS row_count FROM dwd_apply_latest;
SELECT 'dwd_decision_latest' AS table_name, COUNT(*) AS row_count FROM dwd_decision_latest;

SELECT '=== 3. 检查维表 ===' AS msg;

SELECT 'dim_channel' AS table_name, COUNT(*) AS row_count FROM dim_channel;
SELECT 'dim_customer' AS table_name, COUNT(*) AS row_count FROM dim_customer;
SELECT 'dim_strategy' AS table_name, COUNT(*) AS row_count FROM dim_strategy;
SELECT 'dim_reject_reason' AS table_name, COUNT(*) AS row_count FROM dim_reject_reason;

SELECT '=== 4. 验证数据日期范围（ods_apply）===' AS msg;

SELECT MIN(dt) AS min_dt, MAX(dt) AS max_dt FROM ods_apply;

SELECT '=== 5. 验证异常日数据（2024-01-15 申请量应为两倍）===' AS msg;

SELECT dt, COUNT(*) AS apply_cnt FROM ods_apply WHERE dt = '2024-01-15' GROUP BY dt;

SELECT '=== 6. 验证维表增强字段（dim_channel）===' AS msg;

SELECT channel_id, channel_name, channel_group, priority FROM dim_channel ORDER BY priority;

SELECT '=== 7. 验证核心指标计算（2024-01-01）===' AS msg;

WITH stats AS (
    SELECT a.dt,
           COUNT(DISTINCT a.apply_id) AS apply_cnt,
           COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
           COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt = '2024-01-01'
    GROUP BY a.dt
)
SELECT dt, apply_cnt, pass_cnt, reject_cnt,
       ROUND(100.0 * pass_cnt / apply_cnt, 2) AS pass_rate,
       ROUND(100.0 * reject_cnt / apply_cnt, 2) AS reject_rate
FROM stats;