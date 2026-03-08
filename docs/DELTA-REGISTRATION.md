# Delta Registration and Query (Trino + Superset)

Use this to create/register and query Delta tables via Trino.

## 1) Start services

```bash
su - datalab
/home/datalab/app/start --start-lakehouse
```

## 2) Use Superset DB

- Superset database connection: `Trino Delta`

## 3) Create schema

```sql
CREATE SCHEMA IF NOT EXISTS delta.bronze;
CREATE SCHEMA IF NOT EXISTS delta.silver;
CREATE SCHEMA IF NOT EXISTS delta.gold;
```

## 4) Create table

```sql
CREATE TABLE IF NOT EXISTS delta.bronze.orders_delta (
  order_id BIGINT,
  customer_id BIGINT,
  amount DOUBLE,
  event_ts TIMESTAMP
);
```

## 5) Query

```sql
SHOW TABLES FROM delta.bronze;
SELECT * FROM delta.bronze.orders_delta LIMIT 50;
```

