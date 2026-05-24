# 数据调度方案文档

本文档描述了信贷风控数仓项目每日 ETL 的自动化调度方案，包括调度工具、执行脚本、日志管理以及故障处理策略。

---

## 1. 调度概览

| 项目         | 说明                                                  |
| ------------ | ----------------------------------------------------- |
| **调度工具** | Windows 任务计划程序（Task Scheduler）                |
| **执行频率** | 每日一次，凌晨 2:00                                   |
| **执行内容** | 全链路 ETL：raw → ODS → DWD → DWS → ADS → 对账 → 告警 |
| **预计耗时** | < 10 秒（当前数据量）                                 |
| **日志位置** | `C:\credit_risk_portfolio\logs\etl_YYYYMMDD.log`      |

---

## 2. 环境准备

### 2.1 项目路径
为避免中文路径导致的编码问题，项目已部署在纯英文目录：

C:\credit_risk_portfolio
├── scripts
│ ├── run_full_etl.py
│ ├── run_sql.py
│ ├── alert_engine.py
│ └── ...
├── sql
├── logs
├── reports
└── run_daily_etl.bat

### 2.2 Python 环境
- Python 解释器路径：`D:\Users\98128\anaconda3\python.exe`（请根据实际安装路径调整）
- 依赖库：`duckdb`, `pandas`, `tabulate`, `pytest` 等

### 2.3 数据库
- DuckDB 数据库文件：`C:\credit_risk_portfolio\dev.duckdb`

---

## 3. 批处理脚本 `run_daily_etl.bat`

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

## 4. Windows 任务计划程序配置

### 4.1 创建任务步骤

1. 打开“任务计划程序”（Task Scheduler）。
2. 点击“创建基本任务”。
3. 名称：`CreditRiskETL`，描述：每日执行信贷风控 ETL。
4. 触发器：每天，开始时间 `02:00`。
5. 操作：启动程序
   - 程序或脚本：`C:\credit_risk_portfolio\run_daily_etl.bat`
   - 起始于：`C:\credit_risk_portfolio`
6. 完成创建。

### 4.2 高级设置（推荐）

- 在任务属性中，勾选“无论用户是否登录都要运行”。
- 勾选“使用最高权限运行”。
- 设置“如果任务运行时间超过 1 小时，停止任务”（ETL 通常 < 1 分钟）。
- 在“条件”选项卡中，取消“只有在计算机使用交流电源时才启动任务”，以便笔记本电脑在电池模式下也能运行。

------

## 5. 日志管理

### 5.1 日志文件命名

- 格式：`etl_YYYYMMDD.log`，例如 `etl_20260329.log`
- 存放路径：`C:\credit_risk_portfolio\logs\`

### 5.2 日志内容示例

```
[17:13:35] 开始执行每日 ETL
===== 开始全链路 ETL，日期：2026-03-29 =====
步骤1：raw → ODS ...
[2026-03-29] 输入行数: apply=0, decision=0
...
步骤7：插入对账摘要到 reconcile_summary ...
对账摘要插入成功
===== 全链路 ETL 完成，耗时 4.42 秒 =====
[17:13:35] ETL 执行完毕
```

### 5.3 日志清理策略

- 建议保留最近 30 天日志，可编写清理脚本或使用 Windows 计划任务定期删除旧文件。

- 示例清理命令（保留最近 30 天）：

  ```bash
  forfiles /p "C:\credit_risk_portfolio\logs" /s /m *.log /d -30 /c "cmd /c del @file"
  ```

------

## 6. 故障处理

### 6.1 自动重试

可在批处理脚本中添加重试逻辑（最多 3 次）：

```bash
set RETRY=0
:retry
python scripts/run_full_etl.py ...
if errorlevel 1 (
    set /a RETRY+=1
    if !RETRY! lss 3 (
        echo [%time%] 重试第 !RETRY! 次 >> %LOGFILE%
        timeout /t 60 /nobreak
        goto retry
    ) else (
        echo [%time%] 重试失败 >> %LOGFILE%
        exit /b 1
    )
)
```

### 6.2 告警集成

ETL 执行完毕后会自动运行告警引擎（`alert_engine.py`），若产生 `WARN` 或 `ERROR` 级别告警，会在控制台输出，并可配置邮件/钉钉通知。

### 6.3 手动触发

若需临时手动运行，直接在命令行执行：

```bash
C:\credit_risk_portfolio\run_daily_etl.bat
```

------

## 7. 注意事项

- **路径依赖**：所有脚本中的相对路径都基于项目根目录，`run_full_etl.py` 内部已通过 `cwd=PROJECT_DIR` 强制子进程工作目录正确。
- **Python 环境**：批处理中使用了绝对路径 `D:\Users\98128\anaconda3\python.exe`，若迁移环境需修改。
- **数据库锁**：多个进程同时访问 `dev.duckdb` 可能导致冲突，但调度只会在固定时间运行一个进程，无并发问题。
- **节假日调整**：如需在特定日期跳过 ETL，可在批处理中添加日期判断逻辑。

------

## 8. 扩展方向

- **迁移到 Airflow**：将 ETL 步骤拆分为 DAG，实现可视化依赖管理和更复杂的重试策略。
- **容器化**：使用 Docker 打包环境，确保执行环境一致性。
- **云函数**：将调度任务迁移到云平台（如 AWS Lambda + EventBridge），免运维。

------

## 9. 版本记录

| 版本 | 日期       | 更新内容                                                    |
| :--- | :--------- | :---------------------------------------------------------- |
| v1.0 | 2026-03-29 | 初始版本，基于 Windows 任务计划程序和批处理脚本实现每日调度 |

------

*文档维护：数据工程团队*
*最后更新：2026-03-29*