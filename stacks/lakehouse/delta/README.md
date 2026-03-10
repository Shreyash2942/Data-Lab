# Delta Lake Layer

The Delta quickstart exercises the bundled `delta-spark` runtime to create/query a Delta table. Scripts live under `~/lakehouse/delta`, while table storage sits in `~/runtime/lakehouse/delta_tables`.

## Layout

| Path | Purpose |
| --- | --- |
| `lakehouse/delta/delta_example.py` | Writes and reads a `customers` table via Spark. |
| `runtime/lakehouse/delta_tables` | Warehouse that stores Delta tables. |

## Running the demo

```bash
# helper menu (option 14)
bash ~/app/services_demo.sh --run-delta-demo

# or run manually (runs in local[*] mode and pulls delta-spark + delta-storage)
python ~/lakehouse/delta/delta_example.py
```

Inspect the table afterwards:

```bash
spark-sql -e "SELECT * FROM delta.\`~/runtime/lakehouse/delta_tables/customers\`"
# or in PySpark
python - <<'PY'
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("delta-check").getOrCreate()
spark.read.format("delta").load("~/runtime/lakehouse/delta_tables/customers").show()
PY
```

## SQL Assets (for Airflow tasks)

- `stacks/lakehouse/delta/sql/01-create-schema-trino.sql`
- `stacks/lakehouse/delta/sql/02-create-table-spark.sql`
- `stacks/lakehouse/delta/sql/03-register-table-trino.sql`

## Catalog + registration (multi-language, multi-engine)

Delta data files can be written directly by path, or registered as catalog tables.

Data Lab defaults:

- Storage path root: `~/runtime/lakehouse/delta_tables`
- Demo table path: `~/runtime/lakehouse/delta_tables/customers`
- Delta Spark runtime is bundled in this image.

### Do I need to create database/table first?

- Path-based Delta write (`.save(path)`): no database or table pre-creation required.
- Named table write (`saveAsTable` / `CREATE TABLE ... USING DELTA`):
  - Database/schema: create first if it does not exist.
  - Table: no pre-create needed if you use `CREATE TABLE IF NOT EXISTS ... USING DELTA LOCATION ...` or writer APIs that create it.

Example registration from Spark SQL:

```sql
CREATE DATABASE IF NOT EXISTS lakehouse;
CREATE TABLE IF NOT EXISTS lakehouse.customers
USING DELTA
LOCATION '/home/datalab/runtime/lakehouse/delta_tables/customers';
```

### Spark languages (Python, Scala, Java)

Delta format usage is the same across Spark languages:

- Write by path: `df.write.format("delta").mode("append").save(path)`
- Read by path: `spark.read.format("delta").load(path)`
- Register table: `CREATE TABLE ... USING DELTA LOCATION ...`

### Other engines

Delta can also be queried from engines like Flink/Trino, but those connectors/catalogs are not preconfigured in this repo. If you add one, keep the same Delta table path and configure that engine's catalog against it.

## Notes

- Spark should be running (option 1/6) so the session picks up the Delta jars already placed under `/opt/spark/jars`.
- Remove `runtime/lakehouse/delta_tables` if you want a clean run.

## Resources

- Official docs: https://docs.delta.io/latest/
