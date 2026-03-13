# Spark Layer

Spark 3.5.1 (with Hadoop 3) is preinstalled at `/opt/spark` and exposed through the helper scripts. Project-level samples live under `~/spark`, mirrored from `repo_root/spark`.

## Layout

| Path | Purpose |
| --- | --- |
| `spark/example_pyspark.py` | PySpark job that inspects the Spark session and performs a simple word count. |
| `~/app/bin/spark-submit` | Wrapper that injects log settings and ensures Spark sees the right config. |

## Starting services

Launch Spark daemons (master, worker, history server) via the orchestrator:

```bash
bash ~/app/start                    # option 1 starts Spark (option 6 starts Spark/Hadoop/Hive/Kafka)
bash ~/app/stop --stop-spark        # stop Spark-only services
```

The Spark master UI listens on http://localhost:9090 and the history server on http://localhost:18080.

## Running jobs

By default, `~/app/bin/spark-submit` targets the Spark standalone master (`spark://localhost:7077`) when `--master` is not supplied. It also applies a conservative per-application core cap (`spark.cores.max=1`) so multiple jobs can run in parallel on the same worker.

Current single-container defaults that impact parallel jobs:

- Spark worker cores: `2`
- Spark worker memory: `2g`
- Per app cap from wrapper: `spark.cores.max=1`
- Scheduler mode from wrapper/defaults: `FAIR`

With these defaults, Spark usually executes about 2 apps at once and queues the rest.

Example: if Airflow triggers 12 Spark tasks in parallel, Spark runs about 2 immediately and keeps 10 waiting in queue until resources free up.

Execute the bundled example:

```bash
cd ~/spark
python example_pyspark.py
# or explicitly
spark-submit example_pyspark.py
```

From elsewhere:

```bash
spark-submit ~/spark/example_pyspark.py
```

Override defaults when needed:

```bash
# Force local mode for quick debugging
spark-submit --master local[*] ~/spark/example_pyspark.py

# Increase per-app core cap for heavier single jobs
DATALAB_SPARK_APP_MAX_CORES=2 spark-submit ~/spark/example_pyspark.py
```

Menu shortcut: `bash ~/app/services_demo.sh --run-spark-example` (option `2`).

## Logging defaults

Every `spark-submit` call picks up `~/runtime/spark/conf/log4j2.properties`, which pins the root logger (and `org.apache.spark`) to `WARN` and suppresses noisy Hadoop classes such as `NativeCodeLoader`. Edit or replace that file if you prefer different log levels. Event logs land in `~/runtime/spark/events`, and the warehouse lives under `~/runtime/spark/warehouse`.

## Resources

- Official docs: https://spark.apache.org/docs/latest/
