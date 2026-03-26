# Airflow Layer

All DAGs, plugins, and supporting files live under `~/airflow` inside the container (mirrors `repo_root/stacks/airflow`). Airflow 2.9 is preinstalled and configured to use PostgreSQL metadata (`datalab` DB) with `LocalExecutor` for parallel task execution in this single-container environment. This project does not use a SQLite fallback for Airflow.

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

Validation cleanup removes only temporary CDC demo artifacts. It does not shut down your running services after the DAG finishes.

You can also run the same action from `datalab_app` start menu option `12`.

### DAG dependency map (`data_lab_stack_validation`)

- Fast chain: `preflight_checks -> database_stack_health -> etl_stack_health -> lakehouse_stack_health -> quality_stack_health -> observability_stack_health -> ui_services_dynamic_port_mapping -> cleanup_validation_artifacts`
- Cleanup task uses `trigger_rule=all_done`

The validation DAG is optimized for a fast smoke pass, not a full demo marathon. It checks:

- Database stack: PostgreSQL, MongoDB, Redis, pgAdmin, Mongo Express, Redis Commander
- ETL stack: Hadoop, Hive, Spark, Kafka, Schema Registry, Kafka Connect, CDC plugin/converter readiness
- Lakehouse stack: MinIO, Trino, Superset
- Quality/dev stack: Great Expectations, JupyterLab
- Observability stack: Marquez/OpenLineage, Prometheus, Grafana
- Copied-container URL rendering: `ui_services --json` dynamic port mapping logic

Longer lakehouse demo jobs and optional sample workflows remain available through their dedicated helpers; they are intentionally not part of the default validation DAG so `datalab_app --validate-stack` finishes quickly.

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
- Metadata backend: PostgreSQL only

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
