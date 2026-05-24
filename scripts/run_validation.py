# scripts/run_validation.py
# 功能：执行验证 SQL 文件，将结果输出到指定文件
# 用法：python run_validation.py --sql sql/validation/run_week5_validation.sql --out reports/week5_validation.txt

import duckdb
import argparse
import sys
import re

def convert_print_to_select(sql_content):
    """
    将 .print 'text' 转换为 SELECT 'text' AS msg;
    支持多行 .print 命令，简单处理。
    """
    lines = sql_content.split('\n')
    new_lines = []
    for line in lines:
        # 匹配 .print 后面跟着的字符串（单引号或双引号）
        match = re.match(r'^\s*\.print\s+([\'"])(.*)\1\s*$', line)
        if match:
            text = match.group(2)
            new_lines.append(f"SELECT '{text}' AS msg;")
        else:
            new_lines.append(line)
    return '\n'.join(new_lines)

def main():
    parser = argparse.ArgumentParser(description='Run SQL validation script and save output')
    parser.add_argument('--sql', required=True, help='SQL 文件路径')
    parser.add_argument('--out', default='reports/validation.txt', help='输出文件路径')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    args = parser.parse_args()

    # 读取 SQL 文件
    with open(args.sql, 'r', encoding='utf-8') as f:
        sql_content = f.read()

    # 转换 .print 命令
    sql_content = convert_print_to_select(sql_content)

    # 分割语句（以分号分隔）
    statements = [s.strip() for s in sql_content.split(';') if s.strip()]

    con = duckdb.connect(args.db)

    # 收集输出
    output_lines = []

    for stmt in statements:
        if not stmt:
            continue
        try:
            # 执行查询，获取结果
            result = con.execute(stmt).fetchdf()
            # 如果结果非空，格式化为表格输出
            if not result.empty:
                # 使用 pandas 的 to_string 或 to_markdown
                output_lines.append(stmt)  # 可选：记录执行的 SQL
                output_lines.append(result.to_string(index=False))
                output_lines.append('')  # 空行分隔
            else:
                # 无结果，可能是 DDL 或空查询，不输出
                pass
        except Exception as e:
            output_lines.append(f"错误: {e}\n语句: {stmt}")

    con.close()

    # 写入输出文件
    with open(args.out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(output_lines))

    print(f"验证完成，结果已保存至 {args.out}")

if __name__ == '__main__':
    main()