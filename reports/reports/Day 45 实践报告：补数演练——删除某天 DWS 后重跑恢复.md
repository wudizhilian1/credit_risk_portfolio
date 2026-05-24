# Day 45 实践报告：补数演练——删除某天 DWS 后重跑恢复

## 1. 练习目标

- 掌握数据修复（补数）的基本流程：当某天数据出现异常或缺失时，如何通过删除受影响分区并重跑 ETL 来恢复。
- 实践“先删后插”的幂等策略，确保补数操作不影响其他日期数据。
- 学习使用审计表 `etl_run_audit` 记录补数操作，便于追踪。
- 模拟常见故障场景（如某天 DWS 数据错误），并手动修复。

## 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库：`dev.duckdb`
- 项目路径：`C:\credit_risk_portfolio`
- 已实现按日期范围增量刷新的 `run_full_etl.py`（支持 `--dt_start` / `--dt_end` 参数）
- 审计表 `etl_run_audit` 已创建并记录每次运行

## 3. 核心任务执行

### 3.1 模拟数据异常

假设某天（`2024-01-20`）的 DWS 表数据因上游 ETL 错误而异常（例如通过率被错误计算）。需要删除该天的 DWS 数据并重新计算。

### 3.2 删除指定日期的 DWS 数据

编写 SQL 删除 `dws_channel_daily`、`dws_strategy_daily`、`dws_reject_topn_daily` 中 `dt = '2024-01-20'` 的记录：

```sql
DELETE FROM dws_channel_daily WHERE dt = '2024-01-20';
DELETE FROM dws_strategy_daily WHERE dt = '2024-01-20';
DELETE FROM dws_reject_topn_daily WHERE dt = '2024-01-20';
```

可通过 `run_sql.py` 执行：

```bash
python scripts/run_sql.py --sql <(echo "DELETE FROM dws_channel_daily WHERE dt='2024-01-20'; DELETE FROM dws_strategy_daily WHERE dt='2024-01-20'; DELETE FROM dws_reject_topn_daily WHERE dt='2024-01-20';")
```

### 3.3 重跑该天的 ETL

使用 `run_full_etl.py` 只重跑 `2024-01-20`：

```bash
python scripts/run_full_etl.py --dt_start 2024-01-20 --dt_end 2024-01-20
```

执行后，脚本自动完成：

- raw → ODS（当日）
- ODS → DWD（当日）
- DWS 层刷新（按日期范围，仅处理 `2024-01-20`）
- ADS 层刷新（同样按日期范围）
- 对账、单元测试、告警

### 3.4 验证恢复

查询恢复后的数据，确认正确：

```sql
SELECT * FROM dws_channel_daily WHERE dt = '2024-01-20';
```

行数应与预期一致，指标合理。

### 3.5 记录补数操作

审计表 `etl_run_audit` 自动记录了本次运行的 `triggered_by = 'MANUAL'`，便于区分日常调度。

### 3.6 （可选）批量补数多个日期

若发现连续多天数据异常，可一次性删除并重跑：

```sql
DELETE FROM dws_channel_daily WHERE dt BETWEEN '2024-01-15' AND '2024-01-20';
```

然后执行：

```bash
python scripts/run_full_etl.py --dt_start 2024-01-15 --dt_end 2024-01-20
```

### 3.7 撰写补数演练记录

将本次补数过程记录到 `docs/backfill_drill.md`（见下文）。

## 4. 遇到的问题与解决方案

| 问题                        | 原因                             | 解决方案                                                     |
| :-------------------------- | :------------------------------- | :----------------------------------------------------------- |
| 执行 `DELETE` 后 DWS 表为空 | 误删所有分区                     | 使用 `WHERE dt = ...` 精确删除，避免全表清空                 |
| 重跑时 DWD 层未更新         | DWD 全量刷新，重跑时覆盖所有日期 | 已设计为全量刷新，无影响                                     |
| 补数后审计表未标记 `MANUAL` | 脚本中判断逻辑未识别手动参数     | 修改 `insert_audit_run`，检查 `sys.argv` 中是否包含 `--dt_start` 来设置 `triggered_by` |

## 5. 核心产出清单

- 补数演练记录文档 `docs/backfill_drill.md`
- 验证补数成功的日志（截图或文本）
- 审计表中 `MANUAL` 运行记录
- 更新的 `run_full_etl.py`（已集成日期范围、审计和最终检查）

## 6. 思考题

- 如果 DWD 层数据也有错误，补数时是否需要重跑 DWD？如何设计？
  → DWD 采用全量刷新，重跑 ODS → DWD 会覆盖所有日期，因此只需重跑 DWD 即可（可通过指定日期范围，但 DWD 全量刷新，实际重跑所有日期）。
- 如何确保补数操作不影响正在运行的调度？
  → 应在业务低峰期手动执行，或暂停调度任务。
- 如何利用审计表自动发现需要补数的日期？
  → 可设置监控：若某天 DWS 表数据缺失或指标异常（如通过率为 0），则自动触发补数脚本，并记录为 `MANUAL` 运行。