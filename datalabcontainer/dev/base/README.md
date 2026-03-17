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
- Kafka Connect (bundled with Kafka 3.7.1)
- Debezium PostgreSQL connector (bundled into Kafka Connect plugins)
- Apicurio Registry 3.2.0
- Apicurio Kafka Connect converter bundle for registry-backed CDC demos
- OpenLineage Spark integration 1.38.0
- Marquez 0.50.0
- Prometheus 3.2.1
- Grafana 11.5.2
- Great Expectations 1.15.0 (isolated venv)
- JupyterLab 4.2.7 (isolated venv)
- Airflow
- dbt Core + DuckDB/Postgres/Hive/Spark adapters
- Terraform (optional)
- Dual users: `datalab` (default) and `root` (admin)

Lakehouse tooling baked in:

- Apache Hudi 0.15.0 Spark 3.5 bundle
- Apache Iceberg 1.6.1 Spark runtime
- Delta Lake 3.2.0 (Scala + Python packages)

> The primary data stack (Spark, Hadoop, Hive, Kafka, Airflow) runs on Java 11. Service-specific runtimes are bundled where required: Marquez uses Java 17 and Apicurio Registry uses Java 21.

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
