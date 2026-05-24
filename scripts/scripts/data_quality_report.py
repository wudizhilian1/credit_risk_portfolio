#!/usr/bin/env python3
"""
数据质量报告生成脚本
用法：python data_quality_report.py --table feature_apply_broad --out reports/quality_report.md
"""

import duckdb
import pandas as pd
import argparse
import os
from datetime import datetime


def generate_quality_report(con, table_name, output_file, format='markdown'):
    """生成指定表的数据质量报告"""
    df = con.execute(f"SELECT * FROM {table_name} LIMIT 100000").fetchdf()  # 限制行数避免内存溢出
    total_rows = len(df)

    report_lines = []
    if format == 'markdown':
        report_lines.append(f"# 数据质量报告 - {table_name}")
        report_lines.append(f"**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report_lines.append(f"**总行数**: {total_rows}")
        report_lines.append("\n## 列级质量统计\n")
        report_lines.append("| 列名 | 数据类型 | 缺失值数量 | 缺失率(%) | 唯一值个数 | 均值(数值列) | 标准差(数值列) |")
        report_lines.append("|------|----------|------------|-----------|------------|--------------|----------------|")

        for col in df.columns:
            dtype = str(df[col].dtype)
            missing = df[col].isna().sum()
            missing_rate = missing / total_rows * 100
            unique = df[col].nunique()
            mean_val = ""
            std_val = ""
            # 修复：排除布尔类型，只对int/float计算均值和标准差
            if pd.api.types.is_numeric_dtype(df[col]) and not pd.api.types.is_bool_dtype(df[col]):
                mean_val = f"{df[col].mean():.2f}"
                std_val = f"{df[col].std():.2f}"
            report_lines.append(
                f"| {col} | {dtype} | {missing} | {missing_rate:.2f} | {unique} | {mean_val} | {std_val} |")

        # 分类列 Top5 频数
        report_lines.append("\n## 分类列 Top5 值分布\n")
        for col in df.columns:
            if df[col].dtype == 'object' or df[col].nunique() < 20:
                top5 = df[col].value_counts().head(5)
                if len(top5) > 0:
                    report_lines.append(f"### {col}")
                    for val, cnt in top5.items():
                        report_lines.append(f"- {val}: {cnt} ({cnt / total_rows * 100:.2f}%)")

        # 数值列分位数 - 修复：排除布尔类型
        report_lines.append("\n## 数值列分位数\n")
        for col in df.columns:
            # 仅对非布尔的数值列计算分位数
            if pd.api.types.is_numeric_dtype(df[col]) and not pd.api.types.is_bool_dtype(df[col]):
                quantiles = df[col].quantile([0.25, 0.5, 0.75]).round(2)
                report_lines.append(f"### {col}")
                report_lines.append(f"- 25%: {quantiles[0.25]}")
                report_lines.append(f"- 50% (中位数): {quantiles[0.5]}")
                report_lines.append(f"- 75%: {quantiles[0.75]}")

    # 写入文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report_lines))
    print(f"报告已保存至 {output_file}")


def main():
    parser = argparse.ArgumentParser(description='生成数据质量报告')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    parser.add_argument('--table',default='feature_apply_broad', help='表名')
    parser.add_argument('--out', default='reports/quality_report.md', help='输出文件路径')
    parser.add_argument('--format', default='markdown', choices=['markdown', 'html'], help='输出格式')
    args = parser.parse_args()

    con = duckdb.connect(args.db)
    generate_quality_report(con, args.table, args.out, args.format)
    con.close()


if __name__ == '__main__':
    main()