# 数据质量监控平台（Great Expectations/Deequ）- 迟到数据检测与处理

## 一、核心概念：迟到数据与监控平台定位

### 1. 迟到数据定义

迟到数据指「数据生成时间（事件日）与实际加载到数仓的时间（加载日）存在超出阈值的延迟」，常见于风控 / 数仓场景（如信贷交易事件发生在 2026-03-15，但 3 月 20 日才加载到 ODS 层），会导致数仓数据不完整、分析结果失真。

### 2. 监控平台核心价值

Great Expectations（Python 开源）、Deequ（Spark 生态，Java/Scala）可通过「自定义规则 + 自动化校验 + 告警 / 触发回补」，解决迟到数据的「检测→告警→处理」全流程，替代人工巡检，适配风控数仓 7×24 小时数据质量要求。

## 二、核心工具：迟到数据检测实现

### 1. Great Expectations（Python 生态，适配中小规模数仓）

#### 核心原理

通过定义「Expectation（数据期望规则）」验证数据新鲜度，支持本地 / 数仓数据校验，内置时间差、日期范围等校验函数，校验失败可触发告警（邮件 / 钉钉）或自动化流程。

#### 关键功能与实战代码

##### （1）基础规则：检测加载日与事件日的延迟阈值

```python
import great_expectations as ge
from datetime import datetime, timedelta

# 1. 加载数仓ODS层数据（以信贷申请数据为例）
df = ge.read_sql(
    sql="SELECT event_dt, load_dt FROM ods_credit_apply",
    connection_string="postgresql://user:password@host:port/db"
)

# 2. 定义迟到数据检测规则：加载日 ≤ 事件日 + 3天（N=3）
# 计算事件日与加载日的差值（天）
df["delay_days"] = (df["load_dt"] - df["event_dt"]).dt.days
# 期望：delay_days ≤ 3，超出则判定为迟到数据
expectation_result = df.expect_column_values_to_be_between(
    column="delay_days",
    min_value=None,  # 无下限
    max_value=3,     # 最大延迟3天
    meta={"description": "检测信贷申请数据是否迟到（延迟≤3天）"}
)

# 3. 校验结果处理：失败则告警/触发回补
if not expectation_result["success"]:
    # 输出迟到数据详情
    late_data = df[df["delay_days"] > 3]
    print(f"发现{len(late_data)}条迟到数据，事件日范围：{late_data['event_dt'].min()}~{late_data['event_dt'].max()}")
    # 触发告警（可对接钉钉/邮件API）
    send_alert(f"风控数仓ODS层迟到数据告警：{len(late_data)}条数据延迟超3天")
    # 触发数据回补流程（调用ETL脚本）
    trigger_data_backfill(late_data["event_dt"].unique())
```

##### （2）进阶规则：按批次校验数据新鲜度

针对每日增量加载的数仓场景，校验「当日加载数据是否包含前一日的全量事件数据」：

```python
# 定义批次期望：2026-03-16加载的数据中，必须包含2026-03-15的事件数据
batch_expectation = df.expect_column_to_have_data_for_date_range(
    column="event_dt",
    start_date=datetime.now() - timedelta(days=1),  # 前一日
    end_date=datetime.now() - timedelta(days=1),
    meta={"description": "校验前一日事件数据是否全部加载"}
)
# 若失败，说明前一日数据未加载（属于严重迟到）
if not batch_expectation["success"]:
    trigger_urgent_backfill()  # 紧急回补流程
```

#### 核心优势

- 可视化：可生成 HTML 校验报告，直观展示迟到数据分布；
- 可复用：规则可封装为「Expectation Suite」，接入 Airflow 每日调度；
- 适配性：支持 MySQL / 高斯 / PostgreSQL 等数仓，Python 生态易集成 ETL 脚本。

### 2. Deequ（Spark 生态，适配大规模数仓）

#### 核心原理

基于 Spark 分布式计算，通过「Analyzer+Check」定义数据质量规则，适合 TB 级风控数仓的迟到数据检测，支持 Spark SQL/DataFrame，适配 Java/Scala 开发（数仓工程师主流）。

#### 关键功能与实战代码（Scala）

```scala
import com.amazon.deequ.VerificationSuite
import com.amazon.deequ.checks.{Check, CheckLevel, CheckStatus}
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.{datediff, current_date, col}

// 1. 初始化Spark会话
val spark = SparkSession.builder().appName("late_data_check").getOrCreate()

// 2. 加载数仓DWD层数据（分布式读取）
val df = spark.sql("SELECT event_dt, load_dt FROM dwd_credit_apply")
// 计算延迟天数
val dfWithDelay = df.withColumn("delay_days", datediff(col("load_dt"), col("event_dt")))

// 3. 定义迟到数据检测规则
val verificationResult = VerificationSuite()
  .onData(dfWithDelay)
  .addCheck(
    Check(CheckLevel.Error, "迟到数据检测规则")
      // 规则1：延迟天数≤3天，失败则ERROR级别告警
      .isLessThanOrEqualTo("delay_days", 3)
      // 规则2：无缺失的事件日（避免数据完全未加载）
      .isComplete("event_dt")
  )
  .run()

// 4. 结果处理
if (verificationResult.status == CheckStatus.Failure) {
  // 输出失败详情
  val failures = verificationResult.checkResults.flatMap(_.constraintResults.filter(!_.success))
  failures.foreach(f => println(s"迟到数据校验失败：${f.message.get}"))
  // 触发告警与回补（对接数仓调度平台）
  triggerAlert(failures.map(_.message.get).mkString(","))
  triggerBackfillJob()
}
```

#### 核心优势

- 高性能：分布式计算，适配 50W + 风控数据的批量校验；
- 生态集成：无缝对接 Spark 数仓、Hive/Delta Lake，适合企业级数仓；
- 规则丰富：支持按分区、按字段分组校验迟到数据。

## 三、迟到数据处理流程（自动化落地）

### 1. 完整流程设计

![image-20260313172648222](..\docs\exported_image.png)

### 2. 关键规则配置（风控数仓适配）

| 场景         | 延迟阈值 | 校验规则                  | 处理动作                      |
| :----------- | :------- | :------------------------ | :---------------------------- |
| 信贷交易数据 | ≤1 天    | load_dt ≤ event_dt + 1 天 | 失败则立即告警 + 触发实时回补 |
| 客户信息数据 | ≤3 天    | load_dt ≤ event_dt + 3 天 | 失败则每日告警 + 批量回补     |
| 历史归档数据 | ≤7 天    | load_dt ≤ event_dt + 7 天 | 失败仅记录日志，每周统一处理  |

### 3. 回补流程实现（Python/Shell）

```bash
# 数据回补脚本（可由Great Expectations/Deequ触发）
#!/bin/bash
# 参数：需要回补的事件日期
event_date=$1
# 调用ETL脚本重新加载指定日期的数据
python /opt/etl/ods_credit_apply.py --event_date $event_date
# 加载完成后重新执行数据质量校验
python /opt/quality_check/late_data_check.py --event_date $event_date
```

## 四、工具选型与成都岗位适配

| 维度         | Great Expectations               | Deequ                             |
| :----------- | :------------------------------- | :-------------------------------- |
| 技术栈       | Python + 单机 / 小规模数据       | Spark + 分布式 / 大规模数据       |
| 学习成本     | 低（Python 易上手，文档丰富）    | 中（需掌握 Spark/Scala）          |
| 成都公司适配 | 中小金融科技公司（如新希望金融） | 头部银行 / 数仓企业（如成都银行） |
| 核心优势     | 可视化强，易集成 Airflow 调度    | 高性能，适配 TB 级风控数据        |

## 五、简历 / 面试重点表述

1. 核心能力表述：
   - “基于 Great Expectations 定义数据新鲜度校验规则，检测数仓迟到数据（加载日≤事件日 + 3 天），自动化触发告警与数据回补流程，保障风控数仓数据完整性”；
   - “了解 Deequ 分布式数据质量监控工具，适配大规模数仓迟到数据检测，掌握 Spark 生态下的延迟阈值校验规则设计”；
2. **技术关键词**：数据质量监控、Great Expectations、Deequ、迟到数据、数据新鲜度、自动化告警、数据回补。

## 六、避坑要点

1. **时间字段统一**：确保`event_dt`（事件日）和`load_dt`（加载日）为同一时区（如 UTC+8），避免时区差导致误判；
2. **阈值适配业务**：风控核心数据（交易、信贷申请）阈值设为 1 天，非核心数据（客户画像）可放宽至 3-7 天；
3. **避免重复校验**：按数据分区（如按 event_dt 分区）校验，仅校验当日新增分区，减少计算资源消耗；
4. **告警分级**：核心数据迟到触发紧急告警（电话 / 钉钉），非核心数据触发普通邮件告警，避免告警泛滥。

## 总结

1. 迟到数据监控的核心是「定义时间差阈值 + 自动化校验 + 触发处理流程」，Great Expectations 适配 Python 生态中小数仓，Deequ 适配 Spark 分布式大数仓；
2. 风控数仓场景需按数据重要性设置差异化延迟阈值，核心数据优先保障实时性；
3. 掌握监控规则设计与回补流程自动化，是成都金融 / 数仓岗位数据质量模块的核心竞争力。