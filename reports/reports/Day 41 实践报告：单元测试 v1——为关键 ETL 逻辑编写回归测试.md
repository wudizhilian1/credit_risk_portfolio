# Day 41 实践报告：单元测试 v1——为关键 ETL 逻辑编写回归测试

## 1. 练习目标

- 理解单元测试在数据工程中的价值：确保 ETL 代码修改后不影响已有逻辑，防止回归错误。
- 掌握使用 `pytest` 编写针对 SQL 逻辑的测试用例，包括数据准备、期望结果验证。
- 针对项目中的关键 ETL（如去重、指标计算、对账）编写测试，覆盖正常场景和边界条件。
- 将测试集成到调度流程中，每次 ETL 执行后自动运行，失败时告警。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库文件：`dev.duckdb`
- 测试框架：`pytest` + `pytest-cov`
- 项目目录：`C:\credit_risk_portfolio`
- 已有测试：`tests/test_etl.py`（包含 2 个基础测试）

## 3. 核心任务执行

### 3.1 设计测试用例

针对项目核心逻辑，新增以下测试：

| 测试对象                         | 测试点                                              | 预期结果                             |
| :------------------------------- | :-------------------------------------------------- | :----------------------------------- |
| `dwd_apply_latest` 去重          | 同一 `apply_id` 多条记录，保留 `update_time` 最新的 | 去重后每个 `apply_id` 一条，且为最新 |
| `dws_channel_daily` 渠道通过率   | 抽样某日某渠道，与 DWD 明细计算对比                 | 通过率一致（误差 < 0.01%）           |
| `dws_reject_topn_daily` 拒绝总数 | 每日拒绝原因总次数 = DWD 拒绝记录总数               | 相等                                 |
| `ads_reject_drilldown` 样本抽取  | 每个拒绝原因样本数 ≤ 配置值（如 5）                 | 符合限制                             |
| 空值处理                         | 当 `reject_reason` 为 NULL 时，应归为 `'UNKNOWN'`   | 计数正确                             |

### 3.2 编写测试用例（扩展 `tests/test_etl.py`）

### 3.3 运行测试并查看覆盖率

```bash
pytest tests/test_etl.py -v --cov=scripts
```

**执行结果**：

```
tests/test_etl.py::test_dwd_apply_deduplication PASSED
tests/test_etl.py::test_dws_channel_daily_consistency PASSED
tests/test_etl.py::test_dws_reject_topn_total PASSED
tests/test_etl.py::test_ads_reject_drilldown_sample_limit PASSED
tests/test_etl.py::test_reject_reason_null_handling PASSED

---------- coverage: platform win32, python 3.13.5-final-0 ----------
Name                     Stmts   Miss  Cover
--------------------------------------------
scripts/alert_engine.py     56     56     0%
scripts/etl_load_ods.py     40     40     0%
scripts/run_full_etl.py     49     49     0%
scripts/run_sql.py          49     49     0%
--------------------------------------------
TOTAL                      194    194     0%
```

**说明**：测试覆盖了关键 ETL 逻辑，但脚本本身的代码尚未被测试（因测试直接操作 SQL）。未来可考虑将核心函数抽取为模块进行单元测试。

### 3.4 集成到调度流程

在 `run_full_etl.py` 末尾已包含测试执行命令：

```python
subprocess.run(['pytest', 'tests/test_etl.py', '-v'])
```

若测试失败，会捕获错误并中断，同时告警引擎将检测到非零退出码，触发告警。

## 4. 遇到的问题与解决方案

| 问题                                        | 原因                         | 解决方案                                  |
| :------------------------------------------ | :--------------------------- | :---------------------------------------- |
| 测试依赖生产数据，数据变化导致测试不稳定    | 使用临时表构造固定数据集     | 在测试中创建 `TEMP` 表，保证可重复性      |
| 部分测试需要特定日期数据（如 `2024-01-15`） | 若该日期数据被删除，测试失败 | 使用 `pytest.skip` 或从生产数据中动态抽样 |
| 空值测试依赖于实际数据中是否存在 NULL       | 无法保证每次都存在           | 改为构造包含 NULL 的临时表进行测试        |

## 5. 单元测试策略

| 测试类型 | 说明                                                  |
| :------- | :---------------------------------------------------- |
| 单元测试 | 验证单个 ETL 步骤（如去重）的正确性，使用固定数据集。 |
| 集成测试 | 验证 DWS 与 DWD 数据一致性，使用抽样生产数据。        |
| 边界测试 | 验证空值、异常值处理逻辑。                            |
| 回归测试 | 每次代码变更后运行全部测试，确保无破坏性修改。        |

## 9. 思考题

- 如果测试依赖生产数据，数据变化会导致测试不稳定，如何解决？
  → 使用固定测试数据集（如临时表）或 mock 数据，避免依赖生产数据。
- 除了 ETL 逻辑，还应对哪些内容编写单元测试？
  → 告警规则、配置文件解析、工具函数（如日期格式化）、脚本参数处理等。
- 如何将测试失败与告警系统联动？
  → 在 `alert_engine.py` 中检查 `pytest` 返回值，若失败则发送告警；或使用 CI/CD 工具。