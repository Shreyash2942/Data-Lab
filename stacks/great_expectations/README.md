# Great Expectations Stack

This stack documents the embedded Great Expectations workflow used for data-quality checks.

## Runtime Management

- Service module: `datalabcontainer/app/tech/great_expectations/`
- Start Data Docs: `datalab_app --start-great-expectations`
- Run demo validation: `datalab_app --run-great-expectations-demo`

## Endpoints

- Inside container: `http://localhost:8891/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Root: `~/runtime/great_expectations/`
- Latest result: `~/runtime/great_expectations/last_validation.json`

## Why This Stack Exists

- Add a formal data-quality layer before or after Spark, dbt, and CDC pipelines.
- Catch schema drift, null spikes, bad ranges, and row-level surprises early.
- Produce validation output that can be reviewed by the team.

## Common Use Cases

- Validate bronze or silver datasets before downstream jobs run.
- Add quality gates inside Airflow DAGs.
- Generate Data Docs for a quick human-readable validation summary.

## How To Use In Data Lab

Run the built-in demo validation:

```bash
datalab_app --run-great-expectations-demo
```

Start Data Docs:

```bash
datalab_app --start-great-expectations
```

Check the latest validation output:

```bash
cat ~/runtime/great_expectations/last_validation.json
```

## Notes

- Great Expectations is optional and fits the same monolithic topology.
- Validation outputs are designed to stay inside runtime storage.
