# Delta Lake Layer

The Delta quickstart exercises the bundled `delta-spark` runtime to create/query a Delta table. Scripts live under `~/delta`, while table storage sits in `~/runtime/lakehouse/delta_tables`.

## Layout

| Path | Purpose |
| --- | --- |
| `delta/delta_example.py` | Writes and reads a `customers` table via Spark. |
| `runtime/lakehouse/delta_tables` | Warehouse that stores Delta tables. |

## Running the demo

```bash
# helper menu (option 14)
bash ~/app/services_demo.sh --run-delta-demo

# or run manually (runs in local[*] mode and pulls delta-spark + delta-storage)
python ~/delta/delta_example.py
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

## Notes

- Spark should be running (option 1/6) so the session picks up the Delta jars already placed under `/opt/spark/jars`.
- Remove `runtime/lakehouse/delta_tables` if you want a clean run.

## Resources

- Official docs: https://docs.delta.io/latest/
