# Day 34 实践报告：DWS 层数据质量监控 v1（阈值监控 & PSI 稳定性）

## 1. 练习目标

- 建立 DWS 层数据质量监控体系，对核心汇总表进行每日巡检，及时发现数据异常（行数突变、字段空值、负值金额等）。
- 掌握使用统计规则（如环比波动、固定阈值）设定告警条件，并将监控结果写入监控表，便于后续告警推送。
- （加分项）计算拒绝原因分布的 **PSI（群体稳定性指标）**，量化分布漂移，为模型/策略稳定性监控提供依据。
- 明确 DQ 监控口径，更新相关文档。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- DWS 表：

  - `dws_channel_daily`（渠道日报）
  - `dws_strategy_daily`（策略日报）
  - `dws_reject_topn_daily`（拒绝原因 TopN）

- 监控目标表：`dq_dws_monitor`（新建）

- 数据时间范围：2024-01-01 至 2024-01-30（含异常日 2024-01-20）

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── dq/
  │       ├── dq_dws_monitor.sql
  │       └── psi_reject_reason.sql
  ├── docs/
  │   └── data_quality_rules.md
  └── reports/
      └── day34_dq_monitor.md
  ```

  

## 3. 核心任务执行

### 3.1 创建 DQ 监控表

sql

```sql
CREATE TABLE IF NOT EXISTS dq_dws_monitor (
    monitor_date        DATE NOT NULL,
    table_name          VARCHAR NOT NULL,
    row_count           INT,
    row_count_prev_day  INT,
    row_count_pct_change DECIMAL(10,2),
    null_field          VARCHAR,
    null_count          INT,
    null_rate           DECIMAL(10,4),
    negative_amount_cnt INT,
    negative_amount_rate DECIMAL(10,4),
    alert_level         VARCHAR,
    check_time          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```



### 3.2 编写 DWS 层行数监控 SQL

以 `dws_channel_daily` 为例，每日记录行数并与前一日对比：

```sql
INSERT INTO dq_dws_monitor
WITH today AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = '2024-01-15'
),
yesterday AS (
    SELECT COUNT(*) AS row_cnt FROM dws_channel_daily WHERE dt = CAST('2024-01-15'::DATE - INTERVAL '1 day' AS VARCHAR)
)
SELECT
    '2024-01-15' AS monitor_date,
    'dws_channel_daily' AS table_name,
    today.row_cnt AS row_cnt,
    yesterday.row_cnt AS row_count_prev_day,
    ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF (yesterday.row_cnt, 0), 2)
    AS row_count_pct_change,
    NULL AS null_field,
    NULL AS null_count,
    NULL AS null_rate,
    NULL AS negative_amount_cnt,
    NULL AS negative_amount_rate,
    CASE
        WHEN yesterday.row_cnt IS NULL THEN 'INFO'   -- 首日无对比
        WHEN ABS(ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF(yesterday.row_cnt, 0), 2)) > 20 THEN 'ERROR'
        WHEN ABS(ROUND(100.0 * (today.row_cnt - yesterday.row_cnt) / NULLIF(yesterday.row_cnt, 0), 2)) > 10 THEN 'WARN'
        ELSE 'OK'
    END AS alert_level,
    current_date()
FROM today, yesterday;
```

### 3.3 关键字段空值监控（以 `dws_strategy_daily` 为例）

```sql
INSERT INTO dq_dws_monitor
WITH stats AS (
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN strategy_name IS NULL OR strategy_name = '' THEN 1 ELSE 0 END) AS null_cnt
    FROM dws_strategy_daily
    WHERE dt='2024-01-15'
)
SELECT
    '2024-01-15' AS monitor_date,
    'dws_strategy_daily' AS table_name,
    NULL AS row_count,
    NULL AS row_count_prev_day,
    NULL AS row_count_pct_change,
    'strategy_name' AS null_field,
    null_cnt AS null_cnt,
    ROUND(100.0 * null_cnt / total, 4) AS null_rate,
    NULL AS negative_amount_cnt,
    NULL AS negative_amount_rate,
    CASE
        WHEN null_cnt > 0 THEN 'WARN'
        ELSE 'OK'
    END AS alert_level,
    current_date()
FROM stats;
```

### 3.4 负值金额监控（针对 `dws_channel_daily` 的 `apply_cnt`，假设不可能为负）

```sql
INSERT INTO dq_dws_monitor (monitor_date, table_name, negative_amount_cnt, negative_amount_rate, alert_level)
WITH neg AS (
    SELECT COUNT(*) AS neg_cnt
    FROM dws_channel_daily
    WHERE dt = '{{dt}}' AND apply_cnt < 0
)
SELECT
    '{{dt}}' AS monitor_date,
    'dws_channel_daily' AS table_name,
    neg_cnt AS negative_amount_cnt,
    ROUND(100.0 * neg_cnt / (SELECT COUNT(*) FROM dws_channel_daily WHERE dt = '{{dt}}'), 4) AS negative_amount_rate,
    CASE WHEN neg_cnt > 0 THEN 'ERROR' ELSE 'OK' END AS alert_level
FROM neg;
```

### 3.5 （加分项）拒绝原因分布 PSI 计算

创建 PSI 监控表（或直接插入汇总结果表）：

```sql
CREATE TABLE IF NOT EXISTS dq_psi_monitor (
    monitor_date DATE NOT NULL,
    base_date    DATE NOT NULL,
    psi_value    DECIMAL(10,6),
    check_time   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```



PSI 计算脚本（对比今日与 7 天前）：

```sql
WITH today AS (
    SELECT COALESCE(reject_reason, 'UNKNOWN') AS reason, COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt}}'
    GROUP BY reject_reason
),
prev AS (
    SELECT COALESCE(reject_reason, 'UNKNOWN') AS reason, COUNT(*) AS cnt
    FROM dwd_decision_latest
    WHERE decision = 'REJECT' AND dt = '{{dt_minus7}}'
    GROUP BY reject_reason
),
total_today AS (SELECT SUM(cnt) AS total FROM today),
total_prev AS (SELECT SUM(cnt) AS total FROM prev),
joined AS (
    SELECT
        COALESCE(t.reason, p.reason) AS reason,
        COALESCE(t.cnt, 0) AS cnt_today,
        COALESCE(p.cnt, 0) AS cnt_prev,
        tt.total AS total_today,
        tp.total AS total_prev
    FROM today t
    FULL OUTER JOIN prev p ON t.reason = p.reason
    CROSS JOIN total_today tt
    CROSS JOIN total_prev tp
),
eps AS (SELECT 1e-6 AS e)  --0.000001
SELECT
    ROUND(
		SUM( 
			 (
				(cnt_today + e) / (total_today + e) - (cnt_prev + e) / (total_prev + e) 
			 ) *
           LN( 
				(
				  (cnt_today + e) / (total_today + e)
				) / 
				(
				  (cnt_prev + e) / (total_prev + e)
				) 
			 ) 
			), 
		6) AS psi
FROM joined, eps;
```



### 3.6 整合监控执行

编写一个完整的 SQL 脚本（如 `dq_dws_monitor.sql`），按顺序执行上述监控插入，并通过变量传入 `{{dt}}`。然后通过 `run_sql.py` 执行：

```bash
python scripts/run_sql.py --sql sql/dq/dq_dws_monitor.sql --vars dt=2024-01-20
```



### 3.7 监控结果示例（2024-01-20）

查询 `dq_dws_monitor` 表：

```sql
SELECT * FROM dq_dws_monitor WHERE monitor_date = '2024-01-15' ORDER BY table_name;
```



**输出示例**：

```
+---------------------+--------------------+-------------+----------------------+------------------------+---------------+--------------+-------------+-----------------------+------------------------+---------------+---------------------+
| monitor_date        | table_name         | row_count   | row_count_prev_day   |   row_count_pct_change | null_field    | null_count   |   null_rate | negative_amount_cnt   |   negative_amount_rate | alert_level   | check_time          |
|---------------------+--------------------+-------------+----------------------+------------------------+---------------+--------------+-------------+-----------------------+------------------------+---------------+---------------------|
| 2024-01-15 00:00:00 | dws_channel_daily  | 4           | 4                    |                      0 |               | <NA>         |         nan | <NA>                  |                    nan | OK            | 2026-03-20 00:00:00 |
| 2024-01-15 00:00:00 | dws_strategy_daily | <NA>        | <NA>                 |                    nan | strategy_name | 0            |           0 | <NA>                  |                    nan | OK            | 2026-03-20 00:00:00 |
+---------------------+--------------------+-------------+----------------------+------------------------+---------------+--------------+-------------+-----------------------+------------------------+---------------+---------------------+
```

## 4. 口径与边界说明

| 监控项       | 口径                                                         |
| :----------- | :----------------------------------------------------------- |
| **行数波动** | 对比今日与前一日行数变化百分比，超过 ±20% 为 `ERROR`，±10%~20% 为 `WARN`，其余 `OK`。若前一日无数据，则为 `INFO`。 |
| **空值率**   | 关键字段（如策略名称、渠道名称）空值或空字符串比例，>0 即 `WARN`（可调整阈值）。 |
| **负值检测** | 统计数值字段小于 0 的记录数，出现即 `ERROR`。                |
| **PSI**      | 对比今日与 7 天前的拒绝原因分布，PSI < 0.1 稳定，0.1~0.25 略有漂移，>0.25 显著漂移（参考经验值）。 |

## 5. 性能点

- 监控查询涉及单日数据扫描，DWS 表每天仅几十行，扫描量极小，可忽略性能影响。
- PSI 计算扫描 DWD 表单日拒绝数据（约千行级），执行快速。
- 可通过调度每日执行一次，不影响业务。

## 10. 思考题

- 除了行数波动，还有哪些指标适合监控 DWS 表？（如通过率、拒绝率的日环比变化，超过阈值告警；关键维度的占比变化等。）
- 如何设计 PSI 的自动化告警？（每日计算，若 PSI > 0.25 则触发邮件；同时可对特征维度分别监控。）
- 如果发现某日行数突降为 0，可能的原因有哪些？（上游表未更新、调度失败、数据未生成、分区命名错误等。）





# 拒绝原因分布 PSI 计算：原理 + 公式 + 风控场景应用

## 一、PSI 基本概念

**PSI（Population Stability Index，群体稳定性指标）**

用来衡量**两个时间段 / 两个样本集之间，同一变量分布的变化程度**。

在风控里最常用场景：

- 拒绝原因分布是否随时间漂移
- 客群特征是否发生变化
- 模型入模变量是否出现分布偏移

**核心思想**：

如果分布几乎没变 → PSI 很小；

如果分布明显偏移 → PSI 很大，说明客群 / 策略 / 渠道发生了结构性变化。

------

## 二、PSI 计算公式（标准形式）

### 2.1 单变量离散型 PSI 公式（拒绝原因属于离散分布）

对于**分箱 / 类别**（如拒绝原因 A、B、C、D…）：
$$
PSI=∑i=1n((Actuali−Expectedi)×ln(Expectedi/Actuali))
$$
其中：

- Expectedi：**基准期**第 i 类的占比（如上月拒绝原因分布）
- Actuali：**对比期**第 i 类的占比（如本月拒绝原因分布）
- n：类别总数（拒绝原因个数）
- 占比必须是**0~1 小数**，不能是频数

> 注意：
>
> 1）占比不能为 0，否则 ln (0) 无意义，通常用极小值替代（如 0.0001）
>
> 2）所有类别占比求和均为 1

------

## 三、PSI 大小判断标准（风控通用阈值）

| PSI 范围       | 稳定性判断 | 业务含义                                     |
| :------------- | :--------- | :------------------------------------------- |
| **< 0.1**      | 稳定       | 分布无明显变化，正常                         |
| **0.1 ~ 0.25** | 轻微波动   | 需关注，可观察                               |
| **> 0.25**     | 明显漂移   | 需排查：客群、渠道、进件、策略、审批规则变化 |

拒绝原因分布 PSI 一般要求 **< 0.1** 才算稳定。

------

## 四、拒绝原因分布 PSI 计算步骤（实操版）

### 步骤 1：统计基准期 & 对比期 各拒绝原因数量

例如：

- 基准期（预期）：上月拒绝单量
- 对比期（实际）：本月拒绝单量

### 步骤 2：计算每类拒绝原因的**占比**

基准期第类数量基准期总拒绝量

对比期第类数量对比期总拒绝量

### 步骤 3：逐类计算 (A−E)×ln(A/E)

### 步骤 4：全部类别求和 → 得到整体 PSI

------

## 四、举个例子（拒绝原因分布）

假设 4 类拒绝原因：多头借贷、收入不足、征信不良、其他

| 拒绝原因 | 基准期数量 | 基准占比 E | 对比期数量 | 对比占比 A | **(A−E)×ln(A/E)** |
| :------- | :--------- | :--------- | :--------- | :--------- | :---------------- |
| 多头借贷 | 200        | 0.20       | 300        | 0.30       | 0.0405            |
| 收入不足 | 250        | 0.25       | 200        | 0.20       | 0.0112            |
| 征信不良 | 350        | 0.35       | 350        | 0.35       | 0                 |
| 其他     | 200        | 0.20       | 150        | 0.15       | 0.0144            |
| **合计** | **1000**   | **1.00**   | **1000**   | **1.00**   | **PSI = 0.0661**  |

PSI = 0.0661 < 0.1 → **分布稳定**

------

## 五、为什么拒绝原因要用 PSI？

1. **拒绝原因是离散分布**，天然适合 PSI

2. 能快速发现：

   - 某类拒绝突然暴增（如欺诈增多）
   - 渠道质量变化
   - 审批策略 / 规则调整导致结构漂移

   

3. 可作为**策略监控、模型监控、客群监控**的统一量化指标

------

## 六、常见注意事项

1. 占比不能为 0

   出现 0 占比时，替换为 0.0001 或合并类别

2. 拒绝原因必须一致

   基准期与对比期的类别定义、编码必须完全相同

3. PSI 只看分布，不看好坏

   PSI 高≠坏，只是说明 “变了”，需要业务解释

4. 样本量不能太小

   单类别样本过少时 PSI 会失真，建议合并低频类别

------

## 七、极简总结（可直接写进笔记）

- **PSI**：衡量变量分布稳定性，越小越稳定
- **公式**：
- **拒绝原因场景**：对比不同时期拒绝原因占比变化
- **阈值**：<0.1 稳定，0.1~0.25 关注，>0.25 漂移
- **用途**：监控客群、渠道、审批策略、风控规则稳定性

如果你需要，我可以再给你一段 **Python 计算拒绝原因 PSI 的可直接运行代码**（含空值处理、占比平滑）。