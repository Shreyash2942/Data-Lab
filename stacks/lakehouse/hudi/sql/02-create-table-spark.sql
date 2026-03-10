-- Run with spark-sql
CREATE DATABASE IF NOT EXISTS demo_hudi;

DROP TABLE IF EXISTS demo_hudi.order_hudi;

CREATE TABLE demo_hudi.order_hudi (
  order_id BIGINT,
  customer STRING,
  amount DOUBLE,
  ts STRING
)
USING hudi
OPTIONS (
  primaryKey = 'order_id',
  preCombineField = 'ts',
  type = 'cow',
  hoodie.metadata.enable = 'false',
  hoodie.embed.timeline.server = 'false',
  hoodie.datasource.hive_sync.enable = 'true',
  hoodie.datasource.hive_sync.mode = 'hms',
  hoodie.datasource.hive_sync.database = 'demo_hudi',
  hoodie.datasource.hive_sync.table = 'order_hudi',
  hoodie.datasource.hive_sync.metastore.uris = 'thrift://localhost:9083'
)
LOCATION 'hdfs://localhost:9000/datalake/hudi/demo_hudi/order_hudi';

INSERT INTO demo_hudi.order_hudi VALUES
  (1, 'alice', 100.5, '2026-03-08'),
  (2, 'bob', 200.0, '2026-03-08');
