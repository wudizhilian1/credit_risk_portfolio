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

