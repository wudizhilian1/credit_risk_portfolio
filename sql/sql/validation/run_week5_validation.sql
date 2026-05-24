-- run_week5_validation.sql
-- 一键验证 Week5 所有 DWS 表是否存在及基础数据量

SELECT 'dws_channel_daily' AS table_name, COUNT(*) AS row_count FROM dws_channel_daily;
SELECT 'dws_strategy_daily' AS table_name, COUNT(*) AS row_count FROM dws_strategy_daily;
SELECT 'dws_reject_topn_daily' AS table_name, COUNT(*) AS row_count FROM dws_reject_topn_daily;
SELECT 'dws_segment_daily' AS table_name, COUNT(*) AS row_count FROM dws_segment_daily;
SELECT 'dws_strategy_hit_daily' AS table_name, COUNT(*) AS row_count FROM dws_strategy_hit_daily;
SELECT 'dws_segment_strategy_daily' AS table_name, COUNT(*) AS row_count FROM dws_segment_strategy_daily;

SELECT dt, SUM(apply_cnt) AS total_apply FROM dws_channel_daily WHERE dt = '2024-01-15' GROUP BY dt;
SELECT dt, SUM(apply_cnt) AS total_apply FROM dws_strategy_daily WHERE dt = '2024-01-15' GROUP BY dt;
SELECT dt, COUNT(*) AS reason_cnt FROM dws_reject_topn_daily WHERE dt = '2024-01-15' GROUP BY dt;

SELECT * FROM dq_psi_monitor ORDER BY monitor_date DESC LIMIT 5;

SELECT * FROM dq_dws_monitor WHERE alert_level IN ('WARN','ERROR') ORDER BY monitor_date DESC LIMIT 10;