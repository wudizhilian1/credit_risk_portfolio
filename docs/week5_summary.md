# Week 5 项目总结（Day 29-35）

## 本周完成工作
- **DWS 层核心表构建**：
  - 渠道日报表 `dws_channel_daily`（按渠道汇总申请量、通过率、拒绝率）
  - 策略日报表 `dws_strategy_daily`（按策略版本汇总核心指标）
  - 拒绝原因 TopN 表 `dws_reject_topn_daily`（每日拒绝原因分布及占比）
  - 客群分层日报表 `dws_segment_daily`（按新老客、额度区间、渠道分组汇总）
  - 策略命中率表 `dws_strategy_hit_daily`（增加命中量/率指标）
  - 客群×策略交叉分析表 `dws_segment_strategy_daily`（精细化策略评估）
- **数据质量监控**：
  - 建立 DWS 层行数波动监控（日环比超阈值告警）
  - 关键字段空值监控（策略名称、渠道名称）
  - 负值检测（申请量、拒绝量等）
  - PSI 稳定性监控（拒绝原因分布对比）
- **异常 RCA 分析**：
  - 编写渠道维度贡献拆解 SQL，定位通过率变化的主要贡献渠道
  - 针对特定渠道（如 WEB）进行拒绝原因贡献拆解
- **文档与产出**：
  - 更新指标口径文档 `metrics_definitions.md`，补充所有 DWS 表字段说明
  - 更新数据质量规则文档 `data_quality_rules.md`
  - 编写一键验证脚本 `run_week5_validation.sql`

## 遇到的问题与解决方案
| 问题                         | 影响           | 解决方案                                       |
| ---------------------------- | -------------- | ---------------------------------------------- |
| PSI 计算中 NULL 值导致除零   | PSI 计算失败   | 使用 `COALESCE` 和 `1e-6` 平滑处理             |
| 行数波动阈值过高，漏报小波动 | 监控灵敏度不足 | 将阈值从 30% 下调至 20%，增加 WARN 级别        |
| 交叉分析表数据量膨胀         | 存储压力       | 仅保留必要维度组合，按日增量更新（未实现全量） |

## 核心产出清单
- SQL 脚本：6 个 DWS 表建表及刷新脚本
- 监控脚本：`dq_dws_monitor.sql`, `psi_reject_reason.sql`
- RCA 脚本：`apply_rate_change_contrib.sql`, `reason_contrib_channel.sql`
- 验证脚本：`run_week5_validation.sql`
- 文档更新：`metrics_definitions.md`, `data_quality_rules.md`

## 下周计划（Day 36-42）
- **ADS 层构建**：设计风控看板（总览、渠道质量榜、拒绝原因钻取等）
- **工程化**：将 ETL 脚本纳入调度（Airflow/简单 cron），实现自动化执行
- **性能优化**：对核心查询进行 Explain 分析，优化索引或分区策略
- **简历项目**：开始撰写项目描述和面试讲解稿

## 个人收获
- 深入理解了 DWS 层设计原则：预聚合常用维度，避免重复计算
- 掌握了数据质量监控体系的搭建方法，包括行数波动、空值检测、PSI 等
- 通过 RCA 拆解，学会了从多维度定位指标变化根因
- 提升了文档规范意识，确保项目可维护性和可扩展性