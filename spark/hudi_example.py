from pathlib import Path
from pyspark.sql import SparkSession

HUDI_BASE_PATH = str(Path.home() / "hudi_tables" / "users")

spark = (
    SparkSession.builder.appName("data-lab-hudi-demo")
    .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
    .config("spark.sql.hive.convertMetastoreParquet", "false")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

records = spark.createDataFrame(
    [
        (1, "Alice", "2025-11-12"),
        (2, "Bob", "2025-11-12"),
        (3, "Charlie", "2025-11-12"),
    ],
    ["id", "name", "ts"],
)

(
    records.write.format("hudi")
    .option("hoodie.table.name", "users_hudi")
    .option("hoodie.datasource.write.recordkey.field", "id")
    .option("hoodie.datasource.write.precombine.field", "ts")
    .option("hoodie.datasource.write.operation", "upsert")
    .mode("overwrite")
    .save(HUDI_BASE_PATH)
)

df = spark.read.format("hudi").load(HUDI_BASE_PATH)
df.show()

spark.stop()
