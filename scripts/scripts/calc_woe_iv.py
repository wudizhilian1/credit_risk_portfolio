#!/usr/bin/env python3
"""
计算特征宽表中指定特征的 WOE 和 IV
用法：python calc_woe_iv.py --features amount user_apply_cnt_30d credit_score
"""

import duckdb
import pandas as pd
import numpy as np
import argparse


def calc_woe_iv(df, feature, target='bad_flag', bins=5, eps=1e-6):
    """
    计算单个特征的 WOE 和 IV
    参数：
        df: DataFrame，包含 feature 和 target 列
        feature: 特征名
        target: 目标列名（0/1，1表示坏客户）
        bins: 分箱数（等频分箱）
        eps: 平滑项，避免除零或 log(0)
    返回：
        iv: 信息值
        woe_df: 包含分箱、WOE、IV 等信息的 DataFrame
    """
    # 剔除目标列缺失的记录
    data = df[[feature, target]].dropna()
    if len(data) == 0:
        return 0, pd.DataFrame()

    # 等频分箱（若唯一值少于 bins，则自动减少分箱数）
    try:
        data['bin'] = pd.qcut(data[feature], q=bins, duplicates='drop')
    except ValueError:
        # 如果无法分箱（例如所有值相同），则作为一箱
        data['bin'] = 'all'

    # 统计每箱的好坏客户数
    grouped = data.groupby('bin')[target].agg(['count', 'sum'])
    grouped.columns = ['total', 'bad']
    grouped['good'] = grouped['total'] - grouped['bad']

    # 计算好坏客户占比
    total_bad = grouped['bad'].sum()
    total_good = grouped['good'].sum()
    if total_bad == 0 or total_good == 0:
        return 0, grouped

    grouped['bad_pct'] = grouped['bad'] / total_bad
    grouped['good_pct'] = grouped['good'] / total_good

    # 计算 WOE 和 IV（平滑处理）
    grouped['woe'] = np.log((grouped['good_pct'] + eps) / (grouped['bad_pct'] + eps))
    grouped['iv_contrib'] = (grouped['good_pct'] - grouped['bad_pct']) * grouped['woe']
    iv = grouped['iv_contrib'].sum()

    return iv, grouped


def main():
    parser = argparse.ArgumentParser(description='计算特征的 WOE 和 IV')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    parser.add_argument('--table', default='feature_apply_broad_v3', help='特征宽表名')
    parser.add_argument('--target', default='bad_flag', help='目标列名（0/1，1=坏客户）')
    parser.add_argument('--features', nargs='+',
                        default=['amount', 'user_apply_cnt_30d', 'credit_score', 'amount_per_credit'],
                        help='要计算的特征名列表')
    parser.add_argument('--bins', type=int, default=5, help='分箱数')
    args = parser.parse_args()

    con = duckdb.connect(args.db)

    # 读取数据，只选择需要的列
    cols = [args.target] + args.features
    df = con.execute(f"SELECT {','.join(cols)} FROM {args.table}").fetchdf()
    df[args.target] = df[args.target].astype(int)

    print(f"特征 IV 值（目标：{args.target}，分箱数：{args.bins}）\n")
    for feat in args.features:
        iv, woe_df = calc_woe_iv(df, feat, args.target, args.bins)
        print(f"{feat}: IV = {iv:.4f}")
        if not woe_df.empty:
            print(woe_df[['bad', 'good', 'bad_pct', 'good_pct', 'woe', 'iv_contrib']].round(4))
        print()

    con.close()


if __name__ == '__main__':
    main()