-- 创建 dwd_apply_latest 表
CREATE TABLE IF NOT EXISTS dwd_apply_latest (
    apply_id          VARCHAR NOT NULL,
    user_id           VARCHAR NOT NULL,
    channel_id        VARCHAR,
    amount            DECIMAL(18,2),
    apply_time        TIMESTAMP,
    update_time       TIMESTAMP,
    dt                DATE NOT NULL
);

-- 从 ods_apply 去重插入最新记录
INSERT INTO dwd_apply_latest
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
    FROM ods_apply
)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM ranked
WHERE rn = 1;

-- 可选：创建索引（DuckDB 自动优化，可不执行）
CREATE TABLE IF NOT EXISTS dwd_decision_latest (
    apply_id          VARCHAR NOT NULL,
    decision          VARCHAR,
    reject_reason     VARCHAR,
    strategy_version  VARCHAR,
    decision_time     TIMESTAMP,
    dt                DATE NOT NULL
);

INSERT INTO dwd_decision_latest
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC) AS rn
    FROM ods_decision
)
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM ranked
WHERE rn = 1;
CREATE TABLE IF NOT EXISTS dwd_rule_hit (
    apply_id          VARCHAR NOT NULL,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_result        BOOLEAN,   -- true 表示命中
    hit_time          TIMESTAMP,
    dt                DATE NOT NULL
);