from datetime import datetime, timedelta
from textwrap import dedent

from airflow import DAG
from airflow.operators.bash import BashOperator


class DataLabBashOperator(BashOperator):
  # Disable file-based templating so bash_command strings aren't treated as
  # template file paths.
  template_ext = ()


def script(command: str) -> str:
  return dedent(command).strip()


def bash_task(task_id: str, command: str, **kwargs) -> BashOperator:
  # Validation should fail fast rather than retrying for a long time.
  kwargs.setdefault("execution_timeout", timedelta(minutes=20))
  kwargs.setdefault("retries", 0)
  return DataLabBashOperator(
      task_id=task_id,
      bash_command=script(command),
      do_xcom_push=False,
      **kwargs,
  )


with DAG(
    dag_id="data_lab_stack_validation",
    description="Runs a fast end-to-end smoke validation for the full Data Lab container.",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

  preflight_checks = bash_task(
      "preflight_checks",
      """
      set -euo pipefail
      DATALAB_CHECK_FAST=1 bash /home/datalab/app/datalab-check
      """,
      execution_timeout=timedelta(minutes=10),
  )

  database_stack_health = bash_task(
      "database_stack_health",
      """
      set -euo pipefail
      check_http_ready() {
        local url="$1"
        local deadline=$((SECONDS + 45))
        local code=""
        while [[ ${SECONDS} -lt ${deadline} ]]; do
          code="$(curl -sS -o /dev/null -w '%{http_code}' "${url}" || true)"
          case "${code}" in
            200|301|302|303|307|308|401)
              return 0
              ;;
          esac
          sleep 1
        done
        echo "[!] URL did not become ready: ${url} (last status: ${code:-none})" >&2
        return 1
      }

      source /home/datalab/app/tech/common.sh
      source /home/datalab/app/tech/postgres/manage.sh
      source /home/datalab/app/tech/mongodb/manage.sh
      source /home/datalab/app/tech/redis/manage.sh
      source /home/datalab/app/tech/dbui/manage.sh
      source /home/datalab/app/tech/pgadmin/manage.sh

      postgres::start
      mongodb::start
      redis::start
      dbui::start
      pgadmin::start

      export PGPASSWORD=admin
      psql -h localhost -p 5432 -U admin -d datalab -Atc "select 1" | grep -qx "1"

      python3 - <<'PY'
      from pymongo import MongoClient
      client = MongoClient(
          "mongodb://admin:admin@127.0.0.1:27017/admin?authSource=admin",
          serverSelectionTimeoutMS=5000,
      )
      client.admin.command("ping")
      PY

      redis-cli -a "${REDIS_PASSWORD:-admin}" ping | grep -q "PONG"
      check_http_ready "http://127.0.0.1:${PGADMIN_PORT:-8181}/"
      check_http_ready "http://127.0.0.1:${MONGO_EXPRESS_PORT:-8083}/"
      check_http_ready "http://127.0.0.1:${REDIS_COMMANDER_PORT:-8084}/"
      """,
  )

  etl_stack_health = bash_task(
      "etl_stack_health",
      """
      set -euo pipefail
      source /home/datalab/app/tech/common.sh
      source /home/datalab/app/tech/hadoop/manage.sh
      source /home/datalab/app/tech/hive/manage.sh
      source /home/datalab/app/tech/spark/manage.sh
      source /home/datalab/app/tech/kafka/manage.sh
      source /home/datalab/app/tech/schema_registry/manage.sh
      source /home/datalab/app/tech/kafka_connect/manage.sh
      source /home/datalab/app/tech/cdc/manage.sh
      source /home/datalab/app/tech/lineage/manage.sh

      wait_for_hdfs_cli() {
        local deadline=$((SECONDS + 90))
        while [[ ${SECONDS} -lt ${deadline} ]]; do
          if timeout 15 hdfs dfs -ls / >/dev/null 2>&1; then
            return 0
          fi
          sleep 2
        done
        echo "[!] HDFS CLI did not become ready in time." >&2
        return 1
      }

      hadoop::ensure_running
      wait_for_hdfs_cli
      VALIDATION_HDFS_FILE="/tmp/datalab_validation_hdfs.txt"
      printf 'ok\n' > "${VALIDATION_HDFS_FILE}"
      timeout 20 hdfs dfs -mkdir -p /tmp/data-lab-validation
      timeout 20 hdfs dfs -put -f "${VALIDATION_HDFS_FILE}" /tmp/data-lab-validation/airflow_smoke.txt
      timeout 20 bash -lc "hdfs dfs -cat /tmp/data-lab-validation/airflow_smoke.txt | grep -qx 'ok'"
      timeout 20 hdfs dfs -rm -f /tmp/data-lab-validation/airflow_smoke.txt >/dev/null

      hive::prepare_cli
      HIVE_CLI_SKIP_RC=1 bash /home/datalab/app/tech/hive/cli.sh -e 'SHOW DATABASES;' >/dev/null

      spark::ensure_running
      VALIDATION_JOB_FILE="/tmp/datalab_validation_job_name"
      VALIDATION_JOB_NAME="datalab_validation_quick_$(date +%s)"
      printf '%s' "${VALIDATION_JOB_NAME}" > "${VALIDATION_JOB_FILE}"
      export VALIDATION_JOB_NAME
      lineage::start_api
      rm -rf /home/datalab/runtime/validation/spark_lineage
      cat >/tmp/datalab_validation_spark.py <<'PY'
      import sys
      from pathlib import Path
      from pyspark.sql import SparkSession
      from pyspark.sql import functions as F

      app_name = sys.argv[1] if len(sys.argv) > 1 else "datalab_validation_quick"
      base = Path("/home/datalab/runtime/validation/spark_lineage")
      source = str(base / "source")
      target = str(base / "target")
      base.mkdir(parents=True, exist_ok=True)
      spark = SparkSession.builder.appName(app_name).getOrCreate()
      source_df = spark.range(5).withColumn("bucket", (F.col("id") % 2).cast("int"))
      source_df.write.mode("overwrite").parquet(source)
      result_df = spark.read.parquet(source).filter(F.col("id") >= 2)
      result_df.write.mode("overwrite").parquet(target)
      count = result_df.count()
      if count != 3:
          raise SystemExit(f"Unexpected Spark count: {count}")
      spark.stop()
      PY
      export DATALAB_OPENLINEAGE_ENABLED=1
      bash /home/datalab/app/bin/spark-submit \
        --conf spark.ui.enabled=false \
        --conf spark.sql.shuffle.partitions=1 \
        /tmp/datalab_validation_spark.py "${VALIDATION_JOB_NAME}"
      deadline=$((SECONDS + 20))
      found=0
      while [[ ${SECONDS} -lt ${deadline} ]]; do
        if curl -fsS "http://127.0.0.1:${MARQUEZ_API_PORT:-5000}/api/v1/namespaces/datalab/jobs" | \
          python3 -c 'import json, os, sys; payload = json.load(sys.stdin); target = os.environ["VALIDATION_JOB_NAME"]; raise SystemExit(0 if any(job.get("name") == target for job in payload.get("jobs", [])) else 1)'; then
          found=1
          break
        fi
        sleep 1
      done
      if [[ "${found}" -ne 1 ]]; then
        echo "[!] Validation Spark job ${VALIDATION_JOB_NAME} did not appear in Marquez." >&2
        exit 1
      fi
      unset DATALAB_OPENLINEAGE_ENABLED

      kafka::start
      /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null

      schema_registry::start
      curl -fsS "http://127.0.0.1:${SCHEMA_REGISTRY_PORT:-8085}/apis/registry/v3/system/info" >/dev/null

      kafka_connect::start
      curl -fsS "http://127.0.0.1:${KAFKA_CONNECT_PORT:-8086}/connector-plugins" | grep -q 'PostgresConnector'

      cdc::wait_for_plugin
      cdc::registry_converter_ready
      """,
      execution_timeout=timedelta(minutes=25),
  )

  lakehouse_stack_health = bash_task(
      "lakehouse_stack_health",
      """
      set -euo pipefail
      source /home/datalab/app/tech/common.sh
      source /home/datalab/app/tech/hadoop/manage.sh
      source /home/datalab/app/tech/hive/manage.sh
      source /home/datalab/app/tech/minio/manage.sh
      source /home/datalab/app/tech/trino/manage.sh
      source /home/datalab/app/tech/superset/manage.sh

      hadoop::ensure_running
      hive::start_metastore
      minio::start
      curl -fsS "http://127.0.0.1:${MINIO_API_PORT:-9004}/minio/health/live" >/dev/null

      trino::start
      trino::cli_exec "SELECT 1"

      superset::start
      curl -fsSL "http://127.0.0.1:${SUPERSET_PORT:-8090}/login/" >/dev/null
      """,
  )

  quality_stack_health = bash_task(
      "quality_stack_health",
      """
      set -euo pipefail
      source /home/datalab/app/tech/common.sh
      source /home/datalab/app/tech/great_expectations/manage.sh
      source /home/datalab/app/tech/jupyter/manage.sh

      gx::start
      python3 - <<'PY'
      import json
      from pathlib import Path

      result_path = Path("/home/datalab/runtime/great_expectations/last_validation.json")
      payload = json.loads(result_path.read_text(encoding="utf-8"))
      if payload.get("success") is not True:
          raise SystemExit("Great Expectations validation did not succeed")
      docs_site_dir = payload.get("docs_site_dir")
      if not docs_site_dir or not Path(docs_site_dir).exists():
          raise SystemExit("Great Expectations docs site directory is missing")
      PY
      curl -fsSL "http://127.0.0.1:${GX_DOCS_PORT:-8891}/" >/dev/null

      jupyter::start
      curl -fsSL "http://127.0.0.1:${JUPYTER_PORT:-8888}/lab?token=${JUPYTER_TOKEN:-datalab}" >/dev/null
      """,
  )

  observability_stack_health = bash_task(
      "observability_stack_health",
      """
      set -euo pipefail
      source /home/datalab/app/tech/common.sh
      source /home/datalab/app/tech/lineage/manage.sh
      source /home/datalab/app/tech/monitoring/manage.sh

      lineage::start
      curl -fsS "http://127.0.0.1:${MARQUEZ_API_PORT:-5000}/api/v1/namespaces" >/dev/null

      monitoring::start
      curl -fsS "http://127.0.0.1:${PROMETHEUS_PORT:-9095}/-/healthy" >/dev/null
      curl -fsS "http://127.0.0.1:${GRAFANA_PORT:-3001}/api/health" >/dev/null
      """,
      execution_timeout=timedelta(minutes=25),
  )

  ui_services_dynamic_port_mapping = bash_task(
      "ui_services_dynamic_port_mapping",
      """
      set -euo pipefail
      export DATALAB_UI_HOST=copyhost
      export DATALAB_HOST_PORT_MAP='8080=18080,7077=17077,8083=18083,8084=18084,8085=18085,8086=18086,8090=18090,8091=18091,8888=18888,8891=18891,9004=19004,9005=19005,9083=19083,9092=19092,9095=19095,5000=15000,3000=13000,3001=13001,5432=15432,6379=16379,27017=17017'
      bash /home/datalab/app/ui_services --json | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
expected = {
    ("schema_registry", "api"): "http://copyhost:18085/apis/registry/v3",
    ("kafka_connect", "api"): "http://copyhost:18086/connectors",
    ("jupyterlab", "url"): "http://copyhost:18888/lab?token=datalab",
    ("great_expectations", "data_docs"): "http://copyhost:18891/",
    ("marquez", "api"): "http://copyhost:15000/api/v1/namespaces",
    ("marquez", "ui"): "http://copyhost:13000/",
    ("prometheus", "url"): "http://copyhost:19095/",
    ("grafana", "url"): "http://copyhost:13001/",
    ("postgresql", "outside"): "postgresql://copyhost:15432",
    ("mongodb", "outside"): "mongodb://copyhost:17017",
    ("redis", "outside"): "redis://copyhost:16379",
    ("trino", "http"): "http://copyhost:18091",
    ("superset", "url"): "http://copyhost:18090",
    ("minio", "api"): "http://copyhost:19004",
    ("minio", "console"): "http://copyhost:19005",
    ("hive_metastore_external", "endpoint"): "thrift://copyhost:19083",
}

for path, value in expected.items():
    current = payload
    for key in path:
        current = current[key]
    if current != value:
        raise SystemExit(
            "Unexpected mapped value for {}: {!r} != {!r}".format(
                ".".join(path), current, value
            )
        )
'
      """,
      execution_timeout=timedelta(minutes=10),
  )

  cleanup_validation_artifacts = bash_task(
      "cleanup_validation_artifacts",
      """
      set -euo pipefail
      rm -f /tmp/datalab_validation_spark.py >/dev/null 2>&1 || true
      rm -f /tmp/datalab_validation_hdfs.txt >/dev/null 2>&1 || true
      rm -f /tmp/datalab_validation_job_name >/dev/null 2>&1 || true
      rm -rf /home/datalab/runtime/validation/spark_lineage >/dev/null 2>&1 || true
      echo "Validation-only temporary artifacts cleaned."
      """,
      trigger_rule="all_done",
      execution_timeout=timedelta(minutes=10),
  )

  (
      preflight_checks
      >> database_stack_health
      >> etl_stack_health
      >> lakehouse_stack_health
      >> quality_stack_health
      >> observability_stack_health
      >> ui_services_dynamic_port_mapping
      >> cleanup_validation_artifacts
  )
