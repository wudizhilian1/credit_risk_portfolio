#!/usr/bin/env python3
"""
etl_load_ods.py - 将指定日期的数据从 raw 加载到 ODS 表
用法：
    python etl_load_ods.py --dt 2024-01-01
    python etl_load_ods.py --dt 2024-01-01 --db dev.duckdb
"""

import duckdb
import argparse
import time
from datetime import datetime
import logging

# 配置日志格式（时间、级别、消息）
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/etl.log'),  # 输出到文件
        logging.StreamHandler()               # 同时输出到控制台
    ]
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(description='Load raw data to ODS tables')
    parser.add_argument('--dt', required=True, help='日期，格式 YYYY-MM-DD')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    args = parser.parse_args()

    dt = args.dt
    db = args.db
    con = duckdb.connect(db)

    # 开始事务
    con.execute("BEGIN TRANSACTION")

    try:
        # 1. 记录输入行数（从视图读取）
        apply_input = con.execute(f"SELECT COUNT(*) FROM v_apply WHERE dt = '{dt}'").fetchone()[0]
        decision_input = con.execute(f"SELECT COUNT(*) FROM v_decision WHERE dt = '{dt}'").fetchone()[0]

        # print(f"[{dt}] 输入行数: apply={apply_input}, decision={decision_input}")
        logger.info(f"[{dt}] 输出行数: apply={apply_input}, decision={decision_input}")

        # 2. 幂等删除
        con.execute(f"DELETE FROM ods_apply WHERE dt = '{dt}'")
        con.execute(f"DELETE FROM ods_decision WHERE dt = '{dt}'")

        # 3. 插入数据
        con.execute(f"""
            INSERT INTO ods_apply (apply_id, user_id, channel_id, amount, apply_time, update_time, dt)
            SELECT apply_id, user_id, channel_id, amount, apply_time, update_time, dt
            FROM v_apply
            WHERE dt = '{dt}'
        """)
        con.execute(f"""
            INSERT INTO ods_decision (apply_id, decision, reject_reason, strategy_version, decision_time, dt)
            SELECT apply_id, decision, reject_reason, strategy_version, decision_time, dt
            FROM v_decision
            WHERE dt = '{dt}'
        """)

        # 4. 验证输出行数
        apply_output = con.execute(f"SELECT COUNT(*) FROM ods_apply WHERE dt = '{dt}'").fetchone()[0]
        decision_output = con.execute(f"SELECT COUNT(*) FROM ods_decision WHERE dt = '{dt}'").fetchone()[0]

        # print(f"[{dt}] 输出行数: apply={apply_output}, decision={decision_output}")
        logger.info(f"[{dt}] 输出行数: apply={apply_output}, decision={decision_output}")
        # 5. 可选：写入审计表（如果存在）
        # 可创建 ods_load_audit 表记录每次加载的元数据
        con.execute(f"""
            CREATE TABLE IF NOT EXISTS ods_load_audit (
                load_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                dt VARCHAR,
                table_name VARCHAR,
                input_rows INT,
                output_rows INT
            )
        """)
        con.execute(f"""
            INSERT INTO ods_load_audit (dt, table_name, input_rows, output_rows)
            VALUES ('{dt}', 'apply', {apply_input}, {apply_output}),
                   ('{dt}', 'decision', {decision_input}, {decision_output})
        """)

        con.execute("COMMIT")
        # print(f"[{dt}] 加载成功，审计记录已写入。")
        logger.info(f"[{dt}] 加载成功，审计记录已写入。")
    except Exception as e:
        con.execute("ROLLBACK")
        logger.error(f"错误: {e}")
        # print(f"错误: {e}")
        raise

if __name__ == '__main__':
    main()