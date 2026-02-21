# Base Image (Monolithic)

This image is used by `docker-compose.yml` to build the single `data-lab` container.

Includes:

- Ubuntu 22.04
- Python 3
- Java 11 (OpenJDK)
- Scala
- Spark 3.5.1 (Hadoop 3)
- Hadoop 3.3.6
- Hive 4.0.1
- Airflow
- dbt Core + Postgres adapter
- Terraform (optional)
- Dual users: `datalab` (default) and `root` (admin)

Lakehouse tooling baked in:

- Apache Hudi 0.15.0 Spark 3.5 bundle
- Apache Iceberg 1.6.1 Spark runtime
- Delta Lake 3.2.0 (Scala + Python packages)

> All JVM-based components (Spark, Hadoop, Hive, Kafka, Airflow) run on this single Java 11 runtime to avoid cross-version conflicts.

## Resources

- Ubuntu: https://ubuntu.com/server/docs
- Docker: https://docs.docker.com/
- Docker Compose: https://docs.docker.com/compose/
