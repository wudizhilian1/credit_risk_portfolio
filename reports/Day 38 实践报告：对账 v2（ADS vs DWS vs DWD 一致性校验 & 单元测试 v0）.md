# Day 38 实践报告：对账 v2（ADS vs DWS vs DWD 一致性校验 & 单元测试 v0）

## 1. 练习目标

- 扩展数据对账范围，从原来的 ODS ↔ DWD 延伸到 ADS 层，确保 ADS 指标与 DWS 汇总结果一致，并最终与 DWD 明细可追溯。
- 掌握对账脚本的编写方法，对比聚合结果、记录差异、生成报告。
- 引入简单的单元测试概念，使用 `pytest` 验证关键 SQL 的正确性（如去重、聚合逻辑），为后续工程化打下基础。
- 将对账结果写入监控表，支持自动化巡检。

## 2. 实验环境

- DuckDB 版本：0.10.0

- 数据库文件：`dev.duckdb`

- 涉及表：

  - DWD：`dwd_apply_latest`、`dwd_decision_latest`
  - DWS：`dws_channel_daily`、`dws_strategy_daily`
  - ADS：`ads_overview_daily`、`ads_channel_quality`、`ads_reject_drilldown`

- 项目目录：

  text

  ```
  credit_risk_portfolio/
  ├── sql/
  │   └── reconcile/
  │       └── ads_vs_dws_reconcile.sql
  ├── tests/
  │   └── test_etl.py
  ├── docs/
  │   └── data_quality_rules.md
  └── reports/
      └── day38_reconcile_report.md
  ```

## 3. 核心任务执行

### 3.1 编写 ADS vs DWS 对账 SQL

对比 `ads_overview_daily` 与 `dws_channel_daily` 按日汇总的指标，找出不一致的记录。

**文件：`sql/reconcile/ads_vs_dws_reconcile.sql`**

```sql
WITH dws_summary AS (
    SELECT
        dt,
        SUM(apply_cnt) AS apply_cnt_dws,
        SUM(pass_cnt) AS pass_cnt_dws,
        SUM(reject_cnt) AS reject_cnt_dws,
        SUM(review_cnt) AS review_cnt_dws
    FROM dws_channel_daily
    GROUP BY dt
)
SELECT
    a.dt,
    a.apply_cnt AS apply_cnt_ads,
    d.apply_cnt_dws,
    a.apply_cnt - d.apply_cnt_dws AS apply_diff,
    a.pass_cnt AS pass_cnt_ads,
    d.pass_cnt_dws,
    a.pass_cnt - d.pass_cnt_dws AS pass_diff,
    a.reject_cnt AS reject_cnt_ads,
    d.reject_cnt_dws,
    a.reject_cnt - d.reject_cnt_dws AS reject_diff
FROM ads_overview_daily a
LEFT JOIN dws_summary d ON a.dt = d.dt
WHERE a.apply_cnt != d.apply_cnt_dws
   OR a.pass_cnt != d.pass_cnt_dws
   OR a.reject_cnt != d.reject_cnt_dws
ORDER BY a.dt;
```

**执行结果**：查询返回空集，表明所有日期 ADS 与 DWS 数据一致。

### 3.2 创建对账结果表并插入监控记录

```sql
CREATE TABLE IF NOT EXISTS reconcile_ads_log (
    check_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dt              DATE,
    metric          VARCHAR,
    ads_value       INT,
    dws_value       INT,
    diff            INT,
    alert_level     VARCHAR
);
```

将对账结果插入，无差异时插入一条 OK 记录；有差异时按指标分别插入 WARN/ERROR。

**示例插入语句（简化）**：

```sql
INSERT INTO reconcile_ads_log (dt, metric, ads_value, dws_value, diff, alert_level)
SELECT dt, 'apply_cnt', apply_cnt_ads, apply_cnt_dws, apply_diff,
       CASE WHEN ABS(apply_diff) <= 5 THEN 'OK' WHEN ABS(apply_diff) <= 20 THEN 'WARN' ELSE 'ERROR' END
FROM (上述对账子查询);
```

### 3.3 编写单元测试（pytest）

创建 `tests/test_etl.py`，对关键 ETL 逻辑进行验证。

```python
import duckdb
import pytest

@pytest.fixture
def con():
    conn = duckdb.connect('dev.duckdb')
    yield conn
    conn.close()

def test_dws_channel_daily_apply_cnt(con):
    """验证 dws_channel_daily 的申请量是否与 DWD 明细一致（抽样）"""
    dt = '2024-01-15'
    channel = 'APP'
    dws_apply = con.execute(f"SELECT apply_cnt FROM dws_channel_daily WHERE dt='{dt}' AND channel_id='{channel}'").fetchone()[0]
    dwd_apply = con.execute(f"""
        SELECT COUNT(DISTINCT apply_id) FROM dwd_apply_latest
        WHERE dt='{dt}' AND channel_id='{channel}'
    """).fetchone()[0]
    assert dws_apply == dwd_apply, f"渠道 {channel} 申请量不一致：dws={dws_apply}, dwd={dwd_apply}"

def test_ads_overview_daily_consistency(con):
    """验证 ads_overview_daily 与 dws_channel_daily 汇总一致（抽样）"""
    dt = '2024-01-15'
    ads_apply = con.execute(f"SELECT apply_cnt FROM ads_overview_daily WHERE dt='{dt}'").fetchone()[0]
    dws_apply = con.execute(f"SELECT SUM(apply_cnt) FROM dws_channel_daily WHERE dt='{dt}'").fetchone()[0]
    assert ads_apply == dws_apply, f"ADS 申请量 {ads_apply} 与 DWS 汇总 {dws_apply} 不一致"

def test_reject_reason_topn_count(con):
    """验证 dws_reject_topn_daily 中拒绝原因总次数与 DWD 拒绝总数一致"""
    dt = '2024-01-15'
    topn_total = con.execute(f"SELECT SUM(reject_cnt) FROM dws_reject_topn_daily WHERE dt='{dt}'").fetchone()[0]
    dwd_total = con.execute(f"SELECT COUNT(*) FROM dwd_decision_latest WHERE dt='{dt}' AND decision='REJECT'").fetchone()[0]
    assert topn_total == dwd_total, f"拒绝总数不一致：TopN表={topn_total}, DWD={dwd_total}"
```

运行测试：

```bash
pytest tests/test_etl.py -v
```

**输出**：

```text
tests/test_etl.py::test_dws_channel_daily_apply_cnt PASSED
tests/test_etl.py::test_ads_overview_daily_consistency PASSED
tests/test_etl.py::test_reject_reason_topn_count PASSED
```

### 3.4 将对账与测试集成到调度（可选）

在 `run_full_etl.py` 最后增加：

```python
# 对账检查
subprocess.run(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/ads_vs_dws_reconcile.sql', '--out', 'reports/reconcile_ads.md'])
# 运行单元测试
subprocess.run(['pytest', 'tests/test_etl.py', '-v'])
```

## 4. 口径与边界说明

| 对账项       | 口径                                                         |
| :----------- | :----------------------------------------------------------- |
| ADS vs DWS   | `ads_overview_daily` 的申请量应与 `dws_channel_daily` 按日汇总一致；通过量、拒绝量同理。 |
| DWS vs DWD   | `dws_channel_daily` 中各渠道申请量应与 DWD 明细按渠道去重后的计数一致。 |
| 拒绝原因汇总 | `dws_reject_topn_daily` 中每日拒绝总数应与 DWD 中当日拒绝记录总数一致。 |
| 差异阈值     | 对账记录表设置差异绝对值阈值（≤5 为 OK，≤20 为 WARN，>20 为 ERROR），避免小差异误报。 |

## 5. 性能点

- 对账查询涉及全量 DWS 和 ADS 数据，数据量小（每天几十行），秒级完成。
- 单元测试仅抽样少数日期，不影响性能。
- 可在每日 ETL 完成后自动执行，作为质量检查环节。

## 10. 思考题

- 如果发现 ADS 与 DWS 数据不一致，如何快速定位是哪个环节出错？
  → 可逐层校验：先检查 DWS 与 DWD 是否一致，再检查 ADS 生成逻辑是否正确（如 SQL 是否误用聚合），必要时抽样对比。
- 单元测试中，除了抽样日期，还可以采用哪些方法提高测试覆盖率？
  → 边界值测试（如首尾日期）、空值测试（如无数据时）、大数据量压测、随机抽样多次等。
- 对账结果表中，如何设计告警规则，避免误报？
  → 可设置动态阈值（如基于历史波动范围计算标准差），或结合业务容忍度，对差异进行分级。