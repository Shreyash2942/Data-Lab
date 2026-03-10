-- Run with spark-sql
CREATE DATABASE IF NOT EXISTS demo_delta;

DROP TABLE IF EXISTS demo_delta.table_delta;

CREATE TABLE demo_delta.table_delta (
  order_id BIGINT,
  customer STRING,
  amount DOUBLE
)
USING delta
LOCATION 'hdfs://localhost:9000/datalake/delta/demo_delta/table_delta';

INSERT INTO demo_delta.table_delta VALUES
  (1, 'alice', 100.5),
  (2, 'bob', 200.0);
