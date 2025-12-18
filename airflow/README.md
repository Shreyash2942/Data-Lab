# Airflow Layer

All DAGs, plugins, and supporting files live under `~/airflow` inside the container (mirrors `repo_root/airflow`). Airflow 2.9 is preinstalled and configured for a local SQLite metadata database plus a filesystem executor for lightweight demos.

## Layout

| Path | Purpose |
| --- | --- |
| `airflow/dags/` | Place DAG files here; they sync to `~/airflow/dags`. |
| `airflow/plugins/` | Optional plugins/macros/components. |
| `~/runtime/airflow` | Metadata DB, logs, PID files (safe to delete to reset). |

## Starting Airflow

Use the helper to bring up the scheduler + webserver:

```bash
bash ~/app/start --start-airflow      # or choose option 5 from the menu
```

By default the web UI is available at http://localhost:8080 with credentials:

- Username: ```datalab```
- Password: ```airflow```

Stop services when finished:

```bash
bash ~/app/stop --stop-airflow
```

### DAG dependency map (`data_lab_stack_validation`)

- Serial core chain: `start_core_services -> hadoop_demo -> hive_demo_databases -> spark_demo -> {kafka_demo, hudi_quickstart, iceberg_quickstart, delta_quickstart}`
- Independent demos off start: `{python_example, java_example, scala_example, terraform_demo}`
- All flow into `stop_core_services` (trigger_rule=`all_success`)

## Common commands

```bash
airflow version
airflow dags list
airflow dags test example_dag 2024-01-01
```

You can also invoke option `8` in `~/app/services_demo.sh` (`--check-airflow`) for a quick version check.

## Notes

- Airflow uses the shared home directory, so switching users (`root` or `datalab`) still surfaces the same DAG folder.
- Delete `runtime/airflow` on the host if you need a clean metadata/logs reset; the helper recreates it on startup.

## Resources

- Official docs: https://airflow.apache.org/docs/
