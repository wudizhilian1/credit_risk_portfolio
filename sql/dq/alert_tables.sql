CREATE TABLE IF NOT EXISTS dq_alert_rules (
    rule_id         INTEGER PRIMARY KEY,
    rule_name       VARCHAR NOT NULL,
    table_name      VARCHAR,
    metric          VARCHAR,
    field_name      VARCHAR,
    threshold_warn  DECIMAL(10,2),
    threshold_error DECIMAL(10,2),
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO dq_alert_rules (rule_id,rule_name, table_name, metric, field_name, threshold_warn, threshold_error, is_active) VALUES
(1,'行数波动-日环比', 'dws_channel_daily', 'row_count_pct_change', NULL, 10.0, 20.0, true),
(2,'空值率-策略名称', 'dws_strategy_daily', 'null_rate', 'strategy_name', 0.0, 0.0, true),
(3,'负值检测-申请量', 'dws_channel_daily', 'negative_amount_cnt', NULL, 0, 0, true),
(4,'ADS vs DWS 申请量差异', 'ads_overview_daily', 'apply_diff', NULL, 5, 20, true);

CREATE TABLE dq_alert_history (
    alert_id        INTEGER PRIMARY KEY,  -- 仅主键，无自增
    rule_id         INTEGER,              -- 保留rule_id字段，业务层保证关联关系
    rule_name       VARCHAR,
    alert_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    alert_level     VARCHAR,
    alert_message   VARCHAR,
    is_resolved     BOOLEAN DEFAULT false,
    resolved_time   TIMESTAMP
);