# Data Lab — Monolithic Single-Container Architecture

This environment is designed for teaching, demos, and local experimentation.

- One container: `data-lab`
- All stacks installed in that container.
- Clear folder structure:
  - `/dev/base`  → build definition for main image
  - `/dev/<stack>` → reference Dockerfiles per tech
  - `/python`, `/spark`, ... → code + README per stack
- Dual users:
  - `datalab` (default)
  - `datalab_root` (admin)
  - `root` (system)

Use this doc plus each stack's README to explain configuration and usage.

## dbt Defaults

- `dbt/profiles.yml` is committed and points to a DuckDB database at `~/runtime/dbt/data_lab.duckdb`, so `dbt debug` works immediately.
- Adjust the profile if you want to connect to Postgres or any other warehouse.

## Runtime Storage Layout

- All mutable state is isolated under `~/runtime` inside the container (bind-mounted from `repo_root/runtime`).
- Each stack gets its own subfolder: `runtime/airflow`, `runtime/spark`, `runtime/hadoop`, `runtime/hive`, `runtime/kafka`, `runtime/lakehouse`, `runtime/dbt`, `runtime/terraform`, etc.
- Deleting a subfolder resets that stack without touching source code.

## Hadoop Single-Node Setup

- `dev/hadoop/conf/*.xml` ships with pseudo-distributed defaults (localhost NameNode/YARN).
- Use `~/app/services_start.sh` option 2 to format (first run) and start the Hadoop daemons. Option 6 (or `~/app/services_start.sh --start-core`) starts the entire Spark/Hadoop/Hive/Kafka bundle. Run `~/app/services_stop.sh` to stop them.
- HDFS data directories live under `~/runtime/hadoop/dfs`, so they persist outside the container.

## Spark Master + Worker

- `dev/spark/conf/spark-env.sh` and `spark-defaults.conf` configure a localhost master (`spark://localhost:7077`), worker, and history server with logs under `~/runtime/spark/events`.
- Use helper option 1 to start only the Spark master/worker/history server. Combine it with option 6 or `~/app/services_start.sh --start-core` when you need the full stack. Stop everything with `~/app/services_stop.sh`.

## Hive Metastore + HiveServer2

- `dev/hive/conf/hive-site.xml` configures an embedded Derby metastore stored in `~/runtime/hive/metastore_db` with a warehouse path at `~/runtime/hive/warehouse`.
- From the helper script choose option 3 to start the metastore + HiveServer2 (it auto-starts Hadoop if needed). Use option 6 for the broader Spark/Hadoop/Hive/Kafka bundle. Stop services with `~/app/services_stop.sh` and run the CLI via the `hive` alias once HiveServer2 is up.

## Lakehouse / Table Formats

- **Hudi (menu option 12)**: `~/app/services_demo.sh` runs `~/hudi/hudi_example.py`, writing demo data to `~/runtime/lakehouse/hudi_tables`.
- **Iceberg (menu option 13)**: the same demo helper runs `~/iceberg/iceberg_example.py`, targeting a Hadoop catalog at `~/runtime/lakehouse/iceberg_warehouse`.
- **Delta Lake (menu option 14)**: the demo helper runs `~/delta/delta_example.py`, writing to `~/runtime/lakehouse/delta_tables`.

## Kafka Broker

- `dev/kafka/conf/server.properties` and `zookeeper.properties` define a single-node Kafka + Zookeeper stack with logs/data under `~/runtime/kafka`.
- Start it with option 4 of the helper (or `services_start.sh --start-core`); stop via `~/app/services_stop.sh`.
- The broker is exposed on `PLAINTEXT://localhost:9092`. Run the interactive demo from `~/app/services_demo.sh` option 4 (or directly via `~/kafka/demo.sh`) to verify the pipeline.
