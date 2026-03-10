-- Run in Trino SQL
DROP TABLE IF EXISTS iceberg.demo_iceberg.iceberg_table;

CREATE TABLE iceberg.demo_iceberg.iceberg_table (
  order_id BIGINT,
  customer VARCHAR,
  amount DOUBLE
);

INSERT INTO iceberg.demo_iceberg.iceberg_table VALUES
  (1, 'alice', 100.5),
  (2, 'bob', 200.0);
