# Data Lab Config

`datalab_config` is the runtime tuning command for Data Lab.

It lives separately from `datalab_app` so service orchestration and runtime
configuration stay distinct.

Profile intent:

- `conservative`: lower concurrency, more headroom for the rest of the stack
- `balanced`: moderate Spark growth without pushing the container too hard
- `aggressive`: Spark-heavy tuning that targets about 60% of effective CPU for the Spark worker

Guardrail:

- Runtime loading clamps `SPARK_WORKER_CORES` to 60% of effective container CPU.
- If a user manually edits `/home/datalab/runtime/config/datalab-overrides.env`
  above that limit, the service startup path will clamp it back down.
- `datalab_config show` and `datalab_config recommend` print the current Spark
  worker core ceiling so users can see the maximum allowed value directly.
- New containers bootstrap a one-time starter override that targets about 20%
  of effective CPU for compute services. Users can increase it later with
  `datalab_config apply balanced|aggressive compute`.

Inside the container:

```bash
datalab_config show
datalab_config show compute
datalab_config show system
datalab_config detect
datalab_config recommend aggressive compute
datalab_config diff balanced compute
datalab_config apply balanced compute
datalab_config reset compute
```

Runtime overrides are stored in:

```text
/home/datalab/runtime/config/datalab-overrides.env
```

Managed settings in the first phase under the `compute` category:

- `SPARK_WORKER_CORES`
- `SPARK_WORKER_MEMORY`
- `DATALAB_SPARK_APP_MAX_CORES`
- `DBT_SPARK_THREADS`
- `DBT_HIVE_THREADS`
- `HIVE_EXEC_PARALLEL`
- `HIVE_EXEC_PARALLEL_THREAD_NUMBER`
- `AIRFLOW__CORE__PARALLELISM`
- `AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG`
- `AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG`
