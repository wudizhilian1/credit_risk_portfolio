-- 申请事实表（ODS层）
CREATE TABLE IF NOT EXISTS ods_apply (
    apply_id          VARCHAR NOT NULL,      -- 申请单ID（主键）
    user_id           VARCHAR NOT NULL,      -- 用户ID
    channel_id        VARCHAR,               -- 渠道ID
    amount            DECIMAL(18,2),         -- 申请金额
    apply_time        TIMESTAMP,             -- 申请时间
    update_time       TIMESTAMP,             -- 更新时间
    dt                DATE NOT NULL          -- 分区日期（事件日）
);
COMMENT ON TABLE ods_apply IS 'ODS层申请事实表，按事件日分区';
COMMENT ON COLUMN ods_apply.apply_id IS '申请单唯一标识';
COMMENT ON COLUMN ods_apply.user_id IS '用户标识';
COMMENT ON COLUMN ods_apply.channel_id IS '渠道ID，关联dim_channel';
COMMENT ON COLUMN ods_apply.amount IS '申请金额，单位元';
COMMENT ON COLUMN ods_apply.apply_time IS '申请时间戳';
COMMENT ON COLUMN ods_apply.update_time IS '记录更新时间';
COMMENT ON COLUMN ods_apply.dt IS '分区日期，取自申请时间';
--创建 ODS 决策事实表（ods_decision）
CREATE TABLE IF NOT EXISTS ods_decision (
    apply_id          VARCHAR NOT NULL,      -- 申请单ID（主键）
    decision          VARCHAR,               -- 决策结果：PASS/REJECT/REVIEW
    reject_reason     VARCHAR,               -- 拒绝原因代码（若为REJECT）
    strategy_version  VARCHAR,               -- 策略版本号
    decision_time     TIMESTAMP,             -- 决策时间
    dt                DATE NOT NULL          -- 分区日期（事件日）
);
COMMENT ON TABLE ods_decision IS 'ODS层决策事实表';
COMMENT ON COLUMN ods_decision.apply_id IS '申请单ID，关联ods_apply';
COMMENT ON COLUMN ods_decision.decision IS '决策结果';
COMMENT ON COLUMN ods_decision.reject_reason IS '拒绝原因代码，关联dim_reject_reason';
COMMENT ON COLUMN ods_decision.strategy_version IS '策略版本，关联dim_strategy';
COMMENT ON COLUMN ods_decision.decision_time IS '决策时间戳';
COMMENT ON COLUMN ods_decision.dt IS '分区日期，取自决策时间';
--#创建渠道维表（dim_channel）
CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id        VARCHAR PRIMARY KEY,  -- 渠道ID
    channel_name      VARCHAR,              -- 渠道名称
    channel_type      VARCHAR,              -- 渠道类型：APP/WEB/H5/API
    is_active         BOOLEAN DEFAULT true, -- 是否有效
    create_time       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE dim_channel IS '渠道维度表';
COMMENT ON COLUMN dim_channel.channel_id IS '渠道唯一标识';
COMMENT ON COLUMN dim_channel.channel_name IS '渠道名称';
COMMENT ON COLUMN dim_channel.channel_type IS '渠道类型';
COMMENT ON COLUMN dim_channel.is_active IS '是否有效';
--创建客户维表（dim_customer）
CREATE TABLE IF NOT EXISTS dim_customer (
    user_id           VARCHAR PRIMARY KEY,  -- 用户ID
    user_name         VARCHAR,              -- 用户姓名（模拟）
    age               INT,                  -- 年龄
    registration_date DATE,                 -- 注册日期
    risk_level        VARCHAR               -- 风险等级：LOW/MEDIUM/HIGH
);
COMMENT ON TABLE dim_customer IS '客户维度表';
COMMENT ON COLUMN dim_customer.user_id IS '用户唯一标识';
COMMENT ON COLUMN dim_customer.user_name IS '用户姓名';
COMMENT ON COLUMN dim_customer.age IS '年龄';
COMMENT ON COLUMN dim_customer.registration_date IS '注册日期';
COMMENT ON COLUMN dim_customer.risk_level IS '风险等级';
--创建策略维表（dim_strategy）
CREATE TABLE IF NOT EXISTS dim_strategy (
    strategy_version  VARCHAR PRIMARY KEY,  -- 策略版本
    strategy_name     VARCHAR,              -- 策略名称
    effective_date    DATE,                 -- 生效日期
    expiry_date       DATE,                 -- 失效日期
    description       VARCHAR               -- 描述
);
COMMENT ON TABLE dim_strategy IS '策略维度表';
--创建拒绝原因维表（dim_reject_reason）
CREATE TABLE IF NOT EXISTS dim_reject_reason (
    reason_code       VARCHAR PRIMARY KEY,  -- 原因代码
    reason_desc       VARCHAR,              -- 原因描述
    risk_level        VARCHAR               -- 关联的风险等级
);
COMMENT ON TABLE dim_reject_reason IS '拒绝原因维度表';