# Delta Tables

Option **14** in `~/app/services_demo.sh` runs `spark/delta_example.py`, creating a Delta table at `~/delta_tables/customers`. Those files live at `repo_root/delta_tables` on the host. You can also run it by hand:

```bash
cd ~/app
bash services_demo.sh   # option 14
# or
python ~/spark/delta_example.py
```

Inspect the table with:

```bash
/home/datalab/spark/bin/pyspark --packages io.delta:delta-spark_2.12:3.2.0
```

then `spark.read.format("delta").load("~/delta_tables/customers").show()`.
