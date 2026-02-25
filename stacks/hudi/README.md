# Hudi Layer

The Hudi quickstart demonstrates writing/reading Hudi tables via Spark. Source files live under `~/hudi`, and output tables land in `~/runtime/lakehouse/hudi_tables` (mirrored to `repo_root/runtime/lakehouse/hudi_tables` on the host).

## Layout

| Path | Purpose |
| --- | --- |
| `hudi/hudi_example.py` | Creates the `users` table, runs upserts, and prints the result. |
| `runtime/lakehouse/hudi_tables` | Warehouse that stores Hudi table data. Delete it to reset. |

## Running the demo

```bash
# menu helper
bash ~/app/services_demo.sh --run-hudi-demo     # option 12

# or run directly
python ~/hudi/hudi_example.py
```

After completion, inspect the tables from Spark:

```bash
spark-sql -e "SELECT * FROM hudi_users"
```

## Hive sync (multi-language, multi-engine)

This environment supports writing Hudi data and syncing table metadata to Hive.

Data Lab defaults:

- HiveServer2 HTTP JDBC URL: `jdbc:hive2://localhost:10001/default;transportMode=http;httpPath=cliservice;auth=noSasl`
- HiveServer2 binary JDBC URL (optional): `jdbc:hive2://localhost:10000/default`
- Username: `datalab`
- Password: empty
- Recommended table type for immediate Hive query visibility: `COPY_ON_WRITE`

Before syncing, start core services:

```bash
bash ~/app/start    # option 6 (core stack)
# or
bash ~/app/scripts/hive/hs2.sh start
```

### Spark (PySpark, Scala, Java)

For Spark jobs, use Hudi Spark sync keys:

```python
hudi_options = {
  "hoodie.table.name": "users_hudi",
  "hoodie.datasource.write.recordkey.field": "id",
  "hoodie.datasource.write.precombine.field": "ts",
  "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
  "hoodie.datasource.hive_sync.enable": "true",
  "hoodie.datasource.hive_sync.mode": "jdbc",
  "hoodie.datasource.hive_sync.jdbcurl": "jdbc:hive2://localhost:10001/default;transportMode=http;httpPath=cliservice;auth=noSasl",
  "hoodie.datasource.hive_sync.database": "default",
  "hoodie.datasource.hive_sync.table": "users_hudi",
  "hoodie.datasource.hive_sync.username": "datalab",
  "hoodie.datasource.hive_sync.password": ""
}
```

These option names are the same for Spark in Python/Scala/Java DataFrame writes.

### Flink SQL

For Flink SQL connector DDL, use Flink-style keys:

```sql
WITH (
  'connector' = 'hudi',
  'path' = '/home/datalab/runtime/lakehouse/hudi_tables/users_hudi',
  'table.type' = 'COPY_ON_WRITE',
  'hive_sync.enable' = 'true',
  'hive_sync.mode' = 'jdbc',
  'hive_sync.jdbc_url' = 'jdbc:hive2://localhost:10001/default;transportMode=http;httpPath=cliservice;auth=noSasl',
  'hive_sync.table' = 'users_hudi',
  'hive_sync.db' = 'default',
  'hive_sync.username' = 'datalab',
  'hive_sync.password' = ''
);
```

Note: `hive_sync.metastore.uris` is used for metastore-based sync modes. In this Data Lab setup, JDBC sync is the direct path to HiveServer2.

## Notes

- Make sure Spark services are up (`bash ~/app/start` option 1 or 6) so the job can reuse the shared warehouse config.
- Output tables persist on the host; delete `runtime/lakehouse/hudi_tables` if you need a clean slate.

## Resources

- Official docs: https://hudi.apache.org/docs/
