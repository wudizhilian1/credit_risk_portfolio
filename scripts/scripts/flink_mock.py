#!/usr/bin/env python3
"""
Flink 模拟脚本：模拟 DataStream API 的 keyBy、滚动窗口、滑动窗口计算。
无实际 Flink 依赖，仅用于理解窗口逻辑。
用法：python scripts/flink_mock.py
"""

import time
import random
from collections import defaultdict
from datetime import datetime


class FlinkMock:
    """模拟 Flink 流处理环境"""
    def __init__(self):
        self.events = []  # 存储原始事件

    def add_event(self, event):
        """添加事件到模拟流中"""
        self.events.append(event)

    def key_by(self, key_func):
        """模拟 keyBy 操作：按 key 分组"""
        grouped = defaultdict(list)
        for event in self.events:
            key = key_func(event)
            grouped[key].append(event)
        return grouped

    def tumbling_window(self, grouped, window_sec):
        """
        模拟滚动窗口
        :param grouped: keyBy 后的字典 {key: [events]}
        :param window_sec: 窗口长度（秒）
        :return: 字典 {(key, window_start): [events]}
        """
        windows = defaultdict(list)
        for key, events in grouped.items():
            for evt in events:
                ts = evt['timestamp']
                window_start = int(ts // window_sec) * window_sec
                window_key = (key, window_start)
                windows[window_key].append(evt)
        return windows

    def sliding_window(self, grouped, window_sec, slide_sec):
        """
        模拟滑动窗口
        :param grouped: keyBy 后的字典 {key: [events]}
        :param window_sec: 窗口长度（秒）
        :param slide_sec: 滑动步长（秒）
        :return: 字典 {(key, window_start): [events]}
        """
        windows = defaultdict(list)
        for key, events in grouped.items():
            for evt in events:
                ts = evt['timestamp']
                # 计算该事件所属的所有滑动窗口起始时间
                first_start = ts - window_sec + slide_sec
                last_start = ts
                start = first_start - (first_start % slide_sec)
                while start <= last_start:
                    window_key = (key, start)
                    windows[window_key].append(evt)
                    start += slide_sec
        return windows

    def count_per_window(self, windows):
        """统计每个窗口内的事件数量"""
        result = []
        for (key, start), events in windows.items():
            result.append({
                'key': key,
                'window_start': start,
                'window_end': start + 10,  # 假设窗口长度 10 秒（需外部传入）
                'count': len(events)
            })
        return result


def generate_mock_events(num_events=100, user_range=10, time_span=60):
    """生成模拟事件（user_id, timestamp）"""
    events = []
    base_time = time.time()
    for i in range(num_events):
        user_id = random.randint(1, user_range)
        timestamp = base_time + random.uniform(0, time_span)
        events.append({
            'user_id': user_id,
            'timestamp': timestamp,
            'event_id': i
        })
    # 按时间排序
    events.sort(key=lambda x: x['timestamp'])
    return events


def main():
    print("=== Flink 模拟：滚动窗口和滑动窗口 ===\n")

    # 1. 生成模拟事件
    events = generate_mock_events(num_events=50, user_range=5, time_span=30)
    print(f"生成 {len(events)} 个模拟事件，时间范围约 30 秒")

    # 2. 创建模拟 Flink 环境并添加事件
    flink = FlinkMock()
    for evt in events:
        flink.add_event(evt)

    # 3. 按 user_id 分组
    grouped = flink.key_by(lambda e: e['user_id'])
    print(f"分组后用户数: {len(grouped)}")

    # 4. 滚动窗口（窗口长度 10 秒）
    print("\n--- 滚动窗口 (窗口长度 10 秒) ---")
    tumbling_windows = flink.tumbling_window(grouped, window_sec=10)
    tumbling_results = flink.count_per_window(tumbling_windows)
    # 按窗口起始时间排序
    tumbling_results.sort(key=lambda x: x['window_start'])
    for res in tumbling_results[:15]:  # 打印前 15 条
        print(f"用户 {res['key']} 窗口 [{res['window_start']:.0f}, {res['window_end']:.0f}) 事件数: {res['count']}")

    # 5. 滑动窗口（窗口长度 10 秒，滑动步长 5 秒）
    print("\n--- 滑动窗口 (窗口长度 10 秒，滑动步长 5 秒) ---")
    sliding_windows = flink.sliding_window(grouped, window_sec=10, slide_sec=5)
    sliding_results = flink.count_per_window(sliding_windows)
    sliding_results.sort(key=lambda x: x['window_start'])
    for res in sliding_results[:15]:
        print(f"用户 {res['key']} 窗口 [{res['window_start']:.0f}, {res['window_end']:.0f}) 事件数: {res['count']}")

    print("\n模拟结束。")

if __name__ == '__main__':
    main()