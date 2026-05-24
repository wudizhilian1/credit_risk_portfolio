--ODS 层：视图 v_apply（原始数据，可能存在重复或未去重）
--#DWD 层：需要创建一个视图 dwd_apply_latest，表示按 apply_id 去重取最新的申请记录（基于 update_time 或 apply_time）。
CREATE OR REPLACE VIEW dwd_apply_latest AS
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM v_apply
) t
where rn = 1;
--行数与主键数对账
WITH ods_stats AS (
    SELECT
        COUNT(*) AS ods_rows,
        COUNT(DISTINCT apply_id) as ods_unique_apply
    FROM v_apply
    WHERE dt = '2024-01-01'
),
dwd_stats AS (
    SELECT
        COUNT(*) AS dwd_rows,
        COUNT(DISTINCT apply_id) AS dwd_unique_apply
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT
    ods_rows,
    ods_unique_apply,
    dwd_rows,
    dwd_unique_apply,
    ods_rows - dwd_rows AS row_diff,
    ods_unique_apply - dwd_unique_apply AS unique_diff
FROM ods_stats, dwd_stats;
CREATE OR REPLACE VIEW dwd_decision_latest AS
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC) AS rn
    FROM v_decision
) t
where rn = 1;
--关键字段分布对比
WITH ods_dec AS (
    SELECT
        decision,
        COUNT(*) AS cnt
    FROM v_decision
    WHERE dt = '2024-01-01'
    GROUP BY decision
),
dwd_dec AS (
    SELECT
        decision,
        COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE dt = '2024-01-01'
    GROUP BY decision
)
SELECT
    COALESCE(o.decision, d.decision) as decision,
    COALESCE(o.cnt, 0) as ods_cnt,
    COALESCE(d.cnt, 0) as dwd_dnt,
    COALESCE(o.cnt, 0) - COALESCE(d.cnt, 0) as diff
FROM ods_dec o
FULL OUTER JOIN dwd_dec d ON o.decision = d.decision
ORDER BY decision;
--差异样本抽取（TopN 不一致的 apply_id）
WITH compare AS (
    SELECT
        COALESCE(o.apply_id, d.apply_id) as apply_id,
        o.amount AS ods_amount,
        d.amount AS dwd_amount
    FROM v_apply o
    FULL OUTER JOIN dwd_apply_latest d ON o.apply_id = d.apply_id AND o.dt = d.dt
    WHERE o.dt = '2024-01-01' or d.dt = '2024-01-01'
)
SELECT *
FROM compare
WHERE ods_amount IS NULL OR dwd_amount IS NULL OR ods_amount != dwd_amount
limit 10;
--综合对账报表（一次扫描多指标）
WITH ods AS (
    SELECT
        COUNT(*) AS ods_rows,
        COUNT(DISTINCT apply_id) AS ods_unique,
        SUM(amount::INT) AS ods_amount_sum
    FROM v_apply
    WHERE dt = '2024-01-01'
),
dwd AS (
    SELECT
        COUNT(*) AS dwd_rows,
        COUNT(DISTINCT apply_id) as dwd_unique,
        SUM(amount::INT) AS dwd_amount_sum
    FROM dwd_apply_latest
    WHERE dt = '2024-01-01'
)
SELECT
    ods_rows,dwd_rows, ods_rows - dwd_rows AS row_diff,
    ods_unique, dwd_unique, ods_unique - dwd_unique as unique_diff,
    ods_amount_sum, dwd_amount_sum, ods_amount_sum - dwd_amount_sum AS amount_sum_diff
FROM ods,dwd;