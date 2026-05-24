-- ODS 与 DWD 差异
SELECT 'ods_not_in_dwd' AS diff_type, o.apply_id
FROM ods_apply o
LEFT JOIN dwd_apply_latest d ON o.apply_id = d.apply_id AND o.dt = d.dt
WHERE o.dt = '2024-01-01' AND d.apply_id IS NULL
UNION ALL
SELECT 'dwd_not_in_ods', d.apply_id
FROM dwd_apply_latest d
LEFT JOIN ods_apply o ON d.apply_id = o.apply_id AND d.dt = o.dt
WHERE d.dt = '2024-01-01' AND o.apply_id IS NULL;

CREATE TABLE IF NOT EXISTS reconcile_summary (
    check_date DATE,
    layer1 VARCHAR,
    layer2 VARCHAR,
    rows_layer1 INT,
    rows_layer2 INT,
    diff_count INT,
    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO reconcile_summary (check_date, layer1, layer2, rows_layer1, rows_layer2, diff_count)
SELECT
    '2024-01-01',
    'raw',
    'ods',
    (SELECT COUNT(*) FROM v_apply WHERE dt = '2024-01-01'),
    (SELECT COUNT(*) FROM ods_apply WHERE dt = '2024-01-01'),
    (SELECT COUNT(*) FROM (
        SELECT r.apply_id FROM v_apply r WHERE r.dt = '2024-01-01'
        EXCEPT
        SELECT o.apply_id FROM ods_apply o WHERE o.dt = '2024-01-01'
    ) t);