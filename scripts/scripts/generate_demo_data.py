"""
generate_demo_data.py
生成模拟的申请(apply)和决策(decision)数据，按 dt 分区存储为 Parquet 文件。
支持自定义日期范围，可灵活扩展数据量。
"""

import duckdb
import pathlib
import random
from datetime import date, timedelta

# ==================== 配置参数 ====================
# 数据根目录
RAW_PATH = pathlib.Path("data/raw")

# 每天生成的申请/决策记录数（可根据需要调整）
NUM_APPLY_PER_DAY = 5000
NUM_DECISION_PER_DAY = 5000

# 生成数据的日期范围（包含起止日期）
START_DATE = date(2024, 1, 1)
END_DATE = date(2024, 1, 1)   # 生成1月1日~1月30日共30天数据

# 随机种子（保证可重复性）
RANDOM_SEED = 42
random.seed(RANDOM_SEED)

# 可选渠道、用户池、决策结果等
CHANNELS = ["APP", "WEB", "H5", "API"]
USERS = [f"user_{i}" for i in range(1, 2001)]
DECISIONS = ["PASS", "REJECT", "REVIEW"]
REJECT_REASONS = ["FRAUD", "OVER_LIMIT", "RISK_SCORE", "BLACKLIST", None]
STRATEGY_VERSIONS = ["v1.0", "v1.1", "v2.0"]


# ==================== 数据生成函数 ====================
def generate_apply(dt: str):
    data = []
    # 基础申请量
    if dt == '2024-01-15':
        day_apply_cnt = NUM_APPLY_PER_DAY * 2   # 申请量翻倍
    else:
        day_apply_cnt = NUM_APPLY_PER_DAY

    for i in range(day_apply_cnt):
        apply_id = f"{dt}_{i}"
        user_id = random.choice(USERS)
        channel_id = random.choice(CHANNELS)
        # 异常金额：1月25日部分金额异常
        if dt == '2024-01-25' and i % 10 == 0:   # 每10条一条异常
            amount = random.randint(-1000, 50000)  # 可能出现负数
        else:
            amount = random.randint(1000, 50000)

        hour = random.randint(0, 23)
        minute = random.randint(0, 59)
        second = random.randint(0, 59)
        apply_time = f"{dt} {hour:02d}:{minute:02d}:{second:02d}"
        update_time = apply_time
        data.append((apply_id, user_id, channel_id, amount, apply_time, update_time))
    return data

def generate_decision(dt: str):
    data = []
    # 决策量通常应与申请量一致，但可以调整
    if dt == '2024-01-15':
        day_decision_cnt = NUM_DECISION_PER_DAY * 2
    else:
        day_decision_cnt = NUM_DECISION_PER_DAY

    for i in range(day_decision_cnt):
        apply_id = f"{dt}_{i}"
        # 异常通过率：1月20日提高拒绝概率
        if dt == '2024-01-20':
            # 降低通过率，增加拒绝
            decision = random.choices(['PASS', 'REJECT', 'REVIEW'], weights=[0.3, 0.5, 0.2])[0]
        else:
            decision = random.choice(DECISIONS)

        reason = random.choice(REJECT_REASONS) if decision == 'REJECT' else None
        version = random.choice(STRATEGY_VERSIONS)
        hour = random.randint(0, 23)
        minute = random.randint(0, 59)
        second = random.randint(0, 59)
        decision_time = f"{dt} {hour:02d}:{minute:02d}:{second:02d}"
        data.append((apply_id, decision, reason, version, decision_time))
    return data


def write_partition(con, table_name, dt, data, columns):
    """
    将数据写入对应分区的 Parquet 文件
    - con: DuckDB 连接
    - table_name: 'apply' 或 'decision'
    - dt: 日期字符串 'YYYY-MM-DD'
    - data: 元组列表，每行数据
    - columns: 列名列表
    """
    # 创建临时表（使用 VARCHAR 类型简化）
    col_defs = ', '.join([f'"{col}" VARCHAR' for col in columns])
    con.execute(f"CREATE OR REPLACE TEMP TABLE tmp ({col_defs})")

    # 批量插入数据
    placeholders = ','.join(['?'] * len(columns))
    insert_sql = f"INSERT INTO tmp VALUES ({placeholders})"
    con.executemany(insert_sql, data)

    # 写出分区 Parquet
    path = RAW_PATH / table_name / f"dt={dt}" / "data.parquet"
    path.parent.mkdir(parents=True, exist_ok=True)
    con.execute(f"COPY tmp TO '{path}' (FORMAT PARQUET)")
    print(f"Written {path}")


# ==================== 主程序 ====================
def main():
    # 生成日期列表
    delta = END_DATE - START_DATE
    days = [(START_DATE + timedelta(days=i)).strftime("%Y-%m-%d") for i in range(delta.days + 1)]
    print(f"将生成 {len(days)} 天的数据：{days[0]} 到 {days[-1]}")

    con = duckdb.connect()  # 使用内存数据库，无需持久化文件

    for dt in days:
        # 生成申请数据
        apply_data = generate_apply(dt)
        apply_cols = ["apply_id", "user_id", "channel_id", "amount", "apply_time", "update_time"]
        write_partition(con, "apply", dt, apply_data, apply_cols)

        # 生成决策数据
        decision_data = generate_decision(dt)
        decision_cols = ["apply_id", "decision", "reject_reason", "strategy_version", "decision_time"]
        write_partition(con, "decision", dt, decision_data, decision_cols)

    print("所有数据生成完成！")


if __name__ == "__main__":
    main()