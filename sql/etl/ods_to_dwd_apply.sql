-- ods_to_dwd_apply.sql
-- 功能：从 ods_apply 去重取最新申请记录，全量刷新 dwd_apply_latest
-- 说明：此脚本会清空目标表并重新插入所有数据，适用于小数据量场景。
-- 使用方式：在 DuckDB CLI 中执行 .read sql/etl/ods_to_dwd_apply.sql

BEGIN TRANSACTION;

-- 清空目标表（保证幂等）
DELETE FROM dwd_apply_latest;

-- 插入去重后的最新数据
INSERT INTO dwd_apply_latest (apply_id, user_id, channel_id, amount, apply_time, update_time, dt)
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM ods_apply
)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM ranked
WHERE rn = 1;

-- 记录审计信息
CREATE TABLE IF NOT EXISTS etl_audit (
    etl_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    table_name VARCHAR,
    operation VARCHAR,
    rows_affected INT,
    description VARCHAR
);
INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_apply_latest', 'REFRESH', COUNT(*), '全量刷新'
FROM dwd_apply_latest;

COMMIT;

-- 输出统计信息（可选）
SELECT 'dwd_apply_latest' AS table_name, COUNT(*) AS row_count FROM dwd_apply_latest;