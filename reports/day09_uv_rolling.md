# Day 9 实践报告：UV 去重口径与 7 天滚动 UV 计算

## 1. 练习目标
- 理解 UV（独立用户数）在风控/数仓场景中的定义与计算方法。
- 掌握 `COUNT(DISTINCT user_id)` 的基本用法，明确口径边界。
- 学习计算 **7 天滚动 UV** 的 SQL 实现（关联子查询）。
- 通过 `EXPLAIN` 观察去重操作的执行计划，思考性能优化。

## 2. 实验环境
- DuckDB 版本：0.x.x
- 数据路径：`data/raw/apply/` 按 `dt` 分区（3 个分区：2024-01-01, 2024-01-02, 2024-01-03）
- 视图：`v_apply`（基于分区 Parquet 文件创建，`hive_partitioning=1`）
- 数据规模：每天约 5,000 条申请记录，用户 ID 随机，存在同一用户同一天多次申请的情况。

## 3. UV 去重口径与边界

| 口径要素       | 说明                                                         |
| -------------- | ------------------------------------------------------------ |
| **UV 定义**    | 独立用户数，按 `user_id` 去重统计。                          |
| **去重粒度**   | 按天（`dt`）统计；如需跨天滚动则另行定义。                   |
| **空值处理**   | `user_id` 为 NULL 的记录不计入 UV（业务上通常不会发生，但需在文档中声明）。 |
| **跨渠道处理** | 同一用户在不同渠道的申请，在按渠道统计 UV 时分别计入各渠道；在整体 UV 中只计一次。 |
| **时间口径**   | 以申请时间 `apply_time` 所在的日期 `dt` 为准。               |
| **边界案例**   | 若同一天同一用户多次申请，UV 仍为 1；若需统计“活跃用户数”，通常也采用此口径。 |

**性能建议**：UV 计算时应先在事实表过滤所需日期、只选择必要的列（`user_id`、`channel_id`、`dt`）后再去重，避免携带大宽表增加 I/O 开销。

## 4. 基本 UV 计算 SQL 与结果

### 4.1 整体 UV（按天）
```sql
-- 计算 2024-01-01 这一天的独立用户数
SELECT COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01';
```

```
+------+
|   uv |
|------|
| 1835 |
+------+
```

```sql
--按渠道统计 UV
SELECT 
    channel_id,
    COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01'
GROUP BY channel_id
ORDER BY uv DESC;
```

```
+--------------+------+
| channel_id   |   uv |
|--------------+------|
| WEB          |  930 |
| APP          |  923 |
| API          |  918 |
| H5           |  916 |
```

```sql
-- 总申请数 vs UV
SELECT 
    COUNT(*) AS total_applies,
    COUNT(DISTINCT user_id) AS uv
FROM v_apply
WHERE dt = '2024-01-01';
```

```
+-----------------+------+
|   total_applies |   uv |
|-----------------+------|
|            5000 | 1835 |
+-----------------+------+
```

```sql
--统计“7天滚动 UV”
WITH dates AS (
    SELECT DISTINCT dt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
)
SELECT
    d.dt,
    (SELECT COUNT(DISTINCT user_id)
     FROM v_apply
     WHERE dt BETWEEN d.dt - 6 AND d.dt) AS rolling_uv_7d
FROM dates d
ORDER BY d.dt;
```

```
+---------------------+-----------------+
| dt                  |   rolling_uv_7d |
|---------------------+-----------------|
| 2024-01-01 00:00:00 |            1835 |
| 2024-01-02 00:00:00 |            1982 |
| 2024-01-03 00:00:00 |            1998 |
+---------------------+-----------------+
```

## 5. 性能优化思考

- **预聚合每日活跃用户**：若频繁计算滚动 UV，可先构建每日用户列表表（`daily_active_users`：`dt, user_id` 去重），再基于该表进行关联子查询，避免扫描原始大表。
- **使用近似算法**：对于超大规模数据，可采用 HyperLogLog 近似基数估算，DuckDB 提供 `APPROX_COUNT_DISTINCT`，但滚动窗口仍需类似子查询。
- **分区裁剪与列裁剪**：始终在查询中指定日期范围，并只 SELECT 必要列，可大幅减少 I/O。