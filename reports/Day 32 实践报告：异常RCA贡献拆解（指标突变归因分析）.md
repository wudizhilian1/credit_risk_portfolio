# Day 32 实践报告：异常RCA贡献拆解（指标突变归因分析）

## 1. 练习目标

- 理解 **根因分析（RCA, Root Cause Analysis）** 在风控指标监控中的重要性：当核心指标（如通过率、申请量）发生异常波动时，快速定位是哪个维度（渠道、策略版本、拒绝原因等）导致的。
- 掌握使用 **贡献度拆解** 的方法，量化各维度对指标变化的贡献，输出TopN贡献项。
- 编写 SQL 实现指标突变的维度贡献计算，并抽取样本记录辅助验证。
- 为后续自动化监控告警和归因分析提供基础逻辑。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWD 表：

  - `dwd_apply_latest`（申请明细，含 `apply_id`, `channel_id`, `user_id`, `amount`, `dt`）
  - `dwd_decision_latest`（决策明细，含 `apply_id`, `decision`, `reject_reason`, `strategy_version`, `dt`）

- 数据时间范围：2024-01-01 至 2024-01-30（含 Day20 制造的异常场景，如 2024-01-20 通过率突降）

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── rca/
  │       ├── apply_rate_change_contrib.sql
  │       └── reason_contrib_channel.sql
  ├── docs/
  └── reports/
      └── day32_rca.md
  ```

  

## 3. 核心任务执行

### 3.1 定义异常指标与对比周期

选择异常日 `2024-01-20`（通过率较前一周同期显著下降），对比基准日 `2024-01-13`（上周同期）。

通过率变化 = 当前日通过率 - 基准日通过率（百分点）。

### 3.2 渠道维度贡献拆解（SQL修正版）

**文件：`sql/rca/apply_rate_change_contrib.sql`**

```sql
WITH
curr AS (
    SELECT 
        a.channel_id,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END ) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-20'
    GROUP BY a.channel_id
),
curr_total AS (
    SELECT SUM(apply_cnt) AS total_apply FROM curr
),
curr_rate AS (
    SELECT 
        channel_id,
        apply_cnt,
        pass_cnt,
        ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) as pass_rate,
        ROUND(100.0 * apply_cnt / (SELECT total_apply FROM curr_total), 4) AS apply_weight
    FROM curr
),
base AS (
    SELECT
        a.channel_id,
        COUNT(DISTINCT a.apply_id) AS apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) AS pass_cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '2024-01-13'
    GROUP BY a.channel_id
),
base_total AS (
    SELECT SUM(apply_cnt) AS total_apply FROM base
),
base_rate AS (
    SELECT
        channel_id,
        apply_cnt,
        pass_cnt,
        ROUND(100.0 * pass_cnt / NULLIF(apply_cnt, 0), 2) AS pass_rate,
        ROUND(100.0 * apply_cnt / (SELECT total_apply FROM base_total), 4) AS apply_weight
    FROM base
)
SELECT
    COALESCE(c.channel_id, b.channel_id) AS channel_id,
    COALESCE(c.apply_cnt, 0) AS curr_apply,
    COALESCE(b.apply_cnt, 0) AS base_apply,
    COALESCE(c.pass_rate, 0) AS curr_rate,
    COALESCE(b.pass_rate, 0) AS base_rate,
    COALESCE(c.pass_rate, 0) - COALESCE(b.pass_rate, 0) AS rate_diff,
    COALESCE(c.apply_weight, 0) AS curr_weight,
    COALESCE(b.apply_weight, 0) AS base_weight,
     ROUND((COALESCE(c.pass_rate, 0) * COALESCE(c.apply_weight, 0) -
         COALESCE(b.pass_rate, 0) * COALESCE(b.apply_weight, 0)) / 100.0, 4) AS contrib
FROM curr_rate c
FULL OUTER JOIN base_rate b ON c.channel_id = b.channel_id
ORDER BY ABS(contrib) DESC
LIMIT 10;
```

**执行命令**：

```bash
python scripts/run_sql.py --sql sql/rca/apply_rate_change_contrib.sql --vars dt=2024-01-20 dt_baseline=2024-01-13 --out reports/rca_channel_2024-01-20.md
```

```
+--------------+--------------+--------------+-------------+-------------+-------------+---------------+---------------+-----------+
| channel_id   |   curr_apply |   base_apply |   curr_rate |   base_rate |   rate_diff |   curr_weight |   base_weight |   contrib |
|--------------+--------------+--------------+-------------+-------------+-------------+---------------+---------------+-----------|
| H5           |         1232 |         1261 |       32.31 |       35.05 |       -2.74 |         24.64 |         25.22 |   -0.8784 |
| WEB          |         1160 |         1222 |       32.5  |       32.82 |       -0.32 |         23.2  |         24.44 |   -0.4812 |
| API          |         1370 |         1292 |       31.9  |       35.45 |       -3.55 |         27.4  |         25.84 |   -0.4197 |
| APP          |         1238 |         1225 |       32.15 |       31.59 |        0.56 |         24.76 |         24.5  |    0.2208 |
+--------------+--------------+--------------+-------------+-------------+-------------+---------------+---------------+-----------+
```

### 3.3 针对渠道 'WEB' 的拒绝原因贡献拆解（修正版）

**文件：`sql/rca/reason_contrib_channel.sql`**

sql

```
WITH curr_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '{{dt}}' AND a.channel_id = 'WEB' AND d.decision = 'REJECT'
    GROUP BY d.reject_reason
),
base_reason AS (
    SELECT
        COALESCE(d.reject_reason, 'UNKNOWN') AS reason,
        COUNT(*) AS cnt
    FROM dwd_apply_latest a
    LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
    WHERE a.dt = '{{dt_baseline}}' AND a.channel_id = 'WEB' AND d.decision = 'REJECT'
    GROUP BY d.reject_reason
),
total_curr AS (SELECT SUM(cnt) AS total FROM curr_reason),
total_base AS (SELECT SUM(cnt) AS total FROM base_reason)
SELECT
    COALESCE(c.reason, b.reason) AS reason,
    COALESCE(c.cnt, 0) AS curr_cnt,
    COALESCE(b.cnt, 0) AS base_cnt,
    tc.total AS total_curr,
    tb.total AS total_base,
    ROUND(100.0 * COALESCE(c.cnt, 0) / NULLIF(tc.total, 0), 2) AS curr_pct,
    ROUND(100.0 * COALESCE(b.cnt, 0) / NULLIF(tb.total, 0), 2) AS base_pct,
    ROUND(100.0 * COALESCE(c.cnt, 0) / NULLIF(tc.total, 0) -
          100.0 * COALESCE(b.cnt, 0) / NULLIF(tb.total, 0), 2) AS diff_pct
FROM curr_reason c
FULL OUTER JOIN base_reason b ON c.reason = b.reason
CROSS JOIN total_curr tc
CROSS JOIN total_base tb
ORDER BY ABS(diff_pct) DESC
LIMIT 10;
```

**执行命令**：

```bash
python scripts/run_sql.py --sql sql/rca/reason_contrib_channel.sql --vars dt=2024-01-20 dt_baseline=2024-01-13 --out reports/rca_web_reason_2024-01-20.md
```

**输出示例**：

```
+------------+------------+------------+------------+------------+------------+
| reason     |   curr_cnt |   base_cnt |   curr_pct |   base_pct |   diff_pct |
|------------+------------+------------+------------+------------+------------|
| UNKNOWN    |        107 |         70 |      25.06 |      18.09 |       6.97 |
| RISK_SCORE |         73 |         79 |      17.1  |      20.41 |      -3.32 |
| BLACKLIST  |         74 |         76 |      17.33 |      19.64 |      -2.31 |
| FRAUD      |         84 |         84 |      19.67 |      21.71 |      -2.03 |
| OVER_LIMIT |         89 |         78 |      20.84 |      20.16 |       0.69 |
+------------+------------+------------+------------+------------+------------+
```

### 3.4 样本钻取

抽取贡献最大的渠道和拒绝原因对应的样本申请：

```sql
SELECT a.apply_id, a.user_id, a.amount, d.reject_reason
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id AND a.dt = d.dt
WHERE a.dt = '2024-01-20' AND a.channel_id = 'WEB' AND d.reject_reason = 'RISK_SCORE'
LIMIT 10;
```

## 4. 口径与边界说明

| 要素         | 说明                                                         |
| :----------- | :----------------------------------------------------------- |
| **对比周期** | 选择上周同期（避免星期几效应），通过参数 `dt` 和 `dt_baseline` 传入。 |
| **贡献计算** | 贡献分近似为 `(curr_rate * curr_weight - base_rate * base_weight) / 100`，单位为百分点，用于量化各维度对总通过率变化的贡献。 |
| **维度选择** | 首先从最粗粒度（渠道）拆解，找到主要贡献维度后，再钻取到更细粒度（拒绝原因）。 |
| **空值处理** | 使用 `COALESCE` 将 NULL 转换为 0，`NULLIF` 防止除零错误。    |
| **样本抽取** | 抽取贡献维度下的异常样本，用于人工验证。                     |

## 5. 性能点

- 拆解查询涉及两日数据，在 `dt` 字段上过滤，利用分区裁剪，扫描量可控。
- 通过 `WITH` 子句先聚合，再关联，避免在明细层全表扫描。
- 钻取查询仅针对单一渠道和日期，性能良好。

## 10. 思考题

- 如果总通过率下降，但各渠道通过率均上升，可能是什么原因？（渠道结构变化，低通过率渠道申请量占比增加。）
- 如何区分是由于渠道内部通过率变化还是渠道流量变化导致的贡献？（通过贡献分解公式可分离两部分：`(curr_rate - base_rate) * base_weight` 和 `(curr_weight - base_weight) * base_rate` 等。）
- 对于多维度联合拆解，维度爆炸时如何优先选择？（可先粗粒度，再根据贡献最大的维度下钻。）