-- ods_rule_hit_clean.sql
-- 功能：清洗 ods_rule_hit 表，将结果写入 dwd_rule_hit_cleaned
-- 清洗规则：
--   - hit_flag 标准化为布尔值（'1'/'true'/'yes' → TRUE，'0'/'false'/'no' → FALSE，其余 NULL）
--   - hit_time 转换为 TIMESTAMP，无效值置 NULL
--   - 过滤 apply_id 为空的行

BEGIN TRANSACTION;

-- 创建目标清洗表（如果不存在）
CREATE TABLE IF NOT EXISTS dwd_rule_hit_cleaned (
    apply_id          VARCHAR NOT NULL,
    rule_id           VARCHAR,
    rule_name         VARCHAR,
    hit_flag          BOOLEAN,
    hit_time          TIMESTAMP,
    dt                DATE NOT NULL
);

-- 清空目标表（幂等）
DELETE FROM dwd_rule_hit_cleaned;

-- 清洗并插入数据
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
WHERE apply_id IS NOT NULL AND apply_id != '';

-- 记录审计
INSERT INTO etl_audit (table_name, operation, rows_affected, description)
SELECT 'dwd_rule_hit_cleaned', 'CLEAN', COUNT(*), '清洗 ods_rule_hit'
FROM dwd_rule_hit_cleaned;

COMMIT;

-- 输出清洗统计
SELECT '清洗前原始行数' AS stage, COUNT(*) FROM ods_rule_hit
UNION ALL
SELECT '清洗后有效行数', COUNT(*) FROM dwd_rule_hit_cleaned
UNION ALL
SELECT 'hit_flag 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_flag IS NULL
UNION ALL
SELECT 'hit_time 为 NULL 行数', COUNT(*) FROM dwd_rule_hit_cleaned WHERE hit_time IS NULL;