# Iceberg Tables

Option **13** in `~/app/services_demo.sh` runs `spark/iceberg_example.py`, which uses a Hadoop catalog rooted at `~/iceberg_warehouse`. Those files map to `repo_root/iceberg_warehouse` on the host, so they persist. You can also trigger it manually:

```bash
cd ~/app
bash services_demo.sh   # option 13
# or run directly
python ~/spark/iceberg_example.py
```

Use `spark.sql("SELECT * FROM demo.db.sales").show()` inside the script (or a Spark shell) to inspect the generated table.
