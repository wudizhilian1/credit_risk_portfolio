-- ods_to_dwd_decision.sql
-- 功能：从 ods_decision 去重取最新决策记录，全量刷新 dwd_decision_latest

BEGIN TRANSACTION;

DELETE FROM dwd_decision_latest;

INSERT INTO dwd_decision_latest (apply_id, decision, reject_reason, strategy_version, decision_time, dt)
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC) AS rn
    FROM ods_decision
)
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM ranked
WHERE rn = 1;

INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_decision_latest', 'REFRESH', COUNT(*), '全量刷新'
FROM dwd_decision_latest;

COMMIT;

SELECT 'dwd_decision_latest' AS table_name, COUNT(*) AS row_count FROM dwd_decision_latest;