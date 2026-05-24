-- dws_strategy_daily.sql
-- 按策略版本统计每日申请、通过、拒绝等指标
CREATE TABLE IF NOT EXISTS dws_strategy_daily (
    dt                  DATE NOT NULL,
    strategy_version    VARCHAR,
    strategy_name       VARCHAR,
    apply_cnt           INT,
    pass_cnt            INT,
    reject_cnt          INT,
    review_cnt          INT,
    pass_rate           DECIMAL(5,2),
    reject_rate         DECIMAL(5,2)
);

BEGIN TRANSACTION;

DELETE FROM dws_strategy_daily;

INSERT INTO dws_strategy_daily (dt, strategy_version, strategy_name, apply_cnt, pass_cnt, reject_cnt, review_cnt, pass_rate, reject_rate)
WITH strategy_stats AS (
    SELECT
        a.dt,
        d.strategy_version,
        s.strategy_name,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REVIEW' THEN a.apply_id END) AS review_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_strategy s ON d.strategy_version = s.strategy_version
    GROUP BY a.dt, d.strategy_version, s.strategy_name
)
SELECT
    dt,
    strategy_version,
    strategy_name,
    apply_cnt,
    pass_cnt,
    reject_cnt,
    review_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
    ROUND(100.0 * reject_cnt / NULLIF(apply_cnt, 0), 2) AS reject_rate
FROM strategy_stats
WHERE strategy_version IS NOT NULL  -- 过滤无策略记录的申请
ORDER BY dt, strategy_version;

COMMIT;

SELECT dt, COUNT(*) AS strategy_cnt FROM dws_strategy_daily GROUP BY dt ORDER BY dt;