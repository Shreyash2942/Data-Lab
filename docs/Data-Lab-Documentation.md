# Data Lab - Monolithic Single-Container Architecture

This environment is designed for teaching, demos, and local experimentation.

- One container: `data-lab`
- All stacks installed in that container.
- Clear folder structure:
  - `/datalabcontainer/dev/base` -> build definition for main image
  - `/datalabcontainer/dev/<stack>` -> reference Dockerfiles per tech
  - `/stacks/<stack>` -> code + README per stack
- Dual users:
  - `datalab` (default)
  - `root` (system)
- `docker compose exec data-lab bash` drops you into `root`. The workspace is at `/home/datalab`; `cd /home/datalab` or `su - datalab` for day-to-day work (recommended). If you prefer a non-root session immediately, run `docker compose exec -u datalab data-lab bash`.

Use this doc plus each stack's README to explain configuration and usage.

## Environment Setup

Run the example-to-local env copy once so Docker Compose picks up a writable `.env`:

```bash
cp datalabcontainer/.env.example datalabcontainer/.env
```

On Windows use `copy datalabcontainer\.env.example datalabcontainer\.env`. The generated `.env` stays gitignored, so update it per machine while `.env.example` remains the shared reference.

## dbt Defaults

- `stacks/dbt/profiles.yml` is committed and points to a DuckDB database at `~/runtime/dbt/data_lab.duckdb`, so `dbt debug` works immediately.
- Adjust the profile if you want to connect to Postgres or any other warehouse.

## Runtime Storage Layout

- All mutable state is isolated under `~/runtime` inside the container (bind-mounted from `repo_root/datalabcontainer/runtime`).
- Each stack gets its own subfolder: `runtime/airflow`, `runtime/spark`, `runtime/hadoop`, `runtime/hive`, `runtime/kafka`, `runtime/lakehouse`, `runtime/dbt`, `runtime/terraform`, etc.
- Deleting a subfolder resets that stack without touching source code.
- The root `.dockerignore` excludes `datalabcontainer/runtime/`, `datalabcontainer/runtime-copies/`, and other generated state from the build context so `docker compose build` stays fast even after long-lived sessions.

## Hadoop Single-Node Setup

- `datalabcontainer/dev/hadoop/conf/*.xml` ships with pseudo-distributed defaults (localhost NameNode/YARN).
- Use `~/app/start` option 2 to format (first run) and start the Hadoop daemons. Option 6 (or `~/app/start --start-core`) starts the entire Spark/Hadoop/Hive/Kafka bundle. Run `~/app/stop` to stop them.
- HDFS data directories live under `~/runtime/hadoop/dfs`, so they persist outside the container.
- Quick verification: `bash ~/hadoop/scripts/hdfs_check.sh` uploads `~/hadoop/sample_data/hello_hdfs.txt` into `/data-lab/demo/hello_hdfs.txt` in HDFS and prints it back so you can confirm NameNode/DataNode access.

## Spark Master + Worker

- `datalabcontainer/dev/spark/conf/spark-env.sh` and `spark-defaults.conf` configure a localhost master (`spark://localhost:7077`), worker, and history server with logs under `~/runtime/spark/events`.
- Use helper option 1 to start only the Spark master/worker/history server. Combine it with option 6 or `~/app/start --start-core` when you need the full stack. Stop everything with `~/app/stop`.

## Hive Metastore + HiveServer2

- `datalabcontainer/dev/hive/conf/hive-site.xml` configures an embedded Derby metastore stored in `~/runtime/hive/metastore_db` with a warehouse path at `~/runtime/hive/warehouse`.
- From the helper script choose option 3 to start the metastore + HiveServer2 (it auto-starts Hadoop if needed). Use option 6 for the broader Spark/Hadoop/Hive/Kafka bundle. Stop services with `~/app/stop` and run the CLI via the `hive` alias once HiveServer2 is up (enable the current-db prompt with `hive --hiveconf hive.cli.print.current.db=true`).
- Quick verification: `bash ~/hive/bootstrap_demo.sh` uses the Hive CLI to create the `sales_demo`, `analytics_demo`, and `staging_demo` databases from `~/hive/init_demo_databases.sql`, and displays sample tables so you can confirm Hive is working.

## Lakehouse / Table Formats

- **Hudi (menu option 12)**: `~/app/services_demo.sh` runs `~/hudi/hudi_example.py`, writing demo data to `~/runtime/lakehouse/hudi_tables`.
- **Iceberg (menu option 13)**: the same demo helper runs `~/iceberg/iceberg_example.py`, targeting a Hadoop catalog at `~/runtime/lakehouse/iceberg_warehouse`.
- **Delta Lake (menu option 14)**: the demo helper runs `~/delta/delta_example.py`, writing to `~/runtime/lakehouse/delta_tables`.

## Kafka Broker

- `datalabcontainer/dev/kafka/conf/server.properties` and `zookeeper.properties` define a single-node Kafka + Zookeeper stack with logs/data under `~/runtime/kafka`.
- Start it with option 4 of the helper (or `~/app/start --start-core`); stop via `~/app/stop`.
- The broker is exposed on `PLAINTEXT://localhost:9092`. Run the interactive demo from `~/app/services_demo.sh` option 4 (or directly via `~/kafka/demo.sh`) to verify the pipeline.