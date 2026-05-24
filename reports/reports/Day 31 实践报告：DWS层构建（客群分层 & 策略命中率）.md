# Day 31 实践报告：DWS层构建（客群分层 & 策略命中率）

## 1. 练习目标

- 理解 **客群分层** 在风控分析中的价值：不同客群（新客/老客、额度区间、渠道）的风险表现差异显著，分层分析有助于精细化运营和策略调优。
- 掌握使用 `CASE WHEN` 对连续字段（如 `amount`）进行分桶，以及基于用户注册时间划分新老客的方法。
- 构建客群分层日报表 `dws_segment_daily`，按日期、客群维度汇总申请量、通过率、拒绝率等核心指标。
- （加分项）扩展策略命中率指标，构建 `dws_strategy_hit_daily`，计算策略版本的命中率（非通过比例），为策略评估提供更全面的视角。
- 明确各分层口径，更新指标字典文档。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_apply_latest`（已去重，含 `apply_id`, `user_id`, `channel_id`, `amount`, `apply_time`, `dt`）
  - `dwd_decision_latest`（已去重，含 `apply_id`, `decision`, `strategy_version`, `dt`）

- 维表：

  - `dim_channel`（含 `channel_id`, `channel_name`, `channel_group`）
  - `dim_customer`（含 `user_id`, `registration_date`）
  - `dim_strategy`（含 `strategy_version`, `strategy_name`）

- 数据时间范围：2024-01-01 至 2024-01-30

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── dws/
  │       ├── dws_segment_daily.sql
  │       └── dws_strategy_hit_daily.sql（可选）
  ├── docs/
  │   └── metrics_definitions.md
  └── reports/
      └── day31_segment_report.md
  ```

  

## 3. 核心任务执行

### 3.1 创建客群分层表 `dws_segment_daily`

```sql
CREATE TABLE IF NOT EXISTS dws_segment_daily (
    dt              DATE NOT NULL,
    customer_type   VARCHAR,      -- '新客', '老客', '未知'
    amount_bucket   VARCHAR,      -- '小额', '中额', '大额'
    channel_group   VARCHAR,      -- '自有', '外部', '其他'
    apply_cnt       INT,
    pass_cnt        INT,
    reject_cnt      INT,
    review_cnt      INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2)
);
```

### 3.2 编写并执行 ETL 脚本（修正日期计算问题）

**文件：`sql/dws/dws_segment_daily.sql`**（修正后）

```sql
BEGIN TRANSACTION;

DELETE FROM dws_segment_daily;

WITH
customer_reg AS (
    SELECT user_id, registration_date
    FROM dim_customer
),
base AS (
    SELECT
        a.dt,
        a.apply_id,
        a.amount,
        c.registration_date,
        ch.channel_group,
        d.decision
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    LEFT JOIN customer_reg c ON a.user_id = c.user_id
    WHERE a.dt BETWEEN '2024-01-01' AND '2024-01-30'
),
segmented AS (
    SELECT
        dt,
        CASE
            WHEN registration_date IS NULL THEN '未知'
            WHEN (a.dt - registration_date) <= 30 THEN '新客'
            ELSE '老客'
        END AS customer_type,
        CASE
            WHEN amount < 5000 THEN '小额'
            WHEN amount BETWEEN 5000 AND 20000 THEN '中额'
            ELSE '大额'
        END AS amount_bucket,
        COALESCE(channel_group, '其他') AS channel_group,
        apply_id,
        decision
    FROM base a
)
SELECT
    dt,
    customer_type,
    amount_bucket,
    channel_group,
    COUNT(DISTINCT apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) AS pass_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) AS reject_cnt,
    COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END) AS review_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS pass_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END) / NULLIF(COUNT(DISTINCT apply_id), 0), 2) AS reject_rate
FROM segmented
GROUP BY dt, customer_type, amount_bucket, channel_group
ORDER BY dt, customer_type, amount_bucket, channel_group;

COMMIT;
```

执行脚本：

```bash
python scripts/run_sql.py --sql sql/dws/dws_segment_daily.sql
```



### 3.3 执行结果示例

查询 2024-01-15 的数据：

```sql
SELECT * FROM dws_segment_daily 
WHERE dt = '2024-01-15' 
ORDER BY apply_cnt DESC 
LIMIT 10;
```

**输出示例**：

```
+---------------------+-----------------+-----------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
| dt                  | customer_type   | amount_bucket   | channel_group   |   apply_cnt |   pass_cnt |   reject_cnt |   review_cnt |   pass_rate |   reject_rate |
|---------------------+-----------------+-----------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------|
| 2024-01-15 00:00:00 | 未知            | 大额            | 自有            |        4561 |       1502 |         1528 |         1531 |       32.93 |         33.5  |
| 2024-01-15 00:00:00 | 未知            | 中额            | 自有            |        2311 |        816 |          754 |          741 |       35.31 |         32.63 |
| 2024-01-15 00:00:00 | 未知            | 大额            | 外部            |        1470 |        509 |          463 |          498 |       34.63 |         31.5  |
| 2024-01-15 00:00:00 | 未知            | 中额            | 外部            |         824 |        275 |          255 |          294 |       33.37 |         30.95 |
| 2024-01-15 00:00:00 | 未知            | 小额            | 自有            |         573 |        185 |          192 |          196 |       32.29 |         33.51 |
| 2024-01-15 00:00:00 | 未知            | 小额            | 外部            |         213 |         80 |           63 |           70 |       37.56 |         29.58 |
| 2024-01-15 00:00:00 | 老客            | 大额            | 自有            |          21 |         10 |            5 |            6 |       47.62 |         23.81 |
| 2024-01-15 00:00:00 | 老客            | 中额            | 自有            |          14 |          5 |            5 |            4 |       35.71 |         35.71 |
| 2024-01-15 00:00:00 | 老客            | 大额            | 外部            |           6 |          2 |            2 |            2 |       33.33 |         33.33 |
| 2024-01-15 00:00:00 | 老客            | 小额            | 自有            |           3 |          1 |            1 |            1 |       33.33 |         33.33 |
+---------------------+-----------------+-----------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
```

### 3.4 （加分项）策略命中率表 `dws_strategy_hit_daily`

**建表语句**：

```sql
CREATE TABLE IF NOT EXISTS dws_strategy_hit_daily (
    dt                  DATE NOT NULL,
    strategy_version    VARCHAR,
    strategy_name       VARCHAR,
    apply_cnt           INT,
    pass_cnt            INT,
    hit_cnt             INT,
    pass_rate           DECIMAL(5,2),
    hit_rate            DECIMAL(5,2)
);
```

**插入数据**：

```sql
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
```

**查询示例**（2024-01-15）：

```sql
SELECT * FROM dws_strategy_hit_daily WHERE dt = '2024-01-15' ORDER BY apply_cnt DESC;
```

```
+---------------------+--------------------+-----------------+-------------+------------+-----------+-------------+------------+
| dt                  | strategy_version   | strategy_name   |   apply_cnt |   pass_cnt |   hit_cnt |   pass_rate |   hit_rate |
|---------------------+--------------------+-----------------+-------------+------------+-----------+-------------+------------|
| 2024-01-15 00:00:00 | v1.0               | 基础审批策略    |        3359 |       1131 |      2228 |       33.67 |      66.33 |
| 2024-01-15 00:00:00 | v2.0               | 激进策略        |        3335 |       1129 |      2206 |       33.85 |      66.15 |
| 2024-01-15 00:00:00 | v1.1               | 优化版策略      |        3306 |       1126 |      2180 |       34.06 |      65.94 |
+---------------------+--------------------+-----------------+-------------+------------+-----------+-------------+------------+
```

## 4. 口径与边界说明

| 字段                   | 口径                                                         |
| :--------------------- | :----------------------------------------------------------- |
| `customer_type`        | 基于 `dim_customer.registration_date` 与申请日差值，≤30天为新客，>30天为老客，无注册日期为“未知”。 |
| `amount_bucket`        | 小额：`amount < 5000`；中额：`5000 ≤ amount ≤ 20000`；大额：`amount > 20000`。阈值可调整。 |
| `channel_group`        | 取自 `dim_channel.channel_group`，若渠道ID无对应分组，则归为“其他”。 |
| `hit_cnt` / `hit_rate` | 命中定义为决策结果为 `REJECT` 或 `REVIEW`，反映策略拒绝或转人工的比例。 |
| 新老客日期差计算       | 使用 `(dt - registration_date)` 直接得到天数，无需 `DATE_PART`。 |

## 5. 性能点

- 客群分层需要关联多张表，但都在 `dt` 分区过滤下进行，单日数据量约5000行，扫描量可控。
- 使用 `WITH` 子句先构建基础事实，避免重复扫描。
- 若数据量增大，可考虑将分层逻辑写入 DWD 层（如添加 `customer_type` 字段），减少每日计算开销。
- 策略命中率表同样在 `dt` 过滤下聚合，性能良好。

## 10. 思考题

- 如果 `dim_customer` 没有注册日期，如何定义新老客？
  → 可用用户在 `dwd_apply_latest` 中首次申请日期作为“首次出现日”，近似注册日。
- 额度区间的阈值如何科学确定？
  → 可基于业务经验（如产品定价区间）或使用分位数（如按金额的33%、67%分位数）自动划分。
- 命中率指标是否应包含 `REVIEW`？请结合业务讨论。
  → `REVIEW` 表示人工审核，虽然可能最终通过，但通常意味着规则无法自动决策，可视作“未通过自动审批”，因此计入命中率可反映策略的覆盖度和效率。需根据业务定义确认。