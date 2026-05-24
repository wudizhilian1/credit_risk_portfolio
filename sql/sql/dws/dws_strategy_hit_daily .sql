CREATE TABLE IF NOT EXISTS dws_strategy_hit_daily (
    dt                  DATE NOT NULL,
    strategy_version    VARCHAR,
    strategy_name       VARCHAR,
    apply_cnt           INT,
    pass_cnt            INT,
    hit_cnt             INT,        -- 命中量（拒绝+人工）
    pass_rate           DECIMAL(5,2),
    hit_rate            DECIMAL(5,2)
);

-- 插入数据（全量刷新）
INSERT INTO dws_strategy_hit_daily
SELECT
    a.dt,
    d.strategy_version,
    s.strategy_name,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN d.decision IN ('REJECT', 'REVIEW') THEN a.apply_id END) AS hit_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) / NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision IN ('REJECT', 'REVIEW') THEN a.apply_id END) / NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS hit_rate
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
LEFT JOIN dim_strategy s ON d.strategy_version = s.strategy_version
WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30'
GROUP BY a.dt, d.strategy_version, s.strategy_name;