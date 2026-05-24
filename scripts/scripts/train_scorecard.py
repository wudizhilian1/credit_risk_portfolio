#!/usr/bin/env python3
"""
训练简单的逻辑回归评分卡，并将预测概率转换为分数
支持从配置文件读取特征列表，并将模型保存到 models/scorecard.pkl
用法：python train_scorecard.py
"""

import duckdb
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, roc_curve
import matplotlib.pyplot as plt
import pickle
import os
import yaml

# 评分卡参数
BASE_SCORE = 600  # 基准分
BASE_ODDS = 50  # 基准Odds（好:坏）
PDO = 20  # 每增加20分，Odds翻倍


def prob_to_score(prob, base_score=BASE_SCORE, base_odds=BASE_ODDS, pdo=PDO):
    """
    将预测概率转换为信用分
    prob: 坏客户概率
    """
    # 防止除零或 log(0)
    prob = np.clip(prob, 1e-6, 1 - 1e-6)
    odds = (1 - prob) / prob  # 好/坏
    factor = pdo / np.log(2)
    offset = base_score - factor * np.log(base_odds)
    score = offset - factor * np.log(odds)  # 减号是因为 odds 越大越好，分数越高
    return score


def load_config():
    """从 config.yaml 读取特征列表"""
    # 修正1：调整 config_path 路径（适配 Windows 路径，同时兼容相对路径）
    # 方案A：如果 scripts 目录和 config.yaml 同级（推荐）
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config.yaml')
    config_path = os.path.normpath(config_path)  # 标准化路径（解决 Windows 反斜杠问题）

    if os.path.exists(config_path):
        # 修正2：显式指定 UTF-8 编码打开文件
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
        return config.get('features', {}).get('scorecard', [])
    else:
        # 默认特征列表
        return ['amount', 'user_apply_cnt_30d', 'user_avg_amount_30d',
                'user_pass_rate_30d', 'credit_score', 'apply_hour', 'is_weekend',
                'amount_sum_7d', 'amount_per_credit']


def main():
    con = duckdb.connect('dev.duckdb')

    # 1. 读取特征宽表，选取特征和目标
    features = load_config()
    target = 'bad_flag'

    # 确保所有特征存在于表中
    table_info = con.execute("PRAGMA table_info(feature_apply_broad_v3)").fetchdf()
    existing_cols = set(table_info['name'])
    features = [f for f in features if f in existing_cols]

    if not features:
        print("错误：未找到可用的特征列，请检查 feature_apply_broad_v3 表结构")
        return

    print(f"使用的特征: {features}")

    df = con.execute(f"""
        SELECT {','.join(features)}, {target}
        FROM feature_apply_broad_v3
        WHERE {target} IS NOT NULL
    """).fetchdf()

    # 处理缺失值（简单用中位数填充）
    for col in features:
        if df[col].isna().any():
            median_val = df[col].median()
            df[col].fillna(median_val, inplace=True)
            print(f"特征 {col} 存在缺失值，已用中位数 {median_val:.2f} 填充")

    X = df[features]
    y = df[target].astype(int)

    # 2. 划分训练集和测试集
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42, stratify=y)

    # 3. 训练逻辑回归
    lr = LogisticRegression(max_iter=1000, random_state=42, class_weight='balanced')
    lr.fit(X_train, y_train)

    # 4. 预测概率和分数
    y_pred_prob = lr.predict_proba(X_test)[:, 1]
    y_score = prob_to_score(y_pred_prob)

    # 5. 评估
    auc = roc_auc_score(y_test, y_pred_prob)
    fpr, tpr, _ = roc_curve(y_test, y_pred_prob)
    ks = max(tpr - fpr)

    print(f"\n模型 AUC: {auc:.4f}")
    print(f"模型 KS : {ks:.4f}")
    print(f"测试集分数范围: [{y_score.min():.0f}, {y_score.max():.0f}]")

    # 6. 绘制 ROC 曲线
    plt.figure(figsize=(8, 6))
    plt.plot(fpr, tpr, label=f'ROC (AUC={auc:.4f})')
    plt.plot([0, 1], [0, 1], 'k--')
    plt.xlabel('False Positive Rate')
    plt.ylabel('True Positive Rate')
    plt.title('ROC Curve - Scorecard')
    plt.legend()
    os.makedirs('reports', exist_ok=True)
    plt.savefig('reports/scorecard_roc.png')
    plt.close()

    # 7. 保存模型和特征列表
    os.makedirs('models', exist_ok=True)
    model_data = {
        'model': lr,
        'features': features,
        'params': {
            'base_score': BASE_SCORE,
            'base_odds': BASE_ODDS,
            'pdo': PDO
        },
        'auc': auc,
        'ks': ks
    }
    with open('models/scorecard.pkl', 'wb') as f:
        pickle.dump(model_data, f)
    print("模型已保存至 models/scorecard.pkl")

    # 8. 输出特征系数
    coef_df = pd.DataFrame({'feature': features, 'coefficient': lr.coef_[0]})
    coef_df = coef_df.sort_values('coefficient', ascending=False)
    print("\n特征系数（正相关越大，坏概率越高）：")
    print(coef_df)

    # 9. 更新 ads_model_eval 表（如果提供了 eval_date 参数）
    # 可选：集成到调度时传入日期
    con.close()


if __name__ == '__main__':
    main()