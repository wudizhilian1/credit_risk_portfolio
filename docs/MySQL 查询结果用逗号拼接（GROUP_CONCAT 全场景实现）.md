# MySQL 查询结果用逗号拼接（GROUP_CONCAT 全场景实现）

## 一、核心函数：GROUP_CONCAT ()

MySQL 中实现查询结果按逗号拼接的核心函数是 `GROUP_CONCAT()`，可将分组内的多行字段值拼接为单个字符串（默认分隔符为逗号），是数仓报表、维度聚合场景的高频用法。

### 基础语法

```sql
GROUP_CONCAT([DISTINCT] 字段名 
             [ORDER BY 排序字段 ASC/DESC] 
             [SEPARATOR '分隔符'])
```

- `DISTINCT`：可选，去重后再拼接；
- `ORDER BY`：可选，拼接前对字段值排序；
- `SEPARATOR`：可选，指定分隔符（默认逗号）。

## 二、实战场景（附测试用例）

### 场景 1：基础拼接（单字段逗号分隔）

#### 测试表准备

```sql
CREATE TABLE user_orders (
    user_id INT,
    order_id VARCHAR(20),
    order_amount DECIMAL(10,2)
);

INSERT INTO user_orders VALUES
(1, 'O001', 100.00),
(1, 'O002', 200.00),
(2, 'O003', 150.00),
(2, 'O004', 300.00),
(2, 'O004', 300.00); -- 重复订单ID
```

#### 需求：按用户分组，拼接该用户的所有订单 ID（逗号分隔）

```sql
SELECT
    user_id,
    -- 基础拼接（含重复值）
    GROUP_CONCAT(order_id) AS order_ids,
    -- 去重后拼接
    GROUP_CONCAT(DISTINCT order_id) AS distinct_order_ids,
    -- 排序后拼接
    GROUP_CONCAT(DISTINCT order_id ORDER BY order_id DESC) AS sorted_order_ids
FROM user_orders
GROUP BY user_id;
```

#### 结果输出

| user_id | order_ids      | distinct_order_ids | sorted_order_ids |
| :------ | :------------- | :----------------- | :--------------- |
| 1       | O001,O002      | O001,O002          | O002,O001        |
| 2       | O003,O004,O004 | O003,O004          | O004,O003        |

### 场景 2：多字段拼接（自定义分隔符）

#### 需求：拼接订单 ID + 金额（格式：订单 ID (金额)，多个用逗号分隔）

```sql
SELECT
    user_id,
    GROUP_CONCAT(
        CONCAT(order_id, '(', order_amount, ')')  -- 拼接字段为自定义格式
        ORDER BY order_amount DESC
        SEPARATOR ', '  -- 显式指定逗号+空格分隔
    ) AS order_detail
FROM user_orders
GROUP BY user_id;
```

#### 结果输出

| user_id | order_detail                             |
| :------ | :--------------------------------------- |
| 1       | O002(200.00), O001(100.00)               |
| 2       | O004(300.00), O004(300.00), O003(150.00) |

### 场景 3：全局拼接（无分组，所有值拼接）

#### 需求：拼接所有用户的唯一订单 ID（无分组）

```sql
SELECT
    GROUP_CONCAT(DISTINCT order_id ORDER BY order_id) AS all_order_ids
FROM user_orders;
```

#### 结果输出

| all_order_ids       |
| :------------------ |
| O001,O002,O003,O004 |

### 场景 4：拼接结果长度限制（关键避坑）

`GROUP_CONCAT()` 有默认长度限制（默认 1024 字符），超出部分会被截断，需调整配置：

```sql
-- 1. 查看当前限制
SHOW VARIABLES LIKE 'group_concat_max_len';

-- 2. 临时调整（会话级别）
SET SESSION group_concat_max_len = 102400;  -- 设置为100KB

-- 3. 永久调整（修改my.cnf）
[mysqld]
group_concat_max_len = 102400
```

## 三、常见问题与避坑

### 问题 1：拼接结果为空

- 原因：分组内字段值全为 `NULL`；

- 解决方案：用 

  ```
  IFNULL
  ```

   处理空值：

  ```sql
  GROUP_CONCAT(IFNULL(order_id, '无订单'))
  ```

  

### 问题 2：拼接结果截断

- 原因：超出 `group_concat_max_len` 限制；
- 解决方案：按场景 4 调整长度限制。

### 问题 3：排序失效

- 原因：`ORDER BY` 写在 `GROUP_CONCAT` 外部；

- 解决方案：排序必须写在 

  ```
  GROUP_CONCAT
  ```

   内部：

  ```sql
  -- 错误写法
  GROUP_CONCAT(order_id) ORDER BY order_id DESC
  -- 正确写法
  GROUP_CONCAT(order_id ORDER BY order_id DESC)
  ```

  

## 四、扩展用法：非分组拼接（行转列）

若无需分组，仅需将单列所有值拼接为一行（逗号分隔），可结合 `GROUP BY 1` 或子查询：

```sql
-- 方式1：GROUP BY 常量
SELECT GROUP_CONCAT(DISTINCT order_id) AS all_orders
FROM user_orders
GROUP BY 1;

-- 方式2：子查询
SELECT (SELECT GROUP_CONCAT(DISTINCT order_id) FROM user_orders) AS all_orders;
```

## 总结

1. **核心函数**：`GROUP_CONCAT()` 是 MySQL 实现逗号拼接的核心，支持去重、排序、自定义分隔符；
2. **关键配置**：拼接长字符串时需调整 `group_concat_max_len`，避免结果截断；
3. **避坑要点**：空值用 `IFNULL` 处理，排序需写在函数内部，多字段拼接用 `CONCAT` 组合后再拼接；
4. **适用场景**：数仓报表中聚合维度值（如用户所有订单、商品所有标签）、行转列输出等。