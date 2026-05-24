import duckdb
import argparse
import pathlib
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="dev.duckdb")
    parser.add_argument("--raw", default="data/raw")
    args = parser.parse_args()

    print(f"连接数据库: {args.db}")
    con = duckdb.connect(args.db)

    raw_path = pathlib.Path(args.raw)
    print(f"原始数据路径: {raw_path.absolute()}")

    # 检查路径是否存在
    if not raw_path.exists():
        print(f"错误: 路径 {raw_path} 不存在")
        sys.exit(1)

    # 检查 apply 子目录
    apply_glob = raw_path / "apply" / "dt=*" / "**" / "*.parquet"
    print(f"查找文件: {apply_glob}")
    files = list(raw_path.glob("apply/dt=*/**/*.parquet"))
    print(f"找到 apply 文件数: {len(files)}")
    if not files:
        print("错误: 未找到任何 apply 的 parquet 文件，请先运行 generate_demo_data.py")
        sys.exit(1)

    try:
        # 创建视图（使用正斜杠确保跨平台）
        raw_str = str(raw_path).replace('\\', '/')
        con.execute(f"""
            CREATE OR REPLACE VIEW v_apply AS
            SELECT * FROM read_parquet('{raw_str}/apply/dt=*/**/*.parquet', hive_partitioning=1);
        """)
        print("视图 v_apply 创建成功")

        con.execute(f"""
            CREATE OR REPLACE VIEW v_decision AS
            SELECT * FROM read_parquet('{raw_str}/decision/dt=*/**/*.parquet', hive_partitioning=1);
        """)
        print("视图 v_decision 创建成功")

        # 可选：验证视图
        cnt = con.execute("SELECT COUNT(*) FROM v_apply WHERE dt='2024-01-01'").fetchone()[0]
        print(f"验证: v_apply 中 2024-01-01 的数据行数: {cnt}")

    except Exception as e:
        print(f"创建视图时发生错误: {e}")
        sys.exit(1)

    print("OK: created views v_apply, v_decision in", args.db)

if __name__ == "__main__":
    main()