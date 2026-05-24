-- sql/hql/day22_raw_to_ods.sql
-- 功能：将指定日期的数据从 raw 视图（v_apply / v_decision）加载到 ODS 表
--       并记录输入/输出行数到审计表 ods_load_audit
-- 使用方式（通过 run_sql.py）：
--   python scripts/run_sql.py --sql sql/hql/day22_raw_to_ods.sql --vars dt=2024-01-01
-- 要求：ods_apply, ods_decision 表已存在（见 Day16 DDL）

BEGIN TRANSACTION;

-- 1. 创建审计表（如果不存在）
CREATE TABLE IF NOT EXISTS ods_load_audit (
    load_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dt VARCHAR,
    table_name VARCHAR,
    input_rows INT,
    output_rows INT
);

-- 2. 删除目标分区数据（保证幂等）
DELETE FROM ods_apply WHERE dt = '{{dt}}';
DELETE FROM ods_decision WHERE dt = '{{dt}}';

-- 3. 插入新数据
INSERT INTO ods_apply (apply_id, user_id, channel_id, amount, apply_time, update_time, dt)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM v_apply
WHERE dt = '{{dt}}';

INSERT INTO ods_decision (apply_id, decision, reject_reason, strategy_version, decision_time, dt)
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM v_decision
WHERE dt = '{{dt}}';

-- 4. 记录审计日志
INSERT INTO ods_load_audit (dt, table_name, input_rows, output_rows)
SELECT
    '{{dt}}' AS dt,
    'apply' AS table_name,
    (SELECT COUNT(*) FROM v_apply WHERE dt = '{{dt}}') AS input_rows,
    (SELECT COUNT(*) FROM ods_apply WHERE dt = '{{dt}}') AS output_rows
UNION ALL
SELECT
    '{{dt}}' AS dt,
    'decision' AS table_name,
    (SELECT COUNT(*) FROM v_decision WHERE dt = '{{dt}}') AS input_rows,
    (SELECT COUNT(*) FROM ods_decision WHERE dt = '{{dt}}') AS output_rows;

COMMIT;

-- 5. 可选：查看本次加载的审计记录
SELECT dt, table_name, input_rows, output_rows
FROM ods_load_audit
WHERE dt = '{{dt}}'
ORDER BY table_name;