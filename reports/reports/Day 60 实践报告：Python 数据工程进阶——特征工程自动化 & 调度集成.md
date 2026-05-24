# Day 60 实践报告：Python 数据工程进阶——特征工程自动化 & 调度集成

## 1. 练习目标
- 将前一日编写的 AUC/KS 计算和数据质量报告脚本集成到每日 ETL 调度中，实现自动化。
- 学习使用 `pandas` 进行更复杂的特征工程（如滑窗统计、交叉特征），并写入 DuckDB。
- 优化特征宽表 `feature_apply_broad_v2`，增加更多有业务意义的特征。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 数据库：DuckDB 0.10.0（`dev.duckdb`）
- 主要 Python 库：`duckdb`, `pandas`, `scikit-learn`, `matplotlib`
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 集成 AUC/KS 计算到 `run_full_etl.py`
- 修改 `scripts/calc_auc_ks.py`，增加 `--eval_date` 参数，使其可接收外部日期。
- 在 `run_full_etl.py` 末尾添加步骤：
  ```python
  print("步骤10：计算 AUC/KS ...")
  run_subprocess(['python', 'scripts/calc_auc_ks.py', '--eval_date', dt, '--db', db])

- 运行全链路 ETL（处理 2024-01-30），验证 `ads_model_eval` 表新增记录：

  ```sql
  SELECT * FROM ads_model_eval WHERE model_name='strategy_score' ORDER BY eval_date DESC LIMIT 1;
  ```

  结果：AUC=0.7234, KS=0.3421，与手动计算结果一致。

### 3.2 数据质量报告自动化

- 创建 `scripts/run_daily_quality_report.py`，调用 `data_quality_report.py` 并生成带日期的报告文件。
- 手动运行脚本，生成 `reports/quality_report_20260415.md`，内容包含 `feature_apply_broad_v2` 的列级统计。

### 3.3 特征工程进阶

在 `feature_apply_broad_v2` 基础上，使用 pandas 新增 4 个特征：

| 特征名                   | 计算逻辑                           | 实现方式                                            |
| :----------------------- | :--------------------------------- | :-------------------------------------------------- |
| `amount_sum_7d`          | 用户近 7 天申请金额总和            | `groupby('user_id')['amount'].rolling(7).sum()`     |
| `is_late_night`          | 申请时间在 22:00-6:00 为 1，否则 0 | `(apply_hour >= 22) | (apply_hour < 6)`             |
| `user_pass_rate_std_30d` | 过去 30 天通过率的标准差           | `groupby('user_id')['pass_rate'].rolling(30).std()` |
| `amount_per_credit`      | 申请金额 / 征信评分                | `amount / credit_score`                             |

- 将新特征写回 DuckDB 表 `feature_apply_broad_v3`。

### 3.4 验证特征有效性

- 使用 `calc_woe_iv.py` 计算新增特征的 IV 值，结果保存到 `docs/feature_iv_report.md`。
- 发现 `is_late_night` IV 值仅 0.008，无预测能力，建议剔除。

## 4. 遇到的问题与解决方案

| 问题                                                  | 原因                                | 解决方案                                           |
| :---------------------------------------------------- | :---------------------------------- | :------------------------------------------------- |
| `rolling` 滑窗包含当前行，导致未来信息泄露            | `rolling` 默认使用当前行及之前行    | 使用 `shift(1)` 将窗口偏移一天，确保只使用历史数据 |
| 新增特征写回 DuckDB 时类型不匹配                      | pandas 的 `bool` 类型 DuckDB 不支持 | 转换为 `int`（0/1）                                |
| 全链路 ETL 中调用 `calc_auc_ks.py` 时 `dt` 变量未传递 | `run_subprocess` 未正确传递参数     | 确保 `--eval_date` 使用循环中的 `dt` 变量          |

## 5. 核心产出清单

- 修改后的 `scripts/calc_auc_ks.py` 和 `run_full_etl.py`
- `scripts/run_daily_quality_report.py`
- 新特征表 `feature_apply_broad_v3`
- `docs/feature_iv_report.md`
- 数据质量报告示例 `reports/quality_report_20260415.md`

## 6. 思考题

- **滑窗特征（如近7天金额总和）可能引入数据泄露吗？如何避免？**
  可能泄露，如果窗口包含当前记录。解决方案：使用 `shift(1)` 将窗口向后偏移一天。
- **交叉特征 `amount / credit_score` 的业务含义是什么？**
  表示单位信用分对应的申请金额，反映“风险性价比”。值越高，说明客户在低信用分下申请大额，风险较高。
- **如果新增特征的 IV 值极低（<0.02），应该保留还是剔除？**
  剔除，避免引入噪声，降低模型过拟合风险。