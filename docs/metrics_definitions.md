# 指标口径定义文档

本文档定义了信贷风控数仓项目中的所有核心指标口径，涵盖 ODS、DWD、DWS、ADS 各层。所有指标均遵循统一的业务含义和计算逻辑，确保数据一致性和可解释性。

---

## 1. 核心事实指标

### 1.1 申请量 (apply_cnt)
- **定义**：指定时间范围内（通常按天）的申请单总数。
- **计算公式**：`COUNT(DISTINCT apply_id)`
- **数据来源**：`dwd_apply_latest`（已去重，每个 `apply_id` 一条记录）
- **维度**：`dt`（日期）、`channel_id`（渠道）、`user_id`（用户）等
- **边界条件**：
  - 同一 `apply_id` 只计一次（DWD 已去重）。
  - 若某天无数据，则申请量为 0。
- **应用场景**：监控整体业务量、渠道流量分析。

### 1.2 通过量 (pass_cnt)
- **定义**：指定时间范围内，最终决策结果为“通过”的申请数。
- **计算公式**：`COUNT(DISTINCT CASE WHEN decision = 'PASS' THEN apply_id END)`
- **数据来源**：关联 `dwd_apply_latest` 与 `dwd_decision_latest`（取最新决策）
- **边界条件**：
  - 若申请无对应决策记录，则不计入通过量。
  - 若同一申请有多个决策，`dwd_decision_latest` 已取最新，因此直接关联即可。
- **应用场景**：评估审批通过率、渠道质量。

### 1.3 拒绝量 (reject_cnt)
- **定义**：指定时间范围内，最终决策结果为“拒绝”的申请数。
- **计算公式**：`COUNT(DISTINCT CASE WHEN decision = 'REJECT' THEN apply_id END)`
- **数据来源**：同通过量。
- **应用场景**：监控拒绝率、策略收紧程度。

### 1.4 人工审核量 (review_cnt)
- **定义**：指定时间范围内，最终决策结果为“人工审核”的申请数。
- **计算公式**：`COUNT(DISTINCT CASE WHEN decision = 'REVIEW' THEN apply_id END)`
- **数据来源**：同通过量。
- **应用场景**：评估需要人工介入的申请比例，优化自动化策略。

---

## 2. 比率指标

### 2.1 通过率 (pass_rate)
- **定义**：通过量占申请量的百分比。
- **计算公式**：`pass_cnt / apply_cnt * 100`
- **边界条件**：当 `apply_cnt = 0` 时，通过率为 `NULL`（表示无意义）。
- **应用场景**：核心业务指标，反映审批宽松程度。

### 2.2 拒绝率 (reject_rate)
- **定义**：拒绝量占申请量的百分比。
- **计算公式**：`reject_cnt / apply_cnt * 100`
- **边界条件**：当 `apply_cnt = 0` 时，拒绝率为 `NULL`。
- **应用场景**：监控策略风险控制效果。

### 2.3 人工审核率 (review_rate)
- **定义**：人工审核量占申请量的百分比。
- **计算公式**：`review_cnt / apply_cnt * 100`
- **应用场景**：评估自动化覆盖度。

---

## 3. 维度指标

### 3.1 渠道维度
- **渠道 ID** (`channel_id`)：申请来源渠道的唯一标识。
- **渠道名称** (`channel_name`)：取自 `dim_channel` 维表，如“手机应用”、“网页端”。
- **渠道分组** (`channel_group`)：渠道所属分组（如“自有”、“外部”），用于更高层次的汇总分析。
- **计算口径**：所有事实指标均可按 `channel_id` 分组计算，得到各渠道的申请量、通过率等。

### 3.2 策略维度
- **策略版本** (`strategy_version`)：决策所采用的策略版本号。
- **策略名称** (`strategy_name`)：取自 `dim_strategy` 维表，如“基础审批策略”。
- **策略类型** (`strategy_type`)：策略类别（如“准入”、“反欺诈”、“额度”）。
- **计算口径**：按策略版本分组统计申请量、通过率、拒绝率，用于评估不同策略的效果。

### 3.3 拒绝原因维度
- **拒绝原因代码** (`reason_code`)：拒绝原因的标准编码，如 `FRAUD`、`RISK_SCORE`。
- **拒绝原因描述** (`reason_desc`)：取自 `dim_reject_reason` 维表，如“欺诈风险”、“风险评分不足”。
- **拒绝原因类别** (`reason_category`)：原因所属类别（如“信用”、“欺诈”、“规则”），用于更高层次的汇总分析。
- **计算口径**：拒绝原因相关指标均基于 `dwd_decision_latest` 中 `decision='REJECT'` 的记录，并按 `reason_code` 分组统计。

### 3.4 客群分层维度
在客群分层分析中，定义了以下分层维度：
- **客户类型** (`customer_type`)：基于用户注册日期划分，取值 `'新客'`（注册 ≤ 30天）、`'老客'`（注册 > 30天）、`'未知'`（注册日期缺失）。
- **额度区间** (`amount_bucket`)：基于申请金额 `amount` 划分：
  - `'小额'`：`amount < 5000`
  - `'中额'`：`5000 ≤ amount ≤ 20000`
  - `'大额'`：`amount > 20000`
  - （阈值可根据业务调整）
- **渠道分组** (`channel_group`)：同 3.1 节。

---

## 4. DWS 层汇总表指标

### 4.1 `dws_channel_daily`（渠道日报）
| 字段名       | 类型         | 口径说明                       |
| ------------ | ------------ | ------------------------------ |
| dt           | DATE         | 统计日期                       |
| channel_id   | VARCHAR      | 渠道 ID                        |
| channel_name | VARCHAR      | 渠道名称（关联 `dim_channel`） |
| apply_cnt    | INT          | 当日该渠道的申请量             |
| pass_cnt     | INT          | 当日该渠道的通过量             |
| reject_cnt   | INT          | 当日该渠道的拒绝量             |
| review_cnt   | INT          | 当日该渠道的人工审核量         |
| pass_rate    | DECIMAL(5,2) | 通过率（%）                    |
| reject_rate  | DECIMAL(5,2) | 拒绝率（%）                    |

### 4.2 `dws_strategy_daily`（策略日报）
| 字段名           | 类型         | 口径说明                                               |
| ---------------- | ------------ | ------------------------------------------------------ |
| dt               | DATE         | 统计日期                                               |
| strategy_version | VARCHAR      | 策略版本                                               |
| strategy_name    | VARCHAR      | 策略名称（关联 `dim_strategy`）                        |
| apply_cnt        | INT          | 当日该策略版本覆盖的申请量（即使用该策略决策的申请数） |
| pass_cnt         | INT          | 当日该策略版本的通过量                                 |
| reject_cnt       | INT          | 当日该策略版本的拒绝量                                 |
| review_cnt       | INT          | 当日该策略版本的人工审核量                             |
| pass_rate        | DECIMAL(5,2) | 通过率（%）                                            |
| reject_rate      | DECIMAL(5,2) | 拒绝率（%）                                            |

### 4.3 `dws_reject_topn_daily`（拒绝原因 TopN）
| 字段名          | 类型         | 口径说明                                 |
| --------------- | ------------ | ---------------------------------------- |
| dt              | DATE         | 统计日期                                 |
| reason_code     | VARCHAR      | 拒绝原因代码（NULL 处理为 `'UNKNOWN'`）  |
| reason_desc     | VARCHAR      | 拒绝原因描述（关联 `dim_reject_reason`） |
| reason_category | VARCHAR      | 拒绝原因类别                             |
| reject_cnt      | INT          | 该原因当日的拒绝次数                     |
| pct             | DECIMAL(5,2) | 该原因占当日总拒绝次数的百分比           |
| rn              | INT          | 按拒绝次数降序排列的排名（TopN）         |
- **计算公式**：`pct = 100 * reject_cnt / 当日总拒绝次数`
- **数据来源**：`dwd_decision_latest` 且 `decision='REJECT'`，按 `dt` 和 `reject_reason` 分组聚合。

### 4.4 `dws_reject_stability`（拒绝原因稳定性监控）
| 字段名      | 类型         | 口径说明                         |
| ----------- | ------------ | -------------------------------- |
| reason_code | VARCHAR      | 拒绝原因代码                     |
| reason_desc | VARCHAR      | 拒绝原因描述                     |
| cnt_today   | INT          | 今日拒绝次数                     |
| cnt_prev    | INT          | 参考日（如 7 天前）拒绝次数      |
| pct_today   | DECIMAL(5,2) | 今日占比                         |
| pct_prev    | DECIMAL(5,2) | 参考日占比                       |
| diff_pct    | DECIMAL(5,2) | 占比差值（pct_today - pct_prev） |
- **计算公式**：`pct_today = 100 * cnt_today / 今日总拒绝次数`，`pct_prev` 同理，`diff_pct = pct_today - pct_prev`。
- **数据来源**：基于 `dws_reject_topn_daily` 的两日数据，通过 `FULL OUTER JOIN` 合并。

### 4.5 `dws_segment_daily`（客群分层日报）
| 字段名        | 类型         | 口径说明                               |
| ------------- | ------------ | -------------------------------------- |
| dt            | DATE         | 统计日期                               |
| customer_type | VARCHAR      | 客户类型：`'新客'`、`'老客'`、`'未知'` |
| amount_bucket | VARCHAR      | 额度区间：`'小额'`、`'中额'`、`'大额'` |
| channel_group | VARCHAR      | 渠道分组：`'自有'`、`'外部'`、`'其他'` |
| apply_cnt     | INT          | 该客群当日的申请量                     |
| pass_cnt      | INT          | 该客群当日的通过量                     |
| reject_cnt    | INT          | 该客群当日的拒绝量                     |
| review_cnt    | INT          | 该客群当日的人工审核量                 |
| pass_rate     | DECIMAL(5,2) | 通过率（%）                            |
| reject_rate   | DECIMAL(5,2) | 拒绝率（%）                            |
- **分层口径**：
  - `customer_type`：基于 `dim_customer.registration_date` 与申请日 `dt` 的天数差，≤30 天为新客，>30 天为老客，无注册日期为“未知”。
  - `amount_bucket`：按金额阈值划分（默认 `<5000` 小额，`5000~20000` 中额，`>20000` 大额）。
  - `channel_group`：取自 `dim_channel`，若无则“其他”。

### 4.6 `dws_strategy_hit_daily`（策略命中率日报）
| 字段名           | 类型         | 口径说明                                                   |
| ---------------- | ------------ | ---------------------------------------------------------- |
| dt               | DATE         | 统计日期                                                   |
| strategy_version | VARCHAR      | 策略版本                                                   |
| strategy_name    | VARCHAR      | 策略名称（关联 `dim_strategy`）                            |
| apply_cnt        | INT          | 当日该策略版本覆盖的申请量                                 |
| pass_cnt         | INT          | 当日该策略版本的通过量                                     |
| hit_cnt          | INT          | 当日该策略版本的命中量（拒绝 + 人工审核）                  |
| pass_rate        | DECIMAL(5,2) | 通过率（%）                                                |
| hit_rate         | DECIMAL(5,2) | 命中率（%）：`(reject_cnt + review_cnt) / apply_cnt * 100` |
- **命中定义**：决策结果为 `'REJECT'` 或 `'REVIEW'`，反映策略拒绝或转人工的比例。

### 4.7 `dws_segment_strategy_daily`（客群与策略交叉分析）
| 字段名           | 类型         | 口径说明                               |
| ---------------- | ------------ | -------------------------------------- |
| dt               | DATE         | 统计日期                               |
| customer_type    | VARCHAR      | 客户类型：`'新客'`、`'老客'`、`'未知'` |
| amount_bucket    | VARCHAR      | 额度区间：`'小额'`、`'中额'`、`'大额'` |
| strategy_version | VARCHAR      | 策略版本                               |
| strategy_name    | VARCHAR      | 策略名称（关联 `dim_strategy`）        |
| apply_cnt        | INT          | 当日该交叉分组的申请量                 |
| pass_cnt         | INT          | 当日该交叉分组的通过量                 |
| reject_cnt       | INT          | 当日该交叉分组的拒绝量                 |
| review_cnt       | INT          | 当日该交叉分组的人工审核量             |
| pass_rate        | DECIMAL(5,2) | 通过率（%）                            |
| reject_rate      | DECIMAL(5,2) | 拒绝率（%）                            |
- **分层口径**：
  - `customer_type`：同 4.5。
  - `amount_bucket`：同 4.5。
  - `strategy_version`：取自决策表，若缺失则归为“未知策略”。
  - `strategy_name`：关联 `dim_strategy`，若无则“未知”。
- **应用场景**：用于观察同一策略在不同客群上的效果差异，支持精细化策略调优。

---

## 5. ADS 层应用表指标

### 5.1 `ads_overview_daily`（每日总览）
| 字段名          | 类型          | 口径说明                        |
| --------------- | ------------- | ------------------------------- |
| dt              | DATE          | 统计日期                        |
| apply_cnt       | INT           | 当日总申请量（来自 DWS 汇总）   |
| pass_cnt        | INT           | 当日总通过量                    |
| reject_cnt      | INT           | 当日总拒绝量                    |
| review_cnt      | INT           | 当日总人工审核量                |
| pass_rate       | DECIMAL(5,2)  | 通过率（%）                     |
| reject_rate     | DECIMAL(5,2)  | 拒绝率（%）                     |
| review_rate     | DECIMAL(5,2)  | 人工审核率（%）                 |
| avg_amount      | DECIMAL(12,2) | 平均申请金额（从 DWD 明细计算） |
| unique_user_cnt | INT           | 独立用户数（从 DWD 明细计算）   |
- **数据来源**：`dws_channel_daily` 按 `dt` 汇总 + 从 `dwd_apply_latest` 计算平均金额和独立用户数。
- **应用场景**：核心指标趋势监控，支持折线图展示。

### 5.2 `ads_channel_quality`（渠道质量榜）
| 字段名        | 类型          | 口径说明                                                     |
| ------------- | ------------- | ------------------------------------------------------------ |
| stat_date     | DATE          | 统计日期（通常按月）                                         |
| channel_id    | VARCHAR       | 渠道 ID                                                      |
| channel_name  | VARCHAR       | 渠道名称                                                     |
| apply_cnt     | INT           | 当月该渠道总申请量                                           |
| pass_rate     | DECIMAL(5,2)  | 当月该渠道通过率（%）                                        |
| reject_rate   | DECIMAL(5,2)  | 当月该渠道拒绝率（%）                                        |
| ps_30d        | DECIMAL(10,6) | 近 30 天 PSI（与整体分布对比，暂未计算）                     |
| quality_score | DECIMAL(5,2)  | 综合质量得分（示例公式：`pass_rate * 0.6 + (apply_cnt / max_apply) * 0.4`） |
| rank          | INT           | 得分排名（1 表示最佳）                                       |
- **数据来源**：从 `dws_channel_daily` 按月汇总，质量得分和排名可自定义。
- **应用场景**：渠道表现对比，辅助渠道策略调整。

### 5.3 `ads_reject_drilldown`（拒绝原因钻取表）
| 字段名           | 类型          | 口径说明                                 |
| ---------------- | ------------- | ---------------------------------------- |
| dt               | DATE          | 统计日期                                 |
| reason_code      | VARCHAR       | 拒绝原因代码（NULL 统一为 `'UNKNOWN'`）  |
| reason_desc      | VARCHAR       | 拒绝原因描述（关联 `dim_reject_reason`） |
| apply_id         | VARCHAR       | 申请单 ID                                |
| user_id          | VARCHAR       | 用户 ID                                  |
| channel_name     | VARCHAR       | 渠道名称（关联 `dim_channel`）           |
| amount           | DECIMAL(18,2) | 申请金额                                 |
| strategy_version | VARCHAR       | 决策时使用的策略版本                     |
| decision_time    | TIMESTAMP     | 决策时间戳                               |
- **抽样规则**：每个原因每天取最新（按 `decision_time`）的 5 条记录，用于业务复查。
- **数据来源**：从 `dwd_decision_latest` 和 `dwd_apply_latest` 关联，并关联维表获取可读字段。
- **应用场景**：当发现某拒绝原因占比异常时，可快速查看具体申请样例，辅助根因分析。

---

## 6. 补充说明
- **数据更新频率**：DWD 层每日更新，DWS/ADS 层每日刷新（全量或增量），确保指标反映最新数据。
- **空值处理**：所有比率指标分母为零时返回 `NULL`，避免除零错误；计数类指标自动忽略 `NULL`；拒绝原因 NULL 统一为 `'UNKNOWN'`；策略版本 NULL 统一为 `'未知策略'`。
- **维度退化**：部分维度（如 `channel_name`）已退化至事实表，但通过维表关联保持一致性。
- **版本管理**：本文档随项目迭代更新，历史变更记录见末尾。

---
**文档版本：v1.5**  
**最后更新：2026-03-22**  
**更新内容：新增 ADS 层钻取表 `ads_reject_drilldown` 指标口径。**