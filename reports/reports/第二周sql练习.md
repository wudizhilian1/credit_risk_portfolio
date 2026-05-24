512、534、571、574、578需要开会员

# 第8天题目练习

## 550 游戏玩法分析 4

### 题目描述

Table: `Activity`

```
+--------------+---------+
| Column Name  | Type    |
+--------------+---------+
| player_id    | int     |
| device_id    | int     |
| event_date   | date    |
| games_played | int     |
+--------------+---------+
（player_id，event_date）是此表的主键（具有唯一值的列的组合）。
这张表显示了某些游戏的玩家的活动情况。
每一行是一个玩家的记录，他在某一天使用某个设备注销之前登录并玩了很多游戏（可能是 0）。
```

编写解决方案，报告在首次登录的第二天再次登录的玩家的 **比率**，**四舍五入到小数点后两位**。换句话说，你需要计算从首次登录后的第二天登录的玩家数量，并将其除以总玩家数。

结果格式如下所示：

 

**示例 1：**

```
输入：
Activity table:
+-----------+-----------+------------+--------------+
| player_id | device_id | event_date | games_played |
+-----------+-----------+------------+--------------+
| 1         | 2         | 2016-03-01 | 5            |
| 1         | 2         | 2016-03-02 | 6            |
| 2         | 3         | 2017-06-25 | 1            |
| 3         | 1         | 2016-03-02 | 0            |
| 3         | 4         | 2018-07-03 | 5            |
+-----------+-----------+------------+--------------+
输出：
+-----------+
| fraction  |
+-----------+
| 0.33      |
+-----------+
解释：
只有 ID 为 1 的玩家在第一天登录后才重新登录，所以答案是 1/3 = 0.33
```

### 解题思路

**分组求首次登录日期 → 筛选次日登录的玩家 → 计算比例**；

**首次登录日期的计算**：

`MIN(event_date)` 是获取首次登录的核心，按`player_id`分组后，最小值即为该玩家第一次登录的日期。

### 最佳答案

```sql
SELECT 
    ROUND(COUNT(a.player_id) / COUNT(f.player_id), 2) AS fraction
FROM 
    (
        -- Step 1: Get the first login date for every player
        SELECT player_id, MIN(event_date) as first_login
        FROM Activity
        GROUP BY player_id
    ) f
LEFT JOIN Activity a 
    -- Step 2: Join looking for the SAME player on the NEXT day
    ON f.player_id = a.player_id 
    AND a.event_date = DATE_ADD(f.first_login, INTERVAL 1 DAY);
```

## 534 游戏玩法分析 3

### 题目描述

表 `Activity`：

text

复制下载

```
+--------------+---------+
| Column Name  | Type    |
+--------------+---------+
| player_id    | int     |
| device_id    | int     |
| event_date   | date    |
| games_played | int     |
+--------------+---------+
```



`(player_id, event_date)` 是该表的主键（具有唯一值的列的组合）。
该表显示了某些游戏的玩家活动情况：

- 每一行记录的是某个玩家在某一天使用某个设备登录后，当天玩的游戏总数。

**要求**：
编写一个解决方案，**同时报告每组玩家和日期，以及玩家** **到目前** **为止玩了多少游戏**。
也就是说，在此日期之前（包括该日期）玩家所玩的游戏总数。

返回的结果表格式如下例所示，**按 `player_id` 升序，`event_date` 升序排列**。

------

### 📊 **示例**

**输入**：

text

复制下载

```
Activity 表：
+-----------+-----------+------------+--------------+
| player_id | device_id | event_date | games_played |
+-----------+-----------+------------+--------------+
| 1         | 2         | 2016-03-01 | 5            |
| 1         | 2         | 2016-05-02 | 6            |
| 1         | 3         | 2017-06-25 | 1            |
| 3         | 1         | 2016-03-02 | 0            |
| 3         | 4         | 2018-07-03 | 5            |
+-----------+-----------+------------+--------------+
```



**输出**：

text

复制下载

```
+-----------+------------+---------------------+
| player_id | event_date | games_played_so_far |
+-----------+------------+---------------------+
| 1         | 2016-03-01 | 5                   |
| 1         | 2016-05-02 | 11                  |
| 1         | 2017-06-25 | 12                  |
| 3         | 2016-03-02 | 0                   |
| 3         | 2018-07-03 | 5                   |
+-----------+------------+---------------------+
```



**解释**：

- 对于 ID 为 1 的玩家：
  - 2016-03-01：玩 5 个游戏 → 累计 5
  - 2016-05-02：玩 6 个游戏 → 累计 5+6=11
  - 2017-06-25：玩 1 个游戏 → 累计 11+1=12
- 对于 ID 为 3 的玩家：
  - 2016-03-02：玩 0 个游戏 → 累计 0
  - 2018-07-03：玩 5 个游戏 → 累计 0+5=5

### 解题思路

使用**窗口函数** `SUM() OVER(PARTITION BY ... ORDER BY ...)` 实现**分组累加**

**说明**：

- `PARTITION BY player_id`：为每个玩家独立计算累加。
- `ORDER BY event_date`：按照日期顺序累加（默认窗口范围：从分区第一行到当前行）。

### 答案

```sql
SELECT 
    player_id,
    event_date,
    SUM(games_played) OVER (PARTITION BY player_id ORDER BY event_date) AS games_played_so_far
FROM 
    Activity
ORDER BY 
    player_id, event_date;
```

# 第10天题目练习

## 571. 给定数字的频率查询中位数

### **题目描述**：

`Numbers` 表保存数字的值及其频率。

text

```
+----------+-------------+
|  Number  |  Frequency  |
+----------+-------------|
|  0       |  7          |
|  1       |  1          |
|  2       |  3          |
|  3       |  1          |
+----------+-------------+
```



在此表中，数字为 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 3，所以中位数是 (0 + 0) / 2 = 0。

请编写一个查询来查找所有数字的中位数并将结果命名为 `median`。

**预期输出**：

text

```
+--------+
| median |
+--------|
| 0.0000 |
+--------+
```

### 解题思路



### 答案

```sql
SELECT AVG(Number) AS median
FROM (
    SELECT Number,
           SUM(Frequency) OVER(ORDER BY Number ASC) AS asc_accumu,
           SUM(Frequency) OVER(ORDER BY Number DESC) AS desc_accumu,
           SUM(Frequency) OVER() AS total
    FROM Numbers
) t
WHERE asc_accumu >= total / 2 AND desc_accumu >= total / 2;
```

# 第13天题目练习

## 602. 好友申请 II ：谁有最多的好友

### 题目描述

`RequestAccepted` 表：

```
+----------------+---------+
| Column Name    | Type    |
+----------------+---------+
| requester_id   | int     |
| accepter_id    | int     |
| accept_date    | date    |
+----------------+---------+
(requester_id, accepter_id) 是这张表的主键(具有唯一值的列的组合)。
这张表包含发送好友请求的人的 ID ，接收好友请求的人的 ID ，以及好友请求通过的日期。
```

 

编写解决方案，找出拥有最多的好友的人和他拥有的好友数目。

生成的测试用例保证拥有最多好友数目的只有 1 个人。

查询结果格式如下例所示。

 

**示例 1：**

```
输入：
RequestAccepted 表：
+--------------+-------------+-------------+
| requester_id | accepter_id | accept_date |
+--------------+-------------+-------------+
| 1            | 2           | 2016/06/03  |
| 1            | 3           | 2016/06/08  |
| 2            | 3           | 2016/06/08  |
| 3            | 4           | 2016/06/09  |
+--------------+-------------+-------------+
输出：
+----+-----+
| id | num |
+----+-----+
| 3  | 3   |
+----+-----+
解释：
编号为 3 的人是编号为 1 ，2 和 4 的人的好友，所以他总共有 3 个好友，比其他人都多。
```

### 解题思路

1.分别按照requester_id和accepter_id 对应的申请人和接收人的数量

2.合并所有出现过的ID（避免遗漏），因为有的用户只有requester_id或accepter_id 

3.最后通过合并后的ID分别关联子查询，进行相加，统计MAX

### 解法

```sql
WITH accepter AS (
    SELECT accepter_id AS id, COUNT(*) AS cnt FROM RequestAccepted GROUP BY accepter_id
),
requester AS (
    SELECT requester_id AS id, COUNT(*) AS cnt FROM RequestAccepted GROUP BY requester_id
),
all_ids AS (
    -- 合并所有出现过的ID（避免遗漏）
    SELECT id FROM accepter UNION SELECT id FROM requester
),
friend_count AS (
    -- 统计每个ID的总好友数（申请人次数+接收人次数）
    SELECT 
        a.id,
        COALESCE(r.cnt, 0) + COALESCE(ac.cnt, 0) AS num
    FROM all_ids a
    LEFT JOIN requester r ON a.id = r.id
    LEFT JOIN accepter ac ON a.id = ac.id
)
SELECT id, num 
FROM friend_count 
WHERE num = (SELECT MAX(num) FROM friend_count);
```

## [608. 树节点](https://leetcode.cn/problems/tree-node/)

### 题目描述

表：`Tree`

```
+-------------+------+
| Column Name | Type |
+-------------+------+
| id          | int  |
| p_id        | int  |
+-------------+------+
id 是该表中具有唯一值的列。
该表的每行包含树中节点的 id 及其父节点的 id 信息。
给定的结构总是一个有效的树。
```

 

树中的每个节点可以是以下三种类型之一：

- **"Leaf"**：节点是叶子节点。
- **"Root"**：节点是树的根节点。
- **"lnner"**：节点既不是叶子节点也不是根节点。

编写一个解决方案来报告树中每个节点的类型。

以 **任意顺序** 返回结果表。

结果格式如下所示。

```
输入：
Tree table:
+----+------+
| id | p_id |
+----+------+
| 1  | null |
| 2  | 1    |
| 3  | 1    |
| 4  | 2    |
| 5  | 2    |
+----+------+
输出：
+----+-------+
| id | type  |
+----+-------+
| 1  | Root  |
| 2  | Inner |
| 3  | Leaf  |
| 4  | Leaf  |
| 5  | Leaf  |
+----+-------+
解释：
节点 1 是根节点，因为它的父节点为空，并且它有子节点 2 和 3。
节点 2 是一个内部节点，因为它有父节点 1 和子节点 4 和 5。
节点 3、4 和 5 是叶子节点，因为它们有父节点而没有子节点。
```

### 解题思路

直接根据是否有父节点来判定

### 解题

```sql
SELECT 
    id,
    CASE 
        WHEN p_id IS NULL THEN 'Root'
        WHEN id IN (SELECT p_id FROM Tree) THEN 'Inner'
        ELSE 'Leaf'
    END AS type
FROM 
    Tree;
```

