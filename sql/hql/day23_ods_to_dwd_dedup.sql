-- sql/etl/ods_to_dwd_apply.sql
-- 功能：从 ods_apply 去重取最新记录，刷新 dwd_apply_latest
-- 使用方式：在 DuckDB CLI 中执行 .read sql/etl/ods_to_dwd_apply.sql
-- 或通过 run_sql.py 执行（注意 DDL 和 DML 混合）

BEGIN TRANSACTION;

-- 1. 清空目标表（全量刷新）
DELETE FROM dwd_apply_latest;

-- 2. 插入去重后的最新数据
INSERT INTO dwd_apply_latest (apply_id, user_id, channel_id, amount, apply_time, update_time, dt)
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM ods_apply
)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM ranked
WHERE rn = 1;

-- 3. 可选：记录审计信息
CREATE TABLE IF NOT EXISTS etl_audit (
    etl_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    table_name VARCHAR,
    operation VARCHAR,
    rows_affected INT
);
INSERT INTO etl_audit (table_name, operation, rows_affected)
SELECT 'dwd_apply_latest', 'REFRESH', COUNT(*) FROM dwd_apply_latest;

COMMIT;

-- 4. 输出统计信息（可选）
SELECT 'dwd_apply_latest' AS table_name, COUNT(*) AS row_count FROM dwd_apply_latest;

-- sql/etl/ods_to_dwd_decision.sql
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

INSERT INTO etl_audit (table_name, operation, rows_affected)
SELECT 'dwd_decision_latest', 'REFRESH', COUNT(*) FROM dwd_decision_latest;

COMMIT;

SELECT 'dwd_decision_latest' AS table_name, COUNT(*) AS row_count FROM dwd_decision_latest;