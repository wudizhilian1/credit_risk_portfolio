import duckdb
import pytest

@pytest.fixture
def con():
    conn = duckdb.connect('dev.duckdb')
    yield conn
    conn.close()

def test_dws_channel_daily_apply_cnt(con):
    # 随机选取一个日期进行测试
    dt = '2024-01-15'
    dws_apply = con.execute(f"SELECT apply_cnt FROM dws_channel_daily WHERE dt='{dt}' AND channel_id='APP'").fetchone()[0]
    dwd_apply = con.execute(f"""
        SELECT COUNT(DISTINCT apply_id) FROM dwd_apply_latest
        WHERE dt='{dt}' AND channel_id='APP'
    """).fetchone()[0]
    assert dws_apply == dwd_apply, f"申请量不一致：dws={dws_apply}, dwd={dwd_apply}"

def test_ads_overview_daily_consistency(con):
    # 随机抽取某日检查 ADS 与 DWS 是否一致
    dt = '2024-01-15'
    ads_apply = con.execute(f"SELECT apply_cnt FROM ads_overview_daily WHERE dt='{dt}'").fetchone()[0]
    dws_apply = con.execute(f"SELECT SUM(apply_cnt) FROM dws_channel_daily WHERE dt='{dt}'").fetchone()[0]
    assert ads_apply == dws_apply, f"ADS 申请量 {ads_apply} 与 DWS 汇总 {dws_apply} 不一致"