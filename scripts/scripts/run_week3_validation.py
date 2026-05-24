import duckdb

con = duckdb.connect('dev.duckdb')
queries = [
    "SELECT 'ods_apply' AS table, COUNT(*) FROM ods_apply",
    "SELECT 'ods_decision' AS table, COUNT(*) FROM ods_decision",
    # ... 其他检查
]
for q in queries:
    print(q)
    print(con.execute(q).fetchdf())
    print()