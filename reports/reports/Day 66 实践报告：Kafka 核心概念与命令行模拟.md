# Day 66 实践报告：Kafka 核心概念与命令行模拟

## 1. 练习目标
- 理解 Kafka 的核心概念：Topic、Partition、Offset、Producer、Consumer、Consumer Group 等。
- 掌握 Kafka 消息生产和消费的基本流程。
- 通过模拟命令行操作（或使用 Docker 快速启动 Kafka）体验消息收发。
- 为后续实时风控架构中的消息队列选型打下基础。

## 2. 实验环境
- 操作系统：Windows 11
- Python 版本：3.13.5
- 辅助工具：无实际 Kafka 依赖，使用 Python 模拟命令行
- 项目路径：`C:\credit_risk_portfolio`

## 3. 核心任务执行

### 3.1 学习 Kafka 核心概念
通过查阅官方文档和资料，整理了以下关键概念（详见 `docs/kafka_concepts.md`）：
- **Topic**：消息分类主题
- **Partition**：分区，提供并行处理能力
- **Offset**：消息在分区内的唯一序号
- **Producer**：生产者
- **Consumer**：消费者
- **Consumer Group**：消费者组，实现负载均衡
- **Broker**：Kafka 服务器节点
- **ZooKeeper / KRaft**：集群协调服务

### 3.2 编写模拟命令行脚本 `kafka_mock.py`
- 实现 `KafkaMock` 类，模拟创建 topic、列出 topics、生产消息、消费消息。
- 支持指定分区数，根据 key 的哈希决定消息写入的分区。
- 记录每个分区的 offset，模拟消息持久化。
- 输出模拟结果，帮助理解 Kafka 操作流程。

### 3.3 运行模拟脚本
```bash
python scripts/kafka_mock.py
```

**输出示例**：
```
=== Kafka 命令行模拟器 ===

[模拟] 创建 topic 'risk-events' 成功，分区数: 3，副本因子: 1
[模拟] 当前 topics: risk-events

--- 模拟生产者发送消息 ---
[模拟] 生产者发送消息: topic=risk-events, partition=0, offset=0, key=user_123, value={"event":"apply","amount":5000}
[模拟] 生产者发送消息: topic=risk-events, partition=1, offset=0, key=user_456, value={"event":"login","device":"new"}
[模拟] 生产者发送消息: topic=risk-events, partition=0, offset=1, key=user_123, value={"event":"apply","amount":8000}
[模拟] 生产者发送消息: topic=risk-events, partition=2, offset=0, key=user_789, value={"event":"transaction","amount":12000}

--- 模拟消费者消费消息 ---
[模拟] 消费者开始消费 topic 'risk-events' (from_beginning=True):
  offset=0, key=user_123, value={"event":"apply","amount":5000}
  offset=0, key=user_456, value={"event":"login","device":"new"}
  offset=1, key=user_123, value={"event":"apply","amount":8000}
  offset=0, key=user_789, value={"event":"transaction","amount":12000}

--- 各分区消息数量统计 ---
topic 'risk-events': {0: 2, 1: 1, 2: 1}
```

### 3.4 更新实时风控架构文档
在 `docs/realtime_risk_architecture.md` 中新增了“Kafka 在实时风控中的角色”一节，说明：
- 削峰填谷
- 解耦生产者和消费者
- 消息重放
- 多消费者
- 顺序保证

### 3.5 面试话术准备
整理了 Kafka 相关常见问题的回答要点（见 `docs/kafka_concepts.md` 第 7 节）。

## 4. 遇到的问题与解决方案

| 问题                                           | 原因                          | 解决方案                                                     |
| ---------------------------------------------- | ----------------------------- | ------------------------------------------------------------ |
| 模拟脚本中分区分配逻辑不清晰                   | 未实现基于 key 哈希的分区选择 | 添加 `partition = hash(key) % partitions` 逻辑               |
| 消费者消费时显示所有消息，无法模拟 offset 提交 | 模拟未实现消费进度管理        | 增加 `consumed_offset` 字典，支持从指定 offset 开始消费（可选扩展） |
| Docker 启动 Kafka 失败                         | 本地未安装 Docker 或端口冲突  | 跳过 Docker 实践，仅使用模拟脚本；在文档中提供命令供参考     |

## 5. 核心产出清单
- [x] `docs/kafka_concepts.md`（核心概念笔记）
- [x] `scripts/kafka_mock.py`（模拟 Kafka 命令行脚本）
- [x] 更新 `docs/realtime_risk_architecture.md`（v1.2，新增 Kafka 角色说明）

## 6. 思考题
- **Kafka 中消息的顺序性如何保证？**  
  同一分区内消息有序，不同分区无序。如果需要保证同一用户的消息顺序，可使用用户 ID 作为 key，使同一用户的消息进入同一分区。

- **如果消费者处理消息失败，如何保证不丢失？**  
  使用手动提交 offset，只有在消息处理成功后才提交 offset。如果处理失败，不提交，下次拉取仍会得到该消息。

- **实时风控中，如何选择合适的 partition 数量？**  
  根据预估 QPS 和消费者并行度决定。一般每个分区的吞吐量约为 10-20 MB/s，建议分区数 = 目标 TPS / 单分区 TPS，并考虑未来扩展。

---
**完成日期**：2026-04-19