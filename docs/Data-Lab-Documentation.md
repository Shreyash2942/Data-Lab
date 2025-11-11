# Data Lab — Monolithic Single-Container Architecture

This environment is designed for teaching, demos, and local experimentation.

- One container: `data-lab`
- All stacks installed in that container.
- Clear folder structure:
  - `/dev/base`  → build definition for main image
  - `/dev/<stack>` → reference Dockerfiles per tech
  - `/python`, `/spark`, ... → code + README per stack
- Dual users:
  - `datalab_user` (default)
  - `datalab_root` (admin)
  - `root` (system)

Use this doc plus each stack's README to explain configuration and usage.

## dbt Defaults

- `dbt/profiles.yml` is committed and points to a DuckDB database at `/workspace/dbt/data_lab.duckdb`, so `dbt debug` works immediately.
- Adjust the profile if you want to connect to Postgres or any other warehouse.

## Hadoop Single-Node Setup

- `dev/hadoop/conf/*.xml` ships with pseudo-distributed defaults (localhost NameNode/YARN).
- Use `/workspace/app/scripts/services_start.sh` option 3 to format (first run) and start the daemons (Spark/Hadoop/Hive bundle). Run `/workspace/app/scripts/services_stop.sh` to stop them.
- HDFS data directories live under `/workspace/hadoop/dfs`, so they persist outside the container.

## Spark Master + Worker

- `dev/spark/conf/spark-env.sh` and `spark-defaults.conf` configure a localhost master (`spark://localhost:7077`), worker, and history server with logs under `/workspace/spark/events`.
- Use the helper script option 3 (or `/workspace/app/scripts/services_start.sh --start-core`) to start the Spark services (along with Hadoop + Hive); stop them with `/workspace/app/scripts/services_stop.sh`.

## Hive Metastore + HiveServer2

- `dev/hive/conf/hive-site.xml` configures an embedded Derby metastore stored in `/workspace/hive/metastore_db` with a warehouse path at `/workspace/hive/warehouse`.
- From the helper script choose option 3 to start the metastore + HiveServer2 (with Spark/Hadoop/Kafka) and `/workspace/app/scripts/services_stop.sh` to stop them. Option 6 launches the CLI for quick queries.

## Kafka Broker

- `dev/kafka/conf/server.properties` and `zookeeper.properties` define a single-node Kafka + Zookeeper stack with logs/data under `/workspace/kafka`.
- Start it with option 3 of the helper (or `services_start.sh --start-core`); stop via `/workspace/app/scripts/services_stop.sh`.
- The broker is exposed on `PLAINTEXT://localhost:9092`. Run the demo at `/workspace/kafka/demo.sh` (menu option 7) to verify the pipeline.
