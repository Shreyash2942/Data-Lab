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

## Notes

- Make sure Spark services are up (`bash ~/app/start` option 1 or 6) so the job can reuse the shared warehouse config.
- Output tables persist on the host; delete `runtime/lakehouse/hudi_tables` if you need a clean slate.

## Resources

- Official docs: https://hudi.apache.org/docs/
