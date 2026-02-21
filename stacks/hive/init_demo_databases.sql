-- Creates three demo databases plus simple tables to verify Hive services.

CREATE DATABASE IF NOT EXISTS sales_demo;
CREATE DATABASE IF NOT EXISTS analytics_demo;
CREATE DATABASE IF NOT EXISTS staging_demo;

DROP TABLE IF EXISTS sales_demo.daily_orders;
CREATE TABLE sales_demo.daily_orders (
  order_id INT,
  order_date STRING,
  customer STRING,
  amount DOUBLE
);
INSERT OVERWRITE TABLE sales_demo.daily_orders VALUES
  (1, '2024-01-01', 'Alice', 125.50),
  (2, '2024-01-02', 'Bob', 98.25),
  (3, '2024-01-03', 'Carol', 212.00);

DROP TABLE IF EXISTS analytics_demo.customer_metrics;
CREATE TABLE analytics_demo.customer_metrics (
  customer STRING,
  total_spent DOUBLE,
  last_seen STRING
);
INSERT OVERWRITE TABLE analytics_demo.customer_metrics VALUES
  ('Alice', 125.50, '2024-01-01'),
  ('Bob', 98.25, '2024-01-02'),
  ('Carol', 212.00, '2024-01-03');

DROP TABLE IF EXISTS staging_demo.raw_events;
CREATE TABLE staging_demo.raw_events (
  event_id STRING,
  payload STRING
);
INSERT OVERWRITE TABLE staging_demo.raw_events VALUES
  ('evt-001', '{"source":"app","action":"login"}'),
  ('evt-002', '{"source":"api","action":"purchase"}');
