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