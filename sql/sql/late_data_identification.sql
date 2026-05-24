SELECT
    apply_id,
    dt AS load_date,
    CAST(apply_time AS DATE) AS event_date,
    apply_time,
    dt > CAST(apply_time AS DATE) AS is_late
FROM ods_apply
WHERE dt > CAST(apply_time AS DATE);