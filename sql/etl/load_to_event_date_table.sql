-- load_to_event_date_table.sql
-- 功能：将 ods_apply 中的数据按事件日（apply_time 的日期）加载到 dwd_apply_by_event 表
-- 说明：此表用于按事件日统计，避免迟到数据影响。

BEGIN TRANSACTION;

-- 创建目标表（如果不存在）
CREATE TABLE IF NOT EXISTS dwd_apply_by_event (
    apply_id          VARCHAR NOT NULL,
    user_id           VARCHAR NOT NULL,
    channel_id        VARCHAR,
    amount            DECIMAL(18,2),
    apply_time        TIMESTAMP,
    update_time       TIMESTAMP,
    event_date        DATE NOT NULL
);

-- 清空目标表（全量刷新）
DELETE FROM dwd_apply_by_event;

-- 插入数据
INSERT INTO dwd_apply_by_event (apply_id, user_id, channel_id, amount, apply_time, update_time, event_date)
SELECT
    apply_id,
    user_id,
    channel_id,
    amount,
    apply_time,
    update_time,
    CAST(apply_time AS DATE) AS event_date
FROM ods_apply;

-- 记录审计
INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_apply_by_event', 'REFRESH', COUNT(*), '按事件日加载'
FROM dwd_apply_by_event;

COMMIT;

-- 输出按事件日统计（可选）
SELECT event_date, COUNT(*) FROM dwd_apply_by_event GROUP BY event_date ORDER BY event_date;