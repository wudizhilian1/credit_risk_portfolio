# Day 10 实践报告：风控漏斗分析（申请→决策→通过）

## 1. 练习目标
- 理解漏斗分析在风控业务中的意义：监控各环节转化率，定位流失环节。
- 掌握使用 `CASE WHEN` + 聚合计算转化率的 SQL 方法。
- 明确各步骤的口径边界（时间窗口、去重规则、事件顺序）。
- 练习带时间窗口的漏斗（7 天内转化）编写与调试。
- 通过 `EXPLAIN` 观察执行计划，思考性能优化。

## 2. 实验环境
- DuckDB 版本：0.x.x
- 数据路径：`data/raw/apply/` 和 `data/raw/decision/` 按 `dt` 分区（3 个分区：2024-01-01, 2024-01-02, 2024-01-03）
- 视图：
  - `v_apply`：包含 `apply_id`, `user_id`, `channel_id`, `amount`, `apply_time`(VARCHAR), `update_time`, `dt`
  - `v_decision`：包含 `apply_id`, `decision`, `reject_reason`, `strategy_version`, `decision_time`(VARCHAR), `dt`
- 数据规模：每天约 5,000 条申请，决策表与申请表通过 `apply_id` 关联（可能存在 1:0..n）。

## 3. 核心 SQL 及结果

### 3.1 基础漏斗（按天，不带时间窗口）
```sql
WITH
apply_tbl AS (
    SELECT apply_id, channel_id
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_tbl AS (
    SELECT apply_id, decision
    FROM v_decision
    WHERE dt = '2024-01-01'
)
SELECT
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT d.apply_id) AS decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS pass_cnt
FROM apply_tbl a
LEFT JOIN decision_tbl d ON a.apply_id = d.apply_id;
```

```
+-------------------+----------------------+------------------+------------------+
|   step1_apply_cnt |   step2_decision_cnt |   step3_pass_cnt |   step4_loan_cnt |
|-------------------+----------------------+------------------+------------------|
|              5000 |                 5000 |             1665 |             1665 |
+-------------------+----------------------+------------------+------------------+
```

```sql
--在上一步基础上增加比率计算：
WITH
apply_tbl AS (
    SELECT apply_id
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_tbl AS (
    SELECT apply_id, decision
    FROM v_decision
    WHERE dt = '2024-01-01'
),
base AS (
    SELECT
        COUNT(DISTINCT a.apply_id) AS step1,
        COUNT(DISTINCT d.apply_id) AS step2,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS step3
    FROM apply_tbl a
    LEFT JOIN decision_tbl d ON a.apply_id = d.apply_id
)
SELECT
    step1,
    step2,
    step3,
    ROUND(100.0 * step2 / step1, 2) AS pct_apply_to_decision,
    ROUND(100.0 * step3 / step2, 2) AS pct_decision_to_pass,
    ROUND(100.0 * step3 / step1, 2) AS pct_apply_to_pass
FROM base;
```

```
+---------+---------+---------+-------------------------+------------------------+---------------------+
|   step1 |   step2 |   step3 |   pct_apply_to_decision |   pct_decision_to_pass |   pct_apply_to_pass |
|---------+---------+---------+-------------------------+------------------------+---------------------|
|    5000 |    5000 |    1665 |                     100 |                   33.3 |                33.3 |
+---------+---------+---------+-------------------------+------------------------+---------------------+
```

```sql
--分渠道漏斗
SELECT
    a.channel_id,
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT d.apply_id) AS decision_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN d.apply_id END) AS pass_cnt
FROM v_apply a
LEFT JOIN v_decision d ON a.apply_id = d.apply_id AND d.dt = a.dt  -- 注意关联日期一致
WHERE a.dt = '2024-01-01'
GROUP BY a.channel_id
ORDER BY apply_cnt DESC;
```

```
+--------------+-------------+----------------+------------+
| channel_id   |   apply_cnt |   decision_cnt |   pass_cnt |
|--------------+-------------+----------------+------------|
| WEB          |        1273 |           1273 |        418 |
| APP          |        1253 |           1253 |        396 |
| API          |        1251 |           1251 |        419 |
| H5           |        1223 |           1223 |        432 |
+--------------+-------------+----------------+------------+
```

```sql
--带时间窗口的漏斗
WITH
apply_ts AS (
    SELECT apply_id, channel_id, dt, apply_time::TIMESTAMP AS apply_ts
    FROM v_apply
    WHERE dt = '2024-01-01'
),
decision_ts AS (
    SELECT apply_id, decision, decision_time::TIMESTAMP AS decision_ts
    FROM v_decision
    WHERE dt = '2024-01-01'
)
SELECT
    COUNT(DISTINCT a.apply_id) AS apply_cnt,
    COUNT(DISTINCT CASE WHEN d.decision_ts <= a.apply_ts + INTERVAL '7 days' THEN d.apply_id END) AS decision_in_7d_cnt,
    COUNT(DISTINCT CASE WHEN d.decision = 'PASS' AND d.decision_ts <= a.apply_ts + INTERVAL '7 days' THEN d.apply_id END) AS pass_in_7d_cnt
FROM apply_ts a
LEFT JOIN decision_ts d ON a.apply_id = d.apply_id;
```

```
+-------------+----------------------+------------------+
|   apply_cnt |   decision_in_7d_cnt |   pass_in_7d_cnt |
|-------------+----------------------+------------------|
|        5000 |                 5000 |             1665 |
+-------------+----------------------+------------------+
```

**说明**：`::TIMESTAMP` 是 DuckDB 的类型转换语法，也可用 `CAST(apply_time AS TIMESTAMP)`。转换后即可正常进行时间运算。

## 4. 口径与边界说明

| 口径要素       | 说明                                                         |
| :------------- | :----------------------------------------------------------- |
| **申请数**     | 按 `apply_id` 去重后的申请单数。同一用户多次申请分别计数。   |
| **决策完成数** | 与申请关联且存在决策记录的申请单数（不论决策结果）。若同一申请有多次决策，应取最新或按需去重（本练习简化未处理）。 |
| **通过数**     | 最终决策为 `PASS` 的申请单数。若存在多次决策，需定义取最终决策（如 `decision_time` 最新）。 |
| **时间窗口**   | 以申请时间 `apply_time` 为起点，计算 7 天内完成的决策。时间比较要求双方类型一致（均为 `TIMESTAMP`）。 |
| **关联关系**   | 申请与决策为 1:0..n，`LEFT JOIN` 保留所有申请。若决策表有重复，需先在子查询中按 `apply_id` 去重（例如取 `decision_time` 最新）。 |
| **空值处理**   | 决策表中无对应记录的申请，决策相关字段计为 0；`decision` 为 NULL 时不影响计数（因 `CASE` 中条件不成立）。 |

## 5. 性能点

- **分区裁剪**：查询中指定 `dt = '2024-01-01'`，确保只扫描对应分区，通过 `EXPLAIN` 可验证。
- **列裁剪**：只需 `apply_id`, `channel_id`, `decision`, `decision_time` 等字段，避免读取大字段（如 `amount`）。
- **类型转换开销**：频繁的类型转换可能增加 CPU 消耗，建议在数据生成阶段将时间字段存为 `TIMESTAMP`。
- **去重前置**：若决策表有重复记录，应先在子查询中按 `apply_id` 去重（如 `ROW_NUMBER()` 取最新），再与申请表关联，避免 `JOIN` 后行数膨胀。