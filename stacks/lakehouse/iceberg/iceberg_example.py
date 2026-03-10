import os
from pathlib import Path
from typing import List
from pyspark.sql import SparkSession

RUNTIME_ROOT = Path(os.environ.get("RUNTIME_ROOT", Path.home() / "runtime"))
WAREHOUSE = RUNTIME_ROOT / "lakehouse" / "iceberg_warehouse"


def log(msg: str) -> None:
    print(f"[*] {msg}")


def build_spark() -> SparkSession:
    return (
        SparkSession.builder.appName("data-lab-iceberg-demo")
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config("spark.sql.catalog.demo", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.demo.type", "hadoop")
        .config("spark.sql.catalog.demo.warehouse", str(WAREHOUSE))
        .getOrCreate()
    )


def snapshot_ids(spark: SparkSession) -> List[int]:
    rows = spark.sql("SELECT snapshot_id FROM demo.db.sales.history ORDER BY made_current_at").collect()
    return [int(row.snapshot_id) for row in rows]


def main():
    spark = build_spark()
    spark.sparkContext.setLogLevel("WARN")
    WAREHOUSE.mkdir(parents=True, exist_ok=True)

    log("Preparing Iceberg catalog and table...")
    spark.sql("CREATE NAMESPACE IF NOT EXISTS demo.db")
    spark.sql("DROP TABLE IF EXISTS demo.db.sales")
    spark.sql(
        """
        CREATE TABLE demo.db.sales (
            id INT,
            amount DOUBLE,
            day STRING
        ) USING iceberg
        """
    )

    log("Writing baseline sales rows...")
    spark.sql(
        """
        INSERT INTO demo.db.sales VALUES
          (1, 19.99, '2025-11-11'),
          (2, 29.50, '2025-11-12')
        """
    )
    spark.sql("SELECT * FROM demo.db.sales ORDER BY id").show()

    log("MERGE INTO sales (update id=2, add id=3)...")
    spark.sql(
        """
        MERGE INTO demo.db.sales AS target
        USING (
          SELECT 2 AS id, 34.75 AS amount, '2025-11-13' AS day UNION ALL
          SELECT 3 AS id, 48.10 AS amount, '2025-11-13' AS day
        ) AS source
        ON target.id = source.id
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )
    spark.sql("SELECT * FROM demo.db.sales ORDER BY id").show()

    log("History table snapshot IDs:")
    snaps = snapshot_ids(spark)
    spark.sql("SELECT snapshot_id, made_current_at FROM demo.db.sales.history").show()

    if snaps:
        first_snapshot = snaps[0]
        log(f"Time traveling to snapshot {first_snapshot} (before MERGE)...")
        spark.sql(f"SELECT * FROM demo.db.sales VERSION AS OF {first_snapshot} ORDER BY id").show()

    spark.stop()
    log(f"Iceberg warehouse located at: {WAREHOUSE}")


if __name__ == "__main__":
    main()
