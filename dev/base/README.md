# Base Image (Monolithic)

This image is used by `docker-compose.yml` to build the single `data-lab` container.

Includes:

- Ubuntu 22.04
- Python 3
- Java 17 (OpenJDK)
- Scala
- Spark 3.5.1 (Hadoop 3)
- Hadoop 3.3.6
- Hive 3.1.3
- Airflow
- dbt Core + Postgres adapter
- Terraform (optional)
- Dual users: `datalab_user` (default), `datalab_root` (admin)

## Resources

- Ubuntu: https://ubuntu.com/server/docs
- Docker: https://docs.docker.com/
- Docker Compose: https://docs.docker.com/compose/
