CREATE TABLE IF NOT EXISTS dim_credit_score (
    user_id         VARCHAR PRIMARY KEY,
    credit_score    INT,
    score_date      DATE,
    source          VARCHAR
);
DELETE FROM dim_credit_score;
INSERT INTO dim_credit_score (user_id, credit_score, score_date, source)
SELECT
    'user_' || i,
    300 + (RANDOM() * 550)::INT,
    '2024-01-01'::DATE,
    'MOCK'
FROM generate_series(1, 2000) AS i;


CREATE TABLE IF NOT EXISTS feature_apply_broad (
    apply_id        VARCHAR PRIMARY KEY,
    dt              DATE,
    user_id         VARCHAR,
    channel_id      VARCHAR,
    amount          DECIMAL(18,2),
    apply_hour      INT,
    is_weekend      BOOLEAN,
    user_apply_cnt_30d    INT,
    user_avg_amount_30d   DECIMAL(18,2),
    user_pass_rate_30d    DECIMAL(5,2),
    credit_score          INT,
    decision              VARCHAR,
    strategy_version      VARCHAR,
    pred_score            DECIMAL(10,4),   -- 新增：预测分数（如策略评分）
    bad_flag              BOOLEAN
);
DELETE FROM feature_apply_broad WHERE dt BETWEEN '{{dt_start}}' AND '{{dt_end}}';

WITH user_hist AS (
    SELECT
        user_id,
        COUNT(*) AS user_apply_cnt_30d,
        AVG(amount) AS user_avg_amount_30d,
        AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS user_pass_rate_30d
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt BETWEEN DATE('{{dt_end}}') - INTERVAL 30 DAY
                AND DATE('{{dt_end}}') - INTERVAL 1 DAY
    GROUP BY user_id
)
INSERT INTO feature_apply_broad
SELECT
    a.apply_id,
    a.dt,
    a.user_id,
    a.channel_id,
    a.amount,
    EXTRACT(HOUR FROM a.apply_time) as apply_hour,
    EXTRACT(DOW FROM a.apply_time) IN (0,6) AS is_weekend,
    COALESCE(h.user_apply_cnt_30d, 0) AS user_apply_cnt_30d,
    COALESCE(h.user_avg_amount_30d, 0) AS user_avg_amount_30d,
    COALESCE(h.user_pass_rate_30d, 0) as user_pass_rate_30d,
    COALESCE(cs.credit_score, 600) AS credit_score,
    d.decision,
    d.strategy_version,
    CASE
        WHEN strategy_version = 'v2.0' THEN 0.8   -- 激进策略给高分
        WHEN strategy_version = 'v1.1' THEN 0.6
        ELSE 0.4
    END + (RANDOM() * 0.1) AS pred_score,
    RANDOM() < 0.05 AS bad_flag
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
LEFT JOIN user_hist h ON a.user_id = h.user_id
LEFT JOIN dim_credit_score cs ON a.user_id = cs.user_id   -- 模拟维表
WHERE a.dt BETWEEN '{{dt_start}}' AND '{{dt_end}}';