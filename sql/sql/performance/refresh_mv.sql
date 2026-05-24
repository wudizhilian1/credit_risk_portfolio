DROP TABLE IF EXISTS mv_user_hist_30d;
CREATE TABLE mv_user_hist_30d AS
SELECT
    user_id,
    COUNT(*) as apply_cnt_30d,
    AVG(amount) AS avg_amount_30d,
    AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_rate_30d
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
GROUP BY user_id;