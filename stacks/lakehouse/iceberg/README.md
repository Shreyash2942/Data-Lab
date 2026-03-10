# Iceberg Layer

The Iceberg quickstart shows how to write/query an Iceberg table using Spark + the Hadoop catalog. Source files live under `~/lakehouse/iceberg`, and the warehouse is `~/runtime/lakehouse/iceberg_warehouse`.

## Layout

| Path | Purpose |
| --- | --- |
| `lakehouse/iceberg/iceberg_example.py` | Builds a demo catalog/database/table and queries it. |
| `runtime/lakehouse/iceberg_warehouse` | Persistent warehouse for Iceberg data. |

## Running the demo

```bash
# via helper
bash ~/app/services_demo.sh --run-iceberg-demo    # option 13

# manual execution
python ~/lakehouse/iceberg/iceberg_example.py
```

Then explore the table from Spark SQL:

```bash
spark-sql -e "SELECT * FROM demo.db.sales"
```

## SQL Assets (for Airflow tasks)

- `stacks/lakehouse/iceberg/sql/01-create-schema-trino.sql`
- `stacks/lakehouse/iceberg/sql/02-create-table-trino.sql`

## Catalog setup (multi-language, multi-engine)

This stack currently uses an Iceberg Hadoop catalog rooted at:

- Warehouse: `~/runtime/lakehouse/iceberg_warehouse`
- Demo catalog name: `demo`

In Spark, this is configured with:

- `spark.sql.catalog.demo=org.apache.iceberg.spark.SparkCatalog`
- `spark.sql.catalog.demo.type=hadoop`
- `spark.sql.catalog.demo.warehouse=/home/datalab/runtime/lakehouse/iceberg_warehouse`

### Do I need to create database/table first?

- Namespace/database: yes, create it if missing (`CREATE NAMESPACE IF NOT EXISTS ...`).
- Table: no manual pre-create is needed if your job runs `CREATE TABLE ... USING iceberg`.

The demo script already does both.

Example:

```sql
CREATE NAMESPACE IF NOT EXISTS demo.db;
CREATE TABLE IF NOT EXISTS demo.db.sales (
  id INT,
  amount DOUBLE,
  day STRING
) USING iceberg;
```

### Spark languages (Python, Scala, Java)

The Iceberg catalog keys above are the same across Spark languages. Once configured:

- Create namespace/table via SQL.
- Write/read with SQL or DataFrame APIs against `demo.<namespace>.<table>`.

### Other engines

Iceberg tables can also be used from Flink/Trino/etc. by configuring those engines with a matching Iceberg catalog and warehouse. The table metadata/data layout stays the same; only engine-specific catalog config changes.

## Notes

- Ensure Spark is started (option 1/6 in `~/app/start`) before running the script so the warehouse directory exists.
- Remove `runtime/lakehouse/iceberg_warehouse` to reset the catalog.

## Resources

- Official docs: https://iceberg.apache.org/docs/latest/
