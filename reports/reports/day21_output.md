--- 语句 1 执行失败 ---
```sql
.print '\n=== 1. 检查 ODS 表 ==='
SELECT 'ods_apply' AS table_name, COUNT(*) AS row_count FROM ods_apply
```

错误: Parser Error: syntax error at or near "."

LINE 1: .print '\n=== 1. 检查 ODS 表 ==='
        ^
