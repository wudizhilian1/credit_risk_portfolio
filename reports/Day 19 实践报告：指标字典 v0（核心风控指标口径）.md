# Day 19 实践报告：指标字典 v0（核心风控指标口径）

## 1. 练习目标
- 理解**指标口径**在数据工程中的核心地位：同一指标不同口径可能导致数据不一致，业务决策失误。
- 掌握风控场景下核心指标的定义方法：申请量、通过率、拒绝率、渠道质量、策略命中率等。
- 编写清晰、规范的指标口径文档，包括分子分母、去重规则、时间口径、异常处理。
- 用 SQL 实现各指标计算，并验证结果一致性。
- 为后续 DWS 层汇总表建设打下基础。

## 2. 实验环境
- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 已有表：
  - DWD 事实表：`dwd_apply_latest`（每个申请一条最新记录）
  - DWD 事实表：`dwd_decision_latest`（每个申请一条最新决策）
  - 维表：`dim_channel`、`dim_customer`、`dim_strategy`、`dim_reject_reason`（已增强）
- 数据范围：2024-01-01 至 2024-01-10，每日约 5000 申请。

## 3. 核心指标定义与 SQL 实现

### 3.1 申请量（Apply Count）
**口径**：指定日期范围内的申请单总数，每个 `apply_id` 只计一次（DWD 已去重）。

```sql
SELECT dt, COUNT(*) AS apply_cnt
FROM dwd_apply_latest
WHERE dt = '2024-01-01'
GROUP BY dt;
```

```
+---------------------+-------------+
| dt                  |   apply_cnt |
|---------------------+-------------|
| 2024-01-01 00:00:00 |        5000 |
+---------------------+-------------+
```

### 3.2 通过量（Pass Count）与通过率（Pass Rate）

**口径**：通过量 = 最终决策为 `PASS` 的申请数；通过率 = 通过量 / 申请量 * 100%。

```sql
WITH stats AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt = '2024-01-01'
    GROUP BY a.dt
)
SELECT
    dt,
    apply_cnt,
    pass_cnt,
    ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate
FROM stats;
```

```
+---------------------+-------------+------------+-------------+
| dt                  |   apply_cnt |   pass_cnt |   pass_rate |
|---------------------+-------------+------------+-------------|
| 2024-01-01 00:00:00 |        5000 |       1679 |       33.58 |
+---------------------+-------------+------------+-------------+
```

### 3.3 拒绝量（Reject Count）与拒绝率（Reject Rate）

**口径**：拒绝量 = 最终决策为 `REJECT` 的申请数；拒绝率 = 拒绝量 / 申请量 * 100%。

```sql
WITH stats AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
    WHERE a.dt = '2024-01-01'
    GROUP BY a.dt
)
SELECT
    dt,
    apply_cnt,
    reject_cnt,
    ROUND(100.0 * reject_cnt / NULLIF(apply_cnt, 0), 2) AS reject_rate
FROM stats;
```

```
+---------------------+-------------+--------------+---------------+
| dt                  |   apply_cnt |   reject_cnt |   reject_rate |
|---------------------+-------------+--------------+---------------|
| 2024-01-01 00:00:00 |        5000 |         1687 |         33.74 |
+---------------------+-------------+--------------+---------------+
```

### 3.4 渠道通过率（Channel Pass Rate）

**口径**：按渠道分组的申请量、通过量及通过率，关联维表获取渠道名称。

```sql
SELECT
    a.channel_id,
    c.channel_name,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) / NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS pass_rate
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
LEFT JOIN dim_channel c ON a.channel_id = c.channel_id
WHERE a.dt = '2024-01-01'
GROUP BY a.channel_id, c.channel_name
ORDER BY pass_rate DESC;
```

```
+--------------+----------------+-------------+------------+-------------+
| channel_id   | channel_name   |   apply_cnt |   pass_cnt |   pass_rate |
|--------------+----------------+-------------+------------+-------------|
| H5           | H5页面         |        1256 |        427 |       34    |
| WEB          | 网页端         |        1246 |        422 |       33.87 |
| APP          | 手机应用       |        1235 |        413 |       33.44 |
| API          | API接口        |        1263 |        417 |       33.02 |
+--------------+----------------+-------------+------------+-------------+
```

### 3.5 策略版本拒绝率（可选）

**口径**：各策略版本下的申请量及拒绝率，评估策略效果。

```sql
SELECT
    d.strategy_version,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) AS reject_cnt,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN d.decision = 'REJECT' THEN a.apply_id END) / NULLIF(COUNT(DISTINCT a.apply_id), 0), 2) AS reject_rate
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
WHERE a.dt = '2024-01-01'
GROUP BY d.strategy_version;
```

```
+--------------------+-------------+--------------+---------------+
| strategy_version   |   apply_cnt |   reject_cnt |   reject_rate |
|--------------------+-------------+--------------+---------------|
| v1.1               |        1672 |          561 |         33.55 |
| v2.0               |        1623 |          600 |         36.97 |
| v1.0               |        1705 |          526 |         30.85 |
+--------------------+-------------+--------------+---------------+
```

## 5. 口径与边界说明汇总

| 指标       | 口径要点                                                     |
| :--------- | :----------------------------------------------------------- |
| 申请量     | 基于 `dwd_apply_latest`，每个申请一条，`COUNT(*)` 即申请量。 |
| 通过量     | 关联 `dwd_decision_latest`，取 `decision = 'PASS'` 的去重申请数。 |
| 通过率     | 通过量 / 申请量 * 100，申请量为0时返回NULL。                 |
| 拒绝量     | 类似通过量，条件为 `decision = 'REJECT'`。                   |
| 渠道通过率 | 分组键为 `channel_id`，维表提供可读名称，NULL渠道归为“未知”。 |
| 策略拒绝率 | 分组键为 `strategy_version`，可评估不同策略的收紧程度。      |

## 6. 性能点

- 指标计算应尽量在一次扫描中完成，使用 CTE 提前聚合，避免重复读取。
- 关联维表时，维表较小，DuckDB 自动优化为哈希连接，性能良好。
- 日粒度指标建议先按 `dt` 过滤，减少数据量。
- 后续可物化为 DWS 汇总表，避免重复计算。

## 11. 思考题（可选）

- 如果某申请既有通过又有拒绝的决策记录（数据错误），`dwd_decision_latest` 按时间取最新能否解决？如何确保业务正确？
  → 能解决大部分情况，但最好在源头上避免此类错误；若无法避免，可增加数据质量监控，发现异常时告警。
- 在通过率计算中，分母是申请量，但分子是决策通过的申请量。如果某些申请尚未完成决策（如仍处于人工审核中），在计算当日通过率时应如何处理？
  → 可单独统计“待审核”状态，或只对已完成的决策计算通过率，并在报表中注明。
- 如何设计指标口径的版本管理？当口径发生变化时，如何向下兼容？
  → 在口径文档中记录变更日志，使用语义化版本（如 v1.0）；计算指标时可根据版本选择 SQL 逻辑，或通过视图封装，确保旧报表不受影响。