-- sql/etl/ods_rule_hit_clean.sql
-- 功能：清洗 ods_rule_hit 表，写入 dwd_rule_hit_cleaned
-- 要求：dwd_rule_hit_cleaned 表需先创建

BEGIN TRANSACTION;

-- 1. 创建目标清洗表（如果不存在）
CREATE TABLE IF NOT EXISTS dwd_rule_hit_cleaned (
    apply_id          VARCHAR NOT NULL,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_flag          BOOLEAN,   -- 清洗后转为布尔
    hit_time          TIMESTAMP,
    dt                DATE NOT NULL
);

-- 2. 清空目标表（幂等）
DELETE FROM dwd_rule_hit_cleaned;

-- 3. 清洗并插入数据
INSERT INTO dwd_rule_hit_cleaned (apply_id, rule_id, rule_name, hit_flag, hit_time, dt)
SELECT
    apply_id,
    rule_id,
    rule_name,
    CASE
        WHEN LOWER(TRIM(hit_flag)) IN ('1', 'true', 'yes') THEN TRUE
        WHEN LOWER(TRIM(hit_flag)) IN ('0', 'false', 'no') THEN FALSE
        ELSE NULL
    END AS hit_flag,
    CASE
        WHEN hit_time IS NULL OR hit_time = '' THEN NULL
        ELSE TRY_CAST(hit_time AS TIMESTAMP)
    END AS hit_time,
    dt
FROM ods_rule_hit
WHERE apply_id IS NOT NULL AND apply_id != '';  -- 过滤空 apply_id

-- 4. 记录审计信息
CREATE TABLE IF NOT EXISTS etl_audit (
    etl_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    table_name VARCHAR,
    operation VARCHAR,
    rows_affected INT,
    description VARCHAR
);
INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_rule_hit_cleaned', 'CLEAN', COUNT(*), '清洗 ods_rule_hit'
FROM dwd_rule_hit_cleaned;

COMMIT;

-- 5. 输出统计信息
SELECT '清洗前原始行数' AS stage, COUNT(*) FROM ods_rule_hit
UNION ALL
SELECT '清洗后有效行数', COUNT(*) FROM dwd_rule_hit_cleaned
UNION ALL
SELECT 'hit_flag 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_flag IS NULL
UNION ALL
SELECT 'hit_time 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_time IS NULL;

-- 查看清洗后的数据
SELECT * FROM dwd_rule_hit_cleaned LIMIT 10;

-- 检查 NULL 分布
SELECT hit_flag, COUNT(*) FROM dwd_rule_hit_cleaned GROUP BY hit_flag;

-- 检查时间转换是否成功
SELECT hit_time, COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_time IS NOT NULL GROUP BY hit_time;