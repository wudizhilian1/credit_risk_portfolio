#!/usr/bin/env python3
import duckdb
import smtplib
from email.mime.text import MIMEText

def fetch_monitor_data(con, rule):
    """根据规则从监控表获取最新监控值"""
    metric = rule['metric']
    table_name = rule.get('table_name')
    field_name = rule.get('field_name', '')  # 从规则表获取字段名（如果有）

    if metric == 'row_count_pct_change':
        # 行数波动：从 dq_dws_monitor 获取最新行数变化百分比
        res = con.execute(f"""
            SELECT row_count_pct_change
            FROM dq_dws_monitor
            WHERE table_name = '{table_name}'
            ORDER BY monitor_date DESC LIMIT 1
        """).fetchone()
        return res[0] if res else None

    elif metric == 'null_rate':
        # 空值率：从 dq_dws_monitor 获取指定字段的最新空值率
        if not field_name:
            print("警告：空值规则缺少 field_name")
            return None
        res = con.execute(f"""
            SELECT null_rate
            FROM dq_dws_monitor
            WHERE null_field = '{field_name}'
            ORDER BY monitor_date DESC LIMIT 1
        """).fetchone()
        return res[0] if res else None

    elif metric == 'negative_amount_cnt':
        # 负值检测：从 dq_dws_monitor 获取最新负值数量
        res = con.execute(f"""
            SELECT negative_amount_cnt
            FROM dq_dws_monitor
            WHERE table_name = '{table_name}'
            ORDER BY monitor_date DESC LIMIT 1
        """).fetchone()
        return res[0] if res else None

    elif metric == 'apply_diff':
        # ADS vs DWS 差异：从 reconcile_ads_log 获取最新申请量差异
        res = con.execute(f"""
            SELECT diff
            FROM reconcile_ads_log
            WHERE metric = 'apply_cnt'
            ORDER BY check_time DESC LIMIT 1
        """).fetchone()
        return res[0] if res else None

    else:
        print(f"未知指标类型: {metric}")
        return None

def check_rule(con, rule):
    """根据规则检查监控数据，返回告警级别和消息"""
    value = fetch_monitor_data(con, rule)
    if value is None:
        return None, f"无监控数据或数据为空"

    val = abs(value)  # 绝对值比较（波动、差异等）
    if rule['threshold_error'] is not None and val >= rule['threshold_error']:
        return 'ERROR', f"{rule['rule_name']} 值为 {value:.2f}，超过错误阈值 {rule['threshold_error']}"
    elif rule['threshold_warn'] is not None and val >= rule['threshold_warn']:
        return 'WARN', f"{rule['rule_name']} 值为 {value:.2f}，超过警告阈值 {rule['threshold_warn']}"
    return None, None

def send_alert(alert_level, message):
    """发送告警（控制台 + 可选邮件）"""
    print(f"[{alert_level}] {message}")
    # 邮件示例（需配置 SMTP）
    # if alert_level in ('ERROR', 'WARN'):
    #     msg = MIMEText(message)
    #     msg['Subject'] = f"[{alert_level}] 数据质量告警"
    #     msg['From'] = 'monitor@example.com'
    #     msg['To'] = 'team@example.com'
    #     smtp.send_message(msg)
def get_next_alert_id(con):
    """获取下一个自增alert_id"""
    max_id = con.execute("SELECT COALESCE(MAX(alert_id), 0) FROM dq_alert_history").fetchone()[0]
    return max_id + 1

def main():
    con = duckdb.connect('dev.duckdb')
    # 获取所有激活的规则
    rules = con.execute("""
        SELECT rule_id, rule_name, table_name, metric, field_name, threshold_warn, threshold_error
        FROM dq_alert_rules
        WHERE is_active = 1
    """).fetchall()

    for rule in rules:
        rule_dict = {
            'rule_id': rule[0],
            'rule_name': rule[1],
            'table_name': rule[2],
            'metric': rule[3],
            'field_name': rule[4],
            'threshold_warn': rule[5],
            'threshold_error': rule[6]
        }
        level, msg = check_rule(con, rule_dict)
        if level:
            alert_id = get_next_alert_id(con)
            print(alert_id)
            # 插入告警历史
            con.execute("""
                INSERT INTO dq_alert_history (alert_id, rule_id, rule_name, alert_level, alert_message)
                VALUES (?, ?, ?, ?, ?)
            """, [alert_id, rule_dict['rule_id'], rule_dict['rule_name'], level, msg])
            # 发送告警
            send_alert(level, msg)

    con.close()

if __name__ == '__main__':
    main()