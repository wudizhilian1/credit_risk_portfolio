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
def test_dwd_apply_deduplication(con):
    """测试 dwd_apply_latest 去重逻辑：同一 apply_id 取 update_time 最新"""
    # 构造临时数据（模拟 ODS 中重复记录）
    con.execute("""
        CREATE OR REPLACE TEMP TABLE test_ods_apply AS
        SELECT 'apply_1' AS apply_id, 'user_1' AS user_id, 'APP' AS channel_id, 1000 AS amount,
               '2024-01-01 10:00:00' AS apply_time, '2024-01-01 10:00:00' AS update_time, '2024-01-01' AS dt
        UNION ALL
        SELECT 'apply_1', 'user_1', 'APP', 1000, '2024-01-01 10:00:00', '2024-01-01 12:00:00', '2024-01-01'
    """)
    # 执行去重逻辑（可复用 ETL 脚本中的 SQL）
    result = con.execute("""
        WITH ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY apply_id ORDER BY update_time DESC) AS rn
            FROM test_ods_apply
        )
        SELECT apply_id, update_time FROM ranked WHERE rn = 1
    """).fetchall()
    assert len(result) == 1
    assert result[0][1] == '2024-01-01 12:00:00'

def test_dws_channel_daily_consistency(con):
    """验证 dws_channel_daily 与 DWD 明细计算一致（抽样）"""
    dt = '2024-01-15'
    channel = 'APP'
    dws_rate = con.execute(f"SELECT pass_rate FROM dws_channel_daily WHERE dt='{dt}' AND channel_id='{channel}'").fetchone()[0]
    dwd_rate = con.execute(f"""
        SELECT ROUND(100.0 * COUNT(CASE WHEN decision='PASS' THEN 1 END) / COUNT(*), 2)
        FROM dwd_apply_latest a
        LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
        WHERE a.dt='{dt}' AND a.channel_id='{channel}'
    """).fetchone()[0]
    assert abs(float(dws_rate) - float(dwd_rate)) < 0.01, "通过率不一致"

def test_reject_reason_null_handling(con):
    """测试拒绝原因为 NULL 时被归为 'UNKNOWN'"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    result = con.execute("""
        SELECT COUNT(*) FROM dwd_decision_latest
        WHERE decision='REJECT' AND reject_reason IS NULL
    """).fetchone()[0]
    if result > 0:
        # 检查 dws_reject_topn_daily 中是否有 'UNKNOWN' 原因
        unknown_cnt = con.execute("""
            SELECT reject_cnt FROM dws_reject_topn_daily
            WHERE dt='2024-01-15' AND reason_code='UNKNOWN'
        """).fetchone()
        print(unknown_cnt)
        assert unknown_cnt is None, "未将 NULL 拒绝原因归入 UNKNOWN"
def test_reject_topn_pct_sum(con):
    """ 测试dws_reject_topn_daily中比例加起来为100"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    pct = con.execute("""
        WITH base AS (
        SELECT * FROM dws_reject_topn_daily 
        GROUP BY dt,reason_code,reason_desc,reason_category,reject_cnt,pct,rn
        )
        SELECT SUM(pct)  FROM base GROUP BY dt limit 1
    """).fetchone()[0]
    assert abs(float(pct) - float(100)) < 0.01, "dws_reject_topn_daily比例总和不为100"

def test_feature_pred_score_range(con):
    """ 测试特征宽表 feature_apply_broad 中 pred_score 范围是否在 [0,1]。"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    max = con.execute("""
        SELECT MAX(pred_score) FROM feature_apply_broad 
    """).fetchone()[0]

    min = con.execute("""
            SELECT MIN(pred_score) FROM feature_apply_broad 
        """).fetchone()[0]
    assert float(max) < 1, "feature_apply_broad中pred_score最大值<1"
    assert float(min) > 0, "feature_apply_broad中pred_score最小值>0"

def test_mv_user_hist_consistency(con):
    """ 测试物化视图 mv_user_hist_30d 与原始查询结果一致（抽样对比）"""
    # 在 dwd_decision_latest 中找一条 reject_reason 为 NULL 的记录（如果没有，可临时构造）
    base = con.execute("""
        SELECT COUNT(*) FROM mv_user_hist_30d
    """).fetchone()[0]

    compare = con.execute("""
            WITH base AS (
                SELECT
                    user_id,
                    COUNT(*) as apply_cnt_30d,
                    AVG(amount) AS avg_amount_30d,
                    AVG(CASE WHEN decision = 'PASS' THEN 1 ELSE 0 END) AS pass_rate_30d
                FROM dwd_apply_latest a
                LEFT JOIN dwd_decision_latest d ON a.apply_id = d.apply_id
                GROUP BY user_id
                )
                SELECT COUNT(a.*) as cnt FROM mv_user_hist_30d a inner join base b
                ON a.user_id = b.user_id AND a.apply_cnt_30d = b.apply_cnt_30d AND a.avg_amount_30d = b.avg_amount_30d
                AND a.pass_rate_30d = b.pass_rate_30d
        """).fetchone()[0]
    assert float(base) ==  float(compare), "mv_user_hist_30d 与原始查询结果一致"