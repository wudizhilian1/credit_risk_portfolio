# Day 51 实践报告（调整版）：项目文档完善 & 代码重构

## 1. 练习目标
- 完善项目文档，确保新人（或面试官）能根据文档快速理解并运行项目。
- 对核心代码进行重构，提高可读性、可维护性。
- 增加关键代码的注释和类型提示（Type Hints）。
- 为后续强化训练阶段打下扎实基础。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 数据库：DuckDB 0.10.0
- 项目路径：`C:\credit_risk_portfolio`
- 版本标签：v2.0（已发布）

## 3. 核心任务执行

### 3.1 文档完善
逐项检查并更新了以下文档：

| 文档                          | 检查内容                                                     | 状态     |
| ----------------------------- | ------------------------------------------------------------ | -------- |
| `README.md`                   | 项目简介、架构图、快速开始、核心指标、监控告警、调度测试、目录结构、版本记录 | ✅ 已补全 |
| `docs/lineage.md`             | 数据血缘图（Mermaid）包含所有表，节点颜色清晰                | ✅ 已更新 |
| `docs/metrics_definitions.md` | 涵盖所有 DWS/ADS/特征宽表字段，口径说明准确                  | ✅ 已完善 |
| `docs/data_quality_rules.md`  | 包含模型监控和特征稳定性规则                                 | ✅ 已添加 |
| `docs/scheduling.md`          | 注明默认处理昨天，支持历史回填                               | ✅ 已更新 |
| `docs/etl_design.md`          | 补充增量策略、幂等性、特征宽表构建流程                       | ✅ 已补充 |
| `docs/performance_tuning.md`  | 添加物化视图性能对比数据                                     | ✅ 已补充 |
| `docs/idempotency.md`         | 确认各层幂等策略描述清晰                                     | ✅ 已完善 |

**关键改进**：
- 在 `README.md` 中增加了“技术栈”徽章和“快速开始”一键命令说明。
- 在 `lineage.md` 中增加了特征宽表和模型评估节点，优化了图例。
- 在 `data_quality_rules.md` 中新增了模型 KS/PSI 监控规则和特征 PSI 监控规则。

### 3.2 代码重构

#### 3.2.1 统一日志规范
修改了以下脚本，将 `print` 替换为 `logging`：
- `scripts/run_full_etl.py`
- `scripts/etl_load_ods.py`
- `scripts/alert_engine.py`
- `scripts/run_sql.py`

**配置示例**（在 `run_full_etl.py` 中添加）：
```python
import logging

# 配置日志格式（时间、级别、消息）
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/etl.log'),  # 输出到文件
        logging.StreamHandler()               # 同时输出到控制台
    ]
)
logger = logging.getLogger(__name__)
```
所有关键步骤（开始、完成、错误）均使用 `logger.info` 或 `logger.error` 记录。

#### 3.2.2 添加函数类型提示
为 `run_full_etl.py` 中的核心函数添加类型提示：
```python
from typing import List

def run_subprocess(cmd_list: List[str]) -> None:
    ...
def generate_date_range(start_str: str, end_str: str) -> List[str]:
    ...
def insert_audit_run(dt_start: str, dt_end: str, args, status: str, error_msg: str = None) -> int:
    ...
```

#### 3.2.3 配置文件化
创建 `config.yaml`，放在项目根目录：
```yaml
database:
  path: dev.duckdb

etl:
  default_days_back: 1

logging:
  level: INFO
  file: logs/etl.log

monitoring:
  psi_threshold_warn: 0.1
  psi_threshold_error: 0.25
  ks_threshold_warn: 0.25
  ks_threshold_error: 0.20
```
修改 `run_full_etl.py` 读取配置：
```python
import yaml
# 修复：读取 yaml 时指定 UTF-8 编码，并增加异常处理
try:
    with open('config.yaml', 'r', encoding='utf-8') as f:  # 关键：添加 encoding='utf-8'
        config = yaml.safe_load(f)
except FileNotFoundError:
    print("错误：config.yaml 文件不存在，请检查文件路径！")
    sys.exit(1)
except Exception as e:
    print(f"读取 config.yaml 失败：{e}")
    sys.exit(1)
```

#### 3.2.4 SQL 脚本注释
为复杂 SQL 添加了注释，例如：
- `sql/etl/ods_to_dwd_apply.sql`：解释窗口函数去重逻辑。
- `sql/dq/psi_reject_reason.sql`：说明 PSI 公式和平滑处理。
- `sql/features/build_feature_broad.sql`：标注特征来源和窗口期。

### 3.3 单元测试扩充
在 `tests/test_etl.py` 中新增以下测试用例：

```python
def test_reject_topn_pct_sum(con):
    """ 测试dws_reject_topn_daily中比例加起来为100"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    pct = con.execute("""
        WITH base AS (
        SELECT * FROM dws_reject_topn_daily 
        GROUP BY dt,reason_code,reason_desc,reason_category,reject_cnt,pct,rn
        )
        SELECT SUM(pct)  FROM base GROUP BY dt limit 1
    """).fetchone()[0]
    assert abs(float(pct) - float(100)) < 0.01, "dws_reject_topn_daily比例总和不为100"

def test_feature_pred_score_range(con):
    """ 测试特征宽表 feature_apply_broad 中 pred_score 范围是否在 [0,1]。"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    max = con.execute("""
        SELECT MAX(pred_score) FROM feature_apply_broad 
    """).fetchone()[0]

    min = con.execute("""
            SELECT MIN(pred_score) FROM feature_apply_broad 
        """).fetchone()[0]
    assert float(max) < 1, "feature_apply_broad中pred_score最大值<1"
    assert float(min) > 0, "feature_apply_broad中pred_score最小值>0"

def test_mv_user_hist_consistency(con):
    """ 测试物化视图 mv_user_hist_30d 与原始查询结果一致（抽样对比）"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    base = con.execute("""
        SELECT COUNT(*) FROM mv_user_hist_30d
    """).fetchone()[0]

    compare = con.execute("""
            WITH base AS (
                SELECT
                    user_id,
                    COUNT(*) as apply_cnt_30d,
                    AVG(amount) AS avg_amount_30d,
                    AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_rate_30d
                FROM dwd_apply_latest a
                LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
                GROUP BY user_id
                )
                SELECT COUNT(a.*) as cnt FROM mv_user_hist_30d a inner join base b
                ON a.user_id = b.user_id AND a.apply_cnt_30d = b.apply_cnt_30d AND a.avg_amount_30d = b.avg_amount_30d
                AND a.pass_rate_30d = b.pass_rate_30d
        """).fetchone()[0]
    assert float(base) ==  float(compare), "mv_user_hist_30d 与原始查询结果一致"
```

运行 `pytest tests/ -v`，全部通过（8 个测试）。

### 3.4 代码格式化
使用 `black` 格式化 `scripts/` 目录下的 Python 文件：
```bash
black scripts/
```
格式化后代码风格统一，无语法错误。

### 3.5 Git 提交与标签
```bash
git add .
git commit -m "refactor: logging, config, type hints, tests, docs"
git push origin main
git tag -a v2.1-docs-refactor -m "Documentation and code refactoring"
git push origin v2.1-docs-refactor
```

## 4. 遇到的问题与解决方案

| 问题                                   | 原因                       | 解决方案                                                    |
| -------------------------------------- | -------------------------- | ----------------------------------------------------------- |
| `config.yaml` 读取失败                 | 脚本中路径未正确指向根目录 | 使用 `os.path.join(PROJECT_DIR, 'config.yaml')`             |
| 日志文件写入失败                       | `logs/` 目录不存在         | 在脚本开头添加 `os.makedirs('logs', exist_ok=True)`         |
| 单元测试中物化视图数据与原始查询不一致 | 物化视图未刷新             | 在测试前执行 `refresh_mv.sql`，或测试抽样日期确保视图已刷新 |
| `black` 格式化后某些行过长             | 默认行长度 88              | 可配置 `pyproject.toml` 调整，暂不处理                      |

## 5. 核心产出清单

### 文档
- 更新 8 个 Markdown 文档（README, lineage, metrics_definitions, data_quality_rules, scheduling, etl_design, performance_tuning, idempotency）
- 新增 `docs/resume_bullets.md`（简历描述）

### 代码
- 修改 `scripts/run_full_etl.py`, `etl_load_ods.py`, `alert_engine.py`, `run_sql.py`（logging + 类型提示）
- 新增 `config.yaml`
- 新增 3 个单元测试用例

### 其他
- Git 标签 `v2.1-docs-refactor`
- 日志文件 `logs/etl.log` 自动生成

## 6. 思考题
- 为什么需要统一日志规范？  
  → 便于调试、监控、生产环境问题排查，统一格式方便日志解析。
- 配置文件相比硬编码有哪些好处？  
  → 集中管理、灵活调整、避免代码修改，降低出错风险。
- 单元测试覆盖哪些关键逻辑？  
  → 去重、聚合计算、边界条件（空值、极值）、物化视图一致性、特征范围等。

---
**完成日期**：2026-04-07