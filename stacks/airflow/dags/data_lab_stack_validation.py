from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

class DataLabBashOperator(BashOperator):
  # Disable file-based templating so bash_command strings aren't treated as template file paths.
  template_ext = ()


def bash_task(task_id: str, command: str, **kwargs) -> BashOperator:
  # Some Airflow environments enforce strict global task timeouts; keep
  # stack-validation tasks from being killed prematurely.
  kwargs.setdefault("execution_timeout", timedelta(minutes=30))
  kwargs.setdefault("retries", 2)
  kwargs.setdefault("retry_delay", timedelta(seconds=45))
  return DataLabBashOperator(
      task_id=task_id,
      bash_command=command,
      do_xcom_push=False,
      **kwargs,
  )


with DAG(
    dag_id="data_lab_stack_validation",
    description="Runs the built-in demos/tests for every stack in the monolithic container.",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

  start_core_services = bash_task(
      "start_core_services",
      "echo 'Core services are initialized per task.'",
  )

  start_database_services = bash_task(
      "start_database_services",
      "echo 'Database services are initialized per task.'",
  )

  # Core service demos
  hadoop_demo = bash_task(
      "hadoop_demo",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/hadoop/manage.sh; "
          "hadoop::ensure_running; "
          "bash /home/datalab/hadoop/scripts/hdfs_check.sh"
      ),
  )

  hive_demo_databases = bash_task(
      "hive_demo_databases",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/hadoop/manage.sh; "
          "source /home/datalab/app/tech/hive/manage.sh; "
          "hive::prepare_cli; "
          "HIVE_CLI_SKIP_RC=1 bash /home/datalab/app/tech/hive/cli.sh -e 'SHOW DATABASES;'; "
          "HIVE_CLI_SKIP_RC=1 bash /home/datalab/app/tech/hive/cli.sh -e 'CREATE DATABASE IF NOT EXISTS datalab_demo_validation;'"
      ),
  )

  spark_demo = bash_task(
      "spark_demo",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/hadoop/manage.sh; "
          "hadoop::ensure_running; "
          "spark-submit /home/datalab/spark/example_pyspark.py"
      ),
  )

  kafka_demo = bash_task(
      "kafka_demo",
      (
          "set -euo pipefail; "
          "bash /home/datalab/app/tech/kafka/manage.sh stop >/dev/null 2>&1 || true; "
          "bash /home/datalab/app/tech/kafka/manage.sh start >/dev/null 2>&1 || true; "
          "for i in $(seq 1 60); do "
          "  if /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then "
          "    break; "
          "  fi; "
          "  if [ \"$i\" -eq 60 ]; then "
          "    echo 'Kafka not ready, resetting local runtime metadata and retrying once...' >&2; "
          "    rm -rf /home/datalab/runtime/kafka/data/* /home/datalab/runtime/kafka/zookeeper-data/* 2>/dev/null || true; "
          "    bash /home/datalab/app/tech/kafka/manage.sh restart >/dev/null 2>&1 || true; "
          "    sleep 5; "
          "    /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1 || (echo 'Kafka broker still not ready after reset' >&2; exit 1); "
          "    break; "
          "  fi; "
          "  sleep 2; "
          "done; "
          "bash /home/datalab/kafka/health_check.sh || "
          "(echo '--- kafka.log tail ---'; tail -n 120 /home/datalab/runtime/kafka/logs/kafka.log 2>/dev/null || true; "
          "echo '--- zookeeper.log tail ---'; tail -n 80 /home/datalab/runtime/kafka/logs/zookeeper.log 2>/dev/null || true; exit 1)"
      ),
  )

  # Database stack demos and quick UI smoke checks
  postgres_demo = bash_task(
      "postgres_demo",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/postgres/manage.sh; "
          "postgres::start; "
          "export PGPASSWORD=admin; "
          "psql -h localhost -p 5432 -U admin -d datalab -f /home/datalab/postgres/example_postgres.sql"
      ),
  )

  mongodb_demo = bash_task(
      "mongodb_demo",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/mongodb/manage.sh; "
          "mkdir -p /home/datalab/runtime/mongodb/data /home/datalab/runtime/mongodb/logs /home/datalab/runtime/mongodb/pids; "
          "chmod -R u+rwX,go+rX /home/datalab/runtime/mongodb 2>/dev/null || true; "
          "mongodb::stop || true; "
          "rm -f /home/datalab/runtime/mongodb/pids/mongod.pid || true; "
          "rm -f /home/datalab/runtime/mongodb/data/mongod.lock /home/datalab/runtime/mongodb/data/WiredTiger.lock 2>/dev/null || true; "
          "mongodb::start || (echo '--- mongod.log tail ---'; tail -n 160 /home/datalab/runtime/mongodb/logs/mongod.log 2>/dev/null || true; exit 1); "
          "python /home/datalab/mongodb/example_mongodb.py"
      ),
  )

  redis_demo = bash_task(
      "redis_demo",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/redis/manage.sh; "
          "redis::start; "
          "python /home/datalab/redis/example_redis.py"
      ),
  )

  db_ui_smoke_check = bash_task(
      "db_ui_smoke_check",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/postgres/manage.sh; "
          "source /home/datalab/app/tech/mongodb/manage.sh; "
          "source /home/datalab/app/tech/redis/manage.sh; "
          "source /home/datalab/app/tech/pgadmin/manage.sh; "
          "postgres::start; "
          "mongodb::start; "
          "redis::start; "
          "pgadmin::start; "
          "for i in $(seq 1 30); do "
          "  if curl --connect-timeout 3 --max-time 10 -fsS http://localhost:8181/ >/dev/null; then "
          "    exit 0; "
          "  fi; "
          "  sleep 2; "
          "done; "
          "echo 'pgAdmin endpoint not ready after retries' >&2; exit 1"
      ),
  )

  # Additional language / tool demos (independent)
  python_example = bash_task(
      "python_example",
      "python /home/datalab/python/example.py",
  )

  java_example = bash_task(
      "java_example",
      (
          "set -euo pipefail; "
          "command -v javac >/dev/null; "
          "command -v java >/dev/null; "
          "mkdir -p /home/datalab/runtime/java; "
          "javac -d /home/datalab/runtime/java /home/datalab/java/Example.java; "
          "java -cp /home/datalab/runtime/java Example"
      ),
  )

  scala_example = bash_task(
      "scala_example",
      (
          "set -euo pipefail; "
          "command -v scalac >/dev/null; "
          "command -v scala >/dev/null; "
          "mkdir -p /home/datalab/runtime/scala; "
          "scalac -d /home/datalab/runtime/scala /home/datalab/scala/example.scala; "
          "scala -cp /home/datalab/runtime/scala HelloDataLab"
      ),
  )

  terraform_demo = bash_task(
      "terraform_demo",
      (
          "export TF_DATA_DIR=/home/datalab/runtime/terraform/.terraform && "
          "terraform -chdir=/home/datalab/terraform init && "
          "terraform -chdir=/home/datalab/terraform apply -auto-approve "
          "-state=/home/datalab/runtime/terraform/terraform.tfstate && "
          "terraform -chdir=/home/datalab/terraform destroy -auto-approve "
          "-state=/home/datalab/runtime/terraform/terraform.tfstate"
      ),
  )

  hudi_quickstart = bash_task(
      "hudi_quickstart",
      "python /home/datalab/lakehouse/hudi/hudi_example.py",
  )

  iceberg_quickstart = bash_task(
      "iceberg_quickstart",
      "python /home/datalab/lakehouse/iceberg/iceberg_example.py",
  )

  delta_quickstart = bash_task(
      "delta_quickstart",
      "python /home/datalab/lakehouse/delta/delta_example.py",
  )

  stop_core_services = bash_task(
      "stop_core_services",
      (
          "set -euo pipefail; "
          "source /home/datalab/app/tech/common.sh; "
          "source /home/datalab/app/tech/kafka/manage.sh; "
          "source /home/datalab/app/tech/hive/manage.sh; "
          "source /home/datalab/app/tech/spark/manage.sh; "
          "source /home/datalab/app/tech/hadoop/manage.sh; "
          "kafka::stop || true; "
          "hive::stop || true; "
          "spark::stop || true; "
          "hadoop::stop || true"
      ),
      trigger_rule="all_done",
  )

  # Dependencies:
  # start_core -> hadoop -> hive -> spark -> {kafka, hudi, iceberg, delta}
  # start_core -> independent language/tool demos
  # start_db -> {postgres, mongo, redis, db_ui_smoke_check}
  start_core_services >> hadoop_demo >> hive_demo_databases >> spark_demo
  spark_demo >> [kafka_demo, hudi_quickstart, iceberg_quickstart, delta_quickstart]

  start_core_services >> [python_example, java_example, scala_example, terraform_demo]
  start_core_services >> start_database_services
  start_database_services >> [postgres_demo, mongodb_demo, redis_demo]
  [postgres_demo, mongodb_demo, redis_demo] >> db_ui_smoke_check

  # Everything must finish before stopping core services
  all_tasks = [
      start_core_services,
      hadoop_demo,
      hive_demo_databases,
      spark_demo,
      kafka_demo,
      start_database_services,
      postgres_demo,
      mongodb_demo,
      redis_demo,
      db_ui_smoke_check,
      python_example,
      java_example,
      scala_example,
      terraform_demo,
      hudi_quickstart,
      iceberg_quickstart,
      delta_quickstart,
  ]
  for task in all_tasks:
    task >> stop_core_services
