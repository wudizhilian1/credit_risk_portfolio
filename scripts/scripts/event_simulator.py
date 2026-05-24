#!/usr/bin/env python3
"""
实时事件流模拟器 + 滑动窗口计数器
模拟每秒随机生成事件，统计过去 window_sec 秒内的事件总数。
支持按 user_id 分组统计（可选）。
用法：python scripts/event_simulator.py
"""

import time
import random
import threading
from collections import deque
from datetime import datetime


class SlidingWindowCounter:
    """
    滑动窗口计数器（支持整体计数或按 key 分组计数）
    """

    def __init__(self, window_sec=5, slide_sec=1, group_by=None):
        """
        :param window_sec: 窗口长度（秒）
        :param slide_sec: 滑动步长（秒）
        :param group_by: 分组字段（例如 'user_id'），None 表示全局计数
        """
        self.window_sec = window_sec  # 窗口长度（默认5秒）
        self.slide_sec = slide_sec  # 窗口滑动步长（默认1秒）
        self.group_by = group_by  # 分组字段（如'user_id'）
        # 存储事件: 若 group_by 为 None，则使用全局队列；否则使用 dict {key: deque}
        if group_by is None:
            self.events = deque()  # 全局队列，元素为 (timestamp)
        else:
            self.events = {}  # key -> deque of timestamps
        self.lock = threading.Lock()  # 线程安全锁（多线程操作）
        self._start_sliding()  # 启动窗口滑动线程

    def add_event(self, timestamp, key=None):
        """
        添加一个事件
        :param timestamp: 事件时间戳（秒）
        :param key: 分组键（若 group_by 不为 None，则需要提供）
        """
        with self.lock:  # 加锁保证线程安全
            if self.group_by is None:
                self.events.append(timestamp)  # 全局队列直接追加
            else:
                if key is None:
                    raise ValueError("分组模式必须传key")
                if key not in self.events:
                    self.events[key] = deque()  # 新用户初始化队列
                self.events[key].append(timestamp)  # 追加时间戳

    def _clean_old(self, current_time):
        """清理超出窗口的旧事件"""
        # 计算窗口左边界：当前时间 - 窗口长度
        window_left = current_time - self.window_sec
        if self.group_by is None:
            # 全局队列：移除所有早于左边界的时间戳
            while self.events and self.events[0] < window_left:
                self.events.popleft()
        else:
            # 分组队列：遍历每个用户的队列，清理过期数据
            for key in list(self.events.keys()):  # 遍历副本避免删改冲突
                dq = self.events[key]
                while dq and dq[0] < window_left:
                    dq.popleft()
                if not dq:  # 队列空则删除该用户（节省内存）
                    del self.events[key]

    def get_count(self, current_time, key=None):
        """
        获取当前窗口内的事件数量
        :param current_time: 当前时间戳
        :param key: 分组键（若 group_by 不为 None，则必须提供）
        :return: 事件数量
        """
        with self.lock:
            self._clean_old(current_time)  # 先清理过期事件
            if self.group_by is None:
                return len(self.events)  # 全局队列长度 = 总事件数
            else:
                if key is None:
                    # 不传key则返回所有用户的事件总数
                    return sum(len(dq) for dq in self.events.values())
                # 传key则返回指定用户的事件数（无则返回0）
                return len(self.events.get(key, deque()))

    def _sliding_loop(self):
        """定期打印窗口统计"""
        while True:
            time.sleep(self.slide_sec)  # 按滑动步长休眠（默认1秒）
            now = time.time()
            total = self.get_count(now)  # 获取当前窗口事件数
            # 格式化打印统计结果
            if self.group_by is None:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] 窗口内总事件数: {total}")
            else:
                with self.lock:
                    snapshot = {k: len(dq) for k, dq in self.events.items()}
                print(f"[{datetime.now().strftime('%H:%M:%S')}] 窗口内各用户事件数: {snapshot}")

    def _start_sliding(self):
        t = threading.Thread(target=self._sliding_loop, daemon=True)
        t.start()


def event_generator():
    """
    模拟实时事件流，每秒随机生成 0-3 个事件
    每个事件包含 event_id, event_type, user_id, timestamp
    """
    event_id = 0
    while True:
        num_events = random.randint(0, 3)  # 每秒随机生成0-3个事件
        events_batch = []
        for _ in range(num_events):
            event_id += 1
            event = {
                'event_id': event_id,  # 唯一事件ID
                'event_type': random.choice(['apply', 'transaction']),  # 随机事件类型
                'user_id': random.randint(1, 100),  # 随机用户ID（1-100）
                'timestamp': time.time()  # 事件发生时间戳
            }
            events_batch.append(event)
        yield events_batch  # 生成一批事件
        time.sleep(1)  # 模拟每秒一批事件


def main():
    # 配置滑动窗口：窗口长度 5 秒，滑动步长 1 秒，按 user_id 分组统计
    counter = SlidingWindowCounter(window_sec=5, slide_sec=1, group_by='user_id')

    print("开始模拟实时事件流，滑动窗口每 1 秒输出一次统计...")
    for events in event_generator():
        for evt in events:
            # 添加事件到计数器，使用 user_id 作为分组键
            counter.add_event(evt['timestamp'], key=evt['user_id'])
            # 可选：打印每个事件详情（可取消注释）
            # print(f"收到事件: {evt['event_id']} user={evt['user_id']} type={evt['event_type']}")

        # 可选：检查是否有用户超过阈值（例如 5 秒内申请超过 3 次）
        # 这里只是演示，不实际触发告警


if __name__ == '__main__':
    main()