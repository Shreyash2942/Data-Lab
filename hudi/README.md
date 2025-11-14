# Hudi Tables

The Hudi demo writes to `~/hudi_tables` inside the container. Use option **12** in `~/app/services_demo.sh` (or run the script manually):

```bash
cd ~/app
bash services_demo.sh             # choose option 12
# or run directly
python ~/spark/hudi_example.py
```

This populates `~/hudi_tables/users` and reads it back via Spark.

Files in `~/hudi_tables` are bind-mounted to `repo_root/hudi_tables`, so data survives container restarts. Clean it by deleting that directory on the host.
