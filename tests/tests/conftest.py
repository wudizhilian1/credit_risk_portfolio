import duckdb
import pytest

@pytest.fixture(scope='session')
def con():
    conn = duckdb.connect('dev.duckdb')
    yield conn
    conn.close()

@pytest.fixture()
def sample_apply_data(con):
    # 可创建临时表，插入固定数据用于测试去重逻辑
    con.execute("CREATE OR REPLACE TEMP TABLE test_apply AS ...")
    yield
    con.execute("DROP TABLE test_apply")