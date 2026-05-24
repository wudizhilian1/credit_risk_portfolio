# 第四天练习hql

## 要求

每天通过率最高的 3 个渠道（窗口函数 + 分区排序）

## 答案

```sql
WITH d_latest AS (
  SELECT apply_id, decision, decision_time
  FROM (
    SELECT
      apply_id,
      decision,
      decision_time,
      row_number() OVER (
        PARTITION BY apply_id
        ORDER BY decision_time DESC
      ) AS rn
    FROM decision
    WHERE apply_id IS NOT NULL
  ) t
  WHERE rn = 1
)
SELECT
  a.channel AS channel,
  COUNT(*) AS apply_count,
  COUNT(*) FILTER (WHERE d_latest.decision = 'approve') AS pass_count,
  COUNT(*) FILTER (WHERE d_latest.decision = 'approve')::DOUBLE / NULLIF(COUNT(*), 0) AS pass_rate
FROM apply a
LEFT JOIN d_latest
  ON a.apply_id = d_latest.apply_id
GROUP BY 1
ORDER BY pass_rate desc
limit 3
;
```

## 口径和边界

### 数据范围口径

**口径**：统计范围为 `dt = date(apply_time)` 当天产生的申请；仅统计 `apply_time` 在 [开始日, 结束日] 范围内的数据。
**边界**：`apply_time` 为空 → 该行无法归属 dt，**丢弃**并记录占比。
**校验 SQL（示例）**：

- `apply_time` 为空占比：`count_if(apply_time is null) / count(*)`

### 主键与去重口径

**口径**：`apply` 去重规则：以 `apply_id` 为主键；同一 `apply_id` 取 `update_time` 最新的一条作为“最终状态”。
**边界A**：`update_time` 为空 → 该 `apply_id` 无法比较新旧：

- 处理：将 `update_time` 为空的记录排到最末（视为最旧），仍保留一条；并记录该类占比。
   **边界B**：同一 `apply_id` 出现多个 `update_time` 完全相同 →
- 处理：增加稳定 tie-break（例如 `order by update_time desc, ingest_time desc` 或 `order by update_time desc, row_id desc`），否则“随机取”。记录冲突率。
   **校验 SQL（示例）**：
- 去重前重复率：`count(*) - count(distinct apply_id)`
- `update_time is null` 占比：`count_if(update_time is null) / count(*)`
- `apply_id` 为空占比：`count_if(apply_id is null) / count(*)`

> 这条和你 Day1 的“apply 去重=按 apply_id 取 update_time 最新”是一致的，只是 Day4 把 tie-break 和空值处理写清楚了。

```sql
WITH d_latest AS (
  SELECT apply_id, decision, decision_time
  FROM (
    SELECT
      apply_id,
      decision,
      decision_time,
      row_number() OVER (
        PARTITION BY apply_id
        ORDER BY decision_time DESC
      ) AS rn
    FROM decision
    WHERE apply_id IS NOT NULL
  ) t
  WHERE rn = 1
)
SELECT
  a.channel AS channel,
  COUNT(*) AS apply_count,
  COUNT(*) FILTER (WHERE d_latest.decision = 'approve') AS pass_count,
  COUNT(*) FILTER (WHERE d_latest.decision = 'approve')::DOUBLE / NULLIF(COUNT(*), 0) AS pass_rate
FROM apply a
LEFT JOIN d_latest
  ON a.apply_id = d_latest.apply_id
GROUP BY 1
ORDER BY 1
```



### 决策表 decision 关联口径

**口径**：`decision` 与 `apply` 按 `apply_id` 左连接；用于计算“审批通过/拒绝/未决”。
**边界A**：同一 `apply_id` 在 decision 多条（多次决策） →

- 处理：以 `decision_time` 最新为准；若 `decision_time` 相同，用 `update_time/ingest_time/row_id` 打散。
   **边界B**：左连接后 `decision` 为空 →
- 解释：表示“未产生决策或数据缺失”，在指标里单独记为 `pending/unknown`，不混入拒绝。
   **校验 SQL（示例）**：
- decision 多条比例：`count(*) - count(distinct apply_id)`（在 decision 表里）
- join 后 decision 为空比例：`count_if(d.decision is null) / count(*)`

### 通过率指标口径

**口径**：

- `apply_cnt`：去重后的申请数（distinct apply_id after dedup）
- `pass_cnt`：去重后且最终 `decision='PASS'` 的数量
- `pass_rate`：`pass_cnt / apply_cnt`（分母为 0 时返回 null 或 0，需明确）
   **边界**：若存在 `decision` 值不在 {PASS, REJECT}
- 处理：统一映射为 `OTHER` 或 `UNKNOWN`，并记录占比；避免污染通过率。
   **校验 SQL（示例）**：
- 异常枚举：`select decision, count(*) group by decision`

### 分渠道 channel 口径（如果你今天做渠道 TopN）

**口径**：渠道取 `apply.channel`；若为空归类为 `'UNKNOWN'`。
 **边界**：同一 `apply_id` 不同记录的 `channel` 变化 →

- 处理：以去重后“最终记录”的 channel 为准。
   **校验 SQL**：`count_if(channel is null) / count(*)`

## 性能点

**性能点**：去重使用窗口函数 `row_number() over(partition by apply_id order by update_time desc)` 会触发排序/重分布；在大数据场景应先做**时间范围过滤（按 dt 分区）**、**列裁剪（只取 apply_id/update_time 等必要字段）**，再去重与 join，以减少排序数据量与 join 代价。

# 第五天hql练习

## 要求

计算每个渠道（channel）的申请通过率

## 语句

SELECT channel, 
       COUNT(*) AS apply_count,
       COUNT(DISTINCT CASE WHEN decision = 'approve' THEN apply.apply_id END) AS passed_applications,
       COUNT(DISTINCT CASE WHEN decision = 'approve' THEN apply.apply_id END) * 1.0 / COUNT(DISTINCT apply.apply_id) AS pass_rate
FROM apply
LEFT JOIN decision ON apply.apply_id = decision.apply_id
GROUP BY channel;

## 要求

#计算申请通过率的年度和月度趋势，注意空值处理

## 语句

```sql
SELECT EXTRACT(YEAR FROM COALESCE(apply_time, '1970-01-01')) AS year,
       EXTRACT(MONTH FROM COALESCE(apply_time, '1970-01-01')) AS month,
       COUNT(DISTINCT apply.apply_id) AS total_applications,
       COUNT(DISTINCT CASE WHEN decision = 'approve' AND apply.apply_id IS NOT NULL THEN apply.apply_id END) AS passed_applications,
       COUNT(DISTINCT CASE WHEN decision = 'approve' AND apply.apply_id IS NOT NULL THEN apply.apply_id END) * 1.0 / 
       COUNT(DISTINCT CASE WHEN apply.apply_id IS NOT NULL THEN apply.apply_id END) AS pass_rate
FROM apply
LEFT JOIN decision ON apply.apply_id = decision.apply_id
GROUP BY year, month
ORDER BY year, month;
```

### **Day 5 口径与边界**

------

#### **1. 数据范围口径**

**口径**：

- 统计范围为 `dt = date(apply_time)`，即只统计 `apply_time` 在 [开始日, 结束日] 范围内的数据。
  **边界**：
- `apply_time` 为空 → 丢弃该行数据，并记录占比。
- 如果 `apply_time` 无效（如格式错误） → 丢弃该行数据，并记录占比。

------

#### **2. 主键与去重口径**

**口径**：

- `apply` 去重规则：以 `apply_id` 为主键，取 `update_time` 最新的一条记录作为“最终状态”。
  **边界**：
- `update_time` 为空 → 该行 `apply_id` 无法比较新旧；将 `update_time` 为空的记录视为最旧记录，保留一条。并记录该类数据的占比。
- `update_time` 相同的记录 → 使用其他字段（如 `ingest_time`、`row_id`）打破平局，保留最“新”的记录。

------

#### **3. 决策表 `decision` 关联口径**

**口径**：

- `decision` 按 `apply_id` 左连接到 `apply` 表，计算“审批通过”与“拒绝”情况。
  **边界**：
- 同一 `apply_id` 出现多个 `decision` 状态 → 取 `decision_time` 最新的记录。如果 `decision_time` 相同，用 `update_time` 或 `ingest_time` 打破平局。
- `decision` 为 NULL 代表“未决策”或“数据缺失”，在分析中作为 `pending/unknown` 处理，不影响通过率。

------

#### **4. 通过率指标口径**

**口径**：

- `apply_cnt`：去重后的申请数（distinct apply_id after dedup）。
- `pass_cnt`：最终 `decision = 'PASS'` 的数量。
- `pass_rate`：`pass_cnt / apply_cnt`（分母为 0 时返回 null 或 0，需明确）。
  **边界**：
- `decision` 其他值（非 `PASS` 或 `REJECT`）统一标记为 `OTHER`，并记录占比。
- `decision` 异常值需归类为 `UNKNOWN`，并标记在数据报告中。

------

#### **5. 分渠道 `channel` 口径**

**口径**：

- `channel` 为空的记录，统一归类为 `UNKNOWN`。
  **边界**：
- `apply_id` 在不同记录中有不同的 `channel` 值时，保留 `channel` 最后一条记录（按 `update_time` 最新）。
- 对于多次申请的用户，保证 `channel` 取**最终状态**（而不是最初状态）。

------

#### **6. 性能优化点（窗口函数）**

**性能点**：

- 使用窗口函数时，避免全表扫描/排序。如果表数据量较大，使用 **列裁剪**，确保只选择需要的字段。
- 对 `apply_id` 和 `decision_time` 进行 **分区排序**，减少全表排序的开销。
- 在使用 `window function` 时，尽量增加时间范围的限制（如 `WHERE apply_time BETWEEN start_date AND end_date`），减少无关数据的计算。

# 第六天口径与边界

### **Day 6 口径与边界（可执行标准）**

#### **1）数据提取口径与边界**

- **口径**：数据提取的源为 **CSV 文件** 或 **Parquet 文件**，每次导入数据时确保 **文件格式** 正确（CSV 格式应包含表头，Parquet 格式应满足结构化要求）。
  - 数据表的字段 **apply_id, update_time, amount, channel** 必须存在。
  - 提取后的数据将按 **`apply_id`** 进行 **去重**，取 **`update_time`** 最新的一条。
- **边界**：
  - **空值处理**：如果数据源中 `apply_id` 或 `update_time` 为 `NULL`，则该行数据 **丢弃**，并记录丢失数据占比。
  - **重复数据处理**：对于 `apply_id` 相同但 `update_time` 相同的数据，取最新的记录，或根据业务需求使用 `row_number()` 来做排序后去重。
  - **字段缺失**：如果 CSV 文件中缺少某个字段（例如：`apply_id` 或 `update_time`），则应跳过该文件，并记录该类问题的文件路径及错误信息。

**校验 SQL**：

```sql
-- 统计缺失 apply_id 或 update_time 的行数
SELECT COUNT(*) 
FROM apply 
WHERE apply_id IS NULL OR update_time IS NULL;
```

------

#### **2）数据去重与关联口径**

- **口径**：
  - 对 `apply` 表进行 **去重**，以 `apply_id` 为分组字段，选择 **`update_time`** 最新的记录。
  - 使用 **LEFT JOIN** 将 `apply` 表与 `decision` 表按照 `apply_id` 进行关联，确保每条申请记录都有对应的决策记录。
- **边界**：
  - **去重**：对于同一 `apply_id` 出现多条记录时，使用 **`row_number()`** 或 **`rank()`** 函数来保留最新的记录。
  - **数据缺失**：如果 `decision` 表中没有对应的 `apply_id`，则该行 **决策字段** 为空（记录为 `NULL`）。
  - **重复 `apply_id`**：如果有多条 `apply_id` 记录在 `decision` 表中，选择最新的 `decision_time` 来确定最终决策。

**校验 SQL**：

```sql
-- 去重后的记录数和原表的对比
SELECT COUNT(DISTINCT apply_id) AS distinct_apply_id_count, COUNT(*) AS total_count 
FROM apply;
```

------

#### **3）决策表关联口径**

- **口径**：`decision` 表根据 `apply_id` 左连接到 `apply` 表，输出结果包括申请记录和决策记录。若 `decision_time` 相同，取 **`apply_id`** 最新的记录，或者使用 **`update_time`** 或 **`ingest_time`** 作为稳定排序依据。
- **边界**：
  - 若 `decision` 表的 `apply_id` 为空，则此行决策为 `NULL`，表示该申请未做决策。
  - 如果在连接后 `decision` 表有多条记录，选择时间上最新的一条作为最终决策记录。

**校验 SQL**：

```sql
-- 检查左连接后 decision 是否为空
SELECT COUNT(*) FROM apply a
LEFT JOIN decision d ON a.apply_id = d.apply_id
WHERE d.decision IS NULL;
```

------

#### **4）申请通过率（pass_rate）口径**

- **口径**：`pass_rate` 的计算为 `pass_cnt / apply_cnt`，`apply_cnt` 是去重后的 `apply_id` 数，`pass_cnt` 是决策为 `PASS` 的申请数。
- **边界**：
  - `decision` 为 `NULL` 或 **不在预期值范围内（`PASS` 或 `REJECT`）** 的记录会被视为异常，设置为 `UNKNOWN` 或 `OTHER`，并单独统计其比例。

**校验 SQL**：

```sql
-- 统计通过率的异常值
SELECT decision, COUNT(*) FROM decision
GROUP BY decision;
```

------

### **Day 6 性能优化点（可执行标准）**

#### **1）性能优化：数据提取与加载**

- **优化点**：在 **数据提取** 和 **加载** 时，尽量避免全表扫描，选择 **必要字段**，减少不必要的数据加载。
- **技巧**：使用 **列裁剪**（只选择需要的列）来减少数据传输的负担，特别是当文件字段很多时。

**SQL 示例**：

```sql
-- 只选择需要的字段，避免加载不必要的字段
SELECT apply_id, update_time, amount, channel 
FROM apply;
```

#### **2）性能优化：去重操作的窗口函数**

- **优化点**：使用 **窗口函数**（如 `row_number()`）进行去重时，可以提前对数据进行 **分区** 和 **排序**，减少内存占用和计算量。
- **技巧**：在去重前先按 **时间范围过滤**，只处理相关数据，而不是全表去重。

**SQL 示例**：

```sql
-- 使用 row_number() 进行去重
WITH ranked AS (
  SELECT apply_id, update_time, row_number() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
  FROM apply
)
SELECT * FROM ranked WHERE rn = 1;
```

#### **3）性能优化：索引与查询优化**

- **优化点**：为常用的查询字段（如 `apply_id`、`update_time`）创建索引，减少查询时间。
- **技巧**：使用 **`EXPLAIN`** 或 **`ANALYZE`** 分析查询的执行计划，确认是否利用了索引。

**SQL 示例**：

```sql
-- 为 apply_id 创建索引以加速查询
CREATE INDEX idx_apply_id ON apply(apply_id);

-- 查看查询计划
EXPLAIN ANALYZE SELECT * FROM apply WHERE apply_id = 'some_id';
```

#### **4）性能优化：使用 `Parquet` 格式进行数据存储**

- **优化点**：对于大规模数据，使用 **Parquet** 文件格式而不是 CSV，可以大幅提升存储和查询性能。
- **技巧**：确保数据存储为 **Parquet 格式**，减少磁盘占用和提高查询速度。

**SQL 示例**：

```sql
-- 将查询结果保存为 Parquet 格式
COPY (SELECT * FROM apply) TO 'path_to_output.parquet' (FORMAT PARQUET);
```