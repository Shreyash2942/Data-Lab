# Iceberg Registration and Query (Trino + Superset)

Use this to create/register and query Iceberg tables via Trino.

## 1) Start services

```bash
su - datalab
/home/datalab/app/start --start-lakehouse
```

## 2) Use Superset DB

- Superset database connection: `Trino Iceberg`

## 3) Create schema

```sql
CREATE SCHEMA IF NOT EXISTS iceberg.bronze;
CREATE SCHEMA IF NOT EXISTS iceberg.silver;
CREATE SCHEMA IF NOT EXISTS iceberg.gold;
```

## 4) Create table

```sql
CREATE TABLE IF NOT EXISTS iceberg.bronze.orders_iceberg (
  order_id BIGINT,
  customer_id BIGINT,
  amount DOUBLE,
  event_ts TIMESTAMP
);
```

## 5) Query

```sql
SHOW TABLES FROM iceberg.bronze;
SELECT * FROM iceberg.bronze.orders_iceberg LIMIT 50;
```

