# Data Lab — Monolithic (Single Container) with Modular Layout

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
- Hive (3.1.3)
- Apache Kafka (3.7.1, Scala 2.13)
- Java 17
- Scala
- Terraform (CLI, optional/demo)

## User Model

Inside the `data-lab` container:

- `datalab_user`  → default non-root user for all dev workloads.
- `datalab_root` → admin user (for maintenance/installs).
- `root`         → real system root (only if explicitly used).

## Quick Start

From repo root:

```bash
docker compose build
docker compose up -d

# Enter as default user
docker compose exec data-lab bash
whoami   # datalab_user
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

## Tech Stack Helper

Inside the container run:

```bash
bash /workspace/app/scripts/services_start.sh
```

Pick from the menu to:
- run the Python and PySpark sample jobs
- start the full data platform stack (Spark master/worker/history + Hadoop HDFS/YARN + Hive metastore/HiveServer2 + Kafka broker/Zookeeper) via option **3** (use `/workspace/app/scripts/services_stop.sh` to stop everything later)
- launch Airflow (option **4**), run dbt (option **5**), explore Hive CLI (option **6**), trigger the Kafka demo (option **7**), and use Java/Scala/Terraform demos
- run option **11** to execute all tech stack demos/checks sequentially (Python, Spark, Airflow, dbt, Hadoop, Hive, Kafka, Java, Scala, Terraform)
- execute dbt, Java/Scala examples, or the Terraform demo

All workloads operate under `/workspace`, so results persist on the host.

## dbt profile

The repo now ships with `dbt/profiles.yml`, which targets a local DuckDB database located at `/workspace/dbt/data_lab.duckdb`. You can run `dbt debug` or `dbt run` immediately inside the container without provisioning Postgres. Update the profile if you want to point at an external warehouse.

## System Requirements

- Docker / Docker Desktop (recent)
- 4+ GB RAM (8+ GB recommended)
- 8–15 GB free disk space

For details, see `docs/Data-Lab-Documentation.md`.
