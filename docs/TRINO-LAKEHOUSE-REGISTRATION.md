# Trino Lakehouse Registration and Query Guide

This guide shows how to register and query lakehouse tables (Hudi, Iceberg, Delta) in the **single `datalab` container**.

Format-specific guides:

- `docs/HUDI-REGISTRATION.md`
- `docs/ICEBERG-REGISTRATION.md`
- `docs/DELTA-REGISTRATION.md`

## 1) Start required services

Inside container:

```bash
su - datalab
/home/datalab/app/start --start-lakehouse
```

Check endpoints:

```bash
/home/datalab/app/ui_services --all
```

## 2) Use Trino or Superset SQL Lab

You can run SQL from:

- Trino CLI:

```bash
/opt/trino/bin/trino --server localhost:8091
```

- Superset SQL Lab:
  - Open Superset URL from `ui_services --all`
  - Login: `admin / admin`
  - Choose one of:
    - `Trino Iceberg`
    - `Trino Delta`
    - `Trino Hudi`

## 3) Verify catalogs and schemas

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;
SHOW SCHEMAS FROM delta;
SHOW SCHEMAS FROM hudi;
```

Create common layer schemas:

```sql
CREATE SCHEMA IF NOT EXISTS iceberg.bronze;
CREATE SCHEMA IF NOT EXISTS iceberg.silver;
CREATE SCHEMA IF NOT EXISTS iceberg.gold;

CREATE SCHEMA IF NOT EXISTS delta.bronze;
CREATE SCHEMA IF NOT EXISTS delta.silver;
CREATE SCHEMA IF NOT EXISTS delta.gold;

CREATE SCHEMA IF NOT EXISTS hudi.bronze;
CREATE SCHEMA IF NOT EXISTS hudi.silver;
CREATE SCHEMA IF NOT EXISTS hudi.gold;
```

## 4) Register existing Hudi data written by Spark to HDFS

If Spark already wrote Hudi files, register them in Trino by pointing to the HDFS location.

Example:

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

Then query:

```sql
SELECT * FROM hudi.bronze.orders_hudi LIMIT 50;
```

## 5) Query Iceberg and Delta tables

If tables are already registered in metastore:

```sql
SHOW TABLES FROM iceberg.bronze;
SHOW TABLES FROM delta.bronze;
SELECT * FROM iceberg.bronze.<table_name> LIMIT 50;
SELECT * FROM delta.bronze.<table_name> LIMIT 50;
```

If not yet registered, create/register them using your Spark/Hive metadata flow first, then query from Trino.

## 6) Superset behavior notes

- The project auto-creates these database connections:
  - `Trino Iceberg`
  - `Trino Delta`
  - `Trino Hudi`
- DDL/DML is enabled for these, so `CREATE SCHEMA` and `CREATE TABLE` work in SQL Lab.

## 7) Troubleshooting

If a catalog is missing:

```sql
SHOW CATALOGS;
```

Then inspect Trino catalog config:

```bash
ls -la /home/datalab/runtime/trino/etc/catalog
sed -n '1,160p' /home/datalab/runtime/trino/etc/catalog/*.properties
```

If Superset blocks CREATE statements, restart Superset:

```bash
/home/datalab/app/restart --restart-superset
```
