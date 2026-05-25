# 信贷风控数据工程作品集

## 项目简介
本项目模拟消费金融信贷审批场景，构建了从原始数据接入到报表监控的完整数据仓库。采用分层设计（ODS → DWD → DWS → ADS），实现指标自动化计算、数据质量监控、根因分析、单元测试和每日调度。所有代码基于 DuckDB + Python，可在本地完全复现。

**核心能力**：
- 统一风控指标口径（申请量、通过率、拒绝率等）
- 自动化 ETL 与增量刷新（支持历史回填）
- 数据质量监控 + 动态告警（行数波动、空值、PSI）
- 模型评估与特征稳定性监控（KS、PSI、特征分布漂移）
- 单元测试 + 一键跑通 + 定时调度

## 数据架构

详见 [指标口径定义文档](docs/lineage.md)

## 环境准备
- Python 3.8+ (推荐使用 conda 或 venv)
- 安装依赖：`pip install duckdb pandas`

### 一键运行

在项目根目录下执行：

```bash
run_all.bat          # Windows
# 或
bash run_all.sh      # Linux/macOS
```

该脚本会自动完成：

1. 生成 30 天模拟数据
2. 创建 DuckDB 数据库与视图
3. 运行全链路 ETL（处理昨天数据）
4. 执行单元测试
5. 运行告警引擎
6. 生成性能报告与特征稳定性报表

   ```bash
   python scripts/calc_woe_iv.py --features amount_sum_7d is_late_night amount_per_credit
   ```

   计算IV

### 手动执行示例



```bash
# 生成数据
python scripts/generate_demo_data.py

# 创建视图
python scripts/bootstrap_duckdb.py --db dev.duckdb --raw data/raw

# 处理指定日期范围
python scripts/run_full_etl.py --dt_start 2024-01-01 --dt_end 2024-01-15

# 查看核心指标
duckdb dev.duckdb -c "SELECT * FROM dws_channel_daily WHERE dt='2024-01-15';"
```

------

## 项目结构

```
credit_risk_portfolio/
├── data/raw/                # 原始分区 Parquet 数据
├── scripts/                 # Python 工具脚本（ETL、运行SQL、告警引擎）
├── sql/                     # SQL 脚本（按层分类）
│   ├── ddl/                 # 建表语句
│   ├── etl/                 # 增量 ETL
│   ├── dws/                 # DWS 层刷新
│   ├── ads/                 # ADS 层刷新
│   ├── reconcile/           # 对账脚本
│   └── features/            # 特征宽表与模型评估
├── tests/                   # 单元测试（pytest）
├── docs/                    # 技术文档
├── reports/                 # 报告（对账、性能、特征稳定性）
├── logs/                    # 调度日志
├── config.yaml              # 全局配置
├── run_all.bat              # 一键跑通脚本
├── run_daily_etl.bat        # 每日调度脚本
└── README.md
```

## 快速开始

1. 生成模拟数据：`python scripts/generate_demo_data.py`
2. 创建数据库和视图：`python scripts/bootstrap_duckdb.py --db dev.duckdb --raw data/raw`
3. 运行全链路 ETL（指定日期）：`python scripts/run_full_etl.py --dt 2024-01-15`
4. 查看报告：`reports/` 目录下查看对账、性能、监控报告。
4. 查看性能报告:cat reports/performance_baseline.md

## 核心指标口径

| 指标     | 定义                           | 数据来源                   |
| :------- | :----------------------------- | :------------------------- |
| 申请量   | `COUNT(DISTINCT apply_id)`     | `dwd_apply_latest`         |
| 通过率   | `pass_cnt / apply_cnt * 100`   | 关联 `dwd_decision_latest` |
| 拒绝率   | `reject_cnt / apply_cnt * 100` | 同上                       |
| KS       | 模型区分能力（分箱法）         | `feature_apply_broad`      |
| PSI      | 模型分数分布稳定性             | 同上                       |
| 特征 PSI | 特征分布漂移                   | `feature_apply_broad`      |

详见 [指标口径定义文档](docs/metrics_definitions.md)

## 数据质量监控
- **监控规则**：行数波动（±10% WARN, ±20% ERROR）、空值率、负值、PSI 漂移。
- **告警引擎**：每日自动扫描监控表，根据 `dq_alert_rules` 配置触发告警，写入 `dq_alert_history`，输出到控制台（可扩展邮件/钉钉）。
- **模型监控**：KS 低于 0.25 告警，PSI 高于 0.1 告警。
- **特征稳定性**：监控 `amount`、`user_apply_cnt_30d`、`credit_score` 等特征的 PSI。
- 详见 [指标口径定义文档](docs/data_quality_rules.md)

## 调度与测试
- **调度**：Windows 任务计划程序每日凌晨 2 点执行 `run_daily_etl.bat`，处理昨天数据。
- **幂等性**：ODS 按 `dt` 分区覆盖；DWD 全量刷新；DWS/ADS/特征宽表按日期范围先删后插。
- **单元测试**：`pytest tests/` 覆盖去重、指标一致性、空值处理、样本数限制等。
- **补数**：支持 `--dt_start` / `--dt_end` 重跑历史日期。
- 详见 [指标口径定义文档](docs/scheduling.md)

## 性能优化

- **物化视图**：`mv_user_hist_30d` 等加速历史特征计算（性能提升 96%）。
- **分区裁剪**：所有查询使用 `dt` 过滤。
- **增量处理**：DWS/ADS 只重算变化日期。
- **列裁剪**：只 SELECT 必要字段。

详见 [`docs/performance_tuning.md`](https://docs/performance_tuning.md)。

### 连接duckdb

```bash
# 1. 打开CMD，先切换到D:\duckdb（duckdb.exe所在目录）
cd /d D:\duckdb

# 2. 粘贴复制的路径，切换到目标文件夹（路径用双引号包裹）
cd /d "C:\credit_risk_portfolio"

# 3. 用相对路径连接dev.duckdb（无需输入中文路径）
duckdb dev.duckdb
```

### 使用Metabase

```bash
cd /d D:\metabase
java -jar metabase.jar
```

打开浏览器，访问 `http://localhost:3000`，进入初始化向导：

- 语言选择：简体中文；

- 创建管理员账号（输入邮箱、密码，记住账号密码）；

- 跳过「添加数据库」（后续手动添加 DuckDB）；

- 完成初始化，进入 Metabase 主界面。

  **1. 如果你使用的是 JAR 包启动**

  1. **下载驱动文件**：从 GitHub 上的 DuckDB 驱动发布页面下载最新的 `duckdb.metabase-driver.jar` 文件。
  2. **创建插件目录**：在你放置 `metabase.jar` 的同一目录下，新建一个名为 `plugins` 的文件夹。
  3. **放置驱动**：将下载好的 `.jar` 文件复制到 `plugins` 文件夹内。
  4. **重启 Metabase**：完全停止并重新启动 Metabase 服务。启动后，在添加数据库的页面里，你应该就能看到 **DuckDB** 的选项了。

  DuckDB 驱动本身只是一个 Metabase 插件，它需要依赖 **DuckDB 的 JDBC 驱动**才能正常工作。

  - 在 `plugins` 目录下，除了 `duckdb.metabase-driver.jar`，还应该有一个 `duckdb_jdbc-<version>.jar` 文件。
  - 如果缺少 JDBC 驱动，连接时可能产生各种异常。
  - **解决**：从 [DuckDB 官网](https://duckdb.org/docs/api/java) 或 Maven 中央仓库下载对应版本的 `duckdb_jdbc.jar`，放到 `plugins` 目录下，重启 Metabase。

### 创建 DuckDB 数据库与视图

```bash
python scripts/bootstrap_duckdb.py --db dev.duckdb --raw data/raw
```

### 运行示例查询

```bash
python scripts/run_sql.py --sql sql/hql/day01_bootstrap.sql --vars dt=2024-01-01 --out reports/day01_output.md
```

```bash
# 全量运行历史数据
python scripts/run_full_etl.py --dt_start 2024-01-01 --dt_end 2024-01-15

# 增量运行昨天
python scripts/run_full_etl.py --dt_start 2026-03-29 --dt_end 2026-03-29

# 打标签
git tag -a v1.0 -m "First stable release"
git push origin v1.0
```

### 项目sql目录

Day 8 实践报告：分区裁剪与列裁剪验证

Day 9 实践报告：UV 去重口径与 7 天滚动 UV 计算

Day 10 实践报告：风控漏斗分析（申请→决策→通过）

Day 11 实践报告：环比与同比分析（LAG窗口函数）

Day 12 实践报告：滚动窗口计算（移动平均）

Day 13 实践报告：数据质量基础 SQL

Day 14 实践报告：数据对账（Reconciliation）

Day 16 实践报告：ODS 层表结构设计（DDL）

Day 17 实践报告：DWD 层明细表设计（去重与标准化）

Day 18 实践报告：维表建模与维度关联

Day 19 实践报告：指标字典 v0（核心风控指标口径）

Day 20 实践报告：扩展模拟数据（30天分区 + 异常场景）

Day 22 实践笔记：ETL 1：raw → ODS 加载（按 dt 分区）

Day 24 实践报告：ETL 3：策略命中明细清洗（缺失/异常处理）

Day 25 实践报告：迟到数据策略（event_time vs load_time；回补流程设计）

Day 26 实践报告：对账 v0：raw vs ODS vs DWD 行数&关键字段一致性

Day 27 实践报告：性能基线：挑3条核心SQL做优化前后对比（耗时/Explain）

Day 29 实践报告：DWS层构建（渠道日报 & 策略日报）

Day 30 实践报告：DWS层构建（拒绝原因TopN & 稳定性监控）

Day 31 实践报告：DWS层构建（客群分层 & 策略命中率）

Day 32 实践报告：异常RCA贡献拆解（指标突变归因分析）

Day 33 实践报告：客群与策略交叉分析（分群策略评估）

Day 34 实践报告：DWS 层数据质量监控 v1（阈值监控 & PSI 稳定性）

Day 36 实践报告：ADS层构建（风控总览看板 & 渠道质量榜）

Day 37 实践报告：ADS层细化（拒绝原因钻取表 & 数据血缘v0）

Day 38 实践报告：对账 v2（ADS vs DWS vs DWD 一致性校验 & 单元测试 v0）

Day 39 实践报告：工程化 v1——告警方案设计与实现（阈值配置 + 通知脚本）

Day 41 实践报告：单元测试 v1——为关键 ETL 逻辑编写回归测试

Day 43 实践报告：增量框架——run_id审计表 + 参数化日期范围

Day 44 实践报告：幂等策略——分区覆盖 / merge key

Day 45 实践报告：补数演练——删除某天 DWS 后重跑恢复

Day 46 实践报告：性能基线 + 一键跑通 + 讲解稿 v1

Day 47 实践报告：模型评估指标接入 & 特征宽表构建

Day 48 实践报告：性能优化——物化视图加速核心查询

Day 49 实践报告：模型监控与告警扩展——KS/PSI阈值监控 + 特征稳定性报表

Day 51 实践报告（调整版）：项目文档完善 & 代码重构

Day 52 实践报告：SQL 高级实战——窗口函数 & 连续登录 & 留存率

Day 53 实践报告：Python 数据工程与特征工程进阶

Day 54 实践报告：风控业务知识学习——评分卡开发与风控指标体系

Day 55 实践报告：实时风控数据架构设计（Kafka + Flink 概念）

## 项目进展
- **Week 3 (Day 15-21)**: 完成 ODS/DWD 层建设，扩展模拟数据至30天，定义核心风控指标口径。详细见 `docs/week3_summary.md`。

```bash
python scripts/run_sql.py --sql scripts/run_week3_validation.sql
```

- **Week 4 (Day 22-28)**: raw → ODS 加载→ DWD 去重，策略命中明细清洗和迟到数据处理策略，设置三层对账，进行性能优化[详见总结文档](docs/week4_summary.md)。
- **Week 5 (Day 29-35)**: 完成 DWS 层汇总表构建（渠道日报、策略日报、拒绝原因 TopN、客群分层、交叉分析），建立数据质量监控体系（行数波动、空值、PSI），实现 RCA 贡献拆解。[详见总结文档](docs/week5_summary.md)。
- **Week 6 (Day 36-42)**: 完成 ADS 层构建，ADS 层细化，对账 ，工程化 ，调度自动化，单元测试。[详见总结文档](docs/week6_summary.md)。、
- **Week 7 (Day 43-50)**:增量框架，幂等策略，补数演练，性能基线，模型评估指标接入 & 特征宽表构建，性能优化，模型监控与告警扩展。[详见总结文档](docs/week7_summary.md)。

## 版本记录
| 版本 | 日期       | 特性                                                         |
| :--- | :--------- | :----------------------------------------------------------- |
| v1.0 | 2026-03-30 | 全链路 ETL + 基础监控 + 告警 + 调度                          |
| v2.0 | 2026-04-06 | 新增模型评估（KS/PSI/AUC）、特征稳定性监控（特征 PSI）、工程化完善（YAML 配置、日志规范） |

## 技术栈

- **数据存储**：DuckDB（列式存储，本地化）
- **开发语言**：Python 3.8+, SQL
- **测试框架**：pytest + pytest-cov
- **调度**：Windows 任务计划程序（可迁移至 Airflow）
- **配置管理**：YAML
- **版本控制**：Git

## 下一步计划

- 接入真实数据源（CSV/API）替换模拟数据
- 迁移至 PostgreSQL 或 ClickHouse 应对更大数据量
- 使用 Airflow 替代 Windows 计划任务，实现复杂依赖
- 开发前端看板（Streamlit）实时展示核心指标
