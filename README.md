# 信贷风控数据工程作品集

## 项目简介
本项目模拟消费金融信贷审批场景，构建从 ODS → DWD → DWS → ADS 的全流程数据管道，涵盖：
- 数据生成与分区存储
- 数据质量检查
- 核心风控指标计算（通过率、拒绝率、UV 等）
- 时间序列分析（环比、同比、移动平均）
- 数据对账与血缘管理

所有代码均可在本地使用 **DuckDB** 运行，无需大数据集群。

## 环境准备
- Python 3.8+ (推荐使用 conda 或 venv)
- 安装依赖：`pip install duckdb pandas`

## 快速开始
1. 生成模拟数据：
   ```bash
   python scripts/generate_demo_data.py
   ```

### 连接duckdb

```bash
# 1. 打开CMD，先切换到D:\duckdb（duckdb.exe所在目录）
cd /d D:\duckdb

# 2. 粘贴复制的路径，切换到目标文件夹（路径用双引号包裹）
cd /d "C:\Users\98128\Desktop\量化相关\职业规划\credit_risk_portfolio"

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

## 项目进展
- **Week 3 (Day 15-21)**: 完成 ODS/DWD 层建设，扩展模拟数据至30天，定义核心风控指标口径。详细见 `docs/week3_summary.md`。



```bash
python scripts/run_sql.py --sql scripts/run_week3_validation.sql
```

## 项目进展
- **Week 5 (Day 29-35)**: 完成 DWS 层汇总表构建（渠道日报、策略日报、拒绝原因 TopN、客群分层、交叉分析），建立数据质量监控体系（行数波动、空值、PSI），实现 RCA 贡献拆解。详见 `docs/week5_summary.md`。
