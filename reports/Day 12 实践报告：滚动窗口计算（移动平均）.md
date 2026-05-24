# Day 12 实践报告：滚动窗口计算（移动平均）

## 1. 练习目标
- 理解 **滚动窗口（Moving Window）** 的概念，掌握使用窗口函数的 `ROWS` 子句计算移动平均。
- 学会在风控场景中应用 **7 日移动平均**，平滑短期波动，识别长期趋势。
- 处理日期缺失问题，确保窗口计算基于正确的时间间隔。
- 比较 `ROWS` 与 `RANGE` 的区别，并明确使用场景。

## 2. 实验环境
- DuckDB 版本：0.x.x
- 数据路径：`data/raw/apply/` 按 `dt` 分区（2024-01-01 至 2024-01-10，共 10 天）
- 视图：`v_apply`、`v_decision`（基于分区 Parquet 文件创建，`hive_partitioning=1`）
- 数据规模：每天约 5,000 条申请记录，用户 ID 随机。

## 3. 核心 SQL 及结果

### 3.1 生成连续日期日历表
使用 DuckDB 的 `range` 函数生成连续日期序列：
```sql
WITH calendar AS (
    SELECT (range)::DATE AS dt
    FROM range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
)
SELECT * FROM calendar;
```

```
+----------------------------+
| dt                         |
|----------------------------|
| 2024-01-01T00:00:00.000000 |
| 2024-01-02T00:00:00.000000 |
| 2024-01-03T00:00:00.000000 |
| 2024-01-04T00:00:00.000000 |
| 2024-01-05T00:00:00.000000 |
| 2024-01-06T00:00:00.000000 |
| 2024-01-07T00:00:00.000000 |
| 2024-01-08T00:00:00.000000 |
| 2024-01-09T00:00:00.000000 |
| 2024-01-10T00:00:00.000000 |
+----------------------------+
```

### 3.2 每日申请量（填充缺失日期）

```sql
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) as apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt=d.dt
)
SELECT * FROM daily_full ORDER BY dt;
```

```

+---------------------+-------------+
| dt                  |   apply_cnt |
|---------------------+-------------|
| 2024-01-01 00:00:00 |        5000 |
| 2024-01-02 00:00:00 |        5000 |
| 2024-01-03 00:00:00 |        5000 |
| 2024-01-04 00:00:00 |        5000 |
| 2024-01-05 00:00:00 |        5000 |
| 2024-01-06 00:00:00 |        5000 |
| 2024-01-07 00:00:00 |        5000 |
| 2024-01-08 00:00:00 |        5000 |
| 2024-01-09 00:00:00 |        5000 |
| 2024-01-10 00:00:00 |        5000 |
+---------------------+-------------+
```

### 3.3 7 日移动平均申请量（ROWS 方式）

ROWS BETWEEN 6 PRECEDING AND CURRENT ROW 表示取当前行及前 6 行（共 7 行）参与计算，严格按行数，与日期间隔无关。

```sql
WITH calendar AS (
    SELECT (range)::DATE AS dt
    FROM range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) AS apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) AS apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt = d.dt
)
SELECT
    dt,
    apply_cnt,
    ROUND(AVG(apply_cnt) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS avg_7d_rows
FROM daily_full
ORDER BY dt;
```

```
+---------------------+-------------+---------------+
| dt                  |   apply_cnt |   avg_7d_rows |
|---------------------+-------------+---------------|
| 2024-01-01 00:00:00 |        5000 |          5000 |
| 2024-01-02 00:00:00 |        5000 |          5000 |
| 2024-01-03 00:00:00 |        5000 |          5000 |
| 2024-01-04 00:00:00 |        5000 |          5000 |
| 2024-01-05 00:00:00 |        5000 |          5000 |
| 2024-01-06 00:00:00 |        5000 |          5000 |
| 2024-01-07 00:00:00 |        5000 |          5000 |
| 2024-01-08 00:00:00 |        5000 |          5000 |
| 2024-01-09 00:00:00 |        5000 |          5000 |
| 2024-01-10 00:00:00 |        5000 |          5000 |
+---------------------+-------------+---------------+
```

### 3.4 7 日移动平均申请量（RANGE 方式）

```sql
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_apply AS (
    SELECT
        dt,
        COUNT(DISTINCT apply_id) as apply_cnt
    FROM v_apply
    WHERE dt BETWEEN '2024-01-01' AND '2024-01-10'
    GROUP BY dt
),
daily_full AS (
    SELECT
        c.dt,
        COALESCE(d.apply_cnt, 0) as apply_cnt
    FROM calendar c
    LEFT JOIN daily_apply d ON c.dt=d.dt
)
SELECT 
    dt,
    apply_cnt,
    AVG(apply_cnt) OVER (ORDER BY dt RANGE BETWEEN INTERVAL 6 DAYS PRECEDING AND CURRENT
    ROW ) AS avg_7d_range
FROM daily_full
ORDER BY dt;
```

```
+---------------------+-------------+----------------+
| dt                  |   apply_cnt |   avg_7d_range |
|---------------------+-------------+----------------|
| 2024-01-01 00:00:00 |        5000 |           5000 |
| 2024-01-02 00:00:00 |        5000 |           5000 |
| 2024-01-03 00:00:00 |        5000 |           5000 |
| 2024-01-04 00:00:00 |        5000 |           5000 |
| 2024-01-05 00:00:00 |        5000 |           5000 |
| 2024-01-06 00:00:00 |        5000 |           5000 |
| 2024-01-07 00:00:00 |        5000 |           5000 |
| 2024-01-08 00:00:00 |        5000 |           5000 |
| 2024-01-09 00:00:00 |        5000 |           5000 |
| 2024-01-10 00:00:00 |        5000 |           5000 |
+---------------------+-------------+----------------+
```

### 3.5 7 日移动平均通过率

```sql
WITH calendar as (
    SELECT (range)::DATE AS dt
    from range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY)
),
daily_metrics AS (
    SELECT
        a.dt,
        COUNT(DISTINCT a.apply_id) as apply_cnt,
        COUNT(DISTINCT CASE WHEN d.decision = 'PASS' THEN a.apply_id END) as pass_cnt
    FROM v_apply a
    LEFT JOIN v_decision d on a.apply_id = d.apply_id and a.dt=d.dt
    WHERE a.dt BETWEEN '2024-01-01' and '2024-01-10'
    GROUP BY a.dt
),
daily_full AS (
        SELECT
            c.dt,
            COALESCE(m.apply_cnt, 0) as apply_cnt,
            COALESCE(m.pass_cnt, 0) as pass_cnt
        FROM calendar c
        LEFT JOIN daily_metrics m ON c.dt=m.dt
),
daily_rate AS (
    SELECT
        dt,
        apply_cnt,
        pass_cnt,
        CASE WHEN apply_cnt = 0 THEN NULL ELSE ROUND(100.0 * pass_cnt / apply_cnt,2)
        END AS pass_rate
    FROM daily_full
)
SELECT
    dt,
    apply_cnt,
    pass_cnt,
    pass_rate,
    AVG(pass_rate) OVER (ORDER BY dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS pass_rate_ma_7d
    FROM daily_rate
    ORDER BY dt;
```

```
+---------------------+-------------+------------+-------------+-------------------+
| dt                  |   apply_cnt |   pass_cnt |   pass_rate |   pass_rate_ma_7d |
|---------------------+-------------+------------+-------------+-------------------|
| 2024-01-01 00:00:00 |        5000 |       1679 |       33.58 |           33.58   |
| 2024-01-02 00:00:00 |        5000 |       1686 |       33.72 |           33.65   |
| 2024-01-03 00:00:00 |        5000 |       1695 |       33.9  |           33.7333 |
| 2024-01-04 00:00:00 |        5000 |       1662 |       33.24 |           33.61   |
| 2024-01-05 00:00:00 |        5000 |       1625 |       32.5  |           33.388  |
| 2024-01-06 00:00:00 |        5000 |       1675 |       33.5  |           33.4067 |
| 2024-01-07 00:00:00 |        5000 |       1681 |       33.62 |           33.4371 |
| 2024-01-08 00:00:00 |        5000 |       1660 |       33.2  |           33.3829 |
| 2024-01-09 00:00:00 |        5000 |       1642 |       32.84 |           33.2571 |
| 2024-01-10 00:00:00 |        5000 |       1691 |       33.82 |           33.2457 |
+---------------------+-------------+------------+-------------+-------------------+
```

## 4. 口径与边界说明

| 口径要素         | 说明                                                         |
| :--------------- | :----------------------------------------------------------- |
| **移动平均定义** | 对指定窗口大小（如 7 天）内的指标值求算术平均。              |
| **窗口类型**     | `ROWS`：基于行数，与日期是否连续无关，适用于固定窗口大小但日期可能缺失的场景。 |
| **窗口大小**     | 7 日移动平均：包含当前行及前 6 行（共 7 行）。               |
| **缺失值处理**   | 使用日历表左连接，缺失日期填充 0 或 NULL，确保窗口行数固定。 |
| **NULL 处理**    | `AVG` 会忽略 NULL；若希望将 NULL 视为 0，需先用 `COALESCE` 转换。 |
| **边界条件**     | 窗口起始处（前 6 天）窗口内实际行数小于 7，平均值基于可用行数计算，结果仍有效。 |

## 5. 性能点

- **先聚合后窗口**：在日聚合表上使用窗口函数，避免在明细数据上直接开窗，极大减少计算量。
- **日历表填充**：使用 `range` 生成连续日期左连接，确保窗口函数按正确顺序计算。
- **列裁剪**：聚合时只取必要字段，减少 I/O。
- **分区裁剪**：在明细查询中使用 `dt BETWEEN` 过滤，确保只扫描所需分区。



### 一、RANGE () 核心定义

`RANGE()` 是 SQL 窗口函数中 `OVER()` 子句的一部分，作用是：

基于**列的数值范围**（而非物理行数），划定窗口的上下边界，常见于**累计计算、同比环比、风控时序指标**等场景。

#### 基础语法

```sql
函数() OVER (
    PARTITION BY 分组列  -- 可选，按维度分组
    ORDER BY 排序列     -- 必选，RANGE基于此列的数值范围计算
    RANGE BETWEEN 下界 AND 上界  -- 范围界定
)
```

- 常用边界取值

  ：

  - `UNBOUNDED PRECEDING`：分组内第一行
  - `CURRENT ROW`：当前行
  - `n PRECEDING/FOLLOWING`：当前行数值 ±n 的范围（仅支持数值 / 日期列）

  

### 二、RANGE () vs ROWS ()（核心区别，必懂）

这是最易混淆的点，用表格对比：

| 维度       | RANGE()                              | ROWS()                             |
| :--------- | :----------------------------------- | :--------------------------------- |
| 定义方式   | 基于**排序列的数值范围**             | 基于**物理行数**（固定行数）       |
| 适用场景   | 数值 / 日期列的范围统计（如近 7 天） | 固定行数统计（如前 3 行、后 2 行） |
| 重复值处理 | 相同值会被全部包含（合并行）         | 仅取指定行数（不合并）             |

### 四、关键注意事项（避坑）

1. **必须搭配 ORDER BY**：`RANGE()` 基于排序列的数值范围，无 `ORDER BY` 则无法界定范围；

2. **仅支持数值 / 日期列**：`ORDER BY` 后的列必须是数值（int/float）或可转为数值的日期（如时间戳），字符串列不支持；

3. **重复值合并**：若排序列有大量重复值（如风控中的 “0 逾期”），`RANGE` 会包含所有相同值的行，需注意统计口径；

4. 数据库兼容性

   ：

   - MySQL：仅支持 `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`（默认），不支持自定义数值范围（如 `10 PRECEDING`）；
   - PostgreSQL/SQL Server：支持完整的 `RANGE` 语法（数值 / 日期范围）；

   

5. **简写形式**：`ORDER BY 列 RANGE UNBOUNDED PRECEDING` 等价于 `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`（默认）。

### 五、总结

1. `RANGE()` 是窗口函数的**范围界定工具**，基于「列的数值范围」而非物理行数；
2. 核心区别：`RANGE` 按 “值范围” 算，`ROWS` 按 “物理行数” 算，风控中 `RANGE` 更适合日期 / 数值类时序指标；
3. 高频用途：累计计算、近 N 天统计、相同值合并统计，是风控时序指标（如累计放款、近 7 天逾期率）的核心工具；
4. 避坑点：必须搭配 `ORDER BY`，注意数据库兼容性（MySQL 对 RANGE 支持有限）。





### 一、COALESCE () 核心定义

#### 1. 基本语法

```sql
COALESCE(表达式1, 表达式2, ..., 表达式N)
```

#### 2. 核心逻辑

- 依次检查参数列表中的**表达式**，返回**第一个非 NULL 的值**；
- 如果所有参数都是 `NULL`，最终返回 `NULL`。

### 二、COALESCE () 与 ISNULL ()/IFNULL () 的对比（避坑）

很多人会混淆这几个函数，用表格清晰区分：

| 函数         | 支持数据库     | 参数个数 | 核心特点                        |
| :----------- | :------------- | :------- | :------------------------------ |
| `COALESCE()` | 所有主流数据库 | ≥2       | 通用、支持多参数（推荐）        |
| `IFNULL()`   | MySQL/MariaDB  | 2        | 仅支持两个参数，MySQL 专属      |
| `ISNULL()`   | SQL Server     | 2        | 仅支持两个参数，SQL Server 专属 |
| `NVL()`      | Oracle         | 2        | 仅支持两个参数，Oracle 专属     |

> 核心建议：优先用 `COALESCE()`，跨数据库兼容性最好，且支持多参数，满足绝大部分场景。

### 四、关键注意事项

1. **参数类型兼容**：所有参数的类型需可隐式转换（如 `INT` 和 `VARCHAR` 不兼容），否则报错

   ```sql
   -- 错误：INT(100) 和 VARCHAR('未知') 类型不兼容（MySQL）
   SELECT COALESCE(overdue_times, '未知') → 报错
   -- 正确：转为同一类型
   SELECT COALESCE(CAST(overdue_times AS VARCHAR), '未知')
   ```

2.**性能问题**：参数会按顺序执行，若前序参数是复杂计算（如子查询），需注意性能：

```sql
-- 尽量简化前序参数，避免无效计算
SELECT COALESCE(
    (SELECT MAX(loan_amount) FROM loan WHERE user_id = u.id),  -- 子查询（仅前序为NULL时执行）
    0
) AS max_loan FROM user u;
```

3.**和 CASE WHEN 等价性**：`COALESCE(a, b)` 等价于 `CASE WHEN a IS NOT NULL THEN a ELSE b END`，但多参数时 `COALESCE` 更简洁：

```sql
-- 等价写法，但 COALESCE 更短
CASE 
    WHEN phone IS NOT NULL THEN phone
    WHEN email IS NOT NULL THEN email
    ELSE '无联系方式'
END → COALESCE(phone, email, '无联系方式')
```

### 五、总结

1. `COALESCE()` 是 SQL 处理 `NULL` 的**通用工具**，核心是「返回第一个非 NULL 值」，跨数据库兼容；
2. 风控 / 数分中最常用：替换 NULL 为业务默认值、多字段兜底取值、聚合统计避免 NULL 错误；
3. 优先用 `COALESCE()` 而非 `IFNULL()`/`ISNULL()`，兼容性更好、支持多参数；
4. 注意参数类型兼容，避免因类型不一致导致报错。



# AI相关内容

# 时间序列预测方法（ARIMA/Prophet）- 风控场景应用笔记

## 一、基础概念：移动平均（MA）

移动平均（Moving Average，MA）是时间序列数据最基础的平滑与预测方法，核心逻辑为：

- 用**固定窗口内的历史数据均值**作为当前 / 未来值的预测基准；
- 作用：消除短期噪声，凸显数据长期趋势，是 ARIMA 等复杂模型的基础组件；
- 适用场景：无明显趋势、季节性的平稳时间序列（如短期风控指标波动平滑）。

## 二、ARIMA 模型

### 1. 核心构成

ARIMA（自回归积分移动平均模型）整合三类核心逻辑，适配非平稳时间序列：

- **AR（自回归）**：当前值由历史值线性组合预测（如 “前 7 天申请量决定今日申请量”）；
- **I（差分）**：对非平稳数据做差分处理，转化为平稳序列（解决趋势 / 季节性问题）；
- **MA（移动平均）**：当前值由历史预测误差线性组合修正。

### 2. 关键特点

- 适用于**有趋势、有季节性**的时间序列（如月度信贷申请量、季度逾期率）；
- 需手动调参（p,d,q）：p 为 AR 阶数、d 为差分阶数、q 为 MA 阶数；
- 对数据质量要求高，需提前做平稳性检验（ADF 检验）。

## 三、Prophet 模型

### 1. 核心定位

Prophet 是 Facebook 开源的时间序列预测工具，基于加法模型设计，核心优势：

- 原生支持**节假日、周期性（日 / 周 / 年）** 处理（适配风控场景中 “节假日申请量激增” 等特征）；
- 对缺失值、异常值鲁棒性强，无需复杂的前置数据预处理；
- 调参简单，非专业算法人员也能快速上手。

### 2. 适用场景

- 包含强周期性、节假日效应的时间序列（如春节 / 双十一期间的信贷申请量）；
- 业务人员快速落地预测需求，无需深入理解模型底层逻辑。

## 四、风控场景核心应用

时间序列预测方法可直接落地于风控全流程，核心用途：

1. **业务量预测**：预测未来信贷申请量、审批量，提前调配人力 / 系统资源，避免瓶颈；
2. **策略效果预判**：预测通过率、拒贷率走势，提前预警策略规则漂移 / 效果衰减；
3. **风险指标预警**：预测逾期率、不良率变化，提前调整风控阈值或催收策略；
4. **资源规划**：基于预测的放款量，优化资金储备与渠道投放策略。

## 五、方法选型参考

| 预测方法 | 优势                    | 劣势                    | 风控适配场景                         |
| :------- | :---------------------- | :---------------------- | :----------------------------------- |
| 移动平均 | 简单易实现、计算高效    | 无趋势 / 季节性处理能力 | 短期指标平滑、噪声消除               |
| ARIMA    | 趋势 / 季节性拟合精准   | 调参复杂、对异常值敏感  | 中长期风控指标预测（如月度逾期率）   |
| Prophet  | 适配节假日 / 周期、易用 | 复杂趋势拟合能力较弱    | 含节假日效应的业务量预测（如申请量） |

## 六、核心总结

1. 移动平均是时间序列预测的基础，适用于简单平滑场景；
2. ARIMA 适合有明确趋势 / 季节性的精准预测，需算法基础；
3. Prophet 适合业务人员快速落地，对节假日 / 周期适配性最优；
4. 风控中优先根据 “是否含节假日 / 周期”“预测精度要求” 选择模型，核心用于申请量、通过率、风险指标的预测与预警。