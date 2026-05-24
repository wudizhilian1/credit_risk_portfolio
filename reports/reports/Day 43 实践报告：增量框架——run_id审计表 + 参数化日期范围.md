## Day 43 实践报告：增量框架——run_id审计表 + 参数化日期范围

### 1. 练习目标

- 理解增量处理在数据仓库中的价值：避免每次全量刷新，提升效率，支持历史回溯。
- 设计 `run_id` 审计表，记录每次 ETL 运行的元数据。
- 改造 ETL 脚本，支持按日期范围参数（`dt_start`, `dt_end`）执行，而非单日固定。
- 实现幂等性：重复执行同一范围不会产生重复数据。

### 2. 实验环境

- DuckDB 版本：0.10.0
- 数据库：`dev.duckdb`
- 项目路径：`C:\credit_risk_portfolio`
- 已有 ETL 脚本：`run_full_etl.py`（原支持单日 `--dt`）

### 3. 核心任务执行

#### 3.1 创建审计表 `etl_run_audit`

```sql
CREATE TABLE IF NOT EXISTS etl_run_audit (
    run_id          INTEGER PRIMARY KEY,
    start_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time        TIMESTAMP,
    dt_start        DATE,
    dt_end          DATE,
    status          VARCHAR,
    rows_affected   INTEGER,
    error_message   TEXT,
    triggered_by    VARCHAR
);
```

#### 3.2 修改 `run_full_etl.py` 支持日期范围

- 移除原 `--dt` 参数，增加 `--dt_start` 和 `--dt_end`。
- 未提供时默认处理昨天（单日）。
- 生成日期列表，循环执行每一日的原有 ETL 流程。
- 在循环外最后执行统一的对账、测试和告警（避免重复）。

**关键代码片段**：

```python
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default='dev.duckdb')
    parser.add_argument('--dt_start', help='起始日期 YYYY-MM-DD')
    parser.add_argument('--dt_end', help='结束日期 YYYY-MM-DD')
    args = parser.parse_args()

    if not args.dt_start:
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime('%Y-%m-%d')
        dt_start = dt_end = yesterday
    else:
        dt_start = args.dt_start
        dt_end = args.dt_end or args.dt_start

    date_list = generate_date_range(dt_start, dt_end)

    for dt in date_list:
        # 执行原有单日 ETL 逻辑（步骤1-7）
        ...

    # 所有日期完成后，执行最终检查
    subprocess.run(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/ads_vs_dws_reconcile.sql', ...])
    subprocess.run(['pytest', 'tests/test_etl.py', '-v'])
    subprocess.run(['python', 'scripts/alert_engine.py'])
```

#### 3.3 改造 DWS 层 SQL 支持日期范围

以 `dws_channel_daily` 为例，原全量刷新改为按日期范围增量：

```sql
DELETE FROM dws_channel_daily WHERE dt BETWEEN '{{dt_start}}' AND '{{dt_end}}';
INSERT INTO dws_channel_daily ...
WHERE a.dt BETWEEN '{{dt_start}}' AND '{{dt_end}}'
GROUP BY a.dt, a.channel_id, ...
```

#### 3.4 测试增量运行

- 执行 `python scripts/run_full_etl.py --dt_start 2024-01-01 --dt_end 2024-01-15`，观察处理 15 天数据，审计表记录一次运行（范围）。
- 再次执行同一范围，数据未重复（幂等）。
- 执行 `--dt_start 2024-01-16 --dt_end 2024-01-16`，仅处理新增一天，DWS 表正确追加。

### 4. 遇到的问题与解决方案

| 问题                                         | 原因                             | 解决方案                                              |
| :------------------------------------------- | :------------------------------- | :---------------------------------------------------- |
| 脚本中原变量 `dt` 未定义                     | 移除 `--dt` 参数后未更新内部引用 | 改为循环遍历 `date_list`，每轮使用 `dt` 变量          |
| DWD 层去重表按日期范围增量可能丢失跨分区更新 | 增量只处理指定范围的 ODS 记录    | 保持 DWD 全量刷新（数据量小），DWS 层增量             |
| 审计表未自动记录行数                         | 未在 ETL 步骤中统计              | 后续可增强：在 `run_full_etl.py` 中汇总各步骤影响行数 |

### 5. 核心产出清单

- 审计表 `etl_run_audit`
- 修改后的 `scripts/run_full_etl.py`（支持日期范围循环）
- 增量改造的 DWS 层 SQL（`dws_channel_daily`, `dws_strategy_daily` 等）
- 文档更新：
  - `docs/scheduling.md`（新增增量调度说明）
  - `docs/etl_design.md`（新建，记录增量策略）

### 6. 思考题

- 为什么 DWD 去重表难以增量处理？
  → 因为去重需基于全局 `apply_id` 的最新状态，增量仅处理部分分区可能丢失最新记录。解决方法是使用拉链表或保持全量刷新。
- 如何利用审计表实现失败重跑？
  → 查询 `etl_run_audit` 中失败的日期范围，重新执行。
- 如何将增量范围与调度系统结合？
  → 调度脚本每次只处理昨天（`--dt_start yesterday --dt_end yesterday`），审计表记录每次运行范围。