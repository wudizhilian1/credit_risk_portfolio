#!/usr/bin/env python3
"""
计算模型 AUC 和 KS，并更新到 ads_model_eval 表
用法：python calc_auc_ks.py --eval_date 2024-01-30
"""

import duckdb
import pandas as pd
import argparse
from sklearn.metrics import roc_auc_score, roc_curve
import numpy as np
import matplotlib.pyplot as plt
import os


def calculate_auc_ks(con, eval_date, model_name='strategy_score'):
    """从特征宽表读取预测分和标签，计算 AUC 和 KS"""
    df = con.execute(f"""
        SELECT pred_score, bad_flag
        FROM feature_apply_broad
        WHERE dt <= '{eval_date}'
          AND pred_score IS NOT NULL
          AND bad_flag IS NOT NULL
    """).fetchdf()

    if len(df) == 0:
        print(f"警告：日期 {eval_date} 无有效数据")
        return None, None

    y_true = df['bad_flag'].astype(int)
    y_score = df['pred_score'].astype(float)

    auc = roc_auc_score(y_true, y_score)
    """
    计算画 ROC 曲线需要的 3 个值：
fpr（假正率）= 坏客户被误判成好客户的比例
tpr（真正率）= 好客户正确识别的比例
thresholds = 模型使用的概率阈值
    """
    fpr, tpr, thresholds = roc_curve(y_true, y_score)
    ks = max(tpr - fpr)

    return auc, ks, fpr, tpr


def plot_roc_curve(fpr, tpr, auc, output_file):
    """绘制 ROC 曲线并保存"""
    plt.figure(figsize=(8, 6))
    plt.plot(fpr, tpr, label=f'ROC curve (AUC = {auc:.4f})')
    plt.plot([0, 1], [0, 1], 'k--')
    plt.xlabel('False Positive Rate')
    plt.ylabel('True Positive Rate')
    plt.title('ROC Curve')
    plt.legend(loc='lower right')
    plt.grid(True)
    plt.savefig(output_file)
    plt.close()
    print(f"ROC 曲线已保存至 {output_file}")


def update_model_eval(con, eval_date, auc, ks, model_name='strategy_score'):
    """更新 ads_model_eval 表中的 AUC 和 KS"""
    # 确保表存在
    con.execute("""
        CREATE TABLE IF NOT EXISTS ads_model_eval (
            eval_date DATE,
            model_name VARCHAR,
            auc DECIMAL(6,4),
            ks DECIMAL(6,4),
            psi DECIMAL(6,4),
            check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    # 检查是否已有记录
    existing = con.execute(f"""
        SELECT 1 FROM ads_model_eval
        WHERE eval_date = '{eval_date}' AND model_name = '{model_name}'
    """).fetchone()
    if existing:
        con.execute(f"""
            UPDATE ads_model_eval
            SET auc = {auc}, ks = {ks}, check_time = CURRENT_TIMESTAMP
            WHERE eval_date = '{eval_date}' AND model_name = '{model_name}'
        """)
    else:
        con.execute(f"""
            INSERT INTO ads_model_eval (eval_date, model_name, auc, ks)
            VALUES ('{eval_date}', '{model_name}', {auc}, {ks})
        """)
    print(f"已更新 {model_name} 在 {eval_date} 的评估结果: AUC={auc:.4f}, KS={ks:.4f}")


def main():
    parser = argparse.ArgumentParser(description='计算模型 AUC/KS 并更新评估表')
    parser.add_argument('--db', default='dev.duckdb', help='DuckDB 数据库文件')
    parser.add_argument('--eval_date', default='2024-01-05', help='评估日期（用于筛选数据，并作为 eval_date 字段）')
    parser.add_argument('--model_name', default='strategy_score', help='模型名称')
    parser.add_argument('--plot_roc', action='store_true', help='是否生成 ROC 曲线图')
    args = parser.parse_args()

    con = duckdb.connect(args.db)
    auc, ks, fpr, tpr = calculate_auc_ks(con, args.eval_date, args.model_name)
    if auc is not None:
        update_model_eval(con, args.eval_date, auc, ks, args.model_name)
        if args.plot_roc:
            os.makedirs('reports', exist_ok=True)
            plot_roc_curve(fpr, tpr, auc, f'reports/roc_curve_{args.eval_date}.png')
    con.close()


if __name__ == '__main__':
    main()
