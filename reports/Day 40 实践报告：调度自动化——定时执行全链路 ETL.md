# Day 40 实践报告：调度自动化——定时执行全链路 ETL

## 1. 练习目标

- 将人工执行的 ETL 流程自动化，实现每日定时调度。
- 学习使用操作系统自带的定时任务工具（Windows 任务计划程序 / Linux cron）。
- 编写批处理脚本，记录执行日志，便于追溯和故障排查。
- 解决调度环境中的路径依赖、中文字符等常见问题。

## 2. 实验环境

- 操作系统：Windows 10/11
- Python 版本：3.8+（Anaconda）
- 项目路径：`C:\credit_risk_portfolio`（纯英文路径，避免中文问题）
- 已有脚本：
  - `scripts/run_full_etl.py`（全链路 ETL）
  - `scripts/run_sql.py`（执行 SQL 文件）
  - `scripts/alert_engine.py`（告警引擎）
- 数据库：`dev.duckdb`

## 3. 核心任务执行

### 3.1 迁移项目到纯英文路径

为避免中文路径（原路径含“量化相关”）导致的编码和路径识别问题，将整个项目移动到 `C:\credit_risk_portfolio`，并确保所有脚本中的相对路径基于项目根目录。

### 3.2 编写批处理脚本 `run_daily_etl.bat`

```bash
@echo off
setlocal enabledelayedexpansion

:: 切换到项目目录
cd /d C:\credit_risk_portfolio
if errorlevel 1 (
    echo 无法进入目录 C:\credit_risk_portfolio
    pause
    exit /b 1
)

:: 创建日志目录
if not exist logs mkdir logs

:: 使用 PowerShell 获取日期时间（格式：yyyyMMdd HH:mm:ss）
for /f "tokens=*" %%i in ('powershell -Command "Get-Date -Format 'yyyyMMdd HH:mm:ss'"') do set DATETIME=%%i
set LOGFILE=logs\etl_%DATETIME:~0,8%.log

:: 写入开始日志
echo [%DATETIME:~9%] 开始执行每日 ETL >> %LOGFILE%

:: 执行 ETL（使用绝对路径的 python）
D:\Users\98128\anaconda3\python.exe scripts/run_full_etl.py --dt %DATETIME:~0,4%-%DATETIME:~4,2%-%DATETIME:~6,2% >> %LOGFILE% 2>&1

:: 记录执行结果
if errorlevel 1 (
    echo [%DATETIME:~9%] ETL 执行失败，错误码: %errorlevel% >> %LOGFILE%
) else (
    echo [%DATETIME:~9%] ETL 执行完毕 >> %LOGFILE%
)

echo 日志已保存至 %LOGFILE%
pause
```



### 3.3 修改 `run_full_etl.py` 确保子进程工作目录正确

在 `run_full_etl.py` 中定义 `PROJECT_DIR`，并在 `run_subprocess` 中强制指定 `cwd`：

```python
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def run_subprocess(cmd_list):
    result = subprocess.run(cmd_list, cwd=PROJECT_DIR, capture_output=True, text=True)
    ...
```

这样无论从哪个目录启动，子进程都会在项目根目录下执行，保证相对路径有效。

### 3.4 配置 Windows 任务计划程序

1. 打开“任务计划程序”，创建基本任务。
2. 名称：`CreditRiskETL`。
3. 触发器：每天，凌晨 2:00。
4. 操作：启动程序，选择 `C:\credit_risk_portfolio\run_daily_etl.bat`。
5. 条件：取消“只有在计算机使用交流电源时才启动任务”等限制。
6. 完成创建，并手动测试运行一次。

### 3.5 测试验证

手动运行批处理脚本，观察日志输出。

**执行日志示例**（`logs/etl_20260329.log`）：

```
[17:13:35] 开始执行每日 ETL
===== 开始全链路 ETL，日期：2026-03-29 =====
步骤1：raw → ODS ...
[2026-03-29] 输入行数: apply=0, decision=0
[2026-03-29] 输出行数: apply=0, decision=0
...
步骤7：插入对账摘要到 reconcile_summary ...
对账摘要插入成功
===== 全链路 ETL 完成，耗时 4.42 秒 =====
[17:13:35] ETL 执行完毕
```

同时，pytest 单元测试和告警引擎也正常执行，仅有一个空值率告警（策略名称空值率为 0.00 触发了阈值 0.0，属于配置过严，可后续调整）。

## 4. 遇到的问题与解决方案

| 问题                                           | 原因                                             | 解决方案                                             |
| :--------------------------------------------- | :----------------------------------------------- | :--------------------------------------------------- |
| 批处理中 `cd` 失败，提示“系统找不到指定的路径” | 原项目路径包含中文字符，且 `%date%` 变量解析异常 | 将项目迁移到纯英文路径 `C:\credit_risk_portfolio`    |
| 子进程 `run_sql.py` 找不到 SQL 文件            | 子进程工作目录未正确设置                         | 在 `run_full_etl.py` 中强制指定 `cwd=PROJECT_DIR`    |
| 日志文件未生成                                 | 重定向路径未加双引号，或目录不存在               | 使用 `>> "%LOGFILE%"` 并确保 `logs` 目录已创建       |
| 告警引擎误报空值率                             | 阈值设置为 0.0，导致 0.00 也触发告警             | 调整规则阈值（将 `threshold_warn` 改为 0.01 或更高） |

## 5. 口径与边界说明

| 要素     | 说明                                                   |
| :------- | :----------------------------------------------------- |
| 执行时间 | 选择业务低峰期（凌晨 2 点），避免影响查询性能。        |
| 日志保留 | 日志文件按日期命名，建议定期清理（如保留 30 天）。     |
| 失败重试 | 可在批处理脚本中添加循环重试逻辑（最多 3 次）。        |
| 依赖环境 | 需确保 Python 和依赖库在系统 PATH 中，或使用绝对路径。 |

## 6. 性能点

- 调度本身几乎无资源消耗。
- 全链路 ETL 耗时约 4-5 秒，远小于调度间隔，无积压风险。

## 10. 今日产出清单

- 迁移项目到纯英文路径 `C:\credit_risk_portfolio`
- 编写并调试批处理脚本 `run_daily_etl.bat`
- 修改 `run_full_etl.py`，强制子进程工作目录为项目根目录
- 配置 Windows 任务计划程序，设置每天凌晨 2 点执行
- 手动测试批处理脚本，验证全链路成功并生成日志
- 更新文档 `docs/scheduling.md`（记录调度方案和注意事项）
- LeetCode 185 题复盘
- 视频笔记（马尔可夫链）
- AI 学习笔记（Airflow 简介）

## 11. 思考题

- 如果 ETL 执行失败，如何自动重试？
  → 可在批处理脚本中使用循环，检测 `%errorlevel%`，失败则等待 5 分钟后重试，最多 3 次。
- 如何监控调度任务本身是否执行？（可使用外部监控服务，如健康检查接口，或检查日志文件最后更新时间。）
- 如果多个任务有依赖关系（如 ODS 完成后才能执行 DWD），如何设计调度？
  → 可用 Airflow 定义依赖，或编写脚本顺序调用，但当前全链路脚本已顺序执行，无需额外处理。