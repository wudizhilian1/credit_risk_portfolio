#!/usr/bin/env python3
"""
拒绝推断（Reject Inference）脚本：模拟模糊扩张法，对比推断前后的模型评估指标。
用法：python scripts/reject_inference.py
"""

import duckdb
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, roc_curve
import matplotlib.pyplot as plt
import os

# 配置
DB_PATH = 'dev.duckdb'
TABLE_NAME = 'feature_apply_broad_v3'
TARGET = 'bad_flag'
FEATURES = [
    'amount', 'user_apply_cnt_30d', 'user_avg_amount_30d',
    'user_pass_rate_30d', 'credit_score', 'apply_hour',
    'amount_sum_7d', 'amount_per_credit'
]
RANDOM_SEED = 42


def load_data():
    """从 DuckDB 加载数据，确保包含决策字段和标签"""
    con = duckdb.connect(DB_PATH)
    # 假设 feature_apply_broad_v3 中有 decision 字段（PASS/REJECT/REVIEW）
    # 如果没有，可模拟（此处使用实际字段）
    df = con.execute(f"""
        SELECT {','.join(FEATURES)}, {TARGET}, decision
        FROM {TABLE_NAME}
        WHERE {TARGET} IS NOT NULL
    """).fetchdf()
    con.close()
    # 将 decision 列转换为 is_approved (1=通过, 0=拒绝/人工审核)
    df['is_approved'] = df['decision'].apply(lambda x: 1 if x == 'PASS' else 0)
    return df


def train_model(X, y, desc=""):
    """训练逻辑回归，返回模型和评估指标"""
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.3, random_state=RANDOM_SEED, stratify=y
    )
    lr = LogisticRegression(max_iter=1000, random_state=RANDOM_SEED, class_weight='balanced')
    lr.fit(X_train, y_train)
    y_pred = lr.predict_proba(X_test)[:, 1]
    auc = roc_auc_score(y_test, y_pred)
    fpr, tpr, _ = roc_curve(y_test, y_pred)
    ks = max(tpr - fpr)
    print(f"{desc}: AUC = {auc:.4f}, KS = {ks:.4f}")
    return lr, auc, ks, X_test, y_test, y_pred


def plot_roc_curve(y_test, y_pred, title, save_path):
    """绘制 ROC 曲线"""
    fpr, tpr, _ = roc_curve(y_test, y_pred)
    auc = roc_auc_score(y_test, y_pred)
    plt.figure(figsize=(8, 6))
    plt.plot(fpr, tpr, label=f'ROC (AUC={auc:.4f})')
    plt.plot([0, 1], [0, 1], 'k--')
    plt.xlabel('False Positive Rate')
    plt.ylabel('True Positive Rate')
    plt.title(title)
    plt.legend()
    plt.savefig(save_path)
    plt.close()
    print(f"ROC 曲线已保存至 {save_path}")


def main():
    np.random.seed(RANDOM_SEED)
    print("=== 拒绝推断实验（模糊扩张法）===\n")

    # 1. 加载数据
    df = load_data()
    print(f"原始数据量: {len(df)}")
    print(f"通过样本量: {df['is_approved'].sum()}")
    print(f"拒绝样本量: {len(df) - df['is_approved'].sum()}")

    # 2. 划分通过样本（有真实标签）和拒绝样本（无标签）
    approved = df[df['is_approved'] == 1].copy()
    rejected = df[df['is_approved'] == 0].copy()

    # 3. 使用通过样本训练初始模型
    X_approved = approved[FEATURES]
    y_approved = approved[TARGET]
    print("\n--- 初始模型（仅通过样本） ---")
    lr_initial, auc_initial, ks_initial, _, _, _ = train_model(X_approved, y_approved, "初始模型")

    # 4. 对拒绝样本预测概率
    X_reject = rejected[FEATURES]
    proba = lr_initial.predict_proba(X_reject)[:, 1]

    # 5. 模糊扩张法：按预测概率随机赋予标签
    # 生成与每个拒绝样本对应的随机数，若随机数 < 预测概率，则标记为坏样本（1）
    rand_vals = np.random.rand(len(proba))
    rejected['bad_flag_inferred'] = (proba > rand_vals).astype(int)
    print(f"\n拒绝样本推断的坏样本比例: {rejected['bad_flag_inferred'].mean():.4f}")

    # 6. 合并数据集（通过样本真实标签 + 拒绝样本推断标签）
    combined = pd.concat([
        approved[FEATURES + [TARGET]],
        rejected[FEATURES].assign(**{TARGET: rejected['bad_flag_inferred']})
    ], ignore_index=True)

    # 7. 重新训练模型（全量数据）
    X_combined = combined[FEATURES]
    y_combined = combined[TARGET]
    print("\n--- 推断后模型（通过样本 + 推断标签） ---")
    lr_combined, auc_combined, ks_combined, X_test, y_test, y_pred = train_model(
        X_combined, y_combined, "推断后模型"
    )

    # 8. 在保留的测试集上对比（可选：使用原始通过样本的测试集评估推断模型的泛化能力）
    # 为了更公平，我们使用通过样本的测试集来评估推断模型的效果（因为真实标签已知）
    # 分割通过样本的训练/测试集（与初始模型一致）
    _, X_test_approved, _, y_test_approved = train_test_split(
        X_approved, y_approved, test_size=0.3, random_state=RANDOM_SEED, stratify=y_approved
    )
    y_pred_combined = lr_combined.predict_proba(X_test_approved)[:, 1]
    auc_combined_on_approved = roc_auc_score(y_test_approved, y_pred_combined)
    fpr, tpr, _ = roc_curve(y_test_approved, y_pred_combined)
    ks_combined_on_approved = max(tpr - fpr)
    print(f"\n--- 在通过样本测试集上的评估（公平对比）---")
    print(f"初始模型 AUC = {auc_initial:.4f}, KS = {ks_initial:.4f}")
    print(f"推断后模型 AUC = {auc_combined_on_approved:.4f}, KS = {ks_combined_on_approved:.4f}")

    # 9. 绘制 ROC 曲线对比
    os.makedirs('reports', exist_ok=True)
    plot_roc_curve(y_test_approved, y_pred_combined,
                   f'Reject Inference - ROC (AUC={auc_combined_on_approved:.4f})',
                   'reports/reject_inference_roc.png')

    # 10. 保存结果报告
    report = f"""# 拒绝推断实验报告

## 数据概况
- 总样本量: {len(df)}
- 通过样本量: {len(approved)} (真实标签)
- 拒绝样本量: {len(rejected)} (标签推断)

## 初始模型（仅通过样本）
- AUC: {auc_initial:.4f}
- KS: {ks_initial:.4f}

## 模糊扩张法推断
- 拒绝样本推断的坏样本比例: {rejected['bad_flag_inferred'].mean():.4f}

## 推断后模型（全量数据，在通过样本测试集上评估）
- AUC: {auc_combined_on_approved:.4f}
- KS: {ks_combined_on_approved:.4f}

## 结论
推断后模型在通过样本测试集上 {'有提升' if auc_combined_on_approved > auc_initial else '无明显提升'}，AUC 变化 {auc_combined_on_approved - auc_initial:+.4f}。
"""
    with open('reports/reject_inference_report.md', 'w') as f:
        f.write(report)
    print("\n报告已保存至 reports/reject_inference_report.md")


if __name__ == '__main__':
    main()