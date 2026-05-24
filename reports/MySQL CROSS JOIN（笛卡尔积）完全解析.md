# MySQL CROSS JOIN（笛卡尔积）完全解析

`CROSS JOIN` 是 MySQL 中用于生成**两张表笛卡尔积**的连接方式，核心作用是返回「左表每一行」与「右表每一行」的所有组合，是实现「全量维度覆盖」的关键语法（如 LeetCode 1280 中 “所有学生 + 所有科目” 的组合）。

## 一、核心定义

- **笛卡尔积**：若表 A 有 `m` 行，表 B 有 `n` 行，`A CROSS JOIN B` 会生成 `m×n` 行结果（无任何关联条件，仅做全量组合）；
- **使用场景**：需要覆盖「所有维度组合」的统计场景（如所有学生 + 所有科目、所有日期 + 所有地区）。

## 二、基础语法（3 种等价写法）

### 1. 标准写法（推荐，语义清晰）

```sql
SELECT 字段列表
FROM 表A
CROSS JOIN 表B;
```

### 2. 省略 CROSS JOIN 关键字（仅用逗号分隔）

```sql
SELECT 字段列表
FROM 表A, 表B; -- 效果与 CROSS JOIN 完全一致，不推荐（语义不清晰）
```

### 3. 带 WHERE 过滤的 CROSS JOIN（退化为内连接）

```sql
SELECT 字段列表
FROM 表A
CROSS JOIN 表B
WHERE 表A.字段 = 表B.字段; -- 等价于 INNER JOIN
```

## 三、实战用法（按场景分类）

### 场景 1：基础笛卡尔积（无过滤，全量组合）

#### 示例表（延续 1280 题场景）

```sql
-- 学生表（2行）
CREATE TABLE Students (student_id INT, student_name VARCHAR(32));
INSERT INTO Students VALUES (1,'Alice'),(2,'Bob');

-- 科目表（3行）
CREATE TABLE Subjects (subject_name VARCHAR(32));
INSERT INTO Subjects VALUES ('Math'),('English'),('Physics');
```

#### 需求：生成所有学生 + 所有科目的组合

```sql
-- 标准写法
SELECT s.student_id, s.student_name, sub.subject_name
FROM Students s
CROSS JOIN Subjects sub;
```

#### 结果（2×3=6 行）

| student_id | student_name | subject_name |
| :--------- | :----------- | :----------- |
| 1          | Alice        | Math         |
| 1          | Alice        | English      |
| 1          | Alice        | Physics      |
| 2          | Bob          | Math         |
| 2          | Bob          | English      |
| 2          | Bob          | Physics      |

### 场景 2：带过滤条件的 CROSS JOIN（精准全量组合）

#### 需求：生成「2026 年 1 月前 3 天」+「所有科目」的组合

```sql
-- 步骤1：生成日期维度表（临时表）
WITH date_dim AS (
    SELECT '2026-01-01' AS dt UNION ALL
    SELECT '2026-01-02' AS dt UNION ALL
    SELECT '2026-01-03' AS dt
)
-- 步骤2：CROSS JOIN 生成日期+科目全量组合
SELECT dd.dt, sub.subject_name
FROM date_dim dd
CROSS JOIN Subjects sub
-- 可选：过滤不需要的组合（比如排除Physics在1月1日的组合）
WHERE NOT (dd.dt = '2026-01-01' AND sub.subject_name = 'Physics');
```

#### 结果（3×3 -1=8 行，排除了 1 条组合）

| dt         | subject_name |
| :--------- | :----------- |
| 2026-01-01 | Math         |
| 2026-01-01 | English      |
| 2026-01-02 | Math         |
| 2026-01-02 | English      |
| 2026-01-02 | Physics      |
| 2026-01-03 | Math         |
| 2026-01-03 | English      |
| 2026-01-03 | Physics      |

### 场景 3：多表 CROSS JOIN（3 张及以上表）

#### 需求：生成「学生 + 科目 + 日期」的全量组合

```sql
WITH date_dim AS (
    SELECT '2026-01-01' AS dt UNION ALL
    SELECT '2026-01-02' AS dt
)
SELECT s.student_id, sub.subject_name, dd.dt
FROM Students s
CROSS JOIN Subjects sub
CROSS JOIN date_dim dd;
```

#### 结果（2×3×2=12 行，覆盖所有维度组合）

### 场景 4：结合 LEFT JOIN 实现全量统计（核心实战）

这是数据仓 / 面试中最常用的组合用法（如 1280 题）：

```sql
-- 步骤1：CROSS JOIN 生成全量维度（学生+科目）
-- 步骤2：LEFT JOIN 考试表统计次数
SELECT
    s.student_id,
    s.student_name,
    sub.subject_name,
    COUNT(e.subject_name) AS attended_exams -- 无考试则为0
FROM Students s
CROSS JOIN Subjects sub
LEFT JOIN Examinations e 
    ON s.student_id = e.student_id 
    AND sub.subject_name = e.subject_name
GROUP BY s.student_id, s.student_name, sub.subject_name;
```

## 四、关键注意事项（避坑）

### 1. 避免大数据量表的全量 CROSS JOIN

- 若表 A 有 1000 行，表 B 有 1000 行，CROSS JOIN 会生成 100 万行，极易导致性能问题；
- 解决方案：仅对「小维度表」（如科目表、日期表，行数≤1000）使用 CROSS JOIN，大表需先过滤再组合。

### 2. CROSS JOIN 与 INNER JOIN 的区别





| 类型       | 关联条件 | 结果行数       | 核心用途     |
| :--------- | :------- | :------------- | :----------- |
| CROSS JOIN | 无       | m×n            | 全量维度组合 |
| INNER JOIN | ON 条件  | ≤m×n（匹配行） | 关联匹配数据 |

### 3. 不要混淆 CROSS JOIN 和 LEFT JOIN

- 错误用法：想用 CROSS JOIN 实现 “保留左表所有行”（这是 LEFT JOIN 的功能）；
- 正确认知：CROSS JOIN 只负责生成全量组合，保留行需结合 LEFT JOIN。

### 4. 语法细节：CROSS JOIN 后不能加 ON 条件

```sql
-- 错误：CROSS JOIN 不支持 ON 关联条件
SELECT * FROM Students s CROSS JOIN Subjects sub ON s.student_id = 1;

-- 正确：过滤条件放 WHERE
SELECT * FROM Students s CROSS JOIN Subjects sub WHERE s.student_id = 1;
```

## 五、高频面试 / 实战场景总结

| 场景                    | 实现方式                         |
| :---------------------- | :------------------------------- |
| 所有学生 + 所有科目统计 | Students CROSS JOIN Subjects     |
| 所有日期 + 所有地区统计 | date_dim CROSS JOIN area_dim     |
| 全量维度覆盖的计数      | CROSS JOIN + LEFT JOIN + COUNT   |
| 生成测试数据            | 小维度表 CROSS JOIN 生成批量组合 |

## 总结

1. **核心用法**：`CROSS JOIN` 用于生成两张表的笛卡尔积，是实现「全量维度覆盖」的唯一方式；
2. **实战组合**：CROSS JOIN（全量维度） + LEFT JOIN（关联业务数据） + COUNT（统计空值），可解决所有 “全量维度统计” 问题；
3. **避坑关键**：仅对小维度表使用 CROSS JOIN，避免大数据量笛卡尔积导致性能崩溃；
4. **语法优选**：使用 `表A CROSS JOIN 表B` 标准写法，而非逗号分隔，提升代码可读性。