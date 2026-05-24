CREATE TABLE IF NOT EXISTS dws_strategy_eval_daily AS
SELECT
    dt,
    strategy_version,
    apply_cnt,
    pass_cnt,
    reject_cnt,
    pass_rate,
    reject_rate,
    -- 假设有 bad_flag，可添加坏账率
    -- ROUND(100.0 * bad_cnt / NULLIF(apply_cnt, 0), 2) AS bad_rate
FROM dws_strategy_daily;