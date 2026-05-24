--- 语句 1 ---
```sql
CREATE TABLE IF NOT EXISTS ads_model_eval (
    eval_date   DATE,
    model_name  VARCHAR,
    auc         DECIMAL(6,4),
    ks          DECIMAL(6,4),
    psi         DECIMAL(6,4),
    check_time  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

行数: 0

(空结果集)

--- 语句 2 ---
```sql
delete from ads_model_eval
```

行数: 1

|   Count |
|--------:|
|       1 |

--- 语句 3 ---
```sql
-- 1. 计算 KS（基于 pred_score 和 bad_flag）
WITH score_bad AS (
    SELECT pred_score, bad_flag
    FROM feature_apply_broad
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-30'   -- 可根据需要调整范围
      AND pred_score IS NOT NULL
      AND bad_flag IS NOT NULL
),
-- 第一步：先生成分桶（必须单独一层CTE）
score_bucket AS (
    SELECT
        bad_flag,
        -- 按分数降序，分10桶
        NTILE(10) OVER (ORDER BY pred_score DESC) AS bucket
    FROM score_bad
),
-- 第二步：按桶分组统计好坏
binned AS (
    SELECT
        bucket,
        SUM(CASE WHEN bad_flag = 1 THEN 1 ELSE 0 END) AS bad,
        SUM(CASE WHEN bad_flag = 0 THEN 1 ELSE 0 END) AS good
    FROM score_bucket
    GROUP BY bucket
),
cumulative AS (
    SELECT
        bucket,
        SUM(bad) OVER (ORDER BY bucket) AS cum_bad,
        SUM(good) OVER (ORDER BY bucket) AS cum_good,
        SUM(bad) OVER () AS total_bad,
        SUM(good) OVER () AS total_good
    FROM binned
),
ks_value AS (
    SELECT
        MAX(cum_bad * 1.0 / NULLIF(total_bad, 0) - cum_good * 1.0 / NULLIF(total_good, 0)) AS ks
    FROM cumulative
)
-- 2. 计算 PSI（对比当前评估日与基准日的 pred_score 分布）
,score_today AS (
    SELECT
        CASE
            WHEN pred_score < 0.2 THEN '0-0.2'
            WHEN pred_score < 0.4 THEN '0.2-0.4'
            WHEN pred_score < 0.6 THEN '0.4-0.6'
            WHEN pred_score < 0.8 THEN '0.6-0.8'
            ELSE '0.8-1.0'
        END AS score_bin,
        COUNT(*) AS cnt
    FROM feature_apply_broad
    WHERE dt = '2024-01-30' AND pred_score IS NOT NULL
    GROUP BY score_bin
),
score_base AS (
    SELECT
        CASE
            WHEN pred_score < 0.2 THEN '0-0.2'
            WHEN pred_score < 0.4 THEN '0.2-0.4'
            WHEN pred_score < 0.6 THEN '0.4-0.6'
            WHEN pred_score < 0.8 THEN '0.6-0.8'
            ELSE '0.8-1.0'
        END AS score_bin,
        COUNT(*) AS cnt
    FROM feature_apply_broad
    WHERE dt = '2024-01-01' AND pred_score IS NOT NULL
    GROUP BY score_bin
),
total_today AS (SELECT SUM(cnt) AS total FROM score_today),
total_base AS (SELECT SUM(cnt) AS total FROM score_base),
psi_values AS (
    SELECT
        COALESCE(t.score_bin, b.score_bin) AS score_bin,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(b.cnt, 0) AS cnt_base,
        tt.total AS total_today,
        tb.total AS total_base
    FROM score_today t
    FULL OUTER JOIN score_base b ON t.score_bin = b.score_bin
    CROSS JOIN total_today tt
    CROSS JOIN total_base tb
),
psi_calc AS (
    SELECT
        SUM(
            ((cnt_today + 1e-6) / (total_today + 1e-6) - (cnt_base + 1e-6) / (total_base + 1e-6)) *
            LN(((cnt_today + 1e-6) / (total_today + 1e-6)) / ((cnt_base + 1e-6) / (total_base + 1e-6)))
        ) AS psi
    FROM psi_values
)
-- 3. 将结果插入评估表（AUC 暂无法通过 SQL 直接计算，留空或由 Python 补充）
INSERT INTO ads_model_eval (eval_date, model_name, auc, ks, psi)
SELECT
    '2024-01-30'::DATE AS eval_date,
    'strategy_score' AS model_name,
    NULL AS auc,   -- AUC 需要 Python 计算（如 sklearn）
    k.ks,
    p.psi
FROM ks_value k, psi_calc p
```

行数: 1

|   Count |
|--------:|
|       1 |
