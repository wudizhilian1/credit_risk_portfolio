# Day 16 实践报告：ODS 层表结构设计（DDL）

## 1. 练习目标
- 理解 **ODS（操作数据存储）** 层的作用：保留原始数据最细粒度，作为数据仓库的源头。
- 掌握使用 `CREATE TABLE` 定义表结构，包括字段类型、主键、注释。
- 设计符合风控场景的 ODS 表，包括申请、决策、渠道、客户、策略、拒绝原因等主题。
- 编写规范的 DDL 脚本，并加入字段注释，为后续数据字典和血缘管理打下基础。
- 插入维表演例数据，为后续分析提供参照。

## 2. 实验环境
- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`（已存在）
- 已有视图：`v_apply`、`v_decision`（基于分区 Parquet）
- 项目目录结构：
- credit_risk_portfolio/
  ├── data/raw/
  ├── scripts/
  ├── sql/
  │ └── ddl/
  │ ├── ods_tables.sql
  │ └── dim_sample_data.sql
  ├── docs/
  └── reports/

## 3. 核心任务：ODS 层 DDL 与维表数据

### 3.1 创建 ODS 事实表（ods_apply, ods_decision）
由于 DuckDB 对 `COMMENT` 和 `PARTITION BY` 支持有限，采用简洁的 `CREATE TABLE` 语句，后续通过文档记录元数据。

**文件：`sql/ddl/ods_tables.sql`**
```sql
-- ODS 层申请事实表
CREATE TABLE IF NOT EXISTS ods_apply (
  apply_id          VARCHAR NOT NULL,      -- 申请单ID（主键）
  user_id           VARCHAR NOT NULL,      -- 用户ID
  channel_id        VARCHAR,               -- 渠道ID
  amount            DECIMAL(18,2),         -- 申请金额
  apply_time        TIMESTAMP,             -- 申请时间
  update_time       TIMESTAMP,             -- 更新时间
  dt                DATE NOT NULL          -- 分区日期（事件日）
);

-- ODS 层决策事实表
CREATE TABLE IF NOT EXISTS ods_decision (
  apply_id          VARCHAR NOT NULL,      -- 申请单ID（主键）
  decision          VARCHAR,               -- 决策结果：PASS/REJECT/REVIEW
  reject_reason     VARCHAR,               -- 拒绝原因代码（若为REJECT）
  strategy_version  VARCHAR,               -- 策略版本号
  decision_time     TIMESTAMP,             -- 决策时间
  dt                DATE NOT NULL          -- 分区日期（事件日）
);
```

### 3.2 创建维度表并插入样例数据

**文件：`sql/ddl/dim_sample_data.sql`**

```sql
-- 清空现有数据（保证幂等）
DELETE FROM dim_channel;
DELETE FROM dim_customer;
DELETE FROM dim_strategy;
DELETE FROM dim_reject_reason;

-- 渠道维表
CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id        VARCHAR PRIMARY KEY,
    channel_name      VARCHAR,
    channel_type      VARCHAR,
    is_active         BOOLEAN DEFAULT true
);
INSERT INTO dim_channel VALUES
    ('APP', '手机应用', 'APP', true),
    ('WEB', '网页端', 'WEB', true),
    ('H5', 'H5页面', 'H5', true),
    ('API', 'API接口', 'API', true);

-- 客户维表
CREATE TABLE IF NOT EXISTS dim_customer (
    user_id           VARCHAR PRIMARY KEY,
    user_name         VARCHAR,
    age               INT,
    registration_date DATE,
    risk_level        VARCHAR
);
INSERT INTO dim_customer VALUES
    ('user_1', '张三', 28, '2023-01-15', 'LOW'),
    ('user_2', '李四', 35, '2023-02-20', 'MEDIUM'),
    ('user_3', '王五', 42, '2023-03-10', 'HIGH'),
    ('user_4', '赵六', 31, '2023-04-05', 'MEDIUM'),
    ('user_5', '钱七', 45, '2023-05-12', 'HIGH'),
    ('user_6', '孙八', 26, '2023-06-18', 'LOW'),
    ('user_7', '周九', 38, '2023-07-22', 'MEDIUM'),
    ('user_8', '吴十', 29, '2023-08-30', 'LOW'),
    ('user_9', '郑十一', 41, '2023-09-14', 'HIGH'),
    ('user_10', '王十二', 33, '2023-10-01', 'MEDIUM');

-- 策略维表
CREATE TABLE IF NOT EXISTS dim_strategy (
    strategy_version  VARCHAR PRIMARY KEY,
    strategy_name     VARCHAR,
    effective_date    DATE,
    expiry_date       DATE,
    description       VARCHAR
);
INSERT INTO dim_strategy VALUES
    ('v1.0', '基础审批策略', '2024-01-01', '9999-12-31', '初始版本'),
    ('v1.1', '优化版策略', '2024-01-15', '9999-12-31', '调整风险评分阈值'),
    ('v2.0', '激进策略', '2024-02-01', NULL, '放宽部分限制');

-- 拒绝原因维表
CREATE TABLE IF NOT EXISTS dim_reject_reason (
    reason_code       VARCHAR PRIMARY KEY,
    reason_desc       VARCHAR,
    risk_level        VARCHAR
);
INSERT INTO dim_reject_reason VALUES
    ('FRAUD', '欺诈风险', 'HIGH'),
    ('OVER_LIMIT', '超出限额', 'MEDIUM'),
    ('RISK_SCORE', '风险评分不足', 'HIGH'),
    ('BLACKLIST', '命中黑名单', 'HIGH'),
    ('INCOME_LOW', '收入过低', 'MEDIUM'),
    ('AGE_LIMIT', '年龄不符合要求', 'LOW'),
    ('DUPLICATE_APPLY', '重复申请', 'MEDIUM');

-- 验证数据
SELECT 'dim_channel' AS tbl, COUNT(*) FROM dim_channel
UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_strategy', COUNT(*) FROM dim_strategy
UNION ALL
SELECT 'dim_reject_reason', COUNT(*) FROM dim_reject_reason;
```

## 4. 口径与边界说明

| 要素           | 说明                                                         |
| :------------- | :----------------------------------------------------------- |
| **事实表粒度** | `ods_apply` 每一行对应一次申请（由 `apply_id` 唯一标识）；`ods_decision` 每一行对应一次决策（同一申请可能有多次决策，需在 DWD 层处理）。 |
| **主键定义**   | 业务上 `apply_id` 应唯一，但在 ODS 层可能存在重复（源系统重复上报），故未设置主键约束。维度表使用业务主键并标注 `PRIMARY KEY` 以保持一致性。 |
| **分区策略**   | 虽然 DDL 中未使用 `PARTITION BY`，但可通过 `dt` 列手动分区，查询时利用 `WHERE dt = ...` 实现分区裁剪（数据源已按 `dt` 分目录存储）。 |
| **空值处理**   | 事实表中允许部分字段为空（如 `reject_reason` 仅当决策为 `REJECT` 时非空），维度表主键不允许为空。 |
| **数据更新**   | ODS 层保留原始数据，不进行去重或清洗，后续在 DWD 层处理。    |

## 5. 性能点

- **列裁剪**：查询时只 SELECT 必要列，减少 I/O。
- **过滤下推**：对 `dt` 列的过滤应尽早应用，利用数据源的分区结构。
- **表连接**：后续分析中，事实表与维表关联应使用小表驱动大表（DuckDB 自动优化），但可预先在维表上建立主键。