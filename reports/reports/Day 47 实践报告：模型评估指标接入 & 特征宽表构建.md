# Day 47 实践报告：模型评估指标接入 & 特征宽表构建

## 1. 练习目标

- 将风控模型评估指标（AUC、KS、PSI 等）引入数据仓库，支持模型性能监控。
- 设计并构建 **特征宽表（Feature Store）**，为模型训练和预测提供特征数据。
- 编写 SQL 从 DWD 层提取特征（申请特征、历史行为特征、外部评分），并关联目标变量（逾期标签）。
- 将特征宽表物化，作为模型开发的统一数据出口。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库：`dev.duckdb`
- 项目路径：`C:\credit_risk_portfolio`
- 已有 DWD 表：`dwd_apply_latest`、`dwd_decision_latest`
- 维表：`dim_customer`、`dim_channel`
- 模拟外部评分维表：`dim_credit_score`（新建）

## 3. 核心任务执行

### 3.1 创建外部评分维表 `dim_credit_score`

由于项目没有真实征信数据，创建模拟维表并插入随机评分：

```sql
CREATE TABLE IF NOT EXISTS dim_credit_score (
    user_id         VARCHAR PRIMARY KEY,
    credit_score    INT,
    score_date      DATE,
    source          VARCHAR
);

INSERT INTO dim_credit_score (user_id, credit_score, score_date, source)
SELECT 
    'user_' || i,
    300 + (RANDOM() * 550)::INT,
    '2024-01-01'::DATE,
    'MOCK'
FROM generate_series(1, 2000) AS i;
```

### 3.2 设计特征宽表 `feature_apply_broad`

增加 `pred_score` 字段用于存储模型预测分（示例中先留空或随机填充）。

```sql
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
    pred_score            DECIMAL(10,4),   -- 预测分数（模拟）
    bad_flag              BOOLEAN
);
```

### 3.3 构建特征提取 SQL（全量刷新）

从 DWD 和维表中提取特征，并生成模拟预测分和逾期标签。

```sql
WITH user_hist AS (
    SELECT
        user_id,
        COUNT(*) AS user_apply_cnt_30d,
        AVG(amount) AS user_avg_amount_30d,
        AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS user_pass_rate_30d
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt BETWEEN DATE('2024-01-30') - INTERVAL 30 DAY 
                AND DATE('2024-01-30') - INTERVAL 1 DAY
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
WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30';
```

### 3.4 计算模型评估指标（KS）

使用分箱法估算 KS 值（示例基于 `pred_score` 和 `bad_flag`）：

```sql
WITH score_bad AS (
    SELECT
        pred_score,
        bad_flag
    FROM feature_apply_broad
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-30'
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
)
SELECT
    MAX(cum_bad * 1.0 / total_bad - cum_good * 1.0 / total_good) AS ks
FROM cumulative;
```



执行结果示例：`0.00508。

### 3.5 创建模型评估结果表 `ads_model_eval`

sql

```
CREATE TABLE ads_model_eval (
    eval_date   DATE,
    model_name  VARCHAR,
    auc         DECIMAL(6,4),
    ks          DECIMAL(6,4),
    psi         DECIMAL(6,4),
    check_time  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```



将 KS 计算结果写入该表（可定期执行）。

### 3.6 集成到调度

在 `run_full_etl.py` 中添加步骤（可选）：

```python
# 构建特征宽表
run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/features/build_feature_broad.sql',
                '--vars', f'dt_start={dt_start} dt_end={dt_end}', '--db', db])
# 计算模型指标并写入评估表
run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/features/calc_model_metrics.sql',
                            '--vars', f'base_date={dt_start} eval_date={dt_end}','--db', db])
```

## 4. 遇到的问题与解决方案

| 问题                                         | 原因                        | 解决方案                                    |
| :------------------------------------------- | :-------------------------- | :------------------------------------------ |
| `dim_credit_score` 表不存在                  | Day 47 首次引入，未提前创建 | 创建表并插入模拟数据                        |
| `feature_apply_broad` 缺少 `pred_score` 字段 | 初始设计遗漏                | 增加该字段，并在插入时生成模拟预测分        |
| 逾期标签无真实数据                           | 模拟数据未包含贷后表现      | 使用随机逻辑生成 `bad_flag`，仅用于演示流程 |
| KS 计算中 `NTILE` 分桶数不足导致误差         | 样本量小（5000条）          | 使用10分桶，结果稳定                        |

## 5. 核心产出清单

- 维度表 `dim_credit_score`
- 特征宽表 `feature_apply_broad`
- 特征构建 SQL：`sql/features/build_feature_broad.sql`
- 模型评估表 `ads_model_eval`
- KS 计算 SQL：`sql/features/calc_model_metrics.sql`
- 更新文档：
  - `docs/metrics_definitions.md`：添加特征宽表和模型评估指标口径
  - `docs/etl_design.md`：补充特征工程与模型评估模块

## 6. 思考题

- 特征宽表构建时，如何避免数据泄露？
  → 历史行为特征只使用申请日之前30天的数据，不包含未来信息；逾期标签使用表现期后的数据。
- 如果逾期标签尚未产生，模型评估如何做？
  → 可使用替代指标（如通过率、拒绝率变化）或等待表现期后回填。
- 如何将模型评估结果集成到告警系统？
  → 当 KS 低于阈值或 PSI 超过0.25时，通过告警引擎发送通知。