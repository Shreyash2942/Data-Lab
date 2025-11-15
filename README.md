# Data Lab -- Monolithic (Single Container) with Modular Layout

This project runs **all data engineering tools inside ONE container**: `data-lab`.

You still get a **modular file/folder layout** for clarity and debugging:
- `/dev/base` defines the main image build (all stacks baked in).
- `/dev/<tech>/Dockerfile` shows how each stack is installed individually (for debug/reference).
- `/python`, `/spark`, `/airflow`, etc. contain examples and README files.

## Tech Stacks Included (inside one container)

- Python 3
- Apache Spark (3.5.1, Hadoop 3)
- Apache Airflow
- dbt (Core + Postgres adapter)
- Hadoop (3.3.6)
- Hive (4.0.1)
- Apache Kafka (3.7.1, Scala 2.13)
- Java 11
- Scala
- Terraform (CLI, optional/demo)
- Lakehouse formats: Apache Hudi 0.15.0, Apache Iceberg 1.6.1, Delta Lake 3.2.0 (Spark runtimes baked in)

These versions are the most recent stable releases that run cleanly on OpenJDK 11, so the entire stack shares a single, compatible JDK.

## User Model

Inside the `data-lab` container:

- `datalab` - default non-root user for all dev workloads.
- `datalab_root` - admin user (for maintenance/installs).
- `root` - real system root (entered automatically when you `docker compose exec data-lab bash`). Root's home directory is `/home/datalab`, so it shows the same project tree as `datalab`.

## Quick Start

From repo root:

```bash
docker compose build
docker compose up -d

# Enter the container (drops you in as root at /)
docker compose exec data-lab bash

# Switch to the dev user and land in its home (mirrors the repo content)
su - datalab
# now you're in /home/datalab with the same folders as ~
```

Check tools (inside container):

```bash
python --version
java -version
spark-submit --version
hadoop version
hive --version || echo "Hive CLI present; metastore not configured (demo)"
kafka-topics.sh --bootstrap-server localhost:9092 --list || echo "Kafka broker not started yet"
airflow version
dbt --version
terraform version || echo "Terraform optional"
```

Use admin user when needed:

```bash
docker compose exec -u datalab_root data-lab bash
whoami   # datalab_root
```

## Runtime Storage

All logs, metadata, warehouses, and other mutable state live under `runtime/` at the repo root. Docker bind-mounts this directory to `/home/datalab/runtime` so every stack (Airflow, Spark, Hadoop, Hive, Kafka, dbt, Terraform, lakehouse demos, etc.) writes into its own subfolder. Remove a specific subfolder (e.g., `runtime/airflow`) when you want to reset that stack; the helper scripts recreate it automatically.

## Service Control Helper

You can work either from `~/app` (inside the container) or from the same path when running as root/datalab_root (because `/home/datalab` is shared). Launch the orchestration menu with:

```bash
bash ~/app/services_start.sh
```

Current menu layout:

| Option | Action |
| --- | --- |
| `1` | Start the Spark master, worker, and history server (state in `~/runtime/spark`). |
| `2` | Start Hadoop HDFS + YARN + MapReduce (logs in `~/runtime/hadoop/logs`). |
| `3` | Start Hive Metastore + HiveServer2 (state in `~/runtime/hive`). Automatically starts Hadoop if it isn't already running. |
| `4` | Start Zookeeper + Kafka broker (data/logs in `~/runtime/kafka`). |
| `5` | Start Airflow webserver & scheduler (metadata/logs in `~/runtime/airflow`). |
| `6` | Start ALL core services (Spark/Hadoop/Hive/Kafka). |

To stop running services, use `bash ~/app/services_stop.sh`. To cycle (stop + start) them, run `bash ~/app/services_restart.sh`.

## Demo Helper

Run sample jobs and validation checks with:

```bash
bash ~/app/services_demo.sh
```

| Option | Action |
| --- | --- |
| `1` | Run the Python example (`python/example.py`). |
| `2` | Run the Spark example (`spark/example_pyspark.py`). |
| `3` | Run `dbt debug && dbt run` inside `~/dbt`. |
| `4` | Execute the Kafka shell demo (`kafka/demo.sh`). |
| `5` | Compile/run the Java example. |
| `6` | Compile/run the Scala example. |
| `7` | Execute the Terraform demo in `~/terraform`. |
| `8` | Airflow version check. |
| `9` | Hadoop version check. |
| `10` | Hive CLI check (`SHOW DATABASES;`). |
| `11` | Run all demos/checks sequentially. |
| `12` | Run the bundled Apache Hudi quickstart (writes/reads `~/runtime/lakehouse/hudi_tables`). |
| `13` | Run the Apache Iceberg quickstart (creates tables in `~/runtime/lakehouse/iceberg_warehouse`). |
| `14` | Run the Delta Lake quickstart (creates tables in `~/runtime/lakehouse/delta_tables`). |

### Hive CLI shortcut

Once Hive services start, simply run `hive` (or `beeline`) in any shell. The command is aliased to `/opt/hive/bin/beeline -u jdbc:hive2://localhost:10000/default -n datalab`, so you connect to HiveServer2 automatically and can issue `SHOW DATABASES;` right away.

## dbt profile

The repo now ships with `dbt/profiles.yml`, which targets a local DuckDB database located at `~/runtime/dbt/data_lab.duckdb`. You can run `dbt debug` or `dbt run` immediately inside the container without provisioning Postgres. Update the profile if you want to point at an external warehouse.

## System Requirements

- Docker / Docker Desktop (recent)
- 4+ GB RAM (8+ GB recommended)
- 8-15 GB free disk space

For details, see `docs/Data-Lab-Documentation.md`.
