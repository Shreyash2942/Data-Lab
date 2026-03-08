# Hudi Registration and Query (Trino + Superset)

Use this when Spark already writes Hudi tables to HDFS and you want to query them from Trino/Superset.

## 1) Start services

```bash
su - datalab
/home/datalab/app/start --start-lakehouse
```

## 2) Use Superset DB

- Superset database connection: `Trino Hudi`

## 3) Create schema

```sql
CREATE SCHEMA IF NOT EXISTS hudi.bronze;
CREATE SCHEMA IF NOT EXISTS hudi.silver;
CREATE SCHEMA IF NOT EXISTS hudi.gold;
```

## 4) Register existing Hudi table from HDFS location

Important: `location` must be the Hudi base path (contains `.hoodie`).

```sql
CREATE TABLE IF NOT EXISTS hudi.bronze.orders_hudi (
  order_id BIGINT,
  customer_id BIGINT,
  amount DOUBLE,
  event_ts TIMESTAMP
)
WITH (
  location = 'hdfs://localhost:9000/datalake/hudi/bronze/orders_hudi',
  type = 'COPY_ON_WRITE'
);
```

## 5) Query

```sql
SHOW TABLES FROM hudi.bronze;
SELECT * FROM hudi.bronze.orders_hudi LIMIT 50;
```

