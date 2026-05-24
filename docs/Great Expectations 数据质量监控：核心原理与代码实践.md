# Great Expectations 数据质量监控：核心原理与代码实践

## 一、Great Expectations 核心背景

### 1.1 什么是 Great Expectations（GE）

Great Expectations 是一款**开源的数据质量监控工具**，核心目标是解决数据团队的「数据可信度」问题：

- 用「可量化的期望（Expectation）」替代模糊的 “数据校验规则”；
- 支持数据探查、规则定义、自动化监控、可视化报告全流程；
- 兼容主流数据源（MySQL/Hive/Spark/Pandas 等），可无缝集成到数仓 / 建模流程中。

### 1.2 核心价值（对比传统自定义校验脚本）

| 维度       | 传统自定义脚本            | Great Expectations                                |
| :--------- | :------------------------ | :------------------------------------------------ |
| 规则定义   | 硬编码 if/else，复用性差  | 标准化 Expectation，支持 100 + 内置规则           |
| 可视化     | 无原生支持，需手动开发    | 自动生成交互式 HTML 报告，包含校验结果 + 数据概览 |
| 监控自动化 | 需手动对接调度（Airflow） | 内置 Checkpoint 机制，一键对接调度系统            |
| 数据溯源   | 无                        | 记录每次校验的批次、规则、结果，支持问题回溯      |
| 团队协作   | 规则分散在代码中，难共享  | 期望库（Expectation Suite）版本化管理，易协作     |

### 1.3 核心概念（必懂）

| 概念              | 定义                                              | 作用                                  |
| :---------------- | :------------------------------------------------ | :------------------------------------ |
| Expectation       | 数据质量规则（如「列值在 0-100 之间」）           | GE 的核心，所有校验均基于 Expectation |
| Expectation Suite | 一组 Expectation 的集合（如某张表的所有 DQ 规则） | 为特定数据集定义完整的质量标准        |
| Data Context      | GE 的核心配置对象，管理数据源、期望库、报告路径等 | 相当于 GE 的 “项目配置中心”           |
| Checkpoint        | 执行数据校验的入口，关联数据源 + 期望库           | 一键触发数据质量检查                  |
| Validation Result | 校验结果，包含是否通过、失败条数、异常值等        | 数据质量的量化输出                    |
| Data Docs         | 自动生成的可视化报告，展示期望规则 + 校验结果     | 非技术人员也能看懂的质量报告          |

## 二、快速上手：代码实现数据质量监控

### 2.1 环境准备

```bash
# 安装Great Expectations
pip install great-expectations
```

### 2.2 完整代码示例（监控 dws_channel_daily 表）

以监控数仓表 `dws_channel_daily` 为例，实现以下质量规则：

1. 核心字段 `dt` 非空；
2. 行数变化率不超过 ±20%（对比昨日）；
3. `row_cnt` 列值为非负整数；
4. `alert_level` 列值仅包含 ['OK', 'WARN', 'ERROR', 'INFO']。

```python
import great_expectations as ge
from great_expectations.core.batch import RuntimeBatchRequest
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# ===================== 步骤1：初始化Data Context（项目配置） =====================
# 方式1：初始化全新项目（首次运行）
# context = ge.data_context.DataContext.create(project_root_dir="./great_expectations")

# 方式2：加载已有项目（后续运行）
context = ge.data_context.DataContext()

# ===================== 步骤2：定义数据源（以Pandas为例，可替换为Spark/Hive） =====================
# 模拟加载dws_channel_daily表数据（实际场景替换为数据库查询）
def load_dws_channel_daily(dt: str) -> pd.DataFrame:
    """加载指定日期的dws_channel_daily表数据"""
    # 实际场景替换为数据库查询：
    # con = create_db_connection()  # 自定义数据库连接函数
    # df = con.execute(f"SELECT * FROM dws_channel_daily WHERE dt = '{dt}'").fetchdf()
    
    # 模拟数据
    np.random.seed(42)
    data = {
        "dt": [dt]*1000,
        "channel_id": np.random.randint(1, 100, 1000),
        "row_cnt": np.random.randint(0, 10000, 1000),
        "alert_level": np.random.choice(['OK', 'WARN', 'ERROR', 'INFO'], 1000)
    }
    # 插入少量异常数据（用于测试校验）
    data["dt"][0] = None  # 空值
    data["row_cnt"][1] = -100  # 负值
    data["alert_level"][2] = "INVALID"  # 非法值
    return pd.DataFrame(data)

# 加载今日数据
today = (datetime.now()).strftime("%Y-%m-%d")
df_today = load_dws_channel_daily(today)
# 加载昨日数据（用于行数变化率校验）
yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
df_yesterday = load_dws_channel_daily(yesterday)

# ===================== 步骤3：创建Batch Request（数据批次） =====================
# 将Pandas DataFrame包装为GE可识别的Batch
batch_request = RuntimeBatchRequest(
    datasource_name="pandas_datasource",  # 需在great_expectations.yml中配置
    data_connector_name="default_runtime_data_connector_name",
    data_asset_name="dws_channel_daily",  # 数据集名称
    runtime_parameters={"batch_data": df_today},  # 传入待校验数据
    batch_identifiers={"dt": today}  # 批次标识（如日期）
)

# ===================== 步骤4：定义期望规则（Expectation Suite） =====================
# 创建/加载期望库
suite_name = "dws_channel_daily_suite"
if suite_name not in context.list_expectation_suite_names():
    context.create_expectation_suite(expectation_suite_name=suite_name, overwrite_existing=True)
suite = context.get_expectation_suite(expectation_suite_name=suite_name)

# 获取Validator（校验器，用于定义期望）
validator = context.get_validator(
    batch_request=batch_request,
    expectation_suite=suite
)

# -------------------- 4.1 基础字段校验 --------------------
# 1. dt列非空
validator.expect_column_values_to_not_be_null(column="dt")
# 2. row_cnt列值≥0
validator.expect_column_values_to_be_between(
    column="row_cnt",
    min_value=0,
    max_value=None,
    result_format="COMPLETE"  # 返回详细校验结果
)
# 3. alert_level列值仅包含指定枚举值
validator.expect_column_values_to_be_in_set(
    column="alert_level",
    value_set=["OK", "WARN", "ERROR", "INFO"]
)

# -------------------- 4.2 自定义规则：行数变化率校验 --------------------
# 计算今日/昨日行数
today_row_count = len(df_today)
yesterday_row_count = len(df_yesterday)
# 定义行数变化率期望（自定义Expectation）
row_count_change_pct = (today_row_count - yesterday_row_count) / max(yesterday_row_count, 1) * 100
validator.expectation_suite.add_expectation(
    {
        "expectation_type": "expect_custom_sql_expression_to_be_between",
        "kwargs": {
            "sql_expression": f"ABS(({today_row_count} - {yesterday_row_count}) / {max(yesterday_row_count, 1)} * 100)",
            "min_value": 0,
            "max_value": 20,
            "meta": {
                "description": "行数变化率不超过±20%"
            }
        }
    }
)

# 保存期望库
validator.save_expectation_suite(discard_failed_expectations=False)

# ===================== 步骤5：执行校验（Checkpoint） =====================
# 定义Checkpoint配置
checkpoint_config = {
    "name": "dws_channel_daily_checkpoint",
    "config_version": 1.0,
    "class_name": "SimpleCheckpoint",
    "run_name_template": "%Y%m%d-%H%M%S-dws-channel-daily-validation",
    "validations": [
        {
            "batch_request": batch_request,
            "expectation_suite_name": suite_name
        }
    ]
}
# 添加Checkpoint到Context
context.add_checkpoint(**checkpoint_config)

# 执行校验
checkpoint_result = context.run_checkpoint(checkpoint_name="dws_channel_daily_checkpoint")

# ===================== 步骤6：生成数据文档（可视化报告） =====================
# 构建并打开数据文档
context.build_data_docs()
context.open_data_docs()

# ===================== 步骤7：解析校验结果 =====================
print("=== 数据质量校验结果 ===")
validation_result = checkpoint_result.list_validation_results()[0]
# 整体结果
print(f"校验是否通过：{validation_result['success']}")
# 详细规则结果
for result in validation_result["results"]:
    print(f"\n规则：{result['expectation_config']['expectation_type']}")
    print(f"列名：{result['expectation_config']['kwargs'].get('column', '自定义规则')}")
    print(f"是否通过：{result['success']}")
    if not result["success"]:
        print(f"失败详情：{result['result']}")
```

### 2.3 关键代码说明

#### （1）数据源适配

- 示例中用 Pandas 加载数据，实际场景可替换为：

  - **数据库**：配置 `SqlAlchemyDatasource` 对接 MySQL/Hive/Trino；
  - **Spark**：配置 `SparkDFDatasource` 对接 Spark DataFrame；
  - **文件**：配置 `PandasFilesystemDatasource` 对接 CSV/Parquet。

  

#### （2）核心 Expectation 规则

GE 内置 100 + 常用 Expectation，覆盖 90% 的数据质量场景：

| 常用 Expectation                                 | 用途                       |
| :----------------------------------------------- | :------------------------- |
| `expect_column_values_to_not_be_null`            | 列非空校验                 |
| `expect_column_values_to_be_between`             | 数值范围校验               |
| `expect_column_values_to_be_in_set`              | 枚举值校验                 |
| `expect_column_unique_value_count_to_be_between` | 唯一值数量校验             |
| `expect_column_kl_divergence_to_be_less_than`    | 分布一致性校验（对比基准） |
| `expect_row_count_to_be_between`                 | 行数范围校验               |

#### （3）自定义 Expectation

若内置规则不满足需求（如行数变化率），可：

1. 使用 `expect_custom_sql_expression_to_be_between` 执行自定义 SQL 表达式；
2. 开发自定义 Expectation 类（进阶）。

## 三、自动化监控落地

### 3.1 调度集成（对接 Airflow）

```python
# Airflow DAG示例
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'data_team',
    'retries': 1,
    'retry_delay': timedelta(minutes=5)
}

def run_ge_validation():
    # 复用上述GE校验代码
    context = ge.data_context.DataContext()
    checkpoint_result = context.run_checkpoint(checkpoint_name="dws_channel_daily_checkpoint")
    # 校验失败则抛出异常，触发Airflow告警
    if not checkpoint_result["success"]:
        raise Exception("数据质量校验失败！")

with DAG(
    dag_id="dws_channel_daily_dq_monitor",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 8 * * *",  # 每天8点执行
    catchup=False
) as dag:
    validate_task = PythonOperator(
        task_id="ge_validation",
        python_callable=run_ge_validation
    )

validate_task
```

### 3.2 告警集成

GE 支持将校验结果推送到：

- 邮件 / 钉钉 / 企业微信（通过自定义回调函数）；
- Slack/PagerDuty（内置集成）；
- 数据质量平台（通过 Validation Result API 输出）。

示例：校验失败发送钉钉告警

```python
import requests

def send_dingding_alert(validation_result):
    """校验失败发送钉钉告警"""
    if not validation_result["success"]:
        failed_rules = [r["expectation_config"]["expectation_type"] for r in validation_result["results"] if not r["success"]]
        msg = f"""
        【数据质量告警】
        表名：dws_channel_daily
        日期：{today}
        失败规则：{','.join(failed_rules)}
        详情：http://your-data-docs-url
        """
        # 钉钉机器人Webhook
        url = "https://oapi.dingtalk.com/robot/send?access_token=your-token"
        requests.post(url, json={"msgtype": "text", "text": {"content": msg}})

# 执行校验后调用
send_dingding_alert(validation_result)
```

## 四、现有 DQ 规则迁移到 GE

### 4.1 迁移步骤

1. **梳理现有规则**：将自定义 DQ 脚本中的规则拆解为 GE 的 Expectation；

2. 映射规则类型

   ：

   - 空值校验 → `expect_column_values_to_not_be_null`；
   - 数值范围 → `expect_column_values_to_be_between`；
   - 枚举值 → `expect_column_values_to_be_in_set`；
   - 自定义逻辑 → 自定义 Expectation/SQL 表达式；

   

3. **批量导入规则**：通过 GE 的 CLI/API 批量创建 Expectation Suite；

4. **替换调度**：将原有校验脚本替换为 GE 的 Checkpoint + Airflow 调度；

5. **可视化升级**：启用 Data Docs，替换原有自定义报表。

### 4.2 迁移示例（行数监控规则）

原有 SQL 行数监控规则 → GE Expectation：

```python
# 原有逻辑：行数变化率±20%
# GE迁移：自定义SQL表达式校验
validator.expectation_suite.add_expectation(
    {
        "expectation_type": "expect_custom_sql_expression_to_be_between",
        "kwargs": {
            "sql_expression": """
                ABS(
                    (SELECT COUNT(*) FROM dws_channel_daily WHERE dt = '{today}') -
                    (SELECT COUNT(*) FROM dws_channel_daily WHERE dt = '{yesterday}')
                ) / NULLIF(
                    (SELECT COUNT(*) FROM dws_channel_daily WHERE dt = '{yesterday}'), 0
                ) * 100
            """.format(today=today, yesterday=yesterday),
            "min_value": 0,
            "max_value": 20,
            "meta": {"description": "行数变化率不超过±20%"}
        }
    }
)
```

## 五、总结

### 核心要点

1. **GE 核心价值**：标准化数据质量规则、自动生成可视化报告、支持自动化监控；

2. **核心流程**：初始化 Context → 定义数据源 → 编写 Expectation → 执行 Checkpoint → 生成 Data Docs；

3. **规则迁移**：将现有 DQ 规则映射为 GE 内置 / 自定义 Expectation，替换原有调度即可完成迁移；

4. 落地建议

   ：

   - 先从核心表（如 dws_channel_daily）试点，再推广到全量表；
   - 优先使用内置 Expectation，自定义规则仅用于特殊场景；
   - 结合 Airflow 调度 + 钉钉 / 邮件告警，实现端到端自动化。

   

### 后续学习方向

1. 学习 GE 的 Profiler 功能，自动生成初始 Expectation Suite；
2. 对接数据湖 / 数仓（如 Delta Lake/Hive），支持大规模数据校验；
3. 开发自定义 Expectation，适配业务专属规则；
4. 集成 ML 模型监控（如特征分布漂移检测）。