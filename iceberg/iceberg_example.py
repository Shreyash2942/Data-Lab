import os
from pathlib import Path
from pyspark.sql import SparkSession

RUNTIME_ROOT = Path(os.environ.get("RUNTIME_ROOT", Path.home() / "runtime"))
WAREHOUSE = str(RUNTIME_ROOT / "lakehouse" / "iceberg_warehouse")

spark = (
    SparkSession.builder.appName("data-lab-iceberg-demo")
    .config(
        "spark.sql.extensions",
        "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    )
    .config("spark.sql.catalog.demo", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.demo.type", "hadoop")
    .config("spark.sql.catalog.demo.warehouse", WAREHOUSE)
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

spark.sql("CREATE NAMESPACE IF NOT EXISTS demo.db")
spark.sql(
    """
    CREATE TABLE IF NOT EXISTS demo.db.sales (
        id INT,
        amount DOUBLE,
        day STRING
    ) USING iceberg
    """
)

spark.sql(
    "INSERT OVERWRITE demo.db.sales VALUES (1, 19.99, '2025-11-11'), (2, 29.5, '2025-11-12')"
)

spark.sql("SELECT * FROM demo.db.sales").show()

spark.stop()
