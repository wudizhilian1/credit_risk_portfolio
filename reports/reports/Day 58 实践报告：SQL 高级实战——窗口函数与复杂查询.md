# Day 58 实践报告：SQL 高级实战——窗口函数与复杂查询

## 1. 练习目标
- 熟练掌握窗口函数（`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LAG`, `LEAD`）在复杂业务场景中的运用。
- 独立手写中等/困难难度的 SQL 题，包括连续登录、留存率、分组 TopN、行列转换、中位数等。
- 建立错题本，记录易错点和优化思路，为面试手写环节打下坚实基础。

## 2. 实验环境
- 数据库：DuckDB 0.10.0（本地 `dev.duckdb`）+ LeetCode 在线评测
- 辅助工具：文本编辑器（手写 SQL）、DuckDB CLI 验证
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 窗口函数进阶（6 题）
| 题目                           | 手写 SQL                                                     | 验证状态 |
| ------------------------------ | ------------------------------------------------------------ | -------- |
| 1. 每个用户最后一次登录的设备  | `ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date DESC)` | ✅ 通过   |
| 2. 分数排名（DENSE_RANK）      | `DENSE_RANK() OVER (ORDER BY score DESC)`                    | ✅ 通过   |
| 3. 每个部门工资前三高的员工    | `DENSE_RANK() OVER (PARTITION BY departmentId ORDER BY salary DESC)` | ✅ 通过   |
| 4. 连续出现至少 3 次的数字     | `LAG(num,1)` 和 `LAG(num,2)`                                 | ✅ 通过   |
| 5. 上升的温度                  | `LAG(temperature) OVER (ORDER BY recordDate)`                | ✅ 通过   |
| 6. 查找至少连续 3 天登录的用户 | `DATE_SUB(login_date, ROW_NUMBER() OVER(...))` 分组法        | ✅ 通过   |

**易错点**：
- `ROW_NUMBER` 与 `RANK`/`DENSE_RANK` 的区别：唯一序号 vs 并列跳号 vs 并列不跳号。
- 连续登录分组时，需要先用 `ROW_NUMBER()` 生成连续序号，再与日期相减得到分组键。
- `LAG` 窗口函数必须指定 `ORDER BY`，否则默认全表无意义。

### 3.2 留存率与漏斗分析（3 题）
| 题目                    | 手写 SQL                                          | 验证状态 |
| ----------------------- | ------------------------------------------------- | -------- |
| 7. 首次登录后次日留存率 | `WHERE (player_id, event_date) IN (首次登录日+1)` | ✅ 通过   |
| 8. 每日新用户次日留存率 | 先找每日新用户，再左连次日活跃                    | ✅ 通过   |
| 9. 漏斗转化率           | 每步 `COUNT(DISTINCT user_id)` + `CASE WHEN` 判断 | ✅ 通过   |

**留存率核心**：
- 首次登录日：`MIN(event_date) GROUP BY player_id`
- 次日活跃：`event_date = 首次登录日 + 1`
- 注意使用 `DATE_ADD` 或 `+ INTERVAL` 进行日期运算。

### 3.3 聚合与行列转换（3 题）
| 题目                 | 手写 SQL                                                    | 验证状态 |
| -------------------- | ----------------------------------------------------------- | -------- |
| 10. 每月交易 I       | `DATE_FORMAT(trans_date, '%Y-%m')` + `GROUP BY`             | ✅ 通过   |
| 11. 重新格式化部门表 | `SUM(CASE WHEN month='Jan' THEN revenue END)`               | ✅ 通过   |
| 12. 产品销售分析 III | `ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY year)` | ✅ 通过   |

**注意**：行列转换时，聚合函数（`SUM`/`MAX`）配合 `CASE WHEN`，且必须 `GROUP BY` 非转置列。

### 3.4 建立错题本
创建 `sql/sql_errors_day58.md`，记录以下易错点：

1. **窗口函数排序方向**：`ORDER BY year ASC` 取最早，`DESC` 取最新。
2. **连续登录分组**：日期与行号的差值作为分组键，需要日期连续且无重复。
3. **留存率计算**：子查询返回 `(player_id, first_login_date+1)` 时，注意日期边界。
4. **行列转换**：`CASE WHEN` 中未使用聚合函数会导致语法错误。
5. **分区与排序**：`PARTITION BY` 后忘记 `ORDER BY`，窗口函数会报错。

## 4. 遇到的问题与解决方案

| 问题                                 | 原因                            | 解决方案                                   |
| ------------------------------------ | ------------------------------- | ------------------------------------------ |
| `LAG` 函数返回 NULL 导致后续比较错误 | 未处理边界行                    | 使用 `COALESCE` 或条件判断                 |
| 连续登录分组时日期不连续导致分组错误 | 直接用 `id - rn` 需要 id 连续   | 改用 `login_date - ROW_NUMBER() OVER(...)` |
| 留存率 SQL 在 DuckDB 中报错          | `DATE_ADD` 函数不兼容           | 改用 `event_date + INTERVAL '1 day'`       |
| 行列转换后某月无数据返回 NULL        | `CASE WHEN` 无匹配时默认为 NULL | 使用 `COALESCE(..., 0)` 填充 0             |

## 5. 核心产出清单
- [x] 手写 SQL 文件 `sql/sql_handwrite_day58.sql`（12 题）
- [x] 错题本 `sql/sql_errors_day58.md`
- [x] 所有 SQL 在 DuckDB/LeetCode 上验证通过

## 6. 思考题
- **为什么窗口函数比自连接更高效？**  
  窗口函数只需一次表扫描和一次排序，而自连接往往需要多次扫描和笛卡尔积。
- **连续登录的“日期-行号”分组法的原理是什么？**  
  日期减去连续序号，相同差值表示这些行在时间上是连续的（因为序号每行+1，日期也每天+1）。
- **留存率计算中，如何避免统计到重复用户？**  
  使用 `COUNT(DISTINCT user_id)`，或在子查询中先按用户去重。

---
**完成日期**：2026-04-13