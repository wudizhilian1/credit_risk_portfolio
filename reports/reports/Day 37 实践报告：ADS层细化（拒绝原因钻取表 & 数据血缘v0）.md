# Day 37 实践报告：ADS层细化（拒绝原因钻取表 & 数据血缘v0）

## 1. 练习目标

- 完善 ADS 层，设计 **拒绝原因钻取表**，支持从拒绝原因 TopN 下钻到具体申请样本，便于业务人员快速定位问题。
- 建立 **数据血缘文档**，使用 Mermaid 绘制从 raw 到 ADS 的完整数据流向，增强项目可理解性。
- 编写 SQL 脚本抽取钻取样本，并关联维表获取可读信息。
- 将钻取表接入监控或报表，提升异常排查效率。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_apply_latest`（申请明细）
  - `dwd_decision_latest`（决策明细）

- 维表：

  - `dim_customer`、`dim_channel`、`dim_reject_reason`

- DWS 表：

  - `dws_reject_topn_daily`（拒绝原因 TopN）

- ADS 表（已有）：

  - `ads_overview_daily`、`ads_channel_quality`

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── ads/
  │       └── reject_drilldown.sql
  ├── docs/
  │   ├── lineage.md
  │   └── metrics_definitions.md
  └── reports/
      └── day37_drilldown_report.md
  ```

  

## 3. 核心任务执行

### 3.1 创建拒绝原因钻取表 `ads_reject_drilldown`

```sql
CREATE TABLE IF NOT EXISTS ads_reject_drilldown (
    dt              DATE NOT NULL,
    reason_code     VARCHAR NOT NULL,
    reason_desc     VARCHAR,
    apply_id        VARCHAR NOT NULL,
    user_id         VARCHAR,
    channel_name    VARCHAR,
    amount          DECIMAL(18,2),
    strategy_version VARCHAR,
    decision_time   TIMESTAMP
);
```

### 3.2 编写钻取样本抽取脚本 `sql/ads/reject_drilldown.sql`

```sql
-- reject_drilldown.sql
-- 功能：抽取每日每个拒绝原因下的申请样本（每个原因取前 5 条）
-- 执行方式：全量刷新，先删后插

BEGIN TRANSACTION;

DELETE FROM ads_reject_drilldown;

INSERT INTO ads_reject_drilldown
WITH ranked_samples AS (
    SELECT
        a.dt,
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason_code,
        d.apply_id,
        a.user_id,
        ch.channel_name,
        a.amount,
        d.strategy_version,
        d.decision_time,
        ROW_NUMBER() OVER (PARTITION BY a.dt, d.reject_reason ORDER BY d.decision_time DESC) AS rn
    FROM dwd_decision_latest d
    JOIN dwd_apply_latest a ON d.apply_id = a.apply_id AND d.dt = a.dt
    LEFT JOIN dim_channel ch ON a.channel_id = ch.channel_id
    WHERE d.decision = 'REJECT'
)
SELECT
    dt,
    reason_code,
    rr.reason_desc,
    apply_id,
    user_id,
    channel_name,
    amount,
    strategy_version,
    decision_time
FROM ranked_samples
LEFT JOIN dim_reject_reason rr ON ranked_samples.reason_code = rr.reason_code
WHERE rn <= 5
ORDER BY dt, reason_code, rn;

COMMIT;
```

**说明**：每个拒绝原因每天最多保留 5 条样本，按决策时间降序取最新。

### 3.3 执行并验证钻取表

```bash
python scripts/run_sql.py --sql sql/ads/reject_drilldown.sql
```

查询示例：

```sql
SELECT * FROM ads_reject_drilldown 
WHERE dt = '2024-01-20' AND reason_code = 'RISK_SCORE'
LIMIT 5;
```

**输出示例**：

```
+---------------------+---------------+---------------+-----------------+-----------+----------------+----------+--------------------+---------------------+
| dt                  | reason_code   | reason_desc   | apply_id        | user_id   | channel_name   |   amount | strategy_version   | decision_time       |
|---------------------+---------------+---------------+-----------------+-----------+----------------+----------+--------------------+---------------------|
| 2024-01-01 00:00:00 | BLACKLIST     | 命中黑名单    | 2024-01-01_644  | user_1429 | H5页面         |     5150 | v1.1               | 2024-01-01 00:00:03 |
| 2024-01-01 00:00:00 | BLACKLIST     | 命中黑名单    | 2024-01-01_536  | user_1515 | API接口        |    31200 | v1.1               | 2024-01-01 00:15:51 |
| 2024-01-01 00:00:00 | BLACKLIST     | 命中黑名单    | 2024-01-01_132  | user_1950 | H5页面         |    15694 | v1.1               | 2024-01-01 00:20:12 |
| 2024-01-01 00:00:00 | BLACKLIST     | 命中黑名单    | 2024-01-01_907  | user_1601 | 网页端         |    47975 | v2.0               | 2024-01-01 00:26:43 |
| 2024-01-01 00:00:00 | BLACKLIST     | 命中黑名单    | 2024-01-01_2553 | user_1962 | API接口        |    13460 | v1.0               | 2024-01-01 00:33:11 |
+---------------------+---------------+---------------+-----------------+-----------+----------------+----------+--------------------+---------------------+
```

### 3.4 创建数据血缘文档 `docs/lineage.md`

使用 Mermaid 绘制数据流向图，保存至 `docs/lineage.md`

**补充说明**：

- 每层之间的依赖关系已标明，红色箭头表示主要流向。
- 调度顺序：ODS → DWD → DWS → ADS，各层内部脚本可按依赖顺序执行。

## 10. 思考题

- 为什么钻取样本要按 `decision_time` 取最新？如果按申请时间取，可能有什么不同？
  → 按决策时间取最新可以反映最近发生的拒绝，更容易定位近期的策略或数据问题；按申请时间取可能包含历史积压，时效性差。
- 钻取表中的样本量如何控制？抽取太多会影响查询性能，太少可能无法代表整体。你建议每个原因每天抽多少条？
  → 5-10 条通常足够，可配置化，并在文档中说明。
- 如何将钻取表与 BI 工具结合，实现点击拒绝原因后展示样本列表？
  → 在仪表板中设置超链接或下钻事件，将拒绝原因作为参数传递给明细表查询。