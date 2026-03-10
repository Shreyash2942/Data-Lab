# Data Lab CLI Guide (`datalab_app`)

This guide describes the user-facing CLI flow for `datalab_app`.

## Default Menu (Start-focused)

Running `datalab_app` with no flags opens:

```text
=== Data Lab ===
1) Quick Start
2) Databases
3) Lakehouse & Analytics
4) Status & Access Info
5) Manage Services
0) Exit
```

- Default menu is for **start** and **status/info** only.
- Stop/restart operations are done with flags.

## Quick Start

`Quick Start` includes:

1. Start ETL Stack
   Airflow + Spark + Hadoop + Hive + Kafka
2. Start Database Stack
   PostgreSQL + MongoDB + Redis + pgAdmin
3. Start Lakehouse Stack
   MinIO + Trino + Superset + Hive/Hadoop
4. Start Full Platform
   ETL + Databases + Lakehouse

## Databases

Each database action starts the database service. PostgreSQL includes pgAdmin:

1. PostgreSQL (+ pgAdmin)
2. MongoDB
3. Redis
4. All Databases (+ pgAdmin for PostgreSQL)

## Lakehouse & Analytics

1. MinIO
2. Trino
3. Superset
4. Full Lakehouse Stack
5. Test Lakehouse Catalogs (Iceberg/Delta/Hudi via Trino)
6. Setup Simple Demo (schemas/tables for `demo_iceberg`, `demo_delta`, `demo_hudi`)

Superset/Trino query model:

- Use one Superset database connection: `Trino Lakehouse`.
- Use 2-part names: `schema.table` (for example `demo_iceberg.iceberg_table`).
- Do not use 3-part names in SQL Lab for the demo flow.

## Status & Access Info

Read-only information menus:

1. Show running services
2. Show service URLs
3. Show connection details

## Manage Services

Starts individual services:

1. Airflow
2. Spark
3. Hadoop
4. Hive
5. Kafka
6. MinIO
7. Trino
8. Superset
9. PostgreSQL (+ pgAdmin)
10. MongoDB
11. Redis

## Flag-based Commands

### Start stack flags

```bash
datalab_app --start-etl-stack
datalab_app --start-database-stack
datalab_app --start-lakehouse-stack
datalab_app --start-full-platform
```

### Status/info flags

```bash
datalab_app --status-services
datalab_app --status-urls
datalab_app --status-connections
```

### Test flag

```bash
datalab_app --test-lakehouse-catalogs
datalab_app --setup-lakehouse-demo
```

### Stop/restart flags (use with `datalab_app`)

```bash
datalab_app --stop-etl-stack
datalab_app --stop-database-stack
datalab_app --stop-lakehouse-stack
datalab_app --stop-full-platform

datalab_app --restart-etl-stack
datalab_app --restart-database-stack
datalab_app --restart-lakehouse-stack
datalab_app --restart-full-platform
```

### Individual service flags (existing)

```bash
datalab_app --start-airflow
datalab_app --start-spark
datalab_app --start-hadoop
datalab_app --start-hive
datalab_app --start-kafka
datalab_app --start-minio
datalab_app --start-trino
datalab_app --start-superset
datalab_app --start-postgres
datalab_app --start-mongodb
datalab_app --start-redis
```

## Compatibility Notes

- Legacy flags are still supported (for example `--start-core`, `--start-lakehouse`, `--start-databases`, `--test-lakehouse`, `--validate-stack`).
- `datalab_app --help` prints current supported flags.
- MongoDB and Redis are NoSQL services. They do not provide SQL-style schema/table creation in this stack.
- MongoDB should be managed as `database -> collection`, and Redis as key/value (for example via Compass/Redis Insight/CLI).

## Implementation Note (for maintainers)

Shared stack orchestration is centralized in:

- `datalabcontainer/app/tech/service_groups.sh`

`start`, `stop`, and `restart` reuse this module for ETL/database/lakehouse/full-platform actions to avoid duplicate logic.
