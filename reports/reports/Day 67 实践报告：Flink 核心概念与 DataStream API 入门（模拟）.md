# Day 67 实践报告：Flink 核心概念与 DataStream API 入门（模拟）

## 1. 练习目标
- 理解 Apache Flink 的核心概念：DataStream、Source、Sink、Transformation、Window、State、Checkpoint 等。
- 掌握 Flink 流处理的基本流程（通过模拟代码理解窗口计算）。
- 通过 Python 模拟 Flink 窗口计算（滚动窗口、滑动窗口），巩固窗口概念。
- 为实时风控架构中的流处理引擎选型打下基础。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 无实际 Flink 依赖，使用 Python 模拟
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 学习 Flink 核心概念
通过查阅官方文档和资料，整理了以下关键概念（详见 `docs/flink_concepts.md`）：
- **DataStream**：无限事件流抽象
- **Source / Sink**：数据源与输出目标
- **Transformation**：`map`, `filter`, `keyBy`, `window` 等
- **Window**：滚动窗口、滑动窗口、会话窗口
- **State**：Keyed State、Operator State
- **Checkpoint**：状态快照，保证 Exactly‑once
- **Time**：事件时间、处理时间、Watermark

### 3.2 编写模拟脚本 `flink_mock.py`
- 实现 `FlinkMock` 类，模拟 `keyBy`、滚动窗口、滑动窗口。
- 生成模拟事件（用户 ID、时间戳），按用户分组，分别进行窗口聚合。
- 输出每个用户在窗口内的事件数量，验证窗口划分逻辑。

### 3.3 运行模拟脚本
```bash
python scripts/flink_mock.py
```

**输出摘要**：
```
生成 50 个模拟事件，时间范围约 30 秒
分组后用户数: 5

--- 滚动窗口 (窗口长度 10 秒) ---
用户 1 窗口 [1734567890, 1734567900) 事件数: 3
用户 2 窗口 [1734567890, 1734567900) 事件数: 2
...

--- 滑动窗口 (窗口长度 10 秒，滑动步长 5 秒) ---
用户 1 窗口 [1734567885, 1734567895) 事件数: 2
用户 1 窗口 [1734567890, 1734567900) 事件数: 3
...
```

### 3.4 对比 Flink 与其他流处理框架
在 `docs/flink_concepts.md` 中添加对比表格，涵盖延迟、窗口类型、状态管理、Exactly‑once 等维度。

### 3.5 更新实时风控架构文档
在 `docs/realtime_risk_architecture.md`（v1.3）中新增“Flink 在实时风控中的角色”一节，说明：
- 事件时间处理（Watermark）
- 状态存储（用户画像）
- 窗口聚合（滑动窗口统计）
- 容错与恢复（Checkpoint）

## 4. 遇到的问题与解决方案

| 问题                         | 原因                         | 解决方案                                                     |
| ---------------------------- | ---------------------------- | ------------------------------------------------------------ |
| 滑动窗口模拟中事件被重复计算 | 一个事件可能属于多个滑动窗口 | 在 `sliding_window` 方法中计算每个事件所属的所有窗口，确保正确性 |
| 模拟事件时间未排序           | 随机生成顺序可能乱序         | 生成后按时间戳排序，模拟事件时间顺序                         |
| 窗口边界显示不直观           | 时间戳为浮点数               | 输出时取整，并添加窗口起止时间                               |

## 5. 核心产出清单
- [x] `docs/flink_concepts.md`（核心概念笔记）
- [x] `scripts/flink_mock.py`（模拟 Flink 窗口计算脚本）
- [x] 更新 `docs/realtime_risk_architecture.md`（v1.3，新增 Flink 角色说明）

## 6. 思考题
- **Flink 中事件时间窗口如何处理迟到数据？**  
  通过 Watermark 等待一定延迟，使用 `allowedLateness` 允许窗口在触发后继续接收迟到数据，极晚数据可通过侧输出流单独处理。

- **为什么 Flink 适合实时风控场景？**  
  低延迟（毫秒级）、丰富的窗口类型、事件时间语义、Exactly‑once 保证、状态存储支持大状态。

- **如果状态非常大（如亿级用户），Flink 如何应对？**  
  使用 RocksDB 状态后端，将状态存储在磁盘，避免内存溢出；增量 Checkpoint 减少持久化开销。

---
**完成日期**：2026-04-20