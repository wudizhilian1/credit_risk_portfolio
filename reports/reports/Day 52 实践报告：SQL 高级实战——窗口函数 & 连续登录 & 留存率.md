# Day 52 实践报告：SQL 高级实战——窗口函数 & 连续登录 & 留存率

## 1. 练习目标
- 熟练掌握 SQL 窗口函数（`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LAG`, `LEAD`）在风控场景中的应用。
- 独立手写复杂查询：去重取最新、连续登录/活跃、留存率计算、中位数、行列转换。
- 建立 SQL 错题本，记录易错点和优化思路。
- 为后续面试中的手写 SQL 环节做好充分准备。

## 2. 实验环境
- 数据库：DuckDB 0.10.0（本地 `dev.duckdb`） + LeetCode 在线评测
- 辅助工具：文本编辑器（手写 SQL）、DuckDB CLI 验证
- 练习题目来源：LeetCode（512, 534, 178, 184, 185, 180, 197, 601, 603, 550, 602, 262, 571, 1179）

## 3. 核心任务执行

### 3.1 窗口函数专题（去重取最新、排名、前后行）

| 题目                      | 考点                             | 手写SQL                                                      | 易错点                                                   |
| ------------------------- | -------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------- |
| 512. 游戏玩法分析 II      | 每个玩家首次登录的设备ID         | `ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY event_date)` | 忘记 `DISTINCT` 或 `ROW_NUMBER` 的排序方向               |
| 534. 游戏玩法分析 III     | 每个玩家截止当前日期的游戏总数   | `SUM(games_played) OVER (PARTITION BY player_id ORDER BY event_date)` | 窗口范围默认是 `RANGE UNBOUNDED PRECEDING`，无需额外指定 |
| 178. 分数排名             | 分数排名（DENSE_RANK）           | `DENSE_RANK() OVER (ORDER BY score DESC)`                    | 区分 `RANK`（跳号）和 `DENSE_RANK`（不跳号）             |
| 184. 部门工资最高的员工   | 每个部门最高工资（可能存在并列） | `RANK() OVER (PARTITION BY departmentId ORDER BY salary DESC)` | 使用 `RANK` 而非 `ROW_NUMBER` 以保留并列                 |
| 185. 部门工资前三高的员工 | 每个部门前三高工资               | `DENSE_RANK() OVER (PARTITION BY departmentId ORDER BY salary DESC)` | 使用 `DENSE_RANK` 保证前三名包含并列                     |
| 180. 连续出现的数字       | 找出至少连续出现三次的数字       | `LAG(num,1) OVER()` 和 `LAG(num,2) OVER()`                   | 边界条件（不足三行）处理；也可用自连接                   |
| 197. 上升的温度           | 找出比前一天温度更高的日期       | `LAG(temperature) OVER (ORDER BY recordDate)`                | 确保日期连续；使用 `DATE_ADD` 比较相邻日期               |

**手写示例（512）**：
```sql
-- 每个玩家首次登录的设备ID
SELECT player_id, device_id
FROM (
    SELECT player_id, device_id,
           ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY event_date) AS rn
    FROM Activity
) t
WHERE rn = 1;
```

### 3.2 连续登录与留存率专题

| 题目                       | 考点                           | 手写SQL                      | 易错点                                           |
| -------------------------- | ------------------------------ | ---------------------------- | ------------------------------------------------ |
| 601. 体育馆的人流量        | 连续3天以上人流量 >= 100       | 自连接 + `ROW_NUMBER` 差值法 | 连续区间的分组方法（`id - ROW_NUMBER() OVER()`） |
| 603. 连续登录5天以上的用户 | 找出连续5天登录的用户          | 类似连续区间分组             | 日期可能不连续，需先按用户生成连续标记           |
| 550. 游戏玩法分析 IV       | 首次登录后第二天再次登录的比例 | 子查询 + `DATE_ADD`          | 计算次日留存时，需要先求出每个用户的首次登录日   |
| 602. 好友申请 II           | 谁有最多的好友                 | `UNION ALL` + 分组计数       | 请求者和接受者需合并统计                         |

**手写示例（550）**：
```sql
-- 首次登录后第二天再次登录的比例
SELECT ROUND(COUNT(DISTINCT player_id) * 1.0 / (SELECT COUNT(DISTINCT player_id) FROM Activity), 2) AS fraction
FROM Activity
WHERE (player_id, event_date) IN (
    SELECT player_id, DATE_ADD(MIN(event_date), INTERVAL 1 DAY)
    FROM Activity
    GROUP BY player_id
);
```

### 3.3 聚合与行列转换专题

| 题目                          | 考点                 | 手写SQL             | 易错点                                 |
| ----------------------------- | -------------------- | ------------------- | -------------------------------------- |
| 262. 行程和用户               | 取消率（非禁止用户） | 条件聚合 + 日期过滤 | 需排除被禁止的乘客和司机               |
| 571. 给定数字的频率查询中位数 | 中位数（带频率）     | 累积频率法          | 中位数定义（偶数时取平均值）           |
| 1179. 重新格式化部门表        | 行列转换（PIVOT）    | `CASE WHEN` + `SUM` | 月份列可能为 NULL，使用 `SUM` 自动忽略 |

**手写示例（571）**：
```sql
-- 中位数（带频率）
SELECT AVG(Number) AS median
FROM (
    SELECT Number,
           SUM(Frequency) OVER (ORDER BY Number) AS asc_accumu,
           SUM(Frequency) OVER (ORDER BY Number DESC) AS desc_accumu,
           SUM(Frequency) OVER () AS total
    FROM Numbers
) t
WHERE asc_accumu >= total/2 AND desc_accumu >= total/2;
```

### 3.4 手写规范与验证
- 所有 SQL 先手写在文本编辑器中（无自动补全），然后粘贴到 DuckDB CLI 或 LeetCode 运行。
- 记录每道题的错误点（如遗漏 `DISTINCT`、窗口函数排序方向错误、未处理 NULL）到 `sql/sql_errors.md`。

**易错点汇总**：
1. **窗口函数排序方向**：`ORDER BY event_date` 升序取最早，降序取最新（512）。
2. **排名函数选择**：`ROW_NUMBER` 用于唯一排名，`RANK` 用于并列跳号，`DENSE_RANK` 用于并列不跳号（184 vs 185）。
3. **连续区间分组**：使用 `id - ROW_NUMBER() OVER (ORDER BY id)` 作为分组键（601）。
4. **留存率计算**：注意 `DATE_ADD` 函数在不同数据库中的写法（DuckDB 用 `+ INTERVAL '1 day'`）。
5. **中位数**：偶数个时取平均值，需用 `AVG`。
6. **行列转换**：`CASE WHEN` 中需要聚合函数（`SUM` 或 `MAX`）配合 `GROUP BY`。

## 4. 遇到的问题与解决方案

| 问题                               | 原因                          | 解决方案                                                     |
| ---------------------------------- | ----------------------------- | ------------------------------------------------------------ |
| `ROW_NUMBER()` 忘记 `PARTITION BY` | 习惯性遗漏                    | 手写时先写 `PARTITION BY` 再写 `ORDER BY`                    |
| `LAG` 窗口函数默认窗口为全表       | 未指定 `ORDER BY`             | 必须加上 `ORDER BY` 才有意义                                 |
| 连续登录分组时日期不连续导致错误   | 直接用 `id - rn` 需要日期连续 | 先使用 `ROW_NUMBER() OVER (PARTITION BY user ORDER BY login_date)` 生成连续序号，再用 `login_date - INTERVAL 'rn day'` 生成分组键 |
| DuckDB 不支持 `DATE_ADD` 函数      | 数据库差异                    | 改用 `event_date + INTERVAL '1 day'`                         |

## 5. 核心产出清单
- [x] `sql/sql_handwrite_day52.sql`（包含今日所有手写 SQL，共 14 题）
- [x] `sql/sql_errors.md`（记录 8 个易错点及改进）
- [x] 验证所有 SQL 在 DuckDB/LeetCode 上运行正确
- [x] 练习总结（本报告）

## 6. 思考题
- 窗口函数 `ROW_NUMBER`、`RANK`、`DENSE_RANK` 的区别是什么？分别适用于什么场景？  
  → `ROW_NUMBER`：唯一序号（即使值相同），适用于取Top1且不允许并列；`RANK`：并列跳号（1,1,3），适用于允许并列但需保留排名间隙；`DENSE_RANK`：并列不跳号（1,1,2），适用于取TopN且包含并列。
- 计算留存率时，如何避免统计到重复用户？  
  → 使用 `COUNT(DISTINCT user_id)` 或先按用户去重再计算。
- 中位数的几种计算方法（窗口函数 + 分位数）各有什么优缺点？  
  → 窗口函数法：兼容性好，需两次排序；分位数法：简洁但需数据库支持（如 DuckDB 的 `QUANTILE_CONT`）。频率表法则需自定义累积逻辑。

---
**完成日期**：2026-04-08