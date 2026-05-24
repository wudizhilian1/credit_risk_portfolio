# Day 49 实践报告：模型监控与告警扩展——KS/PSI阈值监控 + 特征稳定性报表

## 1. 练习目标
- 将模型评估指标（KS、PSI）纳入每日监控，设置动态阈值，自动触发告警。
- 设计特征稳定性报表，监控关键特征（如申请金额、用户历史行为特征）的分布漂移（PSI）。
- 扩展告警引擎，支持模型性能下降告警（如 KS 低于阈值、PSI 超过阈值）。
- 将监控结果写入报表表，并集成到每日调度中，实现自动化模型运维。

## 2. 实验环境
- DuckDB 版本：0.10.0
- 数据库：`dev.duckdb`
- 项目路径：`C:\credit_risk_portfolio`
- 已有表：
  - `feature_apply_broad`（特征宽表）
  - `ads_model_eval`（模型评估结果表）
  - `dq_alert_rules`（告警规则配置表）
  - `dq_alert_history`（告警历史表）
- 告警引擎：`alert_engine.py`

## 3. 核心任务执行

### 3.1 扩展告警规则配置表
在 `dq_alert_rules` 中插入模型监控相关规则：
```sql
INSERT INTO dq_alert_rules (rule_name, table_name, metric, threshold_warn, threshold_error, is_active)
VALUES 
    ('模型KS下降', 'ads_model_eval', 'ks', 0.25, 0.20, true),
    ('模型PSI漂移', 'ads_model_eval', 'psi', 0.1, 0.25, true);
```
验证规则已生效：
```sql
SELECT * FROM dq_alert_rules WHERE metric IN ('ks', 'psi');
```

### 3.2 修改告警引擎支持模型指标
在 `alert_engine.py` 的 `fetch_monitor_data` 函数中增加对 `ks` 和 `psi` 的查询逻辑：
```python
elif metric == 'ks':
    res = con.execute(f"""
        SELECT ks FROM ads_model_eval
        WHERE model_name = 'strategy_score'
        ORDER BY eval_date DESC LIMIT 1
    """).fetchone()
    return res[0] if res else None
elif metric == 'psi':
    res = con.execute(f"""
        SELECT psi FROM ads_model_eval
        WHERE model_name = 'strategy_score'
        ORDER BY eval_date DESC LIMIT 1
    """).fetchone()
    return res[0] if res else None
```
测试告警引擎：
```bash
python scripts/alert_engine.py
```
若 KS 或 PSI 超过阈值，控制台会输出对应告警。

### 3.3 编写特征稳定性监控脚本 `sql/feature_stability.sql`
创建特征 PSI 监控表并计算 `amount`、`user_apply_cnt_30d`、`credit_score` 等特征的分布漂移。

**关键步骤**：
- 对每个特征定义分桶规则（如金额分4档）。
- 从 `feature_apply_broad` 中分别获取评估日（今日）和基准日（7天前）的分布。
- 使用 PSI 公式计算，将结果写入 `ads_feature_psi` 表。

执行脚本（示例日期）：
```bash
python scripts/run_sql.py --sql sql/feature_stability.sql --vars eval_date=2024-01-30 base_date=2024-01-23
```

### 3.4 集成到每日调度
在 `run_full_etl.py` 中添加步骤，在模型评估完成后自动计算特征 PSI：
```python
# 特征稳定性监控
print("步骤9：特征稳定性监控（PSI）...")
seven_days_ago = (datetime.datetime.strptime(dt, '%Y-%m-%d') - datetime.timedelta(days=7)).strftime('%Y-%m-%d')
run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/feature_stability.sql',
                '--vars', f'eval_date={dt} base_date={seven_days_ago}', '--db', db])
```

### 3.5 生成特征稳定性报表
基于 `ads_feature_psi` 表生成 `reports/feature_stability_report.md`，内容包括：
- 各特征 PSI 汇总及稳定性评估。
- 详细分布对比（今日 vs 基准日）。
- 告警与建议。
- 历史趋势图（可选）。

### 3.6 验证整体流程
运行全链路 ETL，观察：
- 模型评估表 `ads_model_eval` 是否正常写入。
- 告警引擎是否根据 KS/PSI 值触发相应级别告警。
- 特征 PSI 表是否有新记录，报表内容正确。

## 4. 遇到的问题与解决方案

| 问题                                 | 原因                                 | 解决方案                                                    |
| ------------------------------------ | ------------------------------------ | ----------------------------------------------------------- |
| `alert_engine.py` 无法识别 `ks` 指标 | `fetch_monitor_data` 未处理该 metric | 增加对应分支查询 `ads_model_eval`                           |
| 特征分桶边界导致空桶                 | 部分分桶无数据                       | 使用 `COALESCE` 和 `1e-6` 平滑处理                          |
| 特征 PSI 计算耗时较长                | 全表扫描                             | 利用 `feature_apply_broad` 的 `dt` 分区过滤，只扫描两日数据 |
| 告警规则未自动生效                   | 新规则未激活                         | 插入时设置 `is_active = true`                               |

## 5. 核心产出清单
- 告警规则表新增 KS/PSI 监控规则
- 修改后的 `alert_engine.py`（支持模型指标）
- 特征稳定性监控 SQL：`sql/feature_stability.sql`
- 特征 PSI 结果表：`ads_feature_psi`
- 特征稳定性报表：`reports/feature_stability_report.md`
- 集成到 `run_full_etl.py` 的调度步骤

## 6. 思考题
- 为什么模型监控需要独立于数据质量监控？  
  → 模型性能下降可能由数据漂移或业务变化引起，需单独设置阈值和响应流程，便于归因。
- 如果 KS 下降但 PSI 正常，可能是什么原因？  
  → 模型在特定子群体（如新客）上失效，需做分群评估或检查标签分布变化。
- 如何设置动态阈值而不是固定值？  
  → 可基于历史 KS 分布计算均值和标准差，采用 3σ 原则动态告警，避免固定阈值过时。

---
**完成日期**：2026-04-06