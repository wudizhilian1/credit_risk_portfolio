#!/usr/bin/env python3
"""
一键执行全链路 ETL，支持日期范围（单日或连续多日）。
用法：
    python run_full_etl.py --dt_start 2024-01-01 --dt_end 2024-01-15
    python run_full_etl.py --dt_start 2024-01-01              # 单日
    python run_full_etl.py                                   # 默认处理昨天
"""

import subprocess
import argparse
import time
import os
import duckdb
import datetime
import sys
import yaml
# 修复：读取 yaml 时指定 UTF-8 编码，并增加异常处理
try:
    with open('config.yaml', 'r', encoding='utf-8') as f:  # 关键：添加 encoding='utf-8'
        config = yaml.safe_load(f)
except FileNotFoundError:
    print("错误：config.yaml 文件不存在，请检查文件路径！")
    sys.exit(1)
except Exception as e:
    print(f"读取 config.yaml 失败：{e}")
    sys.exit(1)
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def run_subprocess(cmd_list):
    """执行子进程，检查返回值，并强制在项目根目录下运行"""
    print(f"执行: {' '.join(cmd_list)}")
    result = subprocess.run(cmd_list, cwd=PROJECT_DIR, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"错误输出: {result.stderr}")
        raise subprocess.CalledProcessError(result.returncode, cmd_list)
    print(result.stdout)
    return result

def generate_date_range(start_str, end_str):
    """生成日期列表（闭区间）"""
    start = datetime.datetime.strptime(start_str, '%Y-%m-%d')
    end = datetime.datetime.strptime(end_str, '%Y-%m-%d')
    date_list = []
    cur = start
    while cur <= end:
        date_list.append(cur.strftime('%Y-%m-%d'))
        cur += datetime.timedelta(days=1)
    return date_list

def get_next_run_id(con):
    # 查当前最大 run_id
    max_id = con.execute("SELECT COALESCE(MAX(run_id), 0) FROM etl_run_audit").fetchone()[0]
    return max_id + 1

def insert_audit_run(dt_start, dt_end,args, status, error_msg=None):
    """插入审计记录（简化版，仅记录运行范围）"""
    with duckdb.connect(args.db) as con:
        con.execute("""
            CREATE TABLE IF NOT EXISTS etl_run_audit (
                run_id          INTEGER PRIMARY KEY,
                start_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                end_time        TIMESTAMP,
                dt_start        DATE,
                dt_end          DATE,
                status          VARCHAR,
                error_message   TEXT,
                triggered_by    VARCHAR
            )
        """)
        next_run_id = get_next_run_id(con)
        con.execute("""
            INSERT INTO etl_run_audit (run_id, dt_start, dt_end, status, error_message, triggered_by)
            VALUES (?, ?, ?, ?, ?, ?)
        """, [next_run_id, dt_start, dt_end, status, error_msg, 'MANUAL' if '--dt_start' in sys.argv else 'SCHEDULER'])
        return next_run_id

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    parser.add_argument('--dt_start', help='起始日期 YYYY-MM-DD')
    parser.add_argument('--dt_end', help='结束日期 YYYY-MM-DD')
    args = parser.parse_args()
    db = args.db

    # 确定日期范围
    if not args.dt_start:
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime('%Y-%m-%d')
        dt_start = yesterday
        dt_end = yesterday
    else:
        dt_start = args.dt_start
        dt_end = args.dt_end if args.dt_end else args.dt_start

    date_list = generate_date_range(dt_start, dt_end)

    # 插入审计记录（运行开始）
    run_id = insert_audit_run(dt_start, dt_end, args, 'RUNNING')
    print(f"审计记录 run_id={run_id} 已创建")

    overall_start = time.time()
    try:
        for dt in date_list:
            print(f"\n===== 开始处理日期：{dt} =====")
            start_date = time.time()

            # 步骤1：raw → ODS
            print("步骤1：raw → ODS ...")
            run_subprocess(['python', 'scripts/etl_load_ods.py', '--dt', dt, '--db', db])

            # 步骤2：ODS → DWD 申请表去重
            print("步骤2：ODS → DWD 申请表去重 ...")
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/ods_to_dwd_apply.sql',
                            '--vars', f'dt_start={dt_start}', f'dt_end={dt_end}', '--db', db])

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
            if os.path.exists(os.path.join(PROJECT_DIR, 'sql/etl/load_to_event_date_table.sql')):
                print("步骤5：按事件日加载 ...")
                run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/etl/load_to_event_date_table.sql',
                                '--vars', f'dt={dt}', '--db', db])

            # 步骤6：对账检查（raw vs ODS vs DWD）
            print("步骤6：运行对账检查 ...")
            reconcile_out = f"reports/reconcile_{dt}.md"
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/reconcile_3layer_apply.sql',
                            '--vars', f'dt={dt}', '--out', reconcile_out, '--db', db])

            # 步骤7：插入对账摘要到 reconcile_summary
            print("步骤7：插入对账摘要到 reconcile_summary ...")
            with duckdb.connect(db) as con:
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
            # 步骤8：刷新 DWS 层（按日期范围）
            print("步骤8：刷新 DWS 层 ...")
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/dws/dws_channel_daily.sql',
                            '--vars', f'dt_start={dt_start}', f'dt_end={dt_end}', '--db', db])
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/dws/dws_strategy_daily.sql',
                            '--vars', f'dt_start={dt_start}', f'dt_end={dt_end}', '--db', db])
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/dws/dws_reject_topn_daily.sql',
                            '--vars', f'dt={dt}', '--db', db])
            # 构建特征宽表
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/features/build_feature_broad.sql',
                            '--vars', f'dt_start={dt_start}', f'dt_end={dt_end}', '--db', db])
            # 计算模型指标并写入评估表
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/features/calc_model_metrics.sql',
                            '--vars', f'base_date={dt_start}', f'eval_date={dt_end}','--db', db])
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/performance/refresh_mv.sql', '--db', db])
            # 特征稳定性监控
            print("步骤9：特征稳定性监控（PSI）...")
            run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/feature_stability.sql',
                            '--vars', f'eval_date={dt_start}', f'base_date={dt_end}', '--db', db])
            # 计算模型评估指标
            print("步骤10：计算 AUC/KS ...")
            run_subprocess(['python', 'scripts/calc_auc_ks.py', '--eval_date', dt, '--db', db])
            elapsed = time.time() - start_date
            print(f"===== 日期 {dt} ETL 完成，耗时 {elapsed:.2f} 秒 =====")

        # 所有日期处理完毕，执行最终检查
        print("\n===== 所有日期处理完成，运行最终检查 =====")
        # ADS vs DWS 对账
        run_subprocess(['python', 'scripts/run_sql.py', '--sql', 'sql/reconcile/ads_vs_dws_reconcile.sql',
                        '--out', 'reports/reconcile_ads.md', '--db', db])
        # 单元测试
        # run_subprocess(['pytest', 'tests/test_etl.py', '-v'])
        subprocess.run(['pytest', 'tests/test_etl.py', '-v'])
        # 告警引擎
        # run_subprocess(['python', 'scripts/alert_engine.py'])
        subprocess.run(['python', 'scripts/alert_engine.py'])
        # 更新审计记录为成功
        with duckdb.connect(db) as con:
            con.execute("UPDATE etl_run_audit SET end_time = CURRENT_TIMESTAMP, status = 'SUCCESS' WHERE run_id = ?", [run_id])
        overall_elapsed = time.time() - overall_start
        print(f"\n===== 全链路 ETL 完成，总耗时 {overall_elapsed:.2f} 秒 =====")

    except Exception as e:
        # 更新审计记录为失败
        with duckdb.connect(db) as con:
            con.execute("UPDATE etl_run_audit SET end_time = CURRENT_TIMESTAMP, status = 'FAILED', error_message = ? WHERE run_id = ?", [str(e), run_id])
        print(f"ETL 流程中断，错误: {e}")
        raise

if __name__ == '__main__':
    main()