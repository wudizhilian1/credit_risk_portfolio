# 统计过程控制（SPC）与 P-Chart 实战指南（附 Python 自动化监控）

## 一、核心概念：统计过程控制（SPC）基本思想

### 1. SPC 定义与核心目标

统计过程控制（Statistical Process Control，SPC）是通过**统计方法监控过程稳定性、识别异常波动**的质量管理工具，核心目标是：

- 区分「正常波动」（随机因素，如数据自然偏差）和「异常波动」（系统因素，如流程漏洞、数据异常）；
- 提前预警异常，避免批量问题发生；
- 持续优化流程，降低波动范围。

### 2. SPC 核心原理

- **过程处于统计控制状态**：仅受随机因素影响，数据波动在可预测的「控制限」内；
- **过程失控**：存在系统因素，数据超出控制限或呈现非随机模式（如连续 7 点上升 / 下降）；
- 核心工具：控制图（Control Chart），通过可视化方式展示过程波动并标记异常。

## 二、P-Chart（比例控制图）：监控比例指标的核心工具

### 1. P-Chart 适用场景

P-Chart（Percent/Proportion Chart）用于监控**二项分布的比例指标**（如不合格品率、拒绝原因占比、转化率），适用于：

- 指标为「比例 / 百分比」类型（0~1 之间）；
- 样本量可固定或变化（如每日审核量不同）；
- 核心监控目标：比例指标的稳定性（如每日信贷申请拒绝率、订单差评率）。

### 2. P-Chart 核心计算逻辑

#### （1）基础参数

| 参数                  | 计算公式        | 说明                                                |
| :-------------------- | :-------------- | :-------------------------------------------------- |
| 总体不合格率（pˉ）    | 不合格数/样本量 | 所有样本的平均不合格比例                            |
| 上下控制限（UCL/LCL） |                 | 基于 3σ 原则（99.73% 置信区间），ni 为第 i 个样本量 |
| 中心线（CL）          | CL=pˉ           | 比例指标的平均值                                    |

$$
UCL=pˉ​+3×ni​pˉ​(1−pˉ​)
​​LCL=pˉ​−3×ni​pˉ​(1−pˉ​)​​
$$

> 注：若 LCL 计算结果为负数，取 0（比例不能为负）。

#### （2）核心规则（异常判定）

满足以下任一条件则判定为过程失控，触发告警：

1. 单点超出 UCL/LCL；
2. 连续 7 点在中心线同侧；
3. 连续 7 点呈上升 / 下降趋势；
4. 任意 10 点中有 9 点在中心线同侧。

### 3. 业务场景示例：每日拒绝原因占比监控

以「信贷申请拒绝原因占比（如资质不符占比）」为例，监控逻辑：

- 样本量（ni）：每日审核的信贷申请总数；
- 不合格数：每日因「资质不符」被拒绝的申请数；
- 监控指标：每日资质不符拒绝占比（不合格数样本量）；
- 核心目标：当占比超出 UCL 时，触发告警（如资质审核规则异常）。

## 三、Python 实现 P-Chart 自动化监控（两种方案）

### 1. 环境准备

```bash
# 安装依赖库
pip install qcc pandas matplotlib numpy
```

### 2. 方案 1：基于 qcc 库（专业 SPC 工具）

#### （1）数据准备（模拟每日拒绝原因占比数据）

```python
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from qcc import qcc

# 设置中文显示
plt.rcParams['font.sans-serif'] = ['SimHei']
plt.rcParams['axes.unicode_minus'] = False

# 模拟数据：15天的审核量、资质不符拒绝数
data = {
    'date': pd.date_range(start='2026-03-01', periods=15),
    'total': [200, 210, 190, 220, 205, 195, 215, 230, 225, 210, 200, 195, 240, 235, 250],
    'reject_qual': [10, 12, 9, 11, 10, 8, 11, 30, 12, 11, 9, 10, 13, 12, 14]  # 第8天为异常值
}
df = pd.DataFrame(data)
df['reject_p'] = df['reject_qual'] / df['total']  # 拒绝占比
```

#### （2）绘制 P-Chart 并识别异常

```python
# 生成P-Chart
p_chart = qcc(
    data=df['reject_qual'].values,  # 不合格数
    sizes=df['total'].values,       # 样本量
    type='p',                       # 控制图类型：P-Chart
    title='信贷申请资质不符拒绝占比 P-Chart',
    xlab='日期',
    ylab='拒绝占比',
    labels=df['date'].dt.strftime('%m-%d').tolist()  # x轴标签：日期
)

# 输出异常点
print("异常点索引（超出控制限）：", p_chart$violations['beyond_limits'])
plt.show()
```

#### （3）结果解读

- 图表中红色点为「超出控制限的异常点」（示例中第 8 天拒绝占比骤升）；
- 控制台输出异常点索引，可基于此触发告警（如钉钉 / 邮件）。

### 3. 方案 2：自定义规则实现（无第三方 SPC 库）

适用于无法安装 qcc 库的场景，手动计算控制限并判定异常：

```python
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# 1. 计算核心参数
total_reject = df['reject_qual'].sum()  # 总拒绝数
total_sample = df['total'].sum()        # 总样本量
p_bar = total_reject / total_sample     # 总体拒绝率

# 2. 计算每日控制限
df['ucl'] = p_bar + 3 * np.sqrt(p_bar * (1 - p_bar) / df['total'])
df['lcl'] = p_bar - 3 * np.sqrt(p_bar * (1 - p_bar) / df['total'])
df['lcl'] = df['lcl'].apply(lambda x: max(x, 0))  # LCL不能为负
df['cl'] = p_bar  # 中心线

# 3. 异常判定规则
## 规则1：超出UCL/LCL
df['is_out_of_limit'] = (df['reject_p'] > df['ucl']) | (df['reject_p'] < df['lcl'])
## 规则2：连续7点在中心线同侧
df['above_cl'] = df['reject_p'] > df['cl']
df['consecutive_same_side'] = df['above_cl'].rolling(window=7).apply(lambda x: len(set(x)) == 1)
## 规则3：连续7点上升/下降
df['trend_up'] = df['reject_p'].rolling(window=7).apply(lambda x: all(x[i] < x[i+1] for i in range(6)))
df['trend_down'] = df['reject_p'].rolling(window=7).apply(lambda x: all(x[i] > x[i+1] for i in range(6)))
## 最终异常标记
df['is_abnormal'] = df['is_out_of_limit'] | (df['consecutive_same_side'] == 1) | (df['trend_up'] == 1) | (df['trend_down'] == 1)

# 4. 绘制自定义P-Chart
plt.figure(figsize=(12, 6))
# 绘制数据点
plt.plot(df['date'], df['reject_p'], 'o-', label='每日拒绝占比', color='blue')
# 绘制控制限和中心线
plt.plot(df['date'], df['ucl'], '--', label='上控制限（UCL）', color='red')
plt.plot(df['date'], df['cl'], '-', label='中心线（CL）', color='green')
plt.plot(df['date'], df['lcl'], '--', label='下控制限（LCL）', color='orange')
# 标记异常点
abnormal_points = df[df['is_abnormal']]
plt.scatter(abnormal_points['date'], abnormal_points['reject_p'], color='red', s=100, label='异常点', zorder=5)

plt.title('信贷申请资质不符拒绝占比 P-Chart（自定义实现）')
plt.xlabel('日期')
plt.ylabel('拒绝占比')
plt.xticks(rotation=45)
plt.legend()
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.show()

# 5. 输出异常结果
print("异常日期列表：")
print(df[df['is_abnormal']][['date', 'reject_p', 'ucl', 'lcl']])
```

## 四、P-Chart 自动化监控落地流程

### 落地关键配置

1. **数据同步**：每日从数仓 DWS 层同步「审核量、拒绝数」（DWS 表需按日期分区，保证查询效率）；
2. 告警分级：
   - 一级告警（超出 UCL/LCL）：钉钉 + 邮件 + 人工通知；
   - 二级告警（趋势异常）：邮件通知，次日复核；
3. **控制限更新**：每周重新计算总体拒绝率（pˉ），适配流程优化后的基准值。

## 五、常见问题与避坑指南

| 问题现象             | 原因                                                 | 解决方案                                                     |
| :------------------- | :--------------------------------------------------- | :----------------------------------------------------------- |
| 控制限波动过大       | 样本量（ni）差异过大（如某日审核量仅 10，某日 1000） | 1. 合并小样本日期（如按周汇总）；2. 固定样本量抽样；3. 使用标准化控制限 |
| 频繁触发告警（虚警） | 3σ 控制限过严，或流程本身不稳定                      | 1. 短期调整为 2σ（95.45% 置信区间）；2. 先稳定流程再收紧控制限；3. 增加异常判定的连续点数（如从 7 点改为 9 点） |
| 控制限为负           | 总体拒绝率（pˉ）过低，样本量较小                     | 强制将 LCL 设为 0，仅监控 UCL 侧异常                         |
| 数据分布非二项分布   | 指标非比例类型（如连续值）                           | 更换控制图类型（如 X-Bar 图监控均值，R 图监控极差）          |

## 六、SPC 与数据质量监控的结合（数仓场景）

在数仓数据质量监控中，P-Chart 可用于：

- 监控每日数据对账失败率（对账失败条数 / 总对账条数）；

- 监控每日数据迟到率（迟到表数 / 总表数）；

- 监控每日空值字段占比（空值行数 / 总行数）；

  核心价值：将「人工抽查数据质量」转为「自动化、可量化的过程监控」，提前发现数仓数据异常。

## 总结

1. **核心思想**：SPC 通过控制图区分过程的「正常波动」和「异常波动」，P-Chart 是监控比例指标的核心工具，基于 3σ 原则设置控制限；
2. 实战实现：
   - 专业场景用 qcc 库快速生成 P-Chart，开箱即用；
   - 轻量化场景自定义规则，手动计算控制限并判定异常；
3. **落地关键**：适配业务调整样本量和控制限，设置分级告警，定期更新基准值（pˉ）；
4. **数仓适配**：P-Chart 可无缝对接数仓 DWS 层的比例类指标，实现数据质量 / 业务指标的自动化监控。

### 关键点回顾

- P-Chart 核心计算：总体比例pˉ + 3σ 控制限，异常判定需结合「超出控制限」和「趋势异常」规则；
- Python 实现有两种方案：qcc 库（高效）、自定义规则（灵活）；
- 落地时需避免虚警，根据样本量调整控制限，设置分级告警机制。