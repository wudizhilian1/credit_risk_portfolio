#!/usr/bin/env python3
"""
run_sql.py - 执行 SQL 文件并输出结果到 Markdown 报告
支持变量替换（如 {{dt}}），自动处理多条 SQL 语句
"""

import duckdb
import argparse
import pathlib
import sys

def load_sql(path: str) -> str:
    """读取 SQL 文件内容"""
    return pathlib.Path(path).read_text(encoding='utf-8')

def apply_vars(sql: str, vars_dict: dict) -> str:
    """替换 SQL 中的 {{变量名}} 为实际值"""
    for key, value in vars_dict.items():
        sql = sql.replace("{{" + key + "}}", str(value))
    return sql

def parse_vars(var_items):
    """将 ['dt=2024-01-01', 'dt_minus7=2024-01-24'] 解析为字典"""
    kv = {}
    for item in var_items:
        if '=' not in item:
            continue
        k, v = item.split('=', 1)
        kv[k.strip()] = v.strip()
    return kv

def main():
    parser = argparse.ArgumentParser(description='执行 SQL 文件并输出结果')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件路径')
    parser.add_argument('--sql', required=True, help='要执行的 SQL 文件路径')
    parser.add_argument('--vars', nargs='*', default=[], help='变量替换，例如 dt=2024-01-01 dt_minus7=2024-01-24')
    parser.add_argument('--out', default='reports/run_sql_output.txt', help='输出文件路径（支持 .md/.txt）')
    args = parser.parse_args()

    # 连接数据库
    con = duckdb.connect(args.db)

    # 加载 SQL 并替换变量
    raw_sql = load_sql(args.sql)
    vars_dict = parse_vars(args.vars)
    sql_with_vars = apply_vars(raw_sql, vars_dict)

    # 分割多条语句（以分号分隔，忽略空语句）
    statements = [s.strip() for s in sql_with_vars.split(';') if s.strip()]

    out_lines = []
    for i, stmt in enumerate(statements, start=1):
        try:
            # 执行并获取结果 DataFrame
            df = con.execute(stmt).fetchdf()
            out_lines.append(f"--- 语句 {i} ---\n```sql\n{stmt}\n```\n")
            out_lines.append(f"行数: {len(df)}\n")
            if len(df) > 0:
                out_lines.append(df.head(10).to_markdown(index=False) + "\n")
            else:
                out_lines.append("(空结果集)\n")
        except Exception as e:
            out_lines.append(f"--- 语句 {i} 执行失败 ---\n```sql\n{stmt}\n```\n")
            out_lines.append(f"错误: {e}\n")
            # 提前写入失败输出，便于调试
            pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
            pathlib.Path(args.out).write_text("\n".join(out_lines), encoding='utf-8')
            print(f"执行失败，已保存部分输出至 {args.out}")
            sys.exit(1)

    # 确保输出目录存在
    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # 写入最终输出
    out_path.write_text("\n".join(out_lines), encoding='utf-8')
    print(f"执行完成，结果已保存至 {args.out}")

if __name__ == '__main__':
    main()