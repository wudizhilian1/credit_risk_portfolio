# Week 4 项目总结（Day 22-28）

## 本周完成工作

### Day 22：raw → ODS 加载

- 编写 Python ETL 脚本 `etl_load_ods.py`，实现按日期从视图加载数据到 ODS 表，并记录输入输出行数到审计表 `etl_audit`。
- 支持幂等操作（先删后插），确保重复执行结果一致。
- 批量测试了 1 月全量数据的加载，验证行数匹配。

### Day 23：ODS → DWD 去重

- 编写 SQL 脚本 `ods_to_dwd_apply.sql` 和 `ods_to_dwd_decision.sql`，使用窗口函数对 ODS 表按 `update_time`/`decision_time` 取最新记录，刷新 DWD 表。
- 发现 `dwd_apply_latest` 之前是视图导致无法 `DELETE`，修正为基表。
- 验证去重后行数符合预期（重复数据被正确过滤）。

### Day 24：策略命中明细清洗

- 创建模拟脏数据表 `ods_rule_hit`，包含多种格式不一的 `hit_flag`、`hit_time` 等。
- 编写清洗脚本 `ods_rule_hit_clean.sql`，将 `hit_flag` 标准化为布尔值，`hit_time` 转为时间戳，过滤空 `apply_id`。
- 更新数据质量规则文档 `docs/data_quality_rules.md`。

### Day 25：迟到数据策略

- 在 ODS 中模拟插入迟到记录（事件日 2024-01-01，加载日 2024-01-03）。
- 编写识别迟到数据的 SQL，对比按加载日与按事件日统计的差异。
- 创建按事件日分区的表 `dwd_apply_by_event`，并编写加载脚本 `load_to_event_date_table.sql`。
- 撰写迟到数据策略文档 `docs/late_data_strategy.md`。

### Day 26：三层对账

- 编写对账脚本 `reconcile_3layer_apply.sql`，对比 raw（视图）、ODS、DWD 三层的行数、唯一主键数、金额总和。
- 创建对账汇总表 `reconcile_summary`，记录每日对账结果。
- 提取差异样本脚本，帮助定位不一致原因。

### Day 27：性能优化

- 选择 3 条核心 SQL（去重、UV 计算、漏斗分析）进行优化前后对比。
- 使用 `EXPLAIN (analyze)` 分析执行计划，优化技巧包括：避免窗口全排序、先去重再聚合、JOIN 前过滤。
- 优化后执行时间平均提升 20%~30%，撰写性能报告 `reports/day27_performance.md`。

### Day 28：全链路里程碑验证

- 整合所有 ETL 步骤，编写一键执行脚本 `run_full_etl.py`，支持传入日期参数。
- 解决子进程调用时的数据库文件锁冲突问题（改用 Python 直接执行摘要插入）。
- 成功运行 `2024-01-15` 全流程，生成对账报告 `reports/reconcile_2024-01-15.md`。
- 创建问题清单文档 `docs/issues_week4.md`，记录遇到的典型问题及解决方案。

## 核心产出清单

- Python 脚本：`etl_load_ods.py`, `run_full_etl.py`
- SQL 脚本：`ods_to_dwd_apply.sql`, `ods_to_dwd_decision.sql`, `ods_rule_hit_clean.sql`, `load_to_event_date_table.sql`, `reconcile_3layer_apply.sql`
- 审计与对账表：`etl_audit`, `reconcile_summary`
- 文档：
  - `docs/data_quality_rules.md`（数据质量规则）
  - `docs/late_data_strategy.md`（迟到数据处理策略）
  - `docs/issues_week4.md`（问题清单）
- 报告：
  - `reports/reconcile_2024-01-15.md`（对账报告示例）
  - `reports/day27_performance.md`（性能优化报告）

## 遇到的问题与解决方案

| 问题                                                         | 影响                                | 解决方案                                                     |
| :----------------------------------------------------------- | :---------------------------------- | :----------------------------------------------------------- |
| 执行 `DELETE FROM dwd_apply_latest` 时报错 `Can only delete from base table!` | DWD 表实际为视图，无法进行 DML 操作 | 删除原视图，重建为物理表                                     |
| 多个 Python 进程同时打开 `dev.duckdb` 导致文件锁冲突         | 全链路脚本执行到一半失败            | 修改主脚本，所有 ETL 步骤均通过子进程调用，最后一步摘要插入改用 Python 直接连接 |
| Windows 下不支持 `<()` 进程替换                              | 对账摘要插入时命令执行失败          | 改用 Python 直接连接数据库执行 SQL                           |
| 对账发现 raw 与 ODS 行数不一致                               | 可能因迟到数据或重复记录导致        | 确认差异为预期行为（DWD 去重导致），并在文档中说明           |
| 窗口函数在数据量大时性能不佳                                 | 去重 SQL 执行时间较长               | 优化为 `GROUP BY` 取最大时间再关联，性能提升 25%             |

## 个人收获

- 深入理解了数仓分层（ODS → DWD）的 ETL 设计原则，特别是幂等性和增量处理的平衡。
- 掌握了迟到数据的识别与处理策略，明确了事件日与加载日的区别。
- 学会了使用 `EXPLAIN` 分析查询性能，并应用优化技巧提升 SQL 效率。
- 通过全链路整合，体会了自动化调度和数据质量监控的重要性。

## 下周计划（Day 29-35）

- **DWS 层构建**：设计渠道日报、策略日报等轻度汇总表，存储核心指标（申请量、通过率、拒绝率等）。
- **风控指标计算**：实现策略命中率、渠道质量评分等衍生指标。
- **数据质量监控**：开发每日 DQ 检查脚本，监控缺失率、异常值、主键唯一性。
- **继续性能优化**：对 DWS 层查询进行 Explain 分析，确保高效。