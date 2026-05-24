# SQL 手写冲刺

- 去重取最新（窗口函数）

```sql
SELECT 
    *, 
    row_number() over(partition by apply_id order by dt desc) as rol 
FROM v_apply)
SELECT * FROM latest where rol = 1 
```

- 连续登录/活跃用户（自连接或 LAG）

7天连续登录/活跃用户 7 天连续登录 / 活跃用户 = 连续 7 天都登录

```sql
WITH user_daily AS (
    -- 步骤1：用户按天去重，1天1条
    SELECT DISTINCT
        user_id,
        DATE(dt) AS active_date
    FROM v_apply
),
user_lag AS (
    -- 步骤2：用 LAG() 取前1天、前2天...前6天的日期
    SELECT
        user_id,
        active_date,
        LAG(active_date, 1) OVER (PARTITION BY user_id ORDER BY active_date) AS day1,
        LAG(active_date, 2) OVER (PARTITION BY user_id ORDER BY active_date) AS day2,
        LAG(active_date, 3) OVER (PARTITION BY user_id ORDER BY active_date) AS day3,
        LAG(active_date, 4) OVER (PARTITION BY user_id ORDER BY active_date) AS day4,
        LAG(active_date, 5) OVER (PARTITION BY user_id ORDER BY active_date) AS day5,
        LAG(active_date, 6) OVER (PARTITION BY user_id ORDER BY active_date) AS day6
    FROM user_daily
)
-- 步骤3：判断是否连续7天都活跃
SELECT DISTINCT user_id
FROM user_lag
WHERE
    active_date = day1 + INTERVAL 1 DAY
    AND day1 = day2 + INTERVAL 1 DAY
    AND day2 = day3 + INTERVAL 1 DAY
    AND day3 = day4 + INTERVAL 1 DAY
    AND day4 = day5 + INTERVAL 1 DAY
    AND day5 = day6 + INTERVAL 1 DAY
    limit 10;
```

30天连续登录

```sql
WITH user_daily AS (
  SELECT DISTINCT
    user_id,
    DATE(dt) AS active_date
  FROM v_apply
),
user_group AS (
  SELECT
    user_id,
    active_date,
    -- ✅ DuckDB 正确写法：日期 - 整数（必须这么写！）
    active_date - INTERVAL (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY active_date) - 1) DAY AS group_id
  FROM user_daily
)
SELECT DISTINCT user_id
FROM user_group
GROUP BY user_id, group_id
HAVING COUNT(*) >= 30 limit 10;
```



- 留存率计算

留存率 = （后来还活着的人） / （最开始那批人） × 100%
次日留存率 = 第2天还活跃的用户数 ÷ 当天新增用户数 × 100%
7日留存率 = 第7天还活跃的用户数 ÷ 当天新增用户数 × 100%

```sql
WITH user_first_active AS (
    SELECT
        user_id,
        MIN(DATE(dt)) AS first_dt
    FROM v_apply
    GROUP BY user_id
),
user_active_days AS (
    SELECT DISTINCT
        user_id,
        DATE(dt) AS active_dt
    FROM v_apply
)
SELECT
    f.first_dt AS dt,
    COUNT(DISTINCT f.user_id) AS new_users,
    COUNT(DISTINCT CASE WHEN a.active_dt = f.first_dt + 7 THEN f.user_id END) AS retain_7d_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN a.active_dt = f.first_dt + 7 THEN f.user_id END) * 100.0
        / COUNT(DISTINCT f.user_id),
        2
    ) AS retain_rate_7d_pct
FROM user_first_active f
LEFT JOIN user_active_days a
    ON f.user_id = a.user_id
GROUP BY f.first_dt
ORDER BY f.first_dt
```



- 中位数/分位数
- 行列转换（PIVOT）
- 累计求和/移动平均
- 分组 TopN