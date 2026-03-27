# dbt Layer

Project-level dbt files that run entirely inside the monolithic container. The dbt profile now includes three targets:

- `duckdb`: local default target for zero-setup development
- `hive`: dbt against HiveServer2, backed by HDFS + Hive metastore
- `spark_session`: dbt against the local Spark runtime, using Hive metastore + HDFS

## Layout

| Path | Purpose |
| --- | --- |
| `dbt/dbt_project.yml` | Core project definition (name, models path, configs). |
| `dbt/models/example_model.sql` | Starter model that materializes as a Hive table on the `hive` target and as a view elsewhere. Add your own models/tests here. |
| `dbt/profiles.yml` | Multi-target profile for `duckdb`, `hive`, and `spark_session`. |
| `dbt/logs/`, `dbt/target/` | Generated artifacts (ignored in git) from `dbt run`, `dbt test`, docs, etc. |

## Running dbt

1. Start the container (`docker compose up -d`) and open a shell: `docker compose exec data-lab bash`.
2. Switch to the non-root user so `$HOME` resolves to `/home/datalab`: `su - datalab`.
3. Change into the project directory.

```bash
cd ~/dbt
```

Run dbt commands individually as needed.

### DuckDB target

```bash
dbt debug              # verifies the DuckDB profile
```

```bash
dbt deps               # no packages yet, but safe to run
```

```bash
dbt run                # builds models (writes to ~/runtime/dbt/data_lab.duckdb)
```

```bash
dbt test               # executes tests in models/tests (add your own)
```

The helper menu also exposes option 3 (`bash ~/app/services_demo.sh --run-dbt-project`), which performs `dbt debug && dbt run` automatically. By default it uses the `duckdb` target. You can override the target with `DBT_TARGET`.

### Hive target

Start the required services first:

```bash
datalab_app --start-hadoop
datalab_app --start-hive
```

Then run dbt against Hive:

```bash
cd ~/dbt
dbt debug --target hive
dbt run --full-refresh --target hive
dbt test --target hive
```

This target connects to HiveServer2 over thrift/binary (`localhost:10000`) and stores managed tables in HDFS through the existing Hive metastore. In this container, HiveServer2 is started with `authentication=NONE` so the `dbt-hive` adapter can connect successfully.

### Spark target

Start the required services first:

```bash
datalab_app --start-hadoop
datalab_app --start-hive
datalab_app --start-spark
```

Then run dbt against Spark:

```bash
cd ~/dbt
dbt debug --target spark_session
dbt run --target spark_session
dbt test --target spark_session
```

This target uses `dbt-spark` in `session` mode. In this project, the dbt process creates a PySpark session that submits to the standalone Spark master at `spark://localhost:7077` while inheriting the Hive metastore + HDFS settings from the profile.

### Using the helper with non-default targets

```bash
DBT_TARGET=hive bash ~/app/services_demo.sh --run-dbt-project
DBT_TARGET=spark_session bash ~/app/services_demo.sh --run-dbt-project
```

### Running dbt from elsewhere

If you need to run dbt while working in a different folder (for example, from `~/app` or when scripting inside Airflow), point dbt at this project explicitly:

```bash
export DBT_PROFILES_DIR=~/dbt                # tells dbt where profiles.yml lives
dbt --project-dir ~/dbt run                  # builds models from another working dir
dbt --project-dir ~/dbt test                 # executes tests
dbt --project-dir ~/dbt run --target hive
dbt --project-dir ~/dbt run --target spark_session
```

You can also supply `--profiles-dir ~/dbt` inline if you do not want to export the variable.

## Notes

- Runtime state lives in `~/runtime/dbt`, which is bind-mounted from `runtime/dbt` in the repo. The `.gitkeep` file keeps the directory present so DuckDB can create `data_lab.duckdb`.
- Feel free to delete `runtime/dbt` to reset the DuckDB warehouse; dbt recreates it on the next `dbt run`.
- Add more models under `dbt/models`, plus tests in `dbt/tests` if desired; they will be picked up automatically by `dbt run`/`dbt test`.
- Hadoop/HDFS is not a direct dbt adapter target. It is the storage layer used under the `hive` and `spark_session` targets.
- The `hive` and `spark_session` targets both default to `threads: 2`, which is a conservative fit for the single-container runtime while still allowing DBT to schedule more than one model at a time when your project has parallelizable DAG branches.
- `spark_session` is the safest fit for this container today because it reuses the local Spark runtime directly and does not require a separate Spark Thrift server.
- The bundled Hive target runs on HiveServer2 with `hive.execution.engine=mr`, `mapreduce.framework.name=yarn`, and `hive.exec.parallel=true` so independent query stages can fan out on the single-node YARN runtime without changing the container topology.
- The sample model uses `table` materialization on the `hive` target because the bundled `dbt-hive` adapter is reliable for that path in this container, while the default view materialization can fail against vanilla HiveServer2.
- For repeatable demo runs on the `hive` target, prefer `dbt run --full-refresh --target hive`. The helper script already does this automatically when `DBT_TARGET=hive`.

## Resources

- Official docs: https://docs.getdbt.com/
