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

  # Core service demos
  hadoop_demo = bash_task(
      "hadoop_demo",
      "bash ~/hadoop/scripts/hdfs_check.sh",
  )

  hive_demo_databases = bash_task(
      "hive_demo_databases",
      "bash ~/hive/bootstrap_demo.sh",
  )

  spark_demo = bash_task(
      "spark_demo",
      "spark-submit ~/spark/example_pyspark.py",
  )

  kafka_demo = bash_task(
      "kafka_demo",
      "bash ~/kafka/demo.sh",
  )

  # Additional language / tool demos (independent)
  python_example = bash_task(
      "python_example",
      "python ~/python/example.py",
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
      trigger_rule="all_success",
  )

  # Dependencies:
  # start -> hadoop -> hive -> spark -> {kafka, hudi, iceberg, delta}
  # start -> independent language/tool demos
  start_core_services >> hadoop_demo >> hive_demo_databases >> spark_demo
  spark_demo >> [kafka_demo, hudi_quickstart, iceberg_quickstart, delta_quickstart]

  start_core_services >> [python_example, java_example, scala_example, terraform_demo]

  # Everything must finish before stopping core services
  all_tasks = [
      start_core_services,
      hadoop_demo,
      hive_demo_databases,
      spark_demo,
      kafka_demo,
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
