# 第一天sql练习

## LeetCode数据第181题 

### 题目描述



```
+-------------+---------+
| Column Name | Type    |
+-------------+---------+
| id          | int     |
| name        | varchar |
| salary      | int     |
| managerId   | int     |
+-------------+---------+
id 是该表的主键（具有唯一值的列）。
该表的每一行都表示雇员的ID、姓名、工资和经理的ID。
```

编写解决方案，找出收入比经理高的员工。

以 **任意顺序** 返回结果表。

结果格式如下所示。

**示例 1:**

```
输入: 
Employee 表:
+----+-------+--------+-----------+
| id | name  | salary | managerId |
+----+-------+--------+-----------+
| 1  | Joe   | 70000  | 3         |
| 2  | Henry | 80000  | 4         |
| 3  | Sam   | 60000  | Null      |
| 4  | Max   | 90000  | Null      |
+----+-------+--------+-----------+
输出: 
+----------+
| Employee |
+----------+
| Joe      |
+----------+
解释: Joe 是唯一挣得比经理多的雇员。
```

### 解题思路

1 Joe的经理是3 Sam， 2 Herry的经理是4 Max，并且经理之上还有经理

### 代码

```sql
# Write your MySQL query statement below
SELECT A.name as Employee FROM Employee A ,
(SELECT id,salary FROM Employee ) B
WHERE A.managerId = B.id 
and a.salary > b.salary;
```

### **DuckDB** 



![image-20260119230555199](C:\Users\98128\AppData\Roaming\Typora\typora-user-images\image-20260119230555199.png)

# 第二天sql练习

## 第182 题 查找重复的电子邮箱

### 题目描述

表: `Person`

```
+-------------+---------+
| Column Name | Type    |
+-------------+---------+
| id          | int     |
| email       | varchar |
+-------------+---------+
id 是该表的主键（具有唯一值的列）。
此表的每一行都包含一封电子邮件。电子邮件不包含大写字母。
```

 

编写解决方案来报告所有重复的电子邮件。 请注意，可以保证电子邮件字段不为 NULL。

以 **任意顺序** 返回结果表。

```
输入: 
Person 表:
+----+---------+
| id | email   |
+----+---------+
| 1  | a@b.com |
| 2  | c@d.com |
| 3  | a@b.com |
+----+---------+
输出: 
+---------+
| Email   |
+---------+
| a@b.com |
+---------+
```

### 解题思路

最好不要嵌套

### 最佳答案

```sql
Select email
From Person
Group by email
Having COUNT(email) > 1
```

# 第四天sql练习

## 第196题删除重复邮箱

### 题目描述

表: `Person`

```
+-------------+---------+
| Column Name | Type    |
+-------------+---------+
| id          | int     |
| email       | varchar |
+-------------+---------+
id 是该表的主键列(具有唯一值的列)。
该表的每一行包含一封电子邮件。电子邮件将不包含大写字母。
```

 

编写解决方案 **删除** 所有重复的电子邮件，只保留一个具有最小 `id` 的唯一电子邮件。

**示例 1:**

```
输入: 
Person 表:
+----+------------------+
| id | email            |
+----+------------------+
| 1  | john@example.com |
| 2  | bob@example.com  |
| 3  | john@example.com |
+----+------------------+
输出: 
+----+------------------+
| id | email            |
+----+------------------+
| 1  | john@example.com |
| 2  | bob@example.com  |
+----+------------------+
解释: john@example.com重复两次。我们保留最小的Id = 1。
```

### 解题思路

最终重要的是如何拿到最小的且不重复的邮箱ID，要拿到不重复且最小的ID就要对email进行分组，同时取最小，再使用not in 进行排除

### 最优解法

```sql
delete from Person
where id not in (
    SELECT id
    FROM (
        SELECT MIN(id) AS id
        FROM Person
        GROUP BY email
    ) t
)
```

## 第187题分数排名

### 题目描述

表: `Scores`

```
+-------------+---------+
| Column Name | Type    |
+-------------+---------+
| id          | int     |
| score       | decimal |
+-------------+---------+
id 是该表的主键（有不同值的列）。
该表的每一行都包含了一场比赛的分数。Score 是一个有两位小数点的浮点值。
```

编写一个解决方案来查询分数的排名。排名按以下规则计算:

- 分数应按从高到低排列。
- 如果两个分数相等，那么两个分数的排名应该相同。
- 在排名相同的分数后，排名数应该是下一个连续的整数。换句话说，排名之间不应该有空缺的数字。

按 `score` 降序返回结果表。

查询结果格式如下所示。

**示例 1:**

```
输入: 
Scores 表:
+----+-------+
| id | score |
+----+-------+
| 1  | 3.50  |
| 2  | 3.65  |
| 3  | 4.00  |
| 4  | 3.85  |
| 5  | 4.00  |
| 6  | 3.65  |
+----+-------+
输出: 
+-------+------+
| score | rank |
+-------+------+
| 4.00  | 1    |
| 4.00  | 1    |
| 3.85  | 2    |
| 3.65  | 3    |
| 3.65  | 3    |
| 3.50  | 4    |
+-------+------+
```

### 解题思路

利用DENSE_RANK() 函数进行排序，对相同值的行分配**相同的排名**并列排名后，**不会跳过后续排名**（这是它和 `RANK()` 最核心的区别）

```sql
DENSE_RANK() OVER (
    [PARTITION BY 分区列1, 分区列2, ...]  -- 可选：按指定列分区，每个分区内单独排名
    ORDER BY 排序列1 [ASC|DESC], 排序列2 [ASC|DESC], ...  -- 必选：指定排名依据（升序/降序）
)
```

`PARTITION BY`：可选，将结果集划分为多个 “分区”，每个分区内独立计算排名（比如按 “科目” 分区，每个科目内单独排名）；

`ORDER BY`：必选，指定排名的依据列和排序方向（`DESC` 降序，`ASC` 升序，默认升序）

### 最优解法

```sql
# Write your MySQL query statement below
SELECT score, DENSE_RANK() 
OVER(ORDER BY score DESC ) AS 'rank' FROM Scores ORDER BY score DESC 
```

# 第五天sql练习

## 180，连续出现的数字

### 题目描述

表：`Logs`

```
+-------------+---------+
| Column Name | Type    |
+-------------+---------+
| id          | int     |
| num         | varchar |
+-------------+---------+
在 SQL 中，id 是该表的主键。
id 是一个自增列。
```

找出所有至少连续出现三次的数字。

返回的结果表中的数据可以按 **任意顺序** 排列。

结果格式如下面的例子所示：

**示例 1:**

```
输入：
Logs 表：
+----+-----+
| id | num |
+----+-----+
| 1  | 1   |
| 2  | 1   |
| 3  | 1   |
| 4  | 2   |
| 5  | 1   |
| 6  | 2   |
| 7  | 2   |
+----+-----+
输出：
Result 表：
+-----------------+
| ConsecutiveNums |
+-----------------+
| 1               |
+-----------------+
解释：1 是唯一连续出现至少三次的数字。
```

### 解题思路

至少出现三次，那就是连续三次的num相同，可以联查三次，每次id+1且num相同，联查时主键id进行管理，num条件判定放在where条件中

### 最优解法

```sql
SELECT DISTINCT l1.num AS ConsecutiveNums
FROM Logs l1
JOIN Logs l2 ON l1.id = l2.id - 1
JOIN Logs l3 ON l1.id = l3.id - 2
WHERE l1.num = l2.num
  AND l2.num = l3.num;
```

# 第7天sql练习

## 262.行程和用户

### 题目描述

表：`Trips`

```
+-------------+----------+
| Column Name | Type     |
+-------------+----------+
| id          | int      |
| client_id   | int      |
| driver_id   | int      |
| city_id     | int      |
| status      | enum     |
| request_at  | varchar  |     
+-------------+----------+
id 是这张表的主键（具有唯一值的列）。
这张表中存所有出租车的行程信息。每段行程有唯一 id ，其中 client_id 和 driver_id 是 Users 表中 users_id 的外键。
status 是一个表示行程状态的枚举类型，枚举成员为(‘completed’, ‘cancelled_by_driver’, ‘cancelled_by_client’) 。
```

表：`Users`

```
+-------------+----------+
| Column Name | Type     |
+-------------+----------+
| users_id    | int      |
| banned      | enum     |
| role        | enum     |
+-------------+----------+
users_id 是这张表的主键（具有唯一值的列）。
这张表中存所有用户，每个用户都有一个唯一的 users_id ，role 是一个表示用户身份的枚举类型，枚举成员为 (‘client’, ‘driver’, ‘partner’) 。
banned 是一个表示用户是否被禁止的枚举类型，枚举成员为 (‘Yes’, ‘No’) 。
```

**取消率** 的计算方式如下：(被司机或乘客取消的非禁止用户生成的订单数量) / (非禁止用户生成的订单总数)。

编写解决方案找出 `"2013-10-01"` 至 `"2013-10-03"` 期间有 **至少** 一次行程的非禁止用户（**乘客和司机都必须未被禁止**）的 **取消率**。非禁止用户即 banned 为 No 的用户，禁止用户即 banned 为 Yes 的用户。其中取消率 `Cancellation Rate` 需要四舍五入保留 **两位小数** 。

返回结果表中的数据 **无顺序要求** 。

结果格式如下例所示。

**示例 1：**

```
输入： 
Trips 表：
+----+-----------+-----------+---------+---------------------+------------+
| id | client_id | driver_id | city_id | status              | request_at |
+----+-----------+-----------+---------+---------------------+------------+
| 1  | 1         | 10        | 1       | completed           | 2013-10-01 |
| 2  | 2         | 11        | 1       | cancelled_by_driver | 2013-10-01 |
| 3  | 3         | 12        | 6       | completed           | 2013-10-01 |
| 4  | 4         | 13        | 6       | cancelled_by_client | 2013-10-01 |
| 5  | 1         | 10        | 1       | completed           | 2013-10-02 |
| 6  | 2         | 11        | 6       | completed           | 2013-10-02 |
| 7  | 3         | 12        | 6       | completed           | 2013-10-02 |
| 8  | 2         | 12        | 12      | completed           | 2013-10-03 |
| 9  | 3         | 10        | 12      | completed           | 2013-10-03 |
| 10 | 4         | 13        | 12      | cancelled_by_driver | 2013-10-03 |
+----+-----------+-----------+---------+---------------------+------------+
Users 表：
+----------+--------+--------+
| users_id | banned | role   |
+----------+--------+--------+
| 1        | No     | client |
| 2        | Yes    | client |
| 3        | No     | client |
| 4        | No     | client |
| 10       | No     | driver |
| 11       | No     | driver |
| 12       | No     | driver |
| 13       | No     | driver |
+----------+--------+--------+
输出：
+------------+-------------------+
| Day        | Cancellation Rate |
+------------+-------------------+
| 2013-10-01 | 0.33              |
| 2013-10-02 | 0.00              |
| 2013-10-03 | 0.50              |
+------------+-------------------+
解释：
2013-10-01：
  - 共有 4 条请求，其中 2 条取消。
  - 然而，id=2 的请求是由禁止用户（user_id=2）发出的，所以计算时应当忽略它。
  - 因此，总共有 3 条非禁止请求参与计算，其中 1 条取消。
  - 取消率为 (1 / 3) = 0.33
2013-10-02：
  - 共有 3 条请求，其中 0 条取消。
  - 然而，id=6 的请求是由禁止用户发出的，所以计算时应当忽略它。
  - 因此，总共有 2 条非禁止请求参与计算，其中 0 条取消。
  - 取消率为 (0 / 2) = 0.00
2013-10-03：
  - 共有 3 条请求，其中 1 条取消。
  - 然而，id=8 的请求是由禁止用户发出的，所以计算时应当忽略它。
  - 因此，总共有 2 条非禁止请求参与计算，其中 1 条取消。
  - 取消率为 (1 / 2) = 0.50
```

### 解题思路

1.要同时筛选筛选未被禁止的司机和客户，这部分会稍有疑问，Trips要通过两次INNER JOIN Users进行筛选

2.保留两位四舍五入使用函数ROUND(数，位数)，计算取消订单的要使用SUM函数

3.在SUM函数中进行判定，取消的为1，不取消的为0，再和总数相除

### 答案

```sql
SELECT 
    t.request_at AS "Day",
    ROUND(
        SUM(CASE WHEN t.status IN ('cancelled_by_driver', 'cancelled_by_client') THEN 1 ELSE 0 END) / 
        COUNT(*),
        2
    ) AS "Cancellation Rate"
FROM Trips t
-- 关联司机表：筛选未被禁止的司机
INNER JOIN Users d ON t.driver_id = d.users_id AND d.banned = 'No'
-- 关联客户表：筛选未被禁止的客户
INNER JOIN Users c ON t.client_id = c.users_id AND c.banned = 'No'
-- 日期范围
WHERE t.request_at BETWEEN '2013-10-01' AND '2013-10-03'
GROUP BY t.request_at;
```

