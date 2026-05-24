# 第二天Python练习

## LeetCode第189 轮转数组

### 题目表述

给定一个整数数组 `nums`，将数组中的元素向右轮转 `k` 个位置，其中 `k` 是非负数。

 

**示例 1:**

```
输入: nums = [1,2,3,4,5,6,7], k = 3
输出: [5,6,7,1,2,3,4]
解释:
向右轮转 1 步: [7,1,2,3,4,5,6]
向右轮转 2 步: [6,7,1,2,3,4,5]
向右轮转 3 步: [5,6,7,1,2,3,4]
```

## 解题思路

先根据数据长度对K取模，确定初始轮转的坐标，将坐标后的数据拼接坐标前的数据

| 切片写法  | 含义                          | 结果         |
| --------- | ----------------------------- | ------------ |
| nums[:k]  | 前k个元素                     | [1, 2, 3]    |
| nums[k:]  | 索引k到末尾的元素             | [4, 5, 6, 7] |
| nums[:-k] | 开头到倒数第k个元素之前的元素 | [1, 2, 3, 4] |
| nums[-k:] | 倒数第k个元素到末尾的元素     | [5, 6, 7]    |

### 解题步骤

```python
from typing import List
class Solution:
    def rotate(self, nums: List[int], k: int) -> None:
        """
        Do not return anything, modify nums in-place instead.
        """
        n = len(nums)
        k = k % n
        nums[:] = nums[-k:] + nums[:-k]
```

# 第三天Python

## LeetCode 第187题

### 题目描述

**DNA序列** 由一系列核苷酸组成，缩写为 `'A'`, `'C'`, `'G'` 和 `'T'`.。

- 例如，`"ACGAATTCCG"` 是一个 **DNA序列** 。

在研究 **DNA** 时，识别 DNA 中的重复序列非常有用。

给定一个表示 **DNA序列** 的字符串 `s` ，返回所有在 DNA 分子中出现不止一次的 **长度为 `10`** 的序列(子字符串)。你可以按 **任意顺序** 返回答案。

 

**示例 1：**

```
输入：s = "AAAAACCCCCAAAAACCCCCCAAAAAGGGTTT"
输出：["AAAAACCCCC","CCCCCAAAAA"]
```

**示例 2：**

```
输入：s = "AAAAAAAAAAAAA"
输出：["AAAAAAAAAA"]
```

### 解题思路

1. 可以利用字典，key是截取的10个字符串，value是出现次数，统计次数：存在则+1，不存在则初始化为1，最后收集所有出现次数≥2的子串

2. 解法二，先截取字符串，判定是否存在于现有的集和seen中，没有则放在seen中，有则放在ans中（表示之前已经存在），返回ans

3. 虽然可以用双循环来判定结果，但是时间复杂度过高，不被允许

   ### 解题步骤

    

   ```python
   from typing import List
   
   class Solution:
       def findRepeatedDnaSequences(self, s: str) -> List[str]:
           # 边界条件：字符串长度小于10，不可能有重复的10长度序列
           if len(s) < 10:
               return []
           
           # 哈希表：key=长度为10的子串，value=出现次数
           sub_count = {}
           # 遍历所有可能的起始位置（0 到 len(s)-10）
           for i in range(len(s) - 9):
               # 截取长度为10的子串
               sub = s[i:i+10]
               # 统计次数：存在则+1，不存在则初始化为1
               sub_count[sub] = sub_count.get(sub, 0) + 1
           print(sub_count)
           print(type(sub_count))
           # 收集所有出现次数≥2的子串
           result = [sub for sub, count in sub_count.items() if count >= 2]
           return result
   ```

   ```python
   class Solution:
       def findRepeatedDnaSequences(self, s: str) -> List[str]:
           seen = set()
           ans = set()
           n = len(s)
   
           for i in range(n-9):
               x = s[i:i+10]
               
               if x in seen:
                   ans.add(x)
               else :
                   seen.add(x)
           return ans
   ```

   # 第六天练习

   ## 190颠倒二进制位

   ### 题目描述

   颠倒给定的 32 位有符号整数的二进制位。

    

   **示例 1：**

   **输入：**n = 43261596

   **输出：**964176192

   **解释：**

   | 整数      | 二进制                           |
   | --------- | -------------------------------- |
   | 43261596  | 00000010100101000001111010011100 |
   | 964176192 | 00111001011110000010100101000000 |

   ### 解题思路

   1.根据位运算规则，先获取最右端的为1的位置

   2.将原数据整除2，相当于将n的二进制右移了一位

   3.x为最终数据，x*2相当于将最终数字左移了一位，并添加最新的n的末尾，效果相当于将n直接翻转

### 最优解法

```python
class Solution:
    def reverseBits(self, n: int) -> int:
        x = 0  # 1. 初始化结果变量，存储反转后的整数
        for _ in range(32):  # 2. 循环32次：处理32位无符号整数，包含高位0
            bit = n & 1  # 3. 提取n的二进制最低位（最右侧的位）
            n //= 2  # 4. n右移一位（舍弃已提取的最低位），等价于 n = n >> 1
            x = x * 2 + bit  # 5. 核心：将提取的bit放到x的最低位，构建反转数
        return x  # 6. 返回反转后的32位整数
```

