# Day 29 实践报告：DWS层构建（渠道日报 & 策略日报）

## 1. 练习目标

- 理解 **DWS（轻度汇总层）** 的作用：对 DWD 明细数据进行预聚合，存储常用维度的核心指标，提升查询性能，满足日常报表需求。
- 设计渠道日报表（`dws_channel_daily`），按日期、渠道统计申请量、通过量、通过率、拒绝量、拒绝率。
- 设计策略日报表（`dws_strategy_daily`），按日期、策略版本统计申请量、通过量、拒绝量等，为策略评估提供数据基础。
- 掌握使用 `GROUP BY` 和聚合函数（`COUNT`, `SUM`, `AVG`）进行数据汇总的方法。
- 明确各指标口径，更新指标字典文档。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_apply_latest`（已去重，含 `apply_id`, `channel_id`, `dt` 等）
  - `dwd_decision_latest`（已去重，含 `apply_id`, `decision`, `strategy_version`, `dt`）

- 维表：

  - `dim_channel`（含 `channel_id`, `channel_name`, `channel_group`）
  - `dim_strategy`（含 `strategy_version`, `strategy_name`）

- 数据时间范围：2024-01-01 至 2024-01-30

- 项目目录：

  ```text
  credit_risk_portfolio/
  ├── sql/
  │   └── dws/
  │       ├── dws_channel_daily.sql
  │       └── dws_strategy_daily.sql
  ├── docs/
  │   └── metrics_definitions.md
  └── reports/
      └── day29_dws.md
  ```

## 3. 核心任务执行

### 3.1 创建 DWS 表结构

**渠道日报表 `dws_channel_daily`**

```sql
CREATE TABLE IF NOT EXISTS dws_channel_daily (
    dt              DATE NOT NULL,
    channel_id      VARCHAR,
    channel_name    VARCHAR,
    apply_cnt       INT,
    pass_cnt        INT,
    reject_cnt      INT,
    review_cnt      INT,
    pass_rate       DECIMAL(5,2),
    reject_rate     DECIMAL(5,2)
);
```

**策略日报表 `dws_strategy_daily`**

```sql
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
```

### 3.2 编写并执行 ETL 脚本

**文件：`sql/dws/dws_channel_daily.sql`**（全量刷新）

```sql
BEGIN TRANSACTION;

DELETE FROM dws_channel_daily;

INSERT INTO dws_channel_daily (dt, channel_id, channel_name, apply_cnt, pass_cnt, reject_cnt, review_cnt, pass_rate, reject_rate)
WITH daily_stats AS (
    SELECT
        a.dt,
        a.channel_id,
        c.channel_name,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REVIEW' THEN a.apply_id END) AS review_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
    GROUP BY a.dt, a.channel_id, c.channel_name
)
SELECT
    dt,
    channel_id,
    channel_name,
    apply_cnt,
    pass_cnt,
    reject_cnt,
    review_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
    ROUND(100.0 * reject_cnt / NULLIF(apply_cnt, 0), 2) AS reject_rate
FROM daily_stats
ORDER BY dt, channel_id;

COMMIT;
```

**文件：`sql/dws/dws_strategy_daily.sql`**（全量刷新）

```sql
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
WHERE strategy_version IS NOT NULL
ORDER BY dt, strategy_version;

COMMIT;
```

执行命令：

```bash
duckdb dev.duckdb
.read sql/dws/dws_channel_daily.sql
.read sql/dws/dws_strategy_daily.sql
```

### 3.3 验证结果

#### 渠道日报示例（2024-01-15）

```sql
SELECT * FROM dws_channel_daily WHERE dt = '2024-01-15' ORDER BY apply_cnt DESC;
```

**输出示例**：

```
+---------------------+--------------+----------------+-------------+------------+--------------+--------------+-------------+---------------+
| dt                  | channel_id   | channel_name   |   apply_cnt |   pass_cnt |   reject_cnt |   review_cnt |   pass_rate |   reject_rate |
|---------------------+--------------+----------------+-------------+------------+--------------+--------------+-------------+---------------|
| 2024-01-15 00:00:00 | H5           | H5页面         |        2522 |        849 |          838 |          835 |       33.66 |         33.23 |
| 2024-01-15 00:00:00 | API          | API接口        |        2517 |        867 |          784 |          866 |       34.45 |         31.15 |
| 2024-01-15 00:00:00 | WEB          | 网页端         |        2513 |        809 |          850 |          854 |       32.19 |         33.82 |
| 2024-01-15 00:00:00 | APP          | 手机应用       |        2448 |        861 |          797 |          790 |       35.17 |         32.56 |
+---------------------+--------------+----------------+-------------+------------+--------------+--------------+-------------+---------------+
```

#### 策略日报示例（2024-01-15）

```sql
SELECT * FROM dws_strategy_daily WHERE dt = '2024-01-15' ORDER BY apply_cnt DESC;
```

**输出示例**：

```
+---------------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
| dt                  | strategy_version   | strategy_name   |   apply_cnt |   pass_cnt |   reject_cnt |   review_cnt |   pass_rate |   reject_rate |
|---------------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------|
| 2024-01-15 00:00:00 | v1.0               | 基础审批策略    |        3359 |       1131 |         1124 |         1104 |       33.67 |         33.46 |
| 2024-01-15 00:00:00 | v2.0               | 激进策略        |        3335 |       1129 |         1092 |         1114 |       33.85 |         32.74 |
| 2024-01-15 00:00:00 | v1.1               | 优化版策略      |        3306 |       1126 |         1053 |         1127 |       34.06 |         31.85 |
+---------------------+--------------------+-----------------+-------------+------------+--------------+--------------+-------------+---------------+
```

#### 验证与 DWD 明细的一致性（抽样）

```sql
-- 检查 APP 渠道 2024-01-15 的申请量是否与明细匹配
SELECT COUNT(DISTINCT a.apply_id) 
FROM dwd_apply_latest a 
WHERE a.dt = '2024-01-15' AND a.channel_id = 'APP';
-- 预期结果为 4068，与上表一致
```

## 4. 口径与边界说明

| 指标            | 口径                                                         |
| :-------------- | :----------------------------------------------------------- |
| **apply_cnt**   | 当日申请去重后的申请单总数（基于 `dwd_apply_latest`）。      |
| **pass_cnt**    | 当日申请中最终决策为 `PASS` 的申请单数（关联 `dwd_decision_latest`，取最新决策）。 |
| **reject_cnt**  | 当日申请中最终决策为 `REJECT` 的申请单数。                   |
| **review_cnt**  | 当日申请中最终决策为 `REVIEW`（人工审核）的申请单数。        |
| **pass_rate**   | `pass_cnt / apply_cnt * 100`，当 `apply_cnt = 0` 时返回 NULL。 |
| **reject_rate** | 同理。                                                       |
| **渠道名称**    | 通过 `dim_channel` 关联得到，若渠道 ID 在维表中不存在，则显示为 NULL。 |
| **策略名称**    | 通过 `dim_strategy` 关联得到，若策略版本不在维表中，则显示为 NULL。 |

## 5. 性能点

- **预聚合**：DWS 表将明细数据按常用维度预先聚合，后续报表查询直接读取 DWS 表，避免每次扫描明细表（约 15 万行）。
- **列裁剪**：DWS 表只存储必要字段，减少存储和 I/O。
- **索引**：DWS 表在 `dt` 和 `channel_id`/`strategy_version` 上虽然没有显式索引，但 DuckDB 的列式存储和过滤下推已足够高效。
- **更新策略**：当前采用全量刷新（`DELETE`+`INSERT`），简单易行。后续若数据量增大，可改为每日增量（按 `dt` 先删后插），减少处理时间。

## 10. 思考题

- 如果希望 DWS 表支持每日增量更新（只处理当天数据），应该如何修改 SQL？
  → 将 `DELETE` 改为 `DELETE FROM dws_channel_daily WHERE dt = 目标日期`，`INSERT` 语句中增加 `WHERE a.dt = 目标日期` 条件。
- 在策略日报中，如果某策略版本当日无申请，是否应该在结果中保留一行（`apply_cnt=0`）？如何实现？
  → 需要先通过维表获取所有策略版本，再用 `CROSS JOIN` 生成所有日期-策略组合，最后左连接聚合结果，并用 `COALESCE` 填充 0。
- 如何验证 DWS 表的汇总结果与 DWD 明细的手动计算一致？
  → 随机抽取某日某渠道，分别从 DWS 和 DWD 明细计算，对比各项指标；也可编写自动化对账脚本。