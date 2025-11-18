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
- `root` - real system root (the default shell when you `docker compose exec data-lab bash`). Root's home directory is symlinked to `/home/datalab`, so root and datalab always see the exact same `~/app`, `~/runtime`, and helper scripts.

## Quick Start

From repo root (copy the example env file once so Compose reads `.env`):

```bash
cp .env.example .env   # first run only; skip if .env already exists
docker compose build
docker compose up -d

# Enter the container (drops you in as root so you can switch users as needed)
docker compose exec data-lab bash

# Switch to the dev user (recommended for day-to-day work, but optional because root shares the same home)
su - datalab

# Need the intermediate admin user?
docker compose exec -u datalab_root data-lab bash
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

Storage sanity checks (after Hadoop/Hive are running):

```bash
bash ~/hadoop/scripts/hdfs_check.sh   # uploads sample data into HDFS and prints it back
bash ~/hive/bootstrap_demo.sh # creates three demo databases + tables
```

## Runtime Storage

All logs, metadata, warehouses, and other mutable state live under `runtime/` at the repo root. Docker bind-mounts this directory to `/home/datalab/runtime` so every stack (Airflow, Spark, Hadoop, Hive, Kafka, dbt, Terraform, lakehouse demos, etc.) writes into its own subfolder. Remove a specific subfolder (e.g., `runtime/airflow`) when you want to reset that stack; the helper scripts recreate it automatically.

The `.dockerignore` file keeps `runtime/`, `airflow/logs/`, and other generated files out of the Docker build context, so images stay small even though the logs remain available through the bind mount.

## Service Control Helper

You can work either from `~/app` (inside the container) or from the same path when running as root/datalab_root (because `/home/datalab` is shared). Launch the orchestration menu with:

```bash
bash ~/app/start
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

To stop running services, use `bash ~/app/stop`. To cycle (stop + start) them, run `bash ~/app/restart` (all menu options work inside the container except option `7`, which needs the host Docker CLI).

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
| `15` | Run the HDFS smoke test (uploads `~/hadoop/sample_data/hello_hdfs.txt` into `/data-lab/demo`). |
| `16` | Create/show the Hive demo databases (`sales_demo`, `analytics_demo`, `staging_demo`) via the Hive CLI. |

### Hive CLI shortcut

Option `3` in `bash ~/app/start` brings up Hadoop plus the embedded Derby metastore. After that you can simply run `hivelegacy` (classic-style prompt) or `hivecli` (plain Beeline) from any shell inside the container—both commands are on your `PATH` and call the wrapped scripts in `~/app/scripts/hive/`. They auto-connect to `jdbc:hive2://localhost:10001/...`, add `hive.cli.print.current.db=true;` so `USE db;` shows in the prompt, and verify HS2 before launching. Prefer Spark SQL? Run `spark-sql -e 'SHOW DATABASES;'`.

The wrapper honors `HIVE_CLI_HOST/PORT/HTTP_PATH/AUTH/USER/PASS` environment variables, so you can override the endpoint if you change the HS2 port.

Only start HiveServer2 (for JDBC/ODBC tools such as Airflow’s Hive hook) when you need it. A helper script handles the startup + verification:

```bash
# from the host
docker compose exec -u datalab data-lab bash   # or omit -u to run as root
bash ~/app/scripts/hive/hs2.sh start
```

That script launches HS2 over HTTP (`localhost:10001/cliservice`), waits for the port, and runs `SHOW DATABASES` through the Beeline wrapper. Stop it with `bash ~/app/scripts/hive/hs2.sh stop`.
## Published Ports

All services share the single container `data-lab`. Docker publishes the following named ports so dashboards (Docker Desktop, Portainer, etc.) clearly identify them:

| Name | Host ↔ Container | Service |
| --- | --- | --- |
| `airflow-ui` | `8080:8080/tcp` | Airflow webserver or other UI demos |
| `spark-ui` | `4040:4040/tcp` | Spark application UI |
| `spark-master` | `9090:9090/tcp` | Spark master web UI |
| `spark-history` | `18080:18080/tcp` | Spark history server |
| `kafka-broker` | `9092:9092/tcp` | Kafka broker |
| `hadoop-namenode` | `9870:9870/tcp` | HDFS NameNode UI |
| `yarn-resourcemanager` | `8088:8088/tcp` | YARN ResourceManager UI |
| `hiveserver2` | `10000:10000/tcp` | HiveServer2 JDBC endpoint |

### Working as `root` vs `datalab`

- `docker compose exec data-lab bash` lands at `root`, but `/root` is a symlink to `/home/datalab`. That means `~/app/start`, `~/runtime`, and every stack folder look identical whether you are `root`, `datalab`, or `datalab_root`.
- You can launch services from either user; the helper scripts derive paths from `$HOME`/`$WORKSPACE`, so both contexts start Hadoop, Hive, Spark, Kafka, and Airflow the same way.
- For non-root work, simply run `su - datalab` (or `docker compose exec -u datalab data-lab bash`) and continue. Drop back to `root` or `datalab_root` only when you need elevated permissions.

## dbt profile

The repo now ships with `dbt/profiles.yml`, which targets a local DuckDB database located at `~/runtime/dbt/data_lab.duckdb`. You can run `dbt debug` or `dbt run` immediately inside the container without provisioning Postgres. Update the profile if you want to point at an external warehouse.

## System Requirements

- Docker / Docker Desktop (recent)
- 4+ GB RAM (8+ GB recommended)
- 8-15 GB free disk space

For details, see `docs/Data-Lab-Documentation.md`.
