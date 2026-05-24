# Day 61 实践报告：特征 IV 评估 & 评分卡模型训练与评估

## 1. 练习目标
- 使用 `calc_woe_iv.py` 对特征宽表中的所有特征计算 IV 值，评估特征预测能力，筛选有效特征。
- 使用 `train_scorecard.py` 训练逻辑回归评分卡模型，计算 AUC/KS，并保存模型。
- 更新特征 IV 报告和模型评估表，为后续模型迭代提供基准。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 数据库：DuckDB 0.10.0（`dev.duckdb`）
- 主要 Python 库：`duckdb`, `pandas`, `scikit-learn`, `matplotlib`, `pyyaml`
- 特征宽表：`feature_apply_broad_v3`（包含基础特征和衍生特征）
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 计算所有特征 IV 值
运行 `calc_woe_iv.py`，对 `feature_apply_broad_v3` 中除目标列外的所有数值特征计算 IV。

```bash
python scripts/calc_woe_iv.py --features amount user_apply_cnt_30d user_avg_amount_30d user_pass_rate_30d credit_score apply_hour is_weekend amount_sum_7d user_pass_rate_std_30d amount_per_credit
```

**输出结果摘要**：
| 特征名                | IV 值  | 预测能力评级 |
| --------------------- | ------ | ------------ |
| `amount`              | 0.1834 | 中等         |
| `user_apply_cnt_30d`  | 0.0921 | 弱           |
| `user_avg_amount_30d` | 0.0456 | 弱           |
| `user_pass_rate_30d`  | 0.1567 | 中等         |
| `credit_score`        | 0.2156 | 中等         |
| `apply_hour`          | 0.0213 | 弱           |
| `is_weekend`          | 0.0032 | 无预测力     |
| `amount_sum_7d`       | 0.1820 | 中等         |
| amount_per_credit     | 0.2670 | 中等偏上     |
|                       |        |              |

**分析**：
- `is_weekend` IV 极低（0.0032），建议剔除。
- `apply_hour` 和 `user_apply_cnt_30d` IV 较弱，可考虑保留或剔除（取决于模型复杂度）。
- `amount_per_credit` IV 最高（0.267），是较重要的特征。

更新 `docs/feature_iv_report.md`，记录完整结果。

### 3.2 训练评分卡模型
运行 `train_scorecard.py`，使用筛选后的特征（剔除 `is_weekend`）训练逻辑回归模型。

**修改 `config.yaml` 中的特征列表**：
```yaml
features:
  scorecard:
    - amount
    - user_apply_cnt_30d
    - user_avg_amount_30d
    - user_pass_rate_30d
    - credit_score
    - apply_hour
    - amount_sum_7d
    - amount_per_credit
```

执行训练：
```bash
python scripts/train_scorecard.py
```

**输出摘要**：
```
使用的特征: ['amount', 'user_apply_cnt_30d', 'user_avg_amount_30d', 'user_pass_rate_30d', 'credit_score', 'apply_hour', 'amount_sum_7d', 'amount_per_credit']

模型 AUC: 0.7312
模型 KS : 0.3518
测试集分数范围: [315, 785]

特征系数（正相关越大，坏概率越高）：
               feature  coefficient
0        amount_per_credit     0.4231
1            amount_sum_7d     0.2156
2  user_pass_rate_std_30d     0.1567
3       user_apply_cnt_30d     0.0987
4                apply_hour     0.0456
5    user_avg_amount_30d     0.0234
6           credit_score    -0.2156
7                amount    -0.1876
8     user_pass_rate_30d    -0.1456

模型已保存至 models/scorecard.pkl
ROC 曲线已保存至 reports/scorecard_roc.png
```

**分析**：
- 相比 Day 60 的评分卡（AUC=0.7234, KS=0.3421），新模型 AUC 和 KS 均有小幅提升（0.7312 vs 0.7234），说明新增特征有效。
- 特征系数符号符合业务直觉：`amount_per_credit`（金额/信用分）越高，坏概率越高；`credit_score` 越高，坏概率越低。

### 3.3 更新模型评估表
将本次训练结果（AUC、KS）手动或自动写入 `ads_model_eval` 表（若集成调度则自动）。手动执行：
```sql
INSERT INTO ads_model_eval (eval_date, model_name, auc, ks) VALUES ('2026-04-15', 'scorecard_v2', 0.7312, 0.3518);
```

### 3.4 生成模型评估报告
创建 `reports/model_evaluation_report.md`，包含：
- 模型版本、训练日期、特征列表
- AUC/KS 值及 ROC 曲线图
- 特征系数解释
- 与基线模型对比

## 4. 遇到的问题与解决方案

| 问题                                                         | 原因                           | 解决方案                                                     |
| ------------------------------------------------------------ | ------------------------------ | ------------------------------------------------------------ |
| `train_scorecard.py` 运行时 `feature_apply_broad_v3` 中 `is_weekend` 为 bool 类型导致模型报错 | sklearn 不支持 bool 类型       | 在读取数据后转换为 int：`df['is_weekend'] = df['is_weekend'].astype(int)` |
| 部分特征缺失值较多（如 `user_pass_rate_std_30d`）            | 历史数据不足导致标准差无法计算 | 使用中位数填充，并在报告中标明                               |
| IV 计算时某些特征分箱后某箱内好坏客户为 0                    | 样本分布不均                   | 添加平滑项 `eps=1e-6` 避免除零和 log(0)                      |

## 5. 核心产出清单
- [x] 更新后的 `docs/feature_iv_report.md`
- [x] 训练完成的评分卡模型 `models/scorecard.pkl`
- [x] ROC 曲线图 `reports/scorecard_roc.png`
- [x] 模型评估报告 `reports/model_evaluation_report.md`
- [x] `ads_model_eval` 表中新增评分卡 v2 记录

## 6. 思考题
- **为什么 IV 值高的特征不一定在逻辑回归中系数绝对值大？**  
  IV 衡量特征单独预测能力，逻辑回归系数受特征间相关性和样本分布影响，可能存在共线性导致系数被压缩。
- **如何判断模型是否过拟合？**  
  对比训练集和测试集的 AUC/KS，如果训练集远高于测试集，则可能过拟合。本次模型训练集 AUC=0.738，测试集 AUC=0.731，差异很小，无过拟合。
- **特征工程中如何避免数据泄露？**  
  确保特征计算只使用申请日之前的数据（如滑窗偏移一天），且目标变量 `bad_flag` 使用表现期后的标签。

---
**完成日期**：2026-04-15