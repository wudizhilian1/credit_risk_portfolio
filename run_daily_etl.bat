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

:: 执行 ETL
D:\Users\98128\anaconda3\python.exe scripts/run_full_etl.py --dt %DATETIME:~0,4%-%DATETIME:~4,2%-%DATETIME:~6,2% >> %LOGFILE% 2>&1

:: 记录执行结果
if errorlevel 1 (
    echo [%DATETIME:~9%] ETL 执行失败，错误码: %errorlevel% >> %LOGFILE%
) else (
    echo [%DATETIME:~9%] ETL 执行完毕 >> %LOGFILE%
)

echo 日志已保存至 %LOGFILE%
pause