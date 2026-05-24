# Day 17 实践报告：DWD 层明细表设计（去重与标准化）

## 1. 练习目标
- 理解 **DWD（明细数据层）** 的作用：对 ODS 原始数据进行清洗、去重、标准化，形成一致、干净的明细数据，供后续汇总使用。
- 掌握使用窗口函数进行去重取最新记录的方法，并写入物理表。
- 设计 DWD 层表结构，包含必要的字段。
- 更新数据字典，记录 DWD 表口径。

## 2. 实验环境
- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 已有 ODS 表：`ods_apply`、`ods_decision`（已通过 `INSERT INTO ... SELECT * FROM v_apply` 等命令填充数据）
- 已有维度表：`dim_channel`、`dim_customer`、`dim_strategy`、`dim_reject_reason`
- 项目目录结构：

credit_risk_portfolio/
├── data/raw/
├── scripts/
├── sql/
│ └── ddl/
│ ├── ods_tables.sql
│ ├── dim_sample_data.sql
│ └── dwd_tables.sql
├── docs/
└── reports/

## 3. 核心任务：创建 DWD 表并插入去重数据

### 3.1 创建 DWD 申请明细表（`dwd_apply_latest`）
**粒度**：每个 `apply_id` 一条最新记录。  
**去重规则**：按 `update_time` 降序取最新一条。

```sql
-- 创建 dwd_apply_latest 表
CREATE TABLE IF NOT EXISTS dwd_apply_latest (
  apply_id          VARCHAR NOT NULL,
  user_id           VARCHAR NOT NULL,
  channel_id        VARCHAR,
  amount            DECIMAL(18,2),
  apply_time        TIMESTAMP,
  update_time       TIMESTAMP,
  dt                DATE NOT NULL
);

-- 从 ods_apply 去重插入最新记录
INSERT INTO dwd_apply_latest
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
  FROM ods_apply
)
SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
FROM ranked
WHERE rn = 1;
```

### 3.2 创建 DWD 决策明细表（`dwd_decision_latest`）

**粒度**：每个 `apply_id` 一条最新决策记录。
**去重规则**：按 `decision_time` 降序取最新。

```sql
CREATE TABLE IF NOT EXISTS dwd_decision_latest (
    apply_id          VARCHAR NOT NULL,
    decision          VARCHAR,
    reject_reason     VARCHAR,
    strategy_version  VARCHAR,
    decision_time     TIMESTAMP,
    dt                DATE NOT NULL
);

INSERT INTO dwd_decision_latest
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY decision_time DESC) AS rn
    FROM ods_decision
)
SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
FROM ranked
WHERE rn = 1;
```

### 3.3 （可选）创建规则命中明细表 `dwd_rule_hit`

仅定义表结构，暂不填充数据，供后续扩展。

```sql
CREATE TABLE IF NOT EXISTS dwd_rule_hit (
    apply_id          VARCHAR NOT NULL,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_result        BOOLEAN,
    hit_time          TIMESTAMP,
    dt                DATE NOT NULL
);
```

## 5. 口径与边界说明

| 表名                  | 粒度             | 去重规则                  | 说明                                                         |
| :-------------------- | :--------------- | :------------------------ | :----------------------------------------------------------- |
| `dwd_apply_latest`    | 每个申请一条     | 按 `update_time` 取最新   | 若同一 `apply_id` 在 ODS 中有多条记录（如状态更新），取最新状态作为最终申请信息。 |
| `dwd_decision_latest` | 每个申请一条     | 按 `decision_time` 取最新 | 取最终决策结果，忽略历史中间决策（如初审、复审）。若业务需要保留所有决策历史，则不应去重，可直接使用 ODS 表。 |
| `dwd_rule_hit`        | 每个规则命中一条 | 无（假设原始数据已唯一）  | 记录申请命中规则的情况，可关联维表分析规则效果。             |

## 6. 性能点

- **去重操作**：使用窗口函数 `ROW_NUMBER()` 在插入时一次性完成，后续查询可直接使用 DWD 表，避免重复计算。
- **分区裁剪**：虽然 DWD 表未显式分区，但查询时仍应利用 `dt` 字段过滤，DuckDB 会自动优化。
- **列裁剪**：DWD 表仅保留必要字段，减少存储和 I/O。
- **插入效率**：`INSERT INTO ... SELECT` 在 DuckDB 中为批量操作，性能良好。