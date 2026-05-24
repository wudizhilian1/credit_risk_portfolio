#!/usr/bin/env python3
"""
kafka_mock.py
模拟 Kafka 命令行操作（无实际 Kafka 依赖），用于理解 Kafka 核心概念。
功能：模拟创建 topic、列出 topics、生产消息、消费消息。
用法：python scripts/kafka_mock.py
"""

import time
import json
from datetime import datetime

class KafkaMock:
    """模拟 Kafka 客户端"""
    def __init__(self):
        self.topics = {}          # topic_name -> {partitions: int, messages: list}
        self.next_offset = {}     # topic -> partition -> offset

    def create_topic(self, topic, partitions=1, replication_factor=1):
        """模拟创建 topic"""
        if topic in self.topics:
            print(f"[模拟] Topic '{topic}' 已存在")
            return
        self.topics[topic] = {
            'partitions': partitions,
            'messages': []   # 存储消息 (partition, offset, key, value)
        }
        self.next_offset[topic] = {p: 0 for p in range(partitions)}
        print(f"[模拟] 创建 topic '{topic}' 成功，分区数: {partitions}，副本因子: {replication_factor}")

    def list_topics(self):
        """模拟列出所有 topics"""
        topics_list = list(self.topics.keys())
        print(f"[模拟] 当前 topics: {', '.join(topics_list) if topics_list else '(无)'}")

    def produce_message(self, topic, key, value, partition=None):
        """模拟生产消息，默认使用 key 的哈希决定分区"""
        if topic not in self.topics:
            print(f"[模拟] 错误：topic '{topic}' 不存在")
            return
        partitions = self.topics[topic]['partitions']
        if partition is None:
            partition = hash(key) % partitions if key else 0
        else:
            if partition < 0 or partition >= partitions:
                print(f"[模拟] 错误：分区 {partition} 无效，有效范围 0-{partitions-1}")
                return
        offset = self.next_offset[topic][partition]
        msg = {
            'topic': topic,
            'partition': partition,
            'offset': offset,
            'key': key,
            'value': value,
            'timestamp': time.time()
        }
        self.topics[topic]['messages'].append(msg)
        self.next_offset[topic][partition] += 1
        print(f"[模拟] 生产者发送消息: topic={topic}, partition={partition}, offset={offset}, key={key}, value={value}")

    def consume_messages(self, topic, from_beginning=True, group_id=None):
        """模拟消费消息，显示所有消息"""
        if topic not in self.topics:
            print(f"[模拟] 错误：topic '{topic}' 不存在")
            return
        messages = self.topics[topic]['messages']
        if not messages:
            print(f"[模拟] topic '{topic}' 没有消息")
            return
        print(f"[模拟] 消费者开始消费 topic '{topic}' (from_beginning={from_beginning}):")
        for msg in messages:
            # 模拟显示类似 Kafka 控制台输出
            print(f"  offset={msg['offset']}, key={msg['key']}, value={msg['value']}")

def main():
    print("=== Kafka 命令行模拟器 ===\n")
    kafka = KafkaMock()

    # 1. 创建 topic
    kafka.create_topic("risk-events", partitions=3, replication_factor=1)
    print()

    # 2. 列出 topics
    kafka.list_topics()
    print()

    # 3. 模拟生产消息
    print("--- 模拟生产者发送消息 ---")
    kafka.produce_message("risk-events", key="user_123", value='{"event":"apply","amount":5000}')
    kafka.produce_message("risk-events", key="user_456", value='{"event":"login","device":"new"}')
    kafka.produce_message("risk-events", key="user_123", value='{"event":"apply","amount":8000}')
    kafka.produce_message("risk-events", key="user_789", value='{"event":"transaction","amount":12000}')
    print()

    # 4. 模拟消费消息（从最早开始）
    print("--- 模拟消费者消费消息 ---")
    kafka.consume_messages("risk-events", from_beginning=True)
    print()

    # 5. 演示分区效果：显示每个分区消息数量
    print("--- 各分区消息数量统计 ---")
    for topic, info in kafka.topics.items():
        partition_counts = {}
        for msg in info['messages']:
            p = msg['partition']
            partition_counts[p] = partition_counts.get(p, 0) + 1
        print(f"topic '{topic}': {partition_counts}")
    print()

    # 6. 模拟再次消费（从最新开始，实际不会显示已消费过的消息，但这里模拟简单重新显示）
    print("--- 再次消费同一 topic（模拟新消费者，仍从最早开始）---")
    kafka.consume_messages("risk-events", from_beginning=True)

if __name__ == '__main__':
    main()