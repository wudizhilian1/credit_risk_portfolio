SELECT
    'load' AS type,
    ANY_VALUE(dt) AS date,
    COUNT(*) AS cnt
FROM ods_apply WHERE dt = '2024-01-01'

UNION ALL

SELECT
    'event',
    ANY_VALUE(CAST(apply_time AS DATE)) AS date,
    COUNT(*)
FROM ods_apply
WHERE CAST(apply_time AS DATE) = '2024-01-01';
-- 清空并重新加载
DELETE FROM dwd_apply_by_event;

INSERT INTO dwd_apply_by_event (apply_id, user_id, channel_id, amount, apply_time, update_time, event_date)
SELECT
    apply_id, user_id, channel_id, amount, apply_time, update_time,
    CAST(apply_time AS DATE) AS event_date
FROM ods_apply;