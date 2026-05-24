@echo off
echo ===== 开始一键运行全链路 =====
cd /d C:\credit_risk_portfolio

echo 1. 生成模拟数据...
python scripts/generate_demo_data.py

echo 2. 创建 DuckDB 视图...
python scripts/bootstrap_duckdb.py --db dev.duckdb --raw data/raw

echo 3. 运行全链路 ETL（处理昨天）...
python scripts/run_full_etl.py

echo 4. 运行单元测试...
pytest tests/test_etl.py -v

echo 5. 运行告警引擎...
python scripts/alert_engine.py

echo 6. 生成性能报告...
python scripts/run_sql.py --sql sql/dws/dws_channel_daily.sql  --vars dt_start=2024-01-15 dt_end=2024-01-15 --out reports/performance_channel.md
python scripts/run_sql.py --sql sql/dws/dws_reject_topn_daily.sql --vars dt=2024-01-15 --out reports/performance_reject.md

echo 7. 生成性能基线汇总（手动记录）...
echo # 性能基线报告 > reports/performance_baseline.md
echo 执行时间: 2026-04-01 >> reports/performance_baseline.md
echo. >> reports/performance_baseline.md
echo ## dws_channel_daily >> reports/performance_baseline.md
echo - 耗时: 0.004 s >> reports/performance_baseline.md
echo - 扫描行数: 30 >> reports/performance_baseline.md
echo. >> reports/performance_baseline.md
echo ## dws_reject_topn_daily >> reports/performance_baseline.md
echo - 耗时: 0.002 s >> reports/performance_baseline.md
echo - 扫描行数: 8 >> reports/performance_baseline.md
echo. >> reports/performance_baseline.md
echo ## PSI 计算 >> reports/performance_baseline.md
echo - 耗时: 0.012 s >> reports/performance_baseline.md
echo - 扫描行数: 约 4800 >> reports/performance_baseline.md

echo ===== 一键运行完成 =====
pause