# Airflow Layer

All DAGs, plugins, and supporting files live under `~/airflow` inside the container (mirrors `repo_root/stacks/airflow`). Airflow 2.9 is preinstalled and configured to use PostgreSQL metadata (`datalab` DB) with `LocalExecutor` for parallel task execution in this single-container environment.

## Layout

| Path | Purpose |
| --- | --- |
| `stacks/airflow/dags/` | Place DAG files here; they sync to `~/airflow/dags`. |
| `stacks/airflow/plugins/` | Optional plugins/macros/components. |
| `~/runtime/airflow` | Metadata DB, logs, PID files (safe to delete to reset). |

## Starting Airflow

Use the helper to bring up the scheduler + webserver:

```bash
bash ~/app/start --start-airflow      # or choose option 5 from the menu
```

By default the web UI is available at http://localhost:8080 with credentials:

- Username: container name (for example `datalab`, `datalab-copy1`)
- Password: `admin`

When you run `datalab_app --start-airflow`, startup output prints the exact Airflow login credentials and URL.

Stop services when finished:

```bash
bash ~/app/stop --stop-airflow
```

### Validate all stacks with one command

After creating a new container, run the built-in validation DAG end-to-end:

```bash
datalab_app --validate-stack
```

This starts Airflow if needed and runs:

- DAG: `data_lab_stack_validation`
- Command used: `airflow dags test data_lab_stack_validation <today>`

You can also run the same action from `datalab_app` start menu option `12`.

### DAG dependency map (`data_lab_stack_validation`)

- Serial core chain: `start_core_services -> hadoop_demo -> hive_demo_databases -> spark_demo -> {kafka_demo, hudi_quickstart, iceberg_quickstart, delta_quickstart}`
- Independent demos off start: `{python_example, java_example, scala_example, terraform_demo}`
- Database validation branch: `start_database_services -> {postgres_demo, mongodb_demo, redis_demo, db_ui_smoke_check}`
- All flow into `stop_core_services` (trigger_rule=`all_success`)

## Common commands

```bash
airflow version
airflow dags list
airflow dags test example_dag 2024-01-01
```

You can also invoke option `8` in `~/app/services_demo.sh` (`--check-airflow`) for a quick version check.

## Parallelism and Spark queue behavior

Default Airflow runtime settings in this project:

- `executor=LocalExecutor`
- `parallelism=16` (global task slots)
- `max_active_tasks_per_dag=8`
- `max_active_runs_per_dag=4`

When Airflow tasks submit Spark jobs, Airflow concurrency and Spark cluster capacity are separate limits:

- Airflow can mark tasks as `running` up to its configured slots.
- Spark may run fewer jobs immediately and queue the rest based on available worker resources.

Example with 12 Spark tasks in one DAG (current defaults):

- Airflow can run 8 tasks from that DAG at once.
- Spark worker (2 cores) with `spark.cores.max=1` can execute about 2 Spark apps at once.
- Remaining submitted Spark apps wait in Spark queue even though their Airflow tasks are already `running`.
- Remaining DAG tasks stay `queued` in Airflow until DAG slots free up.

## Notes

- Airflow uses the shared home directory, so switching users (`root` or `datalab`) still surfaces the same DAG folder.
- Delete `datalabcontainer/runtime/airflow` on the host if you need a clean metadata/logs reset; the helper recreates it on startup.

## Resources

- Official docs: https://airflow.apache.org/docs/
