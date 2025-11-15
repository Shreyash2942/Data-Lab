import os
from pathlib import Path
from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession

RUNTIME_ROOT = Path(os.environ.get("RUNTIME_ROOT", Path.home() / "runtime"))
DELTA_PATH = str(RUNTIME_ROOT / "lakehouse" / "delta_tables" / "customers")

builder = (
    SparkSession.builder.appName("data-lab-delta-demo")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
)

spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sparkContext.setLogLevel("WARN")

data = spark.createDataFrame(
    [
        (1, "Notebook", 999.0),
        (2, "Keyboard", 79.5),
        (3, "Mouse", 25.0),
    ],
    ["id", "item", "price"],
)

data.write.format("delta").mode("overwrite").save(DELTA_PATH)

spark.read.format("delta").load(DELTA_PATH).show()

spark.stop()
