#!/usr/bin/env python3
"""
一键执行全链路 ETL，从 raw 到 DWD，并运行对账。
用法：python run_full_etl.py --dt 2024-01-01
"""

import subprocess
import argparse
import time
import os
import duckdb

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# def run_subprocess(cmd_list):
#     """执行子进程，检查返回值"""
#     print(f"执行: {' '.join(cmd_list)}")
#     result = subprocess.run(cmd_list, capture_output=True, text=True)
#     if result.returncode != 0:
#         print(f"错误输出: {result.stderr}")
#         raise subprocess.CalledProcessError(result.returncode, cmd_list)
#     print(result.stdout)
#     return result


def run_subprocess(cmd_list):
    """执行子进程，检查返回值，并强制在项目根目录下运行"""
    print(f"执行: {' '.join(cmd_list)}")
    result = subprocess.run(cmd_list, cwd=PROJECT_DIR, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"错误输出: {result.stderr}")
        raise subprocess.CalledProcessError(result.returncode, cmd_list)
    print(result.stdout)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dt', required=True, help='日期，格式 YYYY-MM-DD')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    args = parser.parse_args()
    dt = args.dt
    db = args.db

    print(f"===== 开始全链路 ETL，日期：{dt} =====")
    start_total = time.time()

    try:
        # 步骤1：raw → ODS
        print("步骤1：raw → ODS ...")
        run_subprocess(['python', 'scripts/etl_load_ods.py', '--dt', dt, '--db', db])

        # 步骤2：ODS → DWD 申请表去重
        print("步骤2：ODS → DWD 申请表去重 ...")
        run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/ods_to_dwd_apply.sql',
                        '--vars', f'dt={dt}', '--db', db])

        # 步骤3：ODS → DWD 决策表去重
        print("步骤3：ODS → DWD 决策表去重 ...")
        run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/ods_to_dwd_decision.sql',
                        '--vars', f'dt={dt}', '--db', db])

        # 步骤4：可选：规则命中清洗
        if os.path.exists(os.path.join(PROJECT_DIR, 'sql/etl/ods_rule_hit_clean.sql')):
            print("步骤4：规则命中清洗 ...")
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/ods_rule_hit_clean.sql',
                            '--vars', f'dt={dt}', '--db', db])

        # 步骤5：可选：按事件日加载
        if os.path.exists('sql/etl/load_to_event_date_table.sql'):
            print("步骤5：按事件日加载 ...")
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/load_to_event_date_table.sql',
                            '--vars', f'dt={dt}', '--db', db])

        # 步骤6：对账检查
        print("步骤6：运行对账检查 ...")
        reconcile_out = f"reports/reconcile_{dt}.md"
        run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/reconcile_3layer_apply.sql',
                        '--vars', f'dt={dt}', '--out', reconcile_out, '--db', db])

        # 步骤7：插入对账摘要到 reconcile_summary（直接使用 Python 连接）
        print("步骤7：插入对账摘要到 reconcile_summary ...")
        with duckdb.connect(db) as con:
            # 确保 reconcile_summary 表存在
            con.execute("""
                CREATE TABLE IF NOT EXISTS reconcile_summary (
                    check_date DATE,
                    layer1 VARCHAR,
                    layer2 VARCHAR,
                    rows_layer1 INT,
                    rows_layer2 INT,
                    diff_count INT,
                    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            # 插入数据（使用参数化查询）
            con.execute("""
                INSERT INTO reconcile_summary (check_date, layer1, layer2, rows_layer1, rows_layer2, diff_count)
                SELECT
                    ?,
                    'raw', 'ods',
                    (SELECT COUNT(*) FROM v_apply WHERE dt = ?),
                    (SELECT COUNT(*) FROM ods_apply WHERE dt = ?),
                    (SELECT COUNT(*) FROM (
                        SELECT apply_id FROM v_apply WHERE dt = ?
                        EXCEPT
                        SELECT apply_id FROM ods_apply WHERE dt = ?
                    ) t)
            """, [dt, dt, dt, dt, dt])
        print("对账摘要插入成功")

        elapsed = time.time() - start_total
        print(f"===== 全链路 ETL 完成，耗时 {elapsed:.2f} 秒 =====")
        print(f"对账报告已保存至 {reconcile_out}")

    except subprocess.CalledProcessError as e:
        print(f"ETL 流程中断，错误命令: {e.cmd}")
        raise
    # 对账检查
    subprocess.run(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/ads_vs_dws_reconcile.sql', '--out',
                    'reports/reconcile_ads.md'])
    # 运行单元测试
    subprocess.run(['pytest', 'tests/test_etl.py', '-v'])
    subprocess.run(['python', 'scripts/alert_engine.py'])
if __name__ == '__main__':
    main()