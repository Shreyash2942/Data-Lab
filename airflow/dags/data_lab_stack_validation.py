from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator

class DataLabBashOperator(BashOperator):
  # Disable file-based templating so bash_command strings aren't treated as template file paths.
  template_ext = ()


def bash_task(task_id: str, command: str, **kwargs) -> BashOperator:
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
      "bash ~/app/start --start-core",
  )

  python_example = bash_task(
      "python_example",
      "python ~/python/example.py",
  )

  spark_example = bash_task(
      "spark_example",
      "spark-submit ~/spark/example_pyspark.py",
  )

  dbt_run = bash_task(
      "dbt_run",
      "cd ~/dbt && dbt debug && dbt run",
  )

  hadoop_hdfs_check = bash_task(
      "hadoop_hdfs_check",
      "bash ~/hadoop/scripts/hdfs_check.sh",
  )

  hive_demo_databases = bash_task(
      "hive_demo_databases",
      "bash ~/hive/bootstrap_demo.sh",
  )

  kafka_demo = bash_task(
      "kafka_demo",
      "bash ~/kafka/demo.sh",
  )

  java_example = bash_task(
      "java_example",
      "cd ~/java && javac Example.java && java -cp ~/java Example",
  )

  scala_example = bash_task(
      "scala_example",
      "cd ~/scala && scalac example.scala && scala -cp ~/scala HelloDataLab",
  )

  terraform_demo = bash_task(
      "terraform_demo",
      (
          "export TF_DATA_DIR=~/runtime/terraform/.terraform && "
          "terraform -chdir=~/terraform init && "
          "terraform -chdir=~/terraform apply -auto-approve "
          "-state=~/runtime/terraform/terraform.tfstate && "
          "terraform -chdir=~/terraform destroy -auto-approve "
          "-state=~/runtime/terraform/terraform.tfstate"
      ),
  )

  hudi_quickstart = bash_task(
      "hudi_quickstart",
      "python ~/hudi/hudi_example.py",
  )

  iceberg_quickstart = bash_task(
      "iceberg_quickstart",
      "python ~/iceberg/iceberg_example.py",
  )

  delta_quickstart = bash_task(
      "delta_quickstart",
      "python ~/delta/delta_example.py",
  )

  stop_core_services = bash_task(
      "stop_core_services",
      "bash ~/app/stop --stop-core",
      trigger_rule="all_done",
  )

  validation_tasks = [
      python_example,
      spark_example,
      dbt_run,
      hadoop_hdfs_check,
      hive_demo_databases,
      kafka_demo,
      java_example,
      scala_example,
      terraform_demo,
      hudi_quickstart,
      iceberg_quickstart,
      delta_quickstart,
  ]

  start_core_services >> validation_tasks
  for task in validation_tasks:
    task >> stop_core_services
