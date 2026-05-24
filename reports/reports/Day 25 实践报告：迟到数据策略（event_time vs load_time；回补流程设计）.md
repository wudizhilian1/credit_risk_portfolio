# Day 25 实践报告：迟到数据策略（event_time vs load_time；回补流程设计）

## 1. 练习目标

- 理解迟到数据的概念：数据实际发生时间（event_time）与数据加载时间（load_time）不一致的现象。
- 掌握识别和处理迟到数据的常用策略：分区覆盖、增量重算、延迟窗口。
- 设计针对风控场景的迟到数据处理流程，并编写相应的 SQL 示例。
- 明确口径：按事件日聚合 vs 按加载日聚合，以及如何应对业务查询需求。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 已有 ODS 表：`ods_apply`、`ods_decision`（已包含模拟迟到数据）
- 模拟迟到数据：

```sql
INSERT INTO ods_apply VALUES
('2024-01-01_999', 'user_999', 'APP', 5000.00, '2024-01-01 08:00:00', '2024-01-01 08:00:00', '2024-01-03');
INSERT INTO ods_decision VALUES
('2024-01-01_999', 'PASS', NULL, 'v1.0', '2024-01-01 08:30:00', '2024-01-03');
```

项目目录：

credit_risk_portfolio/
├── sql/
│   ├── late_data_identification.sql
│   └── hql/
│       └── day25_late_data_policy.sql
├── docs/
│   └── late_data_strategy.md
└── reports/
    └── day25_late_data.md

### 3.1 识别迟到数据

编写查询，找出加载日（`dt`）大于事件日（`apply_time` 的日期）的记录：

```sql
SELECT 
    apply_id,
    dt AS load_date,
    CAST(apply_time AS DATE) AS event_date,
    apply_time,
    dt > CAST(apply_time AS DATE) AS is_late
FROM ods_apply
WHERE dt > CAST(apply_time AS DATE);
```

```
+----------------+---------------------+---------------------+---------------------+-----------+
| apply_id       | load_date           | event_date          | apply_time          | is_late   |
|----------------+---------------------+---------------------+---------------------+-----------|
| 2024-01-01_999 | 2024-01-03 00:00:00 | 2024-01-01 00:00:00 | 2024-01-01 08:00:00 | True      |
+----------------+---------------------+---------------------+---------------------+-----------+
```

### 3.2 按加载日 vs 按事件日统计对比

比较按加载日（常规报表）与按事件日（正确口径）统计的申请量差异：

```sql
SELECT
    'load' AS type,
    ANY_VALUE(dt) AS date,
    COUNT(*) AS cnt
FROM ods_apply WHERE dt = '2024-01-01'

UNION ALL

SELECT
    'event',
    ANY_VALUE(CAST(apply_time AS DATE)) AS date,
    COUNT(*)
FROM ods_apply
WHERE CAST(apply_time AS DATE) = '2024-01-01';
```



**执行结果**：

```
+--------+---------------------+-------+
| type   | date                |   cnt |
|--------+---------------------+-------|
| load   | 2024-01-01 00:00:00 |  5000 |
| event  | 2024-01-01 00:00:00 |  5001 |
+--------+---------------------+-------+
```

**分析**：按事件日统计比按加载日多 1 条，因为迟到的记录（2024-01-01_999）虽然加载在 2024-01-03，但事件日属于 2024-01-01，因此正确口径应计入 2024-01-01。

### 3.3 创建事件日分区表

为支持按事件日统计，创建 DWD 层按事件日分区的表：

```sql
CREATE TABLE IF NOT EXISTS dwd_apply_by_event (
    apply_id          VARCHAR NOT NULL,
    user_id           VARCHAR NOT NULL,
    channel_id        VARCHAR,
    amount            DECIMAL(18,2),
    apply_time        TIMESTAMP,
    update_time       TIMESTAMP,
    event_date        DATE NOT NULL
);
```

### 3.4 将 ODS 数据按事件日加载到 DWD 表

全量刷新（适用于小数据量）：

```sql
-- 清空并重新加载
DELETE FROM dwd_apply_by_event;

INSERT INTO dwd_apply_by_event (apply_id, user_id, channel_id, amount, apply_time, update_time, event_date)
SELECT 
    apply_id, user_id, channel_id, amount, apply_time, update_time,
    CAST(apply_time AS DATE) AS event_date
FROM ods_apply;
```

验证数据：

```sql
SELECT event_date, COUNT(*) FROM dwd_apply_by_event GROUP BY event_date ORDER BY event_date;
```

```
+---------------------+-------------+
| event_date          |   cnt_event |
|---------------------+-------------|
| 2024-01-01 00:00:00 |        5001 |
| 2024-01-02 00:00:00 |        5000 |
| 2024-01-03 00:00:00 |        5000 |
| 2024-01-04 00:00:00 |        5000 |
| 2024-01-05 00:00:00 |        5000 |
| 2024-01-06 00:00:00 |        5000 |
| 2024-01-07 00:00:00 |        5000 |
| 2024-01-08 00:00:00 |        5000 |
| 2024-01-09 00:00:00 |        5000 |
| 2024-01-10 00:00:00 |        5000 |
| 2024-01-11 00:00:00 |        5000 |
| 2024-01-12 00:00:00 |        5000 |
| 2024-01-13 00:00:00 |        5000 |
| 2024-01-14 00:00:00 |        5000 |
| 2024-01-15 00:00:00 |        5000 |
| 2024-01-16 00:00:00 |        5000 |
| 2024-01-17 00:00:00 |        5000 |
| 2024-01-18 00:00:00 |        5000 |
| 2024-01-19 00:00:00 |        5000 |
| 2024-01-20 00:00:00 |        5000 |
+---------------------+-------------+
```

### 3.5 编写迟到数据策略文档

创建 `docs/late_data_strategy.md`

## 4. 口径与边界说明

| 要素         | 说明                                                         |
| :----------- | :----------------------------------------------------------- |
| **事件日**   | 取自 `apply_time` 的日期部分，用于业务统计。                 |
| **加载日**   | 数据入库时的日期分区，用于 ETL 调度和回溯。                  |
| **迟到判定** | `dt > event_date` 视为迟到，反之正常。                       |
| **处理方式** | 保持 ODS 按加载日分区；DWD 按事件日重新组织；DWS 按事件日聚合，支持重算。 |
| **幂等性**   | 重算时先删除该事件日的旧数据，再插入新数据，保证多次执行结果一致。 |

## 5. 性能点

- 按事件日分区可优化按日期过滤的查询。
- 增量处理迟到数据时，应只扫描最近 N 天的 ODS 分区，避免全表扫描。
- 重算 DWS 时，如果数据量大，可只针对有迟到的日期，而不是全部重算。

## 10. 思考题

- 如果某条数据迟到超过 30 天，应如何处理？
  → 应标记为异常并告警，业务上可能需要重跑历史数据，或与源系统确认数据有效性。
- 按事件日统计的指标在实时性要求高的场景（如风控监控）中如何保证？
  → 需使用事件日 + 加载时间戳，并容忍一定延迟，或采用 Lambda 架构（实时+离线）。
- 如何设计自动化调度来检测迟到数据并触发回补？
  → 每日扫描 ODS 最近 N 天分区，记录 `dt > event_date` 的记录，并通知下游 DWS 重算受影响日期。