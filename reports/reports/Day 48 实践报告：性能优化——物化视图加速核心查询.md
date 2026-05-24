# Day 48 实践报告：性能优化——物化视图加速核心查询

## 1. 练习目标

- 理解物化视图在数据仓库中的作用：预先计算并存储复杂查询结果，提升查询性能。
- 学习在 DuckDB 中使用 `CREATE TABLE ... AS` 创建物化视图（模拟物化视图）。
- 针对高频查询创建物化视图，并对比查询性能。
- 设计物化视图的刷新策略（全量刷新），并集成到每日调度中。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库：`dev.duckdb`
- 项目路径：`C:\credit_risk_portfolio`
- 已有表：`dws_channel_daily`（渠道日报汇总表）、`dwd_apply_latest`、`dwd_decision_latest`

## 3. 核心任务执行

### 3.1 识别高频查询

选择项目中最常用的查询之一：按日期和渠道查询渠道日报（`dws_channel_daily`）。此查询在报表和监控中频繁使用。

### 3.2 创建物化视图

由于 `dws_channel_daily` 本身已经是汇总表，直接将其复制为物化视图 `mv_channel_daily`：

```sql
CREATE TABLE mv_channel_daily AS
SELECT * FROM dws_channel_daily;
```



为了展示物化视图对复杂查询的优化效果，还创建了一个针对用户历史行为特征的物化视图（模拟）：

```sql
CREATE TABLE mv_user_hist_30d AS
SELECT
    user_id,
    COUNT(*) AS apply_cnt_30d,
    AVG(amount) AS avg_amount_30d,
    AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_rate_30d
FROM dwd_apply_latest a
LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
WHERE a.dt BETWEEN (CURRENT_DATE - INTERVAL '30 days') AND (CURRENT_DATE - INTERVAL '1 day')
GROUP BY user_id;
```



### 3.3 性能对比测试

在 DuckDB CLI 中执行以下查询，并记录执行时间（`.timer on`）：

| 查询对象            | SQL                                                      | 执行时间 (秒) |
| :------------------ | :------------------------------------------------------- | :------------ |
| `dws_channel_daily` | `SELECT * FROM dws_channel_daily WHERE dt='2024-01-15';` | 0.077         |
| `mv_channel_daily`  | `SELECT * FROM mv_channel_daily WHERE dt='2024-01-15';`  | 0.046         |

**结果分析**：

- 物化视图查询性能提升约 **40%**（0.077s → 0.046s）。
- 由于 `dws_channel_daily` 已经是轻量级汇总表，性能提升有限。对于更复杂的查询（如用户历史特征计算），物化视图可带来数量级的提升（预估从 0.25s 降至 0.01s）。

### 3.4 设计刷新策略

由于物化视图依赖的基础表（`dwd_apply_latest`、`dws_channel_daily`）每日更新，物化视图也需要每日刷新。采用**全量刷新**策略（先删后建），简单可靠。

**刷新脚本 `sql/performance/refresh_mv.sql`**：

```sql
DROP TABLE IF EXISTS mv_channel_daily;
CREATE TABLE mv_channel_daily AS SELECT * FROM dws_channel_daily;

DROP TABLE IF EXISTS mv_user_hist_30d;
CREATE TABLE mv_user_hist_30d AS
SELECT ...（同上）;
```

### 3.5 集成到调度

在 `run_full_etl.py` 的末尾（所有 ETL 完成后）添加刷新物化视图的步骤：

```python
# 刷新物化视图
run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/performance/refresh_mv.sql', '--db', db])
```

### 3.6 性能对比报告与文档

- 生成 `reports/performance_mv.md`，记录测试结果。
- 创建 `docs/performance_tuning.md`，汇总所有性能优化策略（物化视图、分区裁剪、增量处理、列裁剪等）。

## 4. 遇到的问题与解决方案

| 问题                     | 原因             | 解决方案                                  |
| :----------------------- | :--------------- | :---------------------------------------- |
| 物化视图与源表数据不一致 | 刷新未集成到调度 | 在每日 ETL 最后自动刷新                   |
| 创建物化视图占用存储     | 全量复制数据     | 只对关键查询创建，DuckDB 列式存储压缩较好 |

## 5. 核心产出清单

- 物化视图 `mv_channel_daily` 和 `mv_user_hist_30d`
- 刷新脚本 `sql/performance/refresh_mv.sql`
- 性能对比报告 `reports/performance_mv.md`
- 性能调优文档 `docs/performance_tuning.md`
- 将物化视图刷新集成到 `run_full_etl.py`

## 6. 思考题

- 物化视图与普通视图的区别？何时使用物化视图？
  → 普通视图不存储数据，每次查询动态计算；物化视图存储结果，适合复杂、读多写少的场景。
- 如果基础表每天更新，如何保证物化视图新鲜度？
  → 每日 ETL 后全量刷新，或使用增量更新（复杂）。
- 物化视图占用存储，如何平衡性能与存储？
  → 只对最关键的查询创建，并定期清理不再使用的视图。