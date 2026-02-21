# Iceberg Layer

The Iceberg quickstart shows how to write/query an Iceberg table using Spark + the Hadoop catalog. Source files live under `~/iceberg`, and the warehouse is `~/runtime/lakehouse/iceberg_warehouse`.

## Layout

| Path | Purpose |
| --- | --- |
| `iceberg/iceberg_example.py` | Builds a demo catalog/database/table and queries it. |
| `runtime/lakehouse/iceberg_warehouse` | Persistent warehouse for Iceberg data. |

## Running the demo

```bash
# via helper
bash ~/app/services_demo.sh --run-iceberg-demo    # option 13

# manual execution
python ~/iceberg/iceberg_example.py
```

Then explore the table from Spark SQL:

```bash
spark-sql -e "SELECT * FROM demo.db.sales"
```

## Notes

- Ensure Spark is started (option 1/6 in `~/app/start`) before running the script so the warehouse directory exists.
- Remove `runtime/lakehouse/iceberg_warehouse` to reset the catalog.

## Resources

- Official docs: https://iceberg.apache.org/docs/latest/
