# Day 53 实践报告：Python 数据工程与特征工程进阶

## 1. 练习目标
- 掌握 `pandas` 与 `DuckDB` 混合使用的技巧，利用 Python 进行复杂数据清洗和特征工程。
- 编写自动化数据质量检测脚本，生成数据质量报告（Markdown/HTML）。
- 学习使用 `scikit-learn` 计算模型评估指标（AUC、KS），并集成到项目中。
- 为后续风控业务知识和模型开发打下基础。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 数据库：DuckDB 0.10.0（`dev.duckdb`）
- 主要 Python 库：`duckdb`, `pandas`, `scikit-learn`, `matplotlib`
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 pandas + DuckDB 混合使用
**目标**：从 DuckDB 读取特征宽表，在 pandas 中进行分箱、缺失值填充等操作，然后写回数据库。

**实现**：
```python
import duckdb
import pandas as pd

con = duckdb.connect('dev.duckdb')
df = con.execute("SELECT * FROM feature_apply_broad LIMIT 10000").fetchdf()

# 对 amount 进行等频分箱（4箱）
df['amount_bin'] = pd.qcut(df['amount'], q=4, labels=['低', '中低', '中高', '高'])

# 对 user_apply_cnt_30d 自定义分桶
bins = [0, 1, 3, 5, float('inf')]
labels = ['0', '1-2', '3-5', '>5']
df['apply_cnt_bin'] = pd.cut(df['user_apply_cnt_30d'], bins=bins, labels=labels, right=False)

# 填充 credit_score 缺失值为中位数
median_score = df['credit_score'].median()
df['credit_score'].fillna(median_score, inplace=True)

# 写回新表
con.register('df_temp', df)
con.execute("CREATE OR REPLACE TABLE feature_apply_broad_v2 AS SELECT * FROM df_temp")
```

**验证**：查询新表，确认新增分箱列存在，缺失值已填充。

### 3.2 自动化数据质量检测脚本
编写 `scripts/data_quality_report.py`，实现对任意表生成质量报告。运行命令：
```bash
python scripts/data_quality_report.py --table feature_apply_broad --out reports/quality_report.md
```

**报告内容示例**（部分）：
```markdown
# 数据质量报告 - feature_apply_broad
**生成时间**: 2026-04-09 10:30:00
**总行数**: 150000

## 列级质量统计
| 列名 | 数据类型 | 缺失值数量 | 缺失率(%) | 唯一值个数 | 均值(数值列) | 标准差(数值列) |
|------|----------|------------|-----------|------------|--------------|----------------|
| apply_id | object | 0 | 0.00 | 150000 |  |  |
| amount | float64 | 0 | 0.00 | 150000 | 25012.34 | 14523.78 |
| credit_score | int64 | 1250 | 0.83 | 1800 | 612.45 | 89.23 |
...
```

报告包含每列的缺失率、唯一值个数、数值列均值/标准差、分类列 Top5 分布、数值列分位数等。

### 3.3 模型评估指标计算（AUC/KS）
编写 `scripts/calc_auc_ks.py`，从 `feature_apply_broad` 读取 `pred_score` 和 `bad_flag`，计算 AUC 和 KS，并更新 `ads_model_eval` 表。

**执行命令**：
```bash
python scripts/calc_auc_ks.py --eval_date 2024-01-30 --plot_roc
```

**输出**：
```
已更新 strategy_score 在 2024-01-30 的评估结果: AUC=0.7234, KS=0.3421
ROC 曲线已保存至 reports/roc_curve_2024-01-30.png
```

**验证**：查询 `ads_model_eval` 表：
```sql
SELECT * FROM ads_model_eval WHERE model_name='strategy_score' ORDER BY eval_date DESC LIMIT 1;
```
结果：AUC=0.7234, KS=0.3421，符合预期（模拟分数具有一定的区分能力）。

### 3.4 特征工程进阶（可选）
在 `feature_apply_broad_v2` 基础上，添加交叉特征 `amount_per_score = amount / credit_score`（当 credit_score > 0）。使用 pandas 计算后写回。

## 4. 遇到的问题与解决方案

| 问题                                     | 原因                                   | 解决方案                                                     |
| ---------------------------------------- | -------------------------------------- | ------------------------------------------------------------ |
| `pd.qcut` 分箱时出现重复边界错误         | 数据中存在大量相同值，导致分位数不唯一 | 使用 `pd.qcut(..., duplicates='drop')` 或改用 `pd.cut` 自定义分位数 |
| DuckDB 读取大表时内存不足                | 默认 fetchdf() 加载全表                | 使用 `LIMIT` 或分块读取（`fetch_record_batch`）              |
| `sklearn` 未安装                         | 环境中缺少库                           | `pip install scikit-learn matplotlib`                        |
| `bad_flag` 列存在 NULL 导致 ROC 计算失败 | 模拟数据中部分 bad_flag 为 NULL        | 在 SQL 查询中增加 `AND bad_flag IS NOT NULL`                 |

## 5. 核心产出清单
- [x] 脚本 `scripts/data_quality_report.py`
- [x] 脚本 `scripts/calc_auc_ks.py`
- [x] 数据质量报告 `reports/quality_report.md`
- [x] ROC 曲线图 `reports/roc_curve_2024-01-30.png`
- [x] 新特征表 `feature_apply_broad_v2`
- [x] 更新 `ads_model_eval` 表中的 AUC/KS 值
- [x] 更新文档 `docs/etl_design.md` 和 `docs/data_quality_rules.md`

## 6. 思考题
- **pandas 和 DuckDB 各有什么优势？什么场景下适合混合使用？**  
  DuckDB 适合 SQL 友好、列式扫描、聚合操作；pandas 适合复杂行级处理、分箱、缺失值填充、机器学习预处理。混合使用可发挥两者长处。
- **数据质量报告对面试有什么帮助？**  
  展示对数据质量的重视，提供具体证据；体现工程化思维（自动化、可复现）。
- **AUC 和 KS 的区别是什么？在风控中哪个更常用？**  
  AUC 衡量模型排序能力（整体区分度），KS 衡量最大区分能力（常用于策略切点选择）。两者均常用，KS 更直观。

---
**完成日期**：2026-04-09