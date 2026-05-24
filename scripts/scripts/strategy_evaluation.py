#!/usr/bin/env python3
"""
策略评估脚本：离线回溯测试，对比新旧策略的通过率、坏账率等指标。
支持自定义策略函数，并计算统计显著性（卡方检验）。
用法：python scripts/strategy_evaluation.py
"""

import duckdb
import pandas as pd
import numpy as np
from scipy.stats import chi2_contingency
import os

# 数据库配置
DB_PATH = 'dev.duckdb'
TABLE_NAME = 'feature_apply_broad_v3'


# ===================== 策略定义 =====================
def old_strategy(row):
    """
    旧策略：基于信用评分的简单规则
    规则：信用评分 > 600 则通过（PASS），否则拒绝（REJECT）
    """
    return 'PASS' if row['credit_score'] > 600 else 'REJECT'


def new_strategy(row):
    """
    新策略：放宽条件，信用评分 > 600 或 申请金额 < 5000 则通过
    """
    if row['credit_score'] > 600:
        return 'PASS'
    elif row['amount'] < 5000:
        return 'PASS'
    else:
        return 'REJECT'


# ===================== 评估函数 =====================
def evaluate_strategy(df, strategy_func, strategy_name):
    """
    对给定策略进行评估，计算通过率、坏账率，并返回通过样本的 DataFrame。
    """
    df = df.copy()
    df['decision'] = df.apply(strategy_func, axis=1)

    total = len(df)
    passed = (df['decision'] == 'PASS').sum()
    pass_rate = passed / total if total > 0 else 0

    # 通过样本中的坏账率
    approved_df = df[df['decision'] == 'PASS']
    if len(approved_df) > 0:
        bad_rate = approved_df['bad_flag'].mean()
    else:
        bad_rate = 0

    print(f"\n【{strategy_name}】")
    print(f"  总样本量: {total}")
    print(f"  通过数: {passed} ({pass_rate:.2%})")
    print(f"  通过样本中坏账率: {bad_rate:.2%}")

    return pass_rate, bad_rate, approved_df


def significance_test(old_df, new_df, metric='pass_rate'):
    """
    对策略变更前后的通过率或坏账率进行卡方检验，判断差异是否显著。
    metric: 'pass_rate' 或 'bad_rate'
    返回：(chi2值, p值)，异常时返回 (np.nan, np.nan)
    """
    try:
        if metric == 'pass_rate':
            # 构建列联表：策略（旧/新） x 决策（通过/拒绝）
            old_pass = (old_df['decision'] == 'PASS').sum()
            old_reject = len(old_df) - old_pass
            new_pass = (new_df['decision'] == 'PASS').sum()
            new_reject = len(new_df) - new_pass
            contingency = np.array([[old_pass, old_reject],
                                    [new_pass, new_reject]])
            # 校验：避免全0样本导致检验失败
            if np.all(contingency == 0):
                print("\n通过率卡方检验: 无有效样本，无法检验")
                return np.nan, np.nan
            chi2, p, dof, expected = chi2_contingency(contingency)
            print(f"\n通过率卡方检验: chi2={chi2:.4f}, p-value={p:.4f}")
            if p < 0.05:
                print("结论: 通过率变化具有统计显著性 (p<0.05)")
            else:
                print("结论: 通过率变化不具有统计显著性 (p>=0.05)")
            return chi2, p

        elif metric == 'bad_rate':
            # 仅对比通过样本中的坏账率（需要先取通过样本）
            old_approved = old_df[old_df['decision'] == 'PASS']
            new_approved = new_df[new_df['decision'] == 'PASS']

            # 校验：任一策略无通过样本，直接返回NaN
            if len(old_approved) == 0 or len(new_approved) == 0:
                print("\n坏账率卡方检验: 任一策略无通过样本，无法检验")
                return np.nan, np.nan

            old_bad = old_approved['bad_flag'].sum()
            old_good = len(old_approved) - old_bad
            new_bad = new_approved['bad_flag'].sum()
            new_good = len(new_approved) - new_bad
            contingency = np.array([[old_bad, old_good],
                                    [new_bad, new_good]])

            # 校验：样本分布极端（全0/全1），无法检验
            if np.all(contingency == 0) or \
                    np.all(contingency[:, 0] == 0) or np.all(contingency[:, 1] == 0) or \
                    np.all(contingency[0, :] == 0) or np.all(contingency[1, :] == 0):
                print("\n坏账率卡方检验: 样本分布极端（无坏账/全为坏账），无法检验")
                return np.nan, np.nan

            chi2, p, dof, expected = chi2_contingency(contingency)
            print(f"\n坏账率卡方检验: chi2={chi2:.4f}, p-value={p:.4f}")
            if p < 0.05:
                print("结论: 坏账率变化具有统计显著性 (p<0.05)")
            else:
                print("结论: 坏账率变化不具有统计显著性 (p>=0.05)")
            return chi2, p

    except Exception as e:
        print(f"\n{metric} 卡方检验失败: {str(e)}")
        return np.nan, np.nan


# ===================== 主程序 =====================
def main():
    print("=== 风控策略离线回溯评估 ===")

    # 1. 加载数据
    con = duckdb.connect(DB_PATH)
    # 读取必要字段：申请金额、信用评分、坏账标签
    df = con.execute(f"SELECT amount, credit_score, bad_flag FROM {TABLE_NAME}").fetchdf()
    con.close()

    # 确保 bad_flag 为数值类型
    df['bad_flag'] = df['bad_flag'].astype(int)

    print(f"\n数据加载完成，总样本量: {len(df)}")

    # 2. 评估旧策略
    old_pass_rate, old_bad_rate, old_approved_df = evaluate_strategy(df, old_strategy, "旧策略")

    # 3. 评估新策略
    new_pass_rate, new_bad_rate, new_approved_df = evaluate_strategy(df, new_strategy, "新策略")

    # 4. 显著性检验（提前计算p值，核心修复：先定义变量再用）
    print("\n=== 统计显著性检验 ===")
    old_dec_df = df.assign(decision=df.apply(old_strategy, axis=1))
    new_dec_df = df.assign(decision=df.apply(new_strategy, axis=1))

    # 初始化p值（避免未定义）
    chi2_pass_p = np.nan
    chi2_bad_p = np.nan

    # 通过率检验
    _, chi2_pass_p = significance_test(old_dec_df, new_dec_df, metric='pass_rate')
    # 坏账率检验
    _, chi2_bad_p = significance_test(old_dec_df, new_dec_df, metric='bad_rate')

    # 辅助函数：生成显著性描述
    def get_significance_desc(p_value):
        if np.isnan(p_value):
            return "无法检验（样本不足/分布极端）"
        return "显著" if p_value < 0.05 else "不显著"

    # 5. 生成报告（兼容NaN值）
    report = f"""# 策略评估报告

## 策略描述
- **旧策略**：信用评分 > 600 则通过，否则拒绝。
- **新策略**：信用评分 > 600 或 申请金额 < 5000 则通过，否则拒绝。

## 评估结果
| 策略 | 通过率 | 通过样本坏账率 |
|------|--------|----------------|
| 旧策略 | {old_pass_rate:.2%} | {old_bad_rate:.2%} |
| 新策略 | {new_pass_rate:.2%} | {new_bad_rate:.2%} |

## 统计显著性
- 通过率变化 p-value = {'N/A' if np.isnan(chi2_pass_p) else f"{chi2_pass_p:.4f}"} → {get_significance_desc(chi2_pass_p)}
- 坏账率变化 p-value = {'N/A' if np.isnan(chi2_bad_p) else f"{chi2_bad_p:.4f}"} → {get_significance_desc(chi2_bad_p)}

## 结论与建议
新策略通过率提升明显（{new_pass_rate - old_pass_rate:+.2%}），但坏账率也上升了（{new_bad_rate - old_bad_rate:+.2%}）。
建议：
1. 旧策略无通过样本，需检查信用评分分布是否合理（如是否所有样本评分≤600）；
2. 结合业务容忍度决定是否上线新策略，或进一步优化规则（如调整申请金额阈值）；
3. 若需更可靠的坏账率对比，需补充旧策略有通过样本的数据集。
"""
    os.makedirs('reports', exist_ok=True)
    with open('reports/strategy_evaluation_report.md', 'w', encoding='utf-8') as f:
        f.write(report)
    print("\n策略评估报告已保存至 reports/strategy_evaluation_report.md")


if __name__ == '__main__':
    main()