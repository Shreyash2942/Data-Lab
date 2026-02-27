# Base Image (Monolithic)

This image is used by `docker-compose.yml` to build the single `data-lab` container.

Includes:

- Ubuntu 22.04
- Python 3
- Java 11 (OpenJDK)
- Scala
- Spark 3.5.1 (Hadoop 3)
- Hadoop 3.3.6
- Hive 2.3.9 (Spark 3.5 compatible)
- Airflow
- dbt Core + Postgres adapter
- Terraform (optional)
- Dual users: `datalab` (default) and `root` (admin)

Lakehouse tooling baked in:

- Apache Hudi 0.15.0 Spark 3.5 bundle
- Apache Iceberg 1.6.1 Spark runtime
- Delta Lake 3.2.0 (Scala + Python packages)

> All JVM-based components (Spark, Hadoop, Hive, Kafka, Airflow) run on this single Java 11 runtime to avoid cross-version conflicts.

## Build Optimization Notes
- Build context is trimmed via root `.dockerignore` to avoid large runtime/doc/helper payloads.
- `PIP_NO_CACHE_DIR=1` and `PIP_DISABLE_PIP_VERSION_CHECK=1` reduce pip cache overhead.
- npm global tools are installed once and npm cache is cleaned.
- Python dependency installs are consolidated to reduce image layers.
- Runtime scripts are normalized in entrypoint to avoid Windows CRLF shell failures.

## Resources

- Ubuntu: https://ubuntu.com/server/docs
- Docker: https://docs.docker.com/
- Docker Compose: https://docs.docker.com/compose/
