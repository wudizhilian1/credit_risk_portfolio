-- dim_sample_data.sql
-- 为维度表插入样例数据
-- 使用方法：在 DuckDB CLI 中执行 .read sql/ddl/dim_sample_data.sql
-- 或通过 Python 执行

-- 清空现有数据（可选，避免主键冲突）
DELETE FROM dim_channel;
DELETE FROM dim_customer;
DELETE FROM dim_strategy;
DELETE FROM dim_reject_reason;

-- 插入渠道维表数据
INSERT INTO dim_channel (channel_id, channel_name, channel_type, is_active) VALUES
    ('APP', '手机应用', 'APP', true),
    ('WEB', '网页端', 'WEB', true),
    ('H5', 'H5页面', 'H5', true),
    ('API', 'API接口', 'API', true);

-- 插入客户维表数据
INSERT INTO dim_customer (user_id, user_name, age, registration_date, risk_level) VALUES
    ('user_1', '张三', 28, '2023-01-15', 'LOW'),
    ('user_2', '李四', 35, '2023-02-20', 'MEDIUM'),
    ('user_3', '王五', 42, '2023-03-10', 'HIGH'),
    ('user_4', '赵六', 31, '2023-04-05', 'MEDIUM'),
    ('user_5', '钱七', 45, '2023-05-12', 'HIGH'),
    ('user_6', '孙八', 26, '2023-06-18', 'LOW'),
    ('user_7', '周九', 38, '2023-07-22', 'MEDIUM'),
    ('user_8', '吴十', 29, '2023-08-30', 'LOW'),
    ('user_9', '郑十一', 41, '2023-09-14', 'HIGH'),
    ('user_10', '王十二', 33, '2023-10-01', 'MEDIUM');

-- 插入策略维表数据
INSERT INTO dim_strategy (strategy_version, strategy_name, effective_date, expiry_date, description) VALUES
    ('v1.0', '基础审批策略', '2024-01-01', '9999-12-31', '初始版本，包含基本规则'),
    ('v1.1', '优化版策略', '2024-01-15', '9999-12-31', '调整了风险评分阈值'),
    ('v2.0', '激进策略', '2024-02-01', NULL, '放宽部分限制以提高通过率');

-- 插入拒绝原因维表数据
INSERT INTO dim_reject_reason (reason_code, reason_desc, risk_level) VALUES
    ('FRAUD', '欺诈风险', 'HIGH'),
    ('OVER_LIMIT', '超出限额', 'MEDIUM'),
    ('RISK_SCORE', '风险评分不足', 'HIGH'),
    ('BLACKLIST', '命中黑名单', 'HIGH'),
    ('INCOME_LOW', '收入过低', 'MEDIUM'),
    ('AGE_LIMIT', '年龄不符合要求', 'LOW'),
    ('DUPLICATE_APPLY', '重复申请', 'MEDIUM');

-- 可选：检查插入结果
SELECT 'dim_channel' AS table_name, COUNT(*) AS rows FROM dim_channel
UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_strategy', COUNT(*) FROM dim_strategy
UNION ALL
SELECT 'dim_reject_reason', COUNT(*) FROM dim_reject_reason;