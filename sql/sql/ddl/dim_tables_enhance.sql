-- 渠道维表增强
ALTER TABLE dim_channel ADD COLUMN IF NOT EXISTS channel_group VARCHAR; -- 渠道分组（如自有/外部）
ALTER TABLE dim_channel ADD COLUMN IF NOT EXISTS priority INT; -- 优先级（数值越小越优先）
UPDATE dim_channel SET channel_group = '自有', priority = 1 WHERE channel_id = 'APP';
UPDATE dim_channel SET channel_group = '自有', priority = 2 WHERE channel_id = 'WEB';
UPDATE dim_channel SET channel_group = '自有', priority = 3 WHERE channel_id = 'H5';
UPDATE dim_channel SET channel_group = '外部', priority = 4 WHERE channel_id = 'API';

-- 客户维表增强
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS gender VARCHAR; -- 性别
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS city VARCHAR; -- 城市
ALTER TABLE dim_customer ADD COLUMN IF NOT EXISTS credit_score INT; -- 信用分（模拟）
UPDATE dim_customer SET gender = '男', city = '北京', credit_score = 720 WHERE user_id = 'user_1';
UPDATE dim_customer SET gender = '女', city = '上海', credit_score = 680 WHERE user_id = 'user_2';
UPDATE dim_customer SET gender = '男', city = '广州', credit_score = 650 WHERE user_id = 'user_3';
UPDATE dim_customer SET gender = '女', city = '深圳', credit_score = 700 WHERE user_id = 'user_4';
UPDATE dim_customer SET gender = '男', city = '成都', credit_score = 690 WHERE user_id = 'user_5';
UPDATE dim_customer SET gender = '女', city = '杭州', credit_score = 710 WHERE user_id = 'user_6';
UPDATE dim_customer SET gender = '男', city = '武汉', credit_score = 670 WHERE user_id = 'user_7';
UPDATE dim_customer SET gender = '女', city = '南京', credit_score = 730 WHERE user_id = 'user_8';
UPDATE dim_customer SET gender = '男', city = '重庆', credit_score = 640 WHERE user_id = 'user_9';
UPDATE dim_customer SET gender = '女', city = '天津', credit_score = 695 WHERE user_id = 'user_10';

-- 策略维表增强
ALTER TABLE dim_strategy ADD COLUMN IF NOT EXISTS strategy_type VARCHAR; -- 策略类型：准入/反欺诈/额度
ALTER TABLE dim_strategy ADD COLUMN IF NOT EXISTS owner_team VARCHAR; -- 所属团队
UPDATE dim_strategy SET strategy_type = '准入', owner_team = '风控策略组' WHERE strategy_version = 'v1.0';
UPDATE dim_strategy SET strategy_type = '准入', owner_team = '风控策略组' WHERE strategy_version = 'v1.1';
UPDATE dim_strategy SET strategy_type = '额度', owner_team = '额度管理组' WHERE strategy_version = 'v2.0';

-- 拒绝原因维表增强
ALTER TABLE dim_reject_reason ADD COLUMN IF NOT EXISTS reason_category VARCHAR; -- 原因类别：欺诈/信用/黑名单/规则
UPDATE dim_reject_reason SET reason_category = '欺诈' WHERE reason_code = 'FRAUD';
UPDATE dim_reject_reason SET reason_category = '信用' WHERE reason_code = 'RISK_SCORE';
UPDATE dim_reject_reason SET reason_category = '信用' WHERE reason_code = 'OVER_LIMIT';
UPDATE dim_reject_reason SET reason_category = '黑名单' WHERE reason_code = 'BLACKLIST';
UPDATE dim_reject_reason SET reason_category = '信用' WHERE reason_code = 'INCOME_LOW';
UPDATE dim_reject_reason SET reason_category = '规则' WHERE reason_code = 'AGE_LIMIT';
UPDATE dim_reject_reason SET reason_category = '规则' WHERE reason_code = 'DUPLICATE_APPLY';