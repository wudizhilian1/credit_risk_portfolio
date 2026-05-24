CREATE TABLE IF NOT EXISTS ads_overview_daily (
    dt              DATE NOT NULL,
    apply_cnt       INT,
    pass_cnt        INT,
    reject_cnt      INT,
    review_cnt      INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2),
    review_rate     DECIMAL(5,2),
    avg_amount      DECIMAL(12,2),
    unique_user_cnt INT
);

-- ads_overview_daily.sql
BEGIN TRANSACTION;
DELETE FROM ads_overview_daily;

INSERT INTO ads_overview_daily
SELECT
    dt,
    SUM(apply_cnt) AS apply_cnt,
    SUM(pass_cnt) AS pass_cnt,
    SUM(reject_cnt) AS reject_cnt,
    SUM(review_cnt) AS review_cnt,
    ROUND(100.0 * SUM(pass_cnt) / NULLIF(SUM(apply_cnt), 0), 2) AS pass_rate,
    ROUND(100.0 * SUM(reject_cnt) / NULLIF(SUM(apply_cnt), 0), 2) AS reject_rate,
    ROUND(100.0 * SUM(review_cnt) / NULLIF(SUM(apply_cnt), 0), 2) AS review_rate,
    (SELECT AVG(amount) FROM dwd_apply_latest WHERE dt = a.dt) AS avg_amount, -- 若 DWS 无平均金额，从 DWD 取
    (SELECT COUNT(DISTINCT user_id) FROM dwd_apply_latest WHERE dt = a.dt) AS unique_user_cnt
FROM dws_channel_daily a
GROUP BY dt
ORDER BY dt;

COMMIT;