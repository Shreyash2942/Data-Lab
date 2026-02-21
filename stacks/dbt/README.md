# dbt Layer

Project-level dbt files that run entirely inside the monolithic container. A ready-to-use DuckDB profile lives in `dbt/profiles.yml`, pointing to `~/runtime/dbt/data_lab.duckdb`, so `dbt debug` works immediately without provisioning Postgres.

## Layout

| Path | Purpose |
| --- | --- |
| `dbt/dbt_project.yml` | Core project definition (name, models path, configs). |
| `dbt/models/example_model.sql` | Starter model that materializes a simple DuckDB view. Add your own models/tests here. |
| `dbt/profiles.yml` | DuckDB profile using the shared runtime folder (`~/runtime/dbt`). |
| `dbt/logs/`, `dbt/target/` | Generated artifacts (ignored in git) from `dbt run`, `dbt test`, docs, etc. |

## Running dbt

1. Start the container (`docker compose up -d`) and open a shell: `docker compose exec data-lab bash`.
2. Switch to the non-root user so `$HOME` resolves to `/home/datalab`: `su - datalab`.
3. Change into the project directory.

```bash
cd ~/dbt
```

Run dbt commands individually as needed:

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

The helper menu also exposes option 3 (`bash ~/app/services_demo.sh --run-dbt-project`), which performs `dbt debug && dbt run` automatically.

### Running dbt from elsewhere

If you need to run dbt while working in a different folder (for example, from `~/app` or when scripting inside Airflow), point dbt at this project explicitly:

```bash
export DBT_PROFILES_DIR=~/dbt                # tells dbt where profiles.yml lives
dbt --project-dir ~/dbt run                  # builds models from another working dir
dbt --project-dir ~/dbt test                 # executes tests
```

You can also supply `--profiles-dir ~/dbt` inline if you do not want to export the variable.

## Notes

- Runtime state lives in `~/runtime/dbt`, which is bind-mounted from `runtime/dbt` in the repo. The `.gitkeep` file keeps the directory present so DuckDB can create `data_lab.duckdb`.
- Feel free to delete `runtime/dbt` to reset the DuckDB warehouse; dbt recreates it on the next `dbt run`.
- Add more models under `dbt/models`, plus tests in `dbt/tests` if desired; they will be picked up automatically by `dbt run`/`dbt test`.

## Resources

- Official docs: https://docs.getdbt.com/
