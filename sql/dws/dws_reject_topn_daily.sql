-- dws_reject_topn_daily 建表语句
CREATE TABLE IF NOT EXISTS dws_reject_topn_daily (
    dt              DATE NOT NULL,          -- 统计日期
    reason_code     VARCHAR NOT NULL,       -- 拒绝原因代码（NULL 处理为 'UNKNOWN'）
    reason_desc     VARCHAR,                -- 拒绝原因描述（关联 dim_reject_reason）
    reason_category VARCHAR,                -- 拒绝原因类别（关联 dim_reject_reason）
    reject_cnt      INT NOT NULL,           -- 该原因当日的拒绝次数
    pct             DECIMAL(5,2),           -- 该原因占当日总拒绝次数的百分比
    rn              INT                     -- 按拒绝次数降序排列的排名（TopN）
);
INSERT INTO dws_reject_topn_daily
WITH reject_stats AS (
    SELECT
        dt,
        COALESCE(reject_reason, 'UNKNOW') AS reason_code,
        COUNT(*) AS reject_cnt
        FROM dwd_decision_latest
        WHERE decision = 'REJECT'
        AND dt = '{{dt}}'
        GROUP BY dt, reject_reason
),
total_reject AS (
    SELECT SUM(reject_cnt) AS total
    FROM reject_stats
)
SELECT
    r.dt,
    r.reason_code,
    rr.reason_desc,
    rr.reason_category,
    r.reject_cnt,
    ROUND(100.0 * r.reject_cnt / t.total, 2) AS pct,
    ROW_NUMBER() OVER (ORDER BY r.reject_cnt DESC) AS rn
FROM reject_stats r
LEFT JOIN dim_reject_reason rr ON r.reason_code = rr.reason_code
CROSS JOIN total_reject t
ORDER BY r.reject_cnt DESC;