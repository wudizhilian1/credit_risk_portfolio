# Day 33 实践报告：客群与策略交叉分析（分群策略评估）

## 1. 练习目标

- 将 **客群分层** 与 **策略评估** 结合，构建交叉分析表，观察不同客群（新客/老客、额度区间）在各策略版本下的表现差异。
- 理解分层评估的价值：同一策略在不同客群上的效果可能不同，有助于精细化调优。
- 掌握使用多维度 `GROUP BY` 和 `CASE WHEN` 进行交叉汇总的方法。
- 编写 SQL 实现客群×策略交叉日报，并解释各指标的业务含义。
- 更新指标字典文档，完善分群策略评估口径。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_apply_latest`（申请明细，含 `apply_id`, `user_id`, `channel_id`, `amount`, `dt`）
  - `dwd_decision_latest`（决策明细，含 `apply_id`, `decision`, `strategy_version`, `dt`）

- 维表：

  - `dim_customer`（含 `user_id`, `registration_date`）
  - `dim_strategy`（含 `strategy_version`, `strategy_name`）

- 数据时间范围：2024-01-01 至 2024-01-30

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── dws/
  │       └── dws_segment_strategy_daily.sql
  ├── docs/
  │   └── metrics_definitions.md
  └── reports/
      └── day33_segment_strategy.md
  ```

## 3. 核心任务执行

### 3.1 创建交叉分析表 `dws_segment_strategy_daily`

```sql
CREATE TABLE IF NOT EXISTS dws_segment_strategy_daily (
    dt                  DATE NOT NULL,
    customer_type       VARCHAR,      -- 新客/老客/未知
    amount_bucket       VARCHAR,      -- 小额/中额/大额
    strategy_version    VARCHAR,      -- 策略版本
    strategy_name       VARCHAR,      -- 策略名称
    apply_cnt           INT,
    pass_cnt            INT,
    reject_cnt          INT,
    review_cnt          INT,
    pass_rate           DECIMAL(5,2),
    reject_rate         DECIMAL(5,2)
);
```



### 3.2 编写并执行 ETL 脚本（全量刷新）

**文件：`sql/dws/dws_segment_strategy_daily.sql`**

```sql
-- dws_segment_strategy_daily.sql
-- 功能：按日期、客户类型、额度区间、策略版本统计核心指标
-- 使用方式：通过 run_sql.py 执行（全量刷新）

BEGIN TRANSACTION;

DELETE FROM dws_segment_strategy_daily;

WITH
-- 客户注册信息
customer_reg AS (
    SELECT user_id, registration_date
    FROM dim_customer
),
-- 基础事实：关联申请、决策、客户、策略
base AS (
    SELECT
        a.dt,
        a.apply_id,
        a.amount,
        c.registration_date,
        d.decision,
        d.strategy_version,
        s.strategy_name
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_strategy s ON d.strategy_version = s.strategy_version
    LEFT JOIN customer_reg c ON a.user_id = c.user_id
    WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30'   -- 可调整范围
),
-- 定义分层字段
segmented AS (
    SELECT
        dt,
        CASE
            WHEN registration_date IS NULL THEN '未知'
            WHEN (dt - registration_date) <= 30 THEN '新客'
            ELSE '老客'
        END AS customer_type,
        CASE
            WHEN amount < 5000 THEN '小额'
            WHEN amount BETWEEN 5000 AND 20000 THEN '中额'
            ELSE '大额'
        END AS amount_bucket,
        COALESCE(strategy_version, '未知策略') AS strategy_version,
        COALESCE(strategy_name, '未知') AS strategy_name,
        apply_id,
        decision
    FROM base
)
-- 聚合统计
SELECT
    dt,
    customer_type,
    amount_bucket,
    strategy_version,
    strategy_name,
    COUNT(DISTINCT apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) AS reject_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END) AS review_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS reject_rate
FROM segmented
GROUP BY dt, customer_type, amount_bucket, strategy_version, strategy_name
ORDER BY dt, customer_type, amount_bucket, strategy_version;

COMMIT;
```

执行脚本：

```bash
python scripts/run_sql.py --sql sql/dws/dws_segment_strategy_daily.sql
```

### 3.3 执行结果验证

查询 2024-01-15 的数据：

```sql
SELECT * FROM dws_segment_strategy_daily 
WHERE dt = '2024-01-15' 
ORDER BY apply_cnt DESC 
LIMIT 15;
```

**输出示例**：

```
+---------------------+-----------------+-----------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
| dt                  | customer_type   | amount_bucket   | strategy_version   | strategy_name   |   apply_cnt |   pass_cnt |   reject_cnt |   review_cnt |   pass_rate |   reject_rate |
|---------------------+-----------------+-----------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------|
| 2024-01-15 00:00:00 | 未知            | 大额            | v1.0               | 基础审批策略    |        2049 |        677 |          702 |          670 |       33.04 |         34.26 |
| 2024-01-15 00:00:00 | 未知            | 大额            | v1.1               | 优化版策略      |        2005 |        677 |          653 |          675 |       33.77 |         32.57 |
| 2024-01-15 00:00:00 | 未知            | 大额            | v2.0               | 激进策略        |        1977 |        657 |          636 |          684 |       33.23 |         32.17 |
| 2024-01-15 00:00:00 | 未知            | 中额            | v2.0               | 激进策略        |        1097 |        382 |          364 |          351 |       34.82 |         33.18 |
| 2024-01-15 00:00:00 | 未知            | 中额            | v1.0               | 基础审批策略    |        1029 |        358 |          334 |          337 |       34.79 |         32.46 |
| 2024-01-15 00:00:00 | 未知            | 中额            | v1.1               | 优化版策略      |        1009 |        351 |          311 |          347 |       34.79 |         30.82 |
| 2024-01-15 00:00:00 | 未知            | 小额            | v1.1               | 优化版策略      |         275 |         91 |           86 |           98 |       33.09 |         31.27 |
| 2024-01-15 00:00:00 | 未知            | 小额            | v1.0               | 基础审批策略    |         267 |         88 |           86 |           93 |       32.96 |         32.21 |
| 2024-01-15 00:00:00 | 未知            | 小额            | v2.0               | 激进策略        |         244 |         86 |           83 |           75 |       35.25 |         34.02 |
| 2024-01-15 00:00:00 | 老客            | 大额            | v1.1               | 优化版策略      |          11 |          4 |            2 |            5 |       36.36 |         18.18 |
+---------------------+-----------------+-----------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
```

### 3.4 一致性验证

与 `dws_segment_daily` 和 `dws_strategy_daily` 对比，确保汇总数据一致：

```sql
-- 按客户类型+额度区间汇总的申请量应与 dws_segment_daily 一致
SELECT customer_type, amount_bucket, SUM(apply_cnt) AS total_apply
FROM dws_segment_strategy_daily
WHERE dt = '2024-01-15'
GROUP BY customer_type, amount_bucket;
```

## 4. 口径与边界说明

| 字段                                     | 口径                                                         |
| :--------------------------------------- | :----------------------------------------------------------- |
| `customer_type`                          | 基于 `dim_customer.registration_date` 与申请日差值，≤30天为新客，>30天为老客，缺失为“未知”。 |
| `amount_bucket`                          | 小额：`amount < 5000`；中额：`5000 ≤ amount ≤ 20000`；大额：`amount > 20000`。阈值可调。 |
| `strategy_version`                       | 取自决策表，若决策缺失则归为“未知策略”。                     |
| `strategy_name`                          | 关联 `dim_strategy` 获取，若无则“未知”。                     |
| `apply_cnt`                              | 当日该交叉分组的申请量（按 `apply_id` 去重）。               |
| `pass_cnt` / `reject_cnt` / `review_cnt` | 对应决策结果的申请数。                                       |
| `pass_rate` / `reject_rate`              | 比率，分母为 `apply_cnt`，为0时返回 NULL。                   |

## 5. 性能点

- 查询涉及多表关联，但均通过 `dt` 过滤（单日数据约 5000 行），扫描量可控。
- 使用 `WITH` 子句先构建基础事实，再分层聚合，避免重复扫描。
- 若数据量极大，可考虑将 `customer_type` 和 `amount_bucket` 提前计算并写入 DWD 层，减少每日计算开销。
- 全量刷新采用 `DELETE`+`INSERT`，对小型表无压力；若数据量大可改为按日增量插入

## 10. 思考题

- 为什么需要客群与策略交叉分析？对策略调优有何帮助？
  → 可以发现某些策略在特定客群上效果不佳（如新客通过率低），从而针对性优化策略或设计差异化策略。
- 如果某策略版本在“新客+小额”组通过率显著低于其他组，可能的原因是什么？
  → 新客风险高、策略规则未考虑新客特征、样本量不足导致统计波动等。
- 如何设计可视化报表展示交叉分析结果？
  → 热力图（不同客群-策略组合的通过率）、分组柱状图（同一策略下不同客群通过率对比）、桑基图（流量分布）。