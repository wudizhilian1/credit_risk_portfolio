# Day 30 实践报告：DWS层构建（拒绝原因TopN & 稳定性监控）

## 1. 练习目标

- 掌握从 DWD 明细数据中提取 **拒绝原因分布** 的方法，并按渠道、日期等维度统计 TopN 拒绝原因。
- 理解 **稳定性监控** 在风控中的重要性：对比今日与昨日（或上周同期）的拒绝原因分布，识别异常波动。
- 编写 SQL 计算拒绝原因 TopN，并计算其占比及环比变化（差值）。
- 为后续 PSI 等量化稳定性指标打下基础。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_decision_latest`（每个申请一条最新决策记录，含 `apply_id`, `decision`, `reject_reason`, `dt`）
  - `dwd_apply_latest`（如需关联渠道信息）

- 维表：

  - `dim_reject_reason`（含 `reason_code`, `reason_desc`, `reason_category`）
  - `dim_channel`（含 `channel_id`, `channel_name`）

- 数据时间范围：2024-01-01 至 2024-01-30

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── dws/
  │       ├── dws_reject_topn_daily.sql
  │       ├── dws_channel_reject_topn.sql
  │       └── dws_reject_stability.sql
  ├── docs/
  │   └── metrics_definitions.md
  └── reports/
      └── day30_reject_topn.md
  ```

  

## 3. 核心任务执行

### 3.1 整体拒绝原因 TopN（按日）

**脚本：`sql/dws/dws_reject_topn_daily.sql**

**脚本：`sql/dws/dws_reject_topn_daily.sql`**

```sql
WITH reject_stats AS (
    SELECT
        dt,
        COALESCE(reject_reason, 'UNKNOWN') AS reason_code,
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
ORDER BY r.reject_cnt DESC
LIMIT 10;
```

**执行（以 2024-01-15 为例）**：

```bash
python scripts/run_sql.py --sql sql/dws/dws_reject_topn_daily.sql --vars dt=2024-01-15 --out reports/reject_topn_2024-01-15.md
```

**输出示例**：

```
+---------------------+---------------+---------------+-------------------+------------------------------------------------------------------------------------+--------------+-------+------+
| dt                  | reason_code   | reason_desc   | reason_category   | r                                                                                  |   reject_cnt |   pct |   rn |
|---------------------+---------------+---------------+-------------------+------------------------------------------------------------------------------------+--------------+-------+------|
| 2024-01-15 00:00:00 | FRAUD         | 欺诈风险      | 欺诈              | {'dt': datetime.date(2024, 1, 15), 'reason_code': 'FRAUD', 'reject_cnt': 687}      |          687 | 21.02 |    1 |
| 2024-01-15 00:00:00 | BLACKLIST     | 命中黑名单    | 黑名单            | {'dt': datetime.date(2024, 1, 15), 'reason_code': 'BLACKLIST', 'reject_cnt': 684}  |          684 | 20.92 |    2 |
| 2024-01-15 00:00:00 | OVER_LIMIT    | 超出限额      | 信用              | {'dt': datetime.date(2024, 1, 15), 'reason_code': 'OVER_LIMIT', 'reject_cnt': 653} |          653 | 19.98 |    3 |
| 2024-01-15 00:00:00 | UNKNOW        |               |                   | {'dt': datetime.date(2024, 1, 15), 'reason_code': 'UNKNOW', 'reject_cnt': 629}     |          629 | 19.24 |    4 |
| 2024-01-15 00:00:00 | RISK_SCORE    | 风险评分不足  | 信用              | {'dt': datetime.date(2024, 1, 15), 'reason_code': 'RISK_SCORE', 'reject_cnt': 616} |          616 | 18.84 |    5 |
+---------------------+---------------+---------------+-------------------+------------------------------------------------------------------------------------+--------------+-------+------+
```

### 3.2 分渠道拒绝原因 TopN

**脚本：`sql/dws/dws_channel_reject_topn.sql`**

```sql
WITH channel_reject AS (
    SELECT
        a.channel_id,
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason_code,
        COUNT(*) AS reject_cnt
    FROM dwd_decision_latest d
    JOIN dwd_apply_latest a ON d.apply_id = a.apply_id
    WHERE d.decision = 'REJECT'
      AND d.dt = '{{dt}}'
    GROUP BY a.channel_id, d.reject_reason
),
ranked AS (
    SELECT
        cr.channel_id,
        c.channel_name,
        cr.reason_code,
        rr.reason_desc,
        cr.reject_cnt,
        ROW_NUMBER() OVER (PARTITION BY cr.channel_id ORDER BY cr.reject_cnt DESC) AS rn
    FROM channel_reject cr
    LEFT JOIN dim_channel c ON cr.channel_id = c.channel_id
    LEFT JOIN dim_reject_reason rr ON cr.reason_code = rr.reason_code
)
SELECT
    channel_id,
    channel_name,
    reason_code,
    reason_desc,
    reject_cnt,
    rn
FROM ranked
WHERE rn <= 5
ORDER BY channel_id, rn;
```

**输出示例（部分）**：

```
+--------------+----------------+---------------+---------------+--------------+------+
| channel_id   | channel_name   | reason_code   | reason_desc   |   reject_cnt |   rn |
|--------------+----------------+---------------+---------------+--------------+------|
| API          | API接口        | OVER_LIMIT    | 超出限额      |          166 |    1 |
| API          | API接口        | FRAUD         | 欺诈风险      |          161 |    2 |
| API          | API接口        | RISK_SCORE    | 风险评分不足  |          158 |    3 |
| API          | API接口        | BLACKLIST     | 命中黑名单    |          152 |    4 |
| API          | API接口        | UNKNOWN       |               |          147 |    5 |
| APP          | 手机应用       | BLACKLIST     | 命中黑名单    |          187 |    1 |
| APP          | 手机应用       | FRAUD         | 欺诈风险      |          161 |    2 |
| APP          | 手机应用       | UNKNOWN       |               |          160 |    3 |
| APP          | 手机应用       | OVER_LIMIT    | 超出限额      |          152 |    4 |
| APP          | 手机应用       | RISK_SCORE    | 风险评分不足  |          137 |    5 |
| H5           | H5页面         | FRAUD         | 欺诈风险      |          177 |    1 |
| H5           | H5页面         | BLACKLIST     | 命中黑名单    |          170 |    2 |
| H5           | H5页面         | OVER_LIMIT    | 超出限额      |          169 |    3 |
| H5           | H5页面         | UNKNOWN       |               |          164 |    4 |
| H5           | H5页面         | RISK_SCORE    | 风险评分不足  |          158 |    5 |
| WEB          | 网页端         | FRAUD         | 欺诈风险      |          188 |    1 |
| WEB          | 网页端         | BLACKLIST     | 命中黑名单    |          175 |    2 |
| WEB          | 网页端         | OVER_LIMIT    | 超出限额      |          166 |    3 |
| WEB          | 网页端         | RISK_SCORE    | 风险评分不足  |          163 |    4 |
| WEB          | 网页端         | UNKNOWN       |               |          158 |    5 |
+--------------+----------------+---------------+---------------+--------------+------+
```

### 3.3 （加分项）拒绝原因稳定性监控（对比7天前）

**脚本：`sql/dws/dws_reject_stability.sql`**

```sql
WITH today AS (
    SELECT COALESCE(reject_reason, 'UNKNOWN') AS reason_code, COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt}}'
    GROUP BY reject_reason
),
prev AS (
    SELECT COALESCE(reject_reason, 'UNKNOWN') AS reason_code, COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt_minus7}}'
    GROUP BY reject_reason
),
total_today AS (SELECT SUM(cnt) AS total FROM today),
total_prev AS (SELECT SUM(cnt) AS total FROM prev),
combined AS (
    SELECT
        COALESCE(t.reason_code, p.reason_code) AS reason_code,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(p.cnt, 0) AS cnt_prev,
        tt.total AS total_today,
        tp.total AS total_prev
    FROM today t
    FULL OUTER JOIN prev p ON t.reason_code = p.reason_code
    CROSS JOIN total_today tt
    CROSS JOIN total_prev tp
)
SELECT
    reason_code,
    rr.reason_desc,
    cnt_today,
    cnt_prev,
    ROUND(100.0 * cnt_today / total_today, 2) AS pct_today,
    ROUND(100.0 * cnt_prev / total_prev, 2) AS pct_prev,
    ROUND(100.0 * cnt_today / total_today - 100.0 * cnt_prev / total_prev, 2) AS diff_pct
FROM combined
LEFT JOIN dim_reject_reason rr ON reason_code = rr.reason_code
WHERE cnt_today > 0 OR cnt_prev > 0
ORDER BY ABS(diff_pct) DESC
LIMIT 20;
```

**执行**：

```bash
python scripts/run_sql.py --sql sql/dws/dws_reject_stability.sql --vars dt=2024-01-15 dt_minus7=2024-01-08 --out reports/reject_stability_2024-01-15.md
```

**输出示例**：

```
+---------------+---------------+-------------+------------+-------------+------------+------------+
| reason_code   | reason_desc   |   cnt_today |   cnt_prev |   pct_today |   pct_prev |   diff_pct |
|---------------+---------------+-------------+------------+-------------+------------+------------|
| BLACKLIST     | 命中黑名单    |         684 |        329 |       20.92 |      10.06 |      10.86 |
| RISK_SCORE    | 风险评分不足  |         616 |        267 |       18.84 |       8.17 |      10.68 |
| FRAUD         | 欺诈风险      |         687 |        358 |       21.02 |      10.95 |      10.06 |
| OVER_LIMIT    | 超出限额      |         653 |        335 |       19.98 |      10.25 |       9.73 |
|               |               |         629 |        369 |       19.24 |      11.29 |       7.95 |
+---------------+---------------+-------------+------------+-------------+------------+------------+
```

## 4. 口径与边界说明

| 要素               | 说明                                                         |
| :----------------- | :----------------------------------------------------------- |
| **拒绝原因标准化** | `reject_reason` 可能为 NULL，统一处理为 `'UNKNOWN'`，并通过维表关联描述和分类。 |
| **占比计算**       | 分母为当日总拒绝次数，而非总申请量，专注于拒绝内部结构。     |
| **TopN 定义**      | 按拒绝次数降序排列，取前 N 个原因。                          |
| **稳定性对比**     | 对比今日与 7 天前的占比差值，可用于监控拒绝原因分布的显著变化。 |
| **空值处理**       | 使用 `COALESCE` 保证 NULL 原因也能被统计。                   |
| **分渠道**         | 需要关联 `dwd_apply_latest` 获取渠道信息，通过 `apply_id` 关联。 |

## 5. 性能点

- 查询仅涉及 `dwd_decision_latest` 表，且使用 `dt` 分区过滤，扫描量小（单日数据）。
- 分渠道 TopN 需要关联 `dwd_apply_latest`，但通过 `apply_id` 哈希关联，性能良好。
- 稳定性对比使用 `FULL OUTER JOIN`，在数据量不大的情况下（单日拒绝记录通常 <5000）可秒级返回。
- 可将 TopN 结果物化为 DWS 表，供报表系统直接查询，避免重复计算。

## 10. 思考题

- 如果某天拒绝原因中出现新的代码（维表中不存在），应如何处理？
  → 可暂归为 `'OTHER'`，同时触发告警检查维表是否需要更新，并将新代码记录到异常表。
- 除了占比差值，还有哪些指标可用于衡量分布变化？
  → PSI（群体稳定性指标）、KL 散度、卡方检验等，可量化分布差异。
- 如何自动化监控 TopN 变化并推送告警？
  → 每日运行稳定性脚本，若 `diff_pct` 超过阈值（如 |5%|），则写入告警表，并通过邮件或钉钉通知数据负责人。