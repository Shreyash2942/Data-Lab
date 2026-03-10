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
/home/datalab/app/start --start-lakehouse-stack
```

Check endpoints:

```bash
/home/datalab/app/ui_services --all
```

## 2) Use Trino or Superset SQL Lab

You can run SQL from:

- Trino CLI:
  - Use `datalab_app --setup-lakehouse-demo` or `datalab_app --test-lakehouse-catalogs`
  - (The image uses Trino HTTP API fallback; direct CLI binary may not be present.)

- Superset SQL Lab:
  - Open Superset URL from `ui_services --all`
  - Login: `admin / admin`
  - Choose database: `Trino Lakehouse`

## 3) Verify catalogs and schemas

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;
SHOW SCHEMAS FROM delta;
SHOW SCHEMAS FROM hudi;
```

Create all schemas/tables automatically from the SQL assets:

```bash
datalab_app --setup-lakehouse-demo
```

This uses:

- `stacks/lakehouse/iceberg/sql/01-create-schema-trino.sql`
- `stacks/lakehouse/iceberg/sql/02-create-table-trino.sql`
- `stacks/lakehouse/delta/sql/01-create-schema-trino.sql`
- `stacks/lakehouse/delta/sql/02-create-table-spark.sql`
- `stacks/lakehouse/delta/sql/03-register-table-trino.sql`
- `stacks/lakehouse/hudi/sql/01-create-schema-trino.sql`
- `stacks/lakehouse/hudi/sql/02-create-table-spark.sql`

## 4) Query demo tables

```sql
SHOW TABLES FROM demo_iceberg;
SHOW TABLES FROM demo_delta;
SHOW TABLES FROM demo_hudi;

SELECT * FROM demo_iceberg.iceberg_table;
SELECT * FROM demo_delta.table_delta;
SELECT * FROM demo_hudi.order_hudi;
```

For Hudi, if `order_hudi` is not present, register/sync a Hudi table from Spark to Hive Metastore, then query in `demo_hudi`.
For Delta on HDFS, write with Spark and register in Trino (`delta.system.register_table`).

## 5) Superset behavior notes

- The project auto-creates one connection: `Trino Lakehouse`.
- DDL/DML is enabled for this Trino database in SQL Lab.
- Use 2-part names (`schema.table`) in SQL Lab:
  - `demo_iceberg.iceberg_table`
  - `demo_delta.table_delta`
  - `demo_hudi.order_hudi`
- This works through Hive catalog redirection:
  - `hive.iceberg-catalog-name=iceberg`
  - `hive.delta-lake-catalog-name=delta`
  - `hive.hudi-catalog-name=hudi`

## 6) Troubleshooting

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
