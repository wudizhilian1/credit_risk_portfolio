-- 创建 ods_apply 表：从分区 Parquet 读取所有数据
CREATE OR REPLACE TABLE ods_apply AS
SELECT * FROM read_parquet('data/raw/apply/dt=*/**/*.parquet', hive_partitioning = true);

-- 创建 ods_decision 表
CREATE OR REPLACE TABLE ods_decision AS
SELECT * FROM read_parquet('data/raw/decision/dt=*/**/*.parquet', hive_partitioning = true);